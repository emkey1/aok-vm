# AOK VM 1.0 (release candidate 1)
## Highlights
* **The AOK gadget engine**: RISC-V, ARM64, x86-64 and 32-bit x86 machines run on iSH-AOK's gadget engine inside QEMU, between 1.6 and 3.6 times faster than QEMU's own engine in our benchmarks, with x87 floating point that gives the hardware's answers.
* **Machines ready to run**: iSH-AOK's own Alpine and Devuan root file systems, as machines of their own, and ReactOS come with the app. The same Alpine and Devuan for x86_64, x86 and riscv64 are under + and Get a Ready-Made Machine. Each is small; `aok-update` and the scripts in /AOK/tools add a desktop and the rest when you want them.
* **iSH-AOK's /AOK/persist**: a machine can share iSH-AOK's /AOK/persist (its settings, Sharing), so iSH-AOK and the machine see the same files.
## Also
* AOK VM is a fork of UTM, made by the iSH-AOK project: please report its problems to AOK VM, not to UTM's developers.
* `aokvm://downloadVM?url=` links add a machine from a zip.
* Machines no longer show as unavailable after the app's data moves (a restore, a new device).
