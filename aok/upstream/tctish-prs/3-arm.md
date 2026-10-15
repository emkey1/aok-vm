**Title:** AOK gadgets: AArch64 front end (3/4)

**Base:** `tctish-edition` · **Head:** `emkey1:pr/aok-arm` · **Depends on** #… (core); only the last commit is this PR's own.

---

`target/arm/tcg/aok`: a front end for the AOK gadget translator (see #…) for A64 code. Here the guest's instruction set is the host's, so an instruction is most often the same instruction with its registers read from `env` and written back.

**Translated:** data processing with immediates and registers (all but the tagged, pointer-authentication, CRC and CSSC instructions), conditional selects and compares, loads and stores of X and W registers in every addressing mode, pairs, literals, the unprivileged and ordered ones, exclusives, direct, conditional and indirect branches, the hint space, barriers, system register accesses, `msr daifset`/`daifclr`, `svc` and `eret`; the base architecture's FP and Advanced SIMD, with AES, SHA-1, SHA-256, PMULL and CRC32 where guest and host both have them. **Left to TCG:** other exceptions, LSE atomics, SVE, SME, and with LSE2 the exclusives and ordered accesses. A TB is translated only in AArch64 state, little-endian, 4 KiB pages, with no single-step, alignment checking, MTE, GCS, nested virtualization or pending branch-target check; with BTI, indirect branches are TCG's.

## How

- **XZR** is two new slots after `pc` in `CPUARMState`, `aok_zero` and `aok_sink`, so register 31 is like any other and the translator picks SP or one of those by operand.
- **Flags** are QEMU's four words. A gadget that reads them right after one that set them uses the host's NZCV (the `_nf` variants).
- **Faults** in a load or store are raised from C with the insn's pc and the syndrome template `translate-a64.c` would have left in the insn start words.
- **System registers, exclusives, `svc`, `eret`** are one call to C each, doing what `handle_sys()` and the `trans_*` functions generate with the same helpers. The `ARMCPRegInfo` is looked up at run time, since a TB is every CPU's. A write ends the TB in the main loop, as with TCG.
- **FP and SIMD:** `gadgets-simd.S` holds every encoding of the class assembled on fixed registers, as a two-instruction thunk in tables indexed by the non-register bits; a gadget loads the registers, calls the thunk and stores the result. The translator decides only whether an encoding exists for the guest CPU. The host's FPCR is the guest's while these run (rounding mode, FZ, DN) and its FPSR collects the flags and QC. The first time any CPU's FPCR gets another bit (AH, FZ16, the AFP modes), FP becomes TCG's for good and every TB is flushed (`arm_aok_fpcr_changed()`, called from `vfp_set_fpcr_masked()`). FP is also TCG's while it traps, in streaming mode, and with SVE vectors longer than 128 bits.
- **`ld1`/`st1`** of whole registers are gadgets; interleaved, single-lane and replicating structure accesses are a call to C.
- **From iSH-AOK:** the operand-specialised integer gadgets, the bodies of loads, stores, pairs and branches, and its table of 592 fused pairs (`shared/`, with `SOURCE`), built against this tree's host definitions in `gadgets-shared.S`. A `cmp` and the `b.cond` after it are one gadget. `br`, `blr` and `ret` are this tree's own bodies under iSH-AOK's names (TBI and the TB lookup). None of this is the arm64 code iSH-AOK adapted from OpenMinis/ish-arm64.
- The `virt` machine says which engine runs it in its device tree.

## Benchmarks

Host CPU cycles, Alpine 3.24 on `-M virt -cpu cortex-a72`, one guest CPU, median of two runs. Apple M5 Max; last column the same ratio on an iPad Pro (M4).

| Workload | TCTI | AOK gadgets | TCTI / AOK | M4 |
|---|--:|--:|--:|--:|
| CoreMark | 10.7 G | 3.6 G | 3.01 | 3.09 |
| n-body (doubles) | 10.8 G | 3.0 G | 3.54 | 3.27 |
| Python | 31.3 G | 9.0 G | 3.49 | 3.69 |
| xz -3 | 10.1 G | 4.4 G | 2.30 | 2.82 |
| sha256sum | 4.6 G | 1.9 G | 2.43 | 2.45 |
| awk | 10.8 G | 4.0 G | 2.71 | 2.96 |

Fused pairs, forwarding and compare-and-branch against none of them: CoreMark 1.16x, Python 1.08x, xz 1.08x, awk 1.04x, sha256sum 1.03x on the M5 Max (best of three, interleaved); 1.15x, 1.07x, 1.05x, 1.05x, 1.11x on the M4.

## Testing

The three transcripts (#…, "Testing") are identical to `QEMU_AOK=0` with one guest CPU and four. **simdtest** runs every encoding of the scalar FP and Advanced SIMD data-processing space (560,640, on fixed registers) over four input sets, one with another rounding mode, flush-to-zero and default NaN, hashing result, flags and FPSR; an encoding that does not exist hashes as SIGILL, so it checks which instructions a guest CPU has as well as what each computes. Its reference is TCG with a JIT backend (QEMU 11.0.3, `cortex-a72`): identical. TCTI is not a reference there: it differs from the JIT, from the gadgets and from hardware (the same guest under HVF) in `cmlt #0`/`cmle #0` on 8-, 16- and 32-bit lanes and in `sshl` on 16- and 32-bit lanes. All pass under UTM's machine options (`virt,virtualization=on,gic-version=3`) and with `-cpu max`. Builds with `--enable-werror`; boots and runs CoreMark under both engines.

`docs/devel/aok-gadgets-arm.rst` has the details and switches (`QEMU_AOK_NO_SYS`, `_NO_EXC`, `_NO_ATOMIC`, `_NO_FP`, `_NO_FUSE`).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
