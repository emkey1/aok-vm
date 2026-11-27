#!/bin/bash
# on MBP5: os9-hd-start.sh [brew|new] [IMAGE] -- Mac OS 9 from the installed disk alone, with the devices AOK VM
# gives a mac99 machine with USB on. QMP on macos9/hd/qmp.sock. brew: Homebrew's QEMU; new: our engine.
export PATH=/opt/homebrew/bin:$PATH
W=$HOME/aok-vm-bench; M=$W/macos9; cd $M/hd; img=${2:-$M/hd/os9-hd.img}
N=$W/engines/UTM/sysroot-ios-tci-arm64/share/qemu/ppc-ndrvloader
case ${1:-brew} in brew) Q=(qemu-system-ppc) ;; new) Q=($W/build-os9-new/qemu-system-ppc-unsigned -L $W/src-aok/pc-bios) ;; esac
case $img in *.qcow2) F=qcow2 ;; *) F=raw ;; esac
rm -f qmp.sock
nohup "${Q[@]}" -nodefaults -vga none -nic none -device VGA,edid=on -smp 1 -machine mac99,via=pmu,usb=on -accel tcg,tb-size=128 \
    -device loader,addr=0x4000000,file=$N -prom-env "boot-command=init-program go" -m 512 -audio none -device virtio-tablet-pci \
    -device ide-hd,bus=ide.0,unit=0,drive=hd0,bootindex=0 -drive "if=none,media=disk,id=hd0,file=$img,format=$F" \
    -display none -serial file:ser.log -qmp unix:qmp.sock,server=on,wait=off < /dev/null > qemu.log 2>&1 &
echo "pid $!"
