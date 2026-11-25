# RCG for AArch64 guests on tctiSH/qemu: how the PRs were tested

The plan is the 2026-11-13 comment on tctiSH/qemu#6, with the maintainer's answers of 2026-11-17. The work
is in `~/git/qemu-rcg-a64` (a worktree of `~/git/qemu-rcg-te`), on top of tctish-edition fcf9d302d6.

| PR | Branch (emkey1/qemu) | What |
|---|---|---|
| 1, tctiSH/qemu#11 | `rcg-core-split` | `tcg/aarch64-tcti/rcg_core.py`: what the generators share |
| 2 | `rcg-a64-skeleton` | the shared C helpers; the A64 generator, decoder, translator and test, ADD and SUB only |

`scripts.txt` holds every script, each under a `==> path` line.

## PR 1: nothing generated changes
- `split.py` builds both files from the original by line number, so moved code is verbatim.
- `gen.sh DIR` writes every output of x86's generator; the SHA lists before and after are equal (22 gadget
  files, the table, four test-case files).
- `cov.sh` runs `--coverage` over made-up listings and traces with both generators: same lines, same exits.
- `m4-split.sh`: a hybrid build on the M4, the build's gadget sources against the unpatched generator's, and
  that touching `rcg_core.py` regenerates.

## PR 2: RCG must give what TCG gives
- Kernels come from camd, which has `aarch64-linux-gnu-gcc` and a native gcc: `k/build.sh` (aarch64
  `rcg-insns`) and `x/build.sh` (x86 `rcg-insns` and `rcg-faults`). Neither Mac has a cross compiler.
- `m4-a64.sh [fresh]` applies `a64.diff` (`git diff fcf9d302d6 HEAD`) to `~/aok-vm-bench/src-a64` and
  builds both targets as CI configures them.
- `m4-a64-test.sh`: `rcg-insns` under the JIT, TCTI, and RCG ordered and plain, on `-cpu max` and
  cortex-a72, then `--coverage`. `rcg-insns.ref` is TCTI's output with `rcg=off`.
- `m4-a64-ctl.sh cf vf zf nf imm` with `ctl-edit.py`: positive controls. **A control must break only gadgets
  the test program's own code does not run.** Breaking a flag in every gadget hangs or kills the guest
  before it prints a line, which a diff then reads as "0 cases differ". The controls break the forms shifted
  by ASR, or one operand value.
- `m4-x86-test.sh`: x86's own tests, since two of its C functions and a trace event moved.
- `alp/run.sh`: AOK VM's Alpine aarch64 machine (copied from MBP5) booted with RCG off and on; a fixed set
  of commands must print the same.
- `sizeof(DisasContext)` for the build check came from a `_Static_assert(... == 0)` probe: clang prints the
  value.
- checkpatch learns a function's parameter types only when the function follows a finished statement. One
  that follows `TRANS(...)` lines trips "spaces required around that '*'" on its `arg_*` parameter, which
  fails their CI: keep the `TRANS` lines after the functions.

Results as committed (1a8abb6276): all matches, 120 of 120 gadgets taken, controls change 64, 56, 64, 60 and
192 cases as accounted for in the commit message, x86 9692 of 9692 and 0 of 225283 fault checks failed.
