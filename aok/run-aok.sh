#!/bin/bash
# run-aok.sh MODE WORKLOADS LOG [SECONDS] [extra qemu args...] -- boot-aok.sh with QEMU_AOK=MODE under a
# watchdog that is reaped.
W=$HOME/aok-vm-bench
mode=$1 wl=$2 log=$3 secs=${4:-600}; shift 4 2>/dev/null || shift $#
QEMU_AOK=$mode QEMU_AOK_STATS=1 "$W/boot-aok.sh" "$wl" "$@" > "$log" 2>&1 &
pid=$!
( sleep "$secs"; kill -9 $pid 2>/dev/null ) > /dev/null 2>&1 &
w=$!
wait $pid; rc=$?
kill $w 2>/dev/null
exit $rc
