#!/bin/bash
# ros-stats.sh TAG [IDLE] [ENV=VAL...] -- ReactOS.utm's disk booted to its desktop on the AOK engine, on a Mac,
# with QEMU_AOK_STATS=2: the time to the desktop, then IDLE seconds there (default 20), then quit, so that the
# engine prints its statistics and its list of the TCG blocks the main loop entered most -- what a stream
# could not go on through. The disk is an overlay on the finished one, which is left as it was.
#
#   ROS_BASE  the finished disk, default ~/aok-vm-bench/reactos-build/reactos.qcow2
#   QEMU      the engine's qemu-system-x86_64, default ~/aok-vm-bench/build-aok-x64/qemu-system-x86_64
#   ROS_BIOS  its pc-bios, default ~/aok-vm-bench/src-aok/pc-bios
#
# Out, in ~/aok-vm-bench/ros-stats/TAG: qemu.out (the statistics), serial.log (the guest's debug output),
# time.txt (seconds to the desktop, whether it got there, and QEMU's CPU time by then), timeline.txt (the
# guest's debug output, each line with the seconds since QEMU started). Extra arguments are environment settings for
# QEMU (QEMU_AOK=0 for TCTI alone). Then: python3 classify.py TAG/qemu.out 40 32
B=$HOME/aok-vm-bench; PATH=/opt/homebrew/bin:$PATH  # qemu-img
TAG=${1:?TAG}; IDLE=${2:-20}; shift; [ $# -gt 0 ] && shift
W=$B/ros-stats/$TAG
rm -rf "$W"; mkdir -p "$W" || exit 1
qemu-img create -q -f qcow2 -b "${ROS_BASE:-$B/reactos-build/reactos.qcow2}" -F qcow2 "$W/ros.qcow2" || exit 1
ROS_DIR=$W ROS_NONET=1 QEMU=${QEMU:-$B/build-aok-x64/qemu-system-x86_64} ROS_BIOS=${ROS_BIOS:-$B/src-aok/pc-bios} \
    bash "$(dirname "$0")/ros-run.sh" QEMU_AOK_STATS=2 "$@" > "$W/qemu.out" 2>&1 &
PID=$!
T0=$(date +%s)
touch "$W/serial.log"
(tail -F "$W/serial.log" 2> /dev/null | perl -MTime::HiRes=time -ne 'BEGIN { $| = 1; $t = time } printf "%7.2f %s", time - $t, $_' > "$W/timeline.txt") &
TL=$!
# The desktop: explorer has read the desktop folder's view settings (the last lines of a start, build.sh's
# serial.log). The firmware and boot loader print nothing, so the clock starts at QEMU's start.
UP=no
while kill -0 $PID 2> /dev/null && [ $(( $(date +%s) - T0 )) -lt 900 ]; do
    if grep -qF 'AllFolders\\Desktop' "$W/serial.log" 2> /dev/null; then UP=yes; break; fi
    sleep 1
done
T=$(( $(date +%s) - T0 )); CPU=$(ps -o time= -p $PID)
sleep "$IDLE"
echo quit | nc -U -w 2 "$W/mon.sock" > /dev/null
wait $PID
pkill -P $TL 2> /dev/null
D=$(grep -m1 -F 'AllFolders\\Desktop' "$W/timeline.txt" | awk '{ print $1 }')
echo "desktop $UP after ${D:-$T} s (QEMU's CPU time then $CPU); idle $IDLE s" | tee "$W/time.txt"
