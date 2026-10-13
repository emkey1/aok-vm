// fptest [-v] -- a floating-point transcript for comparing two engines bit for bit.
//
// Every double-precision operation an engine might run on the host's FP unit instead of in software, over
// a grid of awkward operands (zeros, subnormals, the smallest normals, values that overflow, infinities,
// quiet and signalling NaNs with payloads, integers at the edges of int and long), in all four rounding
// modes. Each line is a hash over every result's bits AND the exception flags it raised, so a wrong sign
// of zero, a NaN payload that should have been made canonical, or one missing inexact flag changes it.
// With -v every case is printed, to find which.
//
// Build with: gcc -O1 -static -ffp-contract=off -fno-math-errno fptest.c -lm
// Operands are volatile so the compiler emits the instruction rather than the answer.
#include <fenv.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static const uint64_t vals[] = {
    0x0000000000000000, 0x8000000000000000,     // +0, -0
    0x3ff0000000000000, 0xbff0000000000000,     // 1, -1
    0x3ff8000000000000, 0x4000000000000000, 0x4008000000000000, 0x3fb999999999999a,  // 1.5 2 3 0.1
    0x3fe0000000000000, 0xbfe0000000000000, 0x4004000000000000, 0x400c000000000000,  // .5 -.5 2.5 3.5
    0x0000000000000001, 0x8000000000000001,     // smallest subnormals
    0x000fffffffffffff, 0x0008000000000000, 0x00000000000fffff,   // subnormals
    0x0010000000000000, 0x8010000000000000, 0x0010000000000001, 0x001fffffffffffff,  // smallest normals
    0x0020000000000000, 0x0350000000000000,     // 2*DBL_MIN, 2^-970: products land near the edge
    0x7fefffffffffffff, 0xffefffffffffffff, 0x7fe0000000000000, 0x7fd0000000000001,  // largest
    0x1e60000000000000, 0x5fd0000000000000, 0x2000000000000001, 0x5ff123456789abcd,  // sqrt-ish scales
    0x7ff0000000000000, 0xfff0000000000000,     // infinities
    0x7ff8000000000000, 0xfff8000000000000, 0x7ff8000000000123, 0x7ffc0000deadbeef,  // quiet NaNs
    0x7ff0000000000001, 0xfff4000000000000, 0x7ff00000000abcde,   // signalling NaNs
    0x41dfffffffc00000, 0x41e0000000000000, 0x41dfffffffe00000, 0xc1e0000000000000, 0xc1e0000000200000,
    0x41efffffffe00000, 0x41f0000000000000,     // around INT_MAX, INT_MIN, UINT_MAX
    0x43dfffffffffffff, 0x43e0000000000000, 0xc3e0000000000000, 0xc3e0000000000001,
    0x43efffffffffffff, 0x43f0000000000000,     // around LONG_MAX, LONG_MIN, ULONG_MAX
    0x4330000000000001, 0x433fffffffffffff, 0x4340000000000001,   // 2^52 and 2^53: last fractions
    0x3ff123456789abcd, 0x4028fedcba987654, 0xc03a5a5a5a5a5a5a, 0x3fd5555555555555, 0x400921fb54442d18,
    0x3cb0000000000000, 0x3ca0000000000001, 0xbfefffffffffffff, 0x3ff0000000000001,
};
#define N (sizeof vals / sizeof vals[0])

static int verbose;
static uint64_t h;
static const char *op;
static int rm;

static double from_bits(uint64_t b) { double d; memcpy(&d, &b, 8); return d; }
static uint64_t bits(double d) { uint64_t b; memcpy(&b, &d, 8); return b; }
static uint32_t bitsf(float f) { uint32_t b; memcpy(&b, &f, 4); return b; }

static void record(uint64_t result, unsigned i, unsigned j, unsigned k) {
    unsigned flags = fetestexcept(FE_ALL_EXCEPT);
    h = (h ^ result) * 0x100000001b3ull;
    h = (h ^ flags) * 0x100000001b3ull;
    if (verbose)
        printf("  %s rm=%d %016llx %016llx %016llx -> %016llx flags %02x\n", op, rm,
               (unsigned long long) vals[i], (unsigned long long) vals[j], (unsigned long long) vals[k],
               (unsigned long long) result, flags);
    feclearexcept(FE_ALL_EXCEPT);
}

static void begin(const char *name) {
    op = name;
    h = 0xcbf29ce484222325ull;
    feclearexcept(FE_ALL_EXCEPT);
}
static void end(void) { printf("FP %-8s rm=%d %016llx\n", op, rm, (unsigned long long) h); }

#define BINARY(name, expr) do { \
    begin(name); \
    for (unsigned i = 0; i < N; i++) for (unsigned j = 0; j < N; j++) { \
        volatile double a = from_bits(vals[i]), b = from_bits(vals[j]); \
        record(expr, i, j, 0); \
    } \
    end(); } while (0)
#define UNARY(name, expr) do { \
    begin(name); \
    for (unsigned i = 0; i < N; i++) { \
        volatile double a = from_bits(vals[i]); \
        record(expr, i, 0, 0); \
    } \
    end(); } while (0)
#define FROM_INT(name, expr) do { \
    begin(name); \
    for (unsigned i = 0; i < N; i++) { \
        volatile uint64_t x = vals[i]; \
        record(expr, i, 0, 0); \
    } \
    end(); } while (0)
// Every third operand of each, 22^3 triples: enough to reach each kind in each position.
#define TERNARY(name, expr) do { \
    begin(name); \
    for (unsigned i = 0; i < N; i += 3) for (unsigned j = 1; j < N; j += 3) for (unsigned k = 2; k < N; k += 3) { \
        volatile double a = from_bits(vals[i]), b = from_bits(vals[j]), c = from_bits(vals[k]); \
        record(expr, i, j, k); \
    } \
    end(); } while (0)

int main(int argc, char **argv) {
    static const int modes[] = { FE_TONEAREST, FE_TOWARDZERO, FE_DOWNWARD, FE_UPWARD };
    verbose = argc > 1 && !strcmp(argv[1], "-v");
    for (rm = 0; rm < 4; rm++) {
        fesetround(modes[rm]);
        BINARY("add", bits(a + b));
        BINARY("sub", bits(a - b));
        BINARY("mul", bits(a * b));
        BINARY("div", bits(a / b));
        BINARY("min", bits(__builtin_fmin(a, b)));
        BINARY("max", bits(__builtin_fmax(a, b)));
        BINARY("eq", a == b);
        BINARY("lt", a < b);
        BINARY("le", a <= b);
        BINARY("sgnj", bits(__builtin_copysign(a, b)));
        UNARY("sqrt", bits(__builtin_sqrt(a)));
        UNARY("neg", bits(-a));
        UNARY("abs", bits(__builtin_fabs(a)));
        UNARY("toint", (uint64_t) (int64_t) (int) a);
        UNARY("touint", (uint64_t) (unsigned) a);
        UNARY("tolong", (uint64_t) (long) a);
        UNARY("toulong", (uint64_t) (unsigned long) a);
        UNARY("lrint", (uint64_t) __builtin_lrint(a));
        UNARY("tofloat", bitsf((float) a));
        UNARY("fromflt", bits((double) (volatile float) { (float) a }));
        FROM_INT("fromint", bits((double) (int) x));
        FROM_INT("fromuint", bits((double) (unsigned) x));
        FROM_INT("fromlong", bits((double) (long) x));
        FROM_INT("fromulng", bits((double) (unsigned long) x));
        FROM_INT("fltlong", bitsf((float) (long) x));
        TERNARY("fmadd", bits(__builtin_fma(a, b, c)));
        TERNARY("fmsub", bits(__builtin_fma(a, b, -c)));
        TERNARY("fnmsub", bits(__builtin_fma(-a, b, c)));
        TERNARY("fnmadd", bits(-__builtin_fma(a, b, c)));
        // Single precision: narrowed operands, so its arithmetic and its NaN boxing are run too.
        begin("fadds");
        for (unsigned i = 0; i < N; i++) for (unsigned j = 0; j < N; j += 2) {
            volatile float a = (float) from_bits(vals[i]), b = (float) from_bits(vals[j]);
            feclearexcept(FE_ALL_EXCEPT);
            record(bitsf(a + b), i, j, 0);
            record(bitsf(a * b), i, j, 0);
            record(bitsf(a / b), i, j, 0);
            record(a < b, i, j, 0);
        }
        end();
    }
    return 0;
}
