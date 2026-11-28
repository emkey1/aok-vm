#!/bin/bash
# on MBP5: av-gate.sh BUILD... -- avstress (av/avstress, put into the kit's stress initramfs under fpstress's
# name, which run1.sh knows) on each build directory's PowerPC engine with the gadgets and without: the lines
# that differ (none may), how many AltiVec FP insns went to C, and what TCG still began TBs with.
W=$HOME/aok-vm-bench; L=$W/logs/av; mkdir -p $L
T=$(mktemp -d); mkdir -p $T/bench; cp $W/av/avstress $T/bench/fpstress; chmod 755 $T/bench/fpstress
(cd $T && find bench | cpio -o -H newc 2>/dev/null) > $T/x.cpio; cat $W/kit/ppc/initramfs-stress.cpio $T/x.cpio > $W/kit/ppc/initramfs-av.cpio; rm -rf $T
export INITRD=$W/kit/ppc/initramfs-av.cpio
for b in "$@"; do
    QEMU_AOK_STATS=2 QBIN=$W/$b/qemu-system-ppc-unsigned $W/ppc-run.sh 1 fpstress $L/$b-a.log ${SECS:-1200} > /dev/null &
    QBIN=$W/$b/qemu-system-ppc-unsigned $W/ppc-run.sh 0 fpstress $L/$b-t.log ${SECS:-1200} > /dev/null &
done
wait
for b in "$@"; do
    for m in a t; do tr -d '\r' < $L/$b-$m.log | grep -a '^AVSTRESS' | awk '{ print $1, $2, ($2 == "all" ? $3 " " $4 " " substr($5, 1, 16) : substr($3, 1, 16)) }' > $L/$b-$m.txt; done
    n=$(wc -l < $L/$b-a.txt | tr -d ' ')
    d=$(paste -d'|' $L/$b-a.txt $L/$b-t.txt | awk -F'|' '$1 != $2 { n++ } END { print n+0 }')
    echo "$b: $n lines with the gadgets, $(wc -l < $L/$b-t.txt | tr -d ' ') without; $d differ; $(grep -a 'RESULT fpstress' $L/$b-a.log | tr -d '\r' | cut -d' ' -f2-4) against $(grep -a 'RESULT fpstress' $L/$b-t.log | tr -d '\r' | cut -d' ' -f3-4)"
    [ "$d" != 0 ] && paste -d'|' $L/$b-a.txt $L/$b-t.txt | awk -F'|' '$1 != $2 { print "  " $1 "   TCG: " $2 }' | cut -c1-110 | head -${SHOW:-60}
    tail -1 $L/$b-a.txt
    grep -a "AltiVec FP insns\|TBs left whole\|main loop entered" $L/$b-a.log | tr -d '\r' | cut -c1-240
    python3 -I $W/i3/entries.py $L/$b-a.log 8 2> /dev/null | head -12
done
echo AV-GATE-DONE
