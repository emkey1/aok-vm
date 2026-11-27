#!/bin/bash
# on MBP5: xb-auto.sh TAG:ENGINE... -- Xbench's CPU, thread and memory tests under Mac OS X 10.4 on each engine
# (osx-run.sh's names: brew, new, or a build directory's), all at once, from the finished Tiger disk. The result
# window of each is left as macosx/shots/TAG-r.png. SAMPLE=TAG: that machine's QEMU is sampled for 30 s from the
# tenth second of the run (macosx/run/sample-TAG.txt).
export PATH=/opt/homebrew/bin:$PATH
W=$HOME/aok-vm-bench; M=$W/macosx; cd $M
X() { bash $W/xb.sh "$@"; }
for p in "$@"; do t=${p%%:*}; e=${p#*:}; rm -f run-$t.log; (KEEP=1 IMG=$M/work/tiger-final2.qcow2 nohup bash $W/osx-run.sh $t $e ${BOOT:-150} app > run-$t.log 2>&1 &); done
for p in "$@"; do t=${p%%:*}; until grep -q "left running" run-$t.log 2>/dev/null; do sleep 5; done; done
for p in "$@"; do t=${p%%:*}
    X $t key meta_l-shift-a sleep 4 type xbench sleep 2 key meta_l-o sleep 20 key ctrl-f7 sleep 1 key tab sleep 1 key tab sleep 1 key tab sleep 1 key spc sleep 1 \
         key tab sleep 1 key spc sleep 1 key tab sleep 1 key spc sleep 1 key tab sleep 1 key spc sleep 1 key tab sleep 1
    X $t shot $t-pre > /dev/null
done
for p in "$@"; do t=${p%%:*}; X $t key spc; done
if [ -n "$SAMPLE" ]; then pid=$(grep "left running" run-$SAMPLE.log | sed 's/.*pid //'); sleep 10; sample $pid 30 -mayDie -file $M/run/sample-$SAMPLE.txt > /dev/null 2>&1; fi
for p in "$@"; do t=${p%%:*}; last=x
    for i in $(seq 1 40); do sleep 20; X $t shot $t-r > /dev/null; a=$(md5 -q shots/$t-r.png); [ "$a" = "$last" ] && break; last=$a; done
    echo "$t: result picture steady after about $((i*20)) s"
done
for p in "$@"; do t=${p%%:*}; pid=$(grep "left running" run-$t.log | sed 's/.*pid //'); kill $pid 2>/dev/null; rm -f run/$t.qcow2; done
echo XB-AUTO-DONE
