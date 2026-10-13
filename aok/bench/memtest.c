// memtest.c -- loads and stores where an engine's fast path does not apply.
//
// A transcript, like check.sh's: every line must be the same whichever engine ran it. What it covers that
// the programs of check.sh reach only by accident:
//
//   sweep   every size, signed and unsigned, at every alignment, in a page and across a page boundary,
//           with values whose sign bit is set
//   fault   accesses to pages that are not there yet: a SIGSEGV handler opens the page and returns, so the
//           instruction runs again. The loops advance a pointer and then use it, so an engine that runs two
//           guest instructions as one step must not repeat the first of them, and must report the second's
//           address. The handler hashes every fault address and the pc's distance from the last one.
//   cross   the same, for an access whose first bytes are in a mapped page and whose last are not
//   vreg    (aarch64) all of that for B, H, S, D and Q registers and pairs of them, in each addressing mode
//
// Built -O2 and with plain pointer dereferences on purpose: the compiler then emits one load or store
// instruction per access, misaligned or not.
#define _GNU_SOURCE
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <ucontext.h>
#include <unistd.h>

static size_t page;
static unsigned char *region;
static size_t region_size;
static volatile uint64_t fault_hash;
static volatile unsigned long faults;
static volatile uintptr_t last_pc;

static uint64_t mix(uint64_t h, uint64_t v) {
    h ^= v + 0x9e3779b97f4a7c15ull + (h << 6) + (h >> 2);
    return h * 0xff51afd7ed558ccdull;
}

static uintptr_t context_pc(void *uc_) {
    ucontext_t *uc = uc_;
#if defined(__riscv)
    return uc->uc_mcontext.__gregs[0];
#elif defined(__aarch64__)
    return uc->uc_mcontext.pc;
#else
    (void) uc;
    return 0;
#endif
}

static void on_segv(int sig, siginfo_t *si, void *uc) {
    uintptr_t addr = (uintptr_t) si->si_addr, pc = context_pc(uc);
    (void) sig;
    if (addr < (uintptr_t) region || addr >= (uintptr_t) region + region_size)
        _exit(3);
    faults++;
    // Where the fault was, and how far the pc moved since the last one: both depend on exactly which
    // instruction was restarted, neither on where the program was loaded.
    fault_hash = mix(fault_hash, addr - (uintptr_t) region);
    fault_hash = mix(fault_hash, last_pc ? pc - last_pc : 0);
    last_pc = pc;
    if (mprotect((void *) (addr & ~(page - 1)), page, PROT_READ | PROT_WRITE) != 0)
        _exit(4);
}

static void fresh_region(size_t pages, int prot) {
    if (region != NULL)
        munmap(region, region_size);
    region_size = pages * page;
    region = mmap(NULL, region_size, prot, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (region == MAP_FAILED)
        _exit(2);
    fault_hash = 0;
    faults = 0;
    last_pc = 0;
}

#define TYPES(X) X(int8_t) X(uint8_t) X(int16_t) X(uint16_t) X(int32_t) X(uint32_t) X(int64_t) X(uint64_t)

// One load and one store of each type, each its own function so that the access is a single instruction
// the caller's surroundings cannot fold away.
#define ACCESSORS(T) \
    static __attribute__((noinline)) uint64_t load_##T(const unsigned char *p) { \
        return (uint64_t) (int64_t) *(const volatile T *) p; \
    } \
    static __attribute__((noinline)) void store_##T(unsigned char *p, uint64_t v) { \
        *(volatile T *) p = (T) v; \
    }
TYPES(ACCESSORS)

static uint64_t sweep(void) {
    uint64_t h = 1;
    fresh_region(4, PROT_READ | PROT_WRITE);
    for (size_t i = 0; i < region_size; i++)
        region[i] = (unsigned char) (0x80 | (i * 131 + (i >> 8) * 17 + 7));
    // Around the boundary between the second and third pages, and around the middle of the first.
    for (int where = 0; where < 2; where++) {
        unsigned char *base = where == 0 ? region + 2 * page - 24 : region + 512;
        for (int off = 0; off < 48; off++) {
            unsigned char *p = base + off;
#define SWEEP(T) \
            h = mix(h, load_##T(p)); \
            store_##T(p, ~h ^ ((uint64_t) off << 56)); \
            h = mix(h, load_##T(p)); \
            h = mix(h, load_uint64_t(p - 8) ^ load_uint64_t(p + 1));
            TYPES(SWEEP)
        }
    }
    for (size_t i = 0; i < region_size; i++)
        h = mix(h, region[i]);
    return h;
}

// Pointer walks over pages that fault on first touch. The pointer is advanced and then used, or used and
// then advanced, by a stride that lands in a new page every few steps.
#define WALKS(T) \
    static __attribute__((noinline)) uint64_t walk_store_##T(unsigned char *p, long stride, long n) { \
        uint64_t v = 0x8123456789abcdefull; \
        for (long i = 0; i < n; i++) { \
            p += stride; \
            *(volatile T *) p = (T) v; \
            v = v * 6364136223846793005ull + 1442695040888963407ull; \
        } \
        return v; \
    } \
    static __attribute__((noinline)) uint64_t walk_load_##T(const unsigned char *p, long stride, long n) { \
        uint64_t h = 7; \
        for (long i = 0; i < n; i++) { \
            T a = *(const volatile T *) p; \
            p += stride; \
            T b = *(const volatile T *) p; \
            h = mix(h, (uint64_t) (int64_t) a + ((uint64_t) (int64_t) b << 1)); \
        } \
        return h; \
    }
TYPES(WALKS)

static uint64_t fault(long stride, long first) {
    uint64_t h = 3;
    long n = (long) ((region_size - 64) / (unsigned long) stride) - 2;
#define FAULT(T) \
    fresh_region(48, PROT_NONE); \
    h = mix(h, walk_store_##T(region + first, stride, n)); \
    h = mix(h, fault_hash); h = mix(h, faults); \
    h = mix(h, walk_load_##T(region + first, stride, n)); \
    fresh_region(48, PROT_NONE); \
    h = mix(h, walk_load_##T(region + first, stride, n)); \
    h = mix(h, fault_hash); h = mix(h, faults); \
    h = mix(h, walk_store_##T(region + first, stride, n)); \
    h = mix(h, walk_load_##T(region + first, stride, n));
    fresh_region(48, PROT_NONE);
    TYPES(FAULT)
    return h;
}

#if defined(__aarch64__)
// The same for FP and SIMD registers, which an engine may load and store by another path than X registers:
// every size, each addressing mode, and pairs. vmem_N(p, in, out) stores from registers loaded from in[],
// loads back with the matching instruction, and leaves in out[] what it read (two registers) and how far
// a write-back moved the base.
#define VMEM(n, body) \
    void vmem_##n(unsigned char *p, const uint64_t *in, uint64_t *out); \
    __asm__(".text\n.globl vmem_" #n "\nvmem_" #n ":\n" \
            "    ldp q0, q1, [x1]\n    movi v2.16b, #0\n    movi v3.16b, #0\n    mov x9, x0\n" \
            body \
            "    stp q2, q3, [x2]\n    sub x9, x9, x0\n    str x9, [x2, #32]\n    ret\n");
VMEM(0, "    str b0, [x0]\n    ldr b2, [x0]\n")
VMEM(1, "    str h0, [x0]\n    ldr h2, [x0]\n")
VMEM(2, "    str s0, [x0]\n    ldr s2, [x0]\n    str s1, [x0, #4]\n    ldr s3, [x0, #4]\n")
VMEM(3, "    str d0, [x0]\n    ldr d2, [x0]\n    str d1, [x0, #8]\n    ldr d3, [x0, #8]\n")
VMEM(4, "    str q0, [x0]\n    ldr q2, [x0]\n    str q1, [x0, #16]\n    ldr q3, [x0, #16]\n")
VMEM(5, "    add x10, x0, #3\n    stur q0, [x10, #-3]\n    ldur q2, [x10, #-3]\n" \
        "    stur d1, [x10, #5]\n    ldur d3, [x10, #5]\n")
VMEM(6, "    str q0, [x9], #16\n    str d1, [x9], #-16\n    ldr q2, [x9], #16\n    ldr d3, [x9], #8\n")
VMEM(7, "    sub x9, x9, #16\n    str q0, [x9, #16]!\n    ldr s3, [x9, #4]!\n    ldr q2, [x9, #-4]!\n")
VMEM(8, "    mov x10, #2\n    mov w11, #-8\n    add x12, x0, #8\n    str q0, [x0, x10]\n" \
        "    ldr q2, [x0, x10]\n    str d1, [x12, w11, sxtw]\n    ldr d3, [x0, x10, lsl #3]\n")
VMEM(9, "    stp s0, s1, [x0]\n    ldp s2, s3, [x0]\n")
VMEM(10, "    stp d0, d1, [x0]\n    ldp d2, d3, [x0]\n")
VMEM(11, "    stp q0, q1, [x0]\n    ldp q2, q3, [x0]\n")
VMEM(12, "    sub x9, x9, #32\n    stp q0, q1, [x9, #32]!\n    ldp q2, q3, [x9], #32\n" \
         "    stp d1, d0, [x9, #-16]!\n    ldp d3, d2, [x9, #-16]\n")
// The structure loads and stores: whole registers (one to four, with and without post-index), the
// interleaved ones, one lane, and the replicating loads. And ldpsw, which is of X registers but no body
// of the plain pairs.
VMEM(13, "    st1 {v0.16b}, [x0]\n    ld1 {v2.4s}, [x0]\n    st1 {v1.1d}, [x0]\n    ld1 {v3.8b}, [x0]\n")
VMEM(14, "    st1 {v0.2d, v1.2d}, [x9], #32\n    sub x9, x9, #32\n    ld1 {v2.16b, v3.16b}, [x9], #32\n")
VMEM(15, "    mov x10, #24\n    st1 {v0.8b, v1.8b}, [x9], x10\n    sub x9, x9, #24\n" \
         "    ld1 {v2.4h, v3.4h}, [x9], x10\n    st1 {v0.2s}, [x9], #8\n")
VMEM(16, "    st1 {v0.16b, v1.16b, v2.16b}, [x0]\n    ld1 {v2.8h, v3.8h, v4.8h, v5.8h}, [x9], #64\n" \
         "    st1 {v2.2d, v3.2d, v4.2d, v5.2d}, [x0]\n    ld1 {v3.2d, v4.2d, v5.2d}, [x0]\n")
VMEM(17, "    st2 {v0.4s, v1.4s}, [x0]\n    ld2 {v2.8h, v3.8h}, [x0]\n    st3 {v0.8b, v1.8b, v2.8b}, [x9], #24\n" \
         "    ld4 {v2.2d, v3.2d, v4.2d, v5.2d}, [x0]\n    eor v2.16b, v2.16b, v4.16b\n    eor v3.16b, v3.16b, v5.16b\n")
VMEM(18, "    st1 {v0.s}[3], [x0]\n    st1 {v1.b}[9], [x0]\n    ld1 {v2.h}[5], [x0]\n" \
         "    ld1 {v3.d}[1], [x9], #8\n    st2 {v0.h, v1.h}[6], [x9], #4\n    ld3 {v2.b, v3.b, v4.b}[14], [x0]\n")
VMEM(19, "    str q0, [x0]\n    ld1r {v2.4s}, [x0]\n    ld2r {v3.8b, v4.8b}, [x9], #2\n" \
         "    eor v3.16b, v3.16b, v4.16b\n    ld1r {v4.2d}, [x9]\n    eor v2.16b, v2.16b, v4.16b\n")
VMEM(20, "    stp q0, q1, [x0]\n    ldpsw x11, x12, [x0]\n    fmov d2, x11\n    ldpsw x13, x14, [x9], #8\n" \
         "    ldpsw x15, x16, [x9, #-4]!\n    eor x12, x12, x13\n    eor x14, x14, x15\n" \
         "    eor x12, x12, x16\n    fmov d3, x12\n    mov v3.d[1], x14\n")
typedef void vmem_fn(unsigned char *, const uint64_t *, uint64_t *);
static vmem_fn *const vmems[] = { vmem_0, vmem_1, vmem_2, vmem_3, vmem_4, vmem_5, vmem_6, vmem_7, vmem_8,
                                  vmem_9, vmem_10, vmem_11, vmem_12, vmem_13, vmem_14, vmem_15, vmem_16,
                                  vmem_17, vmem_18, vmem_19, vmem_20 };
#define NVMEM (sizeof(vmems) / sizeof(vmems[0]))

static uint64_t vmem_step(unsigned k, unsigned char *p, uint64_t h) {
    uint64_t in[4] = { h | 0x8000000000000080ull, ~h, h * 0x9e3779b97f4a7c15ull, h ^ 0x00ff00ff00ff00ffull };
    uint64_t out[5] = { 0 };
    vmems[k](p, in, out);
    for (int i = 0; i < 5; i++)
        h = mix(h, out[i]);
    return h;
}

// Around a page boundary and in the middle of a page, at every alignment.
static uint64_t vsweep(void) {
    uint64_t h = 5;
    fresh_region(4, PROT_READ | PROT_WRITE);
    for (size_t i = 0; i < region_size; i++)
        region[i] = (unsigned char) (0x80 | (i * 131 + (i >> 8) * 17 + 7));
    for (int where = 0; where < 2; where++) {
        unsigned char *base = where == 0 ? region + 2 * page - 40 : region + 512;
        for (int off = 0; off < 80; off++)
            for (unsigned k = 0; k < NVMEM; k++)
                h = vmem_step(k, base + off, h);
    }
    for (size_t i = 0; i < region_size; i++)
        h = mix(h, region[i]);
    return h;
}

// Over pages that fault on first touch, some accesses with their first bytes in a page that is there.
static uint64_t vfault(long stride, long first) {
    uint64_t h = 11;
    long n = (long) ((region_size - 256) / (unsigned long) stride) - 2;
    for (unsigned k = 0; k < NVMEM; k++) {
        fresh_region(24, PROT_NONE);
        for (long i = 0; i < n; i++)
            h = vmem_step(k, region + 64 + first + i * stride, h);
        h = mix(h, fault_hash);
        h = mix(h, faults);
    }
    return h;
}
#endif

int main(void) {
    struct sigaction sa;
    page = (size_t) sysconf(_SC_PAGESIZE);
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = on_segv;
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);

    printf("MEM sweep %016llx\n", (unsigned long long) sweep());
    // Aligned strides, then ones that put every access at an odd address and some across two pages.
    printf("MEM fault 1000 %016llx\n", (unsigned long long) fault(1000, 0));
    printf("MEM fault 2048 %016llx\n", (unsigned long long) fault(2048, 16));
    printf("MEM cross 1365 %016llx\n", (unsigned long long) fault(1365, 3));
    printf("MEM cross 4095 %016llx\n", (unsigned long long) fault(4095, 4093));
    printf("MEM faults %lu\n", faults);
#if defined(__aarch64__)
    printf("MEM vreg sweep %016llx\n", (unsigned long long) vsweep());
    printf("MEM vreg fault 1000 %016llx\n", (unsigned long long) vfault(1000, 0));
    printf("MEM vreg cross 4095 %016llx\n", (unsigned long long) vfault(4095, 4060));
    printf("MEM vreg cross 1365 %016llx\n", (unsigned long long) vfault(1365, 3));
#endif
    return 0;
}
