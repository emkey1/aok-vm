#!/usr/bin/env python3
# classify.py LOG [N [32]]: the hand-off profile of a QEMU_AOK_STATS=2 run of an x86 guest, by opcode
# (the N most frequent; "32" for a 32-bit guest, where 40-4f are inc and dec, not REX)
import sys, collections
GROUPS = {0x80, 0x81, 0x83, 0xc0, 0xc1, 0xd0, 0xd1, 0xd2, 0xd3, 0xf6, 0xf7, 0xfe, 0xff, 0xc6, 0xc7, 0x8f}
GROUPS0F = {0x00, 0x01, 0xba, 0xc7, 0xae, 0x18}
def cls(v):
    b = v.to_bytes(4, "little"); i = 0; pfx = []
    while i < 4 and b[i] in (0x66, 0x67, 0xf0, 0xf2, 0xf3, 0x2e, 0x3e, 0x26, 0x36, 0x64, 0x65):
        pfx.append({0x66: "66", 0x67: "67", 0xf0: "lock", 0xf2: "f2", 0xf3: "f3", 0x64: "fs", 0x65: "gs"}.get(b[i], "seg")); i += 1
    if i < 4 and 0x40 <= b[i] <= 0x4f and not M32:
        if b[i] & 8: pfx.append("W")
        i += 1
    if i >= 4: return " ".join(pfx) + " ?"
    op = "%02x" % b[i]; i += 1; grp = int(op, 16) in GROUPS; mem = ""
    if op == "0f" and i < 4:
        op = "0f %02x" % b[i]; grp = b[i] in GROUPS0F; i += 1
    if i < 4:
        if grp: op += " /%d" % ((b[i] >> 3) & 7)
        mem = " m" if (b[i] >> 6) != 3 else " r"
    return (" ".join(p for p in pfx if p not in ("seg",)) + " " + op).strip() + (mem if grp or op.startswith("0f") or int(op[:2], 16) < 0x40 or 0x84 <= int(op[:2], 16) <= 0x8b else "")
M32 = len(sys.argv) > 3 and sys.argv[3] == "32"
tot = collections.Counter(); n = 0
for l in open(sys.argv[1], errors="replace"):
    f = l.split()
    if len(f) == 5 and f[1] == "tcg-entry":
        c = int(f[2]); tot[cls(int(f[4], 16))] += c; n += c
for k, v in tot.most_common(int(sys.argv[2]) if len(sys.argv) > 2 else 60): print("%10d %5.1f%%  %s" % (v, 100.0 * v / n, k))
print("%10d listed" % n)
