#!/bin/bash
# on MBP5: gate-v.sh BUILD -- the verbose single pass (a line an op, 60000 ops) with the gadgets and without; the
# ops whose lines differ, counted by op, and the first few.
W=$HOME/aok-vm-bench; L=$W/logs/fp; mkdir -p $L; b=$1
T=$(mktemp -d); mkdir -p $T/bench; cp $W/fp/fpstress-v $T/bench/fpstress; chmod 755 $T/bench/fpstress
(cd $T && find bench | cpio -o -H newc 2>/dev/null) > $T/x.cpio; cat $W/kit/ppc/initramfs-stress.cpio $T/x.cpio > $W/kit/ppc/initramfs-stress-v.cpio; rm -rf $T
export INITRD=$W/kit/ppc/initramfs-stress-v.cpio
QBIN=$W/$b/qemu-system-ppc-unsigned $W/ppc-run.sh 1 fpstress $L/v-a.log 600 > /dev/null &
QBIN=$W/$b/qemu-system-ppc-unsigned $W/ppc-run.sh 0 fpstress $L/v-t.log 600 > /dev/null &
wait
for m in a t; do tr -d '\r' < $L/v-$m.log | grep -a '^FPSTRESS-V' > $L/v-$m.txt; done
echo "$(wc -l < $L/v-a.txt | tr -d ' ') and $(wc -l < $L/v-t.txt | tr -d ' ') lines"
paste -d'|' $L/v-a.txt $L/v-t.txt | awk -F'|' '$1 != $2 { n++; split($1, x, " "); c[x[4]]++; if (n <= 6) { print "gadget: " $1; print "helper: " $2 } } END { printf "%d differ:", n; for (k in c) printf " op %s: %d", k, c[k]; print "" }'
