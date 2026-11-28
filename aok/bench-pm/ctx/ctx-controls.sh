#!/bin/bash
# on MBP5: ctx-controls.sh -- each of ctxvariant.py's faults built into build-ctx's PowerPC engine in turn, and
# ctxtest.bin on each, with the gadgets and without. Every one must FAIL, in the test its fault is for.
export PATH=/opt/homebrew/bin:$PATH
W=$HOME/aok-vm-bench; T=$W/ctx; cd $W
V="no-drop no-taint no-jc no-dirty no-reuse-flush short-key"
F="accel/tcg/cputlb.c target/ppc/mmu_helper.c"
mkdir -p $T/good $T/q
[ -n "$RUNONLY" ] || for f in $F; do cp src-ctx/$f $T/good/$(basename $f); done
[ -n "$RUNONLY" ] || for v in $V; do
    for f in $F; do cp $T/good/$(basename $f) src-ctx/$f; done
    python3 -I $T/ctxvariant.py $v $W/src-ctx || { echo "$v: NO-EDIT"; continue; }
    (cd build-ctx && ninja qemu-system-ppc-unsigned > ninja-$v.out 2>&1) || { echo "$v: BUILD-FAILED"; grep -n error build-ctx/ninja-$v.out | head -5; continue; }
    cp build-ctx/qemu-system-ppc-unsigned $T/q/qemu-$v
done
[ -n "$RUNONLY" ] || { for f in $F; do cp $T/good/$(basename $f) src-ctx/$f; done
(cd build-ctx && ninja > ninja.out 2>&1) && echo "restored and rebuilt" || echo "RESTORE BUILD FAILED"; }
clean() { tr -d '\r' | sed 's/\x1b\[[0-9;]*[A-Za-z]//g'; }
for v in $V; do
    [ -x $T/q/qemu-$v ] || continue
    for a in 1 0; do
        ( sleep 4; echo 'xp /36wx 0x3000'; sleep 1; echo quit ) | QEMU_AOK=$a $T/q/qemu-$v -L $W/src-aok/pc-bios -M mac99 -m 128 -bios $T/ctxtest.bin -display none -serial none -monitor stdio 2>&1 | clean | python3 -I $T/ctxcheck.py "$v aok=$a"
    done
done
echo CTX-CONTROLS-DONE
