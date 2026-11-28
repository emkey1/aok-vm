#!/bin/bash
# on MBP5: x4.sh TAG CPUS [EXTRA...] -- Tiger on build-smp with CPUS CPUs (threads of their own): in its
# Terminal the CPU count, sshd's state, and a shell loop timed alone and two at once (pictures TAG-a, TAG-b).
export PATH=/opt/homebrew/bin:$PATH
cd ~/aok-vm-bench/macosx; t=$1; n=$2; shift 2
rm -f run-$t.log
(KEEP=1 IMG=$PWD/work/tiger-final5.qcow2 nohup bash ../osx-run.sh $t smp 150 app -smp $n -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2224-:22 -device sungem,netdev=n0,mac=52:54:00:A0:C0:FA "$@" > run-$t.log 2>&1 &)
until grep -q "left running" run-$t.log 2>/dev/null; do sleep 2; done
pid=$(grep "left running" run-$t.log | sed "s/.*pid //")
echo "QEMU threads: $(ps -M -p $pid | tail -n +2 | wc -l)"
X() { bash ../xb.sh $t "$@"; }
X key meta_l-shift-u sleep 4 type terminal sleep 2 key meta_l-o sleep 15
X type "clear; sysctl hw.ncpu hw.activecpu; ps ax | grep [s]shd; grep -i sshd /var/log/system.log | tail -3" key ret sleep 6
X shot $t-a > /dev/null
X type "clear; L() { i=0; while [ \$i -lt 40000 ]; do i=\$((i+1)); done; }; time L; time (L & L & wait)" key ret
sleep ${WAIT:-150}; X shot $t-b > /dev/null
kill $pid 2>/dev/null; sleep 2; rm -f run/$t.qcow2
echo X4-DONE
