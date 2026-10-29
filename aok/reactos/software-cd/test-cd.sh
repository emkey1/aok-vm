#!/bin/bash
# test-cd.sh ISO [ROUNDS] -- make-cd.sh's CD tried on ReactOS's finished disk (an overlay) with no network, as on an
# iPad without one: Homebrew's QEMU, the CD where the app puts a machine's second IDE drive (ide.1), INSTALL.CMD
# typed in the Run box, a screenshot every 30 s for ROUNDS (default 20), a clean power-off, then the log, Program
# Files and the Start menu read off the disk from the Mac. On MBP5, beside ros-run.sh (../).
K=$(cd "$(dirname "$0")/.." && pwd); B=~/aok-vm-bench
ISO=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
export ROS_DIR=$B/ros-cd/run ROS_CD=$ISO ROS_NONET=1; W=$ROS_DIR
rm -rf $W; mkdir -p $W; cd $W
/opt/homebrew/bin/qemu-img create -q -f qcow2 -b ${ROS_BASE:-$B/reactos-build/reactos.qcow2} -F qcow2 ros.qcow2
QEMU=/opt/homebrew/bin/qemu-system-i386 bash $K/ros-run.sh > q.out 2>&1 &
mon() { echo "$1" | nc -U -w 1 $W/mon.sock > /dev/null; }
key() { # type a string through the monitor
    perl -e '
        my %m = (" "=>"spc", "/"=>"slash", "."=>"dot", "-"=>"minus", "\\"=>"backslash", ":"=>"shift-semicolon");
        for my $c (split //, $ARGV[0]) {
            my $k = $m{$c} // ($c =~ /[A-Z]/ ? "shift-" . lc $c : $c);
            print "sendkey $k\n";
        }' "$1" | while read -r l; do mon "$l"; sleep 0.05; done
}
for i in $(seq 120); do grep -qF 'AllFolders' serial.log 2>/dev/null && break; sleep 2; done
echo "[$(date +%T)] desktop"; sleep 10
mon "sendkey meta_l-r"; sleep 3
key "D:\\INSTALL.CMD"; sleep 1; mon "sendkey ret"
echo "[$(date +%T)] INSTALL.CMD"
for n in $(seq 1 ${2:-20}); do sleep 30; mon "screendump $W/s$n.ppm"; done
mon "system_powerdown"
for i in $(seq 90); do pgrep -f "ros-cd/run/ros.qcow2" > /dev/null || break; sleep 2; done
pkill -f "ros-cd/run/ros.qcow2"; sleep 1
for f in s*.ppm; do sips -s format png "$f" --out "${f%.ppm}.png" > /dev/null 2>&1; done
/opt/homebrew/bin/qemu-img convert -O raw ros.qcow2 ros.raw
dev=$(hdiutil attach -readonly -nomount -imagekey diskimage-class=CRawDiskImage ros.raw | awk 'NR==1{print $1}')
mnt=$(mktemp -d); mount -t msdos -r ${dev}s1 $mnt 2> /dev/null || mount_msdos -o rdonly ${dev}s1 $mnt
echo "== C:\\AOK-install.log"; tr -d '\r' < "$mnt/AOK-install.log"
echo "== Program Files"; ls "$mnt/Program Files"
echo "== Start menu"; ls "$mnt/Documents and Settings/All Users/Start Menu/Programs"
ls -d "$mnt/Python34" "$mnt/tcc" "$mnt/Program Files/OpenTTD/baseset/"* 2>&1
umount $mnt; hdiutil detach $dev > /dev/null; rm -f ros.raw
