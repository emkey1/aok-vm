# AOK VM's base machines

The machines AOK VM ships and offers are iSH-AOK's own root file systems, as
machines of their own: Alpine 3.24.2 and Devuan 6, for aarch64, x86_64, x86
(i386) and riscv64, the same OS and architecture combinations iSH-AOK has.
Small on purpose: what else someone wants (a desktop, games, the "ultimate"
tool set) is iSH-AOK's scripts in `/AOK/tools`, run in the machine.

| Machine | Bundle | Zipped |
|---|---|---|
| Alpine 3.24.2 (aarch64) | 41 MB | 40 MB |
| Alpine 3.24.2 (x86_64) | 50 MB | 48 MB |
| Alpine 3.24.2 (x86) | 32 MB | 30 MB |
| Alpine 3.24.2 (riscv64) | 41 MB | 26 MB |
| Devuan 6 (aarch64) | 95 MB | 97 MB |
| Devuan 6 (x86_64) | 105 MB | 113 MB |
| Devuan 6 (x86) | 88 MB | 99 MB |
| Devuan 6 (riscv64) | 95 MB | 80 MB |

```bash
bash aok/images/build.sh
```

on MBP5 makes all eight (or those named, e.g. `devuan-aarch64`) in
`~/aok-vm-bench/images/machines`, each as `NAME.utm` and `NAME.zip`, in about
ten minutes. Its header says what it needs.

## In the app

`index.py ZIPDIR` writes `machines.json` (name, line, zip, size, SHA-256 of
each), which the app carries with the zips of three machines: Alpine and
Devuan for aarch64, and ReactOS. The Xcode build's "Copy AOK VM machines"
phase copies them from `aok/images/bundled/` (not in git: copy them there
from `build.sh`'s `zips/` and aok/reactos's, as `alpine-3.24.2-aarch64.zip`,
`devuan-6-aarch64.zip`, `reactos-0.4.16.zip`). On its first start the app adds
those three to the list (`Platform/Shared/AOKMachines.swift`, each once: one
its user removes stays removed). "+" -> "Get a Ready-Made Machine..." lists all
nine; the six it does not carry are downloaded from the list's `baseURL`,
checked against their SHA-256, and a newer list is fetched from `indexURL`.
A machine added from the list gets no more memory than the device has room
for (`UTMDownloadVMTask.fitMemory`: UTM's own estimate, under 90% of what iOS
gives the app; 512 MB on a 2 GB device).

## A machine

- **The root disk** is the archive iSH-AOK ships for that OS and
  architecture, unchanged, plus the kernel's modules, `/AOK/tools` (the
  scripts `aok-update` brings), `aok-update`, `/AOK/persist`, and a few
  files that let it start by itself (`job.sh`): `/etc/fstab` (the root, and
  `/AOK/persist` when the machine is given it), the host name, root logged in
  on the serial terminal too, and for Alpine a busybox `inittab` with
  `boot`/`stop` scripts (`alpine/`), because iSH-AOK's Alpine has no OpenRC.
  An 8 GB qcow2 that grows as it fills.
- **The kernel** is Alpine's (linux-virt; linux-lts on riscv64), for both
  distributions, booted directly by UTM.
- **The initramfs** (`init`) loads the disk's drivers, mounts the root,
  loads every other driver the machine's devices want from the root's own
  modules, and takes an address by DHCP. Devuan's root has neither
  `modprobe` nor a DHCP client, so this is where both happen, for either
  distribution. What it did is in `/var/log/aok-init.log`.
- **The machine** (`machine.py`): two CPUs, 1 GB, a display with a USB
  keyboard and tablet, a serial terminal, a VirtIO network card, disk and
  random number source, and Sharing's "Share /AOK/persist" on.

## Checked (2026-10-14)

All eight under Homebrew's QEMU on MBP5 (aarch64 on HVF, the rest emulated):
root logged in on the serial port, the address taken, `apk add` or
`apt-get install` from the network, `/AOK/persist` mounted with the host's
files, a clean power-off. Alpine aarch64 also in the simulator on the AOK
engine, through the app.

Worth knowing: unpacking anything with a `lib/` into Devuan's root needs
`--keep-directory-symlink`, or GNU tar replaces its `/lib -> usr/lib` link
with a directory and every program loses its dynamic loader
(`switch_root: can't execute '/sbin/init'`).
