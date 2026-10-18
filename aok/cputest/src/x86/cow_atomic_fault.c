// cow_atomic_fault (i386/amd64): a LOCK-prefixed atomic on a page that is
// P_COW at fault time but resolved (COW-broken by a sibling thread) before the
// GPF handler re-checks writability must RESTART, not deliver a spurious
// SIGSEGV.
//
// The bug (issue #477, seen as signalfd_epoll_deadlock crashing on i386 under
// heavy concurrent multi-arch load): after any thread calls fork(), the whole
// process's shared pages are marked P_COW. A LOCK atomic gadget's write_prep
// then can't translate the page (mem_ptr_nofault returns NULL for a P_COW
// write) and raises INT_GPF with the fault address recorded. The i386 GPF
// handler re-derived "does this need a page fault?" with a LOCK-FREE re-check
// (i386_gpf_addr_needs_page_fault) -- but a sibling thread racing on the same
// page can break the COW in between, so the re-check reads the page back as
// writable, the handler decides no fault is needed, and falls through to
// SIGSEGV. The store was idempotent and should simply have re-executed.
//
// This reproduces the exact ingredients directly and cheaply: N worker threads
// spinning LOCK-prefixed atomics (xadd/dec/cmpxchg) on a small set of shared
// counters, while M forker threads call fork()+_exit() in a tight loop to keep
// re-COWing those very counter pages out from under the workers. Pre-fix this
// SIGSEGVs within a second or two on i386 under load; fixed, it runs the full
// duration cleanly. x86-only (LOCK-prefixed inline asm); portable across i386
// and amd64. Passes on real Linux (the atomics are just genuinely atomic
// there).

#define _GNU_SOURCE

#include <errno.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <pthread.h>

#include "test_common.h"

#define NUM_COUNTERS 8
#define NUM_WORKERS 4
#define NUM_FORKERS 3
#define RUN_SECONDS 3

// Shared, page-spanning so fork()'s COW marking covers the counters the
// workers hammer. Aligned + padded so they sit on their own pages.
static volatile long g_counters[NUM_COUNTERS * 16];
static atomic_int g_stop;
static atomic_ulong g_ops;

static void lock_xadd(volatile long *p, long v) {
    __asm__ __volatile__("lock; xadd %0, %1"
                         : "+r"(v), "+m"(*p) : : "memory", "cc");
}
static void lock_dec(volatile long *p) {
    __asm__ __volatile__("lock; dec%z0 %0" : "+m"(*p) : : "memory", "cc");
}
static void lock_cmpxchg(volatile long *p) {
    long expected = *p;
    long desired = expected + 1;
    __asm__ __volatile__("lock; cmpxchg %2, %1"
                         : "+a"(expected), "+m"(*p) : "r"(desired) : "memory", "cc");
}

static void *worker_thread(void *arg) {
    (void) arg;
    unsigned seed = (unsigned) (uintptr_t) pthread_self();
    while (!atomic_load(&g_stop)) {
        for (int i = 0; i < NUM_COUNTERS; i++) {
            volatile long *p = &g_counters[i * 16];
            switch (seed & 3) {
                case 0: lock_xadd(p, 1); break;
                case 1: lock_dec(p); break;
                case 2: lock_cmpxchg(p); break;
                default: lock_xadd(p, -1); break;
            }
            seed = seed * 1103515245u + 12345u;
        }
        atomic_fetch_add(&g_ops, NUM_COUNTERS);
    }
    return NULL;
}

static void *forker_thread(void *arg) {
    (void) arg;
    while (!atomic_load(&g_stop)) {
        pid_t pid = fork();
        if (pid == 0) {
            // Child: touch a counter (forces its own COW break, exercising the
            // fault path in the child too) then exit immediately.
            g_counters[0] += 1;
            _exit(0);
        }
        if (pid > 0) {
            int st;
            waitpid(pid, &st, 0);
        } else {
            // fork can transiently fail under load; just retry.
            struct timespec ts = { 0, 1000000 };
            nanosleep(&ts, NULL);
        }
    }
    return NULL;
}

int main(int argc, char **argv) {
    test_init(argc, argv);

    // A watchdog: the pre-fix failure is a hard SIGSEGV in a worker (kills the
    // process), so "we reached the end" is itself the pass signal. The alarm
    // guards against any unexpected hang.
    alarm(RUN_SECONDS + 30);

    pthread_t workers[NUM_WORKERS], forkers[NUM_FORKERS];
    for (int i = 0; i < NUM_WORKERS; i++) {
        if (pthread_create(&workers[i], NULL, worker_thread, NULL) != 0) {
            failf("cow_atomic_fault worker create", (uint64_t) errno, 0, 0, 0, 0, 0);
            return finish_suite("cow_atomic_fault");
        }
    }
    for (int i = 0; i < NUM_FORKERS; i++) {
        if (pthread_create(&forkers[i], NULL, forker_thread, NULL) != 0) {
            failf("cow_atomic_fault forker create", (uint64_t) errno, 0, 0, 0, 0, 0);
            atomic_store(&g_stop, 1);
            return finish_suite("cow_atomic_fault");
        }
    }

    struct timespec run = { RUN_SECONDS, 0 };
    nanosleep(&run, NULL);
    atomic_store(&g_stop, 1);

    for (int i = 0; i < NUM_WORKERS; i++)
        pthread_join(workers[i], NULL);
    for (int i = 0; i < NUM_FORKERS; i++)
        pthread_join(forkers[i], NULL);

    // If any worker had taken a spurious SIGSEGV the process would already be
    // dead; reaching here with real work done is the pass.
    unsigned long ops = atomic_load(&g_ops);
    test_logf("completed %lu atomic ops across %d fork-churned pages\n",
              ops, NUM_COUNTERS);
    if (ops == 0)
        failf("cow_atomic_fault no ops", 0, 0, 0, 1, 0, 0);

    return finish_suite("cow_atomic_fault");
}
