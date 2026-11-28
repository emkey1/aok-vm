#!/bin/bash
# on MBP5: x1.sh TAG [EXTRA...] -- Tiger (tiger-final5, throwaway overlay) on build-smp with -smp 2 and a verbose
# boot: a picture every 15 s for 4 minutes (macosx/shots/TAG-NN.png), then sysctl over ssh if it answers.
export PATH=/opt/homebrew/bin:$PATH
cd ~/aok-vm-bench/macosx; t=$1; shift
rm -f run-$t.log
(KEEP=1 IMG=$PWD/work/tiger-final5.qcow2 nohup bash ../osx-run.sh $t smp 5 app -smp ${CPUS:-2} -prom-env "boot-args=-v" -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2224-:22 -device sungem,netdev=n0,mac=52:54:00:A0:C0:FA "$@" > run-$t.log 2>&1 &)
until grep -q "left running" run-$t.log 2>/dev/null; do sleep 2; done
pid=$(grep "left running" run-$t.log | sed "s/.*pid //")
for i in $(seq -w 1 16); do sleep 15; kill -0 $pid 2>/dev/null || { echo "QEMU ended"; break; }; bash ../xb.sh $t shot $t-$i > /dev/null 2>&1; done
r=$(ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=20 -p 2224 timcook@127.0.0.1 'sysctl hw.ncpu hw.activecpu; uptime' 2>&1); echo "$r"
kill $pid 2>/dev/null; sleep 2; rm -f run/$t.qcow2
tail -3 run/qemu-$t.log 2>/dev/null
echo X1-DONE
