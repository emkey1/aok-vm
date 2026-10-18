// aokvm_addr32_vec.c -- AOK VM's own (not iSH-AOK's): 67, the address-size prefix, on the vector insns in
// 64-bit code, which the engine computes itself (TCG has no AVX-512): the address is the 32-bit sum, wrapped,
// and fs's or gs's base (64 bits) is added after the wrap. VEX loads and stores, EVEX ones, an opmask load,
// eip-relative, and a gather whose elements wrap. Each result against the memory read the plain way. The VEX
// part runs on any AVX2 machine (camd's Ryzen), the rest where CPUID offers AVX-512F/VL (Intel SDE's -spr).
#define _GNU_SOURCE
#include <asm/prctl.h>
#include <cpuid.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

#define LOW  0x10000000ul       // a page below 4 GB
#define HIGH 0x300000000ul      // and one above, for gs's base
static int fails, checks;

static void check(int ok, const char *what)
{
    checks++;
    if (!ok) {
        fails++;
        printf("FAIL %s\n", what);
    }
}

static uint8_t ripdata[32] __attribute__((aligned(32)));

int main(void)
{
    uint8_t *lo = mmap((void *)LOW, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
    uint8_t *hi = mmap((void *)HIGH, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
    uint8_t out[64] __attribute__((aligned(64)));
    unsigned a, b, c, d, has512 = 0;

    if (lo != (void *)LOW || hi != (void *)HIGH) {
        printf("aokvm_addr32_vec: SKIP (no pages at 0x%lx and 0x%lx)\n", LOW, HIGH);
        return 0;
    }
    for (int i = 0; i < 4096; i++) {
        lo[i] = (uint8_t)(i * 7 + 1);
        hi[i] = (uint8_t)(i * 13 + 5);
    }
    for (int i = 0; i < 32; i++)
        ripdata[i] = (uint8_t)(0xa0 + i);
    __cpuid_count(7, 0, a, b, c, d);
    has512 = (b >> 16 & 1) && (b >> 31 & 1);       // AVX512F, AVX512VL

    // VEX: the upper half of the base register is not part of the address
    uint64_t base = 0xdead000000000000ul | (LOW + 0x40);
    memset(out, 0, sizeof(out));
    __asm__ volatile("addr32 vmovdqu (%k1), %%ymm0\n vmovdqu %%ymm0, %0\n vzeroupper"
                     : "=m"(*(uint8_t (*)[32])out) : "r"(base) : "xmm0", "memory");
    check(!memcmp(out, lo + 0x40, 32), "vex load: rax's upper half ignored");
    // the sum wraps: 0xfffffff0 + 0x10000110 = 0x10000100
    uint64_t wrapbase = 0xfffffff0;
    memset(out, 0, sizeof(out));
    __asm__ volatile("addr32 vmovdqu 0x10000110(%k1), %%ymm0\n vmovdqu %%ymm0, %0\n vzeroupper"
                     : "=m"(*(uint8_t (*)[32])out) : "r"(wrapbase) : "xmm0", "memory");
    check(!memcmp(out, lo + 0x100, 32), "vex load: base + disp wraps at 4 GB");
    // index * scale wraps too: (LOW + 0x1000 + 0x7fffff10 * 2) mod 2^32 = LOW + 0xe20
    uint64_t ib = LOW + 0x1000, ix = 0x7fffff10;
    memset(out, 0, sizeof(out));
    __asm__ volatile("addr32 vmovdqu (%k1,%k2,2), %%ymm0\n vmovdqu %%ymm0, %0\n vzeroupper"
                     : "=m"(*(uint8_t (*)[32])out) : "r"(ib), "r"(ix) : "xmm0", "memory");
    check(!memcmp(out, lo + 0xe20, 32), "vex load: base + index * scale wraps");
    // a store through a wrapped address
    __asm__ volatile("vmovdqu %1, %%ymm1\n addr32 vmovdqu %%ymm1, 0x10000210(%k0)\n vzeroupper"
                     :: "r"(wrapbase), "m"(*(const uint8_t (*)[32])ripdata) : "xmm1", "memory");
    check(!memcmp(lo + 0x200, ripdata, 32), "vex store: base + disp wraps");
    // eip-relative, where the code is below 4 GB (a static non-PIE program: tests.list builds it -no-pie);
    // above, eip is not where the code is and the load faults, on the hardware too
    if ((uintptr_t)ripdata < (1ul << 32)) {
        memset(out, 0, sizeof(out));
        __asm__ volatile("addr32 vmovdqu ripdata(%%eip), %%ymm0\n vmovdqu %%ymm0, %0\n vzeroupper"
                         : "=m"(*(uint8_t (*)[32])out) :: "xmm0", "memory");
        check(!memcmp(out, ripdata, 32), "vex load: eip-relative");
    } else {
        printf("(eip-relative skipped: the program is above 4 GB, a PIE)\n");
    }
    // gs's base is 64 bits, added after the wrap: (0xfffffff0 + 0x10 + 0x80) mod 2^32 = 0x80, at HIGH + 0x80
    if (syscall(SYS_arch_prctl, ARCH_SET_GS, HIGH) == 0) {
        memset(out, 0, sizeof(out));
        __asm__ volatile("addr32 vmovdqu %%gs:0x90(%k1), %%ymm0\n vmovdqu %%ymm0, %0\n vzeroupper"
                         : "=m"(*(uint8_t (*)[32])out) : "r"(wrapbase) : "xmm0", "memory");
        check(!memcmp(out, hi + 0x80, 32), "vex load: gs's 64-bit base after the wrap");
    }

    if (has512) {
        memset(out, 0, sizeof(out));
        __asm__ volatile("addr32 vmovdqu32 0x10000110(%k1), %%zmm0\n vmovdqu32 %%zmm0, %0\n vzeroupper"
                         : "=m"(*(uint8_t (*)[64])out) : "r"(wrapbase) : "xmm0", "memory");
        check(!memcmp(out, lo + 0x100, 64), "evex load: base + disp wraps");
        memset(out, 0, sizeof(out));
        __asm__ volatile("addr32 vmovdqu32 %%gs:0x90(%k1), %%zmm0\n vmovdqu32 %%zmm0, %0\n vzeroupper"
                         : "=m"(*(uint8_t (*)[64])out) : "r"(wrapbase) : "xmm0", "memory");
        check(!memcmp(out, hi + 0x80, 64), "evex load: gs's base after the wrap");
        // a masked store, half the dwords
        memset(lo + 0x400, 0x55, 64);
        __asm__ volatile("mov $0x5555, %%eax\n kmovw %%eax, %%k1\n vmovdqu32 %1, %%zmm1\n"
                         " addr32 vmovdqu32 %%zmm1, 0x10000410(%k0)%{%%k1%}\n vzeroupper"
                         :: "r"(wrapbase), "m"(*(const uint8_t (*)[64])hi) : "eax", "xmm1", "memory");
        int ok = 1;
        for (int i = 0; i < 16; i++)
            ok &= !memcmp(lo + 0x400 + 4 * i, (i & 1) ? (const uint8_t *)"\x55\x55\x55\x55" : hi + 4 * i, 4);
        check(ok, "evex masked store: base + disp wraps");
        // an opmask load through a wrapped address
        uint64_t k = 0;
        __asm__ volatile("addr32 kmovw 0x10000510(%k1), %%k2\n kmovw %%k2, %%eax\n mov %%rax, %0"
                         : "=r"(k) : "r"(wrapbase) : "rax");
        check((uint16_t)k == (uint16_t)(lo[0x500] | lo[0x501] << 8), "kmovw load: base + disp wraps");
        // a gather whose elements wrap: base 0xfffffff0, indices LOW + 0x10 + 4 i
        uint32_t idx[16] __attribute__((aligned(64))), got[16] __attribute__((aligned(64)));
        for (int i = 0; i < 16; i++)
            idx[i] = (uint32_t)(LOW + 0x10 + 0x600 + 4 * i);
        __asm__ volatile("vmovdqu32 %1, %%zmm2\n kxnorw %%k0, %%k0, %%k3\n vpxord %%zmm3, %%zmm3, %%zmm3\n"
                         " addr32 vpgatherdd (%k2,%%zmm2,1), %%zmm3%{%%k3%}\n vmovdqu32 %%zmm3, %0\n vzeroupper"
                         : "=m"(got) : "m"(idx), "r"(wrapbase) : "xmm2", "xmm3", "memory");
        ok = 1;
        for (int i = 0; i < 16; i++)
            ok &= !memcmp(&got[i], lo + 0x600 + 4 * i, 4);
        check(ok, "evex gather: each element's address wraps");
    }
    printf("aokvm_addr32_vec: %s (%d checks, %d failures%s)\n", fails ? "FAIL" : "PASS", checks, fails,
           has512 ? "" : ", no AVX-512");
    return fails != 0;
}
