#!/bin/bash
# tinycore.sh OUTDIR -- OUTDIR/tinycore-17.1.zip, the "Tiny Core Linux 17.1" machine: Tiny Core's official CorePlus
# ISO (distro.ibiblio.org) made into a machine every part of which Tiny Core has a driver for, as Mighty-Moth-Boy
# asked for in github.com/emkey1/aok-vm/issues/1. Their machine was an ISA-only PC (isapc) with an ISA NE2000, which
# Linux cannot find by itself, so it had no network, and no DMA for its disk. This one is the i440FX PC ("pc"): an
# IDE disk, a Realtek 8139, the standard VGA, 1 GB.
#
# The kernel and initramfs, taken from the ISO unchanged, are booted directly, so there is no BIOS boot and no boot
# menu (the ISO's waits 60 s). The disk is Tiny Core's own persistent layout: one ext4 partition with tce/, which
# Tiny Core is told to use (tce=sda1), its optional/ holding the ISO's extensions for CorePlus's default desktop
# (flwm_topside), the installer, the remaster tool and the keymaps, unchanged, with what they depend on, and
# onboot.lst loading them. Left out: the CD's 23 firmware extensions and its wifi tools (about 200 of its 256 MB,
# for hardware a virtual machine does not have), and its five other window managers: on the A10X the desktop is up
# 58 s after the app starts the machine, where the CD's full set took 150 s. Apps installs into the same tce/, so
# what it installs stays. Checked 2026-11-12: the desktop, the disk mounted as /mnt/sda1, and a DHCP lease from the
# app's user-mode network (a filter-dump of the RTL8139's traffic), on the A10X and on Homebrew's QEMU on MBP5.
# And that tce-load -wi (what Apps runs) downloads into tce/ and onboot.lst, and the program is there after a restart.
# On a Mac: curl, bsdtar, Homebrew's qemu-img and e2fsprogs, python3, zip. OUTDIR also keeps the ISO (~290 MB).
set -euo pipefail
OUT=$(mkdir -p "$1" && cd "$1" && pwd)
ISO=CorePlus-current.iso
URL=https://distro.ibiblio.org/tinycorelinux/17.x/x86/release/$ISO
# 17.1, as served 2026-11-12: the MD5 the release lists, and the copy in Mighty-Moth-Boy's machine (same CRC-32)
MD5=c681af3450c9890b6bd816fb8d8ea491
NAME="Tiny Core Linux 17.1"
QEMU_IMG=$(command -v qemu-img || echo /opt/homebrew/bin/qemu-img)
MKE2FS=/opt/homebrew/opt/e2fsprogs/sbin/mke2fs
T=$(mktemp -d "${TMPDIR:-/tmp}/tinycore.XXXXXX"); trap 'chmod -R u+w "$T"; rm -rf "$T"' EXIT
[ -f "$OUT/$ISO" ] || curl -fL --max-time 1800 -o "$OUT/$ISO" "$URL"
[ "$(md5 -q "$OUT/$ISO")" = $MD5 ] || { echo "$ISO is not 17.1's" >&2; exit 1; }
M="$T/m/$NAME.utm"; mkdir -p "$M/Data" "$T/fs/tce/optional"
bsdtar -xf "$OUT/$ISO" -C "$T" boot/vmlinuz boot/core.gz cde
python3 -I - "$T/cde/optional" "$T/fs/tce" <<'EOF'
import os, shutil, sys
src, tce = sys.argv[1], sys.argv[2]
KERNEL = "6.18.35-tinycore"
WANT = ["Xvesa.tcz", "aterm.tcz", "flwm_topside.tcz", "wbar.tcz", "tc-install-GUI.tcz", "kmaps.tcz",
        "pciutils.tcz", "ezremaster.tcz"]
got = []
def add(name):
    name = name.strip().replace("KERNEL", KERNEL)
    if not name or name in got:
        return
    if not os.path.exists(os.path.join(src, name)):
        sys.exit("%s is not on the CD" % name)
    got.append(name)
    dep = os.path.join(src, name + ".dep")
    if os.path.exists(dep):
        for d in open(dep):
            add(d)
for w in WANT:
    add(w)
for n in got:
    for f in (n, n + ".dep", n + ".md5.txt"):
        if os.path.exists(os.path.join(src, f)):
            shutil.copyfile(os.path.join(src, f), os.path.join(tce, "optional", f))
with open(os.path.join(tce, "onboot.lst"), "w") as f:
    f.write("".join(w + "\n" for w in WANT))
print(len(got), "extensions,", sum(os.path.getsize(os.path.join(src, n)) for n in got) >> 20, "MB")
EOF
chmod 644 "$T/boot/vmlinuz" "$T/boot/core.gz"; mv "$T/boot/vmlinuz" "$T/boot/core.gz" "$M/Data/"
# 4 GiB, room for what Apps installs: an MBR with one Linux partition from 1 MiB, ext4 holding tce/
truncate -s 4G "$T/disk.raw"
"$MKE2FS" -q -t ext4 -L tce -d "$T/fs" -E offset=1048576 "$T/disk.raw" 4193280k
python3 -I - "$T/disk.raw" <<'EOF'
import struct, sys
start, count = 2048, (4 << 30) // 512 - 2048
entry = struct.pack("<B3sB3sII", 0, b"\xfe\xff\xff", 0x83, b"\xfe\xff\xff", start, count)
with open(sys.argv[1], "r+b") as f:
    f.seek(440); f.write(struct.pack("<I", 0x7c0e7c0e) + b"\0\0" + entry + b"\0" * 48 + b"\x55\xaa")
EOF
"$QEMU_IMG" convert -q -c -O qcow2 "$T/disk.raw" "$M/Data/disk.qcow2"
python3 -I - "$M/config.plist" <<'EOF'
import plistlib, sys
def drive(name, kind, interface, n):
    return {"ImageName": name, "ImageType": kind, "Interface": interface, "InterfaceVersion": 1,
            "Identifier": "B0C0B0C0-0000-4000-8000-0000000071%02X" % n, "ReadOnly": kind == "CD"}
notes = ("Tiny Core Linux 17.1 (CorePlus), from the official ISO at distro.ibiblio.org/tinycorelinux: a small "
         "Linux with a desktop. Apps, on the bar at the bottom, installs programs from Tiny Core's repository "
         "(LibreOffice, Firefox, games and many more); they are kept on the hard disk, in its tce folder, so they "
         "are there at the next start. The kernel and the extensions are the ISO's, unchanged; the wireless "
         "firmware and the other window managers on the ISO are left out, which makes the start much quicker. "
         "Thanks to Mighty-Moth-Boy, who suggested it (github.com/emkey1/aok-vm/issues/1).\n\n"
         "Tiny Core is free software, under the GNU GPL version 2 among others; its sources are at "
         "distro.ibiblio.org/tinycorelinux/17.x/x86/release/src.")
vm = {
    "Backend": "QEMU", "ConfigurationVersion": 4,
    "Information": {"Name": "Tiny Core Linux 17.1", "IconCustom": False, "Icon": "linux", "Notes": notes,
                    "UUID": "B0C0B0C0-0000-4000-8000-000000007100"},
    "System": {"Architecture": "i386", "Target": "pc", "CPU": "qemu32", "CPUFlagsAdd": [], "CPUFlagsRemove": [],
               "CPUCount": 1, "ForceMulticore": False, "MemorySize": 1024, "JITCacheSize": 0},
    "QEMU": {"DebugLog": False, "UEFIBoot": False, "RNGDevice": False, "BalloonDevice": False, "TPMDevice": False,
             "Hypervisor": False, "RTCLocalTime": False, "PS2Controller": True,
             "AdditionalArguments": ['-append "loglevel=3 tce=sda1 showapps desktop=flwm_topside"']},
    "Input": {"UsbBusSupport": "Disabled", "UsbSharing": False, "MaximumUsbShare": 3},
    "Sharing": {"DirectoryShareMode": "None", "DirectoryShareReadOnly": False, "ClipboardSharing": False},
    "Display": [{"Hardware": "VGA", "DynamicResolution": False, "UpscalingFilter": "Linear",
                 "DownscalingFilter": "Linear", "NativeResolution": False}],
    "Drive": [drive("vmlinuz", "LinuxKernel", "None", 1), drive("core.gz", "LinuxInitrd", "None", 2),
              drive("disk.qcow2", "Disk", "IDE", 3)],
    "Network": [{"Mode": "Emulated", "Hardware": "rtl8139", "MacAddress": "52:54:00:B0:C0:71",
                 "IsolateFromHost": False, "PortForward": []}],
    "Serial": [], "Sound": [],
}
with open(sys.argv[1], "wb") as f:
    plistlib.dump(vm, f)
EOF
rm -f "$OUT/tinycore-17.1.zip"
(cd "$T/m" && zip -q -r -X "$OUT/tinycore-17.1.zip" "$NAME.utm")
ls -l "$OUT/tinycore-17.1.zip"
shasum -a 256 "$OUT/tinycore-17.1.zip"
