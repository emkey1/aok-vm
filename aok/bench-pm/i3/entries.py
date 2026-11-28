#!/usr/bin/env python3
# entries.py FILE -- QEMU_AOK_STATS=2's "aok: tcg-entry COUNT PC INSN" lines, summed by what the insn is: the
# first insns of TCG's TBs by how often the main loop entered them.
import collections, sys
rows = []
for l in open(sys.argv[1]):
    p = l.split()
    if len(p) == 5 and p[1] == 'tcg-entry':
        rows.append((int(p[2]), int(p[3], 16), int.from_bytes(bytes.fromhex(p[4]), 'little')))
X31 = {0:'cmp',19:'mfcr',83:'mfmsr',144:'mtcrf',146:'mtmsr',210:'mtsr',242:'mtsrin',595:'mfsr',659:'mfsrin',306:'tlbie',566:'tlbsync',598:'sync',86:'dcbf',54:'dcbst',982:'icbi',1014:'dcbz',278:'dcbt',246:'dcbtst',597:'lswi',533:'lswx',725:'stswi',661:'stswx',103:'lvx',359:'lvxl',231:'stvx',487:'stvxl',6:'lvsl',38:'lvsr',7:'lvebx',39:'lvehx',71:'lvewx',135:'stvebx',167:'stvehx',199:'stvewx',342:'dst',374:'dstst',822:'dss',339:'mfspr',467:'mtspr',371:'mftb',20:'lwarx',150:'stwcx.',4:'tw',534:'lwbrx',662:'stwbrx',790:'lhbrx',918:'sthbrx',512:'mcrxr',758:'dcba'}
X19 = {50:'rfi',150:'isync',528:'bcctr',16:'bclr',0:'mcrf'}
def name(w):
    op = w >> 26; xo = (w >> 1) & 0x3ff
    if op == 31:
        n = X31.get(xo)
        if n in ('mfspr', 'mtspr'):
            return '%s %d' % (n, ((w >> 16) & 0x1f) | (((w >> 11) & 0x1f) << 5))
        if n is None and ((w >> 1) & 0x1ff) in (266, 10, 138, 202, 234, 235, 40, 8, 136, 200, 232, 104, 459, 491) and (w >> 10) & 1:
            return 'OE form %d' % ((w >> 1) & 0x1ff)
        return n or '31/%d' % xo
    if op == 19: return X19.get(xo, '19/%d' % xo)
    if op == 4: return 'altivec 4/%d' % (w & 0x7ff if (w & 0x3f) < 32 or True else 0)
    if op == 17: return 'sc'
    if op == 3: return 'twi'
    if 48 <= op <= 55: return 'FP load/store, MSR[FP] off'
    if op in (59, 63): return 'FP op %d/%d, MSR[FP] off?' % (op, xo)
    if op == 16: return 'bc (CTR and CR, or cond. bcctr)'
    return 'op %d' % op
c = collections.Counter(); ex = {}
for n, pc, w in rows:
    k = name(w); c[k] += n; ex.setdefault(k, (n, pc, w))
tot = sum(c.values())
print(len(rows), 'rows;', tot, 'entries')
# AltiVec lumped for the summary
av = sum(v for k, v in c.items() if k.startswith('altivec'))
print('%11d %5.1f%%  all AltiVec arithmetic (opcode 4)' % (av, 100 * av / tot))
for k, v in c.most_common(int(sys.argv[2]) if len(sys.argv) > 2 else 30):
    n, pc, w = ex[k]
    print('%11d %5.1f%%  %-34s e.g. %08x %08x x%d' % (v, 100 * v / tot, k, pc, w, n))
