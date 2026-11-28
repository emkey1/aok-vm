#!/bin/bash
# on MBP5: vec-gate.sh BUILD... -- vectest (i3/vectest, put into the kit's stress initramfs under fpstress's
# name, which run1.sh knows) on each build directory's PowerPC engine with the gadgets and without: the lines
# that differ (none may), and what the first insns of TCG's TBs were.
W=$HOME/aok-vm-bench; L=$W/logs/i3; mkdir -p $L
T=$(mktemp -d); mkdir -p $T/bench; cp $W/i3/vectest $T/bench/fpstress; chmod 755 $T/bench/fpstress
(cd $T && find bench | cpio -o -H newc 2>/dev/null) > $T/x.cpio; cat $W/kit/ppc/initramfs-stress.cpio $T/x.cpio > $W/kit/ppc/initramfs-vec.cpio; rm -rf $T
export INITRD=$W/kit/ppc/initramfs-vec.cpio
for b in "$@"; do
    QBIN=$W/$b/qemu-system-ppc-unsigned $W/ppc-run.sh 1 fpstress $L/$b-a.log 900 > /dev/null &
    QBIN=$W/$b/qemu-system-ppc-unsigned $W/ppc-run.sh 0 fpstress $L/$b-t.log 900 > /dev/null &
done
wait
for b in "$@"; do
    for m in a t; do tr -d '\r' < $L/$b-$m.log | grep -a '^VECTEST' > $L/$b-$m.txt; done
    n=$(wc -l < $L/$b-a.txt | tr -d ' ')
    d=$(paste -d'|' $L/$b-a.txt $L/$b-t.txt | awk -F'|' '$1 != $2 { n++ } END { print n+0 }')
    echo "$b: $n lines with the gadgets, $(wc -l < $L/$b-t.txt | tr -d ' ') without; $d differ; $(grep -a 'RESULT fpstress' $L/$b-a.log | tr -d '\r' | cut -d' ' -f2-4) against $(grep -a 'RESULT fpstress' $L/$b-t.log | tr -d '\r' | cut -d' ' -f3-4)"
    [ "$d" != 0 ] && paste -d'|' $L/$b-a.txt $L/$b-t.txt | awk -F'|' '$1 != $2 { print "  gadgets: " $1; print "  TCG:     " $2 }' | head -12
    tail -26 $L/$b-a.txt | head -3; grep -a 'fault' $L/$b-a.txt | head -24 | cut -c1-80
    grep -a "first insns left to TCG\|TBs left whole\|main loop entered" $L/$b-a.log | tr -d '\r' | cut -c1-240
done
echo VEC-GATE-DONE
