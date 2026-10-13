#!/bin/bash
# x86-device.sh DEVICE [ROUNDS] -- both PC guests on a device (labels x86_64 and i386, the 32-bit one):
# the gates under the gadgets, compared with the Mac's QEMU_AOK=0 transcripts when MBP5 answers (the same
# extract as x64/x64cmp.sh), then the six workloads under QEMU's own engine and under the gadgets, ROUNDS
# times each (default 2), interleaved, and summarize.py's table of them.
# The device must be unlocked for every launch, and nobody else's app in front meanwhile: about an hour on
# an M4, several on an A10X.
dev=$1; rounds=${2:-2}; here=$(cd "$(dirname "$0")" && pwd)
id=app.ish.aok-qemu-bench; out=$(mktemp -d)
ext() { tr -d "\r" | sed -n "/^BENCH-START/,/^BENCH-END/p" | grep -av "^RESULT\|^aok:\|^BENCH-START"; }
gate() {    # LABEL WORKLOADS REF
    "$here/run-device.sh" "$dev" "$1" 1 "$2" 2400 > "$out/$1.txt" 2>&1 || { tail -3 "$out/$1.txt"; return; }
    xcrun devicectl device copy from --device "$dev" --domain-type appDataContainer --domain-identifier $id \
        --source Documents/serial.log --destination "$out/$1.serial" > /dev/null 2>&1
    a=$(ext < "$out/$1.serial" | md5 -q); n=$(ext < "$out/$1.serial" | wc -l | tr -d " ")
    b=$(ssh -o BatchMode=yes -o ConnectTimeout=8 MBP5.local "cat aok-vm-bench/logs/x64/$3.log" 2> /dev/null | ext | md5 -q)
    if [ "$n" -gt 0 ] && [ "$a" = "$b" ]; then v=IDENTICAL; else v="DIFFERENT, or no reference (device $a, Mac $b)"; fi
    echo "$1 against $3: $n lines $v"
}
for g in x86_64 i386; do
    r=ref; [ $g = i386 ] && r=ref32
    gate $g-check-1 check,fptest,memtest $r-g1
    gate $g-x86test-1 x86test $r-xt
done
: > "$out/wl.txt"
for ((i = 1; i <= rounds; i++)); do
    for g in x86_64 i386; do
        "$here/run-device.sh" "$dev" $g-tctish-$i 0 coremark,nbody,python,xz,sha256,awk 3600 | tee -a "$out/wl.txt" | grep -a "^DONE\|^ERROR\|no DONE"
        "$here/run-device.sh" "$dev" $g-aokq-$i 1 coremark,nbody,python,xz,sha256,awk 3600 | tee -a "$out/wl.txt" | grep -a "^DONE\|^ERROR\|no DONE"
    done
done
grep -a "^WL " "$out/wl.txt" > "$out/wl-lines.txt"
python3 "$here/../summarize.py" "$out/wl-lines.txt" 2> /dev/null || cat "$out/wl-lines.txt"
echo "(kept in $out)"
