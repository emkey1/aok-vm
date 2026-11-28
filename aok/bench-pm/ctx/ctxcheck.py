#!/usr/bin/env python3
# ctxcheck.py LABEL < the monitor's output with "xp /36wx 0x3000" in it -- ctxgen.py's results against what they
# must be. One line: LABEL, PASS or the tests that failed with what they read.
import re, sys
words = []
for line in sys.stdin.read().replace('\r', '').split('\n'):
    g = re.match(r'^0*30[0-9a-f][0-9a-f]: ((?:0x[0-9a-f]{8} ?)+)', line.strip())
    if g:
        words += [int(w, 16) for w in g.group(1).split()]
label = sys.argv[1] if len(sys.argv) > 1 else '?'
if len(words) < 36:
    print(f'{label}: NO RESULTS ({len(words)} words)'); sys.exit(1)
w = words[-36:]
want = [('T1 switch and back', 0, [0x11111111, 0x22222222, 0x11111111, 0x22222222]),
        ('T4 code per context', 4, [1, 2, 1, 2]),
        ('T2 tlbie reaches what is set aside', 8, [0x33333333]),
        ('T3 entry made before the isync (context kept)', 10, [0x44444444]),
        ('T3 entry made before the isync (context set aside)', 12, [0x77777777, 0x66666666]),
        ('T5 store to code through an entry set aside', 14, [7, 9]),
        ('T6 twelve sets', 16, [0, 0x60000003]),
        ("T7 the supervisor's insns", 18, [0x70, 0x111, 0x111, 0x33333333, 0x72]),
        ('T8 the decrementer', 23, [0x7f, 0]),
        ('T8 sc', 25, [0x5d]),
        ('T8 lswx and stswx', 26, [0x01020304, 0x05060700, 0x01020304, 0x050607ff]),
        ('done', 30, [0x444f4e45, 0])]
bad = []
for name, i, exp in want:
    got = w[i:i + len(exp)]
    if got != exp:
        bad.append(f'{name}: read {" ".join("%x" % x for x in got)}, not {" ".join("%x" % x for x in exp)}')
extra = f' (before the isync: {w[9]:x} {w[11]:x})'
if w[30] == 0x4641494c:
    bad.append(f'exception {w[31]:x}00 at {w[32]:08x}, DAR {w[33]:08x}')
print(f'{label}: ' + ('PASS' + extra if not bad else 'FAIL: ' + '; '.join(bad)))
