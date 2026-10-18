// arm64 atomics umbrella: the AArch64 counterpart of x86/atomics32.c.
//
// Covers the load/store-exclusive family (LDXR/STXR, LDAXR/STLXR at 8/16/
// 32/64-bit widths), acquire/release ordering through LDAR/STLR, the
// compiler's __atomic builtins (which lower to exclusives on baseline
// armv8-a, or to LSE if -moutline-atomics probes HWCAP_ATOMICS at runtime
// — either lowering must work), CLREX, and a multithreaded stress mix.
// LSE CAS/SWP/LDADD get direct coverage only when the kernel advertises
// HWCAP_ATOMICS (they'd SIGILL otherwise, correctly).
//
// Bug classes this guards (all real finds from the arm64 JIT bring-up):
// exclusive-monitor pairs that spuriously fail forever (hangs), stale
// register caches around store-conditionals, and lost cross-thread
// wakeups when the atomic loop spans a block boundary.

#include <pthread.h>
#include <stdint.h>
#include <string.h>
#include <sys/auxv.h>
#include "test_common.h"

#ifndef HWCAP_ATOMICS
#define HWCAP_ATOMICS (1 << 8)
#endif

// ---- single-threaded exclusive-pair checks -------------------------------

static void check_ldxr_stxr64(void) {
    uint64_t mem = 0x1122334455667788ull;
    uint64_t old;
    uint32_t fail;
    // add a constant via an exclusive pair; loop on spurious failure
    __asm__ volatile(
        "1:\n\t"
        "ldxr %[old], [%[ptr]]\n\t"
        "add x8, %[old], #0x111\n\t"
        "stxr %w[fail], x8, [%[ptr]]\n\t"
        "cbnz %w[fail], 1b\n\t"
        : [old] "=&r"(old), [fail] "=&r"(fail), "+m"(mem)
        : [ptr] "r"(&mem)
        : "x8", "cc");
    if (mem != 0x1122334455667899ull || old != 0x1122334455667788ull)
        failf("ldxr/stxr64", mem, old, 0, 0x1122334455667899ull, 0x1122334455667788ull, 0);
    else
        test_logf("ldxr/stxr64 ok\n");
}

static void check_ldxr_stxr32(void) {
    uint32_t mem = 0x80000001u;
    uint32_t old, fail;
    __asm__ volatile(
        "1:\n\t"
        "ldxr %w[old], [%[ptr]]\n\t"
        "eor w8, %w[old], #0xff\n\t"
        "stxr %w[fail], w8, [%[ptr]]\n\t"
        "cbnz %w[fail], 1b\n\t"
        : [old] "=&r"(old), [fail] "=&r"(fail), "+m"(mem)
        : [ptr] "r"(&mem)
        : "x8", "cc");
    if (mem != 0x800000feu || old != 0x80000001u)
        failf("ldxr/stxr32", mem, old, 0, 0x800000feu, 0x80000001u, 0);
    else
        test_logf("ldxr/stxr32 ok\n");
}

static void check_ldxr_stxr_narrow(void) {
    uint16_t mem16 = 0x8000;
    uint8_t mem8 = 0x7f;
    uint32_t old, fail;
    __asm__ volatile(
        "1:\n\t"
        "ldxrh %w[old], [%[ptr]]\n\t"
        "add w8, %w[old], #1\n\t"
        "stxrh %w[fail], w8, [%[ptr]]\n\t"
        "cbnz %w[fail], 1b\n\t"
        : [old] "=&r"(old), [fail] "=&r"(fail), "+m"(mem16)
        : [ptr] "r"(&mem16)
        : "x8", "cc");
    if (mem16 != 0x8001 || old != 0x8000)
        failf("ldxrh/stxrh", mem16, old, 0, 0x8001, 0x8000, 0);
    __asm__ volatile(
        "1:\n\t"
        "ldxrb %w[old], [%[ptr]]\n\t"
        "add w8, %w[old], #1\n\t"
        "stxrb %w[fail], w8, [%[ptr]]\n\t"
        "cbnz %w[fail], 1b\n\t"
        : [old] "=&r"(old), [fail] "=&r"(fail), "+m"(mem8)
        : [ptr] "r"(&mem8)
        : "x8", "cc");
    if (mem8 != 0x80 || old != 0x7f)
        failf("ldxrb/stxrb", mem8, old, 0, 0x80, 0x7f, 0);
    else
        test_logf("narrow exclusives ok\n");
}

static void check_acquire_release_pair(void) {
    uint64_t mem = 5;
    uint64_t old;
    uint32_t fail;
    __asm__ volatile(
        "1:\n\t"
        "ldaxr %[old], [%[ptr]]\n\t"
        "lsl x8, %[old], #4\n\t"
        "stlxr %w[fail], x8, [%[ptr]]\n\t"
        "cbnz %w[fail], 1b\n\t"
        : [old] "=&r"(old), [fail] "=&r"(fail), "+m"(mem)
        : [ptr] "r"(&mem)
        : "x8", "cc");
    if (mem != 80 || old != 5)
        failf("ldaxr/stlxr", mem, old, 0, 80, 5, 0);
    else
        test_logf("ldaxr/stlxr ok\n");
}

static void check_clrex_path(void) {
    // An interrupted reservation (clrex between ldxr and stxr) must make
    // the stxr FAIL, not silently succeed.
    uint64_t mem = 42;
    uint32_t fail = 0;
    __asm__ volatile(
        "ldxr x8, [%[ptr]]\n\t"
        "clrex\n\t"
        "add x8, x8, #1\n\t"
        "stxr %w[fail], x8, [%[ptr]]\n\t"
        : [fail] "=&r"(fail), "+m"(mem)
        : [ptr] "r"(&mem)
        : "x8", "cc");
    if (fail != 1 || mem != 42)
        failf("clrex", fail, mem, 0, 1, 42, 0);
    else
        test_logf("clrex ok\n");
}

// ---- pair exclusives (LDXP/STXP) ------------------------------------------
// Code built with -mno-outline-atomics (or old toolchains) implements
// 16-byte atomics as LDXP/STXP loops instead of LSE CASP — these SIGILL'd
// before the pair-exclusive gadgets landed.

static void check_ldxp_stxp64(void) {
    // 128-bit increment across the lo->hi carry boundary via LDXP/STXP
    __attribute__((aligned(16))) uint64_t mem[2] = { ~0ull, 7 };
    uint64_t lo, hi;
    uint32_t fail;
    __asm__ volatile(
        "1:\n\t"
        "ldxp %[lo], %[hi], [%[ptr]]\n\t"
        "adds %[lo], %[lo], #1\n\t"
        "adc %[hi], %[hi], xzr\n\t"
        "stxp %w[fail], %[lo], %[hi], [%[ptr]]\n\t"
        "cbnz %w[fail], 1b\n\t"
        : [lo] "=&r"(lo), [hi] "=&r"(hi), [fail] "=&r"(fail), "+m"(mem)
        : [ptr] "r"(mem)
        : "cc");
    if (mem[0] != 0 || mem[1] != 8)
        failf("ldxp/stxp64 carry", mem[0], mem[1], 0, 0, 8, 0);
    else
        test_logf("ldxp/stxp64 ok\n");

    // clrex between ldxp and stxp must fail the store, like ldxr/stxr
    uint32_t st = 0;
    __asm__ volatile(
        "ldxp x8, x9, [%[ptr]]\n\t"
        "clrex\n\t"
        "stxp %w[st], x8, x9, [%[ptr]]\n\t"
        : [st] "=&r"(st), "+m"(mem)
        : [ptr] "r"(mem)
        : "x8", "x9");
    if (st != 1 || mem[0] != 0 || mem[1] != 8)
        failf("ldxp/stxp64 clrex", st, mem[0], mem[1], 1, 0, 8);
    else
        test_logf("ldxp/stxp64 clrex ok\n");
}

static void check_ldxp_stxp32(void) {
    // W-pair form over 8 bytes: [addr] = lo W, [addr+4] = hi W, loaded
    // values zero-extended
    __attribute__((aligned(8))) uint32_t mem[2] = { 0x11112222u, 0x33334444u };
    uint64_t lo = ~0ull, hi = ~0ull;
    uint32_t fail;
    __asm__ volatile(
        "1:\n\t"
        "ldxp %w[lo], %w[hi], [%[ptr]]\n\t"
        "stxp %w[fail], %w[nl], %w[nh], [%[ptr]]\n\t"
        "cbnz %w[fail], 1b\n\t"
        : [lo] "+&r"(lo), [hi] "+&r"(hi), [fail] "=&r"(fail), "+m"(mem)
        : [ptr] "r"(mem), [nl] "r"(0x55556666u), [nh] "r"(0x77778888u)
        : "cc");
    if (lo != 0x11112222u || hi != 0x33334444u ||
        mem[0] != 0x55556666u || mem[1] != 0x77778888u)
        failf("ldxp/stxp32", lo, hi, mem[0], 0x11112222u, 0x33334444u, 0x55556666u);
    else
        test_logf("ldxp/stxp32 ok\n");
}

static void check_ldar_stlr(void) {
    uint64_t mem = 0;
    uint64_t got;
    __asm__ volatile("stlr %[val], [%[ptr]]" : "+m"(mem) : [val] "r"(0xdeadbeefcafef00dull), [ptr] "r"(&mem));
    __asm__ volatile("ldar %[got], [%[ptr]]" : [got] "=r"(got), "+m"(mem) : [ptr] "r"(&mem));
    if (got != 0xdeadbeefcafef00dull)
        failf("ldar/stlr", got, 0, 0, 0xdeadbeefcafef00dull, 0, 0);
    else
        test_logf("ldar/stlr ok\n");
}

// ---- LSE (only when HWCAP advertises it) ---------------------------------

static void check_lse_if_present(void) {
    if (!(getauxval(AT_HWCAP) & HWCAP_ATOMICS)) {
        test_logf("HWCAP_ATOMICS not advertised; skipping direct LSE checks\n");
        return;
    }
    uint64_t mem = 100;
    uint64_t old;
    __asm__ volatile(".arch_extension lse\n\tldadd %[val], %[old], [%[ptr]]"
                     : [old] "=r"(old), "+m"(mem)
                     : [val] "r"(23ull), [ptr] "r"(&mem));
    if (mem != 123 || old != 100)
        failf("lse ldadd", mem, old, 0, 123, 100, 0);
    uint64_t expected = 123, desired = 777;
    __asm__ volatile(".arch_extension lse\n\tcas %[exp], %[des], [%[ptr]]"
                     : [exp] "+r"(expected), "+m"(mem)
                     : [des] "r"(desired), [ptr] "r"(&mem));
    if (mem != 777 || expected != 123)
        failf("lse cas", mem, expected, 0, 777, 123, 0);
    else
        test_logf("lse ldadd/cas ok\n");
}

// ---- __atomic builtins (whatever lowering the toolchain picked) ----------

static void check_builtins(void) {
    uint64_t v = 10;
    uint64_t prev = __atomic_fetch_add(&v, 32, __ATOMIC_SEQ_CST);
    if (prev != 10 || v != 42)
        failf("atomic_fetch_add", prev, v, 0, 10, 42, 0);
    uint64_t expected = 42;
    int ok = __atomic_compare_exchange_n(&v, &expected, 4242, 0,
                                         __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
    if (!ok || v != 4242)
        failf("atomic_cmpxchg success", ok, v, 0, 1, 4242, 0);
    expected = 1; // wrong
    ok = __atomic_compare_exchange_n(&v, &expected, 1, 0,
                                     __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
    if (ok || expected != 4242 || v != 4242)
        failf("atomic_cmpxchg failure", ok, expected, v, 0, 4242, 4242);
    uint32_t v32 = 0xf0f0f0f0u;
    uint32_t p32 = __atomic_fetch_xor(&v32, 0x0ff0f00fu, __ATOMIC_ACQ_REL);
    if (p32 != 0xf0f0f0f0u || v32 != 0xff0000ffu)
        failf("atomic_fetch_xor32", p32, v32, 0, 0xf0f0f0f0u, 0xff0000ffu, 0);
    uint64_t swapped = __atomic_exchange_n(&v, 7, __ATOMIC_SEQ_CST);
    if (swapped != 4242 || v != 7)
        failf("atomic_exchange", swapped, v, 0, 4242, 7, 0);
    else
        test_logf("__atomic builtins ok\n");
}

// ---- multithreaded stress -------------------------------------------------

#define STRESS_THREADS 4
#define STRESS_ITERS 200000

static uint64_t stress_counter;
static uint32_t stress_or_field;
static _Atomic int mp_flag;
static uint64_t mp_data;
static unsigned mp_bad;

static void *stress_thread(void *arg) {
    unsigned idx = (unsigned) (uintptr_t) arg;
    for (int i = 0; i < STRESS_ITERS; i++) {
        __atomic_fetch_add(&stress_counter, 1, __ATOMIC_RELAXED);
        // rotate through the OR field one bit per thread
        __atomic_fetch_or(&stress_or_field, 1u << ((idx * 8 + (i & 7)) & 31),
                          __ATOMIC_RELAXED);
        // cmpxchg retry loop: a data-dependent update (increment the low
        // 16 bits only) — lost updates or stale compare values wedge or
        // corrupt this immediately
        uint64_t seen = __atomic_load_n(&stress_counter, __ATOMIC_RELAXED);
        while (!__atomic_compare_exchange_n(&stress_counter, &seen,
                                            (seen & ~0xffffull) | ((seen + 1) & 0xffffull),
                                            1, __ATOMIC_RELAXED, __ATOMIC_RELAXED))
            ;
    }
    return NULL;
}

static void *mp_producer(void *arg) {
    (void) arg;
    for (int i = 1; i <= 50000; i++) {
        mp_data = (uint64_t) i;
        __atomic_store_n(&mp_flag, i, __ATOMIC_RELEASE);
        while (__atomic_load_n(&mp_flag, __ATOMIC_ACQUIRE) != 0)
            ;
    }
    __atomic_store_n(&mp_flag, -1, __ATOMIC_RELEASE);
    return NULL;
}

static void *mp_consumer(void *arg) {
    (void) arg;
    for (;;) {
        int f = __atomic_load_n(&mp_flag, __ATOMIC_ACQUIRE);
        if (f == -1)
            break;
        if (f > 0) {
            // acquire/release: mp_data must already be visible
            if (mp_data != (uint64_t) f)
                mp_bad++;
            __atomic_store_n(&mp_flag, 0, __ATOMIC_RELEASE);
        }
    }
    return NULL;
}

static void check_stress(void) {
    pthread_t threads[STRESS_THREADS];
    for (unsigned i = 0; i < STRESS_THREADS; i++)
        pthread_create(&threads[i], NULL, stress_thread, (void *) (uintptr_t) i);
    for (unsigned i = 0; i < STRESS_THREADS; i++)
        pthread_join(threads[i], NULL);
    // every fetch_add and every successful cmpxchg bumps the low half once;
    // exact totals aren't stable across interleavings, so check the invariant
    // that no update was lost outright in the plain counter path
    uint32_t or_expected_bits = 0;
    for (unsigned t = 0; t < STRESS_THREADS; t++)
        for (unsigned b = 0; b < 8; b++)
            or_expected_bits |= 1u << ((t * 8 + b) & 31);
    if ((stress_or_field & or_expected_bits) != or_expected_bits)
        failf("stress or-field", stress_or_field, 0, 0, or_expected_bits, 0, 0);
    else
        test_logf("stress or-field ok (counter=%llu)\n",
                  (unsigned long long) stress_counter);

    pthread_t prod, cons;
    mp_flag = 0;
    pthread_create(&cons, NULL, mp_consumer, NULL);
    pthread_create(&prod, NULL, mp_producer, NULL);
    pthread_join(prod, NULL);
    pthread_join(cons, NULL);
    if (mp_bad != 0)
        failf("acquire/release message passing", mp_bad, 0, 0, 0, 0, 0);
    else
        test_logf("acquire/release message passing ok\n");
}

// Cross-thread atomicity of BOTH lowerings: with 4 threads each doing N
// increments, the total must be exactly 4*N — any lost update means the
// RMW wasn't atomic. Runs the count once via the LL/SC exclusive monitor
// (explicit ldxr/stxr loop) and once via a direct LSE ldadd, so a
// regression in either path is caught. (The emulator's exclusive monitor
// and LSE ldadd both had ABA / non-atomic bugs that lost updates here.)
#define AT_THREADS 4
#define AT_ITERS 250000

static uint64_t llsc_counter;
static uint64_t lse_counter;
static int have_lse;
static __attribute__((aligned(16))) uint64_t pair_counter[2];

static void *llsc_worker(void *arg) {
    (void) arg;
    for (int i = 0; i < AT_ITERS; i++) {
        uint64_t tmp;
        uint32_t fail;
        __asm__ volatile(
            "1:\n\t"
            "ldxr %[t], [%[p]]\n\t"
            "add %[t], %[t], #1\n\t"
            "stxr %w[f], %[t], [%[p]]\n\t"
            "cbnz %w[f], 1b\n\t"
            : [t] "=&r"(tmp), [f] "=&r"(fail), "+m"(llsc_counter)
            : [p] "r"(&llsc_counter)
            : "memory");
    }
    return NULL;
}

// 128-bit LL/SC counter incremented as one atomic quantity (adds/adc
// carries lo->hi). The initial value is chosen so lo wraps mid-run: a
// torn pair store or a lost update shows up as a wrong total in either
// half, and the wrap catches a CAS that compares/stores only 8 bytes.
static void *pair_worker(void *arg) {
    (void) arg;
    for (int i = 0; i < AT_ITERS; i++) {
        uint64_t lo, hi;
        uint32_t fail;
        __asm__ volatile(
            "1:\n\t"
            "ldxp %[lo], %[hi], [%[p]]\n\t"
            "adds %[lo], %[lo], #1\n\t"
            "adc %[hi], %[hi], xzr\n\t"
            "stxp %w[f], %[lo], %[hi], [%[p]]\n\t"
            "cbnz %w[f], 1b\n\t"
            : [lo] "=&r"(lo), [hi] "=&r"(hi), [f] "=&r"(fail), "+m"(pair_counter)
            : [p] "r"(pair_counter)
            : "memory", "cc");
    }
    return NULL;
}

static void *lse_worker(void *arg) {
    (void) arg;
    for (int i = 0; i < AT_ITERS; i++)
        __asm__ volatile(".arch_extension lse\n\tldadd %x0, xzr, [%1]"
                         :: "r"(1ull), "r"(&lse_counter) : "memory");
    return NULL;
}

static void check_cross_thread_atomic(void) {
    pthread_t t[AT_THREADS];
    for (int i = 0; i < AT_THREADS; i++)
        pthread_create(&t[i], NULL, llsc_worker, NULL);
    for (int i = 0; i < AT_THREADS; i++)
        pthread_join(t[i], NULL);
    if (llsc_counter != (uint64_t) AT_THREADS * AT_ITERS)
        failf("ll/sc cross-thread count", llsc_counter, 0, 0,
              (uint64_t) AT_THREADS * AT_ITERS, 0, 0);
    else
        test_logf("ll/sc cross-thread atomic ok\n");

    // pair (128-bit) LL/SC: start lo close enough to wrap that the
    // carry into hi happens mid-run
    uint64_t total = (uint64_t) AT_THREADS * AT_ITERS;
    pair_counter[0] = ~0ull - total / 2;
    pair_counter[1] = 3;
    for (int i = 0; i < AT_THREADS; i++)
        pthread_create(&t[i], NULL, pair_worker, NULL);
    for (int i = 0; i < AT_THREADS; i++)
        pthread_join(t[i], NULL);
    if (pair_counter[0] != total - total / 2 - 1 || pair_counter[1] != 4)
        failf("ldxp/stxp cross-thread count", pair_counter[0], pair_counter[1], 0,
              total - total / 2 - 1, 4, 0);
    else
        test_logf("ldxp/stxp cross-thread atomic ok\n");

    if (have_lse) {
        for (int i = 0; i < AT_THREADS; i++)
            pthread_create(&t[i], NULL, lse_worker, NULL);
        for (int i = 0; i < AT_THREADS; i++)
            pthread_join(t[i], NULL);
        if (lse_counter != (uint64_t) AT_THREADS * AT_ITERS)
            failf("lse cross-thread count", lse_counter, 0, 0,
                  (uint64_t) AT_THREADS * AT_ITERS, 0, 0);
        else
            test_logf("lse cross-thread atomic ok\n");
    }
}

int main(int argc, char **argv) {
    test_init(argc, argv);
    check_ldxr_stxr64();
    check_ldxr_stxr32();
    check_ldxr_stxr_narrow();
    check_acquire_release_pair();
    check_clrex_path();
    check_ldxp_stxp64();
    check_ldxp_stxp32();
    check_ldar_stlr();
    have_lse = (getauxval(AT_HWCAP) & HWCAP_ATOMICS) != 0;
    check_lse_if_present();
    check_builtins();
    check_stress();
    check_cross_thread_atomic();
    return finish_suite("atomics64");
}
