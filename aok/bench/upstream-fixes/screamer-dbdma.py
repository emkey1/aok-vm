#!/usr/bin/env python3
# screamer-dbdma.py QEMU-SYSTEM-PPC PC-BIOS -- after the PowerMac's sound input runs an INPUT_MORE, is its DBDMA channel
# left ACTIVE with RUN clear? Hardware never reports that, and Mac OS 9's sound plugins spin on ACTIVE with no timeout
# (UTM's issue 8033). No guest: through QEMU's qtest protocol, as a driver would program the channel.
import signal, subprocess, sys

signal.alarm(60)

qemu, bios = sys.argv[1:3]
p = subprocess.Popen([qemu, "-M", "mac99,via=pmu", "-accel", "qtest", "-qtest", "stdio", "-display", "none",
                      "-nodefaults", "-m", "256", "-L", bios, "-audiodev", "none,id=a",
                      "-global", "screamer.audiodev=a"],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)


def cmd(s):
    p.stdin.write(s + "\n")
    p.stdin.flush()
    while True:
        line = p.stdout.readline()
        if not line:
            sys.exit("QEMU went away after: " + s)
        if line.startswith("OK") or line.startswith("FAIL"):
            return line.strip()


def swap(v):
    return int.from_bytes(v.to_bytes(4, "little"), "big")


# Devices little-endian, the CPU big: what a driver does with stwbrx and lwbrx.
def wr(a, v):
    cmd(f"writel {a:#x} {swap(v):#x}")


def rd(a):
    return swap(int(cmd(f"readl {a:#x}").split()[1], 16))


CFG_ADDR, CFG_DATA = 0xf2800000, 0xf2c00000
RUN, ACTIVE = 0x8000, 0x0400
BASE = 0x80000000
CH = BASE + 0x8000 + (0x12 << 7)        # the sound input's channel: ChannelControl, then ChannelStatus at +4


def cfg_rd(devfn, reg):
    wr(CFG_ADDR, 0x80000000 | devfn << 8 | reg)
    return rd(CFG_DATA)


def cfg_wr(devfn, reg, v):
    wr(CFG_ADDR, 0x80000000 | devfn << 8 | reg)
    wr(CFG_DATA, v)


macio = next((d for d in range(0, 256, 8) if cfg_rd(d, 0) == 0x0022106b), None)
if macio is None:
    sys.exit("no mac-io found")
cfg_wr(macio, 0x10, BASE)
cfg_wr(macio, 0x04, 0x6)

CMD, BUF = 0x100000, 0x200000
# INPUT_MORE of 64 bytes, little-endian: req_count, command, phy_addr, cmd_dep, res_count, xfer_status
desc = (0x40).to_bytes(2, "little") + (0x2000).to_bytes(2, "little") + BUF.to_bytes(4, "little") + bytes(8)
cmd(f"write {CMD:#x} {len(desc)} 0x{desc.hex()}")
wr(CH + 0x0c, CMD)
before = rd(CH + 4)
wr(CH, RUN << 16 | RUN)
for _ in range(20):
    cmd("clock_step 1000000")
after = rd(CH + 4)
print(f"status before {before:#06x}, after the input ran {after:#06x}: "
      f"RUN {'set' if after & RUN else 'clear'}, ACTIVE {'set' if after & ACTIVE else 'clear'}")
print("WRONG: ACTIVE with RUN clear" if after & ACTIVE and not after & RUN else "ok: a stopped channel is not active")
p.stdin.close()
p.terminate()
