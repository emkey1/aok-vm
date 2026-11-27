#!/bin/bash
# on MBP5: os9-inst-start.sh cd|hd -- Mac OS 9.2.2's CD and the disk being installed on (macos9/hd/os9-hd.img, a
# copy of the blank disk from archive.org's mac-os9), on Homebrew's QEMU with a pointer that takes positions:
# UTM's NDRV loader and a virtio tablet. QMP on macos9/hd/qmp.sock (qmp.py). cd: start from the CD; hd: from the disk.
export PATH=/opt/homebrew/bin:$PATH
W=$HOME/aok-vm-bench; M=$W/macos9; cd $M/hd
N=$W/engines/UTM/sysroot-ios-tci-arm64/share/qemu/ppc-ndrvloader
case ${1:-cd} in cd) B=d ;; hd) B=c ;; esac
rm -f qmp.sock
nohup qemu-system-ppc -M mac99,via=pmu,usb=on -m 512 -boot $B \
    -device loader,addr=0x4000000,file=$N -prom-env "boot-command=init-program go" -device virtio-tablet-pci \
    -drive file=$M/hd/os9-hd.img,format=raw,media=disk -drive file=$M/iso/MacOS9.iso,format=raw,media=cdrom,readonly=on \
    -display none -serial file:ser.log -qmp unix:qmp.sock,server=on,wait=off < /dev/null > qemu.log 2>&1 &
echo "pid $!"
