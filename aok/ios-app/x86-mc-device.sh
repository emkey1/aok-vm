#!/bin/bash
# x86-mc-device.sh DEVICE [CPUS] -- multi-core x86-64 on a device: the gates, x86test, kmovtest and tsotest with the
# max CPU (tsotest on CPUS parallel vCPUs, with the engine's barriers and without them: QEMU_AOK_X86_NOMB, its
# control), then the four parallel checks (stresst) on one vCPU, on CPUS taking turns on one thread and on CPUS in
# parallel, and CoreMark alone and on one of two parallel vCPUs (what the barriers cost). CPUS defaults to 3
# (the A10X's performance cores). Each run's serial log is kept; the summary lines are printed as they come.
dev=$1; n=${2:-3}; here=$(cd "$(dirname "$0")" && pwd)
id=app.ish.aok-qemu-bench; out=$(mktemp -d)
MT='"AOKQ_ACCEL":"tcg,tb-size=256,thread=multi"'; ST='"AOKQ_ACCEL":"tcg,tb-size=256,thread=single"'
MAX='"AOKQ_CPU":"max,-la57"'
ext() { tr -d "\r" | sed -n "/^BENCH-START/,/^BENCH-END/p" | grep -av "^RESULT\|^aok:\|^BENCH-START"; }
run() {     # LABEL AOK WORKLOADS SMP ENV
    AOKQ_ENV=$5 "$here/run-device.sh" "$dev" "$1" "$2" "$3" 5400 "$4" > "$out/$1.txt" 2>&1 ||
        { echo "$1: $(tail -2 "$out/$1.txt" | tr "\n" " ")"; }
    xcrun devicectl device copy from --device "$dev" --domain-type appDataContainer --domain-identifier $id \
        --source Documents/serial.log --destination "$out/$1.serial" > /dev/null 2>&1
}
show() {    # LABEL PATTERN
    echo "$1: $(tr -d "\r" < "$out/$1.serial" 2> /dev/null | grep -a "$2" | tr "\n" "|")"
}
gate() {    # LABEL WORKLOADS REF ENV
    run "$1" 1 "$2" 1 "$4"
    a=$(ext < "$out/$1.serial" | md5 -q); c=$(ext < "$out/$1.serial" | wc -l | tr -d " ")
    b=$(ssh -o BatchMode=yes -o ConnectTimeout=8 -o HostKeyAlias=mbp5.local 100.116.123.106 \
        "cat aok-vm-bench/logs/x64/$3.log" 2> /dev/null | ext | md5 -q)
    if [ "$c" -gt 0 ] && [ "$a" = "$b" ]; then v=IDENTICAL; else v="DIFFERENT (device $a, Mac $b)"; fi
    echo "$1 against $3: $c lines $v"
}
gate x86_64-check-1 check,fptest,memtest ref-g1 ''
gate x86_64-x86test-1 x86test ref-xt ''
gate x86_64-x86testmax-1 x86test adx64-1 "$MAX"
run x86_64-kmov-1 1 kmovtest 1 "$MAX"; show x86_64-kmov-1 "^KMOV ok\|^KMOV FAIL\|BAD\|Illegal"
run x86_64-tso-1 1 tsotest $n "$MT,$MAX"; show x86_64-tso-1 "^TSO"
run x86_64-tsonomb-1 1 tsotest $n "$MT,$MAX,\"QEMU_AOK_X86_NOMB\":\"1\""; show x86_64-tsonomb-1 "^TSO"
for r in 1 2; do
    run x86_64-st1-$r 1 stresst 1 "$MAX"; show x86_64-st1-$r "^RESULT\|^STRESS 1"
    run x86_64-st${n}s-$r 1 stresst $n "$ST,$MAX"; show x86_64-st${n}s-$r "^RESULT\|^STRESS 1"
    run x86_64-st${n}m-$r 1 stresst $n "$MT,$MAX"; show x86_64-st${n}m-$r "^RESULT\|^STRESS 1"
    run x86_64-cm1-$r 1 coremark 1 "$MAX"; show x86_64-cm1-$r "^RESULT"
    run x86_64-cm2m-$r 1 coremark 2 "$MT,$MAX"; show x86_64-cm2m-$r "^RESULT"
done
"$here/keep-awake.sh" "$dev" 3600 > /dev/null 2>&1
echo "(kept in $out)"
