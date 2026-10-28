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

## Files

- `usbhub-wait.patch`: the change in ReactOS's source (0.4.16's
  `drivers/usb/usbhub/pnp.c`).
- `patch-sys.py IN OUT`: the same change made in 0.4.16's released
  usbhub.sys (from its CD), same length, the import call kept where its
  relocation is, the PE checksum redone. Refuses any other file.
- `patch-disk.sh DISK OUT`: a qcow2 overlay on an installed disk with the
  patched driver written over the old one, for `ros-stats.sh ROS_BASE=`.

## Not shipped

ReactOS.utm's disk still has ReactOS's own driver. A changed GPL binary in
it would need its source published with it (ReactOS's source and this
patch; aok/TODO.md has the sources item), and the patch could go to ReactOS
itself, which is the user's call.
