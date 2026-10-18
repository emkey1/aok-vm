/*
 * avx32_smoke -- AVX/VEX coverage for the *i386* guest (GH #525).
 *
 * i386 is JIT-only: unlike amd64 there is no interpreter to bail to, so VEX is
 * decoded at codegen time (emu/decode.h -> gen_vex32 in jit/gen.c) and executed
 * by vec_avx32 (emu/avx.c) through the vec-helper gadgets. That makes the
 * interesting cases different from the amd64 suite's:
 *
 *   - a 256-bit MEMORY operand, which needed new vec_helper_read256/write256
 *     gadget instantiations on both host backends
 *   - VZEROUPPER, which has NO ModRM byte; consuming one for it eats the next
 *     instruction's first byte and desynchronizes the whole decoder
 *   - a GPR destination (VPMOVMSKB), where the vec-helper's dst pointer aims
 *     at cpu->xmm[] and the runtime must instead write cpu->regs[]
 *   - lane-local (VPSHUFD) vs cross-lane (VPERMQ) behaviour at 256 bits
 *
 * Freestanding on purpose: it makes raw int $0x80 syscalls so it can run on an
 * i386 root with no toolchain and no libc. Build on the host with:
 *   clang -target i386-linux-musl -m32 -mavx2 -nostdlib -static -fuse-ld=lld \
 *       -o avx32_smoke tests/manual/x86/avx32_smoke.c
 * then copy it into an i386 guest and run it; it exits nonzero on failure.
 */
typedef unsigned int u32;

static long sys_write(int fd, const void *buf, u32 n) {
    long r;
    __asm__ volatile("int $0x80" : "=a"(r) : "a"(4), "b"(fd), "c"(buf), "d"(n) : "memory");
    return r;
}
static void sys_exit(int c) {
    __asm__ volatile("int $0x80" :: "a"(1), "b"(c));
    __builtin_unreachable();
}
static void put(const char *s) { u32 n = 0; while (s[n]) n++; sys_write(1, s, n); }
static void puthex(u32 v) {
    char b[11]; b[0] = '0'; b[1] = 'x'; b[10] = 0;
    for (int i = 9; i >= 2; i--) { int d = v & 0xf; b[i] = d < 10 ? '0' + d : 'a' + d - 10; v >>= 4; }
    put(b);
}

static int fails = 0;
static void chk(const char *n, const u32 *g, const u32 *w, int c) {
    int ok = 1;
    for (int i = 0; i < c; i++) if (g[i] != w[i]) ok = 0;
    put(ok ? "PASS " : "FAIL "); put(n);
    if (!ok) {
        put("\n  got: "); for (int i = 0; i < c; i++) { put(" "); puthex(g[i]); }
        put("\n  want:"); for (int i = 0; i < c; i++) { put(" "); puthex(w[i]); }
        fails++;
    }
    put("\n");
}

static const u32 A[8] __attribute__((aligned(32))) = {1, 2, 3, 4, 5, 6, 7, 8};
static const u32 B[8] __attribute__((aligned(32))) = {0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80};

void _start(void) {
    u32 r[8] __attribute__((aligned(32)));

    /* 256-bit load and store through memory: needs the read256/write256 gadgets. */
    __asm__ volatile("vmovdqu (%1),%%ymm1\n\tvmovdqu (%2),%%ymm2\n\t"
                     "vpxor %%ymm2,%%ymm1,%%ymm3\n\tvmovdqu %%ymm3,(%0)\n\tvzeroupper"
                     : : "r"(r), "r"(A), "r"(B) : "memory", "ymm1", "ymm2", "ymm3");
    { static const u32 w[8] = {0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88};
      chk("vpxor.256.mem", r, w, 8); }

    /* Memory operand directly on the ALU op, not just on a move. */
    __asm__ volatile("vmovdqu (%1),%%ymm1\n\tvpaddd (%2),%%ymm1,%%ymm3\n\t"
                     "vmovdqu %%ymm3,(%0)\n\tvzeroupper"
                     : : "r"(r), "r"(A), "r"(B) : "memory", "ymm1", "ymm3");
    { static const u32 w[8] = {0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88};
      chk("vpaddd.256.memsrc", r, w, 8); }

    /* Any VEX.128 write must zero bits 128-255. */
    __asm__ volatile("vmovdqu (%1),%%ymm3\n\tvpxor %%xmm3,%%xmm3,%%xmm3\n\t"
                     "vmovdqu %%ymm3,(%0)\n\tvzeroupper"
                     : : "r"(r), "r"(A) : "memory", "ymm3");
    { static const u32 w[8] = {0,0,0,0,0,0,0,0}; chk("vex128.zeroupper", r, w, 8); }

    /* VZEROUPPER clears the upper half and PRESERVES the low 128 bits. It also
       has no ModRM byte, so reaching this at all proves the decoder stayed in
       sync across it. */
    __asm__ volatile("vmovdqu (%1),%%ymm3\n\tvzeroupper\n\tvmovdqu %%ymm3,(%0)"
                     : : "r"(r), "r"(A) : "memory", "ymm3");
    { static const u32 w[8] = {1,2,3,4,0,0,0,0}; chk("vzeroupper.keeplow", r, w, 8); }

    /* Lane-local: the imm8 applies within each 128-bit half independently. */
    __asm__ volatile("vmovdqu (%1),%%ymm1\n\tvpshufd $0x1b,%%ymm1,%%ymm3\n\t"
                     "vmovdqu %%ymm3,(%0)\n\tvzeroupper"
                     : : "r"(r), "r"(A) : "memory", "ymm1", "ymm3");
    { static const u32 w[8] = {4,3,2,1,8,7,6,5}; chk("vpshufd.lane_local", r, w, 8); }

    /* Cross-lane by design -- reversing four qwords moves data between halves. */
    __asm__ volatile("vmovdqu (%1),%%ymm1\n\tvpermq $0x1b,%%ymm1,%%ymm3\n\t"
                     "vmovdqu %%ymm3,(%0)\n\tvzeroupper"
                     : : "r"(r), "r"(A) : "memory", "ymm1", "ymm3");
    { static const u32 w[8] = {7,8,5,6,3,4,1,2}; chk("vpermq.crosslane", r, w, 8); }

    /* Shift-by-imm8 uses the NDD form: the destination is vvvv, not ModRM.reg. */
    __asm__ volatile("vmovdqu (%1),%%ymm1\n\tvpslld $4,%%ymm1,%%ymm3\n\t"
                     "vmovdqu %%ymm3,(%0)\n\tvzeroupper"
                     : : "r"(r), "r"(A) : "memory", "ymm1", "ymm3");
    { static const u32 w[8] = {0x10,0x20,0x30,0x40,0x50,0x60,0x70,0x80};
      chk("vpslld.imm", r, w, 8); }

    /* GPR destination: the vec-helper's dst pointer aims into cpu->xmm[], so
       the runtime has to notice and write cpu->regs[] instead. */
    { u32 m = 0;
      static const u32 s[8] __attribute__((aligned(32))) =
          {0x80008000, 0, 0, 0, 0, 0, 0, 0x80000000};
      __asm__ volatile("vmovdqu (%1),%%ymm1\n\tvpmovmskb %%ymm1,%0\n\tvzeroupper"
                       : "=r"(m) : "r"(s) : "ymm1");
      u32 g[1] = {m};
      static const u32 w[1] = {(1u << 1) | (1u << 3) | (1u << 31)};
      chk("vpmovmskb.gpr", g, w, 1); }

    /* The regression runner keys off a "NAME: PASS" / "NAME: FAIL" verdict
       line and reports anything else as a failure, so emit one. No libc here,
       so the failure count is spelled out by hand rather than printf'd. */
    if (fails) {
        put("\navx32_smoke: FAIL failures=");
        puthex((u32) fails);
        put("\n");
    } else {
        put("\navx32_smoke: PASS\n");
    }
    sys_exit(fails ? 1 : 0);
}
