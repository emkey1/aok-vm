// x86_newer: integer instructions the AOK engine's x86 front end took over from TCG on 2026-10-15 (AOK VM's own
// test): bt/bts/btr/btc of memory by a register (a bit string: offsets past the operand, both signs), plain and
// locked; cmpxchg16b, plain and locked; adc, sbb and cmov at 16 bits, of registers and memory; popcnt; verr and
// verw. One hash a group, on awkward and random operands. The oracle is the same binary run natively (camd):
// its lines must be these.
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef unsigned long W;
#define FL 0x8d5UL              /* CF PF AF ZF SF OF */
#define N 400
static uint64_t seed = 0x2545f4914f6cdd1dull;
static uint32_t hash;
static W rnd(void)
{
    seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17;
    return (W)(seed * 0x9e3779b97f4a7c15ull >> 11);
}
static W val(void)
{
    static const W edge[] = { 0, 1, 2, (W)-1, (W)-2, 0x7f, 0x80, 0xff, 0x7fff, 0x8000, 0xffff,
                              0x7fffffff, 0x80000000, 0xffffffff, (W)1 << 63, ~((W)1 << 63) };
    W r = rnd();
    return (r & 3) ? rnd() : edge[(r >> 2) % (sizeof(edge) / sizeof(edge[0]))];
}
static void mix(W v)
{
    for (int i = 0; i < 8; i++, v >>= 8)
        hash = (hash ^ (v & 0xff)) * 0x01000193u;
}
static void begin(void) { hash = 0x811c9dc5u; }
static void end(const char *g) { printf("X86NEW %s %08x\n", g, hash); }

static uint8_t buf[4096] __attribute__((aligned(64)));
static void fill(void)
{
    for (unsigned i = 0; i < sizeof(buf); i += 8) {
        W v = rnd();
        memcpy(buf + i, &v, 8);
    }
}
static void sum(void)
{
    for (unsigned i = 0; i < sizeof(buf); i += 8) {
        W v;
        memcpy(&v, buf + i, 8);
        mix(v);
    }
}

int main(void)
{
    uint8_t *mid = buf + 2048;

    begin();                    /* a bit string: the offset reaches past the operand, both ways */
    for (int i = 0; i < N; i++) {
        W o = (rnd() % 16000) - 8000, fo;
        fill();
        __asm__ volatile("btq %[o], (%[p])\n pushf\n pop %[fo]" : [fo] "=&r" (fo) : [o] "r" (o), [p] "r" (mid) : "cc", "memory");
        mix(fo & 1);
        __asm__ volatile("btsq %[o], (%[p])\n btrl %k[o], 8(%[p])\n btcq %[o], 3(%[p])\n pushf\n pop %[fo]"
                         : [fo] "=&r" (fo) : [o] "r" (o), [p] "r" (mid) : "cc", "memory");
        mix(fo & 1);
        __asm__ volatile("lock btsq %[o], 16(%[p])\n lock btrl %k[o], (%[p])\n lock btcq %[o], 40(%[p])\n pushf\n pop %[fo]"
                         : [fo] "=&r" (fo) : [o] "r" (o), [p] "r" (mid) : "cc", "memory");
        mix(fo & 1); sum();
    }
    end("bitstring");

    begin();                    /* cmpxchg16b */
    for (int i = 0; i < N; i++) {
        W a = val(), d = val(), b = val(), c = val(), fo;
        uint8_t *p = buf + 64 * (rnd() % 32);
        if (i & 1) {
            memcpy(p, &a, 8); memcpy(p + 8, &d, 8);
        } else {
            fill();
        }
        if (i & 2) {
            __asm__ volatile("lock cmpxchg16b (%[p])\n pushf\n pop %[fo]"
                             : "+a" (a), "+d" (d), [fo] "=&r" (fo) : "b" (b), "c" (c), [p] "r" (p) : "cc", "memory");
        } else {
            __asm__ volatile("cmpxchg16b (%[p])\n pushf\n pop %[fo]"
                             : "+a" (a), "+d" (d), [fo] "=&r" (fo) : "b" (b), "c" (c), [p] "r" (p) : "cc", "memory");
        }
        mix(a); mix(d); mix(fo & 0x40);
        W x, y;
        memcpy(&x, p, 8); memcpy(&y, p + 8, 8);
        mix(x); mix(y);
    }
    end("cmpxchg16b");

    begin();                    /* 16 bits: adc, sbb, cmov, of registers and memory */
    for (int i = 0; i < N; i++) {
        W a = val(), b = val(), fi = rnd() & FL, fo;
        fill();
        __asm__ volatile("push %[fi]\n popf\n adcw %w[b], %w[a]\n sbbw $-3, %w[a]\n adcw $7, 10(%[p])\n"
                         "sbbw %w[b], 20(%[p])\n adcw 30(%[p]), %w[b]\n pushf\n pop %[fo]"
                         : [a] "+q" (a), [b] "+q" (b), [fo] "=&r" (fo) : [fi] "r" (fi), [p] "r" (mid) : "cc", "memory");
        mix(a); mix(b); mix(fo & FL);
        __asm__ volatile("push %[fi]\n popf\n cmovbw %w[b], %w[a]\n cmovow 40(%[p]), %w[b]\n cmovsw %w[a], %w[b]\n"
                         "cmovgw 42(%[p]), %w[a]"
                         : [a] "+q" (a), [b] "+q" (b) : [fi] "r" (fi), [p] "r" (mid) : "cc", "memory");
        mix(a); mix(b); sum();
    }
    end("w16");

    unsigned ea, eb, ec, ed;
    __asm__ volatile("cpuid" : "=a" (ea), "=b" (eb), "=c" (ec), "=d" (ed) : "a" (1), "c" (0));
    begin();                    /* popcnt, where the CPU has it */
    if (ec & (1u << 23)) {
        for (int i = 0; i < N; i++) {
            W a = val(), r, r2, fo;
            __asm__ volatile("popcnt %[a], %[r]\n popcntl %k[a], %k[r2]\n pushf\n pop %[fo]"
                             : [r] "=&r" (r), [r2] "=&r" (r2), [fo] "=&r" (fo) : [a] "r" (a) : "cc");
            mix(r); mix(r2); mix(fo & FL);
            buf[0] = (uint8_t)a;
            __asm__ volatile("popcntq (%[p]), %[r]" : [r] "=r" (r) : [p] "r" (&a) : "memory");
            mix(r);
        }
    }
    end("popcnt");

    begin();                    /* verr and verw: this program's own selectors, and ones that are not */
    {
        unsigned short ds, cs, sels[] = { 0, 3, 0x10, 0x2b, 0x33, 0x23, 0xfff8 };
        __asm__ volatile("mov %%ds, %0\n mov %%cs, %1" : "=r" (ds), "=r" (cs));
        for (unsigned i = 0; i < sizeof(sels) / sizeof(sels[0]) + 2; i++) {
            unsigned short s = i == 0 ? ds : i == 1 ? cs : sels[i - 2];
            W fr, fw;
            __asm__ volatile("verr %w[s]\n pushf\n pop %[fr]\n verw %w[s]\n pushf\n pop %[fw]"
                             : [fr] "=&r" (fr), [fw] "=&r" (fw) : [s] "r" (s) : "cc");
            mix(fr & 0x40); mix(fw & 0x40);
        }
    }
    end("verr-verw");
    return 0;
}
