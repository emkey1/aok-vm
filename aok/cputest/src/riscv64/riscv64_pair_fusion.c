// Fused pairs on the riscv64 JIT (jit/guest-riscv64/frag.h, pairs.h; the
// "fuse2" bit of /proc/ish/riscv64_jit_fuse): two guest instructions that
// follow each other run as one gadget. The arm64 guest's
// tests/manual/arm64/pair_fusion.c, for this guest. What must not change:
//
//   - the values, when the second instruction uses what the first wrote;
//   - a fault in the SECOND: the first's result is already in its register
//     (or in memory), and the fault is reported at the second's address;
//   - a fault in the FIRST: the second has not run, and after the handler
//     repairs the page both do;
//   - a branch as the second half goes the right way on what the first wrote.
//
// Each case is `mulhu; first; second; mulhu`: pairing is greedy, left to
// right, and mulhu's gadget is not in the pair table (a nop is: it is an
// addi), so the two in the middle are the pair. The fault cases resume by
// returning from the handler after mprotect, which restarts the faulting
// instruction in a block of its own.
//
// Nothing here is specific to the emulator. Run it with `echo fuse2=0 >
// /proc/ish/riscv64_jit_fuse` as well.
#define _GNU_SOURCE
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <ucontext.h>
#include <unistd.h>

#if defined(__riscv) && __riscv_xlen == 64

#define PG 4096
#define SEP "mulhu t1, t1, t1\n"

// ---- values ----------------------------------------------------------------

struct st { uint64_t a, b, c, mem[4]; };

// t3 = a, t4 = b, t5 = c, t6 = &mem
#define VCASE(name, insns) \
    __attribute__((noinline)) static void name(struct st *s) { \
        __asm__ volatile("ld t3, 0(%0)\n ld t4, 8(%0)\n ld t5, 16(%0)\n addi t6, %0, 24\n" \
                         SEP insns "\n" SEP \
                         "sd t3, 0(%0)\n sd t4, 8(%0)\n sd t5, 16(%0)" \
                         :: "r"(s) : "t1", "t3", "t4", "t5", "t6", "memory"); \
    }

VCASE(v_add_add,   "add t4, t3, t3\n add t5, t4, t3")
VCASE(v_addw_add,  "addiw t4, t3, 1\n add t5, t4, t4")
VCASE(v_sll_srl,   "slli t4, t3, 8\n srli t5, t4, 4")
VCASE(v_li_add,    "li t4, 0x1234\n add t5, t4, t3")
VCASE(v_ld_add,    "ld t4, 0(t6)\n add t5, t4, t3")
VCASE(v_ld_addi,   "ld t4, 8(t6)\n addi t5, t4, 7")
VCASE(v_add_ld,    "add t4, t6, t3\n ld t5, 0(t4)")
VCASE(v_ld_ld_dep, "ld t4, 24(t6)\n ld t5, 0(t4)")
VCASE(v_lbu_lbu,   "lbu t4, 0(t6)\n lbu t5, 9(t6)")
VCASE(v_lw_addw,   "lw t4, 4(t6)\n addiw t5, t4, 1")
VCASE(v_addi_sd,   "addi t4, t3, 9\n sd t4, 16(t6)")
VCASE(v_addw_sw,   "addiw t4, t3, 1\n sw t4, 16(t6)")
VCASE(v_ld_sd,     "ld t4, 0(t6)\n sd t4, 16(t6)")
VCASE(v_sd_ld,     "sd t3, 16(t6)\n ld t5, 16(t6)")
VCASE(v_sd_li,     "sd t3, 16(t6)\n li t5, 77")
VCASE(v_sb_sb,     "sb t3, 16(t6)\n sb t3, 18(t6)")
VCASE(v_add_beq,   "sub t4, t3, t3\n beq t4, zero, 1f\n li t5, 111\n j 2f\n 1: li t5, 222\n 2:")
VCASE(v_ld_bne,    "ld t4, 16(t6)\n bne t4, zero, 1f\n li t5, 111\n j 2f\n 1: li t5, 222\n 2:")
VCASE(v_addi_bgeu, "addi t4, t3, 1\n bgeu t4, t3, 1f\n li t5, 111\n j 2f\n 1: li t5, 222\n 2:")
VCASE(v_lbu_beq,   "lbu t4, 1(t6)\n beq t4, t3, 1f\n li t5, 111\n j 2f\n 1: li t5, 222\n 2:")
VCASE(v_add_j,     "add t4, t3, t3\n j 1f\n li t4, 0\n 1: addi t5, t4, 1")
// the first half's result as the second's SECOND operand, a store's base, a
// branch's right side
VCASE(v_add_sub_m, "add t4, t3, t3\n sub t5, t3, t4")
VCASE(v_ld_sub_m,  "ld t4, 0(t6)\n sub t5, t3, t4")
VCASE(v_addi_sd_b, "addi t4, t6, 8\n sd t3, 8(t4)")
VCASE(v_addi_bltu, "addi t4, t3, 1\n bltu t3, t4, 1f\n li t5, 111\n j 2f\n 1: li t5, 222\n 2:")
VCASE(v_ld_beq_m,  "ld t4, 8(t6)\n beq t3, t4, 1f\n li t5, 111\n j 2f\n 1: li t5, 222\n 2:")
VCASE(v_loop,      "li t5, 0\n 1: addi t5, t5, 3\n addiw t3, t3, -1\n bnez t3, 1b")

// A call and its return, as the compiler writes them.
__attribute__((noinline)) static uint64_t callee(volatile uint64_t *x) {
    return *x + 40;
}

static const struct { const char *name; void (*fn)(struct st *); struct st in, out; } vcases[] = {
#define M {0x10, 0x20, 0, 0}
#define W {0x1122334455667788, 0x99aabbccddeeff00, 0, 0}
    {"add;add",   v_add_add,   {5, 0, 0, M}, {5, 10, 15, M}},
    {"addiw;add", v_addw_add,  {0x7fffffff, 0, 0, M}, {0x7fffffff, 0xffffffff80000000, 0xffffffff00000000, M}},
    {"slli;srli", v_sll_srl,   {0xf0000000000000ff, 0, 0, M}, {0xf0000000000000ff, 0xff00, 0xff0, M}},
    {"li;add",    v_li_add,    {1, 0, 0, M}, {1, 0x1234, 0x1235, M}},
    {"ld;add",    v_ld_add,    {1, 0, 0, M}, {1, 0x10, 0x11, M}},
    {"ld;addi",   v_ld_addi,   {0, 0, 0, M}, {0, 0x20, 0x27, M}},
    {"add;ld",    v_add_ld,    {8, 0, 0, M}, {8, 0 /* an address */, 0x20, M}},
    {"lbu;lbu",   v_lbu_lbu,   {0, 0, 0, W}, {0, 0x88, 0xff, W}},
    {"lw;addiw",  v_lw_addw,   {0, 0, 0, W}, {0, 0x11223344, 0x11223345, W}},
    {"addi;sd",   v_addi_sd,   {1, 0, 0, M}, {1, 10, 0, {0x10, 0x20, 10, 0}}},
    {"addiw;sw",  v_addw_sw,   {0x7fffffff, 0, 0, M}, {0x7fffffff, 0xffffffff80000000, 0, {0x10, 0x20, 0x80000000, 0}}},
    {"ld;sd",     v_ld_sd,     {0, 0, 0, M}, {0, 0x10, 0, {0x10, 0x20, 0x10, 0}}},
    {"sd;ld",     v_sd_ld,     {9, 0, 0, M}, {9, 0, 9, {0x10, 0x20, 9, 0}}},
    {"sd;li",     v_sd_li,     {9, 0, 0, M}, {9, 0, 77, {0x10, 0x20, 9, 0}}},
    {"sb;sb",     v_sb_sb,     {0xab, 0, 0, M}, {0xab, 0, 0, {0x10, 0x20, 0xab00ab, 0}}},
    {"sub;beq",   v_add_beq,   {5, 1, 0, M}, {5, 0, 222, M}},
    {"ld;bne",    v_ld_bne,    {0, 1, 0, M}, {0, 0, 111, M}},
    {"addi;bgeu", v_addi_bgeu, {~0ull, 0, 0, M}, {~0ull, 0, 111, M}},
    {"lbu;beq",   v_lbu_beq,   {0x77, 0, 0, W}, {0x77, 0x77, 222, W}},
    {"add;j",     v_add_j,     {2, 0, 0, M}, {2, 4, 5, M}},
    {"loop",      v_loop,      {5, 6, 0, M}, {0, 6, 15, M}},
    {"add;sub m", v_add_sub_m, {5, 0, 0, M}, {5, 10, (uint64_t) -5, M}},
    {"ld;sub m",  v_ld_sub_m,  {0x64, 0, 0, M}, {0x64, 0x10, 0x54, M}},
    {"addi;bltu m", v_addi_bltu, {7, 0, 0, M}, {7, 8, 222, M}},
    {"ld;beq m",  v_ld_beq_m,  {0x20, 0, 0, M}, {0x20, 0x20, 222, M}},
#undef M
#undef W
};

static int values(void) {
    int failures = 0;
    for (unsigned i = 0; i < sizeof(vcases) / sizeof(vcases[0]); i++) {
        struct st s, want = vcases[i].out;
        if (vcases[i].fn == v_add_ld)
            want.b = (uint64_t) &s.mem[1];
        // twice: the second pass runs the translated block again, chained
        for (int pass = 0; pass < 2; pass++) {
            s = vcases[i].in;
            vcases[i].fn(&s);
            if (memcmp(&s, &want, sizeof(s)) != 0) {
                printf("riscv64_pair_fusion: %s (pass %d): got a=%#llx b=%#llx c=%#llx mem=%#llx,%#llx,%#llx; "
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
    {   // a store through the first half's result
        struct st s = {0x77, 0, 0, {0x10, 0x20, 0, 0}};
        v_addi_sd_b(&s);
        if (s.b != (uint64_t) &s.mem[1] || s.mem[2] != 0x77 || s.mem[1] != 0x20) {
            printf("riscv64_pair_fusion: addi;sd base: b=%#llx mem=%#llx,%#llx\n", (unsigned long long) s.b,
                   (unsigned long long) s.mem[1], (unsigned long long) s.mem[2]);
            failures++;
        }
    }
    {   // the dependent load: mem[3] holds a pointer to mem[1]
        struct st s = {0, 0, 0, {0x10, 0x20, 0, 0}};
        s.mem[3] = (uint64_t) &s.mem[1];
        v_ld_ld_dep(&s);
        if (s.b != (uint64_t) &s.mem[1] || s.c != 0x20) {
            printf("riscv64_pair_fusion: ld;ld dependent: b=%#llx c=%#llx\n", (unsigned long long) s.b,
                   (unsigned long long) s.c);
            failures++;
        }
    }
    for (volatile uint64_t x = 0; x < 3; x++)
        if (callee(&x) != x + 40) {
            printf("riscv64_pair_fusion: call/return at %llu\n", (unsigned long long) x);
            failures++;
        }
    return failures;
}

// ---- faults ----------------------------------------------------------------

static struct {
    volatile int count;
    volatile uint64_t pc, addr, t3, t4;
    void *volatile page;       // made accessible before returning
    volatile uint64_t peek;    // *peek_at at the fault (0 if peek_at is NULL)
    uint64_t *volatile peek_at;
} seen;

static void on_segv(int sig, siginfo_t *si, void *ctx) {
    (void) sig;
    ucontext_t *uc = ctx;
    seen.count++;
    seen.pc = uc->uc_mcontext.__gregs[0];    // REG_PC
    seen.addr = (uint64_t) si->si_addr;
    seen.t3 = uc->uc_mcontext.__gregs[28];
    seen.t4 = uc->uc_mcontext.__gregs[29];
    seen.peek = seen.peek_at != NULL ? *seen.peek_at : 0;
    if (seen.count > 4 || mprotect(seen.page, PG, PROT_READ | PROT_WRITE) != 0)
        _exit(3);
}

// a6 = good page, a7 = the page that faults; t3 and t4 start as sentinels.
#define FCASE(name, insns_a, insns_b) \
    extern char name##_a[], name##_b[]; \
    __attribute__((noinline)) static void name(uint64_t *good, uint64_t *bad, uint64_t out[2]) { \
        __asm__ volatile("mv a6, %0\n mv a7, %1\n li t3, 0x333\n li t4, 0x262\n" SEP \
                         ".globl " #name "_a\n" #name "_a: " insns_a "\n" \
                         ".globl " #name "_b\n" #name "_b: " insns_b "\n" \
                         SEP "sd t3, 0(%2)\n sd t4, 8(%2)" \
                         :: "r"(good), "r"(bad), "r"(out) : "t1", "t3", "t4", "a6", "a7", "memory"); \
    }

// second faults
FCASE(f_addi_ld,  "addi t4, a6, 8",     "ld t3, 0(a7)")
FCASE(f_ld_ld,    "ld t4, 0(a6)",       "ld t3, 8(a7)")
FCASE(f_sd_sd,    "sd t3, 16(a6)",      "sd t4, 0(a7)")
FCASE(f_addi_sd,  "addi t4, t4, 1",     "sd t4, 8(a7)")
FCASE(f_srli_ld,  "srli t4, t4, 1",     "ld t3, 0(a7)")
// first faults
FCASE(g_ld_addi,  "ld t4, 0(a7)",       "addi t3, t4, 1")
FCASE(g_sd_addi,  "sd t4, 0(a7)",       "addi t3, t3, 1")
FCASE(g_ld_ld,    "ld t4, 0(a7)",       "ld t3, 0(a6)")
FCASE(g_ld_sd,    "ld t4, 0(a7)",       "sd t4, 16(a6)")
FCASE(g_ld_beq,   "ld t4, 16(a7)",      "beqz t4, 1f\n li t3, 111\n j 2f\n 1: li t3, 222\n 2:")

static int fault_case(const char *name, void (*fn)(uint64_t *, uint64_t *, uint64_t *), char *at,
        uint64_t *good, uint64_t *bad, uint64_t addr_off, uint64_t *peek_at,
        uint64_t want_t3, uint64_t want_t4, uint64_t want_peek, uint64_t out3, uint64_t out4) {
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
        seen.addr != (uint64_t) bad + addr_off || seen.t3 != want_t3 || seen.t4 != want_t4 ||
        seen.peek != want_peek || out[0] != out3 || out[1] != out4;
    if (bad_result)
        printf("riscv64_pair_fusion: fault %s: %d fault(s) at pc %#llx (want %p) addr %#llx (want %#llx), "
               "t3=%#llx (want %#llx) t4=%#llx (want %#llx) mem=%#llx (want %#llx); "
               "after: t3=%#llx (want %#llx) t4=%#llx (want %#llx)\n", name, seen.count,
               (unsigned long long) seen.pc, (void *) at, (unsigned long long) seen.addr,
               (unsigned long long) ((uint64_t) bad + addr_off),
               (unsigned long long) seen.t3, (unsigned long long) want_t3,
               (unsigned long long) seen.t4, (unsigned long long) want_t4,
               (unsigned long long) seen.peek, (unsigned long long) want_peek,
               (unsigned long long) out[0], (unsigned long long) out3,
               (unsigned long long) out[1], (unsigned long long) out4);
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
        failures += fault_case("addi;LD", f_addi_ld, f_addi_ld_b, good, bad, 0, NULL, 0x333, g + 8, 0, 0xb0, g + 8);
        failures += fault_case("ld;LD", f_ld_ld, f_ld_ld_b, good, bad, 8, NULL, 0x333, 0xa0, 0, 0xb1, 0xa0);
        failures += fault_case("sd;SD", f_sd_sd, f_sd_sd_b, good, bad, 0, &good[2], 0x333, 0x262, 0x333, 0x333, 0x262);
        failures += fault_case("addi;SD", f_addi_sd, f_addi_sd_b, good, bad, 8, NULL, 0x333, 0x263, 0, 0x333, 0x263);
        failures += fault_case("srli;LD", f_srli_ld, f_srli_ld_b, good, bad, 0, NULL, 0x333, 0x131, 0, 0xb0, 0x131);
        // The first faults: the second has not run.
        failures += fault_case("LD;addi", g_ld_addi, g_ld_addi_a, good, bad, 0, NULL, 0x333, 0x262, 0, 0xb1, 0xb0);
        failures += fault_case("SD;addi", g_sd_addi, g_sd_addi_a, good, bad, 0, NULL, 0x333, 0x262, 0, 0x334, 0x262);
        failures += fault_case("LD;ld", g_ld_ld, g_ld_ld_a, good, bad, 0, NULL, 0x333, 0x262, 0, 0xa0, 0xb0);
        failures += fault_case("LD;sd", g_ld_sd, g_ld_sd_a, good, bad, 0, &good[2], 0x333, 0x262, 0, 0x333, 0xb0);
        failures += fault_case("LD;beqz", g_ld_beq, g_ld_beq_a, good, bad, 16, NULL, 0x333, 0x262, 0, 222, 0);
    }
    munmap(good, 2 * PG);
    return failures;
}

int main(void) {
    int failures = values() + faults();
    if (failures != 0) {
        printf("riscv64_pair_fusion: FAIL failures=%d\n", failures);
        return 1;
    }
    printf("riscv64_pair_fusion: PASS\n");
    return 0;
}

#else

int main(void) {
    printf("riscv64_pair_fusion: PASS\n");
    return 0;
}

#endif
