#!/bin/bash
# on MBP5: xb-auto.sh TAG:ENGINE[:VAR=VALUE]... -- Xbench under Mac OS X 10.4 on each engine (osx-run.sh's names:
# brew, new, or a build directory's), all at once, from the finished Tiger disk; VAR=VALUE goes into that
# machine's environment (QEMU_AOK_NO_TLB_CONTEXTS=1: one binary both ways). The CPU, thread and memory tests; with
# XB_MODE=ui the Quartz graphics and user interface tests instead, which live on calls into the window server.
# The result window of each is left as macosx/shots/TAG-r.png. SAMPLE=TAG: that machine's QEMU is sampled for
# SAMPLE_FOR (30) s from SAMPLE_AT (10) s into the run (macosx/run/sample-TAG.txt).
export PATH=/opt/homebrew/bin:$PATH
W=$HOME/aok-vm-bench; M=$W/macosx; cd $M
X() { bash $W/xb.sh "$@"; }
for p in "$@"; do IFS=: read t e x <<< "$p"; rm -f run-$t.log; (KEEP=1 IMG=$M/work/tiger-final2.qcow2 nohup env ${x:+"$x"} bash $W/osx-run.sh $t $e ${BOOT:-150} app > run-$t.log 2>&1 &); done
for p in "$@"; do t=${p%%:*}; until grep -q "left running" run-$t.log 2>/dev/null; do sleep 5; done; done
for p in "$@"; do t=${p%%:*}
    # The boxes in tab order from CPU, which has the focus: CPU, Thread, Memory, Disk, Quartz, OpenGL, User Interface; then Start.
    X $t key meta_l-shift-a sleep 4 type xbench sleep 2 key meta_l-o sleep 20 key ctrl-f7 sleep 1
    if [ "$XB_MODE" = ui ]; then
        X $t key spc sleep 1 key tab sleep 1 key spc sleep 1 key tab sleep 1 key spc sleep 1 key tab sleep 1 key spc sleep 1 key tab sleep 1 \
             key tab sleep 1 key spc sleep 1 key tab sleep 1 key tab sleep 1
    else
        X $t key tab sleep 1 key tab sleep 1 key tab sleep 1 key spc sleep 1 \
             key tab sleep 1 key spc sleep 1 key tab sleep 1 key spc sleep 1 key tab sleep 1 key spc sleep 1 key tab sleep 1
    fi
    X $t shot $t-pre > /dev/null
done
for p in "$@"; do t=${p%%:*}; X $t key spc; done
if [ -n "$SAMPLE" ]; then pid=$(grep "left running" run-$SAMPLE.log | sed 's/.*pid //'); sleep ${SAMPLE_AT:-10}; sample $pid ${SAMPLE_FOR:-30} -mayDie -file $M/run/sample-$SAMPLE.txt > /dev/null 2>&1; fi
for p in "$@"; do t=${p%%:*}; last=x
    for i in $(seq 1 ${XB_WAITS:-40}); do sleep 20; X $t shot $t-r > /dev/null; a=$(md5 -q shots/$t-r.png); [ "$a" = "$last" ] && break; last=$a; done
    echo "$t: result picture steady after about $((i*20)) s"
done
for p in "$@"; do t=${p%%:*}; pid=$(grep "left running" run-$t.log | sed 's/.*pid //'); kill $pid 2>/dev/null; rm -f run/$t.qcow2; done
echo XB-AUTO-DONE
