#!/bin/bash
# on MBP5: x2.sh TAG -- as x1.sh, but after 70 s the monitor's view: each CPU's state and pc, and the PIC.
export PATH=/opt/homebrew/bin:$PATH
cd ~/aok-vm-bench/macosx; t=$1; shift
rm -f run-$t.log
(KEEP=1 IMG=$PWD/work/tiger-final5.qcow2 nohup bash ../osx-run.sh $t smp 5 app -smp ${CPUS:-2} -prom-env "boot-args=-v" "$@" > run-$t.log 2>&1 &)
until grep -q "left running" run-$t.log 2>/dev/null; do sleep 2; done
pid=$(grep "left running" run-$t.log | sed "s/.*pid //")
sleep ${AT:-70}
python3 -I ../qmp.py run/qmp-$t.sock hmp 'info cpus' 2>&1 | head -6
for k in 1 2 3; do python3 -I ../qmp.py run/qmp-$t.sock hmp 'info registers -a' 2>&1 | grep -a -E "^NIP" | tr '\n' ' ' | cut -c1-200; echo; sleep 1; done
python3 -I ../qmp.py run/qmp-$t.sock hmp 'xp /12wx 0x100' 2>&1 | head -4
python3 -I ../qmp.py run/qmp-$t.sock hmp 'xp /4wx 0xf0' 2>&1 | head -2
python3 -I ../qmp.py run/qmp-$t.sock hmp 'info pic' 2>&1 | head -30
bash ../xb.sh $t shot $t-end > /dev/null 2>&1
kill $pid 2>/dev/null; sleep 2; rm -f run/$t.qcow2
echo X2-DONE
