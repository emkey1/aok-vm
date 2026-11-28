# sc, the decrementer, tlbie, tlbsync, lswx and stswx in the streams

The insns that still began TCG's TBs under Mac OS X once AltiVec had gadgets
(emkey1/qemu `aok-vm` 61cda07b7b; `docs/devel/aok-gadgets-ppc.rst`, "Streams
that hand over to TCG"). On MBP5 in `~/aok-vm-bench/sv`.

| file | what |
|---|---|
| `sv-build.sh` | the engine with them as `src-sv` / `build-sv` (PowerPC only) |
| `svvariant.py NAME SRC` | one deliberate fault (`list` names the eight) |
| `sv-controls.sh [NAME...]` | each fault built in turn; ctxtest must fail for each, in the test written for it |
| `chain-sv.sh` | the controls, every PowerPC gate, the AltiVec switch, Mac OS 9, Xbench beside the engine before |

The test is ctxtest's T8 (`../ctx/ctxgen.py`): the decrementer set to
0x7fffffff and read twice, an `sc` whose handler at 0xc00 returns to the insn
after it, `tlbsync` in T2's sequence, and `lswx` of seven bytes and `stswx`
of them over ff bytes.

## Results (2026-11-28)

* ctxtest passes on Homebrew's QEMU 11.1.2 and on the engine with and without
  the gadgets and the TLB contexts. 8 of 8 faults seen, each by its own test.
* The first run of the controls called seven of them seen with every result
  word reading 0: a binary's first start on macOS is slow, and the test had
  not begun when the monitor was asked. A warm start first, and the seven
  failed where they should, but for one, a `stswx` that stored a byte too
  many: the byte was a zero over a zero. The test now stores over ff bytes.
* The kit's transcripts (166 lines), fpstress, vectest and avstress (720
  lines) as before. With `QEMU_AOK_NO_ALTIVEC=1` avstress prints the same
  lines, and TCG's code is entered 2.9 million times for AltiVec, where it
  is 263 times in all with the gadgets.
* Mac OS X 10.4 with Xbench: TCG's code entered 44,920 times in the run
  against 3,285,673 on the engine before; streams 20.0 million times against
  21.5 million. Xbench's lines did not move (`../../bench/macosx/README.md`).
