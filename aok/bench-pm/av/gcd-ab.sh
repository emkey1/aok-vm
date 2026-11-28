#!/bin/bash
# on MBP5: gcd-ab.sh -- Xbench under Tiger on the engine before (i3) and with the AltiVec gadgets (av), each
# machine alone, in turn, twice: the result pictures as macosx/shots/gcd-ENGINE-N.png.
cd ~/aok-vm-bench/macosx
for n in 1 2; do for e in i3 av; do
    bash ~/aok-vm-bench/xb-auto.sh g$e:$e 2>&1 | grep -a steady
    cp shots/g$e-r.png shots/gcd-$e-$n.png
done; done
echo GCD-AB-DONE
