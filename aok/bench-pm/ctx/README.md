# The TLB context cache's test and its controls (2026-11-28)

For the engine's `tlb_context_switch()` (accel/tcg/cputlb.c) and target/ppc's use of it, engine
commit 9d4b46d897: a TLB and jump cache for each set of the sixteen segment registers, where
QEMU flushed both at every change. Why: `../../bench/macosx/README.md`. All of it runs on MBP5
in `~/aok-vm-bench` (`ctx/` there is this directory).

- `ctxgen.py`: writes `ctxtest.bin`, a firmware for `-M mac99 -bios` as machine code (no
  assembler, no OS). It builds a hashed page table in which one address means different pages
  under different VSIDs, turns translation on, and walks segment register 4 through them; each
  observation is a word at 0x3000. T1 data after switching there and back; T4 code likewise
  (the jump cache is part of a context); T2 a `tlbie` while a context is set aside; T3 an
  access between an `mtsr` and its `isync` (twice: the context kept, and set aside); T5 a store
  to code through an entry that was set aside when the code first ran; T6 twelve sets, more
  than the eight contexts; T7 the supervisor insns that became gadgets the same day.
- `ctxcheck.py`: the words from the monitor's `xp /28wx 0x3000` against what they must be.
- `ctx-test.sh BUILD...`: the test with the gadgets and without, with the contexts and with
  `QEMU_AOK_NO_TLB_CONTEXTS`. A build may also be a path: Homebrew's `qemu-system-ppc` 11.1 is
  the oracle, and passes. So do the engine before and after.
- `ctxvariant.py NAME SRC`, `ctx-controls.sh`: six faults, each built in turn. **Each must fail
  the test written for it,** and does: a flush that spares the contexts (T2), the entry made
  before the isync kept (T3), the jump cache not exchanged (T4), `tlb_reset_dirty()` stopping at
  the TLB in use (T5), a context reused unflushed (T6), a key compared in part (T6).
- `ctx-build.sh`, `all-gates.sh`: the four-guest build and every gate on it (the cache is in
  code all guests share): x86, RISC-V, ARM64 and PowerPC transcripts identical with and
  without the gadgets.

**Measured** (Xbench 1.3 under Mac OS X 10.4.11, one binary, each machine alone; with the
contexts twice, without three times):

| | without | with |
|---|---|---|
| Memory test | 30.69, 30.66, 30.90 | 38.44, 38.18 |
| Allocate | 15.29, 15.22, 15.18 | 33.46, 32.93 |
| Fill | 23.27, 23.44, 23.60 | 24.12, 23.91 |
| Copy | 45.70, 45.96, 46.06 | 47.71, 48.09 |
| Stream | 46.00, 45.74, 46.69 | 47.04, 46.74 |
| Thread test | 60.66, 61.15, 60.17 | 61.33, 63.96 |
| CPU test | 17.02, 17.20, 17.60 | 18.06, 17.25 |
| Quartz Graphics (side by side, before the growth rule) | 17.99 | 23.56 |

Over a boot and a run: 1.07 million switches found their contents, 72 thousand did not, 25
thousand flushes discarded contexts; TLB tables flushed 2.33 million to 0.46 million; lookups
of a TB in C 102 million to 40 million.

**Two things the first numbers hid.**

- *Copy was 16% lower with the contexts* (39.5 and 37.6 against 45.8). A table is resized when
  it is flushed, a context seldom is, and a small direct-mapped table sends a copy between two
  buffers a megabyte apart through the slow path. Fixed: a context taken up again with a table
  over 70% full is flushed to grow (1500 times a run), and tables stop at 8192 entries.
- *Side by side misled.* With both machines running at once Copy also read low, but that could
  not be told from an artifact: once one arm is faster in an early test, the two are in
  different tests at any moment. Only the solo runs settled it.

**Not explained:** the GCD loop read 411, 362, 391, 379 with the contexts and 437, 443, 413
without. The other CPU lines move that much between identical runs (FP Basic 24 to 32, one
AltiVec line dropped to a third once), and two profiles taken to compare landed in different
phases. No mechanism found.
