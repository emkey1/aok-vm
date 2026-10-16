# AOK VM 1.0 (release candidate 3)
## New in build 6
* **A smaller app**: 32-bit PC machines run on the x86-64 engine, as they already did, without a second copy of it; Devuan for ARM64 is now a download (+, then Get a Ready-Made Machine), like the other Devuan machines; and the firmware for machines AOK VM has no engine for (LoongArch, 32-bit ARM) and the Secure Boot firmware for ARM64 are gone.
* An ARM64 machine with a TPM boots the regular UEFI firmware, without enforcing Secure Boot.
* The engine has the newest changes of the QEMU it is built on (tctiSH's).
## In build 5
* **AVX-512 on x86-64 machines**: AVX-512 (F, DQ, CD, BW, VL, IFMA, VBMI, VBMI2, VNNI, BITALG, VPOPCNTDQ, BF16), GFNI, VAES, VPCLMULQDQ and AVX-VNNI, computed by the gadget engine and checked against Intel's emulator. A machine has them with its CPU set to "max" (its settings, System; leave the la57 flag off); QEMU's own engine has none of them.
* **x86 floating point gives the hardware's answers**: SSE's arithmetic, compares and conversions now match an x86 processor bit for bit, where QEMU's own engine differs (which NaN an operation returns, among others), and SSSE3 and SSE4.1 run on the gadget engine too.
* **Faster machines**: what a Linux kernel does most (system calls, returns from interrupts, context switches, bit operations, 128-bit compare-exchange) runs on the gadget engine instead of QEMU's, and the ARM64 engine fuses pairs of instructions (5 to 20% faster on an M4 and an A10X).
* Debuggers can single-step AVX-512 code in a machine.

## Highlights
* **The AOK gadget engine**: RISC-V, ARM64, x86-64 and 32-bit x86 machines run on iSH-AOK's gadget engine inside QEMU, between 1.6 and 3.6 times faster than QEMU's own engine in our benchmarks, with x87 floating point that gives the hardware's answers.
* **Machines ready to run**: iSH-AOK's own Alpine and Devuan root file systems, as machines of their own, and ReactOS. Alpine for ARM64 and ReactOS come with the app; Devuan for ARM64, and Alpine and Devuan for x86_64, x86 and riscv64, are under + and Get a Ready-Made Machine. Each is small; `aok-update` and the scripts in /AOK/tools add a desktop and the rest when you want them.
* **iSH-AOK's /AOK/persist**: a machine can share iSH-AOK's /AOK/persist (its settings, Sharing), so iSH-AOK and the machine see the same files.
## Also
* AOK VM is a fork of UTM, made by the iSH-AOK project: please report its problems to AOK VM, not to UTM's developers.
* `aokvm://downloadVM?url=` links add a machine from a zip.
* Machines no longer show as unavailable after the app's data moves (a restore, a new device).
