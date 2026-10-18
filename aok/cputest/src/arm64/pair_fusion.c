// Fused pairs on the arm64 JIT (jit/guest-arm64/frag.h, pairs.h; the "pair"
// bit of /proc/ish/arm64_jit_fuse): two guest instructions that follow each
// other run as one gadget. What that must not change:
//
//   - the values, when the second instruction uses what the first wrote;
//   - a fault in the SECOND: the first's result is already in its register
//     (or in memory), and the fault is reported at the second's address;
//   - a fault in the FIRST: the second has not run, and after the handler
//     repairs the page both do;
//   - a branch as the second half goes the right way on what the first wrote.
//
// Each case is `nop; first; second; nop`: pairing is greedy, left to right,
// and a nop is not in the pair table, so the two in the middle are the pair.
// The fault cases resume by returning from the handler after mprotect, which
// restarts the faulting instruction in a block of its own.
//
// Nothing here is specific to the emulator: on real hardware it passes
// trivially. Run it with `echo pair=0 > /proc/ish/arm64_jit_fuse` as well.
#define _GNU_SOURCE
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <ucontext.h>

#include "../test_common.h"

#if defined(__aarch64__)

#define PG 4096

// ---- values ----------------------------------------------------------------

struct st { uint64_t a, b, c, mem[4]; };

#define VCASE(name, insns) \
    __attribute__((noinline)) static void name(struct st *s) { \
        __asm__ volatile("ldr x17, [%0]\n ldr x26, [%0, #8]\n ldr x3, [%0, #16]\n add x5, %0, #24\n" \
                         "nop\n" insns "\n nop\n" \
                         "str x17, [%0]\n str x26, [%0, #8]\n str x3, [%0, #16]" \
                         :: "r"(s) : "x3", "x5", "x9", "x17", "x26", "cc", "memory"); \
    }

VCASE(v_alu_alu,     "add x26, x17, #5\n sub x3, x26, #2")
VCASE(v_alu_alu32,   "add w26, w17, #5\n eor w3, w26, w17")
VCASE(v_mov_mov,     "mov x26, x17\n mov x3, x26")
VCASE(v_movw_alu,    "mov w26, w17\n add x3, x26, #1")
VCASE(v_const_alu,   "mov x26, #0x1234\n add x3, x26, x17")
VCASE(v_bfx_alu,     "ubfx x26, x17, #8, #12\n add x3, x26, #1")
VCASE(v_lsl_bfx,     "lsl w26, w17, #3\n lsr w3, w26, #1")
VCASE(v_asr_alu,     "asr x26, x17, #4\n sub x3, x26, #1")
VCASE(v_sxtw_alu,    "sxtw x26, w17\n add x3, x26, x26")
VCASE(v_ld_alu,      "ldr x26, [x5]\n add x3, x26, #7")
VCASE(v_alu_ld,      "add x26, x5, #8\n ldr x3, [x26]")
VCASE(v_ld_ld,       "ldr x26, [x5]\n ldr x3, [x5, #8]")
VCASE(v_ld_ld_dep,   "ldr x26, [x5, #24]\n ldr x3, [x26]")
VCASE(v_ld32_ld8,    "ldr w26, [x5, #4]\n ldrb w3, [x5, #9]")
VCASE(v_alu_st,      "add x26, x17, #9\n str x26, [x5, #16]")
VCASE(v_st_st,       "str x17, [x5]\n str x26, [x5, #8]")
VCASE(v_st_ld,       "str x17, [x5, #16]\n ldr x3, [x5, #16]")
VCASE(v_ld_st,       "ldr x26, [x5]\n str x26, [x5, #16]")
VCASE(v_ldx_alu,     "mov x9, #1\n nop\n ldr x26, [x5, x9, lsl #3]\n add x3, x26, #1")
VCASE(v_alu_ldx,     "mov x9, #2\n nop\n lsl x26, x9, #0\n ldr x3, [x5, x26, lsl #3]")
VCASE(v_ldp_alu,     "ldp x26, x3, [x5]\n add x3, x3, x26")
VCASE(v_alu_stp,     "add x26, x17, #1\n stp x26, x17, [x5, #8]")
VCASE(v_subs_alu,    "subs x26, x17, #1\n add x3, x26, #1")
VCASE(v_alu_cbz,     "sub x26, x17, x17\n cbz x26, 1f\n mov x3, #111\n b 2f\n 1: mov x3, #222\n 2:")
VCASE(v_alu_cbnz,    "add w26, w17, #1\n cbnz w26, 1f\n mov x3, #111\n b 2f\n 1: mov x3, #222\n 2:")
VCASE(v_ld_cbz,      "ldr x26, [x5, #16]\n cbz x26, 1f\n mov x3, #111\n b 2f\n 1: mov x3, #222\n 2:")
VCASE(v_alu_tbz,     "add x26, x17, #4\n tbz x26, #2, 1f\n mov x3, #111\n b 2f\n 1: mov x3, #222\n 2:")
VCASE(v_alu_cmp_b,   "add x26, x17, #1\n cmp x26, x17\n b.hi 1f\n mov x3, #111\n b 2f\n 1: mov x3, #222\n 2:")
VCASE(v_ld_cmpi_b,   "ldr w26, [x5]\n cmp w26, #0x10\n b.eq 1f\n mov x3, #111\n b 2f\n 1: mov x3, #222\n 2:")
VCASE(v_alu_b,       "add x26, x17, #3\n b 1f\n mov x26, #0\n 1: add x3, x26, #1")
// the second half's SECOND operand is the first half's result, and the other
// places a result can go: a store's base, a load's index, a compare's right
// side, a 32-bit move, an indirect branch
VCASE(v_alu_alu_m,   "add x26, x17, #5\n sub x3, x17, x26")
VCASE(v_ld_alu_m,    "ldr x26, [x5]\n sub x3, x17, x26")
VCASE(v_alu_st_base, "add x26, x5, #8\n str x17, [x26, #8]")
VCASE(v_ld_st_base,  "ldr x26, [x5, #24]\n str x17, [x26]")
VCASE(v_ld_ldx_idx,  "ldr x26, [x5, #16]\n ldr x3, [x5, x26, lsl #3]")
VCASE(v_alu_cmp_m,   "add x26, x17, #1\n cmp x17, x26\n b.lo 1f\n mov x3, #111\n b 2f\n 1: mov x3, #222\n 2:")
VCASE(v_alu_movw,    "add x26, x17, #1\n mov w3, w26")
VCASE(v_ld_movx,     "ldr x26, [x5, #8]\n mov x3, x26")
VCASE(v_alu_lsl,     "add x26, x17, #1\n lsl x3, x26, #4")
VCASE(v_alu_addlsl,  "add x26, x17, #1\n add x3, x17, x26, lsl #2")
VCASE(v_ld_stp_base, "ldr x26, [x5, #24]\n stp x17, x17, [x26]")
VCASE(v_ld_br,       "adr x9, 1f\n str x9, [x5, #16]\n nop\n ldr x26, [x5, #16]\n br x26\n mov x3, #111\n 1: add x3, x3, #7")
VCASE(v_subs_bcond,  "subs x26, x17, x17\n nop\n add x3, x26, #5\n b.eq 1f\n mov x3, #111\n 1:")

// A call and its return: `mov; bl` going in, `ldp post; ret` coming back.
__attribute__((noinline)) static uint64_t callee(uint64_t x) {
    uint64_t r;
    __asm__ volatile("stp x29, x30, [sp, #-16]!\n mov x29, sp\n add %0, %1, #40\n ldp x29, x30, [sp], #16"
                     : "=&r"(r) : "r"(x) : "memory");
    return r;
}

static const struct { const char *name; void (*fn)(struct st *); struct st in, out; } vcases[] = {
#define M {0x10, 0x20, 0, 0}
    {"alu;alu",   v_alu_alu,   {100, 0, 0, M}, {100, 105, 103, M}},
    {"alu;alu32", v_alu_alu32, {0xffffffff00000003, 0, 0, M}, {0xffffffff00000003, 8, 11, M}},
    {"mov;mov",   v_mov_mov,   {77, 0, 0, M}, {77, 77, 77, M}},
    {"movw;alu",  v_movw_alu,  {0xaaaaaaaa55555555, 0, 0, M}, {0xaaaaaaaa55555555, 0x55555555, 0x55555556, M}},
    {"const;alu", v_const_alu, {1, 0, 0, M}, {1, 0x1234, 0x1235, M}},
    {"ubfx;alu",  v_bfx_alu,   {0xabcdef12, 0, 0, M}, {0xabcdef12, 0xdef, 0xdf0, M}},
    {"lsl;lsr",   v_lsl_bfx,   {0xf0000001, 0, 0, M}, {0xf0000001, 0x80000008, 0x40000004, M}},
    {"asr;alu",   v_asr_alu,   {0x8000000000000100, 0, 0, M}, {0x8000000000000100, 0xf800000000000010, 0xf80000000000000f, M}},
    {"sxtw;alu",  v_sxtw_alu,  {0x80000000, 0, 0, M}, {0x80000000, 0xffffffff80000000, 0xffffffff00000000, M}},
    {"ld;alu",    v_ld_alu,    {0, 0, 0, M}, {0, 0x10, 0x17, M}},
    {"alu;ld",    v_alu_ld,    {0, 0, 0, M}, {0, 0 /* an address */, 0x20, M}},
    {"ld;ld",     v_ld_ld,     {0, 0, 0, M}, {0, 0x10, 0x20, M}},
    {"ld32;ld8",  v_ld32_ld8,  {0, 0, 0, {0x1122334455667788, 0x99aabbccddeeff00, 0, 0}},
                               {0, 0x11223344, 0xff, {0x1122334455667788, 0x99aabbccddeeff00, 0, 0}}},
    {"alu;st",    v_alu_st,    {1, 0, 0, M}, {1, 10, 0, {0x10, 0x20, 10, 0}}},
    {"st;st",     v_st_st,     {5, 6, 0, M}, {5, 6, 0, {5, 6, 0, 0}}},
    {"st;ld",     v_st_ld,     {9, 0, 0, M}, {9, 0, 9, {0x10, 0x20, 9, 0}}},
    {"ld;st",     v_ld_st,     {0, 0, 0, M}, {0, 0x10, 0, {0x10, 0x20, 0x10, 0}}},
    {"ldx;alu",   v_ldx_alu,   {0, 0, 0, M}, {0, 0x20, 0x21, M}},
    {"alu;ldx",   v_alu_ldx,   {0, 0, 0, {0x10, 0x20, 0x30, 0}}, {0, 2, 0x30, {0x10, 0x20, 0x30, 0}}},
    {"ldp;alu",   v_ldp_alu,   {0, 0, 0, M}, {0, 0x10, 0x30, M}},
    {"alu;stp",   v_alu_stp,   {7, 0, 0, M}, {7, 8, 0, {0x10, 8, 7, 0}}},
    {"subs;alu",  v_subs_alu,  {1, 0, 0, M}, {1, 0, 1, M}},
    {"alu;cbz",   v_alu_cbz,   {5, 1, 0, M}, {5, 0, 222, M}},
    {"alu;cbnz",  v_alu_cbnz,  {0xffffffff, 1, 0, M}, {0xffffffff, 0, 111, M}},
    {"ld;cbz",    v_ld_cbz,    {0, 1, 0, M}, {0, 0, 222, M}},
    {"alu;tbz",   v_alu_tbz,   {0, 0, 0, M}, {0, 4, 111, M}},
    {"alu;cmp+b", v_alu_cmp_b, {9, 0, 0, M}, {9, 10, 222, M}},
    {"ld;cmpi+b", v_ld_cmpi_b, {0, 0, 0, M}, {0, 0x10, 222, M}},
    {"alu;b",     v_alu_b,     {1, 0, 0, M}, {1, 4, 5, M}},
    {"subs;b.eq", v_subs_bcond, {3, 1, 0, M}, {3, 0, 5, M}},
    {"alu;alu m", v_alu_alu_m, {100, 0, 0, M}, {100, 105, (uint64_t) -5, M}},
    {"ld;alu m",  v_ld_alu_m,  {100, 0, 0, M}, {100, 0x10, 0x54, M}},
    {"alu;cmp m", v_alu_cmp_m, {9, 0, 0, M}, {9, 10, 222, M}},
    {"alu;mov w", v_alu_movw,  {0xfffffffff, 0, 0, M}, {0xfffffffff, 0x1000000000, 0, M}},
    {"ld;mov x",  v_ld_movx,   {0, 0, 0, M}, {0, 0x20, 0x20, M}},
    {"alu;lsl",   v_alu_lsl,   {0xf, 0, 0, M}, {0xf, 0x10, 0x100, M}},
    {"alu;add lsl", v_alu_addlsl, {3, 0, 0, M}, {3, 4, 19, M}},
#undef M
};

static int values(void) {
    int failures = 0;
    for (unsigned i = 0; i < sizeof(vcases) / sizeof(vcases[0]); i++) {
        struct st s = vcases[i].in, want = vcases[i].out;
        if (vcases[i].fn == v_alu_ld)
            want.b = (uint64_t) &s.mem[1];
        // twice: the second pass runs the translated block again, chained
        for (int pass = 0; pass < 2; pass++) {
            s = vcases[i].in;
            vcases[i].fn(&s);
            if (memcmp(&s, &want, sizeof(s)) != 0) {
                printf("pair_fusion: %s (pass %d): got a=%#llx b=%#llx c=%#llx mem=%#llx,%#llx,%#llx; "
                       "want a=%#llx b=%#llx c=%#llx mem=%#llx,%#llx,%#llx\n", vcases[i].name, pass,
                       (unsigned long long) s.a, (unsigned long long) s.b, (unsigned long long) s.c,
                       (unsigned long long) s.mem[0], (unsigned long long) s.mem[1], (unsigned long long) s.mem[2],
                       (unsigned long long) want.a, (unsigned long long) want.b, (unsigned long long) want.c,
                       (unsigned long long) want.mem[0], (unsigned long long) want.mem[1],
                       (unsigned long long) want.mem[2]);
                failures++;
                break;
            }
        }
    }
    {   // results that are addresses: a store through the first half's result
        struct st s = {0x77, 0, 0, {0x10, 0x20, 0, 0}};
        v_alu_st_base(&s);
        if (s.b != (uint64_t) &s.mem[1] || s.mem[2] != 0x77 || s.mem[1] != 0x20) {
            printf("pair_fusion: alu;st base: b=%#llx mem=%#llx,%#llx\n", (unsigned long long) s.b,
                   (unsigned long long) s.mem[1], (unsigned long long) s.mem[2]);
            failures++;
        }
        struct st t = {0x55, 0, 0, {0x10, 0x20, 0, 0}};
        t.mem[3] = (uint64_t) &t.mem[1];
        v_ld_st_base(&t);
        if (t.b != (uint64_t) &t.mem[1] || t.mem[1] != 0x55) {
            printf("pair_fusion: ld;st base: b=%#llx mem1=%#llx\n", (unsigned long long) t.b, (unsigned long long) t.mem[1]);
            failures++;
        }
        struct st u = {0x66, 0, 0, {0x10, 0x20, 0, 0}};
        u.mem[3] = (uint64_t) &u.mem[0];
        v_ld_stp_base(&u);
        if (u.mem[0] != 0x66 || u.mem[1] != 0x66) {
            printf("pair_fusion: ld;stp base: mem=%#llx,%#llx\n", (unsigned long long) u.mem[0], (unsigned long long) u.mem[1]);
            failures++;
        }
        struct st v = {0, 0, 0, {0x10, 0x20, 1, 0}};      // index 1 -> mem[1]
        v_ld_ldx_idx(&v);
        if (v.b != 1 || v.c != 0x20) {
            printf("pair_fusion: ld;ldr index: b=%#llx c=%#llx\n", (unsigned long long) v.b, (unsigned long long) v.c);
            failures++;
        }
        struct st w = {0, 0, 100, {0x10, 0x20, 0, 0}};    // an indirect branch through a loaded pointer
        v_ld_br(&w);
        if (w.c != 107 || w.b != w.mem[2]) {
            printf("pair_fusion: ld;br: c=%llu\n", (unsigned long long) w.c);
            failures++;
        }
    }
    {   // the dependent load: mem[3] holds a pointer to mem[1]
        struct st s = {0, 0, 0, {0x10, 0x20, 0, 0}};
        s.mem[3] = (uint64_t) &s.mem[1];
        v_ld_ld_dep(&s);
        if (s.b != (uint64_t) &s.mem[1] || s.c != 0x20) {
            printf("pair_fusion: ld;ld dependent: b=%#llx c=%#llx\n", (unsigned long long) s.b, (unsigned long long) s.c);
            failures++;
        }
    }
    for (uint64_t x = 0; x < 3; x++)
        if (callee(x) != x + 40) {
            printf("pair_fusion: call/return: callee(%llu) = %llu\n", (unsigned long long) x,
                   (unsigned long long) callee(x));
            failures++;
        }
    return failures;
}

// ---- faults ----------------------------------------------------------------

// What the handler saw at the fault, and what it is to do about it.
static struct {
    volatile int count;
    volatile uint64_t pc, addr, x3, x26;
    void *volatile page;       // made accessible before returning
    volatile uint64_t peek;    // *peek_at at the fault (0 if peek_at is NULL)
    uint64_t *volatile peek_at;
} seen;

static void on_segv(int sig, siginfo_t *si, void *ctx) {
    (void) sig;
    ucontext_t *uc = ctx;
    seen.count++;
    seen.pc = uc->uc_mcontext.pc;
    seen.addr = (uint64_t) si->si_addr;
    seen.x3 = uc->uc_mcontext.regs[3];
    seen.x26 = uc->uc_mcontext.regs[26];
    seen.peek = seen.peek_at != NULL ? *seen.peek_at : 0;
    if (seen.count > 4 || mprotect(seen.page, PG, PROT_READ | PROT_WRITE) != 0)
        _exit(3);
}

// x17 = good page, x5 = the page that faults; x3 and x26 start as sentinels.
// The labels give the two instructions' addresses.
#define FCASE(name, insns_a, insns_b) \
    extern char name##_a[], name##_b[]; \
    __attribute__((noinline)) static void name(uint64_t *good, uint64_t *bad, uint64_t out[2]) { \
        __asm__ volatile("mov x17, %0\n mov x5, %1\n mov x3, #0x333\n mov x26, #0x262\n nop\n" \
                         ".globl " #name "_a\n" #name "_a: " insns_a "\n" \
                         ".globl " #name "_b\n" #name "_b: " insns_b "\n" \
                         "nop\n str x3, [%2]\n str x26, [%2, #8]" \
                         :: "r"(good), "r"(bad), "r"(out) : "x3", "x5", "x9", "x17", "x26", "cc", "memory"); \
    }

// second faults
FCASE(f_alu_ld,   "add x26, x17, #8",    "ldr x3, [x5]")
FCASE(f_ld_ld,    "ldr x26, [x17]",      "ldr x3, [x5, #8]")
FCASE(f_st_st,    "str x3, [x17, #16]",  "str x26, [x5]")
FCASE(f_alu_st,   "add x26, x26, #1",    "str x26, [x5, #8]")
FCASE(f_bfx_ld,   "lsr x26, x26, #1",    "ldr x3, [x5]")
FCASE(f_ld_ldp,   "ldr x26, [x17]",      "ldp x3, x9, [x5]")
// first faults
FCASE(g_ld_alu,   "ldr x26, [x5]",       "add x3, x26, #1")
FCASE(g_st_alu,   "str x26, [x5]",       "add x3, x3, #1")
FCASE(g_ld_ld,    "ldr x26, [x5]",       "ldr x3, [x17]")
FCASE(g_ld_st,    "ldr x26, [x5]",       "str x26, [x17, #16]")
FCASE(g_ld_cbz,   "ldr x26, [x5, #16]",  "cbz x26, 1f\n mov x3, #111\n b 2f\n 1: mov x3, #222\n 2:")

static int fault_case(const char *name, void (*fn)(uint64_t *, uint64_t *, uint64_t *), char *at,
        uint64_t *good, uint64_t *bad, uint64_t addr_off, uint64_t *peek_at,
        uint64_t want_x3, uint64_t want_x26, uint64_t want_peek, uint64_t out3, uint64_t out26) {
    good[0] = 0xa0; good[1] = 0xa1; good[2] = 0;
    if (mprotect(bad, PG, PROT_READ | PROT_WRITE) != 0)
        return 1;
    bad[0] = 0xb0; bad[1] = 0xb1; bad[2] = 0;
    if (mprotect(bad, PG, PROT_NONE) != 0)
        return 1;
    memset(&seen, 0, sizeof(seen));
    seen.page = bad;
    seen.peek_at = peek_at;
    uint64_t out[2] = {0, 0};
    fn(good, bad, out);
    int bad_result = seen.count != 1 || seen.pc != (uint64_t) at ||
        seen.addr != (uint64_t) bad + addr_off || seen.x3 != want_x3 || seen.x26 != want_x26 ||
        seen.peek != want_peek || out[0] != out3 || out[1] != out26;
    if (bad_result)
        printf("pair_fusion: fault %s: %d fault(s) at pc %#llx (want %p) addr %#llx (want %#llx), "
               "x3=%#llx (want %#llx) x26=%#llx (want %#llx) mem=%#llx (want %#llx); "
               "after: x3=%#llx (want %#llx) x26=%#llx (want %#llx)\n", name, seen.count,
               (unsigned long long) seen.pc, (void *) at, (unsigned long long) seen.addr,
               (unsigned long long) ((uint64_t) bad + addr_off),
               (unsigned long long) seen.x3, (unsigned long long) want_x3,
               (unsigned long long) seen.x26, (unsigned long long) want_x26,
               (unsigned long long) seen.peek, (unsigned long long) want_peek,
               (unsigned long long) out[0], (unsigned long long) out3,
               (unsigned long long) out[1], (unsigned long long) out26);
    return bad_result;
}

static int faults(void) {
    uint64_t *good = mmap(NULL, 2 * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (good == MAP_FAILED)
        return 1;
    uint64_t *bad = (uint64_t *) ((char *) good + PG);
    struct sigaction sa = {.sa_sigaction = on_segv, .sa_flags = SA_SIGINFO};
    sigemptyset(&sa.sa_mask);
    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
    uint64_t g = (uint64_t) good;
    int failures = 0;
    // twice: the first pass translates, the second runs what was translated
    for (int pass = 0; pass < 2; pass++) {
        // The second faults: the first's result is there to be seen.
        failures += fault_case("alu;LD", f_alu_ld, f_alu_ld_b, good, bad, 0, NULL, 0x333, g + 8, 0, 0xb0, g + 8);
        failures += fault_case("ld;LD", f_ld_ld, f_ld_ld_b, good, bad, 8, NULL, 0x333, 0xa0, 0, 0xb1, 0xa0);
        failures += fault_case("st;ST", f_st_st, f_st_st_b, good, bad, 0, &good[2], 0x333, 0x262, 0x333, 0x333, 0x262);
        failures += fault_case("alu;ST", f_alu_st, f_alu_st_b, good, bad, 8, NULL, 0x333, 0x263, 0, 0x333, 0x263);
        failures += fault_case("lsr;LD", f_bfx_ld, f_bfx_ld_b, good, bad, 0, NULL, 0x333, 0x131, 0, 0xb0, 0x131);
        failures += fault_case("ld;LDP", f_ld_ldp, f_ld_ldp_b, good, bad, 0, NULL, 0x333, 0xa0, 0, 0xb0, 0xa0);
        // The first faults: the second has not run.
        failures += fault_case("LD;alu", g_ld_alu, g_ld_alu_a, good, bad, 0, NULL, 0x333, 0x262, 0, 0xb1, 0xb0);
        failures += fault_case("ST;alu", g_st_alu, g_st_alu_a, good, bad, 0, NULL, 0x333, 0x262, 0, 0x334, 0x262);
        failures += fault_case("LD;ld", g_ld_ld, g_ld_ld_a, good, bad, 0, NULL, 0x333, 0x262, 0, 0xa0, 0xb0);
        failures += fault_case("LD;st", g_ld_st, g_ld_st_a, good, bad, 0, &good[2], 0x333, 0x262, 0, 0x333, 0xb0);
        failures += fault_case("LD;cbz", g_ld_cbz, g_ld_cbz_a, good, bad, 16, NULL, 0x333, 0x262, 0, 222, 0);
    }
    munmap(good, 2 * PG);
    return failures;
}

int main(void) {
    int failures = values() + faults();
    if (failures != 0) {
        printf("pair_fusion: FAIL failures=%d\n", failures);
        return 1;
    }
    printf("pair_fusion: PASS\n");
    return 0;
}

#else

int main(void) {
    printf("pair_fusion: PASS\n");
    return 0;
}

#endif
