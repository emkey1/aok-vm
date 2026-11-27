#!/bin/bash
# on MBP5: controls.sh -- each of variant.py's faults built into a copy of build-fp's engine, fpstress run on it
# with the gadgets, and its lines against the reference run without them (logs/fp/build-fp-t.txt, gate.sh's).
# A fault the gate does not see prints "0 differ": then the gate does not reach that path.
export PATH=/opt/homebrew/bin:$PATH
W=$HOME/aok-vm-bench; L=$W/logs/fp; cd $W
V="adds-exact fmas-b muls-exact divs-swap nan-order nan-mask snan-b infzero inf-any inf-class zero-any quot-any fma-zero fma-tiny fma-cancel fmas-zero fmas-tiny fmas-cancel"
G=src-fp/target/ppc/tcg/aok/gadgets.S
cp $G $L/gadgets.S.good
mkdir -p $W/fpc
for v in $V; do
    cp $L/gadgets.S.good $G
    python3 -I $W/fp/variant.py $v $G || { echo "$v: NO-EDIT"; continue; }
    (cd build-fp && ninja > ninja-$v.out 2>&1) || { echo "$v: BUILD-FAILED"; grep -n error build-fp/ninja-$v.out | head -5; continue; }
    cp build-fp/qemu-system-ppc-unsigned $W/fpc/qemu-$v
done
cp $L/gadgets.S.good $G
(cd build-fp && ninja > ninja.out 2>&1) && echo "restored and rebuilt" || echo "RESTORE BUILD FAILED"
cmp -s $G $L/gadgets.S.good && git -C src-fp diff --stat | tail -1
export INITRD=$W/kit/ppc/initramfs-stress-s.cpio
n=0
for v in $V; do
    [ -x $W/fpc/qemu-$v ] || continue
    QBIN=$W/fpc/qemu-$v $W/ppc-run.sh 1 fpstress $L/c-$v.log 1500 > /dev/null &
    n=$((n+1)); [ $((n % 6)) = 0 ] && wait
done
wait
for v in $V; do
    [ -f $L/c-$v.log ] || continue
    tr -d "\r" < $L/c-$v.log | grep -a "^FPSTRESS" > $L/c-$v.txt
    echo "$v: $(wc -l < $L/c-$v.txt | tr -d ' ') lines, $(paste -d'|' $L/c-$v.txt $L/build-fp-t.txt | awk -F'|' '$1 != $2 { n++ } END { print n+0 }') differ"
done
echo CONTROLS-DONE
