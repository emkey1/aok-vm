// simdtest [-b BUCKET]: every encoding of AArch64's "scalar floating-point and Advanced SIMD data
// processing" space, executed on a few inputs, and what each left behind hashed.
//
// For an engine that runs these instructions some other way than its reference does (the AOK gadgets
// under QEMU run them on the host's FP unit; QEMU's own engine computes them in software), the two
// transcripts must be the same: the same encodings must exist, and each must leave the same register,
// flags and FPSR. An encoding that does not exist is a SIGILL, counted and hashed as that.
//
// The space is bits 27:25 = 111. An encoding is run as "insn; ret" with Rd = 0 and Rn = 1; every other
// bit is enumerated: bits 31:28 and 24:21 name a bucket (one line of output each), bits 20:16 and 15:10
// its 2048 members. Three more passes cover the classes whose low ten bits are not two registers:
// immediates in bits 9:5 (modified immediates, fmov #imm) and compares, whose bits 4:0 are an opcode or
// flags. With -b the members of one bucket (or "imm", "fmov", "cmp") are printed one a line, to find
// which encoding a differing bucket line is about.
//
// aarch64 only. gcc -O2 -static -o simdtest simdtest.c
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <ucontext.h>

struct state {
    uint64_t v[32][2];      // 0
    uint64_t x[4];          // 512
    uint64_t nzcv, fpcr;    // 544, 552
    uint64_t fpsr;          // 560 (out)
};

// run_stub(code, in, out): load everything from *in, call code, store what it could have changed.
void run_stub(void *code, const struct state *in, struct state *out);
__asm__(
    ".text\n"
    ".globl run_stub\n"
    "run_stub:\n"
    "    stp x29, x30, [sp, #-96]!\n"
    "    stp x19, x20, [sp, #16]\n"
    "    stp d8, d9, [sp, #32]\n"
    "    stp d10, d11, [sp, #48]\n"
    "    stp d12, d13, [sp, #64]\n"
    "    stp d14, d15, [sp, #80]\n"
    "    mov x19, x2\n"
    "    mov x9, x0\n"
    "    mov x10, x1\n"
    "    ldp q0, q1, [x10]\n"
    "    ldp q2, q3, [x10, #32]\n"
    "    ldp q4, q5, [x10, #64]\n"
    "    ldp q6, q7, [x10, #96]\n"
    "    ldp q8, q9, [x10, #128]\n"
    "    ldp q10, q11, [x10, #160]\n"
    "    ldp q12, q13, [x10, #192]\n"
    "    ldp q14, q15, [x10, #224]\n"
    "    ldp q16, q17, [x10, #256]\n"
    "    ldp q18, q19, [x10, #288]\n"
    "    ldp q20, q21, [x10, #320]\n"
    "    ldp q22, q23, [x10, #352]\n"
    "    ldp q24, q25, [x10, #384]\n"
    "    ldp q26, q27, [x10, #416]\n"
    "    ldp q28, q29, [x10, #448]\n"
    "    ldp q30, q31, [x10, #480]\n"
    "    add x13, x10, #512\n"
    "    ldp x11, x12, [x13, #32]\n"
    "    msr nzcv, x11\n"
    "    msr fpcr, x12\n"
    "    msr fpsr, xzr\n"
    "    ldp x0, x1, [x13]\n"
    "    ldp x2, x3, [x13, #16]\n"
    "    blr x9\n"
    "    str q0, [x19]\n"
    "    str x0, [x19, #512]\n"
    "    mrs x11, nzcv\n"
    "    mrs x12, fpsr\n"
    "    str x11, [x19, #544]\n"
    "    str x12, [x19, #560]\n"
    "    msr fpcr, xzr\n"
    "    ldp d14, d15, [sp, #80]\n"
    "    ldp d12, d13, [sp, #64]\n"
    "    ldp d10, d11, [sp, #48]\n"
    "    ldp d8, d9, [sp, #32]\n"
    "    ldp x19, x20, [sp, #16]\n"
    "    ldp x29, x30, [sp], #96\n"
    "    ret\n");

static volatile sig_atomic_t fault;

static void on_fault(int sig, siginfo_t *si, void *ctx)
{
    ucontext_t *uc = ctx;

    (void)si;
    fault = sig;
    uc->uc_mcontext.pc += 4;        // on to the stub's ret
}

// Values with something for every kind of instruction to trip on.
static const uint64_t specials[] = {
    0x0000000000000000, 0x8000000000000000, 0x3ff0000000000000, 0xbff0000000000000,     // 0, -0, 1, -1
    0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000000000, 0x7ff4000000000001,     // inf, -inf, qnan, snan
    0x0000000000000001, 0x800fffffffffffff, 0x0010000000000000, 0x7fefffffffffffff,     // denormals, min, max
    0x3fe0000000000000, 0x4008000000000000, 0x43e0000000000000, 0xc3e0000000000001,     // .5, 3, 2^63, -(2^63)-
    0x3ff8000000000000, 0x400921fb54442d18, 0x41dfffffffc00000, 0xc1e0000000000000,     // 1.5, pi, 2^31-1, -2^31
    0x3f8000007fc00000, 0x7f800000ff800000, 0x0000000100800000, 0x7f7fffff80000001,     // singles in pairs
    0x3fc000003f000000, 0x4f0000004f800000, 0xcf000000bf800000, 0x7fa0000100000000,
    0x00007e007c00fc00, 0x3c00bc0000010400, 0x7fff800000ff0080, 0x0123456789abcdef,     // halves, integers
    0xffffffffffffffff, 0x7fffffffffffffff, 0x8000000000000001, 0x00000000ffffffff,
    0x7fff7fff80008000, 0x00ff00ff7f7f8080, 0x0102040810204080, 0xfedcba9876543210,
};
#define NSPECIAL (sizeof(specials) / sizeof(specials[0]))

static uint64_t rng_state;
static uint64_t rng(void)
{
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 7;
    rng_state ^= rng_state << 17;
    return rng_state;
}

#define NSETS 4
static struct state in[NSETS];

static void make_inputs(void)
{
    static const uint64_t nzcv[NSETS] = { 0x60000000, 0x80000000, 0x10000000, 0x00000000 };

    rng_state = 0x9e3779b97f4a7c15ull;
    for (int s = 0; s < NSETS; s++) {
        for (int r = 0; r < 32; r++) {
            for (int h = 0; h < 2; h++) {
                switch (s) {
                case 0: case 3:     // the specials, a different one in each register half
                    in[s].v[r][h] = specials[(r * 7 + h * 3 + 1) % NSPECIAL];
                    break;
                case 1:
                    in[s].v[r][h] = rng();
                    break;
                default:            // small numbers, and shift counts
                    in[s].v[r][h] = (rng() & 0x003f00ff00070003ull) ^ (r & 1 ? 0xffff000000000000ull : 0);
                    break;
                }
            }
        }
        for (int r = 0; r < 4; r++) {
            in[s].x[r] = s == 1 ? rng() : specials[(r * 5 + s * 11 + 2) % NSPECIAL];
        }
        in[s].nzcv = nzcv[s];
        // The last set under another rounding mode, flush-to-zero and default NaN.
        in[s].fpcr = s == 3 ? 0x03c00000 : 0;
    }
}

static uint64_t fnv(uint64_t h, const void *p, size_t n)
{
    const unsigned char *b = p;

    while (n--) {
        h = (h ^ *b++) * 0x100000001b3ull;
    }
    return h;
}

static uint32_t *code;
static int verbose;

// Run one encoding over the input sets. Returns its hash, and whether it faulted.
static uint64_t run_insn(uint32_t insn, int slot, int *ill)
{
    uint64_t h = 0xcbf29ce484222325ull;
    struct state out;

    *ill = 0;
    for (int s = 0; s < NSETS; s++) {
        memset(&out, 0, sizeof(out));
        fault = 0;
        run_stub(code + slot * 2, &in[s], &out);
        if (fault) {
            *ill = fault;
            return 0x1111111111111111ull * fault;
        }
        h = fnv(h, out.v[0], 16);
        h = fnv(h, &out.x[0], 8);
        h = fnv(h, &out.nzcv, 8);
        h = fnv(h, &out.fpsr, 8);
    }
    return h;
}

// A batch of encodings: write the stubs, then run each.
#define BATCH 2048
static uint32_t batch[BATCH];

static void run_batch(const char *name, int n)
{
    uint64_t h = 0xcbf29ce484222325ull;
    int nill = 0;

    for (int i = 0; i < n; i++) {
        code[i * 2] = batch[i];
        code[i * 2 + 1] = 0xd65f03c0;       // ret
    }
    __builtin___clear_cache((char *)code, (char *)(code + n * 2));
    for (int i = 0; i < n; i++) {
        int ill;
        uint64_t e = run_insn(batch[i], i, &ill);

        nill += ill != 0;
        h = fnv(h, &batch[i], 4);
        h = fnv(h, &e, 8);
        if (verbose) {
            if (ill) {
                printf("E %08x sig%d\n", batch[i], ill);
            } else {
                printf("E %08x %016llx\n", batch[i], (unsigned long long)e);
            }
        }
    }
    printf("SIMD %s n=%d ill=%d %016llx\n", name, n, nill, (unsigned long long)h);
    fflush(stdout);
}

int main(int argc, char **argv)
{
    struct sigaction sa = { .sa_sigaction = on_fault, .sa_flags = SA_SIGINFO };
    const char *only = NULL;
    char name[32];
    int n;

    if (argc == 3 && !strcmp(argv[1], "-b")) {
        only = argv[2];
        verbose = 1;
    }
    sigaction(SIGILL, &sa, NULL);
    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
    sigaction(SIGTRAP, &sa, NULL);
    sigaction(SIGFPE, &sa, NULL);
    code = mmap(NULL, BATCH * 8, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (code == MAP_FAILED) {
        perror("mmap");
        return 1;
    }
    make_inputs();

    // The buckets: bits 31:28 and 24:21, with 27:25 = 111; members by bits 20:10.
    for (unsigned b = 0; b < 256; b++) {
        snprintf(name, sizeof(name), "%02x", b);
        if (only && strcmp(only, name)) {
            continue;
        }
        for (unsigned m = 0; m < 2048; m++) {
            batch[m] = (b >> 4) << 28 | 7u << 25 | (b & 15) << 21 | m << 10 | 1 << 5;
        }
        run_batch(name, 2048);
    }
    // Modified immediates: 0 Q op 0111100000 abc cmode o2 1 defgh Rd
    if (!only || !strcmp(only, "imm")) {
        for (unsigned hi = 0; hi < 64; hi++) {      // Q op cmode
            n = 0;
            for (unsigned lo = 0; lo < 512; lo++) { // o2 abc defgh
                batch[n++] = 0x0f000400 | (hi >> 5) << 30 | ((hi >> 4) & 1) << 29 | (hi & 15) << 12 |
                             (lo >> 8) << 11 | ((lo >> 5) & 7) << 16 | (lo & 31) << 5;
            }
            snprintf(name, sizeof(name), "imm%02x", hi);
            run_batch(name, n);
        }
    }
    // fmov with an immediate: 0 0 0 11110 type 1 imm8 100 00000 Rd
    if (!only || !strcmp(only, "fmov")) {
        n = 0;
        for (unsigned t = 0; t < 4; t++) {
            for (unsigned i = 0; i < 256; i++) {
                batch[n++] = 0x1e201000 | t << 22 | i << 13;
            }
        }
        run_batch("fmov", n);
    }
    // Compares: fcmp(e) with a register and with zero, fccmp(e) on every condition and flags.
    if (!only || !strcmp(only, "cmp")) {
        for (unsigned t = 0; t < 4; t++) {
            n = 0;
            for (unsigned rm = 0; rm < 4; rm++) {
                for (unsigned o = 0; o < 32; o++) {
                    batch[n++] = 0x1e202000 | t << 22 | (rm * 9) << 16 | 1 << 5 | o;
                }
            }
            for (unsigned cond = 0; cond < 16; cond++) {
                for (unsigned o = 0; o < 32; o++) {
                    batch[n++] = 0x1e200400 | t << 22 | 2 << 16 | cond << 12 | 1 << 5 | o;
                }
            }
            snprintf(name, sizeof(name), "cmp%u", t);
            run_batch(name, n);
        }
    }
    return 0;
}
