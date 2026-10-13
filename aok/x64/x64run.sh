#!/bin/bash
# x64run.sh TAG WORKLOADS SECONDS [ENV=VAL...] -- the x86_64 guest on the plug-in build, output to logs/x64/TAG.log
# X64_GUEST=x86 is the 32-bit guest (Alpine's x86), on the same binary; X64_CPU, X64_SMP, X64_MACH, X64_ACCEL as named.
# (rdrand, and the kernel told to trust it: without a source of entropy a guest waits a quarter of a minute for some)
W=$HOME/aok-vm-bench; tag=$1; list=$2; secs=$3; shift 3
mkdir -p "$W/logs/x64"
( env "$@" "$W/build-aok-x64/qemu-system-x86_64-unsigned" -M ${X64_MACH:-q35} -cpu ${X64_CPU:-qemu64,+rdrand} -smp ${X64_SMP:-1} ${X64_ACCEL:+-accel $X64_ACCEL} -m 2048 -display none -monitor none -serial stdio -no-reboot -nic none \
    -L "$W/src-aok/pc-bios" -initrd "$W/initramfs-${X64_GUEST:-x86_64}.cpio" -kernel "$W/kernel/vmlinuz-virt-${X64_GUEST:-x86_64}" -append "console=ttyS0 rdinit=/init quiet random.trust_cpu=on bench=$list" < /dev/null > "$W/logs/x64/$tag.log" 2>&1 ) &
q=$!
( sleep "$secs"; kill -9 $q 2>/dev/null; pkill -9 -P $q 2>/dev/null ) > /dev/null 2>&1 &
w=$!
wait $q 2>/dev/null
kill $w 2>/dev/null
echo "$tag: $(wc -l < "$W/logs/x64/$tag.log") lines, $(grep -ac "^RESULT\|BENCH-END" "$W/logs/x64/$tag.log") result lines"
