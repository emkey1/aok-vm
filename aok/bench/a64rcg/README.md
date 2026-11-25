# RCG for AArch64 guests on tctiSH/qemu: how the PRs were tested

The plan is the 2026-11-13 comment on tctiSH/qemu#6, with the maintainer's answers of 2026-11-17. The work
is in `~/git/qemu-rcg-a64` (a worktree of `~/git/qemu-rcg-te`), on top of tctish-edition fcf9d302d6.

| PR | Branch (emkey1/qemu) | What |
|---|---|---|
| 1, tctiSH/qemu#11 | `rcg-core-split` | `tcg/aarch64-tcti/rcg_core.py`: what the generators share |
| 2 | `rcg-a64-skeleton` | the shared C helpers; the A64 generator, decoder, translator and test, ADD and SUB only |
| 3 | `rcg-a64-integer` | the rest of the integer data processing between registers: 376 gadgets, 4477 cases |
| 4 | `rcg-a64-cond` | the conditional selects, compares and branches, and compare joined to branch: 1032 gadgets, 6012 cases |

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

## PR 3: the same recipe, wider
- `m4-a64-ctl2.sh` with `ctl2-patch.py`: one control per kind of gadget. The patch adds hooks to the M4's copy
  of the generator only, and `RCG_CTL` in ninja's environment picks the break. `res:KIND` flips the result
  when the first source holds 0x0123456789abcdef, one of the test's values, so the test program's own code is
  spared. MOV is left out of `res:logic_r`: the test program moves every value with it.
- **Count changed cases line by line** (`paste` and `awk`), never with `diff | grep -c '^<'`: over 4477 lines
  with hundreds changed, diff reported five or six unchanged lines as changed, and an hour went on a bug that
  was not there. PR 2's counts were rechecked this way and hold.
- The test runs every case through one function, `rcg_run_insn()`, with the case's instruction patched into
  it. A function per case would not fit the 2 MiB that kernel.ld gives the text. The label the C code patches
  must be `.global`: a local one reached through the GOT lost its offset and the patch landed on the
  function's first instruction.
- ADR and ADRP results are hashed as distances from the slot, or the reference would depend on the link.

## PR 4: conditions and branches
- A case is now up to three instructions (`RCG_SLOT`): a branch goes forward over `movz x16, #0xbad`, which
  marks the way not taken, and a setter comes before its B.cond. Cases that read NZCV start from all 16 values.
- TCTI swaps the jumps gadget in wherever both ways out start with a goto_tb, so with chaining only those
  run. `rcg-branch` is the branch cases under `-d nochain`, where the gadgets that only branch run;
  `m4-a64-test.sh` runs it and compares with the reference's lines for those cases, as the Makefile does.
- `m4-a64-ctl3.sh` with `ctl3-patch.py`: a kind's gadgets take their condition the wrong way when the guest's
  X28 holds what the test's first start puts there. Counts are predictable exactly: the B.cond control also
  changes the cases where B.cond follows an instruction it does not join.

Results as committed (5a68844f17): all matches with and without chaining, 1032 of 1032 gadgets taken, no
unjoined setter, controls 29, 8, 10, 168, 252 and 280 as predicted, Alpine boots and agrees (about 22% less
time for its command set than with RCG off, for what one run says).

PR 3's results as committed (591d836c8a): all matches, 376 of 376 gadgets taken, every control changes exactly the
cases its kind runs with a value in the first source (counts in the commit message), Alpine boots and agrees.

PR 2's results as committed (5cc0f07f3d, first pushed as 1a8abb6276 with a function per case): all matches, 120 of 120 gadgets taken, controls change 64, 56, 64, 60 and
192 cases as accounted for in the commit message, x86 9692 of 9692 and 0 of 225283 fault checks failed.
