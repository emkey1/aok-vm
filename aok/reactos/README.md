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
QEMU's environment (`QEMU_AOK=0` for TCTI alone).
