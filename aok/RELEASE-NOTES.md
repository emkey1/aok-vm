# AOK VM 1.0 (release candidate 4)
## New in build 11
* **A crash with a terminal machine**: the app could crash when a machine shown in a terminal started running just as its window was being closed or the app was going to the background (seen on an iPhone 11 with build 10).
## New in build 10
* **32-bit x86 Linux starts again**: build 9's default CPU offers AVX-512, and a 32-bit Linux kernel that uses it (TinyCore 17's, in its checksum code) stopped early in its boot with "invalid opcode": the gadget engine ran AVX-512 only in 64-bit code. It now runs AVX-512 and the rest of AVX in 32-bit code too, and an AVX-512 instruction that straddles two pages of code no longer stops a 32-bit program. (TinyCore's CD starts with UEFI off: it has no UEFI loader.)
* **Processor corrections from iSH-AOK's processor tests**, now run against each machine type and checked against real hardware:
  * x86: the x87's environment and its deferred exception; BSF/BSR of zero keeping the whole register; IRET and far returns in 64-bit code; branches to a non-canonical address faulting where hardware faults; the BCD instructions' flags; LAR, INVD/WBINVD, CLFLUSH and MMX/x87 sharing; and the 0x67 prefix on vector instructions.
  * A memory access that straddled two pages could write to the wrong page.
  * Every machine type: some vector comparisons (less-than and less-or-equal) in the TCTI fallback engine gave the opposite answer when the two values were equal.
## New in build 9
* **x86-64 machines boot faster**: a machine whose CPU is left at "Default" now gets the gadget engine's own CPU (QEMU's max, without LA57, as AOK VM's ready-made machines have), not Skylake-Client, which made Linux switch on its Meltdown and MDS defences: a page-table switch and a buffer clear on every system call. The Arch Linux ISO boots 20% faster. A Windows machine may notice the new processor once.
* **x86 machines use several cores at once**: an x86-64 or 32-bit x86 machine left at the default number of cores now gets as many as the device has performance cores, and they run in parallel, where it had one; a machine with a number of cores set now runs them in parallel instead of taking turns on one. Four programs at once ran 2.5 to 3.7 times faster on four cores than on one.
* **PowerPC Macs on the gadget engine**: the PowerPC machines (mac99, g3beige) run on the gadget engine, like the x86, ARM64 and RISC-V ones, instead of only the threaded interpreter: CoreMark 2.75 times and sha256 2 times faster on an M4 iPad Pro, floating point and all, with the same results.
* **Faster encryption on x86-64**: the ADX instructions that OpenSSL and GnuPG use for RSA run on the gadget engine (RSA signing about 2.7 times faster), and OpenSSL's AVX-512 code no longer stops with "illegal instruction" on a machine with the max CPU.
* **Memory near the end of a page**: on every machine the threaded interpreter runs (PowerPC and 68k throughout, the others where the gadget engine hands over), a load or store in the last few bytes of a memory page could read or write another page instead, at random and more often when the device was busy. Fixed.
## New in build 8
* **PowerPC and 68k Macs on the newer engine**: the PowerPC (mac99, g3beige, and 64-bit) and 68k (Quadra 800) machines now run on the same QEMU as every other machine here (tctiSH's, with its threaded interpreter), in place of the older QEMU they had: 1.4 to 2.2 times faster on PowerPC and 1.1 to 2.1 times on 68k in our benchmarks. PowerPC Macs keep the Screamer sound device that Mac OS 9 expects.
* **CDs and removable disks**: a machine that started with an ISO, or had a disc, disk or floppy put in later, stopped with "Parameter 'file-locking-mode' is unexpected".
* **A TPM on ARM64 and RISC-V machines**: a "virt" machine with its TPM on no longer refuses to start.
* A 68k Mac with no display in its settings no longer crashes the app when it starts: the Quadra 800 always has its built-in screen, which the app now shows as Display 0.
* Crash reports and system notices name the app AOK VM, not UTM SE.
## In build 6
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
