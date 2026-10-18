// Add/subtract with carry and the multiplies on the arm64 JIT: ADC, ADCS,
// SBC, SBCS (32 and 64 bit), MUL, MADD, MSUB, UMULH, SMULH, UMULL, SMULL.
// These have slot-fed gadgets (jit/guest-arm64/alu_spec.S, the "ospec" bit of
// /proc/ish/arm64_jit_fuse) beside the generic adcsbc and dp3src ones, and
// the carry forms come in two kinds: one reloads the guest's flags, one runs
// on the host's flags as the instruction before left them. Both are driven
// here -- the carry set by a `subs` immediately before (flags live), and by
// `msr nzcv` with loads in between (not live) -- against plain C, with the
// edge values of carry, overflow and sign, and as the multi-word chains that
// bignum code is made of. Run once with `echo ospec=0 >
// /proc/ish/arm64_jit_fuse`, and with pair=0 and fwd=0, too.
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if defined(__aarch64__)

struct t { uint64_t a, b, cin, nzcv_in, r, nzcv; };

#define N_ 0x80000000u
#define Z_ 0x40000000u
#define C_ 0x20000000u
#define V_ 0x10000000u

// The carry made by `subs` straight before the instruction: flags live.
#define LIVE(name, insn) \
    __attribute__((noinline)) static void name(struct t *s) { \
        __asm__ volatile("ldr x11, [%0]\n ldr x12, [%0, #8]\n ldr x15, [%0, #16]\n mov x16, #1\n mov x13, #0\n" \
                         "subs x14, x15, x16\n" insn "\n mrs x9, nzcv\n str x13, [%0, #32]\n str x9, [%0, #40]" \
                         :: "r"(s) : "x9", "x11", "x12", "x13", "x14", "x15", "x16", "cc", "memory"); \
    }
// The flags written by msr, then loads: nothing live.
#define COLD(name, insn) \
    __attribute__((noinline)) static void name(struct t *s) { \
        __asm__ volatile("ldr x9, [%0, #24]\n msr nzcv, x9\n mov x13, #0\n ldr x11, [%0]\n ldr x12, [%0, #8]\n" \
                         insn "\n mrs x9, nzcv\n str x13, [%0, #32]\n str x9, [%0, #40]" \
                         :: "r"(s) : "x9", "x11", "x12", "x13", "cc", "memory"); \
    }
#define BOTH(n, insn) LIVE(n##_live, insn) COLD(n##_cold, insn)
BOTH(adc64,  "adc x13, x11, x12")
BOTH(adcs64, "adcs x13, x11, x12")
BOTH(sbc64,  "sbc x13, x11, x12")
BOTH(sbcs64, "sbcs x13, x11, x12")
BOTH(adc32,  "adc w13, w11, w12")
BOTH(adcs32, "adcs w13, w11, w12")
BOTH(sbc32,  "sbc w13, w11, w12")
BOTH(sbcs32, "sbcs w13, w11, w12")

static const uint64_t vals[] = {0, 1, 2, 0x7f, 0x7fffffff, 0x80000000, 0xffffffff, 0x100000000,
    0x7fffffffffffffff, 0x8000000000000000, 0xfffffffffffffffe, 0xffffffffffffffff,
    0x123456789abcdef0, 0xfedcba9876543210};
#define NV (sizeof(vals) / sizeof(vals[0]))

// a + b + c in `bits`, with the flags ADDS would give.
static uint64_t add_carry(uint64_t a, uint64_t b, unsigned c, int bits, uint32_t *nzcv) {
    uint64_t mask = bits == 64 ? ~0ull : 0xffffffffull;
    a &= mask; b &= mask;
    unsigned __int128 wide = (unsigned __int128) a + b + c;
    uint64_t r = (uint64_t) wide & mask;
    uint64_t sign = 1ull << (bits - 1);
    uint32_t f = 0;
    if (r & sign) f |= N_;
    if (r == 0) f |= Z_;
    if (wide >> bits) f |= C_;
    if ((~(a ^ b) & (a ^ r)) & sign) f |= V_;
    *nzcv = f;
    return r;
}

static int failures;
static void fail(const char *what, const struct t *s, uint64_t want_r, uint32_t want_f) {
    if (failures++ < 12)
        printf("adc_mul_ospec: %s a=%#llx b=%#llx: got %#llx nzcv %#x, want %#llx nzcv %#x\n", what,
               (unsigned long long) s->a, (unsigned long long) s->b, (unsigned long long) s->r,
               (unsigned) s->nzcv, (unsigned long long) want_r, (unsigned) want_f);
}

static void carry_ops(void) {
    static const struct { const char *name; void (*live)(struct t *), (*cold)(struct t *); int bits, sub, sets; } ops[] = {
        {"adc64", adc64_live, adc64_cold, 64, 0, 0}, {"adcs64", adcs64_live, adcs64_cold, 64, 0, 1},
        {"sbc64", sbc64_live, sbc64_cold, 64, 1, 0}, {"sbcs64", sbcs64_live, sbcs64_cold, 64, 1, 1},
        {"adc32", adc32_live, adc32_cold, 32, 0, 0}, {"adcs32", adcs32_live, adcs32_cold, 32, 0, 1},
        {"sbc32", sbc32_live, sbc32_cold, 32, 1, 0}, {"sbcs32", sbcs32_live, sbcs32_cold, 32, 1, 1},
    };
    for (unsigned o = 0; o < sizeof(ops) / sizeof(ops[0]); o++)
        for (unsigned i = 0; i < NV; i++)
            for (unsigned j = 0; j < NV; j++)
                for (unsigned c = 0; c <= 1; c++) {
                    uint32_t f;
                    uint64_t b = ops[o].sub ? ~vals[j] : vals[j];
                    uint64_t r = add_carry(vals[i], b, c, ops[o].bits, &f);
                    // live: `subs x14, cin, #1` leaves C = cin (1 - 1: Z and C; 0 - 1: N)
                    struct t s = {vals[i], vals[j], c, 0, 0, 0};
                    uint32_t before = c ? (Z_ | C_) : N_;
                    ops[o].live(&s);
                    if (s.r != r || s.nzcv != (ops[o].sets ? f : before))
                        fail(ops[o].name, &s, r, ops[o].sets ? f : before);
                    // cold: every other flag set as well, to see they are kept or replaced
                    for (int k = 0; k < 2; k++) {
                        uint32_t other = k ? (N_ | V_) : 0;
                        struct t u = {vals[i], vals[j], c, (c ? C_ : 0) | other, 0, 0};
                        ops[o].cold(&u);
                        uint32_t want = ops[o].sets ? f : (uint32_t) u.nzcv_in;
                        if (u.r != r || u.nzcv != want)
                            fail(ops[o].name, &u, r, want);
                    }
                }
}

// The chains: a 256-bit add and subtract, word by word.
__attribute__((noinline)) static void add256(const uint64_t *a, const uint64_t *b, uint64_t *r) {
    __asm__ volatile("ldp x9, x10, [%0]\n ldp x11, x12, [%0, #16]\n ldp x13, x14, [%1]\n ldp x15, x16, [%1, #16]\n"
                     "adds x9, x9, x13\n adcs x10, x10, x14\n adcs x11, x11, x15\n adcs x12, x12, x16\n"
                     "stp x9, x10, [%2]\n stp x11, x12, [%2, #16]\n adc x9, xzr, xzr\n str x9, [%2, #32]"
                     :: "r"(a), "r"(b), "r"(r) : "x9", "x10", "x11", "x12", "x13", "x14", "x15", "x16", "cc", "memory");
}
__attribute__((noinline)) static void sub256(const uint64_t *a, const uint64_t *b, uint64_t *r) {
    __asm__ volatile("ldp x9, x10, [%0]\n ldp x11, x12, [%0, #16]\n ldp x13, x14, [%1]\n ldp x15, x16, [%1, #16]\n"
                     "subs x9, x9, x13\n sbcs x10, x10, x14\n sbcs x11, x11, x15\n sbcs x12, x12, x16\n"
                     "stp x9, x10, [%2]\n stp x11, x12, [%2, #16]\n cset x9, cs\n str x9, [%2, #32]"
                     :: "r"(a), "r"(b), "r"(r) : "x9", "x10", "x11", "x12", "x13", "x14", "x15", "x16", "cc", "memory");
}
static void chains(void) {
    uint64_t seed = 0x9e3779b97f4a7c15ull;
    for (int round = 0; round < 400; round++) {
        uint64_t a[4], b[4], r[5], want[5];
        for (int i = 0; i < 4; i++) {
            seed = seed * 6364136223846793005ull + 1442695040888963407ull;
            a[i] = round % 3 == 0 ? ~0ull : seed;
            seed = seed * 6364136223846793005ull + 1442695040888963407ull;
            b[i] = round % 5 == 0 ? (i == 0) : seed;
        }
        unsigned c = 0;
        for (int i = 0; i < 4; i++) {
            unsigned __int128 w = (unsigned __int128) a[i] + b[i] + c;
            want[i] = (uint64_t) w;
            c = (unsigned) (w >> 64);
        }
        want[4] = c;
        add256(a, b, r);
        if (memcmp(r, want, sizeof(r)) != 0 && failures++ < 12)
            printf("adc_mul_ospec: 256-bit add, round %d\n", round);
        c = 1;
        for (int i = 0; i < 4; i++) {
            unsigned __int128 w = (unsigned __int128) a[i] + (uint64_t) ~b[i] + c;
            want[i] = (uint64_t) w;
            c = (unsigned) (w >> 64);
        }
        want[4] = c;
        sub256(a, b, r);
        if (memcmp(r, want, sizeof(r)) != 0 && failures++ < 12)
            printf("adc_mul_ospec: 256-bit subtract, round %d\n", round);
    }
}

// The multiplies. x11 = a, x12 = b, x14 = c; the result in x13.
#define MUL(name, insn) \
    __attribute__((noinline)) static uint64_t name(uint64_t a, uint64_t b, uint64_t c) { \
        uint64_t r; \
        __asm__ volatile("mov x11, %1\n mov x12, %2\n mov x14, %3\n nop\n" insn "\n nop\n mov %0, x13" \
                         : "=&r"(r) : "r"(a), "r"(b), "r"(c) : "x11", "x12", "x13", "x14"); \
        return r; \
    }
MUL(m_mul64,  "mul x13, x11, x12")
MUL(m_mul32,  "mul w13, w11, w12")
MUL(m_madd64, "madd x13, x11, x12, x14")
MUL(m_madd32, "madd w13, w11, w12, w14")
MUL(m_msub64, "msub x13, x11, x12, x14")
MUL(m_msub32, "msub w13, w11, w12, w14")
MUL(m_umulh,  "umulh x13, x11, x12")
MUL(m_smulh,  "smulh x13, x11, x12")
MUL(m_umull,  "umull x13, w11, w12")
MUL(m_smull,  "smull x13, w11, w12")
MUL(m_mul_dep, "mul x13, x11, x12\n umulh x13, x13, x11")       // the second uses the first's result
MUL(m_mul_same, "mul x13, x11, x11")

static void mul_ops(void) {
    for (unsigned i = 0; i < NV; i++)
        for (unsigned j = 0; j < NV; j++) {
            uint64_t a = vals[i], b = vals[j], c = vals[(i + j) % NV];
            unsigned __int128 u = (unsigned __int128) a * b;
            __int128 sg = (__int128) (int64_t) a * (int64_t) b;
            struct { const char *name; uint64_t got, want; } r[] = {
                {"mul64", m_mul64(a, b, c), a * b},
                {"mul32", m_mul32(a, b, c), (uint32_t) ((uint32_t) a * (uint32_t) b)},
                {"madd64", m_madd64(a, b, c), c + a * b},
                {"madd32", m_madd32(a, b, c), (uint32_t) ((uint32_t) c + (uint32_t) a * (uint32_t) b)},
                {"msub64", m_msub64(a, b, c), c - a * b},
                {"msub32", m_msub32(a, b, c), (uint32_t) ((uint32_t) c - (uint32_t) a * (uint32_t) b)},
                {"umulh", m_umulh(a, b, c), (uint64_t) (u >> 64)},
                {"smulh", m_smulh(a, b, c), (uint64_t) (sg >> 64)},
                {"umull", m_umull(a, b, c), (uint64_t) (uint32_t) a * (uint32_t) b},
                {"smull", m_smull(a, b, c), (uint64_t) ((int64_t) (int32_t) a * (int32_t) b)},
                {"mul;umulh", m_mul_dep(a, b, c), (uint64_t) (((unsigned __int128) (a * b) * a) >> 64)},
                {"mul x,x", m_mul_same(a, b, c), a * a},
            };
            for (unsigned k = 0; k < sizeof(r) / sizeof(r[0]); k++)
                if (r[k].got != r[k].want && failures++ < 12)
                    printf("adc_mul_ospec: %s a=%#llx b=%#llx c=%#llx: got %#llx, want %#llx\n", r[k].name,
                           (unsigned long long) a, (unsigned long long) b, (unsigned long long) c,
                           (unsigned long long) r[k].got, (unsigned long long) r[k].want);
        }
}

int main(void) {
    carry_ops();
    chains();
    mul_ops();
    if (failures != 0) {
        printf("adc_mul_ospec: FAIL failures=%d\n", failures);
        return 1;
    }
    printf("adc_mul_ospec: PASS\n");
    return 0;
}

#else

int main(void) {
    printf("adc_mul_ospec: PASS\n");
    return 0;
}

#endif
