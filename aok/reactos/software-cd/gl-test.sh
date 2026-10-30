#!/bin/bash
# gl-test.sh DL [ROUNDS] -- OpenGL in the ReactOS machine, with ReactOS's own (Mesa 2.6, OpenGL 1.1, on the CPU)
# and with Mesa 17's llvmpipe (RAPPS's mesagallium): a CD of GLTEST.CMD, DL/mesa3d_setup.exe, DL/wglgears.exe and,
# if it is there, DL/lzdoom-installer.exe, GLTEST.CMD typed in the Run box of an overlay on the finished disk with
# no network, a screenshot every 15 s for ROUNDS (default 28), a clean power-off, then wglgears' outputs
# (renderer, version, frames per second), LZDoom's console logs and GLTEST.CMD's log read off the disk. QEMU=,
# ROS_BIOS= for another engine (the AOK one has no screen dump: no pictures). On MBP5, beside ros-run.sh (../).
K=$(cd "$(dirname "$0")/.." && pwd); B=~/aok-vm-bench
DL=$(cd "$1" && pwd) || exit 1
export ROS_DIR=$B/ros-gl/run ROS_NONET=1; W=$ROS_DIR
rm -rf $W; mkdir -p $W/cd; cd $W
cp "$K/software-cd/GLTEST.CMD" cd/ && sed -i '' 's/$/\r/' cd/GLTEST.CMD
cp "$DL/mesa3d_setup.exe" "$DL/wglgears.exe" cd/ || exit 1
[ -f "$DL/lzdoom-installer.exe" ] && cp "$DL/lzdoom-installer.exe" cd/
hdiutil makehybrid -quiet -o gl.iso cd -iso -joliet -default-volume-name AOK_GLTEST
export ROS_CD=$W/gl.iso
/opt/homebrew/bin/qemu-img create -q -f qcow2 -b ${ROS_BASE:-$B/reactos-build/reactos.qcow2} -F qcow2 ros.qcow2
QEMU=${QEMU:-/opt/homebrew/bin/qemu-system-i386} bash $K/ros-run.sh > q.out 2>&1 &
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
key "D:\\GLTEST.CMD"; sleep 1; mon "sendkey ret"
echo "[$(date +%T)] GLTEST.CMD"
for n in $(seq 1 ${2:-28}); do sleep 15; mon "screendump $W/s$n.ppm"; done
mon "system_powerdown"
for i in $(seq 90); do pgrep -f "ros-gl/run/ros.qcow2" > /dev/null || break; sleep 2; done
pkill -f "ros-gl/run/ros.qcow2"; sleep 1
for f in s*.ppm; do [ -f "$f" ] && sips -s format png "$f" --out "${f%.ppm}.png" > /dev/null 2>&1; done
/opt/homebrew/bin/qemu-img convert -O raw ros.qcow2 ros.raw
dev=$(hdiutil attach -readonly -nomount -imagekey diskimage-class=CRawDiskImage ros.raw | awk 'NR==1{print $1}')
mnt=$(mktemp -d); mount -t msdos -r ${dev}s1 $mnt 2> /dev/null || mount_msdos -o rdonly ${dev}s1 $mnt
for f in AOK-gl.log gl-1.txt gl-2.txt lz-1.txt lz-2.txt; do
    [ -f "$mnt/$f" ] || continue
    echo "== C:\\$f"; tr -d '\r' < "$mnt/$f" | grep -v '^GL_EXTENSIONS'
done
echo "== Program Files"; ls "$mnt/Program Files"
umount $mnt; hdiutil detach $dev > /dev/null; rm -f ros.raw
