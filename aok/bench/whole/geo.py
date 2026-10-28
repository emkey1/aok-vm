#!/usr/bin/env python3
"""geo.py TIMING [A/B ...]: geometric means from a `bench.py compare` table (timing.txt), one metric per
workload (Blender's render time, xonsh's median key latency, as M0 and ../incdec took them): each column
against the first, then each pair given as LABEL/LABEL (the second over the first), with its range."""
import math
import re
import sys

PICK = {"blender_render": "render", "xonsh_keys": "key_median"}


def g(xs):
    return math.exp(sum(map(math.log, xs)) / len(xs))


rows, labels = {}, None
for line in open(sys.argv[1]):
    m = re.match(r"^(\w+) (\w+) \(\w+\)\s+(.*)$", line)
    if not m:
        if labels is None and line.startswith(" ") and line.strip():
            labels = line.split()
        continue
    w, metric = m.group(1), m.group(2)
    if PICK.get(w, metric) == metric:
        rows[w] = [float(x) for x in re.findall(r"(\d+(?:\.\d+)?) ±\d+%", m.group(3))]

print(f"{len(rows)} workloads; columns {', '.join(labels)}")
for i, lab in enumerate(labels[1:], 1):
    r = g([v[i] / v[0] for v in rows.values()])
    print(f"  {lab} against {labels[0]}: {r:.3f} ({1 / r:.2f}x faster)")
idx = {lab: i for i, lab in enumerate(labels)}
for pair in sys.argv[2:]:
    a, b = pair.split("/")
    per = {w: v[idx[b]] / v[idx[a]] for w, v in rows.items()}
    lo, hi = min(per, key=per.get), max(per, key=per.get)
    print(f"  {b} / {a}: {g(list(per.values())):.3f}, from {lo} {per[lo]:.3f} to {hi} {per[hi]:.3f}")
    print("     " + ", ".join(f"{w} {r:.3f}" for w, r in sorted(per.items())))
