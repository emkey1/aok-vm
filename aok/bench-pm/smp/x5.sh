#!/bin/bash
# on MBP5: x5.sh TAG CPUS [EXTRA...] -- Tiger on build-smp with CPUS CPUs, left running (KEEP) with its ssh at
# 127.0.0.1:2224; tries ssh until it answers and prints what it got.
export PATH=/opt/homebrew/bin:$PATH
cd ~/aok-vm-bench/macosx; t=$1; n=$2; shift 2
rm -f run-$t.log
(KEEP=1 IMG=$PWD/work/tiger-final5.qcow2 nohup bash ../osx-run.sh $t smp 120 app -smp $n -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2224-:22 -device sungem,netdev=n0,mac=52:54:00:A0:C0:FA "$@" > run-$t.log 2>&1 &)
until grep -q "left running" run-$t.log 2>/dev/null; do sleep 2; done
for i in $(seq 1 12); do
  r=$(ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=30 -p 2224 timcook@127.0.0.1 'sysctl -n hw.ncpu hw.activecpu; uptime' 2>&1) && { echo "ssh ok after $i tries: $r" | tr '\n' ' '; echo; break; }
  echo "try $i: $r"; sleep 10
done
echo X5-UP
