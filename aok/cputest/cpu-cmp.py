#!/usr/bin/env python3
"""cpu-cmp.py ENGINE.log ORACLE.log -- the processor tests' transcripts (run1.sh's cpu workload) side by side.

A test's verdict is its CHECK's (tests.list): S, PASS for status 0 and a "NAME: PASS" line, SKIP for a
"NAME: SKIP" line, FAIL otherwise; Xn, PASS for exit status n; D, none, its output against the other's. A test
with no CPUTEST-END was killed with the guest (a hang). Printed: a line a test that is not PASS on both, by
class, then the counts. The class that is the engine's to answer for is "engine only": it fails there and
not on the oracle (the same binary on the hardware, or QEMU's own translator)."""
import re
import sys


def parse(path):
    tests, cur, out = {}, None, []
    for raw in open(path, "rb").read().decode("utf-8", "replace").splitlines():
        line = raw.rstrip("\r")
        m = re.match(r"CPUTEST (\S+) (\S+)$", line)
        if m:
            cur, check, out = m.group(1), m.group(2), []
            tests[cur] = {"check": check, "out": out, "rc": None}
            continue
        m = re.match(r"CPUTEST-END (\S+) rc=(\d+)$", line)
        if m and cur == m.group(1):
            tests[cur]["rc"] = int(m.group(2))
            cur = None
            continue
        if cur:
            out.append(line)
    return tests


def verdict(name, t):
    if t is None:
        return "ABSENT"
    if t["rc"] is None:
        return "HANG"
    short = name.split("/", 1)[1]
    c = t["check"]
    if c.startswith("X"):
        return "PASS" if t["rc"] == int(c[1:]) else "FAIL(rc=%d)" % t["rc"]
    if c == "D":
        return "rc=%d" % t["rc"]
    if any(re.match(re.escape(short) + r": SKIP", l) for l in t["out"]):
        return "SKIP"
    if t["rc"] == 0 and any(re.match(re.escape(short) + r": PASS($|[^A-Za-z])", l) for l in t["out"]):
        return "PASS"
    return "FAIL(rc=%d)" % t["rc"] if t["rc"] < 128 else "FAIL(sig %d)" % (t["rc"] - 128)


def main():
    a, b = parse(sys.argv[1]), parse(sys.argv[2])
    classes = {}
    for name in sorted(set(a) | set(b)):
        va, vb = verdict(name, a.get(name)), verdict(name, b.get(name))
        same = a.get(name) and b.get(name) and a[name]["out"] == b[name]["out"]
        check = (a.get(name) or b.get(name))["check"]
        if check == "D":
            cls = "D same" if same and va == vb else "D different"
        elif va == "PASS" and vb == "PASS":
            cls = "both pass"
        elif va == vb:
            cls = "both " + va.split("(")[0].lower()
        elif vb in ("PASS", "SKIP") and va not in ("PASS", "SKIP"):
            cls = "engine only"
        elif va in ("PASS", "SKIP") and vb not in ("PASS", "SKIP"):
            cls = "oracle only"
        else:
            cls = "differ"
        classes.setdefault(cls, []).append((name, va, vb))
    order = ["engine only", "differ", "D different", "both fail", "both hang", "oracle only", "both skip",
             "D same", "both pass"]
    for cls in order + sorted(set(classes) - set(order)):
        if cls in classes and cls not in ("both pass", "D same"):
            print("== %s" % cls)
            for name, va, vb in classes[cls]:
                print("  %-44s engine %-14s oracle %s" % (name, va, vb))
    print("counts: " + ", ".join("%s %d" % (c, len(classes[c])) for c in order + sorted(set(classes) - set(order))
                                 if c in classes))


if __name__ == "__main__":
    main()
