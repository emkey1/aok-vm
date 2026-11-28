#!/usr/bin/env python3
# ctxgen.py [OUT.bin] -- a PowerPC "firmware" (-M mac99 -bios), as machine code, that tries the TLB context cache
# (engine: tlb_context_switch(), target/ppc's check_tlb_flush()) where a stale translation would show. No
# assembler, no OS. It builds a hashed page table in which one effective address means different pages under
# different VSIDs, turns translation on, and walks segment register 4 through them. Each observation is a word
# at 0x3000; ctxcheck.py reads them from the monitor's "xp /28wx 0x3000".
#
#   T1  res0-3    SR4 = V1, V2, V1, V2 (an isync after each): the word at EA_A is V1's page's, V2's, V1's, V2's.
#   T4  res4-7    the same four with a call to code at EA_C: V1's code returns 1, V2's returns 2 (the jump cache
#                 is part of a context).
#   T2  res8      with V2 in use and V1's TLB set aside: V1's PTE for EA_A is pointed at another page, tlbie,
#                 sync, isync; then SR4 = V1. The word must be the new page's (a flush discards what is set aside).
#   T3  res9-10   SR4 = V2 with no isync, a first access to EA_B (QEMU translates it with V2: res9), SR4 = V1,
#                 isync. EA_B must then be V1's page: the entry made in between must not stay in V1's TLB.
#       res11-13  the same where the isync comes while SR4 is still V2: EA_E under V2 twice, then SR4 = V1 and
#                 EA_E must be V1's (the entry must not have been set aside with V1's TLB).
#   T5  res14-15  code at a page PX returns 7. V1's TLB gets a writable entry for PX (through EA_D) before PX
#                 has been executed; it is set aside (SR4 = V2) while PX's code runs for the first time; then,
#                 back under V1, a store through EA_D changes the code to return 9. The call must return 9: the
#                 entry that was set aside must have been told that PX now holds code.
#   T6  res16-17  twelve VSIDs, each with its own page at EA_A, three times round, then four of them three times
#                 round: res16 counts wrong words (0), res17 is the last word read. More sets than contexts kept,
#                 so one is given up and put to use again at every step of the first part.
#   T7  res18-22  the supervisor's own insns, which are gadgets since 2026-11-28: mfmsr; SR4 = V1 by mtsrin and
#                 read back by mfsr and by mfsrin; the word at EA_A after it; mfmsr after an mtmsr that sets RI.
#   res23 "DONE" (or "FAIL", with the vector in res24, SRR0 in res25 and DAR in res26, on any exception).
import struct, sys

ROM, MAIN, FAIL, RES, HTAB = 0xfff00000, 0x2000, 0x1800, 0x3000, 0x100000
def sprf(n): return (n & 0x1f) << 16 | (n >> 5) << 11
def mfspr(rd, n): return 0x7C0002A6 | rd << 21 | sprf(n)
def mtspr(n, rs): return 0x7C0003A6 | rs << 21 | sprf(n)
def lis(rd, v): return 0x3C000000 | rd << 21 | v
def ori(ra, rs, v): return 0x60000000 | rs << 21 | ra << 16 | v
def li32(rd, v): return [lis(rd, v >> 16), ori(rd, rd, v & 0xffff)]
def li(rd, v): return 0x38000000 | rd << 21 | (v & 0xffff)
def stw(rs, d, ra): return 0x90000000 | rs << 21 | ra << 16 | (d & 0xffff)
def lwz(rd, d, ra): return 0x80000000 | rd << 21 | ra << 16 | (d & 0xffff)
def addi(rd, ra, v): return 0x38000000 | rd << 21 | ra << 16 | (v & 0xffff)
def cmpw(ra, rb): return 0x7C000000 | ra << 16 | rb << 11
def beq(off): return 0x41820000 | (off & 0xfffc)
def bdnz(off): return 0x42000000 | (off & 0xfffc)
def b(off): return 0x48000000 | (off & 0x03fffffc)
def mtsr(sr, rs): return 0x7C0001A4 | rs << 21 | sr << 16
def mtsrin(rs, rb): return 0x7C0001E4 | rs << 21 | rb << 11
def mfsr(rd, sr): return 0x7C0004A6 | rd << 21 | sr << 16
def mfsrin(rd, rb): return 0x7C000526 | rd << 21 | rb << 11
def mfmsr(rd): return 0x7C0000A6 | rd << 21
def mtmsr(rs): return 0x7C000124 | rs << 21
def tlbie(rb): return 0x7C000264 | rb << 11
SPIN, ISYNC, SYNC, RFI, BCTRL, BLR = 0x48000000, 0x4C00012C, 0x7C0004AC, 0x4C000064, 0x4E800421, 0x4E800020
SDR1, SRR0, SRR1, CTR, DAR = 25, 26, 27, 9, 19
IBAT0U, IBAT0L, IBAT1U, IBAT1L, DBAT0U, DBAT0L, DBAT1U, DBAT1L = 528, 529, 530, 531, 536, 537, 538, 539

V1, V2 = 0x111, 0x222
EA_A, EA_B, EA_C, EA_D, EA_E = 0x40000000, 0x40001000, 0x40002000, 0x40003000, 0x40004000
def P(i): return 0x200000 + i * 0x1000
PC1, PC2, PX = 0x220000, 0x221000, 0x230000
NV = 12
def VK(k): return 0x300 + k

used = {}
def pte(vsid, ea, pa):
    """(address, word 0, word 1) of a PTE for ea under vsid, in the primary group."""
    h = (vsid & 0x7ffff) ^ ((ea >> 12) & 0xffff)
    g = HTAB + ((h & 0x3ff) << 6)
    slot = used.get(g, 0); used[g] = slot + 1
    assert slot < 8
    return g + 8 * slot, 0x80000000 | vsid << 7 | ((ea >> 22) & 0x3f), pa | 0x180 | 2   # R, C; read-write

m = []                                      # main, at ROM + MAIN
def here(): return ROM + MAIN + 4 * len(m)
def put(addr, val): m.extend(li32(3, addr) + li32(4, val) + [stw(4, 0, 3)])
def set_pte(vsid, ea, pa):
    a, w0, w1 = pte(vsid, ea, pa)
    put(a, w0); put(a + 4, w1)
    return a
nres = 0
def res(reg):
    global nres
    m.extend(li32(9, RES + 4 * nres) + [stw(reg, 0, 9)]); nres += 1     # r9: r3 is a call's result
def sr4(v, sync=True): m.extend(li32(5, v) + [mtsr(4, 5)] + ([ISYNC] if sync else []))
def rd(ea, reg=7): m.extend(li32(6, ea) + [lwz(reg, 0, 6)])
def call(ea): m.extend(li32(6, ea) + [mtspr(CTR, 6), BCTRL])

# real mode: an empty page table, the PTEs, the pages
m.extend(li32(3, HTAB) + li32(4, 0x4000) + [mtspr(CTR, 4), li(5, 0), stw(5, 0, 3), addi(3, 3, 4), bdnz(-8)])
pte_v1_a = set_pte(V1, EA_A, P(1)); set_pte(V2, EA_A, P(2))
set_pte(V1, EA_B, P(4)); set_pte(V2, EA_B, P(5))
set_pte(V1, EA_C, PC1); set_pte(V2, EA_C, PC2)
set_pte(V1, EA_D, PX)
set_pte(V1, EA_E, P(6)); set_pte(V2, EA_E, P(7))
for k in range(NV):
    set_pte(VK(k), EA_A, P(16 + k))
for i in range(1, 8):
    put(P(i), 0x11111111 * i)
for k in range(NV):
    put(P(16 + k), 0x60000000 + k)
put(PC1, li(3, 1)); put(PC1 + 4, BLR)
put(PC2, li(3, 2)); put(PC2 + 4, BLR)
put(PX, li(3, 7)); put(PX + 4, BLR)
for i in range(28):
    put(RES + 4 * i, 0)
# the MMU: the page table, a VSID of its own for every segment, and BATs for this code and for RAM
m.extend(li32(3, HTAB) + [mtspr(SDR1, 3)])
for n in range(16):
    m.extend(li32(5, 0x100 + n) + [mtsr(n, 5)])
for u, l, vu, vl in ((IBAT0U, IBAT0L, 0xfff0001f, 0xfff00002), (IBAT1U, IBAT1L, 0x00001fff, 0x00000002),
                     (DBAT0U, DBAT0L, 0x00001fff, 0x00000002), (DBAT1U, DBAT1L, 0xfff0001f, 0xfff00002)):
    m.extend(li32(3, vl) + [mtspr(l, 3)] + li32(3, vu) + [mtspr(u, 3)])
m.append(ISYNC)
m.extend(li(20, 0) for _ in range(1))
# (a word that is never to run after the rfi: an rfi that went on to the next insn would stop here)
m.extend(li32(3, here() + 4 * 8) + [mtspr(SRR0, 3)] + li32(3, 0x70) + [mtspr(SRR1, 3), RFI, SPIN])   # IR, DR, IP

# T1
for v in (V1, V2, V1, V2):
    sr4(v); rd(EA_A); res(7)
# T4
for v in (V1, V2, V1, V2):
    sr4(v); call(EA_C); res(3)
# T2: V2 in use, V1's TLB set aside
put(pte_v1_a + 4, P(3) | 0x180 | 2)
m.extend(li32(6, EA_A) + [tlbie(6), SYNC, ISYNC])
sr4(V1); rd(EA_A); res(7)
# T3
sr4(V2, sync=False); rd(EA_B); res(7)
sr4(V1); rd(EA_B); res(7)
sr4(V2, sync=False); rd(EA_E); res(7)
m.append(ISYNC); rd(EA_E); res(7)
sr4(V1); rd(EA_E); res(7)
# T5
m.extend(li32(6, EA_D) + li32(4, 0xabcd) + [stw(4, 0x100, 6)])
sr4(V2); call(PX); res(3)
sr4(V1)
m.extend(li32(6, EA_D) + li32(4, li(3, 9)) + [stw(4, 0, 6), SYNC, ISYNC])
call(PX); res(3)
# T6
for ks in [range(NV)] * 3 + [range(4)] * 3:
    for k in ks:
        sr4(VK(k)); rd(EA_A)
        m.extend(li32(8, 0x60000000 + k) + [cmpw(7, 8), beq(8), addi(20, 20, 1)])
res(20); res(7)
# T7
m.append(mfmsr(7)); res(7)
m.extend(li32(5, V1) + li32(6, EA_A) + [mtsrin(5, 6), ISYNC, mfsr(7, 4)]); res(7)
m.append(mfsrin(7, 6)); res(7)
rd(EA_A); res(7)
m.extend([mfmsr(10), ori(11, 10, 2), mtmsr(11), mfmsr(7)]); res(7)
m.append(mtmsr(10))
NDONE = nres
m.extend(li32(4, 0x444f4e45)); res(4)
m.append(SPIN)

fail = (li32(30, RES + 4 * (NDONE + 1)) + [stw(31, 0, 30), mfspr(29, SRR0), stw(29, 4, 30), mfspr(29, DAR), stw(29, 8, 30)] +
        li32(28, 0x4641494c) + [stw(28, -4, 30), SPIN])
rom = bytearray(MAIN + 4 * len(m))
def at(off, words):
    for i, w in enumerate(words):
        struct.pack_into('>I', rom, off + 4 * i, w)
at(0x100, [b(MAIN - 0x100)])
for v in range(0x200, 0x1800, 0x100):
    at(v, [li(31, v >> 8), b(FAIL - (v + 4))])
at(FAIL, fail)
at(MAIN, m)
assert nres == 24 and NDONE == 23 and len(rom) < 0x100000
out = sys.argv[1] if len(sys.argv) > 1 else 'ctxtest.bin'
open(out, 'wb').write(rom)
print(len(rom), 'bytes;', len(m), 'words of main;', nres, 'results')
