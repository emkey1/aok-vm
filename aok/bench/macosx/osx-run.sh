#!/bin/bash
# on MBP5: osx-run.sh TAG brew|new SECONDS plain|app [EXTRA...] -- Mac OS X 10.4 from the installed disk, on a
# throwaway overlay (the downloaded image stays as it came): a picture every 30 s (macosx/shots/TAG-NN.png) and
# the CPU's place. brew: Homebrew's QEMU 11.1.2 (JIT); new: our engine. plain: -M mac99,via=pmu and the defaults;
# app: the devices AOK VM gives a mac99 machine with USB on. KEEP=1 leaves it running (QMP: macosx/qmp-TAG.sock).
export PATH=/opt/homebrew/bin:$PATH
W=$HOME/aok-vm-bench; M=$W/macosx; tag=$1; eng=$2; secs=$3; set_=$4; shift 4
img=$(ls $M/installed/*.qcow2 | head -1); mkdir -p $M/shots $M/run; cd $M/run
N=$W/engines/UTM/sysroot-ios-tci-arm64/share/qemu/ppc-ndrvloader
case $eng in brew) Q=(qemu-system-ppc) ;; new) Q=($W/build-os9-new/qemu-system-ppc-unsigned -L $W/src-aok/pc-bios) ;; esac
rm -f $tag.qcow2 qmp-$tag.sock; qemu-img create -q -f qcow2 -b "$img" -F qcow2 $tag.qcow2
case $set_ in
plain) A=(-M mac99,via=pmu -m ${MEM:-1024} -boot c -drive file=$tag.qcow2,format=qcow2,media=disk) ;;
app)   A=(-nodefaults -vga none -nic none -device VGA,edid=on -smp 1 -machine mac99,via=pmu,usb=on -accel tcg,tb-size=128
          -device loader,addr=0x4000000,file=$N -prom-env "boot-command=init-program go" -m ${MEM:-1024} -audio none -device virtio-tablet-pci
          -device ide-hd,bus=ide.0,unit=0,drive=hd0,bootindex=0 -drive "if=none,media=disk,id=hd0,file=$tag.qcow2,format=qcow2") ;;
esac
"${Q[@]}" "${A[@]}" "$@" -display none -serial file:ser-$tag.log -qmp unix:qmp-$tag.sock,server=on,wait=off < /dev/null > qemu-$tag.log 2>&1 &
q=$!
qm() { python3 -I $W/qmp.py qmp-$tag.sock "$@" 2>/dev/null; }
t=0; n=0
while [ $t -lt $secs ]; do sleep 30; t=$((t+30)); n=$((n+1)); f=$M/shots/$tag-$(printf %02d $n)
    qm shot $f.ppm > /dev/null; h=$(md5 -q $f.ppm 2>/dev/null | cut -c1-6); sips -s format png $f.ppm --out $f.png > /dev/null 2>&1; rm -f $f.ppm
    echo "$tag t=$t: $h NIP $(qm hmp 'info registers' | grep -a '^NIP' | awk '{print $2}')"; done
head -2 qemu-$tag.log | cut -c1-160
[ -n "$KEEP" ] && { echo "$tag: left running, pid $q"; exit 0; }
qm hmp quit > /dev/null; sleep 1; kill $q 2>/dev/null; rm -f $tag.qcow2
echo "OSX-RUN-DONE $tag"
