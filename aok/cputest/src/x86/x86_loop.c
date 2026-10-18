// LOOP (0xe2), LOOPE/LOOPZ (0xe1) and LOOPNE/LOOPNZ (0xe0).
//
// None of the three were in the i386 one-byte decode table -- jcxz (0xe3) was
// there, but 0xe0-0xe2 were not -- so all of them raised SIGILL on the i386
// guest. Reported upstream as ish-app/ish#2174. We had implemented them for the
// amd64 frontend only, whose own comment noted they were "unimplemented in BOTH
// engines"; the i386 side never got the same treatment.
//
// The subtle part is LOOPE/LOOPNE, which also test ZF. ZF is lazy: it is often
// still deferred in cpu->res with ZF_RES set, and only the ZF macro (or the
// do_jump gadget path) resolves it. An implementation that reads the eflags bit
// directly passes every cmp-based case and fails only when ZF came from
// something like a preceding decl or andl -- so the lazy cases below are the
// ones that actually discriminate, and they are deliberately included.
//
// x86 only. Builds for both i386 and x86_64 guests: on x86_64 the same
// mnemonics use RCX, which exercises the amd64 loop gadget instead.
#define _GNU_SOURCE
#include <stdio.h>
#include <unistd.h>
#include "../test_common.h"

#if defined(__x86_64__)
#define CX  "rcx"
#define MOVCX "movq"
#define INC "incq"
#else
#define CX  "ecx"
#define MOVCX "movl"
#define INC "incl"
#endif

static void check(const char *what, long got, long want) {
    if (got == want) {
        test_logf("  ok   %s = %ld\n", what, got);
        return;
    }
    printf("FAIL: %s = %ld (want %ld)\n", what, got, want);
    failures_total++;
}

int main(int argc, char **argv) {
    test_init(argc, argv);
    alarm(test_watchdog_secs(60));

    long n, left;

    // --- plain LOOP -------------------------------------------------------
    n = 0;
    __asm__ volatile(MOVCX " $5,%%" CX "\n1:\t" INC " %0\n\tloop 1b"
                     : "+r"(n) :: CX, "cc");
    check("loop runs 5 times", n, 5);

    n = 0;
    __asm__ volatile(MOVCX " $1,%%" CX "\n1:\t" INC " %0\n\tloop 1b"
                     : "+r"(n) :: CX, "cc");
    check("loop with count 1 runs body once", n, 1);

    left = -1;
    __asm__ volatile(MOVCX " $4,%%" CX "\n1:\tloop 1b\n\t" MOVCX " %%" CX ",%0"
                     : "=r"(left) :: CX, "cc");
    check("count register is 0 after loop exit", left, 0);

    // LOOP must not disturb the flags: set ZF, run a loop, ZF still set.
    {
        long zf = 0;
        __asm__ volatile("xorl %%eax,%%eax\n\tcmpl $0,%%eax\n\t"
                         MOVCX " $3,%%" CX "\n1:\tloop 1b\n\t"
                         "setz %%al\n\tmovzbl %%al,%%eax\n\tmov %%eax,%k0"
                         : "=r"(zf) :: "eax", CX, "cc");
        check("ZF preserved across loop", zf, 1);
    }

    // Nested loops, to be sure the counter is not shared or clobbered.
    n = 0;
    __asm__ volatile(MOVCX " $3,%%" CX "\n1:\tpush %%" CX "\n\t"
                     MOVCX " $2,%%" CX "\n2:\t" INC " %0\n\tloop 2b\n\t"
                     "pop %%" CX "\n\tloop 1b"
                     : "+r"(n) :: CX, "cc", "memory");
    check("nested loop 3x2", n, 6);

    // --- LOOPE / LOOPZ, flags from cmp (materialized) ---------------------
    n = 0;
    __asm__ volatile(MOVCX " $5,%%" CX "\n1:\t" INC " %0\n\t"
                     "xorl %%eax,%%eax\n\tcmpl $0,%%eax\n\tloope 1b"
                     : "+r"(n) :: CX, "eax", "cc");
    check("loope with ZF always set runs 5 times", n, 5);

    n = 0;
    __asm__ volatile(MOVCX " $5,%%" CX "\n1:\t" INC " %0\n\t"
                     "movl $1,%%eax\n\tcmpl $0,%%eax\n\tloope 1b"
                     : "+r"(n) :: CX, "eax", "cc");
    check("loope with ZF clear exits after one pass", n, 1);

    // The count must still be decremented when ZF is what ends the loop.
    left = -1;
    __asm__ volatile(MOVCX " $5,%%" CX "\n1:\tmovl $1,%%eax\n\tcmpl $0,%%eax\n\t"
                     "loope 1b\n\t" MOVCX " %%" CX ",%0"
                     : "=r"(left) :: CX, "eax", "cc");
    check("count decremented on ZF-caused exit", left, 4);

    // --- LOOPNE / LOOPNZ, flags from cmp ----------------------------------
    n = 0;
    __asm__ volatile(MOVCX " $5,%%" CX "\n1:\t" INC " %0\n\t"
                     "movl $1,%%eax\n\tcmpl $0,%%eax\n\tloopne 1b"
                     : "+r"(n) :: CX, "eax", "cc");
    check("loopne with ZF clear runs 5 times", n, 5);

    n = 0;
    __asm__ volatile(MOVCX " $5,%%" CX "\n1:\t" INC " %0\n\t"
                     "xorl %%eax,%%eax\n\tcmpl $0,%%eax\n\tloopne 1b"
                     : "+r"(n) :: CX, "eax", "cc");
    check("loopne with ZF set exits after one pass", n, 1);

    // --- the discriminating cases: ZF produced LAZILY ----------------------
    // decl leaves its result in cpu->res with ZF deferred; an implementation
    // reading the eflags bit directly gets a stale answer here.
    n = 0;
    __asm__ volatile(MOVCX " $4,%%" CX "\n\tmovl $3,%%edx\n"
                     "1:\t" INC " %0\n\tdecl %%edx\n\tloopne 1b"
                     : "+r"(n) :: CX, "edx", "cc");
    check("loopne with ZF from decl (lazy)", n, 3);

    n = 0;
    __asm__ volatile(MOVCX " $6,%%" CX "\n\tmovl $1,%%edx\n"
                     "1:\t" INC " %0\n\tdecl %%edx\n\tloope 1b"
                     : "+r"(n) :: CX, "edx", "cc");
    check("loope with ZF from decl (lazy)", n, 2);

    n = 0;
    __asm__ volatile(MOVCX " $5,%%" CX "\n1:\t" INC " %0\n\t"
                     "movl $2,%%eax\n\tandl $2,%%eax\n\tloopne 1b"
                     : "+r"(n) :: CX, "eax", "cc");
    check("loopne with ZF from andl (lazy)", n, 5);

    // --- jecxz, the neighbour that always worked --------------------------
    {
        long taken = 0;
        __asm__ volatile(MOVCX " $0,%%" CX "\n\tjecxz 1f\n\tjmp 2f\n1:\t"
                         MOVCX " $1,%0\n2:"
                         : "=r"(taken) :: CX, "cc");
        check("jecxz taken when count is 0", taken, 1);
    }

    // A memchr-shaped scan, the idiom loopne exists for. The pointer is bumped
    // with lea rather than inc so the flags reaching loopne are the cmpb's.
    {
        const char *s = "abcdef";       // 'd' is at index 3
        long remaining = 0;
        __asm__ volatile(MOVCX " $6,%%" CX "\n"
                         "1:\tcmpb $0x64,(%1)\n\t"
                         "lea 1(%1),%1\n\t"
                         "loopne 1b\n\t"
                         MOVCX " %%" CX ",%0"
                         : "=r"(remaining), "+r"(s) :: CX, "cc", "memory");
        // Four passes consume indices 0..3, so two of the six remain.
        check("loopne scan stops at 'd' after 4 passes", 6 - remaining, 4);
    }

    if (failures_total != 0) {
        printf("x86_loop: FAIL failures=%u\n", failures_total);
        return 1;
    }
    printf("x86_loop: PASS\n");
    return 0;
}
