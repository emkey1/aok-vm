/*
 * fpstress -- the FP ops on operands chosen to sit at the edges a translator's fast path draws: exponents
 * near the bottom and top of the range, zeros, denormals, infinities, NaNs, values with few mantissa bits
 * (so that many results are exact), in random rounding modes and with random sticky bits. FPSCR is read
 * after every op and hashed with the result (the enables stay off: a trap would be a SIGFPE); one line per 200000 ops, on stderr (the kit's timeit discards stdout). Two engines must
 * print the same.
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
static uint64_t s = 0x9e3779b97f4a7c15ull;
static uint64_t rnd(void) { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s; }
static double d(uint64_t b) { double x; memcpy(&x, &b, 8); return x; }
static uint64_t bits(double x) { uint64_t b; memcpy(&b, &x, 8); return b; }
static double operand(void)
{
    uint64_t r = rnd(), e, m, sign = (r & 1) << 63;
    switch ((r >> 1) % 16) {
    case 0: return d(sign);                                 /* zero */
    case 1: return d(sign | 0x7ff0000000000000ull);         /* infinity */
    case 2: return d(sign | 0x7ff0000000000000ull | (rnd() & 0xfffffffffffffull) | 1); /* NaN */
    case 3: e = 0; break;                                   /* denormal */
    case 4: e = rnd() % 130; break;                         /* the bottom */
    case 5: e = 1900 + rnd() % 147; break;                  /* the top */
    case 6: e = 1023 + rnd() % 8 - 4; break;                /* near 1 */
    default: e = rnd() % 2047; break;
    }
    m = rnd() & 0xfffffffffffffull;
    if ((r >> 8) & 1) {
        m &= 0xff00000000000ull;                            /* few bits: many exact results */
    }
    if (e == 0 && m == 0) {
        m = 1;
    }
    return d(sign | e << 52 | m);
}
static uint64_t mix(uint64_t h, uint64_t v) { h ^= v; h *= 0x100000001b3ull; return h ^ (h >> 29); }
int main(void)
{
    uint64_t h = 0xcbf29ce484222325ull;
    for (long i = 1; i <= 2000000; i++) {
        double a = operand(), b = operand(), c = operand(), r = 0, f;
        uint64_t fs = rnd(), st;
        /* RN mostly to nearest; the sticky and enable bits at random, but never NI */
        uint32_t fpscr = (uint32_t)(fs >> 3) & 0xfff800f8;
        fpscr |= (fs & 7) < 5 ? 0 : (fs >> 40) & 3;
        fpscr &= ~0xf8u;            /* no enables: the kit's kernel runs processes with FP traps on */
        __asm__ volatile("mtfsf 0xff, %0" : : "f"(d(fpscr)));
        unsigned op = rnd() % 15;
        switch (op) {
        case 0: __asm__ volatile("fadd %0,%1,%2" : "=f"(r) : "f"(a), "f"(b)); break;
        case 1: __asm__ volatile("fsub %0,%1,%2" : "=f"(r) : "f"(a), "f"(b)); break;
        case 2: __asm__ volatile("fmul %0,%1,%2" : "=f"(r) : "f"(a), "f"(c)); break;
        case 3: __asm__ volatile("fdiv %0,%1,%2" : "=f"(r) : "f"(a), "f"(b)); break;
        case 4: __asm__ volatile("fsqrt %0,%1" : "=f"(r) : "f"(b)); break;
        case 5: __asm__ volatile("fmadd %0,%1,%2,%3" : "=f"(r) : "f"(a), "f"(c), "f"(b)); break;
        case 6: __asm__ volatile("fmsub %0,%1,%2,%3" : "=f"(r) : "f"(a), "f"(c), "f"(b)); break;
        case 7: __asm__ volatile("fnmadd %0,%1,%2,%3" : "=f"(r) : "f"(a), "f"(c), "f"(b)); break;
        case 8: __asm__ volatile("fnmsub %0,%1,%2,%3" : "=f"(r) : "f"(a), "f"(c), "f"(b)); break;
        case 9: __asm__ volatile("frsp %0,%1" : "=f"(r) : "f"(b)); break;
        case 10: __asm__ volatile("fctiw %0,%1" : "=f"(r) : "f"(b)); break;
        case 11: __asm__ volatile("fctiwz %0,%1" : "=f"(r) : "f"(b)); break;
        case 12: __asm__ volatile("fcmpu 1,%1,%2\n mfcr %0" : "=r"(st) : "f"(a), "f"(b) : "cr1"); r = d(st); break;
        case 13: __asm__ volatile("fsel %0,%1,%2,%3" : "=f"(r) : "f"(a), "f"(c), "f"(b)); break;
        case 14: __asm__ volatile("fadd. %0,%2,%3\n mfcr %1" : "=f"(r), "=r"(st) : "f"(a), "f"(b) : "cr1"); h = mix(h, st); break;
        }
        __asm__ volatile("mffs %0" : "=f"(f));
        h = mix(mix(mix(h, op), bits(r)), bits(f));
        if (i % 200000 == 0) {
            fprintf(stderr, "FPSTRESS %ld %016llx\n", i, (unsigned long long)h);
        }
    }
    return 0;
}
