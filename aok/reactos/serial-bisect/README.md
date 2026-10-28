# Build 11's silent COM1: the bisect kit

Under build 11's gadget engine (emkey1/qemu 8d8b2b621c) on the M4 iPad, ReactOS wrote no debug output on
COM1; under TCTI alone, and under 11adf734f6 either way, it writes all of it (../README.md, "The M4 iPad
Pro"). These find which commit between them changed that.

- `mac-build.sh`, `mac-test.sh` (MBP5): a Mac qemu-system-x86_64 from `~/aok-vm-bench/src-bisect` (a clone
  of src-aok) and ReactOS on it with the app's command line, COM1 a TCP server read with `nc -d`; exit 0
  if the output came. `ROS_S=N` starts it paused and resumes it N s later, as the app does; `ROS_L=DIR`
  takes the firmware from DIR. **The Mac does not show it** (2026-10-28): 8d8b2b621c prints 25 KB with
  the gadgets, started paused or not, with QEMU's firmware or UTM's.
- So the bisect is on the device: `ios-build.sh` (MBP5; build-engines.sh for x86_64 alone from
  src-bisect, fixed up into the sysroot), then `device-step.sh` (the Air; the engine into the app, the
  app built and installed, "ReactOS Timing C" read for 40 s; exit 0 if the output came). Afterwards put
  the real engine back: `AOK_GL=1 install-engines.sh ios-tci` on MBP5, rsync the x86_64 framework to
  the Air's sysroot, build-app.sh.
