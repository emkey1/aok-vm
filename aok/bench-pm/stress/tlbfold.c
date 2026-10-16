/*
 * tlbfold: the softmmu fast path's check for an access that crosses a page,
 * where the TLB index is folded (tctiSH's CPU_TLB_INDEX_FOLD: page ^ page >> 8).
 * Pages 0x7ffff and 0x80000 then share a slot at every TLB size up to 4096
 * entries, so once 0x80000000 has been touched, the slot that a load from the
 * end of page 0x7ffff looks in holds 0x80000000's entry. A fast path that
 * checks the page of the access's last byte (or of addr + 7) against it takes
 * the entry for its own and reads 0x80000000's host page at -4.
 *
 * Each round writes a fresh value at the end of the first page and in the
 * second, touches the second, and reads the first back: by words at the last
 * 8 bytes, by halfwords, a doubleword through the FPU, and words that do
 * cross the boundary (misaligned, which the G4 does in hardware).
 *
 * Prints TLBFOLD FAIL lines (at most 20), then TLBFOLD ok or bad and counts.
 */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>

#define BOUNDARY 0x80000000u

static int fails;

#define FAIL(...) do {                                                      \
        if (fails++ < 20) {                                                 \
            printf("TLBFOLD FAIL " __VA_ARGS__);                            \
        }                                                                   \
    } while (0)

static inline uint32_t ld32(uintptr_t a)
{
    return *(volatile uint32_t *)a;
}

static inline uint16_t ld16(uintptr_t a)
{
    return *(volatile uint16_t *)a;
}

static inline void st32(uintptr_t a, uint32_t v)
{
    *(volatile uint32_t *)a = v;
}

int main(void)
{
    uintptr_t lo = BOUNDARY - 0x1000;
    void *m = mmap((void *)lo, 0x2000, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
    long checks = 0;

    if (m != (void *)lo) {
        printf("TLBFOLD skip: no mapping at %#lx\n", (unsigned long)lo);
        return 0;
    }
    for (uint32_t r = 1; r <= 20000; r++) {
        uint32_t a = 0x9e3779b9u * r, b = ~a;

        st32(BOUNDARY - 8, a);
        st32(BOUNDARY - 4, a ^ 0x5a5a5a5a);
        st32(BOUNDARY, b);
        st32(BOUNDARY + 4, b ^ 0xa5a5a5a5);

        /* The first page's last words, aligned: they cross nothing. */
        (void)ld32(BOUNDARY + 8);
        uint32_t w1 = ld32(BOUNDARY - 4);
        (void)ld32(BOUNDARY + 8);
        uint32_t w0 = ld32(BOUNDARY - 8);
        (void)ld32(BOUNDARY + 8);
        uint16_t h = ld16(BOUNDARY - 2);
        (void)ld32(BOUNDARY + 8);
        double d;
        memcpy(&d, (void *)(BOUNDARY - 8), 8);     /* lfd/stfd or two lwz */
        uint64_t dw;
        memcpy(&dw, &d, 8);
        checks += 4;
        if (w1 != (a ^ 0x5a5a5a5a)) {
            FAIL("round %u: word at -4 is %08x, not %08x\n", r, w1, a ^ 0x5a5a5a5a);
        }
        if (w0 != a) {
            FAIL("round %u: word at -8 is %08x, not %08x\n", r, w0, a);
        }
        if (h != ((a ^ 0x5a5a5a5a) & 0xffff)) {
            FAIL("round %u: halfword at -2 is %04x, not %04x\n", r, h, (a ^ 0x5a5a5a5a) & 0xffff);
        }
        if (dw != ((uint64_t)a << 32 | (a ^ 0x5a5a5a5a))) {
            FAIL("round %u: doubleword at -8 is %016llx\n", r, (unsigned long long)dw);
        }

        /* A store to the first page's last word, read back through the slow path's eyes: a byte at a time. */
        (void)ld32(BOUNDARY + 8);
        st32(BOUNDARY - 4, r);
        volatile uint8_t *p = (volatile uint8_t *)(BOUNDARY - 4);
        uint32_t back = (uint32_t)p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3];
        checks++;
        if (back != r) {
            FAIL("round %u: a word stored at -4 reads back by bytes as %08x\n", r, back);
        }

        /* Words that cross the boundary: two bytes from each page. */
        st32(BOUNDARY - 4, a);
        (void)ld32(BOUNDARY + 8);
        uint32_t x = ld32(BOUNDARY - 2);
        uint32_t want = (a & 0xffff) << 16 | b >> 16;
        checks++;
        if (x != want) {
            FAIL("round %u: the word across the boundary is %08x, not %08x\n", r, x, want);
        }
    }
    printf("TLBFOLD %s: %d of %ld checks wrong\n", fails ? "bad" : "ok", fails, checks);
    return fails != 0;
}
