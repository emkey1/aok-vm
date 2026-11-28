#!/bin/bash
# on MBP5: ctx-test.sh BUILD... -- ctxtest.bin (ctxgen.py) on each build directory's PowerPC engine, with the
# gadgets and without, with the TLB contexts and with QEMU_AOK_NO_TLB_CONTEXTS (the flush for every change, which
# is what the test's expectations come from), and what the context cache counted.
W=$HOME/aok-vm-bench; T=$W/ctx; cd $T
clean() { tr -d '\r' | sed 's/\x1b\[[0-9;]*[A-Za-z]//g'; }
one() {  # label binary env...
    l=$1; q=$2; shift 2
    out=$( ( sleep ${WAIT:-4}; echo 'xp /28wx 0x3000'; sleep 1; echo quit ) |
           env QEMU_AOK_STATS=1 "$@" $q -M mac99 -m 128 -bios $T/ctxtest.bin -display none -serial none -monitor stdio 2>&1 | clean )
    echo "$out" | python3 -I $T/ctxcheck.py "$l"
    echo "$out" | grep -a 'tlb contexts' | sed 's/^/    /'
}
for b in "$@"; do
    q=$W/$b/qemu-system-ppc-unsigned
    [ -x $q ] || q=$b
    one "$b gadgets, contexts" $q QEMU_AOK=1
    one "$b TCG, contexts" $q QEMU_AOK=0
    one "$b gadgets, no contexts" $q QEMU_AOK=1 QEMU_AOK_NO_TLB_CONTEXTS=1
    one "$b TCG, no contexts" $q QEMU_AOK=0 QEMU_AOK_NO_TLB_CONTEXTS=1
done
echo CTX-TEST-DONE
