# AltiVec gadgets: the test and its controls

The PowerPC front end's AltiVec gadgets (emkey1/qemu `aok-vm` dd744be8ea,
`docs/devel/aok-gadgets-ppc.rst`, "AltiVec"). Everything here runs on MBP5 in
`~/aok-vm-bench/av`, against the kit's PowerPC Linux guest.

| file | what |
|---|---|
| `avgen.py [ROUNDS]` | writes `avstress.c`: a function for every AltiVec insn of a G4 and every value of its immediate (719, with the forms that write over an operand), each run ROUNDS (4000) times; a hash an insn |
| `av-build.sh` | the engine with the gadgets as `src-av` / `build-av` (PowerPC only) |
| `av-gate.sh BUILD...` | avstress with the gadgets and with `QEMU_AOK=0`: the lines that differ, how many FP vectors went to C, what still began TCG's TBs |
| `avvariant.py NAME SRC` | one deliberate fault in a gadget (`list` names the 38) |
| `av-controls.sh [NAME...]` | each fault built in turn and run: every one must change a line |
| `chain-av.sh BUILD ENGINE` | every PowerPC gate (the kit, fpstress, vectest, ctxtest, avstress), Mac OS 9 to its desktop, Xbench's graphics tests beside the engine before |

Build the test with
`python3 avgen.py 4000 > avstress.c && zig cc -target powerpc-linux-musleabihf -mcpu=7400 -O1 -static -o avstress avstress.c`.

## What the test does

Each function loads three operand vectors, VSCR (NJ set three times in four, as
Mac OS X has it; SAT set or not) and CR6, runs the insn into a register that
held something, and stores every vector register, VSCR and the CR; all of it is
hashed. Operands are any bits, or values from where the gadgets draw their
lines: NaNs of both kinds, denormals, the least normal number and its
neighbours, numbers at the bottom of the range and numbers whose products are
there, operands that cancel exactly or by one unit, values around 2^31 and
2^32 for the conversions, and integers at each width's limits for the
saturating ops. A vector with a NaN or a denormal in it goes to C whole, so
every other round has none: there the gadgets' own arithmetic runs, with
results on both sides of the least normal number.

## Results (2026-11-28)

* 720 lines identical with the gadgets and with `QEMU_AOK=0`; 118 thousand of
  the FP vectors went to QEMU's helpers. The test takes 7.3 s of guest time
  with the gadgets and 14.0 s without.
* 38 of 38 faults seen. A fault in `vperm`, `mfvscr` or `mtvscr` changes
  nearly every line: the compiler's own code for the harness uses the first,
  and every function the other two.
* The kit's transcripts (166 lines), fpstress, vectest (42 lines) and ctxtest
  (four ways) are as before. Mac OS 9 is at its desktop by 30 s.
* No AltiVec insn began a TB of TCG's in the test; in the Xbench run under Mac
  OS X eleven did (MSR[VR] off: the exception is TCG's to raise).

Xbench under Mac OS X 10.4: `../../bench/macosx/README.md`.

A kernel message can land on the end of a line of the test's (the console is
shared): the gate compares the name and the hash's sixteen digits only.
