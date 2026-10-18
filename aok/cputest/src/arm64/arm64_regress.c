// arm64 guest regressions: one check per real bug class found while
// bringing up the AArch64 JIT (the counterpart of x86/amd64_regress.c).
//
//  ldp32-upper      `ldp w0, w1` stored only 4 bytes into the 8-byte guest
//                   register slots, leaving stale upper halves — ld computed
//                   wild pointers from them (fixed in memory.S).
//  eor-vec          the U=1 half of the three-same bitwise table
//                   (EOR/BSL/BIT/BIF) was unreachable due to a decode-mask
//                   bug; `eor v.8b` SIGILLed the linker.
//  block-cap        a straight-line block hitting the one-page compile cap
//                   resumed at a garbage address (gen_exit used the i386 ip
//                   field); needs >1024 sequential instructions.
//  tlb-48bit        the TLB fast path indexed with i386's unmasked math, so
//                   guest addresses differing only above bit 32 aliased (or
//                   walked off the TLB array entirely).
//  high-ptr-syscall the legacy syscall path silently truncated 64-bit
//                   pointer args (dmesg read into garbage; sockopt structs).
//  brk-growth       PIE placement pinned start_brk at the top of the mmap
//                   window with no headroom (sbrk is useless under musl by
//                   design, so this uses the raw brk syscall).
//  mrs              CNTVCT/CNTFRQ/NZCV/ID-register MRS emulation.
//  crc32            CRC32/CRC32C instructions (advertised via ISAR0).
//  scalar-misc      FRECPE + CMxx-zero, the cc1-startup SIGILL pair.
//  and-sp           `AND/ORR/EOR <Xd|SP>, ...` (Rd=31, opc != ANDS) was
//                   unconditionally treated as XZR-discard, like the GPR
//                   file's real "no SP" instructions -- but this family IS
//                   SP-capable for its non-flag-setting forms, same as
//                   ADD/SUB immediate. Silently no-opped SP updates, so
//                   the next SP-relative load read stale/wrong memory.
//                   Found via a real crash: LuaJIT's `and sp, x1, #mask`
//                   stack realignment on a call return.
//  int-arg-upper    a 32-bit syscall argument whose register's upper half
//                   holds junk (legal per AAPCS64; Linux truncates) was
//                   validated as a full 64-bit value and SIGSYS'd the caller
//                   -- `uv venv` died with "Bad system call" on fchmod.

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>
#include "test_common.h"

// ---- ldp32-upper -----------------------------------------------------------

static void check_ldp32_upper(void) {
    static const uint32_t pair[2] = { 0x11223344u, 0x55667788u };
    uint64_t a, b;
    __asm__ volatile(
        "movz %[a], #0xdead, lsl #48\n\t"   // poison the upper halves
        "movz %[b], #0xbeef, lsl #48\n\t"
        "ldp %w[a], %w[b], [%[ptr]]\n\t"
        : [a] "=&r"(a), [b] "=&r"(b)
        : [ptr] "r"(pair)
        : "memory");
    if (a != 0x11223344u || b != 0x55667788u)
        failf("ldp32-upper", a, b, 0, 0x11223344u, 0x55667788u, 0);
    else
        test_logf("ldp32-upper ok\n");
}

// ---- eor-vec (U=1 bitwise three-same reachability + semantics) -------------

static void check_eor_vec(void) {
    uint64_t n = 0xff00ff00ff00ff00ull, m = 0x0f0f0f0f0f0f0f0full, d;
    __asm__ volatile(
        "fmov d0, %[n]\n\t"
        "fmov d1, %[m]\n\t"
        "eor v0.8b, v0.8b, v1.8b\n\t"
        "fmov %[d], d0\n\t"
        : [d] "=r"(d)
        : [n] "r"(n), [m] "r"(m)
        : "v0", "v1");
    if (d != (n ^ m))
        failf("eor-vec", d, 0, 0, n ^ m, 0, 0);
    uint64_t sel = 0xffff0000ffff0000ull, x = 0x1111111111111111ull, y = 0x2222222222222222ull;
    __asm__ volatile(
        "fmov d0, %[sel]\n\t"
        "fmov d1, %[x]\n\t"
        "fmov d2, %[y]\n\t"
        "bsl v0.8b, v1.8b, v2.8b\n\t"
        "fmov %[d], d0\n\t"
        : [d] "=r"(d)
        : [sel] "r"(sel), [x] "r"(x), [y] "r"(y)
        : "v0", "v1", "v2");
    uint64_t want = (x & sel) | (y & ~sel);
    if (d != want)
        failf("bsl-vec", d, 0, 0, want, 0, 0);
    else
        test_logf("eor/bsl vec ok\n");
}

// ---- block-cap (long straight-line code) -----------------------------------

static void check_block_cap(void) {
    uint64_t acc = 1;
    // 128 * 24 = 3072 sequential adds: > 1024-instruction page cap, no
    // branches, so the JIT must split the block and continue correctly.
#define ADD24(v) \
    __asm__ volatile( \
        "add %[a], %[a], #1\n\t" "add %[a], %[a], #2\n\t" \
        "add %[a], %[a], #3\n\t" "add %[a], %[a], #4\n\t" \
        "add %[a], %[a], #5\n\t" "add %[a], %[a], #6\n\t" \
        "add %[a], %[a], #7\n\t" "add %[a], %[a], #8\n\t" \
        "add %[a], %[a], #9\n\t" "add %[a], %[a], #10\n\t" \
        "add %[a], %[a], #11\n\t" "add %[a], %[a], #12\n\t" \
        "add %[a], %[a], #13\n\t" "add %[a], %[a], #14\n\t" \
        "add %[a], %[a], #15\n\t" "add %[a], %[a], #16\n\t" \
        "add %[a], %[a], #17\n\t" "add %[a], %[a], #18\n\t" \
        "add %[a], %[a], #19\n\t" "add %[a], %[a], #20\n\t" \
        "add %[a], %[a], #21\n\t" "add %[a], %[a], #22\n\t" \
        "add %[a], %[a], #23\n\t" "add %[a], %[a], #24\n\t" \
        : [a] "+r"(v))
#define ADD24_8(v) ADD24(v); ADD24(v); ADD24(v); ADD24(v); \
                   ADD24(v); ADD24(v); ADD24(v); ADD24(v)
    ADD24_8(acc); ADD24_8(acc); ADD24_8(acc); ADD24_8(acc);
    ADD24_8(acc); ADD24_8(acc); ADD24_8(acc); ADD24_8(acc);
    ADD24_8(acc); ADD24_8(acc); ADD24_8(acc); ADD24_8(acc);
    ADD24_8(acc); ADD24_8(acc); ADD24_8(acc); ADD24_8(acc);
#undef ADD24_8
#undef ADD24
    // each ADD24 adds 300; 128 blocks of them
    uint64_t want = 1 + 300ull * 128;
    if (acc != want)
        failf("block-cap", acc, 0, 0, want, 0, 0);
    else
        test_logf("block-cap ok\n");
}

// ---- tlb-48bit --------------------------------------------------------------

static void check_tlb_48bit(void) {
    // Two fixed mappings whose addresses differ only ABOVE bit 32 (and
    // collide in the old 10-bit-index/32-bit-compare fast path). If the
    // TLB aliases them, the second write lands on the first page.
    void *lo = mmap((void *) 0x200000000000ull, 4096, PROT_READ | PROT_WRITE,
                    MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    void *hi = mmap((void *) 0x300000000000ull, 4096, PROT_READ | PROT_WRITE,
                    MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    if (lo == MAP_FAILED || hi == MAP_FAILED) {
        test_logf("tlb-48bit skipped (fixed mappings unavailable)\n");
        return;
    }
    volatile uint64_t *plo = lo, *phi = hi;
    for (int i = 0; i < 64; i++) { // several round trips through both pages
        *plo = 0x1010101010101010ull + (unsigned) i;
        *phi = 0x2020202020202020ull + (unsigned) i;
        if (*plo != 0x1010101010101010ull + (unsigned) i ||
                *phi != 0x2020202020202020ull + (unsigned) i) {
            failf("tlb-48bit", *plo, *phi, i,
                  0x1010101010101010ull + (unsigned) i,
                  0x2020202020202020ull + (unsigned) i, i);
            break;
        }
    }
    munmap(lo, 4096);
    munmap(hi, 4096);
    test_logf("tlb-48bit ok\n");
}

// ---- high-ptr-syscall --------------------------------------------------------

static void check_high_ptr_syscalls(void) {
    // Stack buffers sit near the top of the 47-bit space; any syscall that
    // silently truncates the pointer reads/writes garbage instead.
    char cwd[512];
    memset(cwd, 0, sizeof(cwd));
    if (getcwd(cwd, sizeof(cwd)) == NULL || cwd[0] != '/')
        failf("high-ptr getcwd", (uint64_t) (uintptr_t) cwd, cwd[0], 0, '/', 0, 0);
    struct timespec ts = {0, 0};
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0 || (ts.tv_sec == 0 && ts.tv_nsec == 0))
        failf("high-ptr clock_gettime", ts.tv_sec, ts.tv_nsec, 0, 1, 0, 0);
    struct rusage ru;
    memset(&ru, 0xff, sizeof(ru));
    if (getrusage(RUSAGE_SELF, &ru) != 0 || ru.ru_maxrss < 0)
        failf("high-ptr getrusage", ru.ru_maxrss, 0, 0, 0, 0, 0);
    else
        test_logf("high-ptr syscalls ok\n");
}

// ---- brk-growth --------------------------------------------------------------

static void check_brk_growth(void) {
    // musl's sbrk() fails by design; talk to the kernel directly.
    uintptr_t cur = (uintptr_t) syscall(SYS_brk, 0);
    if (cur == 0) {
        failf("brk query", cur, 0, 0, 1, 0, 0);
        return;
    }
    uintptr_t want = cur + 1024 * 1024;
    uintptr_t got = (uintptr_t) syscall(SYS_brk, want);
    if (got != want) {
        failf("brk grow 1MiB", got, cur, 0, want, 0, 0);
        return;
    }
    volatile char *p = (volatile char *) cur;
    p[0] = 0x5a;
    p[1024 * 1024 - 1] = 0xa5;
    if (p[0] != 0x5a || p[1024 * 1024 - 1] != (char) 0xa5)
        failf("brk write", p[0], (uint8_t) p[1024 * 1024 - 1], 0, 0x5a, 0xa5, 0);
    else
        test_logf("brk-growth ok\n");
    syscall(SYS_brk, cur); // shrink back
}

// ---- mrs ----------------------------------------------------------------------

static void check_mrs(void) {
    uint64_t frq, v1, v2;
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(frq));
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(v1));
    for (volatile int i = 0; i < 10000; i++)
        ;
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(v2));
    if (frq == 0 || v2 < v1)
        failf("mrs cntvct/cntfrq", frq, v1, v2, 1, 0, 0);
    uint64_t isar0;
    __asm__ volatile("mrs %0, id_aa64isar0_el1" : "=r"(isar0));
    // AES+PMULL / SHA1 / SHA2 / CRC32 fields, as gen.c advertises
    if (((isar0 >> 4) & 0xf) < 1 || ((isar0 >> 16) & 0xf) < 1)
        failf("mrs isar0", isar0, 0, 0, 0x11120, 0, 0);
    // NZCV round trip through MSR/MRS
    uint64_t nzcv_in = 0x60000000ull; // Z and C
    uint64_t nzcv_out;
    __asm__ volatile(
        "msr nzcv, %[in]\n\t"
        "mrs %[out], nzcv\n\t"
        : [out] "=r"(nzcv_out)
        : [in] "r"(nzcv_in)
        : "cc");
    if ((nzcv_out & 0xf0000000ull) != nzcv_in)
        failf("nzcv roundtrip", nzcv_out, 0, 0, nzcv_in, 0, 0);
    else
        test_logf("mrs ok (frq=%llu)\n", (unsigned long long) frq);
}

// ---- crc32 ---------------------------------------------------------------------

static void check_crc32(void) {
    // Known-answer: CRC-32 (the crc32* instruction polynomial, reflected
    // 0x04C11DB7) of "123456789" is 0xCBF43926; CRC-32C is 0xE3069283.
    static const char digits[] = "123456789";
    uint32_t crc = 0xffffffffu, crcc = 0xffffffffu;
    for (int i = 0; i < 9; i++) {
        __asm__ volatile(".arch_extension crc\n\tcrc32b %w0, %w0, %w2"
                         : "=r"(crc) : "0"(crc), "r"((uint32_t) digits[i]));
        __asm__ volatile(".arch_extension crc\n\tcrc32cb %w0, %w0, %w2"
                         : "=r"(crcc) : "0"(crcc), "r"((uint32_t) digits[i]));
    }
    crc ^= 0xffffffffu;
    crcc ^= 0xffffffffu;
    if (crc != 0xCBF43926u || crcc != 0xE3069283u)
        failf("crc32 known answer", crc, crcc, 0, 0xCBF43926u, 0xE3069283u, 0);
    else
        test_logf("crc32 ok\n");
}

// ---- scalar-misc (the cc1 startup SIGILL pair) ----------------------------------

static void check_scalar_misc(void) {
    double four = 4.0, est;
    __asm__ volatile(
        "fmov d0, %[in]\n\t"
        "frecpe d0, d0\n\t"
        "fmov %[est], d0\n\t"
        : [est] "=r"(est)
        : [in] "r"(four)
        : "v0");
    // FRECPE is an estimate: expect ~0.25 within its 8-bit precision
    if (!(est > 0.24 && est < 0.26))
        failf("frecpe", (uint64_t) (est * 1000), 0, 0, 250, 0, 0);
    uint64_t in = (uint64_t) -5, out;
    __asm__ volatile(
        "fmov d0, %[in]\n\t"
        "cmge d0, d0, #0\n\t"
        "fmov %[out], d0\n\t"
        : [out] "=r"(out)
        : [in] "r"(in)
        : "v0");
    if (out != 0) // -5 >= 0 is false -> all zeros
        failf("cmge-zero scalar", out, 0, 0, 0, 0, 0);
    else
        test_logf("scalar-misc ok\n");
}

// ---- and-sp (AND/ORR/EOR with Rd=SP, and ANDS's Rd=31=XZR-discard) --------

static void check_and_sp(void) {
    uint64_t x1_val = 0x1234567890abcd0full;
    uint64_t old_sp, new_sp;

    // AND SP, X1, #mask -- SP-capable, like ADD/SUB immediate.
    __asm__ volatile("mov %0, sp" : "=r"(old_sp));
    __asm__ volatile(
        "mov x1, %2\n\t"
        "and sp, x1, #0xfffffffffffffffc\n\t"
        "mov %0, sp\n\t"
        "mov sp, %1\n\t" // restore immediately -- don't run on a moved SP
        : "=&r"(new_sp)
        : "r"(old_sp), "r"(x1_val)
        : "x1");
    uint64_t expect_and = x1_val & 0xfffffffffffffffcull;
    if (new_sp != expect_and)
        failf("and-sp (AND SP,Xn,#imm)", new_sp, 0, 0, expect_and, 0, 0);
    else
        test_logf("and-sp AND ok\n");

    // ORR SP, XZR, #mask -- the MOV-to-SP-via-bitmask-immediate idiom.
    __asm__ volatile(
        "orr sp, xzr, #0xff00\n\t"
        "mov %0, sp\n\t"
        "mov sp, %1\n\t"
        : "=&r"(new_sp)
        : "r"(old_sp));
    if (new_sp != 0xff00ull)
        failf("and-sp (ORR SP,XZR,#imm)", new_sp, 0, 0, 0xff00ull, 0, 0);
    else
        test_logf("and-sp ORR ok\n");

    // ANDS with Rd=31 is the TST alias: sets flags, discards the result --
    // must NOT touch SP.
    uint64_t nzcv_before, nzcv_after;
    __asm__ volatile("mrs %0, nzcv" : "=r"(nzcv_before));
    __asm__ volatile(
        "mov x1, #0\n\t"
        "ands xzr, x1, #0xff\n\t" // TST: result 0 -> Z set
        : : : "x1", "cc");
    __asm__ volatile("mrs %0, nzcv" : "=r"(nzcv_after));
    __asm__ volatile("mov %0, sp" : "=r"(new_sp));
    if (new_sp != old_sp)
        failf("and-sp (ANDS/TST must not touch SP)", new_sp, 0, 0, old_sp, 0, 0);
    else if (!(nzcv_after & (1ull << 30))) // Z flag
        failf("and-sp (TST zero-flag)", nzcv_after, 0, 0, nzcv_before, 0, 0);
    else
        test_logf("and-sp ANDS/TST ok\n");
}

// ---- int-arg-upper ---------------------------------------------------------

static void check_int_arg_upper(void) {
    // AAPCS64 leaves the upper 32 bits of a register carrying a 32-bit
    // argument UNDEFINED, and Linux truncates each syscall arg to its declared
    // type -- so `fchmod(fd, mode)` with junk above bit 31 of x0 is a
    // perfectly legal call. The legacy 32-bit marshaller used to validate the
    // whole 64-bit register and SIGSYS the caller instead ("Bad system call"
    // from `uv venv`, where LLVM loads the fd as a whole 64-bit stack word and
    // an unrelated neighbouring field rides along in the upper half).
    static const char *path = "/tmp/ish-int-arg-upper";
    int fd = open(path, O_CREAT | O_RDWR | O_TRUNC, 0600);
    if (fd < 0) {
        failf("int-arg-upper open", (uint64_t) (int64_t) fd, 0, 0, 0, 0, 0);
        return;
    }
    // Junk above bit 31 of x0, exactly as the compiler-generated call does.
    register uint64_t x0 __asm__("x0") = (0x7fffull << 32) | (uint32_t) fd;
    register uint64_t x1 __asm__("x1") = 0444;
    register uint64_t x8 __asm__("x8") = SYS_fchmod;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x1), "r"(x8) : "memory");
    // Reaching this line at all is most of the test -- the bug killed the
    // process with SIGSYS before fchmod ran. The result must also show the fd
    // was truncated to w0 rather than taken as a wild 64-bit descriptor.
    if ((int64_t) x0 != 0)
        failf("int-arg-upper fchmod", x0, (uint64_t) (int64_t) fd, 0, 0, 0, 0);
    else
        test_logf("int-arg-upper ok\n");
    close(fd);
    unlink(path);
}

int main(int argc, char **argv) {
    test_init(argc, argv);
    check_ldp32_upper();
    check_int_arg_upper();
    check_eor_vec();
    check_block_cap();
    check_tlb_48bit();
    check_high_ptr_syscalls();
    check_brk_growth();
    check_mrs();
    check_crc32();
    check_scalar_misc();
    check_and_sp();
    return finish_suite("arm64_regress");
}
