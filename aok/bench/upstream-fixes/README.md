# Tests for what came from upstream on 2026-11-01

Each failed on the engine before its fix (11adf734f6, but for `uetest.c`: 6e0ad2a177) and passes after. None is part of a gate.

| | |
|---|---|
| `x86upfix.c` | every x87 compare's C1, and RET, RETF and ENTER counts of 0x8000 and up. Run it on a real x86 and in a guest, and diff the transcripts: QEMU_AOK=1 must match the hardware on every line. With QEMU_AOK=0, TCG differs where the stack is empty, because it has no x87 stack faults. |
| `usbcsw.c` | a USB stick's status request queued with its data transfer, through usbfs, in a guest with `-device qemu-xhci -device usb-storage`. The stick's image holds each block's number in the block's first four bytes. Needs the modules `xhci_pci` and `usbcore`, and no `usb_storage`. |
| `uetest.c` | (2026-11-27) SSE products and quotients that round up to exactly the smallest normal, with the inexact flag already set: x86 calls that an underflow. Run it on a real x86 and in a guest, and compare. TCG's inline float path left UE out until tctiSH's 1599207c97; the gadgets never did. |
| `screamer-dbdma.py` | the PowerMac's sound input leaving its DMA channel ACTIVE with RUN clear. No guest: `screamer-dbdma.py QEMU-SYSTEM-PPC PC-BIOS`. |

Suspending a machine whose disk is zstd-compressed (QEMUKit e8e9e877) was tried in the simulator: on the Alpine x86-64
machine with `qemu-img convert -c -O qcow2 -o compression_type=zstd`, and the `AutosaveBackground` default on, send the
app to the background. Before: `error saving snapshot: ... Invalid parameter 'zstd'`. After: `Save snapshot complete`,
and a relaunch restores that session.

## tctiSH's 0c7e606fbb on our engine (2026-11-01)

brcond, brcondi and the exit check branch around a move instead of a CSEL into
x28. Local branch `tcti-brcond` (aa2a88c556), on 7a7aab20d9. Host cycles, new
against old, on MBP5, three runs interleaved (brcond-scripts.txt):

| guest | gadgets on | gadgets off | coremark, gadgets off |
|---|---|---|---|
| x86-64 | 1.002 | 0.898 | 0.783 |
| ARM64 | 1.004 | 0.925 | 0.780 |
| RISC-V | 0.996 | 0.888 | 0.774 |
| PowerPC | 1.001 | 0.942 | 0.865 |

Gadget code is level; what the gadgets leave to TCTI gains. The whole gates: every
line identical, 16 of 16, as before; TLBFOLD 0 of 120000 wrong in 13 runs.

**On the A10X (2026-11-03, iOS 17.7.11):** the new engine against build 12's
(11adf734f6, so without 11.1.3 either: a comparison of builds), in the app, with the
installs alternating; ms from each run's RESULT lines (a10x-scripts.txt).

| | new | build 12 | new/build 12 |
|---|---|---|---|
| RISC-V, gadgets off: coremark | 4906, 4870 | 5577 | 0.876 |
| nbody | 6316, 6423 | 6579 | 0.968 |
| python | 23054, 22796 | 24262 | 0.945 |
| xz | 8817, 8390 | 8960 | 0.960 |
| sha256 | 2992, 2841 | 3212 | 0.908 |
| awk | 19117, 19353 | 21296 | 0.903 |
| 68k, mostly TCTI: coremark | 6418, 6867, 6420 | 6874, 6657 | 0.949 |
| sha256 | 4426, 5197, 4384 | 4675, 4621 | 0.952 |

So the branch does not hurt on this core: RISC-V's geometric mean with the gadgets off
is 0.926. With the gadgets on, four boots of each, one after another, are level at 1.007
(coremark 4008 to 4039 against 3962 to 3992). Coremark took 5373 and 5546 in two of the
three earlier boots of the new engine, which ran among installs; none of build 12's five
boots did, and none of the last four of the new engine. The other workloads of those two
boots were normal. Coremark is the first workload after boot, so it may be something
else on the device at that moment, but that is not shown, and 2 of 7 against 0 of 5 does
not separate the engines.


## tctiSH's 6a4af68ae2 and 1599207c97 on our engine (2026-11-27)

Two fixes cherry-picked onto emkey1/qemu `aok-vm` (306a214832 and 59d74ba12d, on
6e0ad2a177); both applied without a conflict. Built and run on MBP5 as `build-up`,
beside `build-aok-x64` for the engine before (fixes-1127-scripts.txt).

- **1599207c97, the inline float path and the smallest normal.** `uetest`, 20 lines, against
  camd's (a real x86): the engine before with QEMU_AOK=0 differs in 9, each a product or a
  quotient that should raise UE and has PE alone; the new engine with QEMU_AOK=0 differs in
  none. With the gadgets on both engines match the hardware in all 20: the gadgets already
  leave a result of the smallest normal to the helper. So this matters to what the gadgets
  hand to TCG, and to a machine run with them off.
- **6a4af68ae2, the flush for a code-cache release.** Nothing in AOK VM asks for a release
  (`tctish_code_cache_release_all()` and the shrink have no caller in the app), so the race
  cannot happen there today and nothing here exercises it. Taken to stay level with tctiSH.

The x86 gates on the new binary: 8 of 8 transcripts identical to their references
(x64gate.sh). With QEMU_AOK=0, `check,fptest,memtest` and `fptest -v` (369966 lines) are
identical to the TCG references: fptest clears the flags before each operation, so it never
enters the inline path with PE set, which is why it did not see this.

Not done: the same on a device. The change is in the code TCTI emits, which is the same on
a Mac; the iOS engines get it when they are next built for a release.

## UTM's fixes in the app (2026-11-27)

Four commits of utmapp/UTM cherry-picked (`-x`) onto aok-vm, each without its `Tests/`
files, which this tree has no target for, and the two packages moved to UTM's revisions.

| UTM | here | what | how it was checked |
|---|---|---|---|
| 58803db8 | 4ef025a5 | one registry entry that does not decode no longer empties the registry | below |
| f5aa438d | d8ffa21e | the details pane does not force-cast a missing configuration | the pane still shows a machine's details (simulator). The crash has no route here by hand: an unavailable machine's row cannot be selected, it opens "cannot be found" |
| 467726a0 | dd8c1a99 | the launch crash on iOS 15 from the iOS 26 toolbar spacer | the toolbar is as before on iOS 26.5 (+, heart, Settings, Edit). NOT run on iOS 15: neither Mac has that runtime. Conflict: this tree's buttons kept (no accessibility identifiers, Settings as text) |
| a4d92e3f | 6eb0752e | the FPS limit's default is an integer, as its values are | the built Settings.bundle's Root.plist |
| CocoaSpice e239fab | | UTM took our dbe9036 as db7f044, so the app takes utmapp/CocoaSpice main again; with it aa04c00, a screenshot that owns its pixels | a restore shows its console at once (below) |
| QEMUKit 0a62428 | | a guest agent's bad answer cannot crash the app; the last drive is in removableDrives | boot, suspend and restore go through QEMUKit (below) |

**The registry, end to end** (`regtest.sh` in fixes-1127-scripts.txt; MBP5's simulator, the
Alpine x86-64 machine, AutosaveBackground on): the machine is suspended, the app ended, an
entry with only a Name added to Registry in the app's preferences, and the machine started
again. The witness is `snapshot-load` in the machine's debug.log and the state leaving
snapshots.plist.

| app | bad entry | snapshot-load | state afterwards |
|---|---|---|---|
| build 12's (4 Nov) | none | 2 | used |
| build 12's (4 Nov) | one | 0 | still listed: booted fresh |
| this one | one | 2 | used |

The first row is from a first attempt whose entry went into the wrong file: `simctl spawn
defaults write` writes the device's copy of the domain, which the app's own preferences
(in its data container) shadow. The entry has to go into the container's plist with the app
ended, and the simulator's cfprefsd ended by its pid, or the launch reads its cache.
