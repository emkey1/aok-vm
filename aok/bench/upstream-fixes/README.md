# Tests for what came from upstream on 2026-11-01

Each failed on the engine before the fix (11adf734f6) and passes after. None is part of a gate.

| | |
|---|---|
| `x86upfix.c` | every x87 compare's C1, and RET, RETF and ENTER counts of 0x8000 and up. Run it on a real x86 and in a guest, and diff the transcripts: QEMU_AOK=1 must match the hardware on every line. With QEMU_AOK=0, TCG differs where the stack is empty, because it has no x87 stack faults. |
| `usbcsw.c` | a USB stick's status request queued with its data transfer, through usbfs, in a guest with `-device qemu-xhci -device usb-storage`. The stick's image holds each block's number in the block's first four bytes. Needs the modules `xhci_pci` and `usbcore`, and no `usb_storage`. |
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

