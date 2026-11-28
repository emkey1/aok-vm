# The gadgets of 2026-11-28 ("item 3"): what sent streams to TCG, their test and controls

Engine commit 818dd75848. A TB is a stream as far as its insns are gadgets; TCG's TB runs from
the first that is not to the end of the block, and each change between the two is a pass of the
main loop. `QEMU_AOK_STATS=2` lists TCG's TBs by how often the main loop entered them
(`aok: tcg-entry COUNT PC INSN`); `entries.py FILE` sums that by kind of insn.

| | Mac OS X 10.4, boot and Xbench | Mac OS 9.2.2, ninety seconds |
|---|---|---|
| main loop entered streams / TCG, before | 115 M / 122 M | 208 M / 203 M |
| what began TCG's TBs | dst 17%, mtocrf 14%, isync 11%, stvx 10%, mfmsr 8%, lvx 7%, mtsrin 7%, mtmsr 7%, icbi 4%, dcbf 4%, rfi 2%, lswi 2% | addco 51%, bcctr on a CR bit 28%, subfco 17% |
| after | 24 M / 6.7 M | 12 M / 7.7 M |
| what still does | AltiVec arithmetic 32%, sc 26%, mfspr DEC 18%, lvsl 12%, mfvscr and mtvscr | twi 31 (a trap) 52%, mfspr DEC 24%, lswx 12% |

Xbench under Mac OS X, the machine alone, before (engine 9d4b46d897) and after: Memory test
38.3 to 128.6 (Allocate 33 to 41, Fill 23.9 to 254, Copy 47.9 to 284, the AltiVec stream tests
46.9 to 202); CPU test 17.7 and thread test 61.7 as they were. Mac OS 9 reaches its desktop
after about 30 s on MBP5 where it took about 50 (`STEP=10 os9-try.sh`, the engine before and
after side by side; the first figures written here, 60 against 100, were from runs that could
not be compared).

The copy and fill loops were lvx, stvx and dst in a loop of gadgets: two passes of the main
loop at every turn. Where a loop has an insn that is still TCG's (AltiVec arithmetic), a stream
for part of it would do the same, so the front end looks ahead to the block's branch and
leaves such a TB whole to TCG (`tail_loops_back`; 309 TBs in the run).

- `vectest.c`: the user-mode insns at their edges (the vector loads and stores at every
  alignment, by a page's end, into a page that is not there; mfocrf and mtocrf with every kind
  of mask; the OE forms from every state of XER; bcctr and bcctrl on a CR bit; lswi and stswi of
  every length; the hints and cache insns). Built with
  `zig cc -target powerpc-linux-musleabihf -mcpu=7400 -O1 -static`. `vec-gate.sh BUILD` runs it
  in the kit's Linux with the gadgets and without: 42 lines, none may differ.
- `../ctx/ctxtest.bin` covers the supervisor's (mfmsr, mtmsr, mtsrin, mfsr, mfsrin, isync, sync,
  rfi): T7, and every other test there now runs through them.
- `i3variant.py NAME SRC`, `i3-controls.sh`: seventeen faults, each built in turn; thirteen
  must change vectest's lines and four must fail ctxtest. All do. One of them is a stream that
  goes on after an isync that switched TLB contexts: it runs the other context's code (T4),
  which is why isync, sync and rfi return to the main loop when they did anything.
- `os9-try.sh ENGINE [SECONDS]`: Mac OS 9.2.2 from the test disk on a throwaway overlay, a
  picture every 30 s. `i3-build.sh`: the PowerPC-only build on MBP5.
- `../fp/ppc-gates.sh BUILD`: the kit's transcripts, 166 lines identical.

**Not done here, noticed:** the front end asks only the new gadgets whether the CPU has the
insn (`insns_flags`); the older ones (fsqrt, the FP set, lwarx, dcbz, mftb) are translated for
any 32-bit CPU model, where TCG would raise a program exception for an insn the model lacks.
