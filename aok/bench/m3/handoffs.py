# Decode the first instruction at each hand-off pc in an RCG_DEBUG_PROF file.
import collections, os, subprocess, sys
MC = os.environ.get("LLVM_MC", "llvm-mc")
lines = open(sys.argv[1]).read().splitlines()
n = int(sys.argv[2]) if len(sys.argv) > 2 else 40
total = collections.Counter()
print(lines[0]); print(lines[1])
rows = []
for l in lines[2:]:
    p = l.split()
    if len(p) != 3: continue
    cnt, pc, hx = int(p[0]), p[1], p[2]
    bs = " ".join("0x" + hx[i:i+2] for i in range(0, len(hx), 2))
    out = subprocess.run([MC, "--disassemble", "-triple=x86_64", "-output-asm-variant=1"],
                         input=bs, capture_output=True, text=True).stdout
    ins = [x.strip() for x in out.splitlines() if x.strip() and not x.strip().startswith(".")]
    first = ins[0] if ins else "?"
    total[first.split()[0]] += cnt
    rows.append((cnt, pc, first))
for cnt, pc, first in rows[:n]:
    print(f"{cnt:>11} {pc} {first}")
print("by mnemonic:")
s = sum(total.values())
for m, c in total.most_common(15):
    print(f"{c:>11} {100*c/s:5.1f}% {m}")
