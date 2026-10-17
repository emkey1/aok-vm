// tsotest: the memory order x86 promises between CPUs (TSO), for an engine that runs a guest's CPUs in parallel
// on a host whose order is weaker (the QEMU plug-in's x86 front end on ARM, with -accel tcg,thread=multi).
//
//   mp   message passing: x = 1; y = 1 against y; x. Seeing y's store and not x's is forbidden.
//   lb   load buffering: x; y = 1 against y; x = 1. Each load seeing the other's later store is forbidden.
//   sb   store buffering: x = 1; y against y = 1; x. Both loads seeing 0 is ALLOWED (x86's store buffer), and
//        real hardware shows it: the count says the threads did overlap.
// Each runs in lockstep, each side waiting at every slot for the other to have done the one before: under an
// emulator the two would otherwise seldom meet. sb's count is the witness that they did.
//   lock a lock-prefixed add and xadd from every thread at once: the total must be exact.
//   spin a cmpxchg spinlock around a plain read-modify-write of a counter: exact too.
//
// Built for x86 and x86-64 (gcc -O2 -pthread -static), and for an ARM host as the positive control: there mp,
// lb and sb are the hardware's own, and the forbidden ones turn up. Exit status 1 if a forbidden one is seen
// or a total is wrong. tsotest [rounds] [threads for lock and spin]
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define N (1 << 16)                     /* slots a round */

static volatile int *x, *y;
static int *r0, *r1;
static int which;                       /* the test this round */

/* A spinning barrier for @n threads (macOS has no pthread_barrier), which also lets the two sides start together. */
static volatile int go_n, go_in, go_gen;
static void go_init(int n)
{
    go_n = n;
    go_in = 0;
}
static void go_wait(void)
{
    int gen = __atomic_load_n(&go_gen, __ATOMIC_ACQUIRE);

    if (__atomic_add_fetch(&go_in, 1, __ATOMIC_ACQ_REL) == go_n) {
        go_in = 0;
        __atomic_store_n(&go_gen, gen + 1, __ATOMIC_RELEASE);
    } else {
        while (__atomic_load_n(&go_gen, __ATOMIC_ACQUIRE) == gen) {
        }
    }
}

#if defined(__x86_64__) || defined(__i386__)
#define RELAX() __asm__ volatile("pause")
#else
#define RELAX() __asm__ volatile("yield")
#endif
#define FENCE() __asm__ volatile("" ::: "memory")

static volatile int done[2];             /* lockstep: the slots each side has finished */

static void *side(void *arg)
{
    int me = (int)(intptr_t)arg;

    go_wait();
    for (int k = 0; k < N; k++) {
        switch (which * 2 + me) {
        case 0: x[k] = 1; FENCE(); y[k] = 1; break;                    /* mp writer */
        case 1: r0[k] = y[k]; FENCE(); r1[k] = x[k]; break;            /* mp reader */
        case 2: r0[k] = x[k]; FENCE(); y[k] = 1; break;                /* lb */
        case 3: r1[k] = y[k]; FENCE(); x[k] = 1; break;
        case 4: x[k] = 1; FENCE(); r0[k] = y[k]; break;                /* sb */
        case 5: y[k] = 1; FENCE(); r1[k] = x[k]; break;
        }
        {
            __atomic_store_n(&done[me], k + 1, __ATOMIC_RELEASE);
            while (__atomic_load_n(&done[!me], __ATOMIC_ACQUIRE) < k + 1) {
            }
        }
    }
    return NULL;
}

/* One round of test @t: both sides over fresh slots at once, then the outcomes counted. */
static long round_of(int t, long *seen)
{
    pthread_t a, b;
    long bad = 0;

    memset((void *)x, 0, N * sizeof(int));
    memset((void *)y, 0, N * sizeof(int));
    which = t;
    done[0] = done[1] = 0;
    go_init(2);
    pthread_create(&a, NULL, side, (void *)0);
    pthread_create(&b, NULL, side, (void *)1);
    pthread_join(a, NULL);
    pthread_join(b, NULL);
    for (int k = 0; k < N; k++) {
        if (t == 0 && r0[k] == 1 && r1[k] == 0) {
            bad++;
        } else if (t == 1 && r0[k] == 1 && r1[k] == 1) {
            bad++;
        } else if (t == 2 && r0[k] == 0 && r1[k] == 0) {
            (*seen)++;
        }
    }
    return bad;
}

static volatile long total, plain;
static volatile int spin;
#define ADDS 200000

static void *adder(void *arg)
{
    (void)arg;
    go_wait();
    for (int i = 0; i < ADDS; i++) {
#if defined(__x86_64__) || defined(__i386__)
        long one = 1;
        __asm__ volatile("lock addl $1, %0" : "+m" (*(volatile int *)&total) : : "memory", "cc");
        __asm__ volatile("lock xadd %0, %1" : "+r" (one), "+m" (total) : : "memory", "cc");
#else
        __atomic_fetch_add(&total, 2, __ATOMIC_RELAXED);
#endif
        int free_ = 0;
        while (!__atomic_compare_exchange_n(&spin, &free_, 1, 0, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED)) {
            free_ = 0;
            RELAX();
        }
        plain = plain + 1;              /* a plain load and store, inside the lock */
        __atomic_store_n(&spin, 0, __ATOMIC_RELEASE);
    }
    return NULL;
}

int main(int argc, char **argv)
{
    int rounds = argc > 1 ? atoi(argv[1]) : 40, nt = argc > 2 ? atoi(argv[2]) : 4;
    static const char *name[] = { "mp", "lb" };
    long bad[2] = { 0, 0 }, sb = 0, slots = (long)rounds * N;
    pthread_t th[64];
    int fail = 0;

    x = calloc(N, sizeof(int));
    y = calloc(N, sizeof(int));
    r0 = calloc(N, sizeof(int));
    r1 = calloc(N, sizeof(int));
    for (int r = 0; r < rounds; r++) {
        for (int t = 0; t < 3; t++) {
            long b = round_of(t, &sb);

            if (t < 2) {
                bad[t] += b;
            }
        }
    }
    for (int t = 0; t < 2; t++) {
        printf("TSO %s forbidden %ld of %ld\n", name[t], bad[t], slots);
        fail |= bad[t] != 0;
    }
    printf("TSO sb allowed %ld of %ld\n", sb, slots);

    if (nt > 64) {
        nt = 64;
    }
    go_init(nt);
    for (int i = 0; i < nt; i++) {
        pthread_create(&th[i], NULL, adder, NULL);
    }
    for (int i = 0; i < nt; i++) {
        pthread_join(th[i], NULL);
    }
    printf("TSO lock %s %ld of %ld\n", total == 2L * ADDS * nt ? "ok" : "BAD", total, 2L * ADDS * nt);
    printf("TSO spin %s %ld of %ld\n", plain == (long)ADDS * nt ? "ok" : "BAD", plain, (long)ADDS * nt);
    fail |= total != 2L * ADDS * nt || plain != (long)ADDS * nt;
    printf("TSO %s\n", fail ? "FAIL" : "ok");
    return fail;
}
