#!/bin/bash
# ros-halt.sh TAG [ENV=VAL...] -- ReactOS booted as ros-stats.sh does (the AOK engine, on a Mac), and QEMU's
# monitor asked `info registers` every 20 ms until explorer's desktop: whether the vCPU was halted (HLT=1, the
# guest waiting for an interrupt) and its EIP, each with the seconds since QEMU started. What `sample` calls
# __psynch_cvwait on the vCPU thread, put on the boot's timeline: halted time is the guest's own waiting (its
# timers, its sleeps), which no engine makes shorter, and the EIPs of the busy polls show where it runs.
#
# Out, in ~/aok-vm-bench/ros-stats/halt-TAG: halt.txt (seconds, HLT, EIP), timeline.txt (the guest's debug
# output, timed from the same start), and the halted share by half second. QEMU, ROS_BASE and ROS_BIOS as in
# ros-stats.sh; extra arguments are environment settings for QEMU.
B=$HOME/aok-vm-bench; PATH=/opt/homebrew/bin:$PATH  # qemu-img
TAG=${1:?TAG}; shift
W=$B/ros-stats/halt-$TAG
rm -rf "$W"; mkdir -p "$W" || exit 1
qemu-img create -q -f qcow2 -b "${ROS_BASE:-$B/reactos-build/reactos.qcow2}" -F qcow2 "$W/ros.qcow2" || exit 1
T0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
ROS_DIR=$W ROS_NONET=1 QEMU=${QEMU:-$B/build-aok-x64/qemu-system-x86_64} ROS_BIOS=${ROS_BIOS:-$B/src-aok/pc-bios} \
    bash "$(dirname "$0")/ros-run.sh" "$@" > "$W/qemu.out" 2>&1 &
PID=$!
touch "$W/serial.log"
(tail -F "$W/serial.log" 2> /dev/null | T0=$T0 perl -MTime::HiRes=time -ne 'BEGIN { $| = 1 } printf "%7.2f %s", time - $ENV{T0}, $_' > "$W/timeline.txt") &
TL=$!
n=0; until [ -S "$W/mon.sock" ] || [ $n -ge 500 ]; do sleep 0.02; n=$((n+1)); done
# One connection for the whole boot (the monitor takes one client at a time); each answer read up to its EFER
# line, which comes after HLT's. Stops at the desktop's line (two backslashes in the output) or after 60 s.
T0=$T0 W=$W perl -MIO::Socket::UNIX -MTime::HiRes=time,sleep -e '
    my $s = IO::Socket::UNIX->new(Peer => "$ENV{W}/mon.sock") or die "monitor: $!";
    $s->blocking(0);
    open(my $o, ">", "$ENV{W}/halt.txt") or die; select((select($o), $| = 1)[0]);
    my $end = time + 60;
    while (time < $end) {
        print $s "info registers\n";
        my $t = time - $ENV{T0}; my $got = ""; my $w = time + 1;
        while (time < $w) {
            my $r = sysread($s, my $c, 65536); $got .= $c if $r;
            last if $got =~ /HLT=\d/ && $got =~ /EFER=/;
            sleep 0.002;
        }
        my ($eip) = $got =~ /EIP=([0-9a-f]+)/; my ($h) = $got =~ /HLT=(\d)/;
        printf $o "%7.3f %s %s\n", $t, $h, $eip // "?" if defined $h;
        if (open(my $sl, "<", "$ENV{W}/serial.log")) { local $/; my $x = <$sl>; last if index($x, q(AllFolders\\\\Desktop)) >= 0 }
        sleep 0.02;
    }'
echo quit | nc -U -w 2 "$W/mon.sock" > /dev/null
wait $PID
pkill -P $TL 2> /dev/null
awk '{ b = int($1 / 0.5); n[b]++; if ($2 == 1) h[b]++; N++; if ($2 == 1) H++ }
     END { for (i = 0; i <= b; i++) if (n[i]) printf "%5.1f-%4.1f s  %3d%% halted\n", i * 0.5, i * 0.5 + 0.5, 100 * h[i] / n[i]
           printf "%d polls, halted in %d (%.0f%%)\n", N, H, 100 * H / N }' "$W/halt.txt"
