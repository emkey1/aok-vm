/*
 * unaligned_page_edge.c -- loads and stores of 2, 4, 8 and 16 bytes at every
 * offset around a page boundary read and write the right bytes, and one that
 * runs into an unmapped page faults there (and, on x86 and arm64 guests, writes
 * nothing).
 *
 * The arm64 guest's memory gadgets fold the "does this access cross a page"
 * test into the TLB compare: the tag is compared with the address's page and
 * its low alignment bits together, so an aligned access hits in one compare
 * and everything else -- unaligned inside its page, crossing, or a real miss
 * -- is sorted out on a slower path (jit/guest-arm64/gadgets.h, read_prep).
 * Each of those three leaves by the same branch, which is what this walks:
 * every size at every offset from 24 bytes before a boundary to 8 after it,
 * against byte-wise copies, with a pair (16 bytes aligned to 8, which can
 * cross while aligned) on arm64.
 *
 * Exits 0 and prints "unaligned_page_edge: PASS" on success.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <setjmp.h>
#include <signal.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>

#include "test_common.h"

#define PG 4096
#define NOINLINE __attribute__((noinline))

static sigjmp_buf jb;
static void *volatile fault_addr;

static void on_segv(int sig, siginfo_t *si, void *uc) {
    (void) sig;
    (void) uc;
    fault_addr = si->si_addr;
    siglongjmp(jb, 1);
}

struct __attribute__((packed)) u16 { uint16_t v; };
struct __attribute__((packed)) u32 { uint32_t v; };
struct __attribute__((packed)) u64 { uint64_t v; };

NOINLINE static uint16_t ld16(volatile void *p) { return ((volatile struct u16 *) p)->v; }
NOINLINE static uint32_t ld32(volatile void *p) { return ((volatile struct u32 *) p)->v; }
NOINLINE static uint64_t ld64(volatile void *p) { return ((volatile struct u64 *) p)->v; }
NOINLINE static void st16(volatile void *p, uint16_t v) { ((volatile struct u16 *) p)->v = v; }
NOINLINE static void st32(volatile void *p, uint32_t v) { ((volatile struct u32 *) p)->v = v; }
NOINLINE static void st64(volatile void *p, uint64_t v) { ((volatile struct u64 *) p)->v = v; }

#ifdef __aarch64__
NOINLINE static void ldpair(volatile void *p, uint64_t out[2]) {
    __asm__ volatile("ldp x9, x10, [%0]\n stp x9, x10, [%1]" : : "r"(p), "r"(out) : "x9", "x10", "memory");
}
NOINLINE static void stpair(volatile void *p, uint64_t a, uint64_t b) {
    __asm__ volatile("stp %1, %2, [%0]" : : "r"(p), "r"(a), "r"(b) : "memory");
}
#else
NOINLINE static void ldpair(volatile void *p, uint64_t out[2]) { out[0] = ld64(p); out[1] = ld64((char *) p + 8); }
NOINLINE static void stpair(volatile void *p, uint64_t a, uint64_t b) { st64(p, a); st64((char *) p + 8, b); }
#endif

int main(int argc, char **argv) {
    test_init(argc, argv);
    unsigned char *m = mmap(NULL, 3 * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    static unsigned char ref[3 * PG];
    if (m == MAP_FAILED) {
        printf("FAIL mmap: %s\n", strerror(errno));
        return 1;
    }
    for (int i = 0; i < 3 * PG; i++)
        m[i] = ref[i] = (unsigned char) (i * 131 + 7);

    int bad = 0;
    for (int off = PG - 24; off <= PG + 8; off++) {
        uint16_t e16;
        uint32_t e32;
        uint64_t e64, e128[2], g128[2];
        memcpy(&e16, ref + off, 2);
        memcpy(&e32, ref + off, 4);
        memcpy(&e64, ref + off, 8);
        memcpy(e128, ref + off, 16);
        ldpair(m + off, g128);
        if (ld16(m + off) != e16 || ld32(m + off) != e32 || ld64(m + off) != e64 ||
                memcmp(g128, e128, 16) != 0) {
            printf("FAIL a load at %d bytes into the first page read the wrong bytes\n", off);
            bad++;
        }
    }
    for (int off = PG - 24; off <= PG + 8; off++) {
        uint64_t v = 0x1122334455667788ull ^ (uint64_t) off * 0x9e3779b97f4a7c15ull, nv = ~v, x = v ^ 0x55;
        st16(m + off, (uint16_t) v);
        memcpy(ref + off, &v, 2);
        st32(m + off + 40, (uint32_t) v);
        memcpy(ref + off + 40, &v, 4);
        st64(m + off + 80, v);
        memcpy(ref + off + 80, &v, 8);
        stpair(m + off + 120, v, nv);
        memcpy(ref + off + 120, &v, 8);
        memcpy(ref + off + 128, &nv, 8);
        st64(m + off, x);
        memcpy(ref + off, &x, 8);
        if (memcmp(m, ref, 3 * PG) != 0) {
            printf("FAIL the stores at %d bytes into the first page left the wrong bytes\n", off);
            memcpy(m, ref, 3 * PG);
            bad++;
        }
    }

    /* The last page goes; an 8-byte access 1..7 bytes before it must fault,
     * at an address in what it touched, and a store must write nothing. */
    munmap(m + 2 * PG, PG);
    struct sigaction sa = {.sa_sigaction = on_segv, .sa_flags = SA_SIGINFO};
    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
    for (int back = 1; back <= 7; back++) {
        unsigned char *p = m + 2 * PG - back;
        memcpy(ref, m, 2 * PG);
        if (sigsetjmp(jb, 1) == 0) {
            st64(p, 0xdeadbeefcafef00dull);
            printf("FAIL a store %d bytes before an unmapped page did not fault\n", back);
            bad++;
        } else if ((unsigned char *) fault_addr < p || (unsigned char *) fault_addr > p + 8) {
            printf("FAIL the store's fault address %p is not in %p..%p\n", fault_addr, (void *) p, (void *) (p + 8));
            bad++;
        }
#if defined(__x86_64__) || defined(__i386__) || defined(__aarch64__)
        /* x86 writes nothing when a store faults. Arm leaves the bytes that
         * did not fault UNKNOWN and RISC-V lets a misaligned store be done in
         * part, so neither is required to -- but AOK's arm64 guest does write
         * nothing, and that is kept. Its riscv64 guest writes the first
         * page's bytes before it faults on the second, which the architecture
         * allows (and a trap-emulated store on real hardware does). */
        else if (memcmp(ref, m, 2 * PG) != 0) {
            printf("FAIL a faulting store %d bytes before the page wrote part of itself\n", back);
            bad++;
        }
#endif
        if (sigsetjmp(jb, 1) == 0) {
            (void) ld64(p);
            printf("FAIL a load %d bytes before an unmapped page did not fault\n", back);
            bad++;
        }
    }
    failures_total += bad;
    return finish_suite("unaligned_page_edge");
}
