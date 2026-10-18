/*
 * tlb_collide.c -- pages that share an entry of the emulator's software TLB
 * read and write correctly when used in turn, and a page that has been pushed
 * out of its entry loses its permissions when the guest takes them away.
 *
 * AOK's TLB is direct-mapped (emu/tlb.h: 1024 entries, index = page bits 0-9
 * xor bits 10-19). A page evicted by another that hashes to the same index is
 * kept for a while among the last few evicted (TLB_VICTIMS) and changes
 * places with the page in its entry when it is used again. So there are
 * entries that are valid but not where the first probe looks, and everything
 * that drops or narrows a mapping has to reach them too. This picks, out of a
 * reservation, five pages by that hash: three for one index (A, B, C) and two
 * for another (D, E), and
 *
 *   - reads and writes them in every order, values checked each time;
 *   - makes one read-only while it sits displaced: the next store faults,
 *     at that address, and the loads still work;
 *   - unmaps one while it sits displaced: the next load faults;
 *   - maps a different page over one while it sits displaced: the load
 *     sees the new page's bytes.
 *
 * On real hardware the hash means nothing and the test passes trivially.
 *
 * Exits 0 and prints "tlb_collide: PASS" on success.
 */
#define _GNU_SOURCE
#include <setjmp.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>

#include "test_common.h"

#define PG 4096
#define NPAGES 4096

static int test_fail(const char *test, const char *what) {
    printf("%s: FAIL %s\n", test, what);
    return 1;
}

static sigjmp_buf jb;
static void *volatile fault_addr;

static void on_segv(int sig, siginfo_t *si, void *uc) {
    (void) sig;
    (void) uc;
    fault_addr = si->si_addr;
    siglongjmp(jb, 1);
}

static unsigned tlb_index(uintptr_t addr) {
    return (unsigned) (((addr >> 12) ^ (addr >> 22)) & 1023);
}

__attribute__((noinline)) static uint64_t rd(volatile uint64_t *p) { return *p; }
__attribute__((noinline)) static void wr(volatile uint64_t *p, uint64_t v) { *p = v; }

// (A 32-bit guest makes two accesses of a 64-bit one, in either order.)
static int in_word(volatile uint64_t *p) {
    return (char *) fault_addr >= (char *) p && (char *) fault_addr < (char *) p + sizeof(*p);
}

// 1 if the access faulted (in the word given), 0 if it went through.
static int faults_rd(volatile uint64_t *p) {
    fault_addr = NULL;
    if (sigsetjmp(jb, 1) == 0) {
        (void) rd(p);
        return 0;
    }
    return in_word(p) ? 1 : -1;
}
static int faults_wr(volatile uint64_t *p, uint64_t v) {
    fault_addr = NULL;
    if (sigsetjmp(jb, 1) == 0) {
        wr(p, v);
        return 0;
    }
    return in_word(p) ? 1 : -1;
}

int main(void) {
    int failures = 0;
    char *base = mmap(NULL, (size_t) NPAGES * PG, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (base == MAP_FAILED)
        return test_fail("tlb_collide", "mmap");
    struct sigaction sa = {.sa_sigaction = on_segv, .sa_flags = SA_SIGINFO};
    sigemptyset(&sa.sa_mask);
    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);

    // A, B, C share an index; D, E share another.
    unsigned want = tlb_index((uintptr_t) base);
    uint64_t *pg[5];
    int n = 0;
    for (int k = 0; k < NPAGES && n < 3; k++)
        if (tlb_index((uintptr_t) base + (uintptr_t) k * PG) == want)
            pg[n++] = (uint64_t *) (base + (size_t) k * PG);
    for (int k = 0; k < NPAGES && n < 5; k++)
        if (tlb_index((uintptr_t) base + (uintptr_t) k * PG) == (want ^ 512))
            pg[n++] = (uint64_t *) (base + (size_t) k * PG);
    if (n < 5)
        return test_fail("tlb_collide", "the reservation has no five such pages");
    for (int i = 0; i < 5; i++) {
        if (mprotect(pg[i], PG, PROT_READ | PROT_WRITE) != 0)
            return test_fail("tlb_collide", "mprotect");
        pg[i][0] = 0x1000 + i;
        pg[i][1] = 0;
    }

    // Every order of use: each page keeps its own bytes.
    uint64_t shadow[5] = {0, 0, 0, 0, 0};
    unsigned seed = 12345;
    for (int round = 0; round < 20000 && failures == 0; round++) {
        seed = seed * 1103515245u + 12345u;
        int i = (int) ((seed >> 16) % 5), j = (int) ((seed >> 8) % 5);
        if (rd(&pg[i][0]) != 0x1000u + (unsigned) i || rd(&pg[i][1]) != shadow[i]) {
            printf("tlb_collide: round %d: page %d read %#llx, %#llx (want %#x, %#llx)\n", round, i,
                   (unsigned long long) pg[i][0], (unsigned long long) pg[i][1], 0x1000 + i,
                   (unsigned long long) shadow[i]);
            failures++;
        }
        shadow[j] += (uint64_t) round + 1;
        wr(&pg[j][1], shadow[j]);
    }
    // Strict alternation of two, then three, pages of one index.
    for (int round = 0; round < 3000; round++) {
        wr(&pg[0][1], (uint64_t) round);
        wr(&pg[1][1], (uint64_t) round + 7);
        if (rd(&pg[0][1]) != (uint64_t) round || rd(&pg[2][0]) != 0x1002 || rd(&pg[1][1]) != (uint64_t) round + 7) {
            printf("tlb_collide: alternation, round %d\n", round);
            failures++;
            break;
        }
    }

    // Narrowed while displaced: touch A (read and write), then B, so A is the
    // one pushed aside with a writable entry; then take A's write permission.
    wr(&pg[0][1], 1);
    (void) rd(&pg[0][0]);
    wr(&pg[1][1], 2);
    if (mprotect(pg[0], PG, PROT_READ) != 0)
        return test_fail("tlb_collide", "mprotect read-only");
    if (faults_wr(&pg[0][1], 99) != 1) {
        printf("tlb_collide: a store to a page made read-only while displaced did not fault there\n");
        failures++;
    }
    if (rd(&pg[0][1]) != 1 || rd(&pg[0][0]) != 0x1000) {
        printf("tlb_collide: the read-only page reads %#llx, %#llx\n", (unsigned long long) pg[0][0],
               (unsigned long long) pg[0][1]);
        failures++;
    }
    // ... and again after more evictions
    wr(&pg[3][1], 3);
    wr(&pg[1][1], 4);
    if (faults_wr(&pg[0][1], 99) != 1 || rd(&pg[0][1]) != 1) {
        printf("tlb_collide: the read-only page took a store after more evictions\n");
        failures++;
    }

    // Unmapped while displaced: touch C, then B and D; unmap C.
    wr(&pg[2][1], 5);
    wr(&pg[1][1], 6);
    wr(&pg[3][1], 7);
    (void) rd(&pg[2][1]);
    wr(&pg[1][1], 8);
    if (munmap(pg[2], PG) != 0)
        return test_fail("tlb_collide", "munmap");
    if (faults_rd(&pg[2][1]) != 1) {
        printf("tlb_collide: a load from a page unmapped while displaced did not fault there\n");
        failures++;
    }

    // Replaced while displaced: touch E, then D, which shares its index, then
    // map a fresh page over E.
    wr(&pg[4][1], 0xe);
    wr(&pg[3][1], 0xd);
    wr(&pg[0 + 1][1], 0xb);
    void *fresh = mmap(pg[4], PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    if (fresh != (void *) pg[4])
        return test_fail("tlb_collide", "mmap over a page");
    if (rd(&pg[4][0]) != 0 || rd(&pg[4][1]) != 0) {
        printf("tlb_collide: a page mapped over one that was displaced reads the old bytes (%#llx, %#llx)\n",
               (unsigned long long) pg[4][0], (unsigned long long) pg[4][1]);
        failures++;
    }
    wr(&pg[4][1], 0x4e);
    if (rd(&pg[3][1]) != 0xd || rd(&pg[1][1]) != 0xb || rd(&pg[4][1]) != 0x4e) {
        printf("tlb_collide: after the replacement the neighbours read wrong\n");
        failures++;
    }

    if (failures != 0) {
        printf("tlb_collide: FAIL failures=%d\n", failures);
        return 1;
    }
    printf("tlb_collide: PASS\n");
    return 0;
}
