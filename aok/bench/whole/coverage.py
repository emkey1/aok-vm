#!/usr/bin/env python3
"""coverage.py COUNTS_DIR: for each workload, the share of its executed instructions (M0's counts) in
families structure A has gadgets for, and the largest families it has none for. By family, so an
approximation: a covered family's forms A leaves to TCG (a shift by CL, a 32-bit push, a ROL of a
byte, a locked op) count as covered, and jmp counts as covered (a direct one is TCG's goto_tb)."""
import collections
import os
import sys

# summarise.py's family folding, without running its main().
_src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../m0/summarise.py")).read()
_ns = {}
exec(_src.split("\ndef main")[0], _ns)
load = _ns["load"]

COVERED = set("""mov add sub cmp and or xor test movzx movsx movsxd lea push pop not neg shl shr sar sal
rol ror call ret jmp jcc setcc cmovcc""".split())


def main():
    d = sys.argv[1]
    rows = []
    for f in sorted(os.listdir(d)):
        if not f.endswith(".txt") or f.startswith("sanity"):
            continue
        total, fam, cls = load(os.path.join(d, f))
        cov = sum(n for (name, c), n in fam.items() if c == "integer" and name in COVERED)
        incdec = sum(n for (name, c), n in fam.items() if name in ("inc", "dec"))
        missing = collections.Counter({name: n for (name, c), n in fam.items()
                                       if c == "integer" and name not in COVERED})
        rows.append((f[:-4], total, cov, incdec, cls["vector"] + cls["x87"] + cls["mmx"], missing))
    print("Per workload: covered by A's families, inc/dec (#7), vector/x87, and the largest uncovered integer families")
    for w, total, cov, incdec, vec, missing in rows:
        top = ", ".join(f"{name} {100 * n / total:.1f}%" for name, n in missing.most_common(4))
        print(f"  {w:15} covered {100 * cov / total:5.1f}%  inc/dec {100 * incdec / total:4.1f}%  "
              f"vector/x87 {100 * vec / total:4.1f}%   {top}")


main()
