#!/bin/bash
# x64gate.sh [SECONDS] -- the x86 front end's gates, both guests at once: each transcript against QEMU_AOK=0's
# (logs/x64/ref-*.log and ref32-*.log, which x64run.sh makes with QEMU_AOK=0 the same way). A line a gate.
W=$HOME/aok-vm-bench; secs=${1:-1800}
g() {   # NAME REF WORKLOADS [ENV=VAL...]
    local tag=$1 ref=$2 list=$3; shift 3
    ( env "$@" "$W/x64run.sh" "$tag" "$list" "$secs" > /dev/null; "$W/x64cmp.sh" "$tag" "$ref" ) &
}
for a in 64 32; do
    if [ $a = 32 ]; then e=(X64_GUEST=x86 X64_CPU=qemu32,+rdrand); p=aok32 r=ref32; else e=(X64_GUEST=x86_64); p=aok r=ref; fi
    g $p-g1  $r-g1  check,fptest,memtest "${e[@]}"
    g $p-mt4 $r-mt4 check,stress,memtest "${e[@]}" X64_SMP=4 X64_ACCEL=tcg,thread=multi
    g $p-xt  $r-xt  x86test "${e[@]}"
done
g aok-g4 ref-g4 check,stress,memtest X64_SMP=4 X64_ACCEL=tcg,thread=single
g aok-fpv ref-fpv fptestv
wait
