#!/bin/bash
# a64run.sh TAG WORKLOADS SECONDS [ENV=VAL...] -- the aarch64 guest on the plug-in build, output to logs/a64/TAG.log
W=$HOME/aok-vm-bench; tag=$1; list=$2; secs=$3; shift 3
( env "$@" "$W/build-aok-a64/qemu-system-aarch64-unsigned" -M ${A64_MACH:-virt} -cpu ${A64_CPU:-cortex-a72} -smp ${A64_SMP:-1} -m 2048 -display none -monitor none -serial stdio -no-reboot \
    -initrd "$W/initramfs-aarch64.cpio" -kernel "$W/kernel/vmlinuz-virt-aarch64" -append "console=ttyAMA0 rdinit=/init quiet bench=$list" < /dev/null > "$W/logs/a64/$tag.log" 2>&1 ) &
q=$!
( sleep "$secs"; kill -9 $q 2>/dev/null; pkill -9 -P $q 2>/dev/null ) > /dev/null 2>&1 &
w=$!
wait $q 2>/dev/null
kill $w 2>/dev/null
echo "$tag: $(wc -l < "$W/logs/a64/$tag.log") lines, $(grep -ac "^RESULT\|BENCH-END" "$W/logs/a64/$tag.log") result lines"
