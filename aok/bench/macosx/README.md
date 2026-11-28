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

The network (2026-11-28): the machine's card (sungem) is `en1`, "PCI Ethernet Slot ethernet",
a port the installed system had never seen, so it stayed down until Network in System
Preferences was opened, "New Port Detected" answered and the change applied (the user did
that by hand on the iPad, choosing DHCP). `macosx/work/tiger-final3.qcow2` (sha256
098cdce4...) is tiger-final2 with that done: started on Homebrew's QEMU with `-netdev user`
and the card, the dialog's OK clicked (`rel.py`: the relative mouse in small steps, about
0.18 of a pixel a unit across and 0.3 down), the pane quit with Apply, shut down from the
Apple menu. A fresh start of it has 10.0.2.15 by DHCP and `curl -I example.com` answers 200.
The test runs here start the machine with `-nic none`, which is why this was not seen.

**tigersrc and ssh (2026-11-28; the user chose tigersrc over Tigerbrew).** `tiger-final5.qcow2`
(sha256 bddf82b3...) is tiger-final3 with:
- tigersrc, pkgsrc built for 10.4 PowerPC (netbsd.org/~nia/tigersrc): its bootstrap kit
  (`bootstrap-tiger.tar.gz`, 9.0 MB, sha256 e2ab37b6...; only `./usr/pkg` taken from it) and
  curl, wget, openssh and python310 from its repository (`tigersrc-setup.sh`). PATH and
  PKG_PATH in `~/.bash_profile`. OpenSSL then updated from the repository (3.1.5 to 3.3.7):
  the kit's is older than what Python's `_ssl` was built against
  (`Symbol not found: _X509_STORE_get1_objects`). **pkg_install must stay the kit's
  (20240307):** the repository's 20241101 was built without SSL, and with it `pkg_add` fails
  on the https PKG_PATH ("SSL support disabled ... Authentication error"). That run was
  thrown away; never `pkg_add -u` everything.
- its OpenSSH 9.9p2 as the ssh server (`sshd-setup.sh`): host keys made in the image, a
  launchd job `/Library/LaunchDaemons/org.pkgsrc.sshd.plist`, and in `sshd_config` keys only
  (the pkgsrc sshd has no PAM and cannot check Tiger's passwords) and `SetEnv` of PATH and
  PKG_PATH so that plain `ssh host cmd` finds pkg_add. `authorized_keys` holds the user's
  own keys (the Air's id_ed25519 and id_rsa). sudo's password is the account's ("password").
- the machine's config forwards the iPad's TCP 2222 to the guest's 22.

Checked on fresh starts: sshd up by itself, the user's key in and a test key refused, a real
`pkg_add zip` and `pkg_delete zip` through sudo, Python's ssl fetching https. On both iPads
2026-11-28 (the user: overwrite if pkg_add works and sshd is on). The M4: `ssh -p 2222
timcook@m4pt` from the Air (Tailscale) answers. The A10X could not be reached by any network
that day (Wi-Fi "host is down", Tailscale timing out) and its cable link had only IPv6, which
QEMU's `hostfwd` does not listen on; its debug.log has `hostfwd=tcp::2222-:22`.

A saving trap met here: osx-run.sh runs a machine on an overlay (`run/TAG.qcow2`), so
changes made in it are not in the image it was started from until that overlay is committed;
a disk once renamed under a live overlay was kept without them.

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

### 4: AltiVec arithmetic (engine dd744be8ea)

After the three steps the CPU score was held down by vecLib FFT (4.4 beside 400 and 900):
AltiVec arithmetic was TCG's, softfloat a lane at a time, and a stream stopped at it. The
user asked for gadgets (2026-11-28). Every AltiVec insn of a G4 is one now, on the host's
vector unit. Side by side on MBP5, the engine before and this one (`xb-auto.sh va:av vb:i3`,
then with `XB_MODE=ui`):

| | before | with the AltiVec gadgets |
|---|---|---|
| CPU test | 17.45 | 62.82 |
| GCD loop | 421.30 | 398.79 |
| Floating Point Basic | 30.09 | 30.59 |
| AltiVec Basic | 926.70 | 918.29 |
| vecLib FFT | 4.42 (146 Mflop/s) | 50.60 (1.67 Gflop/s) |
| Floating Point Library | 42.81 | 42.48 |
| Thread test | 60.21 | 62.75 |
| Memory test | 128.56 | 128.64 |
| Quartz Graphics | 29.10 (line 31.96, rectangle 22.29, circle 26.47, bezier 44.68, text 28.18) | 31.65 (33.80, 25.08, 30.83, 45.68, 29.24) |
| User Interface | 9.74 | 9.94 |

No FP vector went to QEMU's helpers in the run. The main loop entered TCG's code 3.4 million
times where it was 6.6 million; half of what is left is `sc` and a third the decrementer's
`mfspr`. AltiVec Basic did not move: at 37 Gflop/s under an interpreter it can hardly be doing the
arithmetic it counts (not looked into).
The test and its 38 controls: `../../bench-pm/av/README.md`.

**The GCD loop line, alone and in turn** (`../../bench-pm/av/gcd-ab.sh`; the user's M4 iPad read
it a fifth lower with the AltiVec gadgets, twice, against one run without). On MBP5, each
machine by itself, the engine before and with the gadgets alternately:

| | before | with the AltiVec gadgets |
|---|---|---|
| GCD loop | 424.38, 347.25 | 418.63, 450.60 |
| CPU test | 18.08, 18.28 | 62.52, 61.66 |
| vecLib FFT | 4.58, 4.64 | 49.36, 53.78 |
| AltiVec Basic | 512.34, 951.54 | 916.03, 969.47 |
| Floating Point Basic | 32.18, 31.43 | 30.68, 26.98 |
| Thread test, computation | 265.58, 256.05 | 126.83, 253.33 |

No difference between the engines in the GCD loop; it moves by a quarter between runs of
one engine (321 and 328 in the pair below, both engines with the gadgets). Why it moves
that much is not known. AltiVec Basic and the thread test's computation each read half once.

### 5: sc, the decrementer, tlbie, tlbsync, lswx (engine 61cda07b7b)

What still began TCG's TBs after step 4. Side by side with the engine of step 4
(`xb-auto.sh sa:sv sb:av`): CPU test 59.56 against 49.81 (vecLib FFT 50.47 against 27.63,
which is that line's spread: 49 and 54 alone, above), GCD loop 321.23 against 328.34,
Floating Point Basic 27.25 against 27.43, thread test 59.77 against 61.09, memory test 127.33
against 129.99 (allocate 40.53 against 41.07). Nothing moved: Xbench's tests are loops of a
user's code. TCG's code was entered 44,920 times in the run against 3,285,673.
`../../bench-pm/sv/README.md`.

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
| Quartz Graphics | 18.31 (line 20.19, rectangle 11.61, circle 16.42, bezier 29.96, text 23.19) | 23.6 |
| OpenGL Graphics | 14.75 (spinning squares, 18.71 frames/s) | |
| User Interface | 7.36 (elements, 33.77 refreshes/s) | |
| Disk test | 82.28 | |
| Sequential | 49.30 (uncached write 22.10 at 4K, 431.63 at 256K; read 31.59, 522.37) | |
| Random | 248.43 (uncached write 75.47 at 4K, 732.57 at 256K; read 1251.81, 1456.02) | |

**The same iPad with the AltiVec gadgets (engine dd744be8ea, the user's second run, 2026-11-28):**

| | engine 818dd75848 | engine dd744be8ea |
|---|---|---|
| CPU test | 14.97 | 56.19 |
| GCD loop | 357.15 | 283.53 |
| Floating Point Basic | 23.72 | 26.95 |
| AltiVec Basic | 864.14 | 458.83 |
| vecLib FFT | 3.81 | 48.27 |
| Floating Point Library | 38.99 | 39.26 |
| Thread test | 53.32 (214.24, 30.45) | 51.90 (221.18, 29.40) |
| Memory test | 101.66 | 100.48 |
| System | 72.40 (30.12, 225.25, 263.29) | 70.41 (30.40, 224.46, 190.17) |
| Stream | 170.60 (186.71, 154.72, 186.12, 159.88) | 175.36 (187.63, 154.52, 186.22, 177.33) |
| Quartz Graphics | 18.31 (line 20.19) | 19.83 (line 22.16) |

Two more runs of the user's on the same iPad: a second with engine dd744be8ea (CPU 46.50, GCD
loop 287.28, AltiVec Basic 859.43, vecLib FFT 31.25, System Copy 299.46, Quartz 19.59), and
one with engine 61cda07b7b (CPU 47.58, GCD loop 361.52, Floating Point Basic 23.01, AltiVec
Basic 789.51, vecLib FFT 31.00, Floating Point Library 39.45, thread 52.59, memory 102.52,
System Copy 245.28, Quartz 19.97). So the GCD loop read 357, 284, 287 and 362 over four runs,
the last three all with the AltiVec gadgets: the spread of the line, as on MBP5, and no loss.

One run of each, not at the same time. vecLib FFT and the CPU score moved as on MBP5. Three
lines read lower, AltiVec Basic by half, GCD loop by a fifth and System Copy by a quarter,
where MBP5's side-by-side pair had them level (918 against 927, 399 against 421): not
explained. GCD loop has no AltiVec in it, and these lines have moved this much between
identical runs before, so the iPad's scheduling is the first suspect; a second run would say.

The iPad comes out at about four fifths of MBP5 line for line. There is no run of the old
engine on the iPad to set beside it: the first run was not saved (nothing of it is on the
disk the iPad had). The CPU score is held where it is by vecLib FFT, 3.81 beside 357 and
864: AltiVec arithmetic is still TCG's.
