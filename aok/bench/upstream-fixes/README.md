# Tests for what came from upstream on 2026-11-01

Each failed on the engine before its fix (11adf734f6, but for `uetest.c`: 6e0ad2a177) and passes after. None is part of a gate.

| | |
|---|---|
| `x86upfix.c` | every x87 compare's C1, and RET, RETF and ENTER counts of 0x8000 and up. Run it on a real x86 and in a guest, and diff the transcripts: QEMU_AOK=1 must match the hardware on every line. With QEMU_AOK=0, TCG differs where the stack is empty, because it has no x87 stack faults. |
| `usbcsw.c` | a USB stick's status request queued with its data transfer, through usbfs, in a guest with `-device qemu-xhci -device usb-storage`. The stick's image holds each block's number in the block's first four bytes. Needs the modules `xhci_pci` and `usbcore`, and no `usb_storage`. |
| `uetest.c` | (2026-11-27) SSE products and quotients that round up to exactly the smallest normal, with the inexact flag already set: x86 calls that an underflow. Run it on a real x86 and in a guest, and compare. TCG's inline float path left UE out until tctiSH's 1599207c97; the gadgets never did. |
| `batgen.py` | (2026-11-27) two PowerPC programs as machine code, for what a reset leaves in the BATs (UTM's e1c17c2009): a firmware that records them, and a kernel that leaves one over OpenBIOS. No assembler, no Mac OS. |
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

On a device: below.

## UTM's e1c17c2009 on our engine: a reset clears the BATs (2026-11-27)

Mac OS 9's Restart ended on a black screen in UTM (their #7999): a 6xx/7xx/74xx CPU's BATs
are outside `env->spr[]`, so a reset left them as the guest had them, and OpenBIOS, which
turns translation on expecting its next fetch to fault, ran through the stale mapping
instead. utmapp/qemu e1c17c2009, cherry-picked as emkey1/qemu aok-vm 30e130b9a6 (the user
asked for it the same day). Two tests that need no Mac OS (`batgen.py` writes both programs
as machine code; mbp5-bat-test.sh in fixes-1127-scripts.txt), each on the engine before
(6e0ad2a177) and after, on mac99 and g3beige, gadgets on and off: eight runs a test.

| test | before | after |
|---|---|---|
| A: our own firmware loads DBAT0 and IBAT3, and after `system_reset` stores what they hold | 80001fff 80000012 90001ffe 90000012: as loaded | all four zero |
| B: OpenBIOS starts a kernel that maps OpenBIOS's address to empty RAM with BAT0 and counts its starts; then `system_reset` | the count is never 2: OpenBIOS is stuck at fff2cd8c, one banner on the serial line | the kernel starts a second time, two banners |

All eight runs of each agree with their column.

**With Mac OS 9 itself** (the user gave the images: archive.org's item mac-os9, `MacOS9.iso`
724755456 bytes, sha256 1bedd15e...269b7, Mac OS 9.2.2's CD; os9-run.sh). On MBP5, the
engine built with pixman so that there is a VGA card and `screendump`, `-M mac99 -m 512
-boot d` and the CD: the Finder is up within 90 s on either engine.

| restart | before the fix | with it |
|---|---|---|
| the monitor's `system_reset` | the picture stays as it was, clock stopped, one OpenBIOS banner (1 of 1) | the Finder again, two banners (1 of 1) |
| Mac OS's own: the Power key's dialog, then R for Restart | black for the 150 s watched, one banner (2 of 2) | the Finder again, two banners (3 of 3) |

The Power key through `sendkey power` is not reliable there on either engine (three
machines each, three presses: the dialog, an icon selected, or nothing, in no pattern), so
os9-run.sh presses it until the picture has the dialog's fewer colours before it sends R.
A first run on the fixed engine sent R to the Finder and proved nothing.

**In the app on the A10X** (os9-dev.sh; "Mac OS 9 Test": mac99, the CD, a VGA display, USB
2.0, a monitor on TCP 4455; the Finder is up 60 s after the start in either app):

| the monitor's `system_reset` | build 13's app | this build |
|---|---|---|
| Mac OS 9.2.2 at the Finder | the CPU stays at fff2d2c4 in the firmware and the Finder's picture stays on the screen, 12 minutes watched | the screen leaves the Finder and Mac OS is back in 60 s |

The first tries there did not get as far as the Finder, for a reason of the test machine's
own: the last section.

## The three engine fixes and the app's on the A10X (2026-11-27, iPadOS 17.7.11)

The iOS engines built from 30e130b9a6 (MBP5, eng.sh), the app from aok-vm 4c42eb51, against
build 13's app from its archive (dev-fix.sh, dev-round.sh).

| | build 13 | this build |
|---|---|---|
| `uetest` in "AOK UE Test" (the x86-64 console machine with the test added), QEMU_AOK=0 | 9 of 20 lines differ from the hardware | 0 |
| the same with the gadgets | | 0 |
| "AOK BAT Reset" (mac99, test B's kernel), `system_reset` over a monitor on TCP 4455 | 90 s later no second start, NIP fff2d2c4, one banner | second start after 5 s, two banners |

Then this build alone: each engine's machine comes up (Alpine ARM64 to its login, ReactOS to
its desktop, the x86-64 stress with four equal hashes, the RISC-V workloads, PowerPC's
`TLBFOLD ok: 0 of 120000 checks wrong`, the 68k workloads; no error in any log), and a
suspend through the background with a restore on "x64 CPU Test" (x86-64, virtio-vga:
`snapshot-load`, the state used, the same picture 8 s after the relaunch) and on "Alpine
3.24.2 (aarch64)" (the state used, its console on the screen 8 s after the relaunch). That
is CocoaSpice's and QEMUKit's new revisions on a device. One report from the day: a
cpu_resource diagnostic (not a crash) of build 13's app during its gadgets-off run.

The monitor on a device: `-monitor tcp:0.0.0.0:4455,server=on,wait=off` in the machine's
additional arguments, reached with nc at the iPad's cable address (169.254.114.85 for bip;
its Tailscale address answers too).

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

## Mac OS 9 needs the Power Mac's USB controller (found and fixed 2026-11-27)

The Mac OS 9 machine first made for the A10X never reached the Finder, 3 starts of 3: the
CPU went round 68067ec0 to 68067ed4 (LR 680b07f0, in Mac OS's 68k emulator) from the first
minute on, the screen still showing OpenBIOS's last text. Not from that day's fixes (the
engine before them did the same), not our engine (Homebrew's QEMU 11.1.2 with the JIT did
the same), and not speed: under `-icount`, where the machine has one speed whatever the
host does, it stopped at 500, 125, 31 and 8 MIPS alike.

**Cause.** The test machine was cloned from a console machine whose USB support is off. The
app passes `-nodefaults` and adds `-usb` only when a machine's USB support is on, and
QEMU's mac99 has its USB controller only with the defaults or `usb=on`
(hw/ppc/mac_newworld.c: `machine->usb |= defaults_enabled() && !machine->usb_disabled`).
Mac OS 9.2.2 waits for ever without it, with ADB input or without. Under `-icount shift=3`
on Homebrew's QEMU (os9-e5.sh, os9-e6.sh), one run each:

| machine | result |
|---|---|
| plain `-M mac99`; the same with no network card, with `-device VGA`, with the CD on ide.0 | the Finder, all four |
| plain with `usb=off` | stopped at 68067ec0 |
| `-nodefaults` with the display, a network card and the CD given back | stopped |
| `-nodefaults` with `usb=on` | the Finder |
| the app's whole set | stopped |
| the app's whole set with `usb=on` | the Finder, on our engine too |

**Fix (aok-vm, UTMQemuConfiguration+Arguments.swift):** a mac99 machine whose USB support is
off gets `usb=on` as a machine property, so the Power Mac keeps the controller it is built
with; a property the user wrote still wins. On the A10X, the same machine with USB support
Disabled: 3 of 3 stopped before; with the change `-machine mac99,via=pmu,usb=on` is in its
log and the Finder is up in 60 s. UTM has the same lines and its QEMU the same default:
reported there (utmapp/UTM#8233).

**What misled me, for the next time.** The first comparisons ran eight to eighteen machines
at once, and there the outcome of the same settings changed from round to round, so it
looked like timing. Two more things are true and are not ours to fix: on Homebrew's QEMU the
plain machine (with USB) also stops now and then when the host is that busy (1 of 3, and
1 of 4 on our engine with twelve running), and under `-icount shift=5` it stops every time
(4 of 4) at 00f268d0, while shifts 1, 2, 3, 4, 6 and 7 reach the Finder. Neither was seen with six machines or fewer
(17 of 17 on our engine), nor on the A10X once USB was there (3 starts of 3). `-icount` is
what separated them: fix the machine's speed before comparing settings.
The Power key sent with `sendkey power` is unreliable on either engine.

The images are on MBP5 in `~/aok-vm-bench/macos9` (the 2 GB disk image untried), with the
engines built with a display (`build-os9-old`, `build-os9-new`).
