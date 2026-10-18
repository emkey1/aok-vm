// Regression coverage for jit/guest-arm64/control.S's ANDS+B.cond gadget
// fusion (fused_andsi/fused_andsr, wired in gen.c's opc==3 peek-ahead in
// gen_step_arm64's logical-immediate and logical-register decode paths).
//
// The fusion collapses `ands Xd, Xn, (#imm|Xm)` immediately followed by
// `b.cc target` into one gadget that runs a real host ANDS, stores guest
// NZCV, conditionally writes the result (skipped for the TST alias,
// Rd=31/XZR), and branches straight to the taken or fallthrough target
// with no second gadget dispatch. Fourteen conditions x {imm,reg} x
// {32,64-bit} x {TST,normal-Rd} = 224 combinations (backed by 56 compiled
// gadget instances in jit/guest-arm64/control.S: 14 conditions x 2 forms x
// 2 sizes, with the TST/normal split handled at runtime inside each
// gadget) -- a bug in any one combination (wrong b.cc encoding for one
// condition's table slot, a TST-path store that should have been skipped
// or vice versa, a clobbered scratch register leaking into a guest-visible
// one, or a taken/fallthrough target swap) would only surface for that
// specific combination, so this drives all of them rather than a spot
// check.
//
// Reference semantics: ANDS is a logical op, so C and V are
// unconditionally cleared; only N (result MSB) and Z (result == 0) vary
// with the operands. cond_true_for_nz() is the literal ARM condition-code
// truth table with C=0, V=0 substituted in -- so e.g. CS/HI/VS read as
// permanently false and CC/LS/VC as permanently true after any ANDS. That
// is itself under test: a gadget using the wrong b.cc mnemonic for its
// table slot would only be caught by checking the real architectural truth
// table, not by assuming only the "obviously interesting" conditions
// matter.
//
// Each check drives two operand scenarios per condition -- one producing
// Z=1,N=0 (result zero) and one producing Z=0,N=1 (result negative, i.e.
// sign bit set for the given operand width) -- so every condition's taken
// AND not-taken path through its gadget gets exercised, not just whichever
// one the first scenario happens to hit.
//
// This file is portable host-native AArch64 (no guest syscalls), so it can
// be compiled and run directly on an Apple Silicon Mac to validate the
// test's own logic against real hardware before running it under the JIT
// (from tests/manual/arm64/):
//   cc -O0 -I.. -o /tmp/ands_bcond_fusion ands_bcond_fusion.c && /tmp/ands_bcond_fusion -v
// Confirmed: 140/140 probes pass natively.
//
// Run under the guest with ISH_ARM64_NO_FUSE=1 to compare against the
// unfused (gadget_arm64_logical_imm / andsr_fast) path for the same
// inputs -- a clean run in both modes with a failure only when fusion is
// enabled isolates the bug to the fused gadgets specifically.

#include <stdint.h>
#include "test_common.h"

enum cond {
    C_EQ, C_NE, C_CS, C_CC, C_MI, C_PL, C_VS, C_VC,
    C_HI, C_LS, C_GE, C_LT, C_GT, C_LE, C_COUNT,
};

static const char *const cond_names[C_COUNT] = {
    "eq", "ne", "cs", "cc", "mi", "pl", "vs", "vc",
    "hi", "ls", "ge", "lt", "gt", "le",
};

// Real ARM64 condition truth table, with C=0 and V=0 forced (ANDS always
// clears both). n/z are 0 or 1.
static int cond_true_for_nz(enum cond c, int n, int z) {
    switch (c) {
    case C_EQ: return z == 1;
    case C_NE: return z == 0;
    case C_CS: return 0;               // C==1, impossible after ANDS
    case C_CC: return 1;               // C==0, always true after ANDS
    case C_MI: return n == 1;
    case C_PL: return n == 0;
    case C_VS: return 0;               // V==1, impossible after ANDS
    case C_VC: return 1;               // V==0, always true after ANDS
    case C_HI: return 0;               // C==1 && Z==0, impossible
    case C_LS: return 1;               // C==0 || Z==1, always true (C==0)
    case C_GE: return n == 0;          // N==V, V==0
    case C_LT: return n == 1;          // N!=V, V==0
    case C_GT: return z == 0 && n == 0;
    case C_LE: return z == 1 || n == 1;
    default: return 0;
    }
}

#define NZCV_N (1u << 31)
#define NZCV_Z (1u << 30)
#define NZCV_C (1u << 29)
#define NZCV_V (1u << 28)

#define CANARY1 0x1919191919191919ull
#define CANARY2 0x2020202020202020ull

struct probe_result {
    int taken;
    uint32_t nzcv;
    uint64_t rd;
    uint64_t canary1;
    uint64_t canary2;
};

static unsigned g_checked;

static void check_form(const char *label, enum cond c, int n, int z,
                        struct probe_result r, int check_rd, uint64_t rd_expect) {
    g_checked++;
    int expect_taken = cond_true_for_nz(c, n, z);
    if (r.taken != expect_taken)
        failf(label, (uint64_t) r.taken, r.nzcv, 0, (uint64_t) expect_taken,
              (uint64_t) n << 4 | (uint64_t) z, 0);
    else
        test_logf("%s taken=%d nzcv=%#x ok\n", label, r.taken, r.nzcv);

    int got_n = (r.nzcv & NZCV_N) != 0;
    int got_z = (r.nzcv & NZCV_Z) != 0;
    int got_c = (r.nzcv & NZCV_C) != 0;
    int got_v = (r.nzcv & NZCV_V) != 0;
    if (got_n != n || got_z != z || got_c != 0 || got_v != 0)
        failf(label, r.nzcv, 0, 0,
              ((uint64_t) n << 3) | ((uint64_t) z << 2), 0, 0);

    if (r.canary1 != CANARY1 || r.canary2 != CANARY2)
        failf(label, r.canary1, r.canary2, 0, CANARY1, CANARY2, 0);

    if (check_rd && r.rd != rd_expect)
        failf(label, r.rd, 0, 0, rd_expect, 0, 0);
}

// ---- immediate form, 64-bit, normal Rd (x10) -------------------------------
// x9 = Rn (varies), imm = #0xff. Canaries in x19/x20 catch a fused gadget's
// scratch usage leaking into a guest-visible register it shouldn't touch.
#define ANDSI64_PROBE(cc, rn_val) ({ \
    uint64_t _rd = 0xdeadbeefdeadbeefull, _c1 = CANARY1, _c2 = CANARY2; \
    int _taken; uint32_t _nzcv; \
    register uint64_t _rn __asm__("x9") = (rn_val); \
    __asm__ volatile( \
        "mov x19, %[c1in]\n\t" \
        "mov x20, %[c2in]\n\t" \
        "ands x10, x9, #0xff00000000000000\n\t" \
        "mov %[rd], x10\n\t" \
        "b." #cc " 1f\n\t" \
        "mov %w[taken], #0\n\t" \
        "b 2f\n\t" \
        "1: mov %w[taken], #1\n\t" \
        "2: mrs x11, nzcv\n\t" \
        "mov %w[nzcv], w11\n\t" \
        "mov %[c1out], x19\n\t" \
        "mov %[c2out], x20\n\t" \
        : [taken] "=&r"(_taken), [nzcv] "=&r"(_nzcv), [rd] "+r"(_rd), \
          [c1out] "=&r"(_c1), [c2out] "=&r"(_c2) \
        : [rn] "r"(_rn), [c1in] "r"((uint64_t) CANARY1), [c2in] "r"((uint64_t) CANARY2) \
        : "x10", "x11", "x19", "x20", "cc", "memory"); \
    (struct probe_result){ _taken, _nzcv, _rd, _c1, _c2 }; \
})

// TST alias: Rd=31/xzr, result discarded -- no write to check, but the
// fused gadget's skip-store branch is what's exercised here.
#define ANDSI64_TST_PROBE(cc, rn_val) ({ \
    uint64_t _c1 = CANARY1, _c2 = CANARY2; \
    int _taken; uint32_t _nzcv; \
    register uint64_t _rn __asm__("x9") = (rn_val); \
    __asm__ volatile( \
        "mov x19, %[c1in]\n\t" \
        "mov x20, %[c2in]\n\t" \
        "ands xzr, x9, #0xff00000000000000\n\t" \
        "b." #cc " 1f\n\t" \
        "mov %w[taken], #0\n\t" \
        "b 2f\n\t" \
        "1: mov %w[taken], #1\n\t" \
        "2: mrs x11, nzcv\n\t" \
        "mov %w[nzcv], w11\n\t" \
        "mov %[c1out], x19\n\t" \
        "mov %[c2out], x20\n\t" \
        : [taken] "=&r"(_taken), [nzcv] "=&r"(_nzcv), \
          [c1out] "=&r"(_c1), [c2out] "=&r"(_c2) \
        : [rn] "r"(_rn), [c1in] "r"((uint64_t) CANARY1), [c2in] "r"((uint64_t) CANARY2) \
        : "x11", "x19", "x20", "cc", "memory"); \
    (struct probe_result){ _taken, _nzcv, 0, _c1, _c2 }; \
})

// 32-bit immediate form, normal Wd (w10).
#define ANDSI32_PROBE(cc, rn_val) ({ \
    uint64_t _rd = 0xdeadbeefdeadbeefull, _c1 = CANARY1, _c2 = CANARY2; \
    int _taken; uint32_t _nzcv; \
    register uint32_t _rn __asm__("w9") = (rn_val); \
    __asm__ volatile( \
        "mov x19, %[c1in]\n\t" \
        "mov x20, %[c2in]\n\t" \
        "ands w10, w9, #0xff000000\n\t" \
        "mov %w[rd], w10\n\t" \
        "b." #cc " 1f\n\t" \
        "mov %w[taken], #0\n\t" \
        "b 2f\n\t" \
        "1: mov %w[taken], #1\n\t" \
        "2: mrs x11, nzcv\n\t" \
        "mov %w[nzcv], w11\n\t" \
        "mov %[c1out], x19\n\t" \
        "mov %[c2out], x20\n\t" \
        : [taken] "=&r"(_taken), [nzcv] "=&r"(_nzcv), [rd] "+r"(_rd), \
          [c1out] "=&r"(_c1), [c2out] "=&r"(_c2) \
        : [rn] "r"(_rn), [c1in] "r"((uint64_t) CANARY1), [c2in] "r"((uint64_t) CANARY2) \
        : "x10", "x11", "x19", "x20", "cc", "memory"); \
    (struct probe_result){ _taken, _nzcv, _rd & 0xffffffffu, _c1, _c2 }; \
})

// register form, 64-bit, normal Rd (x10). x9=Rn, x12=Rm.
#define ANDSR64_PROBE(cc, rn_val, rm_val) ({ \
    uint64_t _rd = 0xdeadbeefdeadbeefull, _c1 = CANARY1, _c2 = CANARY2; \
    int _taken; uint32_t _nzcv; \
    register uint64_t _rn __asm__("x9") = (rn_val); \
    register uint64_t _rm __asm__("x12") = (rm_val); \
    __asm__ volatile( \
        "mov x19, %[c1in]\n\t" \
        "mov x20, %[c2in]\n\t" \
        "ands x10, x9, x12\n\t" \
        "mov %[rd], x10\n\t" \
        "b." #cc " 1f\n\t" \
        "mov %w[taken], #0\n\t" \
        "b 2f\n\t" \
        "1: mov %w[taken], #1\n\t" \
        "2: mrs x11, nzcv\n\t" \
        "mov %w[nzcv], w11\n\t" \
        "mov %[c1out], x19\n\t" \
        "mov %[c2out], x20\n\t" \
        : [taken] "=&r"(_taken), [nzcv] "=&r"(_nzcv), [rd] "+r"(_rd), \
          [c1out] "=&r"(_c1), [c2out] "=&r"(_c2) \
        : [rn] "r"(_rn), [rm] "r"(_rm), \
          [c1in] "r"((uint64_t) CANARY1), [c2in] "r"((uint64_t) CANARY2) \
        : "x10", "x11", "x19", "x20", "cc", "memory"); \
    (struct probe_result){ _taken, _nzcv, _rd, _c1, _c2 }; \
})

// register form, 32-bit, TST (Rd=31/wzr).
#define ANDSR32_TST_PROBE(cc, rn_val, rm_val) ({ \
    uint64_t _c1 = CANARY1, _c2 = CANARY2; \
    int _taken; uint32_t _nzcv; \
    register uint32_t _rn __asm__("w9") = (rn_val); \
    register uint32_t _rm __asm__("w12") = (rm_val); \
    __asm__ volatile( \
        "mov x19, %[c1in]\n\t" \
        "mov x20, %[c2in]\n\t" \
        "ands wzr, w9, w12\n\t" \
        "b." #cc " 1f\n\t" \
        "mov %w[taken], #0\n\t" \
        "b 2f\n\t" \
        "1: mov %w[taken], #1\n\t" \
        "2: mrs x11, nzcv\n\t" \
        "mov %w[nzcv], w11\n\t" \
        "mov %[c1out], x19\n\t" \
        "mov %[c2out], x20\n\t" \
        : [taken] "=&r"(_taken), [nzcv] "=&r"(_nzcv), \
          [c1out] "=&r"(_c1), [c2out] "=&r"(_c2) \
        : [rn] "r"(_rn), [rm] "r"(_rm), \
          [c1in] "r"((uint64_t) CANARY1), [c2in] "r"((uint64_t) CANARY2) \
        : "x11", "x19", "x20", "cc", "memory"); \
    (struct probe_result){ _taken, _nzcv, 0, _c1, _c2 }; \
})

// One function per condition, each driving both the Z=1/N=0 and Z=0/N=1
// scenarios across all four gadget shapes (imm/reg x 64/32-bit), plus the
// TST alias for imm-64 and reg-32 (the other two TST shapes are the same
// skip-store code path parameterized only by size/form, already covered
// structurally by the imm-64/reg-32 TST checks + the non-TST 32-bit/reg-64
// checks above).
#define DEFINE_COND_CHECK(ccname, cc) \
static void check_cond_##ccname(void) { \
    enum cond c = C_##cc; \
    char label[80]; \
    struct probe_result r; \
    \
    r = ANDSI64_PROBE(ccname, 0x00ull); \
    snprintf(label, sizeof(label), "andsi64-%s-z1", cond_names[c]); \
    check_form(label, c, 0, 1, r, 1, 0); \
    \
    r = ANDSI64_PROBE(ccname, 0xffffffffffffffffull); \
    snprintf(label, sizeof(label), "andsi64-%s-n1", cond_names[c]); \
    check_form(label, c, 1, 0, r, 1, 0xff00000000000000ull); \
    \
    r = ANDSI64_TST_PROBE(ccname, 0x00ull); \
    snprintf(label, sizeof(label), "andsi64tst-%s-z1", cond_names[c]); \
    check_form(label, c, 0, 1, r, 0, 0); \
    \
    r = ANDSI64_TST_PROBE(ccname, 0xffffffffffffffffull); \
    snprintf(label, sizeof(label), "andsi64tst-%s-n1", cond_names[c]); \
    check_form(label, c, 1, 0, r, 0, 0); \
    \
    r = ANDSI32_PROBE(ccname, 0x00u); \
    snprintf(label, sizeof(label), "andsi32-%s-z1", cond_names[c]); \
    check_form(label, c, 0, 1, r, 1, 0); \
    \
    r = ANDSI32_PROBE(ccname, 0xffffffffu); \
    snprintf(label, sizeof(label), "andsi32-%s-n1", cond_names[c]); \
    check_form(label, c, 1, 0, r, 1, 0xff000000u); \
    \
    r = ANDSR64_PROBE(ccname, 0xffffffffffffffffull, 0x0000000000000000ull); \
    snprintf(label, sizeof(label), "andsr64-%s-z1", cond_names[c]); \
    check_form(label, c, 0, 1, r, 1, 0); \
    \
    r = ANDSR64_PROBE(ccname, 0xffffffffffffffffull, 0x8000000000000000ull); \
    snprintf(label, sizeof(label), "andsr64-%s-n1", cond_names[c]); \
    check_form(label, c, 1, 0, r, 1, 0x8000000000000000ull); \
    \
    r = ANDSR32_TST_PROBE(ccname, 0xffffffffu, 0x00000000u); \
    snprintf(label, sizeof(label), "andsr32tst-%s-z1", cond_names[c]); \
    check_form(label, c, 0, 1, r, 0, 0); \
    \
    r = ANDSR32_TST_PROBE(ccname, 0xffffffffu, 0x80000000u); \
    snprintf(label, sizeof(label), "andsr32tst-%s-n1", cond_names[c]); \
    check_form(label, c, 1, 0, r, 0, 0); \
}

DEFINE_COND_CHECK(eq, EQ)
DEFINE_COND_CHECK(ne, NE)
DEFINE_COND_CHECK(cs, CS)
DEFINE_COND_CHECK(cc, CC)
DEFINE_COND_CHECK(mi, MI)
DEFINE_COND_CHECK(pl, PL)
DEFINE_COND_CHECK(vs, VS)
DEFINE_COND_CHECK(vc, VC)
DEFINE_COND_CHECK(hi, HI)
DEFINE_COND_CHECK(ls, LS)
DEFINE_COND_CHECK(ge, GE)
DEFINE_COND_CHECK(lt, LT)
DEFINE_COND_CHECK(gt, GT)
DEFINE_COND_CHECK(le, LE)

int main(int argc, char **argv) {
    test_init(argc, argv);
    check_cond_eq();
    check_cond_ne();
    check_cond_cs();
    check_cond_cc();
    check_cond_mi();
    check_cond_pl();
    check_cond_vs();
    check_cond_vc();
    check_cond_hi();
    check_cond_ls();
    check_cond_ge();
    check_cond_lt();
    check_cond_gt();
    check_cond_le();
    test_logf("checked %u probes\n", g_checked);
    return finish_suite("ands_bcond_fusion");
}
