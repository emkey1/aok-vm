#!/bin/bash
# get-test.sh DISK [ROUNDS] -- "Get Programs" tried on DISK (put-on-disk.sh's, or build.sh's reactos.qcow2; an
# overlay of it) with the network, as a user would: Homebrew's QEMU with its user-mode network, the desktop's
# "Get Programs" typed in the Run box, a key for its "press a key to start", a screenshot every 30 s for ROUNDS
# (default 40), a key for INSTALL.CMD's closing pause, a clean power-off, then both logs, Program Files and the
# Start menu read off the disk from the Mac. On MBP5, beside ros-run.sh (../).
K=$(cd "$(dirname "$0")/.." && pwd); B=~/aok-vm-bench
DISK=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
export ROS_DIR=$B/ros-get/run; W=$ROS_DIR
rm -rf $W; mkdir -p $W; cd $W
/opt/homebrew/bin/qemu-img create -q -f qcow2 -b "$DISK" -F qcow2 ros.qcow2
QEMU=/opt/homebrew/bin/qemu-system-i386 bash $K/ros-run.sh > q.out 2>&1 &
mon() { echo "$1" | nc -U -w 1 $W/mon.sock > /dev/null; }
key() { # type a string through the monitor
    perl -e '
        my %m = (" "=>"spc", "/"=>"slash", "."=>"dot", "-"=>"minus", "\\"=>"backslash", ":"=>"shift-semicolon",
                 "\""=>"shift-apostrophe");
        for my $c (split //, $ARGV[0]) {
            my $k = $m{$c} // ($c =~ /[A-Z]/ ? "shift-" . lc $c : $c);
            print "sendkey $k\n";
        }' "$1" | while read -r l; do mon "$l"; sleep 0.05; done
}
for i in $(seq 120); do grep -qF 'AllFolders' serial.log 2>/dev/null && break; sleep 2; done
echo "[$(date +%T)] desktop"; sleep 10
mon "screendump $W/desktop.ppm"
mon "sendkey meta_l-r"; sleep 3
key '"C:\Documents and Settings\All Users\Desktop\Get Programs.cmd"'; sleep 1; mon "sendkey ret"
sleep 10; mon "screendump $W/s0.ppm"; mon "sendkey ret"
echo "[$(date +%T)] Get Programs"
for n in $(seq 1 ${2:-40}); do sleep 30; mon "screendump $W/s$n.ppm"; done
mon "sendkey ret"; sleep 5
mon "system_powerdown"
for i in $(seq 90); do pgrep -f "ros-get/run/ros.qcow2" > /dev/null || break; sleep 2; done
pkill -f "ros-get/run/ros.qcow2"; sleep 1
for f in *.ppm; do sips -s format png "$f" --out "${f%.ppm}.png" > /dev/null 2>&1; done
rm -f ./*.ppm
/opt/homebrew/bin/qemu-img convert -O raw ros.qcow2 ros.raw
dev=$(hdiutil attach -readonly -nomount -imagekey diskimage-class=CRawDiskImage ros.raw | awk 'NR==1{print $1}')
mnt=$(mktemp -d); mount -t msdos -r ${dev}s1 $mnt 2> /dev/null || mount_msdos -o rdonly ${dev}s1 $mnt
for f in AOK-get.log AOK-install.log; do echo "== C:\\$f"; tr -d '\r' < "$mnt/$f"; done
echo "== C:\\AOK\\Programs"; ls "$mnt/AOK/Programs" "$mnt/AOK/Programs/SETUP" "$mnt/AOK/Programs/ZIPS" "$mnt/AOK/Programs/APPS"
echo "== Program Files"; ls "$mnt/Program Files"
echo "== Start menu"; ls "$mnt/Documents and Settings/All Users/Start Menu/Programs"
ls -d "$mnt/Python34" "$mnt/tcc" "$mnt/Program Files/OpenTTD/baseset/"* 2>&1
umount $mnt; hdiutil detach $dev > /dev/null; rm -f ros.raw
