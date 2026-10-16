#!/bin/bash
# ppc-many.sh NAME QBIN MODE GUESTS WORKLOAD -- WORKLOAD in GUESTS PowerPC kit guests at once, on QBIN with QEMU_AOK=MODE
# and INITRD (default: stress/build-stress.sh's initramfs); each console to /tmp/ppcg/many-NAME-N.txt, and a line each
# of what went wrong. Many at once is the point: under load a guest does less in each 100 ms, its TLB shrinks, and
# timing-dependent faults show (TCTI's page-crossing check was 1 check in 24 at eight guests, 1 in 8 at twelve).
#   ppc-many.sh tcti ~/aok-vm-bench/build-ppc/qemu-system-ppc-unsigned 0 12 corecheck
cd ~/aok-vm-bench; name=$1; export QBIN=$2; mode=$3; g=$4; wl=$5
export INITRD=${INITRD:-$HOME/aok-vm-bench/kit/ppc/initramfs-stress.cpio}
mkdir -p /tmp/ppcg; rm -f /tmp/ppcg/many-$name-*.txt
for i in $(seq $g); do QEMU_AOK_STATS=0 ./ppc-run.sh $mode $wl /tmp/ppcg/many-$name-$i.txt 3600 > /dev/null & done; wait
for f in /tmp/ppcg/many-$name-*.txt; do
    echo "$f: $(grep -a "TLBFOLD\|HEAPSTRESS\|SORTLOOP\|FAIL\|Abort\|egfault\|Oops\|TIMEOUT\|CORE-BEGIN\|^CHECK sort" $f | tr -d '\r' |
        grep -v "771062dd5be60e845fc93a82d0ed2f00  - 2974" | head -6 | tr '\n' '|')"
done
