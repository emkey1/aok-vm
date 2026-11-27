#!/bin/bash
# on MBP5: gate.sh BUILD... -- fpstress with the single-precision pass (kit/ppc/initramfs-stress-s.cpio) on each
# build's PowerPC engine, with the gadgets and without, and how many FP insns QEMU's helpers did under the gadgets.
W=$HOME/aok-vm-bench; L=$W/logs/fp; mkdir -p $L
ext() { tr -d "\r" < "$1" | grep -a "^FPSTRESS"; }
export INITRD=$W/kit/ppc/initramfs-stress-s.cpio
for b in "$@"; do
    QBIN=$W/$b/qemu-system-ppc-unsigned $W/ppc-run.sh 1 fpstress $L/$b-a.log 1500 > /dev/null &
    QBIN=$W/$b/qemu-system-ppc-unsigned $W/ppc-run.sh 0 fpstress $L/$b-t.log 1500 > /dev/null &
done
wait
for b in "$@"; do
    ext $L/$b-a.log > $L/$b-a.txt; ext $L/$b-t.log > $L/$b-t.txt
    n=$(wc -l < $L/$b-a.txt | tr -d ' ')
    d=$(paste -d'|' $L/$b-a.txt $L/$b-t.txt | awk -F'|' '$1 != $2 { n++ } END { print n+0 }')
    echo "$b: $n lines with the gadgets ($(grep -c S $L/$b-a.txt) of the single pass), $(wc -l < $L/$b-t.txt | tr -d ' ') without; $d differ; $(grep -a 'RESULT fpstress' $L/$b-a.log | tr -d '\r' | cut -d' ' -f2-4) against $(grep -a 'RESULT fpstress' $L/$b-t.log | tr -d '\r' | cut -d' ' -f3-4)"
    grep -a "aok: ppc:" $L/$b-a.log | tr -d '\r' | cut -c1-400
done
echo FP-GATE-DONE
