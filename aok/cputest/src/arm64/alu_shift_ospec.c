// Rotates, shifted and inverted logic, shifted and extended add/subtract,
// MVN, and add-with-carry of XZR on the arm64 JIT. These have slot-fed
// gadgets (jit/guest-arm64/alu_spec.S, the "ospec" bit of
// /proc/ish/arm64_jit_fuse) beside the generic logical_reg, addsub_reg,
// addsub_ext, extr and adcsbc ones, which decode the instruction at run time.
// Every form is run on edge values in both widths and compared with plain C.
// Run once with `echo ospec=0 > /proc/ish/arm64_jit_fuse`, and with pair=0 and
// fwd=0, too: two of these in a row are a fused pair.
#include <stdint.h>
#include <stdio.h>

#if defined(__aarch64__)

static const uint64_t vals[] = {0, 1, 0x80, 0xff, 0x7fff, 0x8000, 0xffff, 0x7fffffff, 0x80000000, 0xffffffff,
    0x100000000, 0x7fffffffffffffff, 0x8000000000000000, 0xffffffffffffffff, 0x123456789abcdef0,
    0xfedcba9876543210, 0xa5a5a5a55a5a5a5a};
#define NV (sizeof(vals) / sizeof(vals[0]))

static int failures;
static void check(const char *what, uint64_t a, uint64_t b, uint64_t got, uint64_t want) {
    if (got != want && failures++ < 16)
        printf("alu_shift_ospec: %s a=%#llx b=%#llx: got %#llx, want %#llx\n", what,
               (unsigned long long) a, (unsigned long long) b, (unsigned long long) got, (unsigned long long) want);
}

// x11 = a, x12 = b; the result in x13. A nop either side keeps the
// instruction from pairing with the moves around it.
#define OP(name, insn) \
    __attribute__((noinline)) static uint64_t name(uint64_t a, uint64_t b) { \
        uint64_t r; \
        __asm__ volatile("mov x11, %1\n mov x12, %2\n nop\n" insn "\n nop\n mov %0, x13" \
                         : "=&r"(r) : "r"(a), "r"(b) : "x11", "x12", "x13", "cc"); \
        return r; \
    }

static uint64_t ror64(uint64_t v, unsigned n) { return n ? (v >> n) | (v << (64 - n)) : v; }
static uint32_t ror32(uint32_t v, unsigned n) { return n ? (v >> n) | (v << (32 - n)) : v; }
static uint64_t sh64(uint64_t v, int kind, unsigned n) {
    switch (kind) {
        case 0: return v << n;
        case 1: return v >> n;
        case 2: return (uint64_t) ((int64_t) v >> n);
        default: return ror64(v, n);
    }
}
static uint32_t sh32(uint32_t v, int kind, unsigned n) {
    switch (kind) {
        case 0: return v << n;
        case 1: return v >> n;
        case 2: return (uint32_t) ((int32_t) v >> n);
        default: return ror32(v, n);
    }
}
static uint64_t logic(int op, uint64_t a, uint64_t b) {
    switch (op) {
        case 0: return a & b;
        case 1: return a | b;
        case 2: return a ^ b;
        case 3: return a & ~b;
        case 4: return a | ~b;
        default: return a ^ ~b;
    }
}

// ---- logical, shifted: six operations, four shifts, three amounts, two widths
#define LOGSH(op, sh, n) \
    OP(l64_##op##_##sh##_##n, #op " x13, x11, x12, " #sh " #" #n) \
    OP(l32_##op##_##sh##_##n, #op " w13, w11, w12, " #sh " #" #n)
#define LOGSH_ALL(op) \
    LOGSH(op, lsl, 1) LOGSH(op, lsl, 13) LOGSH(op, lsl, 31) \
    LOGSH(op, lsr, 1) LOGSH(op, lsr, 13) LOGSH(op, lsr, 31) \
    LOGSH(op, asr, 1) LOGSH(op, asr, 13) LOGSH(op, asr, 31) \
    LOGSH(op, ror, 1) LOGSH(op, ror, 13) LOGSH(op, ror, 31)
LOGSH_ALL(and) LOGSH_ALL(orr) LOGSH_ALL(eor) LOGSH_ALL(bic) LOGSH_ALL(orn) LOGSH_ALL(eon)
OP(l64_and_lsl_63, "and x13, x11, x12, lsl #63")
OP(l64_eor_ror_63, "eor x13, x11, x12, ror #63")
OP(l64_orr_asr_63, "orr x13, x11, x12, asr #63")
// ---- inverted, unshifted; MVN
OP(l64_bic, "bic x13, x11, x12") OP(l32_bic, "bic w13, w11, w12")
OP(l64_orn, "orn x13, x11, x12") OP(l32_orn, "orn w13, w11, w12")
OP(l64_eon, "eon x13, x11, x12") OP(l32_eon, "eon w13, w11, w12")
OP(l64_mvn, "mvn x13, x12")       OP(l32_mvn, "mvn w13, w12")
// ---- rotates
OP(r64_1, "ror x13, x11, #1") OP(r64_17, "ror x13, x11, #17") OP(r64_63, "ror x13, x11, #63")
OP(r32_1, "ror w13, w11, #1") OP(r32_17, "ror w13, w11, #17") OP(r32_31, "ror w13, w11, #31")
OP(x64_20, "extr x13, x11, x12, #20") OP(x32_20, "extr w13, w11, w12, #20")   // the general form: still generic
// ---- add and subtract with LSR and ASR
OP(a64_lsr, "add x13, x11, x12, lsr #7") OP(a32_lsr, "add w13, w11, w12, lsr #7")
OP(a64_asr, "add x13, x11, x12, asr #7") OP(a32_asr, "add w13, w11, w12, asr #7")
OP(s64_lsr, "sub x13, x11, x12, lsr #33") OP(s32_lsr, "sub w13, w11, w12, lsr #3")
OP(s64_asr, "sub x13, x11, x12, asr #33") OP(s32_asr, "sub w13, w11, w12, asr #3")
// ---- extended
#define EXT(e, n) \
    OP(e64a_##e##_##n, "add x13, x11, w12, " #e " #" #n) OP(e64s_##e##_##n, "sub x13, x11, w12, " #e " #" #n)
EXT(uxtw, 0) EXT(uxtw, 2) EXT(sxtw, 0) EXT(sxtw, 3) EXT(uxtb, 0) EXT(uxtb, 4) EXT(uxth, 1) EXT(sxtb, 0) EXT(sxtb, 2)
EXT(sxth, 0) EXT(sxth, 4)
OP(e64a_uxtx_3, "add x13, x11, x12, uxtx #3") OP(e64s_sxtx_1, "sub x13, x11, x12, sxtx #1")
OP(e32a_uxtb, "add w13, w11, w12, uxtb #1") OP(e32s_uxth, "sub w13, w11, w12, uxth")
OP(e32a_sxtb, "add w13, w11, w12, sxtb")    OP(e32s_sxth, "sub w13, w11, w12, sxth #2")
// SP as the first operand, and as the destination
__attribute__((noinline)) static uint64_t sp_ext(uint64_t b) {
    uint64_t r;
    __asm__ volatile("mov x12, %1\n mov x9, sp\n nop\n add x13, sp, w12, uxtw #2\n nop\n sub %0, x13, x9"
                     : "=&r"(r) : "r"(b) : "x9", "x12", "x13");
    return r;
}
__attribute__((noinline)) static uint64_t sp_dest(uint64_t b) {
    uint64_t r;
    __asm__ volatile("mov x12, %1\n mov x9, sp\n nop\n sub sp, sp, w12, uxtb #4\n nop\n mov x13, sp\n mov sp, x9\n sub %0, x9, x13"
                     : "=&r"(r) : "r"(b) : "x9", "x12", "x13");
    return r;
}
// ---- the carry on its own: adc/adcs/sbc with XZR, the carry made just before (live) and by msr (not)
#define CARRY(name, insn) \
    __attribute__((noinline)) static uint64_t name##_live(uint64_t a, uint64_t c) { \
        uint64_t r; \
        __asm__ volatile("mov x11, %1\n mov x12, %2\n subs x14, x12, #1\n" insn "\n mov %0, x13" \
                         : "=&r"(r) : "r"(a), "r"(c) : "x11", "x12", "x13", "x14", "cc"); \
        return r; \
    } \
    __attribute__((noinline)) static uint64_t name##_cold(uint64_t a, uint64_t c) { \
        uint64_t r; \
        __asm__ volatile("mov x11, %1\n lsl x12, %2, #29\n msr nzcv, x12\n ldr x14, [sp]\n" insn "\n mov %0, x13" \
                         : "=&r"(r) : "r"(a), "r"(c) : "x11", "x12", "x13", "x14", "cc"); \
        return r; \
    }
CARRY(cz_adc64, "adc x13, x11, xzr") CARRY(cz_adc32, "adc w13, w11, wzr")
CARRY(cz_sbc64, "sbc x13, x11, xzr") CARRY(cz_sbc32, "sbc w13, w11, wzr")
CARRY(cz_adcs64, "adcs x13, x11, xzr\n cset x14, cs\n add x13, x13, x14, lsl #1")   // result + 2 * carry out

int main(void) {
    static const struct { uint64_t (*f)(uint64_t, uint64_t); int bits, op, kind, n; const char *name; } logs[] = {
#define L1(op, i, sh, k, n) {l64_##op##_##sh##_##n, 64, i, k, n, #op " x " #sh " " #n}, {l32_##op##_##sh##_##n, 32, i, k, n, #op " w " #sh " " #n},
#define L(op, i) L1(op, i, lsl, 0, 1) L1(op, i, lsl, 0, 13) L1(op, i, lsl, 0, 31) L1(op, i, lsr, 1, 1) L1(op, i, lsr, 1, 13) \
        L1(op, i, lsr, 1, 31) L1(op, i, asr, 2, 1) L1(op, i, asr, 2, 13) L1(op, i, asr, 2, 31) L1(op, i, ror, 3, 1) \
        L1(op, i, ror, 3, 13) L1(op, i, ror, 3, 31)
        L(and, 0) L(orr, 1) L(eor, 2) L(bic, 3) L(orn, 4) L(eon, 5)
        {l64_and_lsl_63, 64, 0, 0, 63, "and x lsl 63"}, {l64_eor_ror_63, 64, 2, 3, 63, "eor x ror 63"},
        {l64_orr_asr_63, 64, 1, 2, 63, "orr x asr 63"},
    };
    for (unsigned t = 0; t < sizeof(logs) / sizeof(logs[0]); t++)
        for (unsigned i = 0; i < NV; i++)
            for (unsigned j = 0; j < NV; j++) {
                uint64_t a = vals[i], b = vals[j], want;
                // (the inverted forms invert the SHIFTED operand)
                if (logs[t].bits == 64)
                    want = logic(logs[t].op, a, sh64(b, logs[t].kind, (unsigned) logs[t].n));
                else
                    want = (uint32_t) logic(logs[t].op, (uint32_t) a, sh32((uint32_t) b, logs[t].kind, (unsigned) logs[t].n));
                check(logs[t].name, a, b, logs[t].f(a, b), want);
            }
    for (unsigned i = 0; i < NV; i++)
        for (unsigned j = 0; j < NV; j++) {
            uint64_t a = vals[i], b = vals[j];
            uint32_t a32 = (uint32_t) a, b32 = (uint32_t) b;
            check("bic x", a, b, l64_bic(a, b), a & ~b);   check("bic w", a, b, l32_bic(a, b), a32 & ~b32);
            check("orn x", a, b, l64_orn(a, b), a | ~b);   check("orn w", a, b, l32_orn(a, b), (uint32_t) (a32 | ~b32));
            check("eon x", a, b, l64_eon(a, b), a ^ ~b);   check("eon w", a, b, l32_eon(a, b), (uint32_t) (a32 ^ ~b32));
            check("mvn x", a, b, l64_mvn(a, b), ~b);       check("mvn w", a, b, l32_mvn(a, b), (uint32_t) ~b32);
            check("ror x 1", a, b, r64_1(a, b), ror64(a, 1));    check("ror x 17", a, b, r64_17(a, b), ror64(a, 17));
            check("ror x 63", a, b, r64_63(a, b), ror64(a, 63)); check("ror w 1", a, b, r32_1(a, b), ror32(a32, 1));
            check("ror w 17", a, b, r32_17(a, b), ror32(a32, 17)); check("ror w 31", a, b, r32_31(a, b), ror32(a32, 31));
            check("extr x 20", a, b, x64_20(a, b), (a << 44) | (b >> 20));
            check("extr w 20", a, b, x32_20(a, b), (uint32_t) ((a32 << 12) | (b32 >> 20)));
            check("add x lsr", a, b, a64_lsr(a, b), a + (b >> 7));
            check("add w lsr", a, b, a32_lsr(a, b), (uint32_t) (a32 + (b32 >> 7)));
            check("add x asr", a, b, a64_asr(a, b), a + (uint64_t) ((int64_t) b >> 7));
            check("add w asr", a, b, a32_asr(a, b), (uint32_t) (a32 + (uint32_t) ((int32_t) b32 >> 7)));
            check("sub x lsr", a, b, s64_lsr(a, b), a - (b >> 33));
            check("sub w lsr", a, b, s32_lsr(a, b), (uint32_t) (a32 - (b32 >> 3)));
            check("sub x asr", a, b, s64_asr(a, b), a - (uint64_t) ((int64_t) b >> 33));
            check("sub w asr", a, b, s32_asr(a, b), (uint32_t) (a32 - (uint32_t) ((int32_t) b32 >> 3)));
#define X(e, n, expr) check("add " #e " " #n, a, b, e64a_##e##_##n(a, b), a + ((uint64_t) (expr) << n)); \
                      check("sub " #e " " #n, a, b, e64s_##e##_##n(a, b), a - ((uint64_t) (expr) << n));
            X(uxtw, 0, (uint32_t) b) X(uxtw, 2, (uint32_t) b) X(sxtw, 0, (int64_t) (int32_t) b) X(sxtw, 3, (int64_t) (int32_t) b)
            X(uxtb, 0, (uint8_t) b) X(uxtb, 4, (uint8_t) b) X(uxth, 1, (uint16_t) b) X(sxtb, 0, (int64_t) (int8_t) b)
            X(sxtb, 2, (int64_t) (int8_t) b) X(sxth, 0, (int64_t) (int16_t) b) X(sxth, 4, (int64_t) (int16_t) b)
            check("add uxtx 3", a, b, e64a_uxtx_3(a, b), a + (b << 3));
            check("sub sxtx 1", a, b, e64s_sxtx_1(a, b), a - (b << 1));
            check("add w uxtb 1", a, b, e32a_uxtb(a, b), (uint32_t) (a32 + ((uint32_t) (uint8_t) b << 1)));
            check("sub w uxth", a, b, e32s_uxth(a, b), (uint32_t) (a32 - (uint16_t) b));
            check("add w sxtb", a, b, e32a_sxtb(a, b), (uint32_t) (a32 + (uint32_t) (int32_t) (int8_t) b));
            check("sub w sxth 2", a, b, e32s_sxth(a, b), (uint32_t) (a32 - ((uint32_t) (int32_t) (int16_t) b << 2)));
        }
    for (unsigned j = 0; j < NV; j++) {
        uint64_t b = vals[j];
        check("add x, sp, w, uxtw 2", 0, b, sp_ext(b), (uint64_t) (uint32_t) b << 2);
        check("sub sp, sp, w, uxtb 4", 0, b, sp_dest(b), (uint64_t) (uint8_t) b << 4);
    }
    for (unsigned i = 0; i < NV; i++)
        for (uint64_t c = 0; c <= 1; c++) {
            uint64_t a = vals[i];
            uint32_t a32 = (uint32_t) a;
            uint64_t carry_out = (a == ~0ull && c) ? 1 : 0;
            check("adc x, xzr live", a, c, cz_adc64_live(a, c), a + c);        check("adc x, xzr cold", a, c, cz_adc64_cold(a, c), a + c);
            check("adc w, wzr live", a, c, cz_adc32_live(a, c), (uint32_t) (a32 + c)); check("adc w, wzr cold", a, c, cz_adc32_cold(a, c), (uint32_t) (a32 + c));
            check("sbc x, xzr live", a, c, cz_sbc64_live(a, c), a - 1 + c);    check("sbc x, xzr cold", a, c, cz_sbc64_cold(a, c), a - 1 + c);
            check("sbc w, wzr live", a, c, cz_sbc32_live(a, c), (uint32_t) (a32 - 1 + c)); check("sbc w, wzr cold", a, c, cz_sbc32_cold(a, c), (uint32_t) (a32 - 1 + c));
            check("adcs x, xzr live", a, c, cz_adcs64_live(a, c), a + c + 2 * carry_out);
            check("adcs x, xzr cold", a, c, cz_adcs64_cold(a, c), a + c + 2 * carry_out);
        }
    if (failures != 0) {
        printf("alu_shift_ospec: FAIL failures=%d\n", failures);
        return 1;
    }
    printf("alu_shift_ospec: PASS\n");
    return 0;
}

#else

int main(void) {
    printf("alu_shift_ospec: PASS\n");
    return 0;
}

#endif
