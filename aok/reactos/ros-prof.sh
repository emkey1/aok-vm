#!/bin/bash
# ros-prof.sh TAG [SECONDS] [ENV=VAL...] -- ReactOS booted as ros-stats.sh does, the host sampled (`sample`) for
# SECONDS (default 10) into ~/aok-vm-bench/ros-stats/prof-TAG/sample.txt: from QEMU's monitor coming up (the
# firmware, the boot loader and on), or with PHASE=kernel from the kernel's first line (its start, the drivers,
# the logon). A run gets one window: sampling sooner than the monitor stops dyld, and QEMU with it, and `sample`
# spends its first seconds reading the binary's symbols, which a short window loses. QEMU as in ros-stats.sh.
# Then: python3 vcpu-profile.py prof-TAG/sample.txt 25
B=$HOME/aok-vm-bench; PATH=/opt/homebrew/bin:$PATH
TAG=${1:?TAG}; SECS=${2:-10}; shift; [ $# -gt 0 ] && shift
W=$B/ros-stats/prof-$TAG; rm -rf "$W"; mkdir -p "$W"
qemu-img create -q -f qcow2 -b $B/reactos-build/reactos.qcow2 -F qcow2 "$W/ros.qcow2"
ROS_DIR=$W ROS_NONET=1 QEMU=${QEMU:-$B/build-aok-x64/qemu-system-x86_64} ROS_BIOS=$B/src-aok/pc-bios \
    bash "$(dirname "$0")/ros-run.sh" "$@" > "$W/qemu.out" 2>&1 &
PID=$!
n=0; until [ -S "$W/mon.sock" ] || [ $n -ge 300 ]; do sleep 0.1; n=$((n+1)); done
if [ "$PHASE" = kernel ]; then
    n=0; until grep -q . "$W/serial.log" 2> /dev/null || [ $n -ge 300 ]; do sleep 0.1; n=$((n+1)); done
fi
sample $PID "$SECS" -file "$W/sample.txt" > /dev/null 2>&1
echo quit | nc -U -w 2 "$W/mon.sock" > /dev/null; wait $PID
