#!/bin/bash
# patch-disk.sh DISK OUT -- OUT: a qcow2 overlay on DISK (an installed ReactOS 0.4.16 disk, build.sh's
# reactos.qcow2) whose system32\drivers\usbhub.sys is patch-sys.py's. The driver's bytes are found on the
# disk by their contents (the file system's clusters of it are contiguous on build.sh's disk) and written
# over in the overlay with qemu-io; DISK is left as it was. Needs the ReactOS 0.4.16 CD's usbhub.sys:
# USBHUB_SYS, default ~/aok-vm-bench/usbhub-exp/reactos/system32/drivers/usbhub.sys (bsdtar -xf the ISO).
# For experiments on a Mac (ros-stats.sh with ROS_BASE=OUT), and build.sh's step 6 (then committed into DISK).
set -e
PATH=/opt/homebrew/bin:$PATH
DISK=${1:?DISK}; OUT=${2:?OUT}
here=$(cd "$(dirname "$0")" && pwd)
SYS=${USBHUB_SYS:-$HOME/aok-vm-bench/usbhub-exp/reactos/system32/drivers/usbhub.sys}
T=$(mktemp -d "${TMPDIR:-/tmp}/usbhub.XXXXXX"); trap 'rm -rf "$T"' EXIT
python3 "$here/patch-sys.py" "$SYS" "$T/usbhub.sys"
qemu-img convert -O raw "$DISK" "$T/disk.raw"   # sparse
AT=$(python3 - "$T/disk.raw" "$SYS" <<'EOF'
import mmap, sys
f = open(sys.argv[1], "rb"); m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
d = open(sys.argv[2], "rb").read()
at = m.find(d)
if at < 0 or m.find(d, at + 1) >= 0:
    sys.exit("usbhub.sys is not on the disk exactly once, whole")
print(at)
EOF
)
rm -f "$T/disk.raw" "$OUT"
qemu-img create -q -f qcow2 -b "$(cd "$(dirname "$DISK")" && pwd)/$(basename "$DISK")" -F qcow2 "$OUT"
qemu-io -c "write -s $T/usbhub.sys $AT $(wc -c < "$T/usbhub.sys")" "$OUT" | head -1
