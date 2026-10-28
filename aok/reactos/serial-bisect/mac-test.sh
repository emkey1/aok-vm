#!/bin/bash
# bisect-test.sh [ENV=VAL...]: ReactOS on build-bisect's engine, the M4's command line (as the app runs it), its
# COM1 a TCP server read with nc -d for 30 s; prints the bytes of debug output and whether the desktop's line
# came. Exit 0 if the debug output came (good), 1 if not (bad), 125 if the guest did not run.
B=~/aok-vm-bench; W=$B/ros-bisect; rm -rf $W; mkdir -p $W; cd $W
/opt/homebrew/bin/qemu-img create -q -f qcow2 -b $B/reactos-build/reactos.qcow2 -F qcow2 ros.qcow2
env "$@" $B/build-bisect/qemu-system-x86_64 -L ${ROS_L:-$B/src-aok/pc-bios} -nodefaults -vga none \
  -device rtl8139,mac=52:54:00:A0:C0:39,netdev=net0 -netdev hubport,id=net0,hubid=0 -device VGA \
  -chardev socket,id=term0,port=4557,host=127.0.0.1,server=on,wait=off -serial chardev:term0 -cpu qemu32 \
  -smp cpus=1,sockets=1,cores=1,threads=1 -machine pc,vmport=off,hpet=off -accel tcg,tb-size=256 \
  -global PIIX4_PM.disable_s3=1 -global ICH9-LPC.disable_s3=1 -m 1024 -usb -device usb-tablet,bus=usb-bus.0 \
  -device ide-hd,bus=ide.0,drive=d0,bootindex=0 -drive if=none,media=disk,id=d0,file.filename=ros.qcow2,discard=unmap,detect-zeroes=unmap \
  -device virtio-serial -device virtserialport,chardev=ga,name=org.qemu.guest_agent.0 -chardev null,id=ga \
  ${ROS_S:+-S} -rtc base=localtime -display none -monitor unix:$W/mon.sock,server,nowait > q.out 2>&1 &
Q=$!; [ -n "$ROS_S" ] && { sleep $ROS_S; echo cont | nc -U -w 1 $W/mon.sock > /dev/null; }
for i in $(seq 50); do nc -z -G 1 127.0.0.1 4557 2>/dev/null && break; sleep 0.2; done
nc -d 127.0.0.1 4557 > raw.bin & N=$!
sleep 30
# still running? the screen as proof the guest got somewhere
CPU=$(ps -o time= -p $Q)
kill $N $Q 2>/dev/null; wait 2>/dev/null
n=$(wc -c < raw.bin | tr -d ' '); d=$(grep -c 'AllFolders' raw.bin)
echo "serial $n bytes, desktop lines $d, QEMU CPU $CPU"
[ "$n" -gt 1000 ] && exit 0
exit 1
