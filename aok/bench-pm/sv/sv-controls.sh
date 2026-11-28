#!/bin/bash
# on MBP5: sv-controls.sh [NAME...] -- each of svvariant.py's faults built into build-sv's engine in turn and
# ctxtest run on it with the gadgets: every one must FAIL (or print no results).
export PATH=/opt/homebrew/bin:$PATH
W=$HOME/aok-vm-bench; T=$W/sv; cd $W
VV=${*:-$(python3 -I $T/svvariant.py list x)}
F=target/ppc/tcg/aok/translate.c
mkdir -p $T/good $T/q; cp src-sv/$F $T/good/translate.c
for v in $VV; do
    cp $T/good/translate.c src-sv/$F
    python3 -I $T/svvariant.py $v $W/src-sv || { echo "$v: NO-EDIT"; continue; }
    (cd build-sv && ninja > ninja-$v.out 2>&1) || { echo "$v: BUILD-FAILED"; grep -n error build-sv/ninja-$v.out | head -5; continue; }
    cp build-sv/qemu-system-ppc-unsigned $T/q/qemu-$v
done
cp $T/good/translate.c src-sv/$F
(cd build-sv && ninja > ninja.out 2>&1) && echo "restored and rebuilt" || echo "RESTORE BUILD FAILED"
clean() { tr -d '\r' | sed 's/\x1b\[[0-9;]*[A-Za-z]//g'; }
# (a binary's first start is slow, macOS checking it: one run thrown away, so that the test has its four seconds;
# a fault is seen only if the tests before the one it is in read as they should)
for v in $VV; do
    [ -x $T/q/qemu-$v ] || continue
    $T/q/qemu-$v --version > /dev/null 2>&1
    ( sleep 4; echo 'xp /36wx 0x3000'; sleep 1; echo quit ) | QEMU_AOK=1 $T/q/qemu-$v -L $W/src-aok/pc-bios -M mac99 -m 128 -bios $W/ctx/ctxtest.bin -display none -serial none -monitor stdio 2>&1 | clean | python3 -I $W/ctx/ctxcheck.py "$v"
done
# sc-next is for the kit's Linux, whose every system call it would send back one insn late
[ -x $T/q/qemu-sc-next ] && { INITRD=$W/kit/ppc/initramfs-stress.cpio QBIN=$T/q/qemu-sc-next $W/ppc-run.sh 1 check $W/logs/sv-sc-next.log 120 > /dev/null; echo "sc-next under Linux: $(grep -a -c 'BENCH-END' $W/logs/sv-sc-next.log) BENCH-END lines (0: seen)"; }
echo SV-CONTROLS-DONE
