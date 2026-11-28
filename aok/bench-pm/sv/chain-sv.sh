#!/bin/bash
# on MBP5: chain-sv.sh -- build-sv: the controls, every PowerPC gate, the AltiVec switch, Mac OS 9, and Xbench
# under Tiger beside the engine before (av), with what still begins TCG TBs.
W=$HOME/aok-vm-bench; cd $W; b=build-sv
bash sv/sv-controls.sh 2>&1 | grep -v Terminated
bash fp/ppc-gates.sh $b 2>&1 | grep -v "Terminated\|many-"
bash fp/gate.sh $b 2>&1 | grep -a "differ\|IDENTICAL\|DONE" | tail -3
bash i3/vec-gate.sh $b 2>&1 | grep -a "differ\|DONE"
bash av/av-gate.sh $b 2>&1 | grep -a "differ\|AltiVec FP\|main loop\|DONE"
# the switch: avstress again with AltiVec left to TCG under the gadgets
INITRD=$W/kit/ppc/initramfs-av.cpio QEMU_AOK_NO_ALTIVEC=1 QEMU_AOK_STATS=2 QBIN=$W/$b/qemu-system-ppc-unsigned $W/ppc-run.sh 1 fpstress logs/av/noav.log 1200 > /dev/null
echo "QEMU_AOK_NO_ALTIVEC: $(tr -d "\r" < logs/av/noav.log | grep -a "^AVSTRESS all" | cut -c1-44); $(grep -a -c "AltiVec FP insns" logs/av/noav.log) lines of FP vectors by helpers; $(python3 -I i3/entries.py logs/av/noav.log 3 | sed -n 2p)"
STEP=10 bash i3/os9-try.sh sv 60 > logs/os9-sv.log 2>&1
echo "os9 pictures: $(ls macos9/shots/try-sv-*.png | wc -l)"
cd macosx && bash $W/xb-auto.sh sa:sv:QEMU_AOK_STATS=2 sb:av:QEMU_AOK_STATS=2 2>&1 | grep -a "steady\|DONE"
grep -a "main loop entered" run/qemu-sa.log run/qemu-sb.log | cut -c1-200
python3 -I ../i3/entries.py run/qemu-sa.log 12
echo CHAIN-SV-DONE
