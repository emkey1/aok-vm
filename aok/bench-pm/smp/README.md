# A dual G4: two CPUs on mac99

emkey1/qemu `aok-vm` fa91339fb7 (`docs/devel/aok-gadgets-ppc.rst`, "Two CPUs: a
dual G4"). The protocol is Apple's `MacRISC2CPU` (AppleMacRISC2PE, open
source): a second `/cpus` node, KeyLargo's GPIO `0x5C` strobing CPU 1's SRESET,
GPIO `0x73` as the timebase enable, and a per-CPU OpenPIC. 32-bit PowerPC runs
its CPUs in parallel (MTTCG) and the front end's `stwcx.` is a compare-and-swap.

| file | what |
|---|---|
| `smp0.py`, `smp1.py`, `smp2.py` | the patches as applied to a tree (experiment 0; the machine; MTTCG and `stwcx.`) |
| `smp-build.sh` | the engine with them as `src-smp` / `build-smp` on MBP5 (PowerPC only, with slirp for ssh) |
| `x1.sh`, `x2.sh` | Tiger booted verbosely on two CPUs, pictures every 15 s; the monitor's view of both CPUs |
| `x4.sh`, `x5.sh` | Tiger on N CPUs: in its Terminal, or left running with ssh at 127.0.0.1:2224 |
| `smpstress.c` | threads incrementing shared counters (OSAtomicIncrement32, a mutex, an OSSpinLock, and one unprotected); built with Xcode 2.5's GCC in Tiger |
| `par.sh` | a shell loop alone, two at once, four at once |
| `xb-smp.sh` | Xbench under Tiger, one CPU and two, each alone, in turn, twice |
| `chain-smp.sh` | every PowerPC gate on the engine, one CPU, and Mac OS 9 |
| `rename-user.sh` | Tiger's account renamed (timcook to mke), its group, groups, home and auto-login |

## How it was found working (2026-11-28)

1. QEMU stopped with two CPUs: the OpenPIC was built for one ("Only UP
   supported today") and every output set was wired to the last CPU created.
2. Tiger then booted but waited for its disk for ever: interrupts went to CPU
   1, which was released (it took the reset, NIP `0x100`, Mac OS X's start
   handler at `0xF0` armed) but never ran. The halt request queued while it
   was held was taken as it first ran and halted it again. The same with the
   gadgets off, so not the engine.
3. Then it started both CPUs and crawled: both CPUs sat in `hw_rem_map` and
   `hw_protect_gv`, around the `tlbie` lock at `0x5180`. Taking turns on one
   thread, every `sync` handed the thread to the other CPU, which spun on the
   lock for a 100 ms slice. MTTCG ended it.
4. ssh "failed" only because a test used another MAC address: Tiger named the
   card `en2`, unconfigured.

## Results

* Tiger: `hw.ncpu` and `hw.activecpu` 2 on MBP5, the M4 iPad, the A10X and the
  A9 iPad.
* smpstress: exact counts with 2 and 4 threads everywhere; the unprotected
  counter loses updates (about 1,500 of 4,000,000 on MBP5), so the CPUs run at
  once.
* A shell loop, alone / two at once / four at once: MBP5 10 / 12 / 26 s; M4
  12 / 15 / 34 s; A10X 29 / 40 / 93 s; A9 (two cores in all) 70 / 124 / 298 s.
* Xbench on MBP5, one CPU against two, alone, in turn (run 1, run 2): thread
  test 71.4, 65.3 against 122.9, 96.2; computation 259, 241 against 438, 326;
  lock contention 41.4, 37.7 against 71.5, 56.4. The CPU test (one thread) 63.7,
  58.7 against 60.9, 36.4; the second two-CPU run was low on every line, the
  host busy.
* One CPU as before: the kit's transcripts (166 lines), fpstress, vectest,
  avstress (720 lines) and ctxtest (four ways) identical; Mac OS 9 to its
  desktop.

The app gives a mac99 machine one CPU unless two are set, and never more
(`UTMQemuConfiguration+Arguments.swift`, `emulatedCpuCount`).
