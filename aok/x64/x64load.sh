#!/bin/bash
# x64load.sh TAG ROUNDS PER SECONDS [ENV=VAL...] -- x64try.sh PER at a time beside eight busy loops, ROUNDS times,
# and the count of each verdict (logs/x64/load-TAG.txt has them one by one). For what only a loaded host shows:
#   X64_GUEST=x86 X64_CPU=qemu32,+rdrand X64_SMP=4 X64_ACCEL=tcg,thread=multi X64_BENCH=poke ./x64load.sh pk 2 8 420
W=$HOME/aok-vm-bench; tag=$1; rounds=$2; per=$3; secs=$4; shift 4
hogs=(); for i in 1 2 3 4 5 6 7 8; do ( while :; do :; done ) & hogs+=($!); done
trap 'kill "${hogs[@]}" 2>/dev/null' EXIT
out=$W/logs/x64/load-$tag.txt; : > "$out"
for ((r = 1; r <= rounds; r++)); do
    tries=()
    for ((k = 1; k <= per; k++)); do "$W/x64try.sh" "$tag-$r-$k" "$secs" "$@" >> "$out" 2> /dev/null & tries+=($!); done
    wait "${tries[@]}"
done
echo "$tag: GOOD $(grep -c GOOD "$out") BAD $(grep -c BAD "$out") TIMEOUT $(grep -c TIMEOUT "$out") EXITED $(grep -c EXITED "$out")"
