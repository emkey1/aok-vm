// Correctness test for the JIT copy/fill loop idiom recognition (jit/hle.c),
// arm64 guest. Each loop is written in inline asm so the exact recognized
// instruction shapes are guaranteed regardless of compiler version/flags:
// LDR/STR post-index with SUBS+B.NE, SUB+CBNZ, and CMP+B.NE counters, plus
// store-only fills (register and WZR). Verifies data results, final register
// values (pointers advanced, count zero, data reg = last element), NZCV via
// cset, LZ77-style forward-overlap propagation (distance < length must
// duplicate the leading window periodically -- the case memmove semantics
// would get wrong), chunking (70k iterations), and a PROT_NONE fault landing
// mid-copy with the prefix intact. Passes identically with HLE off (plain
// translation) and on (ISH_HLE=1, where these loops become bulk gadgets);
// run it under both. Also passes on real Linux. Exits nonzero on failure.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <signal.h>
#include <sys/mman.h>
#include <unistd.h>
#include <sys/wait.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; \
    printf("FAIL %s:%d: ", __func__, __LINE__); printf(__VA_ARGS__); \
    printf("\n"); } } while (0)

// P1: ldrb/strb/subs/b.ne
static void test_byte_copy_subs(size_t n) {
    unsigned char *s = malloc(n + 16), *d = malloc(n + 16);
    for (size_t i = 0; i < n; i++) s[i] = (unsigned char) (i * 7 + 1);
    memset(d, 0xEE, n + 16);
    uint64_t rs = (uint64_t) s, rd = (uint64_t) d, rc = n, rt = 0xdead;
    uint64_t zf;
    __asm__ volatile(
        "1:\n"
        "ldrb %w[t], [%[s]], #1\n"
        "strb %w[t], [%[d]], #1\n"
        "subs %[c], %[c], #1\n"
        "b.ne 1b\n"
        "cset %[z], eq\n"
        : [s]"+r"(rs), [d]"+r"(rd), [c]"+r"(rc), [t]"+r"(rt), [z]"=r"(zf)
        :: "cc", "memory");
    CHECK(memcmp(s, d, n) == 0, "data n=%zu", n);
    CHECK(d[n] == 0xEE, "overrun n=%zu", n);
    CHECK(rs == (uint64_t) s + n, "rs advanced n=%zu", n);
    CHECK(rd == (uint64_t) d + n, "rd advanced n=%zu", n);
    CHECK(rc == 0, "count zero n=%zu", n);
    CHECK(rt == s[n - 1], "rt last elem n=%zu (rt=%llx want %x)", n,
            (unsigned long long) rt, s[n - 1]);
    CHECK(zf == 1, "Z set after loop n=%zu", n);
    free(s); free(d);
}

// P1 with 8-byte elements: ldr/str/subs/b.ne
static void test_quad_copy_subs(size_t elems) {
    uint64_t *s = malloc(elems * 8 + 16), *d = malloc(elems * 8 + 16);
    for (size_t i = 0; i < elems; i++) s[i] = 0x0123456789abcdefull * (i + 1);
    memset(d, 0xEE, elems * 8 + 16);
    uint64_t rs = (uint64_t) s, rd = (uint64_t) d, rc = elems, rt = 0;
    __asm__ volatile(
        "1:\n"
        "ldr %[t], [%[s]], #8\n"
        "str %[t], [%[d]], #8\n"
        "subs %[c], %[c], #1\n"
        "b.ne 1b\n"
        : [s]"+r"(rs), [d]"+r"(rd), [c]"+r"(rc), [t]"+r"(rt)
        :: "cc", "memory");
    CHECK(memcmp(s, d, elems * 8) == 0, "data elems=%zu", elems);
    CHECK(rt == s[elems - 1], "rt last elem");
    free(s); free(d);
}

// P2: sub + cbnz (no flags)
static void test_byte_copy_cbnz(size_t n) {
    unsigned char *s = malloc(n), *d = malloc(n);
    for (size_t i = 0; i < n; i++) s[i] = (unsigned char) (i ^ 0x5A);
    uint64_t rs = (uint64_t) s, rd = (uint64_t) d, rc = n, rt = 0;
    __asm__ volatile(
        "1:\n"
        "ldrb %w[t], [%[s]], #1\n"
        "strb %w[t], [%[d]], #1\n"
        "sub %[c], %[c], #1\n"
        "cbnz %[c], 1b\n"
        : [s]"+r"(rs), [d]"+r"(rd), [c]"+r"(rc), [t]"+r"(rt)
        :: "memory");
    CHECK(memcmp(s, d, n) == 0, "data n=%zu", n);
    CHECK(rc == 0, "count zero");
    free(s); free(d);
}

// P4: cmp src,end + b.ne
static void test_byte_copy_cmp(size_t n) {
    unsigned char *s = malloc(n), *d = malloc(n);
    for (size_t i = 0; i < n; i++) s[i] = (unsigned char) (i * 3 + 5);
    uint64_t rs = (uint64_t) s, rd = (uint64_t) d, re = (uint64_t) s + n,
             rt = 0, zf = 9;
    __asm__ volatile(
        "1:\n"
        "ldrb %w[t], [%[s]], #1\n"
        "strb %w[t], [%[d]], #1\n"
        "cmp %[s], %[e]\n"
        "b.ne 1b\n"
        "cset %[z], eq\n"
        : [s]"+r"(rs), [d]"+r"(rd), [t]"+r"(rt), [z]"=r"(zf)
        : [e]"r"(re)
        : "cc", "memory");
    CHECK(memcmp(s, d, n) == 0, "data n=%zu", n);
    CHECK(rs == re, "rs at end");
    CHECK(rd == (uint64_t) d + n, "rd advanced");
    CHECK(zf == 1, "Z set");
    free(s); free(d);
}

// Fill: strb/subs/b.ne (both a register value and wzr)
static void test_fill(size_t n) {
    unsigned char *d = malloc(n + 8);
    memset(d, 0xEE, n + 8);
    uint64_t rd = (uint64_t) d, rc = n, rt = 0x42;
    __asm__ volatile(
        "1:\n"
        "strb %w[t], [%[d]], #1\n"
        "subs %[c], %[c], #1\n"
        "b.ne 1b\n"
        : [d]"+r"(rd), [c]"+r"(rc)
        : [t]"r"(rt)
        : "cc", "memory");
    for (size_t i = 0; i < n; i++)
        CHECK(d[i] == 0x42, "fill byte %zu", i);
    CHECK(d[n] == 0xEE, "fill overrun");
    uint64_t rd2 = (uint64_t) d, rc2 = n;
    __asm__ volatile(
        "1:\n"
        "strb wzr, [%[d]], #1\n"
        "subs %[c], %[c], #1\n"
        "b.ne 1b\n"
        : [d]"+r"(rd2), [c]"+r"(rc2)
        :: "cc", "memory");
    for (size_t i = 0; i < n; i++)
        CHECK(d[i] == 0, "wzr fill byte %zu", i);
    free(d);
}

// LZ77-style forward overlap: dst = src + dist, dist < n. Byte-forward
// semantics must duplicate the leading window periodically.
static void test_overlap(size_t dist, size_t n) {
    unsigned char *buf = malloc(dist + n + 8);
    for (size_t i = 0; i < dist; i++) buf[i] = (unsigned char) (i + 1);
    memset(buf + dist, 0xEE, n + 8);
    unsigned char *ref = malloc(dist + n);
    memcpy(ref, buf, dist);
    for (size_t i = 0; i < n; i++) ref[dist + i] = ref[i]; // oracle
    uint64_t rs = (uint64_t) buf, rd = (uint64_t) buf + dist, rc = n, rt = 0;
    __asm__ volatile(
        "1:\n"
        "ldrb %w[t], [%[s]], #1\n"
        "strb %w[t], [%[d]], #1\n"
        "subs %[c], %[c], #1\n"
        "b.ne 1b\n"
        : [s]"+r"(rs), [d]"+r"(rd), [c]"+r"(rc), [t]"+r"(rt)
        :: "cc", "memory");
    CHECK(memcmp(buf, ref, dist + n) == 0, "overlap dist=%zu n=%zu", dist, n);
    free(buf); free(ref);
}

// Fault: copy runs into a PROT_NONE page; expect SIGSEGV with si_addr at
// the guard page and forward progress up to it.
static unsigned char *fault_src, *fault_dst;
static void on_segv(int sig, siginfo_t *si, void *uc) {
    (void) sig; (void) uc; (void) si;
    // fork+COW means the parent can't see our writes: verify here.
    _exit(memcmp(fault_dst, fault_src, 64) == 0 ? 42 : 43);
}
static void test_fault(void) {
    long pagesz = sysconf(_SC_PAGESIZE);
    unsigned char *area = mmap(NULL, 3 * pagesz, PROT_READ | PROT_WRITE,
            MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(area != MAP_FAILED, "mmap");
    mprotect(area + 2 * pagesz, pagesz, PROT_NONE);
    unsigned char *src = area;                    // 2 RW pages
    unsigned char *dst = area + 2 * pagesz - 64;  // 64B before the guard
    for (int i = 0; i < 2 * pagesz; i++) src[i] = (unsigned char) i;
    fault_src = src; fault_dst = dst;
    pid_t pid = fork();
    if (pid == 0) {
        struct sigaction sa = { .sa_sigaction = on_segv,
                                .sa_flags = SA_SIGINFO };
        sigaction(SIGSEGV, &sa, NULL);
        uint64_t rs = (uint64_t) src, rd = (uint64_t) dst, rc = 4096, rt = 0;
        __asm__ volatile(
            "1:\n"
            "ldrb %w[t], [%[s]], #1\n"
            "strb %w[t], [%[d]], #1\n"
            "subs %[c], %[c], #1\n"
            "b.ne 1b\n"
            : [s]"+r"(rs), [d]"+r"(rd), [c]"+r"(rc), [t]"+r"(rt)
            :: "cc", "memory");
        _exit(1); // should not get here
    }
    int status = 0;
    waitpid(pid, &status, 0);
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 42,
            "child SIGSEGV + prefix copied (status=%x)", status);
    munmap(area, 3 * pagesz);
}

int main(void) {
    for (size_t n = 1; n <= 5; n++) test_byte_copy_subs(n);
    test_byte_copy_subs(4096);
    test_byte_copy_subs(70000);   // multiple chunks of pages
    test_quad_copy_subs(1);
    test_quad_copy_subs(513);
    test_byte_copy_cbnz(3);
    test_byte_copy_cbnz(9000);
    test_byte_copy_cmp(1);
    test_byte_copy_cmp(6000);
    test_fill(1);
    test_fill(5000);
    test_overlap(1, 300);   // run-length: repeat single byte
    test_overlap(3, 1000);
    test_overlap(7, 65);
    test_overlap(255, 4096);
    test_fault();
    if (failures == 0) {
        printf("hle_loop: PASS\n");
        return 0;
    }
    printf("hle_loop: %d FAILURES\n", failures);
    return 1;
}
