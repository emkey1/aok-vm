#!/usr/bin/env python3
"""make-vm.py OUTDIR KERNEL INITRAMFS EFI_VARS [DEVUAN_DIR] -- ready-made RISC-V virtual machines for UTM.

A .utm bundle is a directory: config.plist (UTM's configuration format, version 4) and Data/ with the files it
names. Copied into the app's Documents, UTM lists it like one made in its own wizard.

  "AOK RISC-V Console.utm"  The race's guest: the Alpine kernel and the benchmark userland, booted directly
                            (OpenSBI, then the kernel), one CPU, no display, the console on UTM's built-in
                            terminal, a virtio network card. It runs the six workloads, printing a RESULT
                            line for each (name, then wall, user and system milliseconds in the guest), and
                            leaves a shell.
  "AOK RISC-V Display.utm"  The same guest with its console on a display: UTM's default display device
                            (virtio-ramfb), a USB keyboard, network, two CPUs. No workloads, a shell.
  "AOK RISC-V UEFI.utm"     What UTM's wizard makes for a RISC-V "virt" machine, with no disk: UEFI firmware,
                            a virtio-ramfb display, USB input, sound, network. It ends at the firmware's own
                            shell, having found nothing to boot. It is there to attach an installer to.

  "Devuan Ultimate RISC-V.utm"
                            With DEVUAN_DIR (what build-devuan-disk.sh and its "ultimate" step leave:
                            devuan-riscv64.qcow2, vmlinuz, initrd.img): Devuan 6 on a disk of its own, booted
                            with its own kernel, on the GL display device, four CPUs, 2 GB, and provisioned
                            with iSH-AOK's own scripts, which are in /AOK/tools there: the "ultimate
                            terminal" tool set, and a Wayland desktop that `desktop` starts. The login aok
                            (no password, sudo without one) is on the display's console, root on the serial
                            terminal; "gltest" says which GL renderer a program gets.

INITRAMFS is the VM image of update-roots.sh (initramfs-riscv64-vm.cpio): the race's userland plus the
kernel's modules, without which the guest has no driver for a network card, a display or a USB keyboard.
The Alpine guests carry the same scripts in /AOK/tools when the image was built with them (update-roots.sh),
to try: they live in memory, so what the scripts install is gone at shutdown.
All of them have UTM's debug log on (Data/debug.log: the QEMU command line and QEMU's messages).
"""
import os
import plistlib
import shutil
import sys
import uuid

WORKLOADS = "coremark,nbody,python,xz,sha256,awk"

# ARCH=aarch64 in the environment makes the arm64 machines instead: "AOK ARM64 Console.utm" (KERNEL and
# INITRAMFS are then the arm64 guest's: kernel/vmlinuz-virt-aarch64, initramfs-aarch64-vm.cpio) and, with
# DEVUAN_DIR (devuan-aarch64/), "Devuan Ultimate ARM64.utm". UTM gives an arm64 machine a cortex-a72.
# Their UUIDs and MAC addresses are the RISC-V ones plus 0x10.
#
# ARCH=x86_64 and ARCH=i386 make "AOK x86-64 Console.utm" and "AOK x86 32-bit Console.utm" the same way
# (kernel/vmlinuz-virt-x86_64 with initramfs-x86_64.cpio; kernel/vmlinuz-virt-x86 with initramfs-x86.cpio):
# a PC, with a CPU that has rdrand and a kernel told to trust it, since without a source of entropy the
# guest waits a quarter of a minute for some, and with no network card, the image having no modules.
# With ARCH=i386 and XP_DISK naming an empty 20 GB qcow2, also "Windows XP.utm" (windows_xp() below).
ARCH = os.environ.get("ARCH", "riscv64")
A = {
    "riscv64": {"label": "RISC-V", "serial": "ttyS0", "kernel": "Image-lts-riscv64",
                "initramfs": "initramfs-riscv64.cpio", "n": 0, "target": "virt", "cpu": "default"},
    "aarch64": {"label": "ARM64", "serial": "ttyAMA0", "kernel": "vmlinuz-virt-aarch64",
                "initramfs": "initramfs-aarch64.cpio", "n": 0x10, "target": "virt", "cpu": "default"},
    "x86_64": {"label": "x86-64", "serial": "ttyS0", "kernel": "vmlinuz-virt-x86_64",
               "initramfs": "initramfs-x86_64.cpio", "n": 0x20, "target": "q35", "cpu": "qemu64"},
    "i386": {"label": "x86 32-bit", "serial": "ttyS0", "kernel": "vmlinuz-virt-x86",
             "initramfs": "initramfs-x86.cpio", "n": 0x30, "target": "q35", "cpu": "qemu32"},
}[ARCH]
X86 = ARCH in ("x86_64", "i386")


def vm_uuid(n):
    return "A0C0A0C0-0000-4000-8000-%012X" % (n + A["n"])


def mac(n):
    return "52:54:00:A0:C0:%02X" % (n + A["n"])


def base(name, notes, vm_uuid, cpus, memory):
    return {
        "Backend": "QEMU",
        "ConfigurationVersion": 4,
        "Information": {"Name": name, "IconCustom": False, "Icon": "linux", "Notes": notes, "UUID": vm_uuid},
        "System": {
            "Architecture": ARCH, "Target": A["target"], "CPU": A["cpu"],
            "CPUFlagsAdd": ["rdrand"] if X86 else [], "CPUFlagsRemove": [],
            "CPUCount": cpus, "ForceMulticore": False, "MemorySize": memory, "JITCacheSize": 0,
        },
        "QEMU": {
            "DebugLog": True, "UEFIBoot": False, "RNGDevice": False, "BalloonDevice": False,
            "TPMDevice": False, "Hypervisor": False, "RTCLocalTime": False, "PS2Controller": False,
            "AdditionalArguments": [],
        },
        "Input": {"UsbBusSupport": "Disabled", "UsbSharing": False, "MaximumUsbShare": 3},
        "Sharing": {"DirectoryShareMode": "None", "DirectoryShareReadOnly": False, "ClipboardSharing": False},
        "Display": [], "Drive": [], "Network": [], "Serial": [], "Sound": [],
    }


def network(mac):
    # "Emulated": QEMU's user-mode network, which is all iOS allows. The guest takes an address by DHCP.
    return {"Mode": "Emulated", "Hardware": "virtio-net-pci", "MacAddress": mac,
            "IsolateFromHost": False, "PortForward": []}


def display():
    return {"Hardware": "virtio-ramfb", "DynamicResolution": True, "UpscalingFilter": "Nearest",
            "DownscalingFilter": "Linear", "NativeResolution": False}


def direct_boot(n):
    """The kernel and initramfs as UTM's -kernel and -initrd "drives"."""
    return [
        {"ImageName": A["kernel"], "ImageType": "LinuxKernel", "Interface": "None", "InterfaceVersion": 1,
         "Identifier": str(uuid.UUID(int=0xA0C0A0C0_0000_4000_8000_0000000000A0 + n + A["n"] * 0x100)).upper(),
         "ReadOnly": True},
        {"ImageName": A["initramfs"], "ImageType": "LinuxInitrd", "Interface": "None", "InterfaceVersion": 1,
         "Identifier": str(uuid.UUID(int=0xA0C0A0C0_0000_4000_8000_0000000000B0 + n + A["n"] * 0x100)).upper(),
         "ReadOnly": True},
    ]


def terminal():
    return {
        "Mode": "Terminal", "Target": "Auto",
        "Terminal": {"Font": "Menlo", "FontSize": 12, "CursorBlink": True,
                     "ForegroundColor": "#ffffff", "BackgroundColor": "#000000"},
    }


def write(outdir, config, files):
    bundle = os.path.join(outdir, config["Information"]["Name"] + ".utm")
    shutil.rmtree(bundle, ignore_errors=True)
    os.makedirs(os.path.join(bundle, "Data"))
    for name, source in files.items():
        shutil.copyfile(source, os.path.join(bundle, "Data", name))
    with open(os.path.join(bundle, "config.plist"), "wb") as f:
        plistlib.dump(config, f)
    print(bundle)


def devuan(outdir, d):
    # (a name and a UUID of its own: an earlier, unprovisioned "Devuan RISC-V" may be installed and running)
    vm = base("Devuan Ultimate " + A["label"],
              "Devuan 6 (Excalibur) " + ARCH + " with its own kernel, provisioned by iSH-AOK's scripts "
              "(/AOK/tools). The login aok is on the display: `desktop` starts the Wayland desktop, "
              "`gltest` says which GL renderer programs get. root is on the serial terminal. Neither has a "
              "password.",
              vm_uuid(6), cpus=4, memory=2048)
    # net.ifnames=0: the image's network configuration names eth0.
    vm["QEMU"]["AdditionalArguments"] = [
        '-append "root=/dev/vda rw console=%s console=tty0 net.ifnames=0 quiet"' % A["serial"],
    ]
    vm["QEMU"]["RNGDevice"] = True
    vm["Input"]["UsbBusSupport"] = "3.0"
    vm["Display"] = [dict(display(), Hardware="virtio-ramfb-gl")]
    vm["Network"] = [network(mac(6))]
    # A sound card the Debian riscv64 kernel has a driver for (snd-hda-intel; also virtio-sound and
    # usb-audio, not AC97 or ES1370). The games of /AOK/tools/setup-games.sh play through it with ALSA.
    vm["Sound"] = [{"Hardware": "intel-hda"}]
    vm["Serial"] = [terminal()]
    def ident(n):
        return str(uuid.UUID(int=0xA0C0A0C0_0000_4000_8000_0000000000E0 + n + A["n"] * 0x100)).upper()
    vm["Drive"] = [
        {"ImageName": "vmlinuz", "ImageType": "LinuxKernel", "Interface": "None", "InterfaceVersion": 1,
         "Identifier": ident(1), "ReadOnly": True},
        {"ImageName": "initrd.img", "ImageType": "LinuxInitrd", "Interface": "None", "InterfaceVersion": 1,
         "Identifier": ident(2), "ReadOnly": True},
        {"ImageName": "devuan-%s.qcow2" % ARCH, "ImageType": "Disk", "Interface": "VirtIO",
         "InterfaceVersion": 1, "Identifier": ident(3), "ReadOnly": False},
    ]
    write(outdir, vm, {n: os.path.join(d, n) for n in ("vmlinuz", "initrd.img", "devuan-%s.qcow2" % ARCH)})


def windows_xp(outdir, disk):
    """
    "Windows XP.utm": UTM's own gallery template for XP (512 MB, a 20 GB IDE disk, VGA), with an empty
    IDE CD drive for the installation disc, which is the user's to supply (UTM's page names Microsoft's
    en_windows_xp_professional_sp3_Nov_2013_Incl_SATA_Drivers.iso). Choose it in the machine's CD drive
    and start: SeaBIOS boots the CD, and setup takes it from there. DISK is an empty qcow2 of 20 GB.

    The machine is what XP has drivers for out of the box: the i440FX PC ("pc": IDE, not AHCI, which XP
    lacks), a Realtek 8139 network card, and a USB tablet beside the PS/2 keyboard, so that the pointer
    goes where the finger or the trackpad does. The clock is local time, as Windows keeps it. No sound
    card: XP has no driver for any of QEMU's that UTM offers, and the simulator stops UTM when a guest
    opens one. One CPU, which is XP's uniprocessor kernel and the gadgets' fastest case.
    """
    vm = base("Windows XP",
              "Windows XP, 32-bit, on the AOK gadget engine. Put your Windows XP installation ISO in the CD "
              "drive, start, and install with the defaults.",
              vm_uuid(8), cpus=1, memory=512)
    vm["System"]["Target"] = "pc"
    vm["System"]["CPUFlagsAdd"] = []
    vm["QEMU"]["RTCLocalTime"] = True
    vm["QEMU"]["PS2Controller"] = True
    vm["Input"]["UsbBusSupport"] = "2.0"
    vm["Information"]["Icon"] = "windows-xp"
    vm["Display"] = [{"Hardware": "VGA", "DynamicResolution": False, "UpscalingFilter": "Linear",
                      "DownscalingFilter": "Linear", "NativeResolution": False}]
    vm["Network"] = [{"Mode": "Emulated", "Hardware": "rtl8139", "MacAddress": mac(8),
                      "IsolateFromHost": False, "PortForward": []}]
    vm["Drive"] = [
        {"ImageName": "windows-xp.qcow2", "ImageType": "Disk", "Interface": "IDE", "InterfaceVersion": 1,
         "Identifier": str(uuid.UUID(int=0xA0C0A0C0_0000_4000_8000_0000000000C8 + A["n"] * 0x100)).upper(),
         "ReadOnly": False},
        {"ImageType": "CD", "Interface": "IDE", "InterfaceVersion": 1,
         "Identifier": str(uuid.UUID(int=0xA0C0A0C0_0000_4000_8000_0000000000D8 + A["n"] * 0x100)).upper(),
         "ReadOnly": True},
    ]
    write(outdir, vm, {"windows-xp.qcow2": disk})


def main():
    outdir, kernel, initramfs, efi_vars = sys.argv[1:5]
    if len(sys.argv) > 5:
        devuan(outdir, sys.argv[5])
    os.makedirs(outdir, exist_ok=True)

    # Fixed UUIDs: copying a rebuilt bundle over an installed one keeps it the same machine to UTM.
    console = base("AOK %s Console" % A["label"],
                   "Alpine 6.18 kernel and the benchmark userland, booted directly. Runs six workloads, then "
                   "leaves a shell on the terminal.",
                   vm_uuid(1), cpus=1, memory=1024)
    console["QEMU"]["AdditionalArguments"] = [
        f'-append "console={A["serial"]} rdinit=/init quiet {"random.trust_cpu=on " if X86 else ""}'
        f'bench={WORKLOADS} then=shell"',
    ]
    console["Serial"] = [terminal()]
    console["Network"] = [] if X86 else [network(mac(1))]
    console["Drive"] = direct_boot(1)
    write(outdir, console, {A["kernel"]: kernel, A["initramfs"]: initramfs})
    if ARCH == "i386" and os.environ.get("XP_DISK"):
        windows_xp(outdir, os.environ["XP_DISK"])
    if ARCH != "riscv64":
        return      # (the display and firmware machines below are the RISC-V study's)

    # console=tty0 last makes the display the console: /init's output and its shell go there, and the
    # kernel's messages to the serial terminal as well.
    shown = base("AOK RISC-V Display",
                 "The Alpine guest with its console on the display (virtio-ramfb) and a USB keyboard.",
                 "A0C0A0C0-0000-4000-8000-000000000003", cpus=2, memory=1024)
    shown["QEMU"]["AdditionalArguments"] = [
        '-append "console=ttyS0 console=tty0 rdinit=/init quiet bench=none then=shell"',
    ]
    shown["QEMU"]["RNGDevice"] = True
    shown["Input"]["UsbBusSupport"] = "3.0"
    shown["Display"] = [display()]
    shown["Network"] = [network("52:54:00:A0:C0:03")]
    shown["Serial"] = [terminal()]
    shown["Drive"] = direct_boot(3)
    write(outdir, shown, {"Image-lts-riscv64": kernel, "initramfs-riscv64.cpio": initramfs})

    # The same machine on UTM's accelerated display device. UTM then starts QEMU with -spice gl=on and,
    # as its settings allow, venus=, neptune= and blob= on the device.
    gl = base("AOK RISC-V Display GL",
              "The Display machine on the GL display device (virtio-ramfb-gl). Needs a QEMU with the GL path.",
              "A0C0A0C0-0000-4000-8000-000000000004", cpus=2, memory=2048)
    gl["QEMU"]["AdditionalArguments"] = list(shown["QEMU"]["AdditionalArguments"])
    gl["QEMU"]["RNGDevice"] = True
    gl["Input"]["UsbBusSupport"] = "3.0"
    gl["Display"] = [dict(display(), Hardware="virtio-ramfb-gl")]
    gl["Network"] = [network("52:54:00:A0:C0:04")]
    gl["Serial"] = [terminal()]
    gl["Drive"] = direct_boot(4)
    write(outdir, gl, {"Image-lts-riscv64": kernel, "initramfs-riscv64.cpio": initramfs})

    uefi = base("AOK RISC-V UEFI",
                "UTM's defaults for a RISC-V virt machine with no disk attached. It ends at the UEFI shell: "
                "attach an installer image to boot something.",
                "A0C0A0C0-0000-4000-8000-000000000002", cpus=2, memory=1024)
    uefi["QEMU"].update({"UEFIBoot": True, "RNGDevice": True})
    uefi["Input"]["UsbBusSupport"] = "3.0"
    uefi["Sharing"]["ClipboardSharing"] = True
    uefi["Display"] = [display()]
    uefi["Network"] = [network("52:54:00:A0:C0:02")]
    uefi["Sound"] = [{"Hardware": "intel-hda"}]
    uefi["Serial"] = [terminal()]
    write(outdir, uefi, {"efi_vars.fd": efi_vars})


if __name__ == "__main__":
    main()
