// uetest.c -- SSE results that round up to exactly the smallest normal, with the inexact flag already set.
//
// x86 tells tininess after rounding to the precision with an unbounded exponent, so DBL_MIN * (1 - 2^-53),
// which rounds to DBL_MIN, is an underflow (UE and PE), while DBL_MIN * (1 - 2^-54) is not (PE only), and a
// sum that comes to DBL_MIN exactly raises nothing (but DE, from subnormal operands). MXCSR is loaded with PE alone before each operation:
// that is the state in which TCG's inline float path (include/tcg/tcg-inline-fp.h) takes the operation, and
// it stored the first kind without UE until tctiSH's 1599207c97. A line a case: the result's bits and the
// MXCSR flags after it. Run on an x86 and in a guest, and compare.
//
// Build with: gcc -O1 -static -msse2 -ffp-contract=off uetest.c -o uetest
#include <emmintrin.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static volatile uint64_t da, db;
static volatile uint32_t fa, fb;

static __m128d ld(volatile uint64_t *p) { uint64_t v = *p; double d; memcpy(&d, &v, 8); return _mm_set_pd(d, d); }
static __m128 lf(volatile uint32_t *p) { uint32_t v = *p; float f; memcpy(&f, &v, 4); return _mm_set_ps(f, f, f, f); }

#define START() _mm_setcsr(0x1f80 | 0x20)
static void outd(const char *n, __m128d r, unsigned csr)
{
    uint64_t b[2]; memcpy(b, &r, 16);
    printf("%-10s %016llx %016llx flags %02x\n", n, (unsigned long long)b[0], (unsigned long long)b[1], csr & 0x3f);
}
static void outf(const char *n, __m128 r, unsigned csr)
{
    uint32_t b[4]; memcpy(b, &r, 16);
    printf("%-10s %08x %08x %08x %08x flags %02x\n", n, b[0], b[1], b[2], b[3], csr & 0x3f);
}

#define D(name, A, B, expr) do { da = A; db = B; __m128d a = ld(&da), b = ld(&db), r; unsigned c; \
        START(); r = expr; c = _mm_getcsr(); outd(name, r, c); } while (0)
#define F(name, A, B, expr) do { fa = A; fb = B; __m128 a = lf(&fa), b = lf(&fb), r; unsigned c; \
        START(); r = expr; c = _mm_getcsr(); outf(name, r, c); } while (0)

int main(void)
{
    // rounds up to the smallest normal from a tiny value: UE and PE
    D("mulsd-ue", 0x0010000000000000, 0x3fefffffffffffff, _mm_mul_sd(a, b));
    D("mulpd-ue", 0x0010000000000000, 0xbfefffffffffffff, _mm_mul_pd(a, b));
    D("divsd-ue", 0x001fffffffffffff, 0x4000000000000000, _mm_div_sd(a, b));
    D("divpd-ue", 0x801fffffffffffff, 0x4000000000000000, _mm_div_pd(a, b));
    F("mulss-ue", 0x00800000, 0x3f7fffff, _mm_mul_ss(a, b));
    F("mulps-ue", 0x00800000, 0xbf7fffff, _mm_mul_ps(a, b));
    F("divss-ue", 0x00ffffff, 0x40000000, _mm_div_ss(a, b));
    F("divps-ue", 0x80ffffff, 0x40000000, _mm_div_ps(a, b));
    D("mulsd-ue2", 0x0020000000000000, 0x3fdfffffffffffff, _mm_mul_sd(a, b));
    // the smallest normal, not tiny before the result is fitted: PE only
    D("mulpd-pe", 0x0010000000000001, 0x3fefffffffffffff, _mm_mul_pd(a, b));
    F("mulss-pe", 0x00800001, 0x3f7fffff, _mm_mul_ss(a, b));
    // exactly the smallest normal: nothing new
    D("mulsd-ex", 0x0020000000000000, 0x3fe0000000000000, _mm_mul_sd(a, b));
    D("addsd-ex", 0x0008000000000000, 0x0008000000000000, _mm_add_sd(a, b));
    D("subpd-ex", 0x0020000000000000, 0x0010000000000000, _mm_sub_pd(a, b));
    F("addss-ex", 0x00400000, 0x00400000, _mm_add_ss(a, b));
    F("subps-ex", 0x01000000, 0x00800000, _mm_sub_ps(a, b));
    // just above and just below, for the neighbours
    D("mulsd-up", 0x0010000000000001, 0x3ff0000000000001, _mm_mul_sd(a, b));
    D("mulsd-dn", 0x0010000000000000, 0x3feffffffffffffe, _mm_mul_sd(a, b));
    F("mulss-dn", 0x00800000, 0x3f7ffffe, _mm_mul_ss(a, b));
    printf("uetest done\n");
    return 0;
}
