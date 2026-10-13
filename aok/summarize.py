#!/usr/bin/env python3
"""Summarise race.sh output (cycwrap WL lines).

Every sample is first put in a machine state, because the same work costs a different number of cycles on
each core class and the host moves work between them when it throttles:

    super   >= 90% of the sample's instructions ran on the fastest cores
    mid     <= 10% did
    mixed   anything else; dropped

Logs from the first cycwrap, which did not report the share, are classified by effective clock speed instead
(>= 4.0 GHz is super, <= 2.2 GHz is mid). For each state, guest arch and workload this prints the median over
samples of host cycles, host instructions and host CPU seconds per engine, and each engine's ratio to AOK
(above 1 means it needs more than AOK does).
"""
import sys, collections, statistics

rows = collections.defaultdict(list)   # (state, arch, engine, workload) -> [sample]
dropped = 0
for path in sys.argv[1:]:
    for line in open(path, errors="replace"):
        f = line.split()
        if len(f) not in (8, 9) or f[0] != "WL":
            continue
        arch, eng, _round = f[1].split("-")
        x = dict(cpu=float(f[4]), cyc=int(f[5]), ins=int(f[6]))
        if not x["cpu"] or not x["cyc"]:
            continue
        ghz = x["cyc"] / 1e6 / x["cpu"]
        if len(f) == 9:
            share = float(f[8])
            state = "super" if share >= 90 else "mid" if share <= 10 else "mixed"
        else:
            state = "super" if ghz >= 4.0 else "mid" if ghz <= 2.2 else "mixed"
        if state == "mixed":
            dropped += 1
            continue
        rows[(state, arch, eng, f[2])].append(x)

# aok: AOK's CLI. aokq: AOK's gadgets inside QEMU (the tctiSH fork with --enable-aok-gadgets).
# tctish: the tctiSH fork's TCTI (QEMU 11.1). tcti: UTM's (QEMU 10). jit: QEMU's JIT.
known = ["aok", "aokq", "tctish", "tcti", "jit"]
engines = [e for e in known if any(k[2] == e for k in rows)]
others = [e for e in engines if e != "aok"]
order = ["coremark", "nbody", "python", "xz", "sha256", "awk"]
med = statistics.median
titles = {"super": "fastest cores (Super), ~4.3 GHz", "mid": "mid-tier cores (Performance), throttled"}
for state in ("super", "mid"):
    for a in sorted({k[1] for k in rows if k[0] == state}):
        print(f"\n===== {a} guest on the {titles[state]} =====")
        for key, unit, title in (("cyc", 1e9, "billions of host CPU cycles"),
                                 ("ins", 1e9, "billions of host instructions"),
                                 ("cpu", 1e3, "host CPU seconds")):
            print(f"-- {title}: median (samples, max/min)")
            print(f"{'workload':9} " + " ".join(f"{e:>20}" for e in engines) + " " + " ".join(f"{e + '/aok':>10}" for e in others))
            for w in order:
                m = {}; cells = []
                for e in engines:
                    s = [x[key] for x in rows.get((state, a, e, w), [])]
                    if not s:
                        cells.append(f"{'-':>20}"); continue
                    m[e] = med(s) / unit
                    cells.append(f"{m[e]:8.2f} (n{len(s)}, x{max(s) / min(s):4.2f})")
                ratios = " ".join(f"{m[e] / m['aok']:10.2f}" if e in m and "aok" in m else f"{'-':>10}" for e in others)
                print(f"{w:9} " + " ".join(cells) + " " + ratios)
        print("-- instructions per cycle, median")
        for w in order:
            cells = []
            for e in engines:
                s = rows.get((state, a, e, w), [])
                cells.append(f"{med([x['ins'] / x['cyc'] for x in s]):20.2f}" if s else f"{'-':>20}")
            print(f"{w:9} " + " ".join(cells))
print(f"\n{dropped} samples dropped because they straddled core classes")
