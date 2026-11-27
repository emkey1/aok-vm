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

The pointer: Mac OS X has no driver for the virtio tablet, so in the app the guest's mouse
is the Power Mac's own USB mouse, relative. Keys through QMP work as they are.
