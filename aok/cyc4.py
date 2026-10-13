#!/usr/bin/env python3
# cyc4.py LOG -- cyc4.sh's output as a table: per guest and workload, billions of host cycles under QEMU's
# own engine and under the AOK gadgets (the least of the repetitions), and how many times fewer.
import collections, sys
d = collections.defaultdict(lambda: collections.defaultdict(lambda: collections.defaultdict(list)))
order = []
for l in open(sys.argv[1], errors="replace"):
    f = l.split()
    if len(f) >= 6 and f[0] == "WL":
        guest, eng = f[1].rsplit("-", 1)
        d[guest][f[2]][eng].append(int(f[5]) / 1e9)
        if f[2] not in order: order.append(f[2])
names = {"riscv64": "RISC-V (rv64)", "aarch64": "ARM64 (cortex-a72)", "x86_64": "x86-64 (qemu64)", "x86": "x86 32-bit (qemu32)"}
for g in d:
    print("%s" % names.get(g, g))
    print("  %-10s %10s %10s %7s" % ("workload", "QEMU", "AOK", "x"))
    for w in order:
        v = d[g][w]
        if v["qemu"] and v["aok"]:
            q, a = min(v["qemu"]), min(v["aok"])
            print("  %-10s %8.2f G %8.2f G %6.2fx" % (w, q, a, q / a))
