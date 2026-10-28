#!/bin/bash
# ros-dis.sh TAG ADDR... -- ReactOS booted to explorer's desktop as ros-stats.sh does, then 48 bytes at each
# guest virtual ADDR (0x..., as ros-halt.sh's EIPs) read through QEMU's monitor and disassembled with
# Homebrew's llvm-mc (the AOK engine's QEMU has no disassembler). The kernel's and the HAL's code keep their
# addresses from boot to boot; a user program's address is read in whatever process is current.
#
# Out, in ~/aok-vm-bench/ros-stats/dis-TAG: bytes.txt, and the listing on stdout. QEMU, ROS_BASE and ROS_BIOS
# as in ros-stats.sh.
B=$HOME/aok-vm-bench; PATH=/opt/homebrew/bin:$PATH  # qemu-img
TAG=${1:?TAG}; shift
W=$B/ros-stats/dis-$TAG
rm -rf "$W"; mkdir -p "$W" || exit 1
qemu-img create -q -f qcow2 -b "${ROS_BASE:-$B/reactos-build/reactos.qcow2}" -F qcow2 "$W/ros.qcow2" || exit 1
ROS_DIR=$W ROS_NONET=1 QEMU=${QEMU:-$B/build-aok-x64/qemu-system-x86_64} ROS_BIOS=${ROS_BIOS:-$B/src-aok/pc-bios} \
    bash "$(dirname "$0")/ros-run.sh" > "$W/qemu.out" 2>&1 &
PID=$!
n=0; until grep -qF 'AllFolders\\Desktop' "$W/serial.log" 2> /dev/null || [ $n -ge 600 ]; do sleep 0.1; n=$((n+1)); done
{ for a in "$@"; do echo "x /48xb $a"; done; sleep 2; echo quit; } | nc -U "$W/mon.sock" > "$W/monitor.txt" 2>&1
wait $PID
# The monitor echoes with terminal escapes; its dump lines are "ADDRESS: 0xNN 0xNN ...".
tr -d '\r' < "$W/monitor.txt" | sed $'s/\x1b\\[[0-9;]*[A-Za-z]//g' | grep -E '^[0-9a-f]{8,16}:' > "$W/bytes.txt"
for a in "$@"; do
    echo "== $a"
    perl -ne 'BEGIN { $s = hex(shift @ARGV) } if (/^([0-9a-f]{8,16}):\s*(.*)/) { $v = hex($1); print "$2 " if $v >= $s && $v < $s + 48 } END { print "\n" }' \
        "$a" "$W/bytes.txt" | /opt/homebrew/opt/llvm/bin/llvm-mc --disassemble -triple=i386 -output-asm-variant=1 2> /dev/null |
        grep -v '^\s*\.text' | head -16
done
