#!/bin/bash
# on MBP5: os9-try.sh ENGINE [SECONDS] -- Mac OS 9.2.2 from the finished test disk on a throwaway overlay, on
# build-ENGINE's PowerPC engine with the app's devices: a picture every STEP (30) s (macos9/shots/try-ENGINE-NN.png),
# then the machine is told to quit. The disk itself is not written.
export PATH=/opt/homebrew/bin:$PATH
W=$HOME/aok-vm-bench; M=$W/macos9; e=$1; secs=${2:-150}; mkdir -p $M/shots $M/try; cd $M/try
N=$W/engines/UTM/sysroot-ios-tci-arm64/share/qemu/ppc-ndrvloader
rm -f $e.qcow2 qmp-$e.sock; qemu-img create -q -f qcow2 -b $M/hd/os9-hd.qcow2 -F qcow2 $e.qcow2
QEMU_AOK_STATS=${STATS:-1} $W/build-$e/qemu-system-ppc-unsigned -L $W/src-aok/pc-bios -nodefaults -vga none -nic none -device VGA,edid=on -smp 1 \
    -machine mac99,via=pmu,usb=on -accel tcg,tb-size=128 -device loader,addr=0x4000000,file=$N -prom-env "boot-command=init-program go" \
    -m 512 -audio none -device virtio-tablet-pci -device ide-hd,bus=ide.0,unit=0,drive=hd0,bootindex=0 \
    -drive "if=none,media=disk,id=hd0,file=$e.qcow2,format=qcow2" -display none -serial file:ser-$e.log \
    -qmp unix:qmp-$e.sock,server=on,wait=off < /dev/null > qemu-$e.log 2>&1 &
q=$!
qm() { python3 -I $W/qmp.py qmp-$e.sock "$@" 2>/dev/null; }
t=0; n=0
while [ $t -lt $secs ]; do sleep ${STEP:-30}; t=$((t+${STEP:-30})); n=$((n+1)); f=$M/shots/try-$e-$(printf %02d $n)
    qm shot $f.ppm > /dev/null; sips -s format png $f.ppm --out $f.png > /dev/null 2>&1; rm -f $f.ppm
    echo "$e t=$t: $(md5 -q $f.png | cut -c1-6) NIP $(qm hmp 'info registers' | grep -a '^NIP' | awk '{print $2}')"; done
qm hmp quit > /dev/null; sleep 2; kill $q 2>/dev/null; rm -f $e.qcow2
grep -a "aok: main loop\|TBs (9\|tlb contexts" qemu-$e.log | cut -c1-230
echo "OS9-TRY-DONE $e"
