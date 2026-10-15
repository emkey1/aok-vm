**Title:** AOK gadgets: RISC-V front end (2/4)

**Base:** `tctish-edition` · **Head:** `emkey1:pr/aok-riscv` · **Depends on** #… (core); only the last commit is this PR's own.

---

`target/riscv/tcg/aok`: a front end for the AOK gadget translator (see #… for what that is). RV64 guests with C.

**Translated:** the integer base, M, A, Zba, Zbb, Zbs and Zicond, loads and stores, branches, `jal` and `jalr`, CSR accesses, F and D. **Left to TCG:** `ecall`, `ebreak`, `sret`, `mret`, `wfi`, fences other than `fence`, vectors, and every extension not listed. A TB is translated only for little-endian RV64 with C, not virtualized, with no pointer masking, CFI or instruction-count trigger, and stays within its page.

## How

- **Operands** are offsets into `CPURISCVState`. `x0` is two new slots, `aok_zero` (read, never written) and `aok_sink` (written, never read), so a gadget takes register 0 like any other.
- **Atomics and CSR accesses** are one call to C each, doing what `trans_rva.c.inc` and `trans_csr*` generate with the same helpers. A CSR access ends its TB in the main loop, as with TCG.
- **F and D:** loads and stores are the integer gadgets on an FP register's offset (`flw` with the NaN box). Double-precision arithmetic, fused multiply-adds, compares and integer conversions run on the **host's FP unit** when `frm` is round-to-nearest and the host gives softfloat's answer, flags included: a NaN result becomes RISC-V's canonical NaN, and anything that could have underflowed goes to softfloat, since AArch64 detects tininess before rounding and RISC-V after (`gadgets.S` lists every case). Single precision, other rounding modes and the rarer operations are softfloat's, called from the stream.
- **From iSH-AOK:** the integer gadgets, loads, stores, branches and direct jumps, and its table of 535 fused pairs (`shared/`, with `SOURCE`), built against this tree's host definitions in `gadgets-shared.S` (the softmmu fast path; a copy of the TB exit for each way out of a block). `jalr` is this tree's own, ending in the shared TB lookup.
- The `virt` machine says which engine runs it in its device tree.

## Benchmarks

Host CPU cycles, Alpine 3.24 on `-M virt -cpu rv64`, one guest CPU, between a program's first line of output and its last, median of two runs. Apple M5 Max; the last two columns are the same ratio on an iPad Pro (M4, two runs) and a 2017 iPad Pro (A10X, four runs, all on its performance cores).

| Workload | TCTI | AOK gadgets | TCTI / AOK | M4 | A10X |
|---|--:|--:|--:|--:|--:|
| CoreMark | 11.7 G | 6.1 G | 1.91 | 1.90 | 1.62 |
| n-body (doubles) | 10.1 G | 3.2 G | 3.13 | 2.77 | 2.17 |
| Python | 32.5 G | 10.3 G | 3.16 | 3.18 | 2.53 |
| xz -3 | 8.5 G | 5.1 G | 1.66 | 1.70 | 1.64 |
| sha256sum | 5.1 G | 2.9 G | 1.72 | 1.75 | 1.52 |
| awk | 11.5 G | 4.5 G | 2.56 | 2.58 | 2.52 |

Fused pairs alone (iSH-AOK's first table, 332 pairs, M5 Max, five interleaved runs): CoreMark 1.08x, Python 1.10x, xz 1.14x, sha256sum 1.09x, awk 1.08x, n-body 1.04x. In a boot and those programs, 220,000 pairs fused out of 697,000 translated instructions.

## Testing

The program, FP and memory transcripts (#…, "Testing") are identical to `QEMU_AOK=0` with one guest CPU and four, with pairs, without (`QEMU_AOK_NO_PAIRS=1`) and without forwarding (`QEMU_AOK_NO_FWD=1`). Builds with `--enable-werror`; boots and runs CoreMark under both engines.

`docs/devel/aok-gadgets-riscv.rst` has the details and the switches (`QEMU_AOK_NO_CSR`, `_NO_ATOMIC`, `_NO_FP`, `_NO_FPNATIVE` leave a class to TCG, for bisecting).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
