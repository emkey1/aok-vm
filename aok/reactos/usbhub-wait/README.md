# The USB hub's start-up second, made a wait for the root hub

ReactOS 0.4.16's USB hub driver sleeps a fixed second the first time it is
asked for a root hub's devices, before the root hub has said it is ready
(`drivers/usb/usbhub/pnp.c`, USBH_FdoQueryBusRelations, "FIXME: this delay
makes devices discovery during early boot more reliable"). Only then: a
device plugged in later skips it (the flag it tests is set for good once the
root hub is ready), so the second is paid on every boot and only at boot.
In AOK VM's ReactOS machine it is on the boot's critical path, the vCPU
halted, because of the USB tablet (the pointer touch needs).

The driver already has the moment it waits for: the root hub's ready
callback (USBHUB_RootHubCallBack, run from usbport's 500 ms timer) sets
`RootHubNotificationEvent`, which registering the callback clears. So
`usbhub-wait.patch` waits on that event with the same one-second timeout:
the same start-up wait, ended when the root hub is ready.

## Measured (MBP5, the AOK engine at 11adf734f6, 2026-10-28)

Seconds to explorer's desktop (`ros-stats.sh`, six interleaved boots each):

| | desktop | QEMU's CPU time | tablet driver loaded |
|---|---|---|---|
| stock usbhub.sys | 9.72 to 9.98 | 7.37 to 7.47 | 6 of 6 |
| patched | 9.27 to 9.44 | 7.34 to 7.48 | 6 of 6 |

About half a second of waiting gone, for the same CPU time. The root hub
says it is ready about 0.7 s after its pipes open; a sleep of almost nothing
(the interval made 100 ns) times the same (9.28 to 9.48), so the event wait
loses nothing against no wait. What USB still costs (about 0.9 s against no
USB controller at all, 8.29 to 8.61) is that 0.7 s, the hub's 100 ms settle
and port reset, and a further half second before the HID driver loads.

## Booting from USB

The second was added for booting ReactOS from a USB stick (ReactOS commit
d14d7e5b8c, CORE-7826, failing on real hardware). `ros-run.sh` with
`ROS_USBDISK=uhci` or `ehci` boots the disk from a USB stick instead of IDE:
stock, patched, and with the sleep made almost nothing, all three reach the
desktop on both controllers (MBP5, the AOK engine, 2026-10-29). So QEMU does
not show the failure the second was for, and cannot show that the wait keeps
the fix; the wait still holds the query until the root hub is ready, which
is what the second gave the boot.

## Files

- `usbhub-wait.patch`: the change in ReactOS's source (0.4.16's
  `drivers/usb/usbhub/pnp.c`; the same as the change offered to ReactOS,
  emkey1/reactos branch `usbhub-root-hub-wait`, against master:
  https://github.com/reactos/reactos/pull/9751).
- `patch-sys.py IN OUT`: the same change made in 0.4.16's released
  usbhub.sys (from its CD), same length, the import call kept where its
  relocation is, the PE checksum redone. Refuses any other file.
- `patch-disk.sh DISK OUT`: a qcow2 overlay on an installed disk with the
  patched driver written over the old one, for `ros-stats.sh ROS_BASE=`,
  and for build.sh, which commits it into the disk it makes.

## Shipped

ReactOS.utm's disk has the patched driver from the image build.sh made on
2026-10-29 on (its step 6, checked in step 7: the tablet's driver loads).
The driver is GPL-2.0-or-later; its source is ReactOS 0.4.16's with
`usbhub-wait.patch`, and `patch-sys.py` is how the binary was made from
0.4.16's. The machine's notes point here (make-vm.py).
