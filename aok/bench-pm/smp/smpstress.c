/*
 * smpstress -- for a guest with more than one CPU: two (or N) threads hammer shared counters, so that a CPU's
 * lwarx/stwcx. that is not atomic against the other CPU's, or a lock that lets two in, shows as a wrong count.
 *   atomic: OSAtomicIncrement32 (lwarx/stwcx. in libkern)   mutex: pthread_mutex   spin: OSSpinLock
 *   plain: an unprotected counter -- with CPUs truly in parallel it loses updates; with one CPU it rarely does
 * Prints each count against what it must be, and OK or WRONG.
 */
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <libkern/OSAtomic.h>

static int N = 2000000, T = 2;
static volatile int32_t atomic_c;
static int mutex_c, spin_c;
static volatile int plain_c;
static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static OSSpinLock sl = OS_SPINLOCK_INIT;

static void *work(void *arg)
{
    int i;
    for (i = 0; i < N; i++) {
        OSAtomicIncrement32(&atomic_c);
        if ((i & 7) == 0) {
            pthread_mutex_lock(&mu); mutex_c++; pthread_mutex_unlock(&mu);
            OSSpinLockLock(&sl); spin_c++; OSSpinLockUnlock(&sl);
        }
        plain_c++;
    }
    return 0;
}

int main(int argc, char **argv)
{
    pthread_t th[16];
    int i, bad = 0, want8;
    if (argc > 1) N = atoi(argv[1]);
    if (argc > 2) T = atoi(argv[2]);
    for (i = 0; i < T; i++) pthread_create(&th[i], 0, work, 0);
    for (i = 0; i < T; i++) pthread_join(th[i], 0);
    want8 = T * ((N + 7) / 8);
    bad |= atomic_c != T * N; bad |= mutex_c != want8; bad |= spin_c != want8;
    printf("atomic %d/%d mutex %d/%d spin %d/%d plain %d/%d (lost %d) %s\n", (int)atomic_c, T * N,
           mutex_c, want8, spin_c, want8, plain_c, T * N, T * N - plain_c, bad ? "WRONG" : "OK");
    return bad;
}
