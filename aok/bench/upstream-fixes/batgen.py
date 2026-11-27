#!/usr/bin/env python3
# batgen.py -- two PowerPC programs, as machine code, for what a CPU reset does to the BAT registers
# (UTM's e1c17c2009: Mac OS 9's Restart ended on a black screen). No assembler needed.
#
# batbios-mac99.bin, batbios-g3beige.bin: a "firmware" (-bios). At the reset vector, the first time (the word at
#   0x2000 is not "OKAY") it loads DBAT0 and IBAT3, writes "OKAY" and spins. After a reset it finds "OKAY", stores
#   what DBAT0U, DBAT0L, IBAT3U, IBAT3L hold at 0x2010.., "DONE" at 0x2004, and spins. RAM outlives a reset, so
#   xp /8wx 0x2000 from the monitor shows what the BATs held when the CPU came out of reset.
# batkern.bin: a "kernel" (-kernel, raw: loaded at 0x01000000 and entered by OpenBIOS). It counts its starts in the
#   word at 0x03000000, maps OpenBIOS's own address (0xfff00000, 128 KiB) to empty RAM at 0x02000000 with IBAT0 and
#   DBAT0, as an OS that has taken the machine over does, and spins. After a reset OpenBIOS turns translation on and
#   expects its next fetch to fault; through the stale BAT it runs zeros instead and never starts the kernel again.
import struct, sys
SPR = dict(IBAT0U=528, IBAT0L=529, IBAT3U=534, IBAT3L=535, DBAT0U=536, DBAT0L=537)
def sprf(n): return (n & 0x1f) << 16 | (n >> 5) << 11
def mfspr(rd, n): return 0x7C0002A6 | rd << 21 | sprf(SPR[n])
def mtspr(n, rs): return 0x7C0003A6 | rs << 21 | sprf(SPR[n])
def lis(rd, v): return 0x3C000000 | rd << 21 | v
def ori(ra, rs, v): return 0x60000000 | rs << 21 | ra << 16 | v
def li32(rd, v): return [lis(rd, v >> 16), ori(rd, rd, v & 0xffff)]
def stw(rs, d, ra): return 0x90000000 | rs << 21 | ra << 16 | d
def lwz(rd, d, ra): return 0x80000000 | rd << 21 | ra << 16 | d
def addi(rd, ra, v): return 0x38000000 | rd << 21 | ra << 16 | v
def cmpw(ra, rb): return 0x7C000000 | ra << 16 | rb << 11
def beq(off): return 0x41820000 | (off & 0xfffc)
SPIN, ISYNC = 0x48000000, 0x4C00012C
def code(words): return b''.join(struct.pack('>I', w) for w in words)

first = (li32(3, 0x80001fff) + [mtspr('DBAT0U', 3)] + li32(4, 0x80000012) + [mtspr('DBAT0L', 4)] +
         li32(5, 0x90001ffe) + [mtspr('IBAT3U', 5)] + li32(6, 0x90000012) + [mtspr('IBAT3L', 6)] +
         [stw(10, 0x2000, 0), SPIN])
head = [lwz(9, 0x2000, 0)] + li32(10, 0x4f4b4159) + [cmpw(9, 10)]
second = ([mfspr(3, 'DBAT0U'), stw(3, 0x2010, 0), mfspr(4, 'DBAT0L'), stw(4, 0x2014, 0),
           mfspr(5, 'IBAT3U'), stw(5, 0x2018, 0), mfspr(6, 'IBAT3L'), stw(6, 0x201c, 0)] +
          li32(11, 0x444f4e45) + [stw(11, 0x2004, 0), SPIN])
bios = code(head + [beq(4 * (1 + len(first)))] + first + second)
open('batbios-mac99.bin', 'wb').write(b'\0' * 0x100 + bios)                   # PROM at 0xfff00000
open('batbios-g3beige.bin', 'wb').write(b'\0' * 0x300100 + bios + b'\0' * (0x400000 - 0x300100 - len(bios)))  # 0xffc00000, 4 MiB

kern = ([lis(9, 0x0300), lwz(10, 0, 9), addi(10, 10, 1), stw(10, 0, 9)] +
        li32(3, 0xfff00002) + li32(4, 0x02000002) +
        [mtspr('IBAT0L', 4), mtspr('IBAT0U', 3), mtspr('DBAT0L', 4), mtspr('DBAT0U', 3), ISYNC, SPIN])
open('batkern.bin', 'wb').write(code(kern))
print(len(bios), len(code(kern)))
