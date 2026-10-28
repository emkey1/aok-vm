#!/bin/bash
# rapps-probe.sh PKG...: ReactOS's finished disk (an overlay) on Homebrew's QEMU with the network, RAPPS asked to
# install PKGs silently from the Run box, screenshots every 30 s, then a clean power-off and the disk's
# Program Files listed from the Mac.
K=$(cd "$(dirname "$0")" && pwd); B=~/aok-vm-bench; export ROS_DIR=$B/ros-sw/run; W=$ROS_DIR
rm -rf $W; mkdir -p $W; cd $W
/opt/homebrew/bin/qemu-img create -q -f qcow2 -b $B/reactos-build/reactos.qcow2 -F qcow2 ros.qcow2
QEMU=/opt/homebrew/bin/qemu-system-i386 bash $K/ros-run.sh > q.out 2>&1 &
mon() { echo "$1" | nc -U -w 1 $W/mon.sock > /dev/null; }
key() { # type a string through the monitor
    perl -e '
        my %m = (" "=>"spc", "/"=>"slash", "."=>"dot", "-"=>"minus", "\\"=>"backslash", ":"=>"shift-semicolon",
                 ">"=>"shift-dot", "\""=>"shift-apostrophe", "&"=>"shift-7", "_"=>"shift-minus", "="=>"equal",
                 "+"=>"shift-equal", "*"=>"shift-8", "("=>"shift-9", ")"=>"shift-0", ","=>"comma", ";"=>"semicolon");
        for my $c (split //, $ARGV[0]) {
            my $k = $m{$c} // ($c =~ /[A-Z]/ ? "shift-" . lc $c : $c);
            print "sendkey $k\n";
        }' "$1" | while read -r l; do mon "$l"; sleep 0.05; done
}
for i in $(seq 120); do grep -qF 'AllFolders' serial.log 2>/dev/null && break; sleep 2; done
echo "[$(date +%T)] desktop"; sleep 10
mon "sendkey meta_l-r"; sleep 3
key "rapps /INSTALL /S $*"; sleep 1; mon "sendkey ret"
for n in $(seq 1 ${ROUNDS:-12}); do sleep 30; mon "screendump $W/s$n.ppm"; done
mon "system_powerdown"
for i in $(seq 90); do kill -0 $(pgrep -f "ros-sw/run/ros.qcow2" | head -1) 2>/dev/null || break; sleep 2; done
pkill -f "ros-sw/run/ros.qcow2"; sleep 1
/opt/homebrew/bin/qemu-img convert -O raw ros.qcow2 ros.raw
dev=$(hdiutil attach -readonly -nomount -imagekey diskimage-class=CRawDiskImage ros.raw | awk 'NR==1{print $1}')
mnt=$(mktemp -d); mount -t msdos -r ${dev}s1 $mnt 2>/dev/null || mount_msdos -o rdonly ${dev}s1 $mnt
ls "$mnt/Program Files" "$mnt/ReactOS/Downloads" 2>&1 | head -40
ls "$mnt/Documents and Settings/Administrator/Desktop" 2>&1 | head
umount $mnt; hdiutil detach $dev > /dev/null; rm -f ros.raw
