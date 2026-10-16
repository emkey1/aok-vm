#!/usr/bin/env python3
"""corewalk.py CORE [SYMS] -- a 32-bit big-endian PowerPC core from a kit guest (corecheck, coreget.py): its
segments, registers and stack back chain, named by SYMS (nm -n of the program, unstripped: bb-syms.sh makes
busybox's) if given, and glibc's main heap walked chunk by chunk to the first header that cannot be right, with
the bytes around it.

In the back chain, a frame's saved lr is a return address into the function that owns the frame: a callee
saves its own return address in its caller's frame."""
import bisect, struct, sys

data = open(sys.argv[1], 'rb').read()
assert data[:4] == b'\x7fELF' and data[4] == 1 and data[5] == 2, 'not a 32-bit big-endian ELF'
syms = []
if len(sys.argv) > 2:
    for l in open(sys.argv[2]):
        p = l.split()
        if len(p) == 3 and p[1] in 'tTwW':
            syms.append((int(p[0], 16), p[2]))
    syms.sort()
addrs = [a for a, _ in syms]


def sym(a):
    i = bisect.bisect_right(addrs, a) - 1
    return f'{syms[i][1]}+{a - syms[i][0]:#x}' if i >= 0 and a - syms[i][0] < 0x40000 else ''


phoff, = struct.unpack_from('>I', data, 28)
phentsize, phnum = struct.unpack_from('>HH', data, 42)
segs, regs = [], None
for i in range(phnum):
    p_type, p_off, p_vaddr, _, p_filesz, p_memsz, p_flags, _ = struct.unpack_from('>8I', data, phoff + i * phentsize)
    if p_type == 1:
        segs.append((p_vaddr, p_memsz, p_off, p_filesz, p_flags))
    elif p_type == 4:
        o = p_off
        while o < p_off + p_filesz:
            namesz, descsz, ntype = struct.unpack_from('>3I', data, o)
            desc = o + 12 + ((namesz + 3) & ~3)
            if ntype == 1 and regs is None:     # NT_PRSTATUS: pr_reg at 72
                regs = struct.unpack_from('>48I', data, desc + 72)
            o = desc + ((descsz + 3) & ~3)


def seg_of(a):
    for s in segs:
        if s[0] <= a < s[0] + s[3]:
            return s
    return None


def rd(a, n=4):
    s = seg_of(a)
    if not s or a + n > s[0] + s[3]:
        return None
    return data[s[2] + a - s[0]: s[2] + a - s[0] + n]


def u32(a):
    b = rd(a)
    return None if b is None else struct.unpack('>I', b)[0]


def dump(a, n):
    for l in range(a & ~15, a + n, 16):
        b = rd(l, 16)
        if b is None:
            print(f'  {l:08x}: --')
            continue
        hx = ' '.join(b[i:i + 4].hex() for i in range(0, 16, 4))
        print(f'  {l:08x}: {hx}  ' + ''.join(chr(c) if 32 <= c < 127 else '.' for c in b))


print('segments:')
for v, m, o, f, fl in segs:
    print(f'  {v:08x}-{v + m:08x} file {f:#x} {"r" if fl & 4 else "-"}{"w" if fl & 2 else "-"}{"x" if fl & 1 else "-"}')
if regs:
    names = [f'r{i}' for i in range(32)] + ['nip', 'msr', 'orig_r3', 'ctr', 'lr', 'xer', 'ccr', 'mq', 'trap', 'dar',
                                            'dsisr', 'result']
    print(f'registers: nip {sym(regs[32])} lr {sym(regs[36])}')
    for i in range(0, 44, 4):
        print('  ' + '  '.join(f'{names[j]:>7}={regs[j]:08x}' for j in range(i, min(i + 4, 44))))
    print('back chain (frame, next, saved lr):')
    sp = regs[1]
    for _ in range(64):
        nxt, lr = u32(sp), u32(sp + 4)
        if nxt is None:
            break
        print(f'  {sp:08x} -> {nxt:08x}  lr {lr:08x} {sym(lr) if lr else ""}')
        if nxt <= sp:
            break
        sp = nxt

# The main heap: the largest writable segment below 0x40000000 (brk's, after the program's data).
heap = max((s for s in segs if s[4] & 2 and s[0] < 0x40000000 and s[3]), key=lambda s: s[3])
end = heap[0] + heap[3]
print(f'heap segment {heap[0]:08x}+{heap[3]:#x}')


def chain(c, limit):
    k = 0
    while c + 8 <= end and k < limit:
        sz = (u32(c + 4) or 0) & ~7
        if sz < 16 or sz % 16 or c + sz > end:
            break
        c, k = c + sz, k + 1
    return k


# The first chunk: TLS and the like come first from sbrk, so the start whose chain runs longest. A chunk's user
# memory (chunk + 8) is 16-aligned on 32-bit PowerPC.
c = max(range(heap[0] + 8, min(end, heap[0] + 0x10000), 16), key=lambda a: chain(a, 400))
print(f'first chunk at {c:08x}')
n, prev = 0, None
while c + 8 <= end:
    size = u32(c + 4)
    sz = size & ~7
    if sz >= 16 and c + sz == end:       # top, whose size is whatever is left
        print(f'walked {n + 1} chunks; the last, at {c:08x}, is top')
        break
    if sz < 16 or sz % 16 or c + sz > end:
        print(f'BAD chunk {n} at {c:08x}: size word {size:08x}')
        dump((prev if prev is not None else c) - 32, (c - prev if prev is not None else 0) + 160)
        break
    prev, c, n = c, c + sz, n + 1
