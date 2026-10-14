#!/usr/bin/env python3
"""machine.py OS ARCH DIR OUTDIR -- a base machine's .utm bundle, from build.sh's DIR (vmlinuz, initramfs,
disk.qcow2): iSH-AOK's OS root file system on ARCH, as UTM's configuration (version 4) wants it.

The same machine on every architecture, as far as UTM lets it be: the AOK gadget engine's CPU, two of
them and 1 GB, the Alpine kernel and initramfs booted directly (no firmware, no boot loader), the root
on a VirtIO disk (8 GB, growing as it fills), QEMU's user-mode network on a VirtIO card, a display with
a USB keyboard and tablet, root logged in on it and on the serial terminal, a VirtIO random number
source, and iSH-AOK's /AOK/persist shared (the machine's Sharing setting). The PCs are q35 machines with
the CPU QEMU names for the architecture.
"""
import os
import plistlib
import shutil
import sys
import uuid

OSES = {
    # name in the list, the machine's name, UTM's icon
    "alpine": ("Alpine 3.24.2", "alpine", 0),
    "devuan": ("Devuan 6", "linux", 1),
}
ARCHES = {
    "aarch64": {"label": "aarch64", "target": "virt", "cpu": "default", "serial": "ttyAMA0",
                "display": "virtio-ramfb", "n": 0},
    "x86_64": {"label": "x86_64", "target": "q35", "cpu": "qemu64", "serial": "ttyS0",
               "display": "virtio-vga", "n": 1},
    "i386": {"label": "x86", "target": "q35", "cpu": "qemu32", "serial": "ttyS0",
             "display": "virtio-vga", "n": 2},
    "riscv64": {"label": "riscv64", "target": "virt", "cpu": "default", "serial": "ttyS0",
                "display": "virtio-ramfb", "n": 3},
}


def ident(kind, n):
    """A fixed UUID per machine and per drive: AOK VM's base machines are 0xB0C0... (the study
    machines of make-vm.py are 0xA0C0...)."""
    return str(uuid.UUID(int=0xB0C0B0C0_0000_4000_8000_000000000000 + kind * 0x1000 + n)).upper()


def config(os_name, arch):
    title, icon, on = OSES[os_name]
    a = ARCHES[arch]
    n = on * 0x10 + a["n"]
    x86 = arch in ("x86_64", "i386")
    name = "%s (%s)" % (title, a["label"])
    notes = ("iSH-AOK's %s root file system for %s, as a machine of its own: the same files iSH-AOK "
             "imports, with an Alpine kernel. root is logged in on the display and the serial terminal. "
             "Small on purpose: `aok-update` brings the /AOK/tools scripts, and "
             "/AOK/tools/provision-ultimate-%s.sh a desktop and the rest, downloaded when wanted. "
             "/AOK/persist is iSH-AOK's shared directory." % (title, a["label"], os_name))
    drive = lambda image, kind, iface, k: {
        "ImageName": image, "ImageType": kind, "Interface": iface, "InterfaceVersion": 1,
        "Identifier": ident(k, n), "ReadOnly": kind != "Disk"}
    return name, {
        "Backend": "QEMU",
        "ConfigurationVersion": 4,
        "Information": {"Name": name, "IconCustom": False, "Icon": icon, "Notes": notes,
                        "UUID": ident(0, n)},
        "System": {
            "Architecture": arch, "Target": a["target"], "CPU": a["cpu"],
            "CPUFlagsAdd": [], "CPUFlagsRemove": [],
            "CPUCount": 2, "ForceMulticore": False, "MemorySize": 1024, "JITCacheSize": 0,
        },
        "QEMU": {
            "DebugLog": False, "UEFIBoot": False, "RNGDevice": True, "BalloonDevice": False,
            "TPMDevice": False, "Hypervisor": False, "RTCLocalTime": False, "PS2Controller": x86,
            "AdditionalArguments": [
                '-append "root=/dev/vda rw console=%s console=tty0 quiet"' % a["serial"]],
        },
        "Input": {"UsbBusSupport": "3.0", "UsbSharing": False, "MaximumUsbShare": 3},
        "Sharing": {"DirectoryShareMode": "None", "DirectoryShareReadOnly": False,
                    "ClipboardSharing": False, "AOKPersist": True},
        "Display": [{"Hardware": a["display"], "DynamicResolution": True, "UpscalingFilter": "Nearest",
                     "DownscalingFilter": "Linear", "NativeResolution": False}],
        "Drive": [
            drive("vmlinuz", "LinuxKernel", "None", 1),
            drive("initramfs", "LinuxInitrd", "None", 2),
            drive("disk.qcow2", "Disk", "VirtIO", 3),
        ],
        "Network": [{"Mode": "Emulated", "Hardware": "virtio-net-pci",
                     "MacAddress": "52:54:00:B0:C0:%02X" % n, "IsolateFromHost": False, "PortForward": []}],
        "Serial": [{
            "Mode": "Terminal", "Target": "Auto",
            "Terminal": {"Font": "Menlo", "FontSize": 12, "CursorBlink": True,
                         "ForegroundColor": "#ffffff", "BackgroundColor": "#000000"},
        }],
        "Sound": [],
    }


def main():
    os_name, arch, src, outdir = sys.argv[1:5]
    name, cfg = config(os_name, arch)
    bundle = os.path.join(outdir, name + ".utm")
    shutil.rmtree(bundle, ignore_errors=True)
    os.makedirs(os.path.join(bundle, "Data"))
    for f in ("vmlinuz", "initramfs", "disk.qcow2"):
        shutil.copyfile(os.path.join(src, f), os.path.join(bundle, "Data", f))
    with open(os.path.join(bundle, "config.plist"), "wb") as f:
        plistlib.dump(cfg, f)
    print(bundle)


if __name__ == "__main__":
    main()
