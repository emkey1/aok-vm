#!/bin/bash
# on MBP5: chain-av.sh BUILD ENGINE -- every PowerPC gate on one build, then Mac OS 9 to its desktop and
# Xbench graphics tests under Tiger beside the engine before (i3).
W=$HOME/aok-vm-bench; cd $W; b=$1; e=$2
bash fp/ppc-gates.sh $b 2>&1 | grep -v Terminated
bash fp/gate.sh $b 2>&1 | grep -v Terminated | tail -4
bash i3/vec-gate.sh $b 2>&1 | grep -a "differ\|DONE"
bash ctx/ctx-test.sh $b 2>&1 | grep -a "PASS\|FAIL\|DONE"
bash av/av-gate.sh $b 2>&1 | grep -a "differ\|AltiVec FP\|DONE"
STEP=10 bash i3/os9-try.sh $e 60 > logs/os9-$e.log 2>&1 & STEP=10 bash i3/os9-try.sh i3 60 > logs/os9-i3b.log 2>&1 & wait
echo "os9 pictures: $(ls macos9/shots/try-$e-*.png | wc -l)"
cd macosx && XB_MODE=ui bash $W/xb-auto.sh ua:$e ub:i3 2>&1 | grep -a "steady\|DONE"
echo CHAIN-AV-DONE
