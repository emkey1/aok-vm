#!/bin/bash
# ros-device.sh DEVICE NAME TAG -- ReactOS booted to its desktop in AOK VM on a device, timed from the Mac it is
# connected to: the time from the launch (start-vm.sh) to explorer's desktop, by the guest's debug output.
#
# NAME is a machine whose serial port is a TCP server on port 4555 that accepts connections from elsewhere
# ("Serial": [{"Mode": "TcpServer", "Target": "Auto", "TcpPort": 4555, "RemoteConnectionAllowed": true}]):
# COM1, where ReactOS writes its debug output, as ros-run.sh's -serial file: does on a Mac. The installed disk
# has known COM1 since build.sh's install, so the port adds no new hardware. The script connects as soon as the
# app listens (ROS_HOST, or each link-local neighbour of the Mac in turn, after a ping of the link's
# broadcast address puts them in the ARP table) and stops at the line that ros-stats.sh
# stops at; the guest's output from before the connection is lost, which is the firmware's and the boot
# loader's (they print nothing) and the kernel's first lines. Then the app is ended (start-vm.sh --stop, which
# leaves the bench app holding the screen).
#
# Out, in ~/aok-vm-work/ros-device/TAG: timeline.txt (each line of the guest's output with the seconds since the
# launch) and time.txt (seconds to the desktop, and to the first line read).
#
# The network side is nc and the clock perl: macOS's local network privacy keeps a python3 from the link
# (its connections fail, and even the arp it runs prints nothing), while the system's own tools may use it.
dev=${1:?DEVICE}; name=${2:?NAME}; tag=${3:?TAG}
here=$(cd "$(dirname "$0")" && pwd)
W=$HOME/aok-vm-work/ros-device/$tag
rm -rf "$W"; mkdir -p "$W" || exit 1
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
T0=$(now)
bash "$here/../app/start-vm.sh" "$dev" "$name" > /dev/null 2>&1 || { echo "start-vm.sh failed"; exit 1; }
host=$ROS_HOST
while :; do
    if [ -n "$host" ]; then nc -z -G 1 "$host" 4555 2> /dev/null && break
    else
        ping -c 1 -t 1 169.254.255.255 > /dev/null 2>&1
        for ip in $(arp -an | awk '/169\.254\./ && !/permanent/ && !/incomplete/ && !/255\.255/ { gsub(/[()]/, "", $2); print $2 }'); do
            nc -z -G 1 "$ip" 4555 2> /dev/null && { host=$ip; break; }
        done
        [ -n "$host" ] && break
    fi
    [ "$(perl -e "print $(now) - $T0 > 180 ? 1 : 0")" = 1 ] && { echo "no serial port answered on 4555"; exit 1; }
    sleep 0.2
done
TC=$(perl -e "printf '%.2f', $(now) - $T0")
# Each line with its time; at the desktop's line (two backslashes in the output, as ros-stats.sh greps for)
# perl says when and stops, and nc goes at its next write. nc -d: without it nc closes its side at the end of
# its input, and QEMU takes that for the end of the connection and sends nothing more.
nc -d "$host" 4555 | T0=$T0 TC=$TC perl -MTime::HiRes=time -e '
    $| = 1; alarm 600; open(my $tl, ">", "$ARGV[0]/timeline.txt") or die; select((select($tl), $| = 1)[0]);
    while (<STDIN>) {
        my $s = time - $ENV{T0}; $first //= $s;
        printf $tl "%7.2f %s", $s, $_;
        if (index($_, q(AllFolders\\\\Desktop)) >= 0) { $desk = $s; last }
    }
    printf "%s (connected %s s, first line %.2f s after the launch)\n",
        defined $desk ? sprintf("desktop after %.2f s", $desk) : "no desktop", $ENV{TC}, $first // -1;
' "$W" | tee "$W/time.txt"
bash "$here/../app/start-vm.sh" "$dev" --stop > /dev/null 2>&1 &
