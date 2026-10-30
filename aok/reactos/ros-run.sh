#!/bin/bash
# ros-run.sh [ENV=VAL...] -- the ReactOS machine as AOK VM runs it, on a Mac: UTM's own QEMU command line for
# ReactOS.utm (i440FX without vmport or HPET, qemu32, 1 GB, std VGA, a Realtek 8139, an AC97 sound card, a
# USB tablet, the guest agent's virtio-serial port, local time), the devices in the same order, so that the
# guest finds the same devices in the same PCI slots and what it learns about them here holds in the app.
# Without the screen:
# the monitor is ROS_DIR/mon.sock (shot.sh dumps the screen through it, keys go in as `sendkey`), the
# guest's debug output is ROS_DIR/serial.log.
#
#   ROS_DIR   the working directory (build.sh's), default ~/aok-vm-bench/reactos
#   ROS_DISK  the disk, default ROS_DIR/ros.qcow2
#   ROS_CD    a CD, booted first (ReactOS's own boot sector boots the disk when no key is pressed)
#   QEMU      the qemu-system-i386 to run, default Homebrew's; the AOK engine's has no screen dump and no
#             user-mode network, so with ROS_NONET=1 the card is on a hub of its own
#   ROS_BIOS  a firmware directory for -L (the AOK engine's pc-bios)
#   ROS_NOUSB without the USB controller and tablet: an experiment (the boot without the USB hub driver's
#             waits), not the machine the app runs
#   ROS_USBDISK uhci or ehci: the disk as a USB stick on that controller instead of on IDE, ReactOS booted
#             from USB (what the USB hub driver's start-up wait is for, ReactOS's CORE-7826); a test, not
#             the machine the app runs
#   ROS_SOUND wav: what the sound card plays recorded to ROS_DIR/sound.wav (the app plays it through
#             SPICE; here it goes nowhere otherwise); off: no sound card, the machine before 2026-10-30
# Extra arguments are environment settings for QEMU (QEMU_AOK=0 and the like).
W=${ROS_DIR:-$HOME/aok-vm-bench/reactos}
cd "$W" || exit 1
DISK=${ROS_DISK:-$W/ros.qcow2}
Q=${QEMU:-/opt/homebrew/bin/qemu-system-i386}
NET="-netdev user,id=net0"; [ -n "$ROS_NONET" ] && NET="-netdev hubport,id=net0,hubid=0"
L=; [ -n "$ROS_BIOS" ] && L="-L $ROS_BIOS"
USB="-usb -device usb-tablet,bus=usb-bus.0"; [ -n "$ROS_NOUSB" ] && USB=
AUD="none,id=audio0"; [ "${ROS_SOUND:-}" = wav ] && AUD="wav,id=audio0,path=$W/sound.wav"
SND="-audiodev $AUD -device AC97,audiodev=audio0"; [ "${ROS_SOUND:-}" = off ] && SND=
BOOT=0; CD=
if [ -n "$ROS_CD" ]; then
    BOOT=2; CD="-device ide-cd,bus=ide.1,drive=cd0,bootindex=1 -drive if=none,media=cdrom,id=cd0,file=$ROS_CD,readonly=on"
fi
case "$ROS_USBDISK" in
    "")   HD="-device ide-hd,bus=ide.0,drive=d0,bootindex=$BOOT" ;;
    uhci) HD="-device usb-storage,bus=usb-bus.0,drive=d0,bootindex=$BOOT"; USB="-usb -device usb-tablet,bus=usb-bus.0" ;;
    ehci) HD="-device usb-ehci,id=ehci -device usb-storage,bus=ehci.0,drive=d0,bootindex=$BOOT" ;;
    *)    echo "ROS_USBDISK is uhci or ehci" >&2; exit 1 ;;
esac
exec env "$@" "$Q" $L -nodefaults -vga none \
    -device rtl8139,mac=52:54:00:A0:C0:39,netdev=net0 $NET -device VGA -cpu qemu32 -smp 1 \
    -machine pc,vmport=off,hpet=off -global PIIX4_PM.disable_s3=1 -m 1024 \
    $SND $USB \
    $HD -drive if=none,media=disk,id=d0,file="$DISK" $CD \
    -device virtio-serial -device virtserialport,chardev=ga,name=org.qemu.guest_agent.0 -chardev null,id=ga \
    -rtc base=localtime -display none \
    -monitor unix:"$W/mon.sock",server,nowait -serial file:"$W/serial.log"
