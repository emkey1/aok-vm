#!/bin/bash
# on MBP5: every gate on build-ctx: the four front ends' (flush-gates.sh), the PowerPC kit's with fptest and
# memtest (ppc-gates.sh), the FP gate, and the context test.
export PATH=/opt/homebrew/bin:$PATH
W=$HOME/aok-vm-bench; cd $W
bash flush-gates.sh build-ctx 2>&1 | grep -v "many-.*TLBFOLD ok"
bash fp/ppc-gates.sh build-ctx 2>&1 | grep -v "many-.*TLBFOLD ok"
grep -a "tlb contexts" logs/build-ctx/ppc-a.log | tr -d '\r' | head -2
bash fp/gate.sh build-ctx 2>&1 | head -2 | cut -c1-300
bash ctx/ctx-test.sh build-ctx 2>&1
echo CHAIN7-DONE
