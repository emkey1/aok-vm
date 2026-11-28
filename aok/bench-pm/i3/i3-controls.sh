#!/bin/bash
# on MBP5: i3-controls.sh -- each of i3variant.py's faults built into build-i3's engine in turn; vectest's lines
# against the run without gadgets (vec-gate.sh's: logs/i3/build-i3-t.txt) for those vectest sees, ctxtest for the
# rest. Every one must be seen.
export PATH=/opt/homebrew/bin:$PATH
W=$HOME/aok-vm-bench; T=$W/i3; L=$W/logs/i3; cd $W
VV="lvx-order stvx-order lvx-align mfocrf-shift mtocrf-many icbi-line lswi-32 addco-ov ov-so mullwo-ov divwo-min bcctr-sense bcctrl-lr"
VC="sync-stays mtsrin-index mfmsr-other rfi-next"
F="target/ppc/tcg/aok/gadgets.S target/ppc/tcg/aok/translate.c"
mkdir -p $T/good $T/q
for f in $F; do cp src-i3/$f $T/good/$(basename $f); done
for v in $VV $VC; do
    for f in $F; do cp $T/good/$(basename $f) src-i3/$f; done
    python3 -I $T/i3variant.py $v $W/src-i3 || { echo "$v: NO-EDIT"; continue; }
    (cd build-i3 && ninja > ninja-$v.out 2>&1) || { echo "$v: BUILD-FAILED"; grep -n error build-i3/ninja-$v.out | head -5; continue; }
    cp build-i3/qemu-system-ppc-unsigned $T/q/qemu-$v
done
for f in $F; do cp $T/good/$(basename $f) src-i3/$f; done
(cd build-i3 && ninja > ninja.out 2>&1) && echo "restored and rebuilt" || echo "RESTORE BUILD FAILED"
export INITRD=$W/kit/ppc/initramfs-vec.cpio
for v in $VV; do
    [ -x $T/q/qemu-$v ] && QBIN=$T/q/qemu-$v $W/ppc-run.sh 1 fpstress $L/c-$v.log 900 > /dev/null &
done
wait
for v in $VV; do
    [ -f $L/c-$v.log ] || { echo "$v: no log"; continue; }
    tr -d "\r" < $L/c-$v.log | grep -a "^VECTEST" > $L/c-$v.txt
    echo "$v: $(wc -l < $L/c-$v.txt | tr -d ' ') lines, $(paste -d'|' $L/c-$v.txt $L/build-i3-t.txt | awk -F'|' '$1 != $2 { n++ } END { print n+0 }') differ"
done
clean() { tr -d '\r' | sed 's/\x1b\[[0-9;]*[A-Za-z]//g'; }
for v in $VC; do
    [ -x $T/q/qemu-$v ] || continue
    ( sleep 4; echo 'xp /36wx 0x3000'; sleep 1; echo quit ) | QEMU_AOK=1 $T/q/qemu-$v -L $W/src-aok/pc-bios -M mac99 -m 128 -bios $W/ctx/ctxtest.bin -display none -serial none -monitor stdio 2>&1 | clean | python3 -I $W/ctx/ctxcheck.py "$v"
done
echo I3-CONTROLS-DONE
