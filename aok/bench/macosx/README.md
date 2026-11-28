# Mac OS X 10.4 (PowerPC) for testing (2026-11-27)

Not for distribution: Mac OS X is Apple's. The user gave the sources, archive.org's item
`mac-osx-tiger-10.4-ppc-installed-qcow2-image`: an installed disk
(`osx-tiger_10.4.11_installed.qcow2.7z`, 1929055939 bytes, sha256 cb37f452...8bf1; inside,
a 20 GB qcow2 of 4.8 GB) and the install DVD (`OSX_Tiger_4.6_installation_dvd.img`).
On MBP5 in `~/aok-vm-bench/macosx/{installed-7z,installed,dvd}` (osx-dl.sh; the 7z opens
with macOS's own bsdtar). The installed disk is kept read-only; every run is on an overlay
or a copy.

**It boots**, to the Finder and its Dock, logged in by itself: Mac OS X 10.4.11 on
`-M mac99,via=pmu` with 1 GB, on Homebrew's QEMU 11.1.2 with the plain machine and with the
devices AOK VM gives a mac99 machine with USB on, and on our engine with the app's devices
(osx-run.sh; the desktop within two minutes on MBP5 on the threaded interpreter). Unlike
Mac OS 9 it is PowerPC code all the way down, no 68k emulator in the guest.

**The work disk** (`macosx/work/tiger.qcow2`, osx-work.sh) is a copy with free software
added, the user's choice of that day (osx-dl2.sh; each download in a directory of its own
under `macosx/dl`): TenFourFox FPR32.5 (the 7400 build), VLC 2.0.10, Xbench 1.3, DOSBox
0.74-2, ScummVM 1.2.1, SuperTux 0.1.3, TextWrangler 3.5.3 and The Battle for Wesnoth 1.8.6,
from their projects' own hosts but TextWrangler (Macintosh Garden). Nothing downloaded is
opened on the Mac: the guest fetches each file from a server on the Mac's loopback
(10.0.2.2:8642 from inside) and installs it with its own hdiutil and ditto: `i.sh`, typed
into the guest's Terminal through QMP (Finder: command-shift-U, type "terminal", command-O).

**A script that deleted what it was meant to add to.** The first `i.sh` removed
`/Applications/NAME.app` before each copy and took its sources from `"$m"/*/*.app`. VLC's
image has the usual link `Applications -> /Applications`, so the wildcard named the guest's
own applications and the script deleted several before anything stopped it. Only the work
copy was touched; it was thrown away and made again. `i.sh` now never removes, lists
sources with `find` (which does not follow links) and leaves an application that is already
there alone.

**Three of the eight did not start on 10.4** (the user found Wesnoth; `t.sh` then started each
in the guest): the versions first chosen need Mac OS X 10.5. Wesnoth 1.8.6: its Lua wants
`___stack_chk_guard`; VLC 2.0.10: a newer libiconv; TextWrangler 3.5.3: `_kUTTypeImage`.
Replaced (osx-dl3.sh, `i.sh vlc9 tw31 wes16`) by Wesnoth 1.6.5, VLC 0.9.10 and TextWrangler
3.1, which start, as do TenFourFox, Xbench, DOSBox, ScummVM and SuperTux (SuperTux only
from its own folder or the Finder: it looks for its data beside itself). The corrected
disk is `macosx/work/tiger-final2.qcow2` (sha256 f956eece...); it boots on our engine.
Check that a thing starts on the system it is for before calling it installed.

All eight installed (Xbench was started as a check); the guest was shut down from its Apple
menu, by keyboard (control-F2, down, "shut", return, return: a shut down asked of the Finder
from Terminal times out, because Terminal will not quit under it). The result,
`macosx/work/tiger-final.qcow2` (4.8 GB, sha256 0985056a...), is the machine "Mac OS X
Tiger" (mac99, 1 GB, VGA, USB 2.0, a sungem card, the disk on IDE): on the user's M4 iPad
Pro, in the released build 13, the desktop is up 60 s after the start. Build 13 has not the
BAT fix, so a Restart inside the guest will not come back there; Shut Down is fine.

The pointer: Mac OS X has no driver for the virtio tablet, so in the app the guest's mouse
is the Power Mac's own USB mouse, relative. Keys through QMP work as they are.

## Xbench 1.3 on our engine and on the JIT (2026-11-27, MBP5, the same disk; 100 is a 2 GHz G5)

The user found the score on the M4 iPad underwhelming. CPU, thread and memory tests only
(osx-run.sh with KEEP=1 and the app's devices, xb.sh; Xbench's boxes and Start are worked by
keyboard: control-F7, tab, space):

| | our engine | Homebrew's QEMU 11.1.2, JIT |
|---|---|---|
| CPU test | 4.52 | 5.31 |
| GCD loop | 180.48 | 246.99 |
| Floating Point Basic | 2.55 | 3.24 |
| AltiVec Basic | 322.07 | 547.76 |
| vecLib FFT | 1.63 | 2.18 |
| Floating Point Library | 11.03 | 5.91 |
| Thread test | 20.39 (computation 63.40, lock contention 12.15) | 29.67 (260.43, 15.73) |
| Memory test | 12.30 (allocate 5.15, fill 11.15, copy 22.10; stream 18.87) | 30.37 (10.96, 90.08, 112.09; 34.76) |

The CPU score is its two floating-point lines: a fortieth of a G5 on either engine, because
QEMU does PowerPC floating point in software (every operation owes FPSCR its FPRF, FR and
FI). Two samples of our engine's vCPU thread during the run, by kind of work: in the first
(system-heavy) 15% is `tcg_flush_jmp_cache`, 21% TLB and TB lookups and refills, 42% gadgets;
in the second 25% is softfloat and its helpers, 33% gadgets. Mac OS X flushes the TLB very
often, and every flush clears all 4096 entries of the jump cache whether or not anything
was put in it since the last one.

The user's order of work (2026-11-27): the redundant jump-cache flushes; then PowerPC
floating point on the host's FPU as gadgets; then more PowerPC gadgets for memory work (the
front end has 220 against about 2000 for the other guests).

### 2: the jump-cache flushes were not redundant

A flag that skips a flush of a jump cache nothing was put into passed every gate and changed
nothing: counted over a boot and one Xbench run, 1305771 flushes found TBs in the cache and
67 found it clean. (The change was dropped, engine commit never pushed.) What flushes: 160520
`tlbie`, but 8.9 million writes that changed a segment register, and 1.17 million whole-TLB
flushes at the sync points after them, about 4300 a second. Mac OS X gives the kernel an
address space of its own, so it loads other segment registers on the way in and out of the
kernel, and QEMU's PowerPC target flushes the TLB (and so the jump cache) each time, where
the real machine's TLB is tagged by VSID and keeps its entries.

A simulation in the engine (diag2.py, with the FP kit): at each such flush, were the sixteen
segment registers a set seen since the last flush a `tlbie` asked for? Of 1166508 flushes,
40833 had a `tlbie` pending; of the rest the set was the 2nd most recent 332463 times, the
3rd or 4th 705215, 5th to 8th 29846, 9th to 16th 2475, and new 55676. Keeping four TLB
contexts, keyed by the segment registers, would spare 89% of the flushes.

### 1: PowerPC floating point (engine 27e0e02bb2)

Single-precision gadgets alone did not move the score: 43 million FP insns in the run still
went to C, because the fast paths gave up on zero operands in fused multiply-adds (14.2
million), on NaN or infinite operands in single ops (6.3 million each of `fadds`, `fmuls`,
`fmadds`: a loop that runs on NaNs) and on tiny products. With those finished in the
gadgets too, 87 thousand go to C. Side by side on MBP5 (xb-auto.sh, same disk, same moment;
absolute scores move with the host's load, so only a pair compares):

| | before | with the FP gadgets |
|---|---|---|
| CPU test | 12.48 | 16.42 |
| GCD loop | 401.78 | 395.65 |
| Floating Point Basic | 6.26 | 26.53 |
| AltiVec Basic | 457.92 | 910.90 |
| vecLib FFT | 4.84 | 4.18 |
| Floating Point Library | 33.67 | 42.06 |
| Thread test | 58.60 | 58.01 |
| Memory test | 29.64 | 29.67 |

The gate and its controls: `../../bench-pm/fp/README.md`.

### 2 again: a TLB context for each set of segment registers (engine 9d4b46d897)

What the simulation promised, built: `tlb_context_switch()` sets the TLB and the jump cache
aside under the sixteen segment registers and takes up the pair kept under the new ones. One
binary, each machine alone: Memory test 30.8 to 38.3 (Allocate 15.2 to 33.2), Thread test 60.7
to 62.6; side by side, Quartz Graphics 18.0 to 23.6. Test, controls, the table of runs and
the two things the first numbers hid: `../../bench-pm/ctx/README.md`.

### 3: the insns that sent streams to TCG (engine 818dd75848)

Not more memory gadgets as first thought: the count of what TCG's TBs begin with said the
streams were leaving for a dozen insns the front end did not have (dst, mtocrf, isync, lvx and
stvx, mfmsr, mtsrin, mtmsr, icbi, dcbf under Mac OS X; addco, subfco and a conditional bcctr
in Mac OS 9's 68k emulator), and each visit cost two passes of the main loop. With gadgets
for them:

| Xbench, machine alone | FP only (27e0e02bb2), side by side | + TLB contexts | + these gadgets |
|---|---|---|---|
| CPU test | 16.4 | 18.06, 17.25 | 18.07, 17.65 |
| Thread test | 58.0 | 61.33, 63.96 | 63.16, 61.69 |
| Memory test | 29.7 | 38.44, 38.18 | 132.54, 128.62 |
| Allocate | 14.6 | 33.46, 32.93 | 41.55, 41.13 |
| Fill | 22.5 | 24.12, 23.91 | 264.30, 254.32 |
| Copy | 44.3 | 47.71, 48.09 | 371.52, 284.10 |
| Stream | 45.0 | 47.04, 46.74 | 203.76, 201.56 |

The main loop entered streams 115 million times and TCG's code 122 million over the run
before, 24 and 6.7 million after. Mac OS 9: 208 and 203 million in ninety seconds before, 12
and 7.7 after, and its desktop after about 30 s where it took about 50 (side by side). Test, controls and what
is still TCG's: `../../bench-pm/i3/README.md`.

`xb-auto.sh` now takes `TAG:ENGINE:VAR=VALUE` (one binary both ways), `XB_MODE=ui` (the Quartz
and user interface tests) and `SAMPLE_AT`/`SAMPLE_FOR`.

### On the M4 iPad Pro (2026-11-28, the user's run, the build with engine 818dd75848)

The user ran Xbench in the app on their iPad, the machine "Mac OS X Tiger" with the corrected
disk, and saved it in the guest as `benchmark2`. Read from a screenshot of the device:

| | M4 iPad, in the app | MBP5, the same engine |
|---|---|---|
| CPU test | 14.97 | 17.9 |
| GCD loop | 357.15 | 362 to 411 |
| Floating Point Basic | 23.72 | about 27 |
| AltiVec Basic | 864.14 | |
| vecLib FFT | 3.81 | |
| Floating Point Library | 38.99 | |
| Thread test | 53.32 (computation 214.24, lock contention 30.45) | 62.4 |
| Memory test | 101.66 | 130.6 |
| System | 72.40 (allocate 30.12, fill 225.25, copy 263.29) | (41, 254 to 264, 284 to 372) |
| Stream | 170.60 (copy 186.71, scale 154.72, add 186.12, triad 159.88) | about 202 |
| Quartz Graphics | 18.31 (line 20.19) | 23.6 |

The iPad comes out at about four fifths of MBP5 line for line. There is no run of the old
engine on the iPad to set beside it: the first run was not saved (nothing of it is on the
disk the iPad had). The CPU score is held where it is by vecLib FFT, 3.81 beside 357 and
864: AltiVec arithmetic is still TCG's.
