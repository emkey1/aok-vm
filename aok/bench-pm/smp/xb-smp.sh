#!/bin/bash
# on MBP5: xb-smp.sh -- Xbench under Tiger on build-smp, one CPU and two, each machine alone, in turn, twice
# (CPU, thread and memory tests): the result pictures as macosx/shots/xs-N-RUN.png.
cd ~/aok-vm-bench/macosx
for r in 1 2; do for n in 1 2; do
    sed "s/-smp 1 /-smp $n /" ../osx-run.sh > ../osx-run-smp$n.sh
    sed "s|osx-run.sh|osx-run-smp$n.sh|" ../xb-auto.sh > ../xb-auto-smp$n.sh
    bash ../xb-auto-smp$n.sh xs$n:smp 2>&1 | grep -a steady
    cp shots/xs$n-r.png shots/xs-$n-$r.png
done; done
echo XB-SMP-DONE
