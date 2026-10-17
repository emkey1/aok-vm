# AOK VM

A fork of [UTM](https://github.com/utmapp/UTM)'s iOS "SE" edition (the one
that runs with no JIT) built around another engine: QEMU with the *AOK
gadgets*, which translate a guest's code into threaded code instead of
interpreting QEMU's intermediate form. On the same programs they need 1.6
to 3.6 times fewer host cycles than the interpreter UTM SE ships, for
RISC-V, ARM64, x86-64 and 32-bit x86 guests (`docs/engine-study.md` has the
tables and how they were measured).

It is three repositories:

| | |
|---|---|
| this one | the app: UTM's front end with this fork's changes (`git log 7eadb056..`), and under `aok/` everything that builds, packages and measures it |
| [emkey1/qemu](https://github.com/emkey1/qemu) | the engine: QEMU 11 (the tctiSH fork) with the gadget front ends, `docs/devel/aok-gadgets.rst` there; `aok/ENGINE` names the commit this app is built with |
| emkey1/aok-gadgets | the gadget sources that iSH-AOK's own JIT and the engine both build |

## Building

1. **Dependencies.** UTM's prebuilt sysroot for the platform, unpacked at
   the repository's root (`aok/app/build-app.sh` says where it comes from).
2. **Engines.** `aok/app/build-engines.sh [ios-tci|ios_simulator-tci]`
   cross-builds the QEMU of `aok/ENGINE` against that sysroot, and
   `install-engines.sh` puts it in as the sysroot's riscv64, aarch64,
   x86_64 and i386 QEMU (a 32-bit PC guest runs on the x86-64 engine).
3. **The app.** Open `UTM.xcodeproj`, choose the scheme **AOK VM** and a
   device, Run. Or `aok/app/build-app.sh device|sim`, which also writes
   `CodeSigning.xcconfig` when there is none.

It needs the released Xcode 27. Step 2 is not part of the Xcode build yet
(`TODO.md`).

## Releasing

1. Raise `CURRENT_PROJECT_VERSION` in `Build.xcconfig` (App Store Connect
   takes each build number once), commit, push.
2. `bash aok/release.sh` on the Mac that signs: one archive, and from it
   the App Store IPA (upload it to TestFlight with Apple's Transporter) and
   the sideloaders' IPA, `AOK-VM-VERSION-BUILD.ipa`
   (`aok/app/sideload-ipa.sh`: ad hoc signed with the app's entitlements,
   so that AltStore and the like give it its App Groups).
3. Try the build from TestFlight's internal testing.
4. `bash aok/release.sh publish`: the GitHub release `vVERSION-BUILD`
   with the sideloaders' IPA and `aok/RELEASE-NOTES.md`, at the commit it
   was built from (the archive is not made again). The IPA is attached
   twice, the second time as `AOK-VM.ipa`: the name the permanent link
   https://github.com/emkey1/aok-vm/releases/latest/download/AOK-VM.ipa
   fetches from whichever release is the latest.

No CI builds it: the engines and the sysroot are built outside Xcode, on
two Macs (`TODO.md`).

## What is under `aok/`

| | |
|---|---|
| `release.sh` | a release: the archive, the App Store IPA, the sideloaders' IPA, and with `publish` the GitHub release ("Releasing" above) |
| `app/` | the engine build and install, the app build, `start-vm.sh` (start a machine with no tap), `sideload-ipa.sh`, `install-app.sh` (app and machines onto a device), `make-vm.py` (ready-made machines: the Alpine console guests of all four architectures, Devuan with a desktop), and what builds the Devuan disks |
| `reactos/` | ReactOS for the PC machines: `build.sh` makes the installed disk that `make-vm.py` puts in "ReactOS.utm", from the release CD, by itself |
| `icon/` | the icon's sources |
| `docs/engine-study.md` | the whole account: why, each front end, results, the bugs worth remembering |
| `TODO.md` | what is open |
| `cyc4.sh`, `race.sh`, `cycwrap.c`, `summarize.py` | the benchmarks: host CPU cycles per workload, engine against engine |
| `bench/` | what runs inside a guest: the workloads, and the test programs whose transcripts are the gates (`fptest`, `memtest`, `simdtest`, `x86test`, `poke`) |
| `a64/`, `x64/` | the gates: a guest's transcript under the gadgets against the same binary with them off |
| `ios-app/` | the same gates and workloads on a device, in a test app that loads the engine |
| `setup-roots.sh`, `update-roots.sh` | build the guests' root images |

Two things these lean on that are not here. The guests' root images are
made with iSH-AOK's command-line build (`~/git/ish-AOK/build/ish`), and
`race.sh` times iSH-AOK itself beside the QEMU engines, which is where this
started. And a Devuan machine's own tools are iSH-AOK's `/AOK/tools`; the
script that refreshes them inside a machine (`aok-update`) is kept there,
at the address installed machines fetch it from.

The scripts keep their working files outside the tree: `~/aok-vm-bench` on
the Mac that cross-builds (QEMU builds, guest images, logs) and `~/aok-vm-work`
on the Mac that signs (derived data, machine bundles).

## Licences

The app is UTM's, under UTM's licence (Apache 2.0, `LICENSE` at the root),
and this fork's changes to it are offered under the same. What is under
`aok/` was written in iSH-AOK's repository and came here under its licence
(`aok/LICENSE.md`: GPLv3, and GPLv2 as well). QEMU's and the gadget
sources' are in their own repositories.
