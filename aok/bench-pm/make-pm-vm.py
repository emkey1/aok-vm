#!/usr/bin/env python3
"""make-pm-vm.py OUTDIR KITDIR -- two console machines for the PowerPC and 68k engines, from the kit build-kit.sh
makes (KITDIR/ppc, KITDIR/m68k: vmlinux and initramfs.cpio):

  "AOK PowerPC Console.utm"  a PowerPC Mac (mac99, the G4), Linux booted directly, the console on the serial
                             terminal: the race's workloads, then a shell.
  "AOK 68k Console.utm"      a Quadra 800 (q800), the same.

Copied into the app's Documents, the app lists them. They check that an engine starts in the app and runs the
guest; they are not machines for anyone to use (no disk, no network, no display).
"""
import os
import plistlib
import shutil
import sys
import uuid

MACHINES = {
    "ppc": {"name": "AOK PowerPC Console", "target": "mac99", "memory": 512, "n": 0x40},
    "m68k": {"name": "AOK 68k Console", "target": "q800", "memory": 256, "n": 0x50},
}


def ident(n):
    return str(uuid.UUID(int=0xA0C0A0C0_0000_4000_8000_000000000000 + n)).upper()


def machine(arch, m):
    return {
        "Backend": "QEMU",
        "ConfigurationVersion": 4,
        "Information": {"Name": m["name"], "IconCustom": False, "Icon": "linux", "UUID": ident(m["n"]),
                        "Notes": "Linux on the %s engine, booted directly: the race's workloads, then a shell on "
                                 "the serial terminal (aok/bench-pm)." % arch},
        "System": {"Architecture": arch, "Target": m["target"], "CPU": "default", "CPUFlagsAdd": [],
                   "CPUFlagsRemove": [], "CPUCount": 1, "ForceMulticore": False, "MemorySize": m["memory"],
                   "JITCacheSize": 0},
        "QEMU": {"DebugLog": True, "UEFIBoot": False, "RNGDevice": False, "BalloonDevice": False,
                 "TPMDevice": False, "Hypervisor": False, "RTCLocalTime": False, "PS2Controller": False,
                 "AdditionalArguments": ['-append "console=ttyS0 rdinit=/init quiet bench=coremark,sha256 then=shell"']},
        "Input": {"UsbBusSupport": "Disabled", "UsbSharing": False, "MaximumUsbShare": 3},
        "Sharing": {"DirectoryShareMode": "None", "DirectoryShareReadOnly": False, "ClipboardSharing": False},
        "Display": [], "Network": [], "Sound": [],
        "Serial": [{"Mode": "Terminal", "Target": "Auto",
                    "Terminal": {"Font": "Menlo", "FontSize": 12, "CursorBlink": True,
                                 "ForegroundColor": "#ffffff", "BackgroundColor": "#000000"}}],
        "Drive": [
            {"ImageName": "vmlinux", "ImageType": "LinuxKernel", "Interface": "None", "InterfaceVersion": 1,
             "Identifier": ident(m["n"] + 1), "ReadOnly": True},
            {"ImageName": "initramfs.cpio", "ImageType": "LinuxInitrd", "Interface": "None", "InterfaceVersion": 1,
             "Identifier": ident(m["n"] + 2), "ReadOnly": True},
        ],
    }


def main():
    outdir, kit = sys.argv[1], sys.argv[2]
    for arch, m in MACHINES.items():
        bundle = os.path.join(outdir, m["name"] + ".utm")
        shutil.rmtree(bundle, ignore_errors=True)
        os.makedirs(os.path.join(bundle, "Data"))
        for f in ("vmlinux", "initramfs.cpio"):
            shutil.copyfile(os.path.join(kit, arch, f), os.path.join(bundle, "Data", f))
        with open(os.path.join(bundle, "config.plist"), "wb") as f:
            plistlib.dump(machine(arch, m), f)
        print(bundle)


main()
