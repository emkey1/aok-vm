#!/usr/bin/env python3
# patch-sys.py IN OUT -- ReactOS 0.4.16's usbhub.sys (i386, release; from its CD, reactos/system32/drivers)
# with usbhub-wait.patch's change made in the binary: USBH_FdoQueryBusRelations waits for the root hub's
# notification event, at most a second, instead of sleeping a second. The 45 bytes from the sleep's interval
# to the stack's restoring after the call become a KeWaitForSingleObject call, the same length; the call keeps
# its place, so the base relocation of its import slot (the only one in those bytes) still applies. Then the
# PE checksum. Refuses any other usbhub.sys.
import struct, sys

BASE = 0x10000                      # the image base; .text is at file offset = RVA (0x1000)
AT, END = 0x14f35, 0x14f62
OLD = bytes.fromhex(
    "c745e0806967ff"                # mov dword [ebp-0x20], 0xff676980: -10000000, one second, low half
    "c745e4ffffffff"                # mov dword [ebp-0x1c], -1: the high half
    "8d45e0" "89442408"             # lea eax, [ebp-0x20]; mov [esp+8], eax: &Interval
    "c744240400000000"              # mov dword [esp+4], 0: FALSE
    "c7042400000000"                # mov dword [esp], 0: KernelMode
    "ff15e8510200"                  # call [KeDelayExecutionThread]
    "83ec0c")                       # sub esp, 12: the callee popped three arguments
NEW = bytes.fromhex(
    "0f1f840000000000"              # nop
    "c745e0806967ff"                # mov dword [ebp-0x20], 0xff676980
    "834de4ff"                      # or dword [ebp-0x1c], -1
    "8d45e0" "50"                   # lea eax, [ebp-0x20]; push eax: Timeout
    "6a00" "6a00" "6a00"            # push 0 three times: Alertable FALSE, KernelMode, Executive
    "8d861c010000" "50"             # lea eax, [esi+0x11c]; push eax: &HubExtension->RootHubNotificationEvent
    "ff150c520200"                  # call [KeWaitForSingleObject]: the callee pops the five pushes
    "0f1f00")                       # nop
IMPORTS = {0x251e8: "KeDelayExecutionThread", 0x2520c: "KeWaitForSingleObject"}

def checksum(d, at):
    b = bytearray(d); b[at:at + 4] = bytes(4)
    s = 0
    for (w,) in struct.iter_unpack("<H", b + bytes(len(b) & 1)):
        s += w; s = (s & 0xffff) + (s >> 16)
    return (s + len(b)) & 0xffffffff

def import_slots(d):
    """{IAT address: name} for ntoskrnl's imports, to check the two this relies on."""
    pe = struct.unpack_from("<I", d, 0x3c)[0]; opt = pe + 24
    nsec = struct.unpack_from("<H", d, pe + 6)[0]; optsz = struct.unpack_from("<H", d, pe + 20)[0]
    secs = [struct.unpack_from("<IIII", d, pe + 24 + optsz + 40 * i + 8) for i in range(nsec)]
    def off(rva):
        return next(rp + rva - va for vsz, va, rsz, rp in secs if va <= rva < va + max(vsz, rsz))
    out = {}; i = off(struct.unpack_from("<I", d, opt + 104)[0])
    while True:
        oft, _, _, name, ft = struct.unpack_from("<IIIII", d, i)
        if not name: return out
        for j in range(1 << 16):
            e = struct.unpack_from("<I", d, off(oft or ft) + 4 * j)[0]
            if not e: break
            out[BASE + ft + 4 * j] = d[off(e) + 2:].split(b"\0")[0].decode()
        i += 20

d = bytearray(open(sys.argv[1], "rb").read())
pe = struct.unpack_from("<I", d, 0x3c)[0]
if struct.unpack_from("<I", d, pe + 24 + 28)[0] != BASE or d[AT - BASE:END - BASE] != OLD:
    sys.exit("not ReactOS 0.4.16's usbhub.sys (or patched already)")
slots = import_slots(d)
for a, n in IMPORTS.items():
    if slots.get(a) != n:
        sys.exit("import slot %#x is %s, not %s" % (a, slots.get(a), n))
assert len(NEW) == len(OLD) and NEW[0x14f59 - AT:][:2] == b"\xff\x15"
d[AT - BASE:END - BASE] = NEW
struct.pack_into("<I", d, pe + 0x58, checksum(d, pe + 0x58))
open(sys.argv[2], "wb").write(d)
print("%s: patched, checksum %#x" % (sys.argv[2], struct.unpack_from("<I", d, pe + 0x58)[0]))
