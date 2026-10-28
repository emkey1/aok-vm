# ReactOS for AOK VM

"ReactOS.utm" is ReactOS 0.4.16 (a free operating system that runs Windows
programs and drivers), already installed: it starts to a desktop at 1024x768,
logged in as Administrator, with its network card working, on the AOK gadget
engine's 32-bit PC. It stands in for Windows XP, which cannot be shipped.

`build.sh` makes its disk from the release CD with no one at the keyboard; the
script's header says what each step does. On MBP5:

```bash
bash aok/reactos/build.sh ~/aok-vm-bench/reactos-build
```

Then the bundle, beside the 32-bit console machine:

```bash
ARCH=i386 REACTOS_DISK=~/aok-vm-bench/reactos-build/reactos.qcow2 python3 aok/app/make-vm.py OUTDIR KERNEL INITRAMFS EFI_VARS
```

## What is worth knowing

- **The machine is UTM's, exactly.** `ros-run.sh` is the QEMU command line
  UTM builds for ReactOS.utm (taken from the bundle's `Data/debug.log`), less
  SPICE. ReactOS remembers devices by where they are, so an install on any
  other machine meets new hardware on its first start in the app: the first
  install here, on QEMU's defaults, had no guest agent port, and the app then
  asked about a "Communication device".
- **Two devices have no driver**, and the New Hardware Wizard asks about
  each: QEMU's firmware configuration device (ACPI `QEMU0002`, "Other ACPI
  device") and UTM's guest agent port (virtio-serial, PCI 1af4:1003,
  "Communication device"), which UTM adds to every x86 machine with no
  setting to leave it out. A device is asked about once, answered or not;
  `build.sh` answers what the second start asks ("Do not show this dialog
  anymore") and checks on a third that nothing is asked or tried.
- **At the first logon the wizard can be behind the shell**: on the screen,
  its title bar grey, and keys sent to it go to the desktop. On later starts
  it has the keyboard.
- **Text-mode setup reads `i386/unattend.inf`**, not `reactos/unattend.inf`
  (that one is the live system's graphical installer's). With it in the wrong
  place, setup stops at its first question, the language.
- **The steps are watched on the screen.** Homebrew's QEMU dumps the screen
  through the monitor; `screen.py` knows the wizard by its flat blue panel.
  The AOK engine's QEMU has no screen dump (and no user-mode network:
  `ROS_NONET=1`), so it runs the finished disk, not the install. Pointer
  clicks sent through the monitor do not land where they are aimed (the
  tablet's scaling); keys do.
- **The time zone is GMT and the clock is local time**, as Windows keeps it:
  the desktop shows the host's local time.

## Timing and profiling it

`ros-stats.sh TAG` boots the finished disk (an overlay: the disk itself is
left as it was) on MBP5 to its desktop with `QEMU_AOK_STATS=2`, and gives the
time to explorer's desktop from the guest's debug output, QEMU's CPU time,
and the engine's statistics: what went back to TCG, by opcode
(`../x64/classify.py OUT 40 32`), and the writes to pages with code.
`ros-prof.sh TAG [SECONDS]` samples the host over the boot (or, with
`PHASE=kernel`, from the kernel's first line); `../vcpu-profile.py` splits
the vCPU thread's samples by what they were doing. Both take `QEMU=` for another build, and extra arguments as
QEMU's environment (`QEMU_AOK=0` for TCTI alone). `ros-halt.sh TAG` asks the
monitor every 20 ms whether the vCPU is halted and where it is, on the same
timeline as the guest's debug output; `ros-dis.sh TAG ADDR...` disassembles
guest addresses (such EIPs) once the desktop is up. `ROS_NOUSB=1` before any
of them leaves out the USB controller and tablet (an experiment only).

On a device, `ros-device.sh DEVICE NAME TAG` times a machine whose serial
port is a TCP server on port 4555 (COM1, which build.sh's install already
knew, so no new hardware): it starts the machine with `../app/start-vm.sh`,
reads the guest's debug output over the cable with `nc -d` (without `-d`, nc
closes its side at the end of its input and QEMU stops sending), and stops
at the same line as `ros-stats.sh`. Its times run from the app's launch, so
they include the app's start (about 1.5 s to the port). Python cannot be
the network side: macOS's local network privacy keeps it off the link.

Where the guest prints nothing, `ros-shots.sh` takes screenshots in two
staggered loops (each takes 2.3 to 3.2 s) and `ros-desk.py REF DIR` gives
each one's difference from a picture of the desktop. The first within 2.0
came 0.10 and 0.25 s before the debug output's desktop line in two runs
that had both.

### The M4 iPad Pro, 2026-10-28

Seconds from the launch to explorer's desktop, `ReactOS Timing` machines
(build.sh's disk, a serial port added), one CPU; the engine at aok/ENGINE
11adf734f6 (the code bitmap 1af7747dfa and the compressed-cluster cache
bdcb2b3f6b) against build 11's (8d8b2b621c):

| | gadgets | TCTI alone |
|---|---|---|
| build 11 | 15.2, 16.4 (screenshots) | 26.29, 25.68 |
| 11adf734f6 | 12.72 to 13.24 (7 runs) | 20.35, 20.90 |

A fresh disk and one booted before take the same time (12.97 and 12.72,
13.24). The kernel's first line comes at 3.2 to 3.7 s now and at 5.8 to 6.2
s on build 11: SeaBIOS's and the boot loader's writes beside their code, as
on the Mac. So the iPad gains as MBP5 did: about a fifth (TCTI 21%, the
gadgets about 19%), and the gadgets are 1.6 times TCTI. From the kernel's
first line the M4 takes about 9.6 s, MBP5 8.4 s.

**Build 11's gadgets print nothing on COM1.** Under build 11 with the
gadgets, ReactOS reaches its desktop but writes no debug output at all; with
`QEMU_AOK=0`, and with the new engine either way, the same machine writes
its 25 KB. So that build's gadget engine ran some of ReactOS's kernel
debugger set-up differently from TCG. Which commit since 8d8b2b621c changed
it is not known (aok/TODO.md).

### Where the boot's time goes now (MBP5, 11adf734f6, 2026-10-28)

The desktop at 9.81 to 9.89 s (5 runs), the kernel's first line at 1.37 s.

**A quarter of it is ReactOS waiting.** The vCPU is halted in 22 to 24% of
`ros-halt.sh`'s polls, about 2.2 s, with every QEMU thread idle: the guest's
own timers. Most of it is one stretch, 2.5 to 3.7 s (94 to 100% halted), between
the USB root hub's pipes opening and the tablet's: ReactOS's USB hub driver
sleeps a second before its first enumeration (`drivers/usb/usbhub/pnp.c`,
USBH_FdoQueryBusRelations, "FIXME: this delay makes devices discovery during
early boot more reliable"), then 100 ms, then resets the port. The M4's runs
have the same 1.22 s between those two lines on every engine (gadgets, TCTI,
build 11). Without the controller and tablet (`ROS_NOUSB=1`) the desktop
comes at 8.29 to 8.61 s (4 runs, interleaved with the 9.81 to 9.89) with the
same CPU time (7.6 to 7.9 s): the tablet costs about 1.4 s, all of it
waiting, about a ninth of the M4's 12.9 s. It cannot just go: the tablet is
the absolute pointer that touch needs.

**Some of the busy time is waiting too.** Of 205 busy polls in the kernel
phase, the HAL's calibrated stall loop (`sub eax, 1; jne`,
KeStallExecutionProcessor: fixed microseconds, so more turns on a faster
engine) has 13, reads of the PIT's counter (`out 43h`, `in 40h` twice) 9,
the idle loop's spin (`sti; pause; pause; cli`) 6, and `rep movs` (a
memory copy) 5.

**The engine's own costs**, as shares of the kernel phase's busy samples
(`ros-prof.sh`, `PHASE=kernel`, 8 s, 34% of them halted):

| | |
|---|---|
| gadgets | 67% |
| `rep` and other string insns in C (`aok_x86_helper_string`, element by element through the soft TLB for lods, cmps, scas and the unrepeated forms) | 4.7% |
| the jump-cache probe (`aok_x86_lookup_pc`, a gadget) | 4% |
| jump-cache misses (`tb_lookup_slow`, `qht`) and the cache's flush on every CR3 write | 4.3% |
| stores to pages with code (7.0 M, 6.99 M of them beside it) | 3% |
| TLB fills | 2.8% |
| the main loop | 1.8% |
| translation | 1.7% |
| device I/O | 1.4% |

Over the whole boot, device I/O is 10%: the firmware's and boot loader's
disk reads by PIO (`in` through TCG's helper) and, on these timing machines
only, COM1's debug output (a host write per byte).
