#!/bin/bash
# on MBP5: ppc-gates.sh BUILD -- the PowerPC front end's gates on one build directory's engine (flush-gates.sh's
# PowerPC part): the kit's check, fpstress, heapstress and tlbfold with the gadgets against without, and tlbfold
# twelve times at once.
W=$HOME/aok-vm-bench; B=$W/$1; L=$W/logs/$1; mkdir -p $L
ext() { tr -d "\r" < "$1" | sed -n "/^BENCH-START/,/^BENCH-END/p" | grep -av "^RESULT\|^aok:\|^BENCH-START\|^WL "; }
cmpv() { ext "$1" > $L/.a.$$; ext "$2" > $L/.b.$$; n=$(wc -l < $L/.a.$$ | tr -d " ")
         if [ "$n" -gt 0 ] && cmp -s $L/.a.$$ $L/.b.$$; then v=IDENTICAL; else v="DIFFERENT"; fi
         echo "$(basename $1 .log) vs $(basename $2 .log): $n lines $v"; rm -f $L/.a.$$ $L/.b.$$; }
export INITRD=$W/kit/ppc/initramfs-stress.cpio; Q=$B/qemu-system-ppc-unsigned
QBIN=$Q $W/ppc-run.sh 1 check,fptest,memtest,fpstress,heapstress,tlbfold $L/ppc-a.log 1500 > /dev/null &
QBIN=$Q $W/ppc-run.sh 0 check,fptest,memtest,fpstress,heapstress,tlbfold $L/ppc-t.log 1500 > /dev/null & wait
cmpv $L/ppc-a.log $L/ppc-t.log; grep -a "CHECKHASH\|TLBFOLD\|HEAPSTRESS" $L/ppc-a.log | tr -d "\r" | head -5
$W/ppc-many.sh ${1#build-} $Q 1 12 tlbfold
echo PPC-GATES-DONE
