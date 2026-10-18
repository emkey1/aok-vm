// rep_interruptible.c -- a long REP string op must be interruptible, and must
// still be correct after being interrupted.
//
// x86 defines REP as interruptible BETWEEN iterations: ecx/esi/edi are the
// architectural restart state, which is why a #PF partway through a `rep movsb`
// can resume it. AOK's i386 JIT did not honour that. jit/helpers.c's
// rep_string_fast resolved a host page per page-run and bulk-copied with
// memmove until ecx hit zero, and the JIT only tests the poke flag at BLOCK
// boundaries -- so one `rep movsb` over a large buffer held the thread inside a
// single gadget for the whole copy. Measured before the fix: 192 MB copied with
// a 1ms repeating timer armed delivered exactly ONE signal, and it arrived
// after the instruction had finished. Nothing could interrupt it: not a signal,
// and not the swap pager's throttle poke (emu/tlb.c sets mem_throttle_wanted
// and calls cpu_poke), so memory reclaim waited on a copy that had already
// faulted in everything it was going to touch.
//
// A REPEATING timer is the whole point of the test. A single expiry proves
// nothing, because the rep takes only tens of milliseconds and one shot can
// land after it and still "pass". At a 1ms interval the handler count is itself
// the witness:
//
//   uninterruptible -> signals cannot be delivered while it runs, they
//                      coalesce, and the handler runs about ONCE
//   interruptible   -> the handler runs many times before the rep returns
//
// The second assertion is the one that guards the risky half of the fix: the
// copy must still be byte-for-byte correct, which only holds if ecx/esi/edi
// were left as a valid restart state every time the rep was interrupted.
//
// THREE shapes are exercised, because the two halves of the fix are separate
// mechanisms and an earlier version of this test covered only the first:
//
//   forward rep movsb  -- the bulk fast path (jit/helpers.c rep_string_fast),
//                         which resolves a host page per page-run
//   backward rep movsb -- DF=1 is diverted away from the fast path entirely and
//                         runs in the per-element gadget loop
//   repne scasb        -- what strlen compiles to; no scan or compare of any
//                         length ever reaches the fast path
//
// Measured before the per-element loop was fixed, on a 96 MB buffer: backward
// rep movsb 118ms/ONE signal, repne scasb 111ms/ONE signal. Those are LONGER
// stalls than the forward case, because the per-element path pays a TLB lookup
// per element instead of a memmove per page-run -- so a test that covered only
// the forward shape would have reported PASS while the worse stalls remained.
//
// The amd64 interpreter reaches the interruptible answer by a different route
// and already passed before the JIT was fixed; it is covered here so it stays
// that way.
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <time.h>
#include <sys/time.h>

static volatile sig_atomic_t hits;
static void handler(int sig) { (void) sig; hits++; }

static double since(struct timespec a) {
    struct timespec b;
    clock_gettime(CLOCK_MONOTONIC, &b);
    return (b.tv_sec - a.tv_sec) * 1000.0 + (b.tv_nsec - a.tv_nsec) / 1e6;
}

static struct timespec arm_timer(void) {
    struct itimerval it;
    memset(&it, 0, sizeof it);
    it.it_value.tv_usec = 1000;
    it.it_interval.tv_usec = 1000;          /* every 1ms, repeating */
    struct timespec t0;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    hits = 0;
    setitimer(ITIMER_REAL, &it, NULL);
    return t0;
}

static void disarm_timer(void) {
    struct itimerval it;
    memset(&it, 0, sizeof it);
    setitimer(ITIMER_REAL, &it, NULL);
}

static int failures;

// The uninterruptible case scores exactly 1 (the expiry delivered once the
// instruction retired). Anything above a small handful means the rep really was
// being re-entered. Deliberately loose: this is a yes/no property and the exact
// count follows host speed. A shape that finishes too fast to arm the timer is
// reported and skipped rather than failed.
static void judge(const char *shape, double ms, int signals, int ok) {
    printf("  %-18s %7.1f ms  %4d signals  %s\n", shape, ms, signals,
           ok ? "result ok" : "RESULT WRONG");
    if (!ok) {
        printf("rep_interruptible: FAIL %s produced the wrong result --"
               " the restart state after an interrupt is wrong\n", shape);
        failures++;
        return;
    }
    if (signals < 3) {
        if (ms < 5.0)
            printf("      (skipped: %.1f ms is too short to arm a 1ms timer)\n", ms);
        else {
            printf("rep_interruptible: FAIL %s was not interruptible:"
                   " %d signal(s) in %.1f ms\n", shape, signals, ms);
            failures++;
        }
    }
}

int main(void) {
    size_t n = 96u << 20;
    unsigned char *src = malloc(n), *dst = malloc(n);
    if (src == NULL || dst == NULL) {
        printf("rep_interruptible: SKIP could not allocate 2 x %zu MB\n", n >> 20);
        return 0;
    }
    for (size_t i = 0; i < n; i++)
        src[i] = (unsigned char) (i * 31u + 7u);
    memset(dst, 0, n);   /* fault both in; this tests the rep, not paging */

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = handler;
    sa.sa_flags = SA_RESTART;
    if (sigaction(SIGALRM, &sa, NULL) != 0) {
        printf("rep_interruptible: SKIP sigaction failed\n");
        return 0;
    }

    /* 1. forward rep movsb -- the bulk fast path */
    {
        void *d = dst, *s = src; size_t c = n;
        struct timespec t = arm_timer();
        __asm__ volatile ("cld; rep movsb" : "+D"(d), "+S"(s), "+c"(c) : : "memory");
        double ms = since(t); int sig = (int) hits; disarm_timer();
        judge("fwd rep movsb", ms, sig, c == 0 && memcmp(dst, src, n) == 0);
    }

    /* 2. backward rep movsb -- DF=1 never reaches the fast path */
    memset(dst, 0, n);
    {
        void *d = dst + n - 1, *s = src + n - 1; size_t c = n;
        struct timespec t = arm_timer();
        __asm__ volatile ("std; rep movsb; cld" : "+D"(d), "+S"(s), "+c"(c) : : "memory");
        double ms = since(t); int sig = (int) hits; disarm_timer();
        judge("bwd rep movsb", ms, sig, c == 0 && memcmp(dst, src, n) == 0);
    }

    /* 3. repne scasb -- what strlen compiles to; scans for a byte that is not
       there, so it runs the whole count. src holds i*31+7 for every i, which
       takes every byte value, so scan a buffer we control instead. */
    memset(dst, 'x', n);
    {
        void *d = dst; size_t c = n;
        struct timespec t = arm_timer();
        __asm__ volatile ("cld; repne scasb" : "+D"(d), "+c"(c) : "a"('Z') : "memory", "cc");
        double ms = since(t); int sig = (int) hits; disarm_timer();
        /* 'Z' is not in a buffer of 'x', so the scan must exhaust the count. */
        judge("repne scasb", ms, sig, c == 0);
    }

    if (failures != 0)
        return 1;
    printf("rep_interruptible: PASS (all three rep shapes interruptible)\n");
    return 0;
}
