// x86test: the integer instructions of x86 and x86-64 on awkward and random operands, one hash a group.
// For an engine that executes them another way than its reference does (the QEMU plug-in's x86 front end against
// TCG): the two transcripts must be the same. What Linux and its compilers seldom emit is here on purpose --
// rep with the direction flag set, repne scas, repe cmps, loop, cmpxchg8b, rotates whose flags are read,
// every condition after every kind of flag-setting instruction -- because other systems' code is full of it.
// Flags an instruction leaves undefined are masked. Build: gcc -O1 -mno-red-zone -static (as 32- or 64-bit).
// x86test -v prints every result instead of a hash.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

typedef unsigned long W;
#define FL 0x8d5UL              /* CF PF AF ZF SF OF */
#ifdef __x86_64__
#define BITS 64
#else
#define BITS 32
#endif

static uint64_t seed = 0x9e3779b97f4a7c15ull;
static int verbose;
static uint32_t hash;
static const char *group;

static W rnd(void)
{
    seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17;
    return (W)(seed * 0x2545f4914f6cdd1dull >> 16);
}

/* Operands that sit on the edges, and random ones. */
static W val(void)
{
    static const W edge[] = { 0, 1, 2, (W)-1, (W)-2, 0x7f, 0x80, 0xff, 0x7fff, 0x8000, 0xffff,
                              0x7fffffff, 0x80000000, 0xffffffff, (W)1 << (BITS - 1), ~((W)1 << (BITS - 1)) };
    W r = rnd();
    return (r & 3) ? rnd() : edge[(r >> 2) % (sizeof(edge) / sizeof(edge[0]))];
}

static void mix(W v)
{
    if (verbose) {
        printf(" %lx", v);
    }
    hash = (hash ^ (uint32_t)v) * 16777619u;
#if BITS == 64
    hash = (hash ^ (uint32_t)(v >> 32)) * 16777619u;
#endif
}

static void begin(const char *name)
{
    group = name;
    hash = 2166136261u;
    if (verbose) {
        printf("X86TEST %s:", name);
    }
}

static void end(void)
{
    if (verbose) {
        printf("\n");
    } else {
        printf("X86TEST %s %08x\n", group, hash);
    }
}

#define N 300
#define FLAGS_IN "push %[fi]\n popf\n"
#define FLAGS_OUT "\n pushf\n pop %[fo]"

/* op src, dst with the flags going in and coming out; M the size's operand modifier */
#define BIN(insn, M, mask) do {                                                         \
        for (int i = 0; i < N; i++) {                                                   \
            W a = val(), b = val(), fi = rnd() & FL, fo;                                \
            __asm__ volatile(FLAGS_IN insn " %" M "[b], %" M "[a]" FLAGS_OUT            \
                             : [a] "+q" (a), [b] "+q" (b), [fo] "=&r" (fo) : [fi] "r" (fi) : "cc"); \
            mix(a); mix(b); mix(fo & (mask));                                           \
        }                                                                               \
    } while (0)
#define UN(insn, M, mask) do {                                                          \
        for (int i = 0; i < N; i++) {                                                   \
            W a = val(), fi = rnd() & FL, fo;                                           \
            __asm__ volatile(FLAGS_IN insn " %" M "[a]" FLAGS_OUT                       \
                             : [a] "+q" (a), [fo] "=&r" (fo) : [fi] "r" (fi) : "cc");   \
            mix(a); mix(fo & (mask));                                                   \
        }                                                                               \
    } while (0)
/* a shift or rotate by cl: nothing changes for a count of zero, and only then is every flag defined */
#define SHCL(insn, M, bits, defined) do {                                               \
        for (int i = 0; i < N; i++) {                                                   \
            W a = val(), c = rnd() & 0xff, fi = rnd() & FL, fo;                         \
            unsigned n = c & ((bits) == 64 ? 63 : 31);                                  \
            __asm__ volatile(FLAGS_IN insn " %%cl, %" M "[a]" FLAGS_OUT                 \
                             : [a] "+q" (a), [fo] "=&r" (fo) : "c" (c), [fi] "r" (fi) : "cc"); \
            mix(a); mix(fo & (n == 0 ? FL : n == 1 ? (defined) | 0x800 : (defined)));   \
        }                                                                               \
    } while (0)
#define SHI(insn, cnt, M, mask) do {                                                    \
        for (int i = 0; i < N; i++) {                                                   \
            W a = val(), fi = rnd() & FL, fo;                                           \
            __asm__ volatile(FLAGS_IN insn " $" #cnt ", %" M "[a]" FLAGS_OUT            \
                             : [a] "+q" (a), [fo] "=&r" (fo) : [fi] "r" (fi) : "cc");   \
            mix(a); mix(fo & (mask));                                                   \
        }                                                                               \
    } while (0)

#if BITS == 64
#define SIZES(X) X("b", 8) X("w", 16) X("k", 32) X("q", 64)
#define WIDE(X) X("k", 32) X("q", 64)
#define INCW "incq"
#define JCXZ "jrcxz"
#define STK1 "(%%rsp)"
#else
#define SIZES(X) X("b", 8) X("w", 16) X("k", 32)
#define WIDE(X) X("k", 32)
#define INCW "incl"
#define JCXZ "jecxz"
#define STK1 "(%%esp)"
#endif

static void arith(void)
{
#define X_ADD(M, b) BIN("add", M, FL);
    begin("add"); SIZES(X_ADD) end();
#define X_ADC(M, b) BIN("adc", M, FL);
    begin("adc"); SIZES(X_ADC) end();
#define X_SUB(M, b) BIN("sub", M, FL);
    begin("sub"); SIZES(X_SUB) end();
#define X_SBB(M, b) BIN("sbb", M, FL);
    begin("sbb"); SIZES(X_SBB) end();
#define X_CMP(M, b) BIN("cmp", M, FL);
    begin("cmp"); SIZES(X_CMP) end();
#define X_AND(M, b) BIN("and", M, FL & ~0x10);
    begin("and"); SIZES(X_AND) end();
#define X_OR(M, b) BIN("or", M, FL & ~0x10);
    begin("or"); SIZES(X_OR) end();
#define X_XOR(M, b) BIN("xor", M, FL & ~0x10);
    begin("xor"); SIZES(X_XOR) end();
#define X_TEST(M, b) BIN("test", M, FL & ~0x10);
    begin("test"); SIZES(X_TEST) end();
#define X_INC(M, b) UN("inc", M, FL);
    begin("inc"); SIZES(X_INC) end();
#define X_DEC(M, b) UN("dec", M, FL);
    begin("dec"); SIZES(X_DEC) end();
#define X_NEG(M, b) UN("neg", M, FL);
    begin("neg"); SIZES(X_NEG) end();
#define X_NOT(M, b) UN("not", M, FL);
    begin("not"); SIZES(X_NOT) end();
#define X_XADD(M, b) BIN("xadd", M, FL);
    begin("xadd"); SIZES(X_XADD) end();
#define X_IMUL(M, b) BIN("imul", M, 0x801);
    begin("imul2"); WIDE(X_IMUL) BIN("imul", "w", 0x801); end();
#define X_BSF(M, b) BIN("bsf", M, 0x40);
    begin("bsf"); WIDE(X_BSF) end();
#define X_BSR(M, b) BIN("bsr", M, 0x40);
    begin("bsr"); WIDE(X_BSR) end();
#define X_BT(M, b) BIN("bt", M, 0x41); BIN("bts", M, 0x41); BIN("btr", M, 0x41); BIN("btc", M, 0x41);
    begin("bt"); WIDE(X_BT) end();
#define X_BTI(M, b) SHI("bt", 5, M, 0x41); SHI("bts", 31, M, 0x41); SHI("btr", 0, M, 0x41); SHI("btc", 17, M, 0x41);
    begin("bt-imm"); WIDE(X_BTI) end();
}

static void shifts(void)
{
    /* The carry and the result's flags are defined; the overflow for a count of one; AF never. */
#define X_SH1(M, b) SHI("shl", 1, M, 0x8c5); SHI("shr", 1, M, 0x8c5); SHI("sar", 1, M, 0x8c5);
    begin("shift-1"); SIZES(X_SH1) end();
#define X_SH7(M, b) SHI("shl", 7, M, 0xc5); SHI("shr", 7, M, 0xc5); SHI("sar", 7, M, 0xc5);
    begin("shift-7"); SIZES(X_SH7) end();
#define X_SHC(M, b) SHCL("shl", M, b, 0xc5); SHCL("shr", M, b, 0xc5); SHCL("sar", M, b, 0xc5);
    begin("shift-cl"); SIZES(X_SHC) end();
    /* A rotate changes the carry and, for a count of one, the overflow; the rest stay. */
#define X_RO1(M, b) SHI("rol", 1, M, FL); SHI("ror", 1, M, FL);
    begin("rotate-1"); SIZES(X_RO1) end();
#define X_RO5(M, b) SHI("rol", 5, M, FL & ~0x800); SHI("ror", 13, M, FL & ~0x800);
    begin("rotate-n"); SIZES(X_RO5) end();
#define X_ROC(M, b) SHCL("rol", M, b, FL & ~0x800); SHCL("ror", M, b, FL & ~0x800);
    begin("rotate-cl"); SIZES(X_ROC) end();
    /* ... and one whose flags nothing reads, between two that set them all */
    begin("rotate-dead");
    for (int i = 0; i < N; i++) {
        W a = val(), b = val(), fo;
        __asm__ volatile("add %[b], %[a]\n rol $7, %k[a]\n ror $3, %[b]\n inc %[b]\n xor %[b], %[a]" FLAGS_OUT
                         : [a] "+q" (a), [b] "+q" (b), [fo] "=&r" (fo) : : "cc");
        mix(a); mix(b); mix(fo & (FL & ~0x10));
    }
    end();
    begin("shld-shrd");
    for (int i = 0; i < N; i++) {
        W a = val(), b = val(), c = rnd() & 0xff, fi = rnd() & FL, fo;
        unsigned n = c & 31;
        __asm__ volatile(FLAGS_IN "shld %%cl, %k[b], %k[a]" FLAGS_OUT
                         : [a] "+q" (a), [fo] "=&r" (fo) : [b] "q" (b), "c" (c), [fi] "r" (fi) : "cc");
        mix(a); mix(fo & (n == 0 ? FL : n == 1 ? 0x8c5 : 0xc5));
        a = val();
        __asm__ volatile(FLAGS_IN "shrd %%cl, %k[b], %k[a]" FLAGS_OUT
                         : [a] "+q" (a), [fo] "=&r" (fo) : [b] "q" (b), "c" (c), [fi] "r" (fi) : "cc");
        mix(a); mix(fo & (n == 0 ? FL : n == 1 ? 0x8c5 : 0xc5));
        a = val();
        __asm__ volatile(FLAGS_IN "shld $11, %k[b], %k[a]\n shrd $3, %[b], %[a]" FLAGS_OUT
                         : [a] "+q" (a), [fo] "=&r" (fo) : [b] "q" (b), [fi] "r" (fi) : "cc");
        mix(a); mix(fo & 0xc5);
    }
    end();
}

static void muldiv(void)
{
    begin("mul-div");
    for (int i = 0; i < N; i++) {
        W a = val(), d, b = val(), fo;
        __asm__ volatile("mul %[b]" FLAGS_OUT : "+a" (a), "=d" (d), [fo] "=&r" (fo) : [b] "r" (b) : "cc");
        mix(a); mix(d); mix(fo & 0x801);
        a = val();
        __asm__ volatile("imul %[b]" FLAGS_OUT : "+a" (a), "=d" (d), [fo] "=&r" (fo) : [b] "r" (b) : "cc");
        mix(a); mix(d); mix(fo & 0x801);
        a = val();
        __asm__ volatile("mulb %b[b]" FLAGS_OUT : "+a" (a), [fo] "=&r" (fo) : [b] "q" (b) : "cc");
        mix(a); mix(fo & 0x801);
        a = val();
        __asm__ volatile("imulw %w[b]" FLAGS_OUT : "+a" (a), "=d" (d), [fo] "=&r" (fo) : [b] "q" (b) : "cc");
        mix(a); mix(d & 0xffff); mix(fo & 0x801);
        a = val();
        __asm__ volatile("mull %k[b]" FLAGS_OUT : "+a" (a), "=d" (d), [fo] "=&r" (fo) : [b] "q" (b) : "cc");
        mix(a); mix(d); mix(fo & 0x801);
        a = val();
        __asm__ volatile("imul $-77, %k[b], %k[a]" FLAGS_OUT : [a] "+a" (a), [fo] "=&r" (fo) : [b] "q" (b) : "cc");
        mix(a); mix(fo & 0x801);
        /* a quotient that fits: the high half below the divisor, or the dividend's sign */
        b |= 3; a = val(); d = val() % b;
        __asm__ volatile("div %[b]" : "+a" (a), "+d" (d) : [b] "r" (b) : "cc");
        mix(a); mix(d);
        a = val(); b = ((b >> 1) | 5) & 0x7fffffff;
        __asm__ volatile("cltd\n idivl %k[b]" : "+a" (a), "=d" (d) : [b] "r" (b) : "cc");
        mix(a); mix(d);
        a = val() & 0x7fff;
        __asm__ volatile("divb %b[b]" : "+a" (a) : [b] "q" (b | 0x80) : "cc");
        mix(a);
        a = val();
        __asm__ volatile("cwtl\n cltd\n cbtw" : "+a" (a), "=d" (d) : : "cc");
        mix(a); mix(d);
        a = val();
        __asm__ volatile("bswap %k[a]" : [a] "+q" (a));
        mix(a);
        a = val(); b = val();
        __asm__ volatile("movzbl %b[b], %k[a]\n movswl %w[a], %k[b]\n movsbw %b[b], %w[a]\n xchg %k[a], %k[b]\n"
                         "mov %%ah, %%bl\n mov %%bl, %%ah" : [a] "+a" (a), [b] "+b" (b));
        mix(a); mix(b);
    }
    end();
}

/*
 * Every condition, read three ways, after each kind of instruction that sets flags. @which: 2 for all of
 * them, 1 without the parity, 0 for the carry and zero alone (after bt, which defines no other).
 */
#define COND1(cc, setup)                                                                \
    {                                                                                   \
        W a = va, b = vb, r = 0, s = 0x55, t = 3;                                       \
        __asm__ volatile(setup "\n set" #cc " %b[r]\n cmov" #cc " %k[a], %k[s]\n j" #cc " 1f\n " INCW " %[t]\n 1:" \
                         : [a] "+q" (a), [b] "+q" (b), [r] "+q" (r), [s] "+q" (s), [t] "+m" (t) \
                         : [m] "r" (m) : "cc", "memory");                               \
        mix(r); mix(s); mix(t); mix(m[0]); mix(m[1]);                                   \
    }
#define AFTER(name, setup, which) do {                                                  \
        begin("cond-" name);                                                            \
        for (int i = 0; i < 60; i++) {                                                  \
            W va = val(), vb = (i & 3) == 3 ? va : val();                               \
            m[0] = va ^ vb; m[1] = 0;                                                   \
            COND1(b, setup) COND1(ae, setup) COND1(e, setup) COND1(ne, setup)           \
            if (which) {                                                                \
                COND1(o, setup) COND1(no, setup) COND1(be, setup) COND1(a, setup)       \
                COND1(s, setup) COND1(ns, setup) COND1(l, setup) COND1(ge, setup)       \
                COND1(le, setup) COND1(g, setup)                                        \
            }                                                                           \
            if (which > 1) {                                                            \
                COND1(p, setup) COND1(np, setup)                                        \
            }                                                                           \
        }                                                                               \
        end();                                                                          \
    } while (0)

static void conds(void)
{
    static W cell[4];
    W *m = cell;

    AFTER("cmp8", "cmp %b[b], %b[a]", 2); AFTER("cmp16", "cmp %w[b], %w[a]", 2);
    AFTER("cmp32", "cmp %k[b], %k[a]", 2); AFTER("cmpw", "cmp %[b], %[a]", 2);
    AFTER("sub32", "sub %k[b], %k[a]", 2); AFTER("add8", "add %b[b], %b[a]", 2);
    AFTER("add32", "add %k[b], %k[a]", 2); AFTER("addw", "add %[b], %[a]", 2);
    AFTER("test8", "test %b[b], %b[a]", 2); AFTER("test32", "test %k[b], %k[a]", 2);
    AFTER("and16", "and %w[b], %w[a]", 2); AFTER("xor32", "xor %k[b], %k[a]", 2);
    AFTER("inc32", "add %k[b], %k[b]\n inc %k[a]", 2); AFTER("dec8", "sub %k[a], %k[b]\n dec %b[a]", 2);
    AFTER("neg32", "neg %k[a]", 2); AFTER("adc32", "add %k[b], %k[b]\n adc %k[b], %k[a]", 2);
    AFTER("sbb32", "cmp %k[a], %k[b]\n sbb %k[b], %k[a]", 2);
    AFTER("shl32", "shl $1, %k[a]", 2); AFTER("sar32", "sar $1, %k[a]", 2);
    AFTER("shr8", "shr $1, %b[a]", 2);
    AFTER("bt32", "cmp %k[b], %k[a]\n bt %k[b], %k[a]", 0);
    AFTER("bts32", "test %k[b], %k[a]\n bts $3, %k[a]", 0);
    AFTER("imul32", "imul %k[b], %k[a]\n seto %b[b]\n movzbl %b[b], %k[b]\n cmp $1, %k[b]", 2);
    /* the same with a load, a store or a push between the compare and the condition */
    AFTER("cmp-load", "cmp %k[b], %k[a]\n mov (%[m]), %[b]", 2);
    AFTER("sub-mem", "sub %k[b], (%[m])\n mov %k[b], 4(%[m])", 2);
    AFTER("cmp-mem", "cmp (%[m]), %k[a]\n push %[a]\n pop %[b]", 2);
    AFTER("add-mem", "add %k[a], (%[m])", 2);
    AFTER("test-mem", "testb $0x81, (%[m])", 2);
    AFTER("dec-mem", "cmp %k[b], %k[a]\n decl (%[m])", 1);
    AFTER("xadd-mem", "lock; xadd %k[b], (%[m])", 2);
    AFTER("cmpxchg-mem", "mov %k[a], %%eax\n lock; cmpxchg %k[b], (%[m])", 2);
}

/* Three pages, the middle one's ends being where an access runs over. */
static uint8_t *page;
#define PG 4096

static void fill(void)
{
    uint32_t *q = (uint32_t *)page;

    for (int i = 0; i < 3 * PG / 4; i++) {
        q[i] = rnd() >> 3;
    }
}

static void sum(void)
{
    const uint32_t *q = (const uint32_t *)page;
    uint32_t s = 2166136261u;

    for (int i = 0; i < 3 * PG / 4; i++) {
        s = (s ^ q[i]) * 16777619u;
    }
    if (verbose) {
        printf(" [%08x]", s);
    }
    hash = (hash ^ s) * 16777619u;
}

static void strings(void)
{
    static const int counts[] = { 0, 1, 2, 3, 7, 8, 15, 16, 17, 63, 64, 100, 1000, 4096, 4200 };
    begin("rep-movs");
    for (unsigned k = 0; k < sizeof(counts) / sizeof(counts[0]); k++) {
        for (int v = 0; v < 12; v++) {
            W n = counts[k], si, di, c;
            /* forward and backward, apart, and overlapping by a little either way */
            int back = v & 1, dist = (int[]){ 3000, 1, 3, 8, -1, -5 }[v >> 1];
            fill();
            /* (going down, the registers start at the last element) */
            si = (W)(page + PG - 40 + (v & 2 ? 0 : 7) + (back && n ? n - 1 : 0)); di = si + dist; c = n;
            if (back) {
                __asm__ volatile("std\n rep movsb\n cld" : "+S" (si), "+D" (di), "+c" (c) : : "cc", "memory");
            } else {
                __asm__ volatile("rep movsb" : "+S" (si), "+D" (di), "+c" (c) : : "cc", "memory");
            }
            mix(si - (W)page); mix(di - (W)page); mix(c); sum();
            fill();
            si = (W)(page + PG - 64); di = si + (dist > 100 ? dist : dist * 4); c = n / 4;
            if (back) {
                si += 4400; di += 4400;
                __asm__ volatile("std\n rep movsl\n cld" : "+S" (si), "+D" (di), "+c" (c) : : "cc", "memory");
            } else {
                __asm__ volatile("rep movsl" : "+S" (si), "+D" (di), "+c" (c) : : "cc", "memory");
            }
            mix(si - (W)page); mix(di - (W)page); mix(c); sum();
            si = (W)(page + 100); di = (W)(page + PG + 3); c = n / 2;
            __asm__ volatile("rep movsw\n movsb\n movsw\n movsl" : "+S" (si), "+D" (di), "+c" (c) : : "cc", "memory");
            mix(si - (W)page); mix(di - (W)page); mix(c); sum();
        }
    }
    end();
    begin("rep-stos-lods");
    for (unsigned k = 0; k < sizeof(counts) / sizeof(counts[0]); k++) {
        W n = counts[k], di, si, c, a = val();
        fill();
        di = (W)(page + PG - 33); c = n;
        __asm__ volatile("rep stosb" : "+D" (di), "+c" (c) : "a" (a) : "cc", "memory");
        mix(di - (W)page); mix(c);
        di = (W)(page + 2 * PG + 2001); c = n / 4;
        __asm__ volatile("std\n rep stosl\n stosw\n stosb\n cld" : "+D" (di), "+c" (c) : "a" (a) : "cc", "memory");
        mix(di - (W)page); mix(c); sum();
        si = (W)(page + PG - 5); c = (n & 15) + 1;
        __asm__ volatile("rep lodsb\n lodsw\n lodsl" : "+S" (si), "+c" (c), "+a" (a) : : "cc", "memory");
        mix(si - (W)page); mix(c); mix(a);
    }
    end();
    begin("scas-cmps");
    for (int i = 0; i < 200; i++) {
        W di, si, c, a, fo;
        int at = rnd() % 300;
        fill();
        memset(page + PG - 100, 'x', 400);
        memcpy(page + 2 * PG - 100, page + PG - 100, 400);
        if (i & 1) {
            page[PG - 100 + at] = 0;
        }
        if (i & 2) {
            page[2 * PG - 100 + at / 2] ^= 0x40;
        }
        di = (W)(page + PG - 100); c = (i & 4) ? at / 2 + 1 : 350; a = 0;
        __asm__ volatile("repne scasb" FLAGS_OUT : "+D" (di), "+c" (c), [fo] "=&r" (fo) : "a" (a) : "cc", "memory");
        mix(di - (W)page); mix(c); mix(fo & FL);
        di = (W)(page + PG - 100); c = 200; a = 0x7878;
        __asm__ volatile("repe scasw" FLAGS_OUT : "+D" (di), "+c" (c), [fo] "=&r" (fo) : "a" (a) : "cc", "memory");
        mix(di - (W)page); mix(c); mix(fo & FL);
        si = (W)(page + PG - 100); di = (W)(page + 2 * PG - 100); c = 380;
        __asm__ volatile("repe cmpsb" FLAGS_OUT : "+S" (si), "+D" (di), "+c" (c), [fo] "=&r" (fo) : : "cc", "memory");
        mix(si - (W)page); mix(di - (W)page); mix(c); mix(fo & FL);
        si = (W)(page + PG - 100); di = (W)(page + 2 * PG - 100); c = 90;
        __asm__ volatile("repne cmpsl\n cmpsb\n scasb" FLAGS_OUT
                         : "+S" (si), "+D" (di), "+c" (c), [fo] "=&r" (fo) : "a" (a) : "cc", "memory");
        mix(si - (W)page); mix(di - (W)page); mix(c); mix(fo & FL);
        /* a count of zero leaves the flags as they were */
        si = (W)(page + 5); di = (W)(page + 9); c = 0; a = rnd() & FL;
        __asm__ volatile("push %[fi]\n popf\n repe cmpsb\n repne scasb" FLAGS_OUT
                         : "+S" (si), "+D" (di), "+c" (c), [fo] "=&r" (fo) : [fi] "r" (a) : "cc", "memory");
        mix(si - (W)page); mix(c); mix(fo & FL);
    }
    end();
}

static void memory(void)
{
    begin("locked");
    for (int i = 0; i < N; i++) {
        /* across the end of a page too */
        uint8_t *p = page + PG - (i % 9);
        W a = val(), b = val(), fo;
        fill();
        __asm__ volatile("lock; add %k[a], (%[p])\n lock; xadd %k[b], 4(%[p])\n xchg %[a], 8(%[p])\n"
                         "lock; incl (%[p])\n lock; negb 1(%[p])\n lock; notw 2(%[p])\n lock; sub %b[b], 3(%[p])\n"
                         "lock; btsl $9, (%[p])\n lock; btrw $3, 6(%[p])\n lock; orl $0x1000, 12(%[p])\n"
                         "lock; andb $0x77, 13(%[p])\n lock; xor %[a], 16(%[p])\n lock; decw 20(%[p])" FLAGS_OUT
                         : [a] "+q" (a), [b] "+q" (b), [fo] "=&r" (fo) : [p] "r" (p) : "cc", "memory");
        mix(a); mix(b); mix(fo & 0x8c5); sum();
        a = val(); b = val();
        memcpy(p + 30, &a, sizeof(a));
        if (i & 1) {
            a ^= 0x100;
        }
        __asm__ volatile("lock; cmpxchg %[b], 30(%[p])" FLAGS_OUT
                         : "+a" (a), [fo] "=&r" (fo) : [b] "q" (b), [p] "r" (p) : "cc", "memory");
        mix(a); mix(fo & FL);
        __asm__ volatile("cmpxchg %b[b], 31(%[p])\n cmpxchg %w[b], 33(%[p])" FLAGS_OUT
                         : "+a" (a), [fo] "=&r" (fo) : [b] "q" (b), [p] "r" (p) : "cc", "memory");
        mix(a); mix(fo & FL); sum();
        {
            W d = val(), c = val(), bb = val();
            a = val();
            if (i & 2) {
                memcpy(p + 40, &a, 4); memcpy(p + 44, &d, 4);
            }
            __asm__ volatile("lock; cmpxchg8b 40(%[p])" FLAGS_OUT
                             : "+a" (a), "+d" (d), [fo] "=&r" (fo)
                             : "b" (bb), "c" (c), [p] "S" (p) : "cc", "memory");
            mix(a); mix(d); mix(fo & 0x40);
            __asm__ volatile("cmpxchg8b 41(%[p])" FLAGS_OUT
                             : "+a" (a), "+d" (d), [fo] "=&r" (fo) : "b" (bb), "c" (c), [p] "S" (p) : "cc", "memory");
            mix(a); mix(d); mix(fo & 0x40); sum();
        }
    }
    end();
    begin("memory-ops");
    for (int i = 0; i < N; i++) {
        uint8_t *p = page + PG - (i % 11);
        W a = val(), b = val(), c = rnd(), fo;
        fill();
        __asm__ volatile("add %k[a], (%[p])\n adc %k[b], 4(%[p])\n sbb (%[p]), %k[a]\n rolb $3, 9(%[p])\n"
                         "shll %%cl, 12(%[p])\n sarw $2, 17(%[p])\n notl 20(%[p])\n negw 24(%[p])\n incb 27(%[p])\n"
                         "imul 4(%[p]), %k[b]\n xor %b[a], 31(%[p])\n movzwl 33(%[p]), %k[a]\n movsbl 36(%[p]), %k[b]\n"
                         "btcl $7, 40(%[p])\n shrdl $5, %k[a], 44(%[p])\n rorl %%cl, 48(%[p])\n cmp %k[a], 52(%[p])\n"
                         "setg 56(%[p])\n cmovb 57(%[p]), %k[a]\n movl $0x12345678, 61(%[p])\n movw $0xabcd, 66(%[p])\n"
                         "lea 5(%[a], %[b], 4), %[b]\n mov %b[b], 70(%[p], %[c], 2)" FLAGS_OUT
                         : [a] "+q" (a), [b] "+q" (b), [fo] "=&r" (fo) : [p] "r" (p), [c] "c" (c & 15) : "cc", "memory");
        mix(a); mix(b); mix(fo & 0xc5); sum();
    }
    end();
}

/* The stack, calls, loop and the flags register. */
__asm__(".text\n helper_ret:\n"
#ifdef __x86_64__
        " mov 8(%rsp), %rax\n add 16(%rsp), %rax\n ret $16\n"
#else
        " mov 4(%esp), %eax\n add 8(%esp), %eax\n ret $8\n"
#endif
       );

static void control(void)
{
    begin("stack-control");
    for (int i = 0; i < N; i++) {
        W a = val(), b = val(), c = (rnd() & 31) + 1, d = 0, fi = rnd() & FL, fo;
        __asm__ volatile("push %[a]\n push %[b]\n call helper_ret\n"
                         "push $-5\n pop %[d]\n pushf\n pop %[fo]\n push %[fi]\n popf\n pushf\n pop %[fi]\n"
                         "1: add %[c], %[d]\n loop 1b\n " JCXZ " 2f\n add $99, %[d]\n 2: lea (%[d], %[d], 2), %[d]"
                         : [a] "+a" (a), [b] "+b" (b), [c] "+c" (c), [d] "+d" (d), [fi] "+S" (fi), [fo] "=&D" (fo)
                         : : "cc", "memory");
        mix(a); mix(b); mix(c); mix(d); mix(fi & FL);
        (void)fo;
        {
            /* the carry set, cleared and turned; the flags through ah; a pop to memory that uses the stack pointer */
            W v = val(), w = val(), f1, f2, f3, cell[2] = { 0, 0 };
            __asm__ volatile("cmp %[w], %[v]\n stc\n adc $0, %[v]\n clc\n sbb $0, %[w]\n cmc\n pushf\n pop %[f1]\n"
                             "cmp %[v], %[w]\n lahf\n mov %%eax, %k[f2]\n xor $0x4100, %%eax\n sahf\n"
                             "push %[v]\n pop (%[p])\n push %[w]\n push %[v]\n pop " STK1 "\n pop %[v]\n"
                             /* what sahf left, read here: a flag after anything the compiler put between */
                             /* two statements is the stack pointer's, which is another one at every start */
                             "pushf\n pop %[f3]"
                             : [v] "+b" (v), [w] "+c" (w), [f1] "=&S" (f1), [f2] "=&D" (f2), [f3] "=&a" (f3)
                             : [p] "d" (cell) : "cc", "memory");
            mix(v); mix(w); mix(f1 & FL); mix(f2 & 0xd500); mix(cell[0]); mix(f3 & 0xd5);
        }
#ifndef __x86_64__
        {
            /* segment registers, as a 32-bit system's entry and exit code handles them */
            W s = 0, t = 0;
            __asm__ volatile("push %%ds\n push %%es\n push %%fs\n push %%gs\n mov %%ds, %k[s]\n mov %w[s], %%es\n"
                             "pop %%gs\n pop %%fs\n pop %%es\n pop %%ds\n mov %%es, %k[t]"
                             : [s] "+r" (s), [t] "+r" (t) : : "cc", "memory");
            mix(s == t);
        }
#endif
    }
    end();
}

int main(int argc, char **argv)
{
    verbose = argc > 1 && !strcmp(argv[1], "-v");
    page = mmap(NULL, 3 * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (page == MAP_FAILED) {
        return 1;
    }
    arith();
    shifts();
    muldiv();
    conds();
    strings();
    memory();
    control();
    printf("X86TEST-END\n");
    return 0;
}
