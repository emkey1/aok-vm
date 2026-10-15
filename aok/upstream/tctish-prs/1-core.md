**Title:** AOK gadgets: a second translator for hosts that cannot JIT (1/4, core)

**Base:** `tctish-edition` · **Head:** `emkey1:pr/aok-core`

---

This series adds a second translator to TCG for AArch64 hosts that may not generate code at run time. A front end turns guest instructions straight into a stream of pointers to precompiled gadgets, **one gadget per guest instruction**, instead of going through TCG ops and TCTI's one dispatch per op. On the same guest programs it takes **1.7 to 3.7 times fewer host cycles than TCTI** in this tree, for RISC-V, AArch64, x86-64 and 32-bit x86 guests, on a Mac and on an iPad alike.

It is off unless configured (`--enable-aok-gadgets`), and `QEMU_AOK=0` turns it off at run time in the same binary. Nothing outside system emulation on an AArch64 host changes.

The series:

1. **this PR**: the core in `accel/tcg` (no guest uses it yet), a TCG fix it exposed, and the design notes
2. RISC-V front end (#…)
3. AArch64 front end (#…)
4. x86-64 and 32-bit x86 front end (#…), with two x86 TCG corrections

Each front end is based on this PR alone and touches no file the others do, so they can be reviewed and merged in any order after it. Until this one is merged, their diffs include its three commits.

## History

**iSH** (Theodore Dubois, 2017) runs x86 Linux programs on iOS, where an app may not generate code. Its answer was threaded code: hand-written AArch64 gadgets, one per guest operation, and a translator that strings their addresses together with their operands. **iSH-AOK** ([emkey1/ish-AOK](https://github.com/emkey1/ish-AOK)), my fork of it, took that engine much further: 64-bit x86, arm64 and riscv64 guests; pairs of gadgets fused into one, chosen from what real programs execute, with the first's result forwarded in a host register; and x87, SSE, AVX and AVX-512 bodies that give the hardware's answers, checked against an AMD Ryzen and Intel's SDE.

This October, users asked whether that engine could run a whole kernel (Linux, FreeDOS, old Windows) on an iPad. A race on identical programs put iSH-AOK's engine at about 3x fewer host cycles than this fork's TCTI, and within 1.5x of QEMU's real JIT. TCTI and iSH dispatch the same way, down to the host register that holds the stream pointer, so the gadgets could live **inside TCG as a second translator** rather than as an accelerator: QEMU keeps the MMU, kernel mode, exceptions, interrupts and devices, and the gadgets do the instructions programs spend their time in. The RISC-V front end came first (2026-10-11), then AArch64 (10-13), then x86-64 and 32-bit x86 (10-13 to 10-15). It is the engine of AOK VM, a fork of UTM SE. The full development history is on [emkey1/qemu `aok-gadgets`](https://github.com/emkey1/qemu/commits/aok-gadgets); this series is the same code, regrouped.

## How it works

A front end sets `TCGCPUOps.aok_translate_code`, and `setjmp_gen_code` offers it each TB before `translate_code`. What it returns is an **ordinary `TranslationBlock`** whose code is a stream: a gadget's address, its operands (mostly byte offsets into the CPU state, so one gadget serves every register), the next gadget. It is found by `tb_lookup`, linked by `tb_add_jump` and invalidated by `tb_phys_invalidate` like any other, and reaches guest memory through the softmmu TLB, with `cputlb.c`'s helpers on a miss.

**A front end translates what it is sure of and stops in front of anything else.** The next TB starts there and is TCG's, raising whatever is due. So a guest runs correctly with a front end that translates nothing, and each instruction class added only makes it faster. Guest registers are always in `env`; nothing is unwound from a stream (a helper that can raise is given the insn's pc first, and called with a zero return address).

Changes to TCG outside the new files are small:

- `setjmp_gen_code` offers the TB; a TB records which translator made it (`TranslationBlock.aok`, in existing padding)
- `cpu_tb_exec` enters a stream through `aok_tb_exec`
- a stream's linked jump is a word the gadget reads, so `tb_set_jmp_target` stores it and leaves the backend's patcher alone
- TCG code and a stream never jump into each other: the main loop links two TBs only when one translator made both, and `helper_lookup_tb_ptr` sends TCG back to the main loop for a stream
- a TB of two pages is never linked to, so the main loop points such a jump at the stream's own lookup stub
- `CPUState.aok_host_fpsr`: host FP flags a front end's gadgets raised, until `TCGCPUOps.aok_fold_fpsr` folds them into the guest's

Shared by all front ends: entering and leaving a stream, jumps between TBs, a TB lookup done in a gadget (both ways of the jump cache, same `cs_base`/`flags`/`cflags`, deferring to C when the CPU has a breakpoint), **fused pairs** (two gadgets that cannot fault, call C or end a TB become one that dispatches once), and a note of which engine runs the machine (`/chosen/aok,engine` in the device tree and fw_cfg `opt/aok/engine`). `docs/devel/aok-gadgets.rst` has the rules a front end must keep.

## A TCG fix this found

The first commit stands on its own. With a thread per guest CPU, `notdirty_write()` invalidates the TBs a store overlaps and only then is the store made, without the page's lock in between, so another CPU can translate the old bytes in that gap and keep them for good. Linux on x86 patches live code with a breakpoint-first sequence that relies on no CPU meeting the breakpoint afterwards; a TB translated in the gap gives `Oops: int3`. TCG seldom loses this race, but it has it: with the gap widened by a few microseconds, TCG alone died in 5 of 6 runs. The fix notes such stores and invalidates their ranges again in the main loop once the store is in memory. After it: 16 of 16 and 100 of 100 where the gadgets had died, 6 of 6 for TCG with the widened gap.

## Benchmarks

Host CPU cycles a program takes under TCTI (`QEMU_AOK=0`, same binary) divided by the cycles under the gadgets. One guest CPU, Alpine 3.24 (its 6.18 kernel and userland), the cycles the QEMU process spends between a program's first line of output and its last, median of two runs. Apple M5 Max under macOS; in brackets, an iPad Pro (M4) running the same engine in an iOS app, where nothing may be generated at run time.

| Workload | RISC-V | AArch64 | x86-64 | 32-bit x86 |
|---|--:|--:|--:|--:|
| CoreMark | 1.91 (1.90) | 3.01 (3.09) | 2.36 (2.30) | 2.66 (2.52) |
| n-body (doubles) | 3.13 (2.77) | 3.54 (3.27) | 1.66 (1.49) | 1.90 (1.67) |
| Python | 3.16 (3.18) | 3.49 (3.69) | 3.17 (3.15) | 3.65 (3.41) |
| xz -3 | 1.66 (1.70) | 2.30 (2.82) | 2.04 (2.44) | 2.35 (2.58) |
| sha256sum | 1.72 (1.75) | 2.43 (2.45) | 1.69 (1.77) | 2.37 (2.34) |
| awk | 2.56 (2.58) | 2.71 (2.96) | 2.41 (2.35) | 3.09 (3.30) |

Machines: `-M virt -cpu rv64`, `-M virt -cpu cortex-a72`, `-M q35 -cpu qemu64,+rdrand`, `-M q35 -cpu qemu32,+rdrand`. Each front-end PR has its absolute numbers.

## Testing

The reference is TCG in the same binary (`QEMU_AOK=0`), or the hardware where TCG is not its equal. For every front end, three guest transcripts are compared: programs whose output must be identical (CoreMark's checksums, Python integer and float arithmetic, xz and gzip, four hashes, sort, awk, shell loops, a hash of every binary in the image); an FP test of each double-precision operation over awkward operands in all four rounding modes, hashing every result with its flags; and a memory test of every access size at every alignment and across pages, with pointer walks over pages that fault and are restarted. All identical with one guest CPU and four, with pairs, without, and without forwarding. The front-end PRs list their own tests.

Built and tested on Apple silicon: macOS (M5 Max) and iPadOS (M4, A10X), with TCTI. Other hosts and backends are untested. This branch builds with `--enable-werror` alone and with each front end.

## Provenance, licence, AI assistance

- Gadget sources taken from iSH-AOK sit in each front end's `shared/` (and x86's `vec/`) with a `SOURCE` file naming their origin. All of them are my own contributions to iSH-AOK after its commit 0e3a4144, which iSH-AOK licenses as GPLv2 as well as GPLv3 for exactly this reason; they are marked `GPL-2.0-only OR GPL-3.0-only`. None of upstream iSH's own lines are among them, and none of the arm64 code iSH-AOK adapted from OpenMinis/ish-arm64 (GPLv3) is.
- Most of this series was written by Claude (Anthropic's Claude Code, Opus 5.5) working under my direction; each commit says so with `Assisted-by:`. QEMU mainline's `docs/devel/code-provenance.rst` declines such contributions. That is why this goes to this fork rather than to mainline; if this fork follows mainline's policy, tell me and I'll close the series.

## Trying it

```
./configure --target-list=riscv64-softmmu,aarch64-softmmu,x86_64-softmmu \
    --enable-tcg-threaded-interpreter --enable-aok-gadgets
```

With a front end merged, `QEMU_AOK_STATS=1` prints at exit how many TBs each translator made; `QEMU_AOK=0` is the reference.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
