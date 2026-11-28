#!/bin/bash
# on MBP5: av-controls.sh [NAME...] -- each of avvariant.py's faults built into build-av's engine in turn, and
# avstress's lines against the run without gadgets (av-gate.sh's: logs/av/build-av-t.txt). Every one must be seen.
export PATH=/opt/homebrew/bin:$PATH
W=$HOME/aok-vm-bench; T=$W/av; L=$W/logs/av; cd $W
VV=${*:-$(python3 -I $T/avvariant.py list x)}
F="target/ppc/tcg/aok/gadgets.S target/ppc/tcg/aok/translate.c"
mkdir -p $T/good $T/q
for f in $F; do cp src-av/$f $T/good/$(basename $f); done
for v in $VV; do
    for f in $F; do cp $T/good/$(basename $f) src-av/$f; done
    python3 -I $T/avvariant.py $v $W/src-av || { echo "$v: NO-EDIT"; continue; }
    (cd build-av && ninja > ninja-$v.out 2>&1) || { echo "$v: BUILD-FAILED"; grep -n error build-av/ninja-$v.out | head -5; continue; }
    cp build-av/qemu-system-ppc-unsigned $T/q/qemu-$v
done
for f in $F; do cp $T/good/$(basename $f) src-av/$f; done
(cd build-av && ninja > ninja.out 2>&1) && echo "restored and rebuilt" || echo "RESTORE BUILD FAILED"
export INITRD=$W/kit/ppc/initramfs-av.cpio
n=0
for v in $VV; do
    [ -x $T/q/qemu-$v ] && QBIN=$T/q/qemu-$v $W/ppc-run.sh 1 fpstress $L/c-$v.log 900 > /dev/null &
    n=$((n+1)); [ $((n % 10)) = 0 ] && wait
done
wait
seen=0; all=0
for v in $VV; do
    all=$((all+1))
    [ -f $L/c-$v.log ] || { echo "$v: no log"; continue; }
    tr -d "\r" < $L/c-$v.log | grep -a "^AVSTRESS" | awk '{ print $1, $2, ($2 == "all" ? $3 " " $4 " " substr($5, 1, 16) : substr($3, 1, 16)) }' > $L/c-$v.txt
    d=$(paste -d'|' $L/c-$v.txt $L/build-av-t.txt | awk -F'|' '$1 != $2 { n++ } END { print n+0 }')
    [ "$d" != 0 ] && seen=$((seen+1))
    echo "$v: $(wc -l < $L/c-$v.txt | tr -d ' ') lines, $d differ: $(paste -d'|' $L/c-$v.txt $L/build-av-t.txt | awk -F'|' '$1 != $2 { split($1, a, " "); printf "%s ", a[2] }' | cut -c1-90)"
done
echo "AV-CONTROLS-DONE: $seen of $all seen"
