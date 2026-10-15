// The reproducer of tctiSH/tctiSH#4: TCTI's cmp_vec swaps LT/LE and LTU/LEU. Run in the arm64 race guest
// in place of /bench/simdtest (a cpio of bench/simdtest appended to initramfs-aarch64.cpio, bench=simdtest).
//
// simdrepro: CMLT #0, CMLE #0 and SSHL on every lane size, against a C reference.
// Builds for Linux (static, for a guest) and for macOS, so the same source runs on the hardware.
//   cc -O2 -o simdrepro simdrepro.c            (macOS, arm64)
//   gcc -O2 -static -o simdrepro simdrepro.c   (aarch64 Linux)
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct { uint8_t b[16]; } V;

#define OP2(name, insn)                                                              \
    static V name(V n) {                                                             \
        V d;                                                                         \
        __asm__ volatile("ld1 {v1.16b}, [%1]\n\t" insn "\n\tst1 {v0.16b}, [%0]"       \
                         : : "r"(d.b), "r"(n.b) : "v0", "v1", "memory");             \
        return d;                                                                    \
    }
#define OP3(name, insn)                                                              \
    static V name(V n, V m) {                                                        \
        V d;                                                                         \
        __asm__ volatile("ld1 {v1.16b}, [%1]\n\tld1 {v3.16b}, [%2]\n\t" insn         \
                         "\n\tst1 {v0.16b}, [%0]"                                    \
                         : : "r"(d.b), "r"(n.b), "r"(m.b) : "v0", "v1", "v3", "memory"); \
        return d;                                                                    \
    }

OP2(cmlt_8b,  "movi v0.16b, #0x55\n\tcmlt v0.8b, v1.8b, #0")
OP2(cmlt_16b, "cmlt v0.16b, v1.16b, #0")
OP2(cmlt_4h,  "movi v0.16b, #0x55\n\tcmlt v0.4h, v1.4h, #0")
OP2(cmlt_8h,  "cmlt v0.8h, v1.8h, #0")
OP2(cmlt_2s,  "movi v0.16b, #0x55\n\tcmlt v0.2s, v1.2s, #0")
OP2(cmlt_4s,  "cmlt v0.4s, v1.4s, #0")
OP2(cmlt_2d,  "cmlt v0.2d, v1.2d, #0")
OP2(cmle_8b,  "movi v0.16b, #0x55\n\tcmle v0.8b, v1.8b, #0")
OP2(cmle_16b, "cmle v0.16b, v1.16b, #0")
OP2(cmle_4h,  "movi v0.16b, #0x55\n\tcmle v0.4h, v1.4h, #0")
OP2(cmle_8h,  "cmle v0.8h, v1.8h, #0")
OP2(cmle_2s,  "movi v0.16b, #0x55\n\tcmle v0.2s, v1.2s, #0")
OP2(cmle_4s,  "cmle v0.4s, v1.4s, #0")
OP2(cmle_2d,  "cmle v0.2d, v1.2d, #0")
OP3(sshl_8b,  "movi v0.16b, #0x55\n\tsshl v0.8b, v1.8b, v3.8b")
OP3(sshl_16b, "sshl v0.16b, v1.16b, v3.16b")
OP3(sshl_4h,  "movi v0.16b, #0x55\n\tsshl v0.4h, v1.4h, v3.4h")
OP3(sshl_8h,  "sshl v0.8h, v1.8h, v3.8h")
OP3(sshl_2s,  "movi v0.16b, #0x55\n\tsshl v0.2s, v1.2s, v3.2s")
OP3(sshl_4s,  "sshl v0.4s, v1.4s, v3.4s")
OP3(sshl_2d,  "sshl v0.2d, v1.2d, v3.2d")

static const uint64_t specials[] = {
    0x0000000000000000, 0x8000000000000000, 0x3ff0000000000000, 0xbff0000000000000,     // 0, -0, 1, -1
    0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000000000, 0x7ff4000000000001,     // inf, -inf, qnan, snan
    0x0000000000000001, 0x800fffffffffffff, 0x0010000000000000, 0x7fefffffffffffff,     // denormals, min, max
    0x3fe0000000000000, 0x4008000000000000, 0x43e0000000000000, 0xc3e0000000000001,     // .5, 3, 2^63, -(2^63)-
    0x3ff8000000000000, 0x400921fb54442d18, 0x41dfffffffc00000, 0xc1e0000000000000,     // 1.5, pi, 2^31-1, -2^31
    0x3f8000007fc00000, 0x7f800000ff800000, 0x0000000100800000, 0x7f7fffff80000001,     // singles in pairs
    0x3fc000003f000000, 0x4f0000004f800000, 0xcf000000bf800000, 0x7fa0000100000000,
    0x00007e007c00fc00, 0x3c00bc0000010400, 0x7fff800000ff0080, 0x0123456789abcdef,     // halves, integers
    0xffffffffffffffff, 0x7fffffffffffffff, 0x8000000000000001, 0x00000000ffffffff,
    0x7fff7fff80008000, 0x00ff00ff7f7f8080, 0x0102040810204080, 0xfedcba9876543210,
};
#define NSPECIAL (sizeof(specials) / sizeof(specials[0]))
static uint64_t rng_state;
static uint64_t rng(void) { rng_state ^= rng_state << 13; rng_state ^= rng_state >> 7; rng_state ^= rng_state << 17; return rng_state; }

// The register contents simdtest (which first found this) uses: its four input sets, v1 and v3.
static void simdtest_inputs(int s, V *n, V *m) {
    uint64_t v[32][2];
    rng_state = 0x9e3779b97f4a7c15ull;
    for (int set = 0; set <= s; set++) {
        for (int r = 0; r < 32; r++)
            for (int h = 0; h < 2; h++)
                v[r][h] = set == 0 || set == 3 ? specials[(r * 7 + h * 3 + 1) % NSPECIAL]
                        : set == 1 ? rng()
                        : (rng() & 0x003f00ff00070003ull) ^ (r & 1 ? 0xffff000000000000ull : 0);
        if (set == 1)
            for (int k = 0; k < 4; k++) rng();      // simdtest's x registers
    }
    memcpy(n->b, v[1], 16);
    memcpy(m->b, v[3], 16);
}

// Lane access, little-endian, esize in bytes.
static int64_t get(const V *v, int i, int es) {
    int64_t x = 0;
    memcpy(&x, v->b + i * es, es);
    int sh = 64 - 8 * es;
    return sh ? (x << sh) >> sh : x;    // sign-extended
}
static void put(V *v, int i, int es, int64_t x) { memcpy(v->b + i * es, &x, es); }

// The architecture's answer. A 64-bit form (lanes == 8 / es) clears bits 127:64.
static V ref(int op, V n, V m, int es, int bytes) {
    V d;
    memset(&d, 0, sizeof d);
    int bits = 8 * es;
    for (int i = 0; i < bytes / es; i++) {
        int64_t x = get(&n, i, es), r;
        if (op == 0) {
            r = x < 0 ? -1 : 0;                             // CMLT #0
        } else if (op == 1) {
            r = x <= 0 ? -1 : 0;                            // CMLE #0
        } else {
            int s = (int8_t) m.b[i * es];                   // SSHL: the low byte of each lane, signed
            if (s >= 0) r = s >= bits ? 0 : (int64_t) ((uint64_t) x << s);
            else r = -s >= bits ? (x < 0 ? -1 : 0) : x >> -s;
        }
        put(&d, i, es, r);
    }
    return d;
}

static void hex(const char *tag, V v) {
    printf(" %s=", tag);
    for (int i = 15; i >= 0; i--) printf("%02x", v.b[i]);
}

static int bad;
static void check(const char *name, int op, V got, V n, V m, int es, int bytes) {
    V want = ref(op, n, m, es, bytes);
    int ok = !memcmp(&got, &want, sizeof got);
    if (!ok) bad++;
    printf("%-30s %s", name, ok ? "ok " : "BAD");
    if (!ok) { hex("n", n); if (op == 2) hex("m", m); hex("got", got); hex("want", want); }
    printf("\n");
}

int main(void) {
    // Lanes of every sign and size: zero, small, the extremes, and -1.
    static const int64_t vals[] = { 0, 1, -1, 2, -2, 0x3f, -0x40, 0x7f, -0x80, 0x7fff, -0x8000,
                                    0x7fffffff, -0x7fffffff - 1, 0x12345678, -0x12345678, 5 };
    // Shift amounts, read from each lane's low byte: left, right, and past the lane.
    static const int8_t shifts[] = { 0, 1, -1, 3, -3, 7, -7, 8, -8, 15, -15, 16, -16, 31, -33, -64 };
    for (int es = 1; es <= 8; es *= 2) {
        V n, m;
        // Rounds 4-7: SSHL's shift lanes with bits above the low byte set too, which the instruction ignores.
        for (int round = 0; round < 8; round++) {
            memset(&n, 0, sizeof n); memset(&m, 0, sizeof m);
            for (int i = 0; i < 16 / es; i++) {
                put(&n, i, es, vals[(i + round * 3) % 16]);
                uint64_t hi = round < 4 ? 0 : 0x5a3c00ff12345600ull * (uint64_t) (i + round);
                put(&m, i, es, (int64_t) ((hi & ~0xffull) | (uint8_t) shifts[(i * 5 + round) % 16]));
            }
            char name[64];
#define T2(op, f, bytes, s) snprintf(name, sizeof name, "%s r%d", s, round); check(name, op, f(n), n, m, es, bytes)
#define T3(f, bytes, s) snprintf(name, sizeof name, "%s r%d", s, round); check(name, 2, f(n, m), n, m, es, bytes)
            switch (es) {
            case 1: T2(0, cmlt_8b, 8, "cmlt v0.8b, v1.8b, #0"); T2(0, cmlt_16b, 16, "cmlt v0.16b, v1.16b, #0");
                    T2(1, cmle_8b, 8, "cmle v0.8b, v1.8b, #0"); T2(1, cmle_16b, 16, "cmle v0.16b, v1.16b, #0");
                    T3(sshl_8b, 8, "sshl v0.8b, v1.8b, v3.8b"); T3(sshl_16b, 16, "sshl v0.16b, v1.16b, v3.16b"); break;
            case 2: T2(0, cmlt_4h, 8, "cmlt v0.4h, v1.4h, #0"); T2(0, cmlt_8h, 16, "cmlt v0.8h, v1.8h, #0");
                    T2(1, cmle_4h, 8, "cmle v0.4h, v1.4h, #0"); T2(1, cmle_8h, 16, "cmle v0.8h, v1.8h, #0");
                    T3(sshl_4h, 8, "sshl v0.4h, v1.4h, v3.4h"); T3(sshl_8h, 16, "sshl v0.8h, v1.8h, v3.8h"); break;
            case 4: T2(0, cmlt_2s, 8, "cmlt v0.2s, v1.2s, #0"); T2(0, cmlt_4s, 16, "cmlt v0.4s, v1.4s, #0");
                    T2(1, cmle_2s, 8, "cmle v0.2s, v1.2s, #0"); T2(1, cmle_4s, 16, "cmle v0.4s, v1.4s, #0");
                    T3(sshl_2s, 8, "sshl v0.2s, v1.2s, v3.2s"); T3(sshl_4s, 16, "sshl v0.4s, v1.4s, v3.4s"); break;
            case 8: T2(0, cmlt_2d, 16, "cmlt v0.2d, v1.2d, #0"); T2(1, cmle_2d, 16, "cmle v0.2d, v1.2d, #0");
                    T3(sshl_2d, 16, "sshl v0.2d, v1.2d, v3.2d"); break;
            }
        }
    }
    // simdtest's own inputs: its four sets, as rounds 8-11.
    for (int set = 0; set < 4; set++) {
        V n, m;
        char name[64];
        int round = 8 + set;
        simdtest_inputs(set, &n, &m);
        int es;
        es = 1; T3(sshl_8b, 8, "sshl v0.8b, v1.8b, v3.8b"); T3(sshl_16b, 16, "sshl v0.16b, v1.16b, v3.16b");
        es = 2; T3(sshl_4h, 8, "sshl v0.4h, v1.4h, v3.4h"); T3(sshl_8h, 16, "sshl v0.8h, v1.8h, v3.8h");
        es = 4; T3(sshl_2s, 8, "sshl v0.2s, v1.2s, v3.2s"); T3(sshl_4s, 16, "sshl v0.4s, v1.4s, v3.4s");
        es = 8; T3(sshl_2d, 16, "sshl v0.2d, v1.2d, v3.2d");
    }
    // Every shift count at every lane size, on a negative and a positive lane: only the failures are printed,
    // as "sweep sshl LANEBITS SHIFT ...".
    for (int es = 1; es <= 8; es *= 2) {
        int sweep_bad = 0;
        for (int sh = -128; sh < 128; sh++) {
            V n, m;
            memset(&m, 0, sizeof m);
            for (int i = 0; i < 16 / es; i++) {
                put(&n, i, es, i & 1 ? 0x5a : -0x5b);
                m.b[i * es] = (uint8_t) sh;
            }
            V got = es == 1 ? sshl_16b(n, m) : es == 2 ? sshl_8h(n, m) : es == 4 ? sshl_4s(n, m) : sshl_2d(n, m);
            V want = ref(2, n, m, es, 16);
            if (memcmp(&got, &want, sizeof got)) {
                sweep_bad++;
                printf("sweep sshl %d-bit lanes, shift %d: BAD", 8 * es, sh);
                hex("n", n); hex("got", got); hex("want", want); printf("\n");
            }
        }
        bad += sweep_bad;
        printf("sweep sshl %d-bit lanes: %d of 256 shift counts bad\n", 8 * es, sweep_bad);
    }
    printf("simdrepro: %d bad\n", bad);
    return bad != 0;
}
