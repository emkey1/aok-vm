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
