#!/usr/bin/env python3
# a64sym.py ADDR...: the aarch64 guest kernel symbols those addresses are in
import sys, bisect, os
m = []
for l in open(os.path.expanduser("~/aok-vm-bench/kernel/a64map/boot/System.map-6.18.55-0-virt")):
    a, t, n = l.split()[:3]
    if t in "tTwW": m.append((int(a, 16), n))
m.sort(); ks = [a for a, _ in m]
for s in sys.argv[1:]:
    v = int(s, 16); i = bisect.bisect_right(ks, v) - 1
    print("%s %s+%#x" % (s, m[i][1], v - m[i][0]))
