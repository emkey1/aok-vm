// FCVTL/FCVTL2 and FCVTN/FCVTN2 between half and single precision, on vectors.
//
// These two conversions are base ARMv8 AdvSIMD -- not FEAT_FP16, which is
// arithmetic on halves -- and the arm64 JIT answered both as undefined
// instructions ("sz=0 is the FP16 form"). A compiler that has a half type and
// no FP16 does its half arithmetic in single through exactly this pair:
// llvmpipe's JIT, in Mesa 26, died of SIGILL on `fcvtl v3.4s, v3.4h` in the
// first fragment shader it built.
//
// Every expected value below is an IEEE 754 bit pattern written out by hand,
// not something computed here with another instruction of the same family:
//
//   lengthen   1.0, -2.0, the smallest subnormal, the largest half, the
//              infinities, -0, a quiet NaN's payload
//   narrow     exact values; 1 + 2^-11 (a tie: to even, down) and 1 + 3*2^-11
//              (a tie: to even, up); overflow to infinity; underflow to zero;
//              a NaN stays a quiet NaN
//   the 2-forms read the HIGH half of the source (FCVTL2) and write the high
//              half of the destination, leaving the low half (FCVTN2); the
//              plain FCVTN zeroes the high half
//
// arm64 only.
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if !defined(__aarch64__)
int main(void) { printf("fcvt_half: SKIP (arm64 only)\n"); return 0; }
#else
#include <arm_neon.h>

static int failures;

static void check16(const char *what, const uint16_t *got, const uint16_t *want, int n) {
    for (int i = 0; i < n; i++)
        if (got[i] != want[i]) {
            printf("fcvt_half: %s lane %d: got %#06x, wanted %#06x\n", what, i, got[i], want[i]);
            failures++;
        }
}
static void check32(const char *what, const uint32_t *got, const uint32_t *want, int n) {
    for (int i = 0; i < n; i++)
        if (got[i] != want[i]) {
            printf("fcvt_half: %s lane %d: got %#010x, wanted %#010x\n", what, i, got[i], want[i]);
            failures++;
        }
}

// The instructions themselves, by name, with the operands in registers the
// compiler cannot fold away.
static void lengthen(const uint16_t in[8], uint32_t lo[4], uint32_t hi[4]) {
    uint16x8_t v = vld1q_u16(in);
    uint32x4_t a, b;
    __asm__ volatile("fcvtl %0.4s, %2.4h\n\tfcvtl2 %1.4s, %2.8h" : "=&w"(a), "=&w"(b) : "w"(v));
    vst1q_u32(lo, a);
    vst1q_u32(hi, b);
}
static void narrow(const uint32_t in[4], uint16_t plain[8], uint16_t two[8]) {
    uint32x4_t v = vld1q_u32(in);
    uint16x8_t p = vdupq_n_u16(0xaaaa);   // FCVTN must clear the high half of this
    uint16x8_t t = vdupq_n_u16(0x5555);   // FCVTN2 must keep the low half of this
    __asm__ volatile("fcvtn %0.4h, %2.4s\n\tfcvtn2 %1.8h, %2.4s" : "+w"(p), "+w"(t) : "w"(v));
    vst1q_u16(plain, p);
    vst1q_u16(two, t);
}

int main(void) {
    //                         1.0     -2.0    min sub  max     +inf    -inf    -0      qNaN+payload
    const uint16_t halves[8] = {0x3c00, 0xc000, 0x0001, 0x7bff, 0x7c00, 0xfc00, 0x8000, 0x7e01};
    const uint32_t singles[8] = {0x3f800000, 0xc0000000, 0x33800000, 0x477fe000,
                                 0x7f800000, 0xff800000, 0x80000000, 0x7fc02000};
    uint32_t lo[4], hi[4];
    lengthen(halves, lo, hi);
    check32("fcvtl", lo, singles, 4);
    check32("fcvtl2", hi, singles + 4, 4);

    //                        1.0         -2.0        65504 (max)  2^-24 (min sub)
    const uint32_t exact[4] = {0x3f800000, 0xc0000000, 0x477fe000, 0x33800000};
    const uint16_t exact_h[4] = {0x3c00, 0xc000, 0x7bff, 0x0001};
    //                          1+2^-11     1+3*2^-11   65520 -> inf  1e-10 -> 0
    const uint32_t rounded[4] = {0x3f801000, 0x3f803000, 0x477ff000, 0x2edbe6ff};
    const uint16_t rounded_h[4] = {0x3c00, 0x3c02, 0x7c00, 0x0000};
    //                          +inf        -0          sNaN         -1.5
    const uint32_t special[4] = {0x7f800000, 0x80000000, 0x7fa00000, 0xbfc00000};
    const uint16_t special_h[4] = {0x7c00, 0x8000, 0x7f00, 0xbe00};

    const struct { const char *name; const uint32_t *in; const uint16_t *want; } cases[] = {
        {"exact", exact, exact_h}, {"rounded", rounded, rounded_h}, {"special", special, special_h},
    };
    for (unsigned c = 0; c < 3; c++) {
        uint16_t plain[8], two[8], want_plain[8], want_two[8];
        char what[48];
        narrow(cases[c].in, plain, two);
        for (int i = 0; i < 4; i++) {
            want_plain[i] = cases[c].want[i];
            want_plain[4 + i] = 0;          // cleared
            want_two[i] = 0x5555;           // kept
            want_two[4 + i] = cases[c].want[i];
        }
        snprintf(what, sizeof(what), "fcvtn (%s)", cases[c].name);
        check16(what, plain, want_plain, 8);
        snprintf(what, sizeof(what), "fcvtn2 (%s)", cases[c].name);
        check16(what, two, want_two, 8);
    }

    if (failures != 0) {
        printf("fcvt_half: FAIL failures=%d\n", failures);
        return 1;
    }
    printf("fcvt_half: PASS\n");
    return 0;
}
#endif
