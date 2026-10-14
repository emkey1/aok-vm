#!/bin/bash
# ros-run.sh [ENV=VAL...] -- the ReactOS machine as AOK VM runs it, on a Mac: UTM's own QEMU command line for
# ReactOS.utm (i440FX without vmport or HPET, qemu32, 1 GB, std VGA, a Realtek 8139, a USB tablet, the guest
# agent's virtio-serial port, local time), the devices in the same order, so that the guest finds the same
# devices in the same PCI slots and what it learns about them here holds in the app. Without the screen:
# the monitor is ROS_DIR/mon.sock (shot.sh dumps the screen through it, keys go in as `sendkey`), the
# guest's debug output is ROS_DIR/serial.log.
#
#   ROS_DIR   the working directory (build.sh's), default ~/aok-vm-bench/reactos
#   ROS_DISK  the disk, default ROS_DIR/ros.qcow2
#   ROS_CD    a CD, booted first (ReactOS's own boot sector boots the disk when no key is pressed)
#   QEMU      the qemu-system-i386 to run, default Homebrew's; the AOK engine's has no screen dump and no
#             user-mode network, so with ROS_NONET=1 the card is on a hub of its own
#   ROS_BIOS  a firmware directory for -L (the AOK engine's pc-bios)
# Extra arguments are environment settings for QEMU (QEMU_AOK=0 and the like).
W=${ROS_DIR:-$HOME/aok-vm-bench/reactos}
cd "$W" || exit 1
DISK=${ROS_DISK:-$W/ros.qcow2}
Q=${QEMU:-/opt/homebrew/bin/qemu-system-i386}
NET="-netdev user,id=net0"; [ -n "$ROS_NONET" ] && NET="-netdev hubport,id=net0,hubid=0"
L=; [ -n "$ROS_BIOS" ] && L="-L $ROS_BIOS"
BOOT=0; CD=
if [ -n "$ROS_CD" ]; then
    BOOT=2; CD="-device ide-cd,bus=ide.1,drive=cd0,bootindex=1 -drive if=none,media=cdrom,id=cd0,file=$ROS_CD,readonly=on"
fi
exec env "$@" "$Q" $L -nodefaults -vga none \
    -device rtl8139,mac=52:54:00:A0:C0:39,netdev=net0 $NET -device VGA -cpu qemu32 -smp 1 \
    -machine pc,vmport=off,hpet=off -global PIIX4_PM.disable_s3=1 -m 1024 \
    -usb -device usb-tablet,bus=usb-bus.0 \
    -device ide-hd,bus=ide.0,drive=d0,bootindex=$BOOT -drive if=none,media=disk,id=d0,file="$DISK" $CD \
    -device virtio-serial -device virtserialport,chardev=ga,name=org.qemu.guest_agent.0 -chardev null,id=ga \
    -rtc base=localtime -display none \
    -monitor unix:"$W/mon.sock",server,nowait -serial file:"$W/serial.log"
