# The PowerPC FP gadgets' gate and its controls (2026-11-27)

For the engine's `target/ppc/tcg/aok/gadgets.S` (engine commit 27e0e02bb2: the single-precision
gadgets and the zero, tiny-product, cancelled, quiet-NaN and infinity results). All of it runs on
MBP5 in `~/aok-vm-bench` (`fp/` there is this directory).

- `../stress/fpstress.c`: two million double ops, then two million single ops, a hash line per
  200000 (`FPSTRESS`, `FPSTRESS-S`). One op in eight gets an addend that is the product or its
  negative, so that fused ops cancel exactly. Built here with
  `zig cc -target powerpc-linux-musleabihf -mcpu=7400 -O1 -static` (build-stress.sh's Debian cross
  compiler needs a container runtime, which was not up); `mkinitrd.sh` appends it to the kit's
  stress initramfs as `kit/ppc/initramfs-stress-s.cpio`.
- `gate.sh BUILD...`: fpstress with the gadgets and with `QEMU_AOK=0`, the lines that differ
  (must be 0 of 20), and what the gadgets still sent to C and why (`QEMU_AOK_STATS`).
- `variant.py NAME gadgets.S`: one deliberate fault, eighteen of them. `controls.sh` builds each
  into `build-fp`'s engine in turn, runs fpstress on all, and counts the lines that differ from
  the gate's run without gadgets. **Every fault must change lines.** All eighteen do (ten or
  twenty of twenty). `fma-cancel` and `fmas-cancel` (a wrong sign on a cancelled sum) changed
  none until fpstress had the cancelling addends: the gate did not reach that path, and Xbench
  does, 156 thousand times a run.
- `fpstress-v.c`, `gate-v.sh`: a line per op, for finding which op differs.
- `ppc-gates.sh BUILD`: the kit's check, fptest, memtest, fpstress, heapstress and tlbfold with
  and without the gadgets (166 lines, identical), and tlbfold twelve at once.
- `build.sh`, `rebuild.sh`: the worktree and build directory on MBP5.

Results on Xbench under Mac OS X: `../../bench/macosx/README.md`.
