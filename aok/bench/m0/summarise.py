#!/usr/bin/env python3
"""summarise.py COUNTS_DIR -- M0's instruction counts (mnemcount's WORKLOAD.txt files) as instruction
families: the AT&T size suffix folded (movq/movl -> mov), condition codes folded (jcc, cmovcc,
setcc), rep/lock kept, and each family put in a class: integer, vector (SSE/AVX), x87 or MMX."""
import collections
import os
import sys

STEMS = set("""mov add sub adc sbb cmp test and or xor inc dec neg not lea push pop shl shr sar sal rol ror
rcl rcr imul mul idiv div xchg cmpxchg xadd bt bts btr btc bsf bsr tzcnt lzcnt popcnt bswap call ret jmp
nop stos movs lods scas cmps shld shrd andn shlx shrx sarx rorx bzhi bextr pdep pext adcx adox mulx
cmpxchg8b cmpxchg16b crc32 movbe""".split())
CC = "o no b c nae ae nb nc e z ne nz be na a nbe s ns p pe np po l nge ge nl le ng g nle".split()
X87 = ("f",)


def family(m):
    pre = ""
    for p in ("rep ", "repz ", "repe ", "repnz ", "repne ", "lock ", "data16 ", "addr32 "):
        if m.startswith(p):
            pre, m = p.strip() + " ", m[len(p):]
            break
    tag = ""
    for t in (".vec", ".mmx", ".x87"):
        if m.endswith(t):
            tag, m = t, m[: -len(t)]
    if tag == ".vec":
        return pre + m, "vector"
    if tag == ".mmx":
        return pre + m, "mmx"
    if tag == ".x87" or (m.startswith(X87) and m not in ("fs",)):
        return pre + m, "x87"
    if m == "movabsq":
        m = "mov"
    elif m[:4] in ("movz", "movs") and len(m) == 6 and m[4] in "bwl" and m[5] in "wlq":
        m = "movsxd" if m == "movslq" else ("movzx" if m[3] == "z" else "movsx")
    elif m.startswith("cmov") and m[4:].rstrip("wlq") in CC:
        m = "cmovcc"
    elif m.startswith("set") and m[3:] in CC:
        m = "setcc"
    elif m.startswith("j") and m[1:] in CC:
        m = "jcc"
    elif m in ("cltq", "cqto", "cltd", "cwtl", "cbtw", "cwtd"):
        m = "cbw/cwd family"
    elif m[:-1] in STEMS and m[-1] in "bwlq":
        m = m[:-1]
    return pre + m, "integer"


def load(path):
    total, fam, cls = 0, collections.Counter(), collections.Counter()
    for line in open(path):
        n, name = line.split(" ", 1)
        name = name.strip()
        if name == "total":
            total = int(n)
            continue
        f, c = family(name)
        fam[(f, c)] += int(n)
        cls[c] += int(n)
    return total, fam, cls


def main():
    d = sys.argv[1]
    files = sorted(f for f in os.listdir(d) if f.endswith(".txt") and not f.startswith("sanity"))
    allfam, allcls, grand = collections.Counter(), collections.Counter(), 0
    per = []
    for f in files:
        total, fam, cls = load(os.path.join(d, f))
        grand += total
        allfam.update(fam)
        allcls.update(cls)
        top = [k[0] for k, _ in fam.most_common() if k[1] == "integer"][:6]
        per.append((f[:-4], total, cls, top))
    print("Per workload (whole run, boot included): instructions, class shares, top integer families")
    for w, total, cls, top in per:
        sh = " ".join("%s %.0f%%" % (c, 100 * cls[c] / total) for c in ("integer", "vector", "x87", "mmx") if cls[c])
        print("  %-15s %7.2f G  %-34s %s" % (w, total / 1e9, sh, ", ".join(top)))
    print()
    print("All workloads: %.1f G instructions; %s" % (grand / 1e9, ", ".join(
        "%s %.1f%%" % (c, 100 * allcls[c] / grand) for c in ("integer", "vector", "x87", "mmx"))))
    print()
    print("Integer families, most executed (share of all instructions, cumulative):")
    cum = 0
    for (f, c), n in allfam.most_common():
        if c != "integer":
            continue
        cum += n
        print("  %-16s %6.2f%%  %6.2f%%" % (f, 100 * n / grand, 100 * cum / grand))
        if cum / grand > 0.95 * allcls["integer"] / grand:
            break
    print()
    print("Vector families, most executed:")
    for (f, c), n in [x for x in allfam.most_common() if x[0][1] == "vector"][:15]:
        print("  %-16s %6.2f%%" % (f, 100 * n / grand))


main()
