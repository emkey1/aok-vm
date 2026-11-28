#!/bin/bash
# on MBP5: chain-smp.sh -- build-smp (two-CPU mac99, MTTCG for 32-bit PowerPC, atomic stwcx.): every PowerPC gate
# on one CPU, ctxtest, Mac OS 9 to its desktop.
W=$HOME/aok-vm-bench; cd $W; b=build-smp
bash fp/ppc-gates.sh $b 2>&1 | grep -v "Terminated\|many-"
bash fp/gate.sh $b 2>&1 | grep -a "differ\|DONE" | tail -2
bash i3/vec-gate.sh $b 2>&1 | grep -a "differ\|DONE"
bash av/av-gate.sh $b 2>&1 | grep -a "differ\|DONE"
bash ctx/ctx-test.sh $b 2>&1 | grep -a "PASS\|FAIL\|RESULTS\|DONE"
STEP=10 bash i3/os9-try.sh smp 60 > logs/os9-smp.log 2>&1
echo "os9 pictures: $(ls macos9/shots/try-smp-*.png 2>/dev/null | wc -l)"
echo CHAIN-SMP-DONE
