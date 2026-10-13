#!/usr/bin/env python3
# classify.py LOG: the hand-off profile of a QEMU_AOK_STATS=2 run, by instruction class
import sys, collections
def cls(i):
    top = (i >> 25) & 15
    if (i & 0xfffff01f) == 0xd503201f:
        crm, op2 = (i >> 8) & 15, (i >> 5) & 7
        return "hint crm=%d op2=%d" % (crm, op2)
    if (i & 0xfff00000) == 0xd5300000: return "mrs S%d_%d_C%d_C%d_%d" % (2 + ((i >> 19) & 1), (i >> 16) & 7, (i >> 12) & 15, (i >> 8) & 15, (i >> 5) & 7)
    if (i & 0xfff00000) == 0xd5100000: return "msr S%d_%d_C%d_C%d_%d" % (2 + ((i >> 19) & 1), (i >> 16) & 7, (i >> 12) & 15, (i >> 8) & 15, (i >> 5) & 7)
    if (i & 0xfff8f01f) == 0xd500401f: return "msr pstate op1=%d op2=%d" % ((i >> 16) & 7, (i >> 5) & 7)
    if (i & 0xfff80000) == 0xd5080000: return "sys %d C%d C%d %d" % ((i >> 16) & 7, (i >> 12) & 15, (i >> 8) & 15, (i >> 5) & 7)
    if (i & 0xfffff0ff) == 0xd50330df: return "isb"
    if (i & 0xff000000) == 0xd4000000: return "exception gen (svc/hvc/brk)"
    if i == 0xd69f03e0: return "eret"
    if (i & 0xff000000) == 0xd5000000: return "system other"
    if (i & 0x3f000000) == 0x08000000:
        o2, l, o1, o0 = (i >> 23) & 1, (i >> 22) & 1, (i >> 21) & 1, (i >> 15) & 1
        if o2 == 0: return "exclusive %s%s" % ("ld" if l else "st", "xp" if o1 else "xr")
        if o1 == 0: return "ldar/stlr" if o0 else "lload/stllr"
        return "cas"
    if top in (4, 6, 12, 14):
        if i & (1 << 26):
            if (i & 0x3a000000) == 0x28000000: return "fp/simd ldp/stp"
            if (i & 0x3b000000) == 0x18000000: return "fp/simd literal"
            if (i & 0x3a000000) == 0x38000000: return "fp/simd ldr/str"
            return "simd ld1/st1 struct"
        if (i & 0x3b200c00) == 0x38000800: return "ldtr/sttr (unpriv)"
        if (i & 0x3b200c00) == 0x38200000: return "atomic (lse)"
        if (i & 0x3a000000) == 0x28000000: return "ldpsw/stgp"
        return "ldst other %08x" % (i & 0xff200c00)
    if top in (7, 15):
        if (i & 0x5f000000) == 0x1e000000 or (i & 0x5f000000) == 0x1f000000: return "scalar fp"
        return "advsimd"
    if top in (5, 13): return "dp reg %08x" % (i & 0x7fe0fc00)
    if top in (8, 9): return "dp imm %08x" % (i & 0x7f800000)
    if top in (10, 11): return "branch/sys %08x" % (i & 0xff000000)
    return "other top=%d" % top
tot = collections.Counter(); n = 0
for l in open(sys.argv[1], errors="replace"):
    f = l.split()
    if len(f) == 5 and f[1] == "tcg-entry":
        c = int(f[2]); tot[cls(int(f[4], 16))] += c; n += c
for k, v in tot.most_common(45): print("%10d %5.1f%%  %s" % (v, 100.0 * v / n, k))
print("%10d listed" % n)
