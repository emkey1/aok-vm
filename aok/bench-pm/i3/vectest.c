/*
 * vectest -- the insns a user program has that the PowerPC front end took over from TCG on 2026-11-28: AltiVec's
 * aligned loads and stores (lvx, lvxl, stvx, stvxl) at every alignment and in both address forms, into and out
 * of every vector register, beside page ends and into a page that is not there; mfocrf and mtocrf with every
 * mask (QEMU does nothing for a mask of no bit or of several); and the hints and cache insns that do nothing or
 * touch memory for its faults only (dst, dstst, dss, dcba, dcbf, dcbst, icbi, isync, sync); and lswi and stswi
 * of every length, across a page's end too; the arithmetic that records overflow (addo and the rest, with
 * and without Rc, from every state of XER's SO, OV and CA); and bcctr and bcctrl on a CR bit. Results and the
 * faults' addresses are hashed, a line per 20000 rounds on stderr (the kit's timeit discards stdout), then a
 * line per fault. Two engines must print the same.
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <signal.h>
#include <setjmp.h>
#include <sys/mman.h>

static uint64_t s = 0x243f6a8885a308d3ull;
static uint64_t rnd(void) { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s; }
static uint64_t mix(uint64_t h, uint64_t v) { h ^= v; h *= 0x100000001b3ull; return h ^ (h >> 29); }

static sigjmp_buf jb;
static volatile uintptr_t fault_addr;
static volatile int fault_sig;
static void on_fault(int sig, siginfo_t *si, void *uc)
{
    fault_addr = (uintptr_t)si->si_addr;
    fault_sig = sig;
    siglongjmp(jb, 1);
}

/* Load 16 bytes at (a|0)+b into vector register 2 and copy them out through v2 with stvx to out (aligned). */
static void lvx_ab(const void *a, long b, unsigned char *out, int l)
{
    if (l) {
        __asm__ volatile("lvxl 2,%0,%1\n stvxl 2,0,%2" : : "b"(a), "r"(b), "r"(out) : "v2", "memory");
    } else {
        __asm__ volatile("lvx 2,%0,%1\n stvx 2,0,%2" : : "b"(a), "r"(b), "r"(out) : "v2", "memory");
    }
}
static void lvx_0b(const void *p, unsigned char *out)
{
    __asm__ volatile("lvx 3,0,%0\n stvx 3,0,%1" : : "r"(p), "r"(out) : "v3", "memory");
}
/* Store v4, loaded from in (aligned), at (a|0)+b. */
static void stvx_ab(const unsigned char *in, void *a, long b)
{
    __asm__ volatile("lvx 4,0,%0\n stvx 4,%1,%2" : : "r"(in), "b"(a), "r"(b) : "v4", "memory");
}
/* Every vector register in turn: v(n) loaded from in, stored to out. */
static void through(int n, const unsigned char *in, unsigned char *out)
{
    switch (n) {
#define T(n) case n: __asm__ volatile("lvx " #n ",0,%0\n stvx " #n ",0,%1" : : "r"(in), "r"(out) : "v" #n, "memory"); break;
    T(0) T(1) T(2) T(3) T(4) T(5) T(6) T(7) T(8) T(9) T(10) T(11) T(12) T(13) T(14) T(15)
    T(16) T(17) T(18) T(19)
#undef T
    }
}

/* mtocrf with mask crm from v, then the whole CR; and mfocrf with mask crm of a CR set to v. */
static uint32_t mtocrf(uint32_t v, unsigned crm, uint32_t before)
{
    register uint32_t rv __asm__("r5") = v;     /* the insn is written out below: mtocrf m,r5 */
    uint32_t cr;
    switch (crm) {
#define M(m) case m: __asm__ volatile("mtcrf 0xff,%1\n .long 0x7cb00120 | (" #m " << 12)\n mfcr %0" : "=r"(cr) : "r"(before), "r"(rv) : "cr0", "cr1", "cr2", "cr3", "cr4", "cr5", "cr6", "cr7"); break;
    M(0) M(1) M(2) M(4) M(8) M(16) M(32) M(64) M(128) M(3) M(0x81) M(0xff) M(0x18)
#undef M
    default: cr = 0;
    }
    return cr;
}
static uint32_t mfocrf(uint32_t v, unsigned crm, uint32_t junk)
{
    register uint32_t out __asm__("r6") = junk;
    switch (crm) {
#define M(m) case m: __asm__ volatile("mtcrf 0xff,%1\n .long 0x7cd00026 | (" #m " << 12)" : "+r"(out) : "r"(v) : "cr0", "cr1", "cr2", "cr3", "cr4", "cr5", "cr6", "cr7"); break;   /* mfocrf r6,m */
    M(0) M(1) M(2) M(4) M(8) M(16) M(32) M(64) M(128) M(3) M(0x81) M(0xff) M(0x18)
#undef M
    }
    return out;
}
static const unsigned crms[13] = { 0, 1, 2, 4, 8, 16, 32, 64, 128, 3, 0x81, 0xff, 0x18 };

/* The hints and cache insns at p: nothing to see but that the program goes on with its registers as they were. */
static uint32_t hints(void *p, uint32_t v)
{
    register uint32_t keep __asm__("r7") = v;
    /* dst r3,r4,0 and dststt r3,r4,0 (whatever the registers hold: hints), dss 0 */
    __asm__ volatile(".long 0x7c0322ac\n .long 0x7e0322ec\n .long 0x7c00066c\n dcbf 0,%1\n dcbst 0,%1\n icbi 0,%1\n isync\n sync\n dcbt 0,%1"
                     : "+r"(keep) : "b"(p) : "memory");
    return keep;
}

/*
 * r20..r27 from regs, lswi 20,3,nb, r20..r27 back to regs: the bytes loaded and the registers lswi leaves alone.
 * Or stswi 20,4,nb: the bytes stored.
 */
static const int nbs[12] = { 1, 2, 3, 4, 5, 7, 8, 13, 16, 30, 31, 0 };
#define IN8 "lwz 20,0(5)\n lwz 21,4(5)\n lwz 22,8(5)\n lwz 23,12(5)\n lwz 24,16(5)\n lwz 25,20(5)\n lwz 26,24(5)\n lwz 27,28(5)\n"
#define OUT8 "\n stw 20,0(5)\n stw 21,4(5)\n stw 22,8(5)\n stw 23,12(5)\n stw 24,16(5)\n stw 25,20(5)\n stw 26,24(5)\n stw 27,28(5)"
#define CL "r20", "r21", "r22", "r23", "r24", "r25", "r26", "r27", "memory"
static void lsw(const void *src, void *dst, uint32_t *regs, int nb, int store)
{
    register const void *a __asm__("r3") = src;
    register void *b __asm__("r4") = dst;
    register uint32_t *o __asm__("r5") = regs;
    switch (nb + 100 * store) {
#define L(nb) \
    case nb: __asm__ volatile(IN8 ".long 0x7e8304aa | (" #nb " << 11)" OUT8 : : "r"(a), "r"(b), "r"(o) : CL); break; \
    case nb + 100: __asm__ volatile(IN8 ".long 0x7e8405aa | (" #nb " << 11)" : : "r"(a), "r"(b), "r"(o) : CL); break;
    L(1) L(2) L(3) L(4) L(5) L(7) L(8) L(13) L(16) L(30) L(31) L(0)
#undef L
    }
}

/* An OE op on a and b from XER = xer: the result, and XER and CR after it. */
static uint32_t oe_op(unsigned k, uint32_t a, uint32_t b, uint32_t xer, uint32_t *xer_out, uint32_t *cr_out)
{
    uint32_t r = 0, x = 0, cr = 0;
    switch (k) {
#define O2(n, insn) case n: __asm__ volatile("mtcrf 0xff,%2\n mtxer %5\n " insn " %0,%3,%4\n mfxer %1\n mfcr %2" \
        : "=&r"(r), "=&r"(x), "+r"(cr) : "r"(a), "r"(b), "r"(xer) : "xer", "cr0", "cr1", "cr2", "cr3", "cr4", "cr5", "cr6", "cr7"); break;
#define O1(n, insn) case n: __asm__ volatile("mtcrf 0xff,%2\n mtxer %5\n " insn " %0,%3\n mfxer %1\n mfcr %2" \
        : "=&r"(r), "=&r"(x), "+r"(cr) : "r"(a), "r"(b), "r"(xer) : "xer", "cr0", "cr1", "cr2", "cr3", "cr4", "cr5", "cr6", "cr7"); break;
    O2(0, "addo") O2(1, "addo.") O2(2, "addco") O2(3, "addco.") O2(4, "addeo") O2(5, "addeo.")
    O1(6, "addmeo") O1(7, "addmeo.") O1(8, "addzeo") O1(9, "addzeo.")
    O2(10, "subfo") O2(11, "subfo.") O2(12, "subfco") O2(13, "subfco.") O2(14, "subfeo") O2(15, "subfeo.")
    O1(16, "subfmeo") O1(17, "subfmeo.") O1(18, "subfzeo") O1(19, "subfzeo.")
    O1(20, "nego") O1(21, "nego.") O2(22, "mullwo") O2(23, "mullwo.") O2(24, "divwo") O2(25, "divwo.")
    O2(26, "divwuo") O2(27, "divwuo.")
#undef O2
#undef O1
    }
    *xer_out = x; *cr_out = cr;
    return r;
}
static uint32_t edge(void)
{
    static const uint32_t e[8] = { 0, 1, 0xffffffff, 0x80000000, 0x7fffffff, 2, 0x80000001, 0xfffffffe };
    uint64_t r = rnd();
    return (r & 3) ? e[(r >> 2) & 7] : (uint32_t)(r >> 8);
}

/*
 * bcctr (and with lk, bcctrl) on CR bit bi, branching if it is set (bo 12) or clear (bo 4), with the CR as
 * given: 9 if it branched, 7 if not; and what LR came to, from the insn's own address.
 */
static uint32_t bcctr(unsigned k, uint32_t cr, uint32_t *lr_out)
{
    uint32_t r = 0, lr = 0;
    switch (k) {
#define B(n, bo, bi, lk) case n: __asm__ volatile( \
        "bl 1f\n 1: mflr 9\n addi 10,9,2f-1b\n mtctr 10\n li 10,0\n mtlr 10\n mtcrf 0xff,%2\n" \
        "4: .long 0x4c000420 | (" #bo " << 21) | (" #bi " << 16) | " #lk "\n li %0,7\n b 3f\n 2: li %0,9\n 3: mflr %1\n" \
        "cmpwi %1,0\n beq 5f\n addi 9,9,4b-1b\n subf %1,9,%1\n 5:" \
        : "=&r"(r), "=&r"(lr) : "r"(cr) : "r9", "r10", "lr", "ctr", "cr0", "cr1", "cr2", "cr3", "cr4", "cr5", "cr6", "cr7"); break;
    B(0, 12, 0, 0) B(1, 4, 0, 0) B(2, 12, 2, 0) B(3, 4, 2, 0) B(4, 12, 5, 0) B(5, 4, 5, 0) B(6, 12, 30, 0) B(7, 4, 30, 0)
    B(8, 12, 1, 1) B(9, 4, 1, 1) B(10, 12, 3, 1) B(11, 4, 3, 1) B(12, 12, 29, 1) B(13, 4, 29, 1)
#undef B
    }
    *lr_out = lr;
    return r;
}

int main(void)
{
    struct sigaction sa;
    unsigned char *m = mmap(0, 3 * 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    unsigned char *page = m + 4096, tmp[32] __attribute__((aligned(16))), in[16] __attribute__((aligned(16)));
    uint64_t h = 0xcbf29ce484222325ull;
    int n = 0;

    if (m == MAP_FAILED) {
        fprintf(stderr, "VECTEST mmap failed\n");
        return 1;
    }
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = on_fault;
    sa.sa_flags = SA_SIGINFO | SA_NODEFER;
    sigaction(SIGSEGV, &sa, 0); sigaction(SIGBUS, &sa, 0); sigaction(SIGILL, &sa, 0);
    if (sigsetjmp(jb, 1)) {
        fprintf(stderr, "VECTEST no AltiVec here: signal %d\n", fault_sig);
        return 1;
    }
    for (int i = 0; i < 3 * 4096; i++) {
        m[i] = rnd();
    }
    for (long i = 1; i <= 200000; i++) {
        uint64_t r = rnd();
        long off = (r >> 4) % 4096;                 /* any byte of the page: the low four bits are dropped */
        unsigned op = r % 11;
        uint32_t v = rnd(), w = rnd();

        if ((r >> 20) % 4 == 0) {
            off = (r >> 24) & 1 ? 4095 - (r >> 28) % 20 : (r >> 28) % 20;       /* by the page's ends */
        }
        switch (op) {
        case 0: lvx_ab(page, off, tmp, (r >> 40) & 1); h = mix(h, memcmp(tmp, page + (off & ~15), 16)); break;
        case 1: lvx_0b(page + off, tmp); break;
        case 2: lvx_ab(m, 4096 + off, tmp, 0); break;
        case 3:
            for (int k = 0; k < 16; k++) { in[k] = rnd(); }
            stvx_ab(in, page, off);
            memcpy(tmp, page + (off & ~15), 16);
            h = mix(h, memcmp(tmp, in, 16));
            break;
        case 4:
            for (int k = 0; k < 16; k++) { in[k] = rnd(); }
            through((r >> 40) % 20, in, tmp);
            h = mix(h, memcmp(tmp, in, 16));
            break;
        case 5: memset(tmp, 0, 16); h = mix(h, mtocrf(v, crms[(r >> 40) % 13], w)); break;
        case 6: memset(tmp, 0, 16); h = mix(h, mfocrf(v, crms[(r >> 40) % 13], w)); break;
        case 7: memset(tmp, 0, 16); h = mix(h, hints(page + off, v)); break;
        case 8: {
            uint32_t regs[8];
            unsigned char out[48];
            int nb = nbs[(r >> 40) % 12];

            for (int k = 0; k < 8; k++) { regs[k] = rnd(); }
            memset(out, 0x5a, sizeof(out));
            memset(tmp, 0, 16);
            lsw(page + off, out, regs, nb, 0);          /* off may leave it to run into the next page */
            for (int k = 0; k < 8; k++) { h = mix(h, regs[k]); }
            lsw(page + off, out + 4, regs, nb, 1);
            for (int k = 0; k < 48; k++) { h = mix(h, out[k]); }
            break;
        }
        case 9: {
            uint32_t x, cr;
            memset(tmp, 0, 16);
            h = mix(h, oe_op((r >> 40) % 28, edge(), edge(), (uint32_t)(r >> 16) & 0xe0000000, &x, &cr));
            h = mix(mix(h, x), cr);
            break;
        }
        case 10: {
            uint32_t lr;
            memset(tmp, 0, 16);
            h = mix(h, bcctr((r >> 40) % 14, v, &lr));
            h = mix(h, lr);
            break;
        }
        }
        for (int k = 0; k < 16; k += 8) {
            uint64_t t;
            memcpy(&t, tmp + k, 8);
            h = mix(h, t);
        }
        h = mix(h, op);
        if (i % 20000 == 0) {
            fprintf(stderr, "VECTEST %ld %016llx\n", i, (unsigned long long)h);
        }
    }
    /* faults: the page after is taken away, and each insn tried at four places in it */
    munmap(m + 2 * 4096, 4096);
    for (n = 0; n < 32; n++) {
        long off = 4096 + (long[]){ 0, 5, 17, 4095 }[n % 4];
        memset(tmp, 0xa5, 32);
        fault_addr = 0; fault_sig = 0;
        if (!sigsetjmp(jb, 1)) {
            switch (n / 4) {
            case 0: lvx_ab(page, off, tmp, 0); break;
            case 1: stvx_ab(in, page, off); break;
            case 2: __asm__ volatile("dcbf %0,%1" : : "b"(page), "r"(off)); break;
            case 3: __asm__ volatile("dcbst %0,%1" : : "b"(page), "r"(off)); break;
            case 4: __asm__ volatile("icbi %0,%1" : : "b"(page), "r"(off)); break;
            case 6: { uint32_t regs[8] = { 0 }; lsw(page + off - 3, tmp, regs, 8, 0); tmp[0] = regs[0]; break; }
            case 7: { uint32_t regs[8] = { 0 }; lsw(tmp, page + off - 3, regs, 8, 1); break; }
            case 5: {   /* dcba r3,r4 */
                register void *ra __asm__("r3") = page;
                register long rb __asm__("r4") = off;
                __asm__ volatile(".long 0x7c0325ec" : : "r"(ra), "r"(rb));
                break;
            }
            }
        }
        fprintf(stderr, "VECTEST fault %d: signal %d at page+%lx, tmp %02x\n", n, (int)fault_sig,
                fault_addr ? (unsigned long)(fault_addr - (uintptr_t)page) : 0ul, tmp[0]);
    }
    return 0;
}
