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
line identical, 16 of 16, as before; TLBFOLD 0 of 120000 wrong in 13 runs. Not
tried: the A10X, where a branch may do otherwise than on M-series cores.

