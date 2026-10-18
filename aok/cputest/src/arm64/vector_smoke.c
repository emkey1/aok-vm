// arm64 NEON smoke: compare compiler-generated vector instructions against
// scalar reference loops computed on the same inputs. The scalar side is
// forced through volatile so the compiler cannot vectorize it away — any
// divergence is the emulator's vector engine disagreeing with plain
// integer/FP code, which is exactly the bug signal we want in-guest
// (the host-vs-guest differential harness in tests/arm64/ needs a Mac;
// this one runs anywhere the app runs).
//
// Families covered: three-same integer (add/sub/mul/min/max/compare,
// saturating), pairwise, across-lanes reductions, widening multiplies,
// narrowing (incl. saturating), shifts, permute (zip/uzp/ext/tbl),
// two-reg-misc (abs/neg/count/reverse), and FP vector arithmetic,
// compares, conversions, and fused multiply-add.

#include <arm_neon.h>
#include <math.h>
#include <stdint.h>
#include <string.h>
#include "test_common.h"

static const uint8_t IN_A[16] = {
    0x01, 0x7f, 0xff, 0x80, 0x3c, 0x5a, 0xa5, 0xc3,
    0xef, 0xcd, 0xab, 0x89, 0x67, 0x45, 0x23, 0x01,
};
static const uint8_t IN_B[16] = {
    0x40, 0xff, 0x80, 0x7f, 0xb3, 0xd2, 0xe1, 0x00,
    0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe,
};

static void check_bytes(const char *label, const void *got, const void *want, size_t n) {
    if (memcmp(got, want, n) != 0) {
        uint64_t g[2] = {0}, w[2] = {0};
        memcpy(g, got, n > 16 ? 16 : n);
        memcpy(w, want, n > 16 ? 16 : n);
        failf(label, g[0], g[1], 0, w[0], w[1], 0);
    } else {
        test_logf("%s ok\n", label);
    }
}

// ---- integer three-same ----------------------------------------------------

static void check_int_three_same(void) {
    uint8x16_t a = vld1q_u8(IN_A), b = vld1q_u8(IN_B);
    uint8_t got[16], want[16];

    vst1q_u8(got, vaddq_u8(a, b));
    for (int i = 0; i < 16; i++) {
        volatile uint8_t x = IN_A[i], y = IN_B[i];
        want[i] = (uint8_t) (x + y);
    }
    check_bytes("vaddq_u8", got, want, 16);

    vst1q_u8(got, vqaddq_u8(a, b));
    for (int i = 0; i < 16; i++) {
        volatile unsigned x = IN_A[i], y = IN_B[i];
        unsigned s = x + y;
        want[i] = s > 255 ? 255 : (uint8_t) s;
    }
    check_bytes("vqaddq_u8 (saturating)", got, want, 16);

    int8_t sgot[16], swant[16];
    vst1q_s8(sgot, vqsubq_s8(vreinterpretq_s8_u8(a), vreinterpretq_s8_u8(b)));
    for (int i = 0; i < 16; i++) {
        volatile int x = (int8_t) IN_A[i], y = (int8_t) IN_B[i];
        int d = x - y;
        swant[i] = d > 127 ? 127 : d < -128 ? -128 : (int8_t) d;
    }
    check_bytes("vqsubq_s8 (saturating)", sgot, swant, 16);

    uint16_t got16[8], want16[8];
    uint16x8_t a16 = vreinterpretq_u16_u8(a), b16 = vreinterpretq_u16_u8(b);
    vst1q_u16(got16, vmulq_u16(a16, b16));
    for (int i = 0; i < 8; i++) {
        volatile uint16_t x, y;
        memcpy((void *) &x, IN_A + 2 * i, 2);
        memcpy((void *) &y, IN_B + 2 * i, 2);
        want16[i] = (uint16_t) (x * y);
    }
    check_bytes("vmulq_u16", got16, want16, 16);

    int32_t got32[4], want32[4];
    int32x4_t a32 = vreinterpretq_s32_u8(a), b32 = vreinterpretq_s32_u8(b);
    vst1q_s32(got32, vmaxq_s32(a32, b32));
    for (int i = 0; i < 4; i++) {
        volatile int32_t x, y;
        memcpy((void *) &x, IN_A + 4 * i, 4);
        memcpy((void *) &y, IN_B + 4 * i, 4);
        want32[i] = x > y ? x : y;
    }
    check_bytes("vmaxq_s32", got32, want32, 16);

    uint32_t gotc[4], wantc[4];
    vst1q_u32(gotc, vcgtq_s32(a32, b32));
    for (int i = 0; i < 4; i++) {
        volatile int32_t x, y;
        memcpy((void *) &x, IN_A + 4 * i, 4);
        memcpy((void *) &y, IN_B + 4 * i, 4);
        wantc[i] = x > y ? 0xffffffffu : 0;
    }
    check_bytes("vcgtq_s32", gotc, wantc, 16);
}

// ---- pairwise + across-lanes -------------------------------------------------

static void check_reductions(void) {
    uint8x16_t a = vld1q_u8(IN_A), b = vld1q_u8(IN_B);

    uint8_t got[16], want[16];
    vst1q_u8(got, vpaddq_u8(a, b));
    for (int i = 0; i < 8; i++) {
        volatile uint8_t x = IN_A[2 * i], y = IN_A[2 * i + 1];
        want[i] = (uint8_t) (x + y);
    }
    for (int i = 0; i < 8; i++) {
        volatile uint8_t x = IN_B[2 * i], y = IN_B[2 * i + 1];
        want[8 + i] = (uint8_t) (x + y);
    }
    check_bytes("vpaddq_u8", got, want, 16);

    volatile unsigned ref = 0;
    for (int i = 0; i < 16; i++)
        ref += IN_A[i];
    uint16_t red = vaddlvq_u8(a); // widening across-lanes sum
    if (red != (uint16_t) ref)
        failf("vaddlvq_u8", red, 0, 0, ref, 0, 0);

    volatile uint8_t mx = 0;
    for (int i = 0; i < 16; i++)
        if (IN_B[i] > mx)
            mx = IN_B[i];
    uint8_t redmax = vmaxvq_u8(b);
    if (redmax != mx)
        failf("vmaxvq_u8", redmax, 0, 0, mx, 0, 0);
    else
        test_logf("reductions ok\n");
}

// ---- widening / narrowing ------------------------------------------------------

static void check_widen_narrow(void) {
    uint8x16_t a = vld1q_u8(IN_A), b = vld1q_u8(IN_B);

    uint16_t got16[8], want16[8];
    vst1q_u16(got16, vmull_u8(vget_low_u8(a), vget_low_u8(b)));
    for (int i = 0; i < 8; i++) {
        volatile unsigned x = IN_A[i], y = IN_B[i];
        want16[i] = (uint16_t) (x * y);
    }
    check_bytes("vmull_u8", got16, want16, 16);

    vst1q_u16(got16, vmull_high_u8(a, b));
    for (int i = 0; i < 8; i++) {
        volatile unsigned x = IN_A[8 + i], y = IN_B[8 + i];
        want16[i] = (uint16_t) (x * y);
    }
    check_bytes("vmull_high_u8", got16, want16, 16);

    int16x8_t w = vreinterpretq_s16_u8(a);
    int8_t got8[8], want8[8];
    vst1_s8(got8, vqmovn_s16(w));
    for (int i = 0; i < 8; i++) {
        volatile int16_t x;
        memcpy((void *) &x, IN_A + 2 * i, 2);
        want8[i] = x > 127 ? 127 : x < -128 ? -128 : (int8_t) x;
    }
    check_bytes("vqmovn_s16", got8, want8, 8);

    uint32_t gotl[4], wantl[4];
    uint16x4_t lo = vget_low_u16(vreinterpretq_u16_u8(a));
    vst1q_u32(gotl, vshll_n_u16(lo, 4));
    for (int i = 0; i < 4; i++) {
        volatile uint16_t x;
        memcpy((void *) &x, IN_A + 2 * i, 2);
        wantl[i] = (uint32_t) x << 4;
    }
    check_bytes("vshll_n_u16", gotl, wantl, 16);
}

// ---- shifts ----------------------------------------------------------------------

static void check_shifts(void) {
    uint32x4_t a32 = vreinterpretq_u32_u8(vld1q_u8(IN_A));
    uint32_t got[4], want[4];

    vst1q_u32(got, vshlq_n_u32(a32, 5));
    for (int i = 0; i < 4; i++) {
        volatile uint32_t x;
        memcpy((void *) &x, IN_A + 4 * i, 4);
        want[i] = x << 5;
    }
    check_bytes("vshlq_n_u32", got, want, 16);

    int32x4_t s32 = vreinterpretq_s32_u8(vld1q_u8(IN_A));
    int32_t sgot[4], swant[4];
    vst1q_s32(sgot, vshrq_n_s32(s32, 9));
    for (int i = 0; i < 4; i++) {
        volatile int32_t x;
        memcpy((void *) &x, IN_A + 4 * i, 4);
        swant[i] = x >> 9;
    }
    check_bytes("vshrq_n_s32 (arithmetic)", sgot, swant, 16);

    // register-form shift: negative amounts shift right
    int32x4_t amounts = {3, -4, 17, -28};
    vst1q_s32(sgot, vshlq_s32(s32, amounts));
    int32_t amt[4] = {3, -4, 17, -28};
    for (int i = 0; i < 4; i++) {
        volatile int32_t x;
        memcpy((void *) &x, IN_A + 4 * i, 4);
        swant[i] = amt[i] >= 0 ? (int32_t) ((uint32_t) x << amt[i]) : x >> -amt[i];
    }
    check_bytes("vshlq_s32 (register)", sgot, swant, 16);
}

// ---- permute ----------------------------------------------------------------------

static void check_permute(void) {
    uint8x16_t a = vld1q_u8(IN_A), b = vld1q_u8(IN_B);
    uint8_t got[16], want[16];

    vst1q_u8(got, vzip1q_u8(a, b));
    for (int i = 0; i < 8; i++) {
        want[2 * i] = IN_A[i];
        want[2 * i + 1] = IN_B[i];
    }
    check_bytes("vzip1q_u8", got, want, 16);

    vst1q_u8(got, vuzp2q_u8(a, b));
    for (int i = 0; i < 8; i++) {
        want[i] = IN_A[2 * i + 1];
        want[8 + i] = IN_B[2 * i + 1];
    }
    check_bytes("vuzp2q_u8", got, want, 16);

    vst1q_u8(got, vextq_u8(a, b, 5));
    for (int i = 0; i < 16; i++)
        want[i] = i < 11 ? IN_A[5 + i] : IN_B[i - 11];
    check_bytes("vextq_u8", got, want, 16);

    // TBL: indexes from IN_B select within IN_A; >= 16 yields 0
    vst1q_u8(got, vqtbl1q_u8(a, b));
    for (int i = 0; i < 16; i++)
        want[i] = IN_B[i] < 16 ? IN_A[IN_B[i]] : 0;
    check_bytes("vqtbl1q_u8", got, want, 16);

    vst1q_u8(got, vrev64q_u8(a));
    for (int i = 0; i < 8; i++) {
        want[i] = IN_A[7 - i];
        want[8 + i] = IN_A[15 - i];
    }
    check_bytes("vrev64q_u8", got, want, 16);
}

// ---- two-reg misc -------------------------------------------------------------------

static void check_two_misc(void) {
    int8x16_t s = vreinterpretq_s8_u8(vld1q_u8(IN_A));
    int8_t got[16], want[16];

    vst1q_s8(got, vabsq_s8(s));
    for (int i = 0; i < 16; i++) {
        volatile int8_t x = (int8_t) IN_A[i];
        want[i] = x == -128 ? -128 : x < 0 ? (int8_t) -x : x;
    }
    check_bytes("vabsq_s8", got, want, 16);

    uint8_t ugot[16], uwant[16];
    vst1q_u8(ugot, vcntq_u8(vld1q_u8(IN_A)));
    for (int i = 0; i < 16; i++) {
        volatile uint8_t x = IN_A[i];
        uint8_t c = 0;
        for (int bit = 0; bit < 8; bit++)
            c += (x >> bit) & 1;
        uwant[i] = c;
    }
    check_bytes("vcntq_u8 (popcount)", ugot, uwant, 16);

    uint32_t gotz[4], wantz[4];
    uint32x4_t u32 = vreinterpretq_u32_u8(vld1q_u8(IN_A));
    vst1q_u32(gotz, vclzq_u32(u32));
    for (int i = 0; i < 4; i++) {
        volatile uint32_t x;
        memcpy((void *) &x, IN_A + 4 * i, 4);
        uint32_t n = 0;
        while (n < 32 && !(x & (0x80000000u >> n)))
            n++;
        wantz[i] = n;
    }
    check_bytes("vclzq_u32", gotz, wantz, 16);
}

// ---- FP vector -----------------------------------------------------------------------

static void check_fp(void) {
    const float fa[4] = { 1.5f, -2.25f, 1e10f, -0.5f };
    const float fb[4] = { 3.0f, -1e-10f, 2.5f, 7.75f };
    float32x4_t a = vld1q_f32(fa), b = vld1q_f32(fb);
    float got[4], want[4];

    vst1q_f32(got, vaddq_f32(a, b));
    for (int i = 0; i < 4; i++) {
        volatile float x = fa[i], y = fb[i];
        want[i] = x + y;
    }
    check_bytes("vaddq_f32", got, want, 16);

    vst1q_f32(got, vmulq_f32(a, b));
    for (int i = 0; i < 4; i++) {
        volatile float x = fa[i], y = fb[i];
        want[i] = x * y;
    }
    check_bytes("vmulq_f32", got, want, 16);

    vst1q_f32(got, vfmaq_f32(b, a, a)); // b + a*a, fused
    for (int i = 0; i < 4; i++) {
        volatile float x = fa[i], y = fb[i];
        want[i] = fmaf(x, x, y);
    }
    check_bytes("vfmaq_f32 (fused)", got, want, 16);

    uint32_t cgot[4], cwant[4];
    vst1q_u32(cgot, vcgeq_f32(a, b));
    for (int i = 0; i < 4; i++) {
        volatile float x = fa[i], y = fb[i];
        cwant[i] = x >= y ? 0xffffffffu : 0;
    }
    check_bytes("vcgeq_f32", cgot, cwant, 16);

    int32_t igot[4], iwant[4];
    vst1q_s32(igot, vcvtq_s32_f32(a));
    for (int i = 0; i < 4; i++) {
        volatile float x = fa[i];
        // round toward zero, saturating (1e10 exceeds INT32_MAX)
        iwant[i] = x >= 2147483648.0f ? INT32_MAX
                 : x < -2147483648.0f ? INT32_MIN : (int32_t) x;
    }
    check_bytes("vcvtq_s32_f32 (saturating)", igot, iwant, 16);

    const double da[2] = { 2.0, -9.5 }, db[2] = { 0.5, 3.25 };
    float64x2_t xa = vld1q_f64(da), xb = vld1q_f64(db);
    double dgot[2], dwant[2];
    vst1q_f64(dgot, vdivq_f64(xa, xb));
    for (int i = 0; i < 2; i++) {
        volatile double x = da[i], y = db[i];
        dwant[i] = x / y;
    }
    check_bytes("vdivq_f64", dgot, dwant, 16);

    vst1q_f64(dgot, vsqrtq_f64(vabsq_f64(xa)));
    for (int i = 0; i < 2; i++) {
        volatile double x = da[i] < 0 ? -da[i] : da[i];
        dwant[i] = sqrt(x);
    }
    check_bytes("vsqrtq_f64", dgot, dwant, 16);
}

// ---- LDR (literal, SIMD&FP) -------------------------------------------------
//
// V=1 counterpart of the ordinary GPR "LDR (literal)" PC-relative form
// (which the JIT already handled). Compilers emit this constantly for FP
// constant pools -- NEON intrinsics alone don't reliably force the compiler
// to pick this exact encoding over materializing the constant some other
// way, so these use inline asm with a local literal to guarantee it.

static void check_literal_loads(void) {
    float sgot;
    asm volatile(
        "ldr s0, 1f\n"
        "str s0, %0\n"
        "b 2f\n"
        "1: .float 3.140625\n"
        "2:\n"
        : "=m"(sgot) :: "s0");
    if (sgot != 3.140625f)
        failf("ldr s (literal)", (uint64_t) (uint32_t) sgot, 0, 0, 0, 0, 0);
    else
        test_logf("ldr s (literal) ok\n");

    double dgot;
    asm volatile(
        "ldr d0, 1f\n"
        "str d0, %0\n"
        "b 2f\n"
        "1: .double 1.0\n" // the exact bit pattern (0x3ff0000000000000) that
                            // surfaced the missing-gadget bug: nvim/LuaJIT's
                            // arm64 build hit this on startup with no gadget
                            // to decode it, taking a guest SIGILL every time.
        "2:\n"
        : "=m"(dgot) :: "d0");
    if (dgot != 1.0)
        failf("ldr d (literal)", 0, 0, 0, 0, 0, 0);
    else
        test_logf("ldr d (literal) ok\n");

    uint64_t qgot[2];
    asm volatile(
        "ldr q0, 1f\n"
        "str q0, %0\n"
        "b 2f\n"
        ".align 4\n"
        "1: .dword 0x0123456789abcdef\n"
        "   .dword 0xfedcba9876543210\n"
        "2:\n"
        : "=m"(qgot) :: "q0");
    if (qgot[0] != 0x0123456789abcdefULL || qgot[1] != 0xfedcba9876543210ULL)
        failf("ldr q (literal)", qgot[0], qgot[1], 0, 0x0123456789abcdefULL, 0xfedcba9876543210ULL, 0);
    else
        test_logf("ldr q (literal) ok\n");
}

int main(int argc, char **argv) {
    test_init(argc, argv);
    check_int_three_same();
    check_reductions();
    check_widen_narrow();
    check_shifts();
    check_permute();
    check_two_misc();
    check_fp();
    check_literal_loads();
    return finish_suite("vector_smoke");
}
