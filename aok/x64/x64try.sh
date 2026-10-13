#!/bin/bash
# x64try.sh TAG SECONDS [ENV=VAL...] -- boot the x86_64 guest until it says BENCH-START or the kernel complains: prints which
W=$HOME/aok-vm-bench; tag=$1; secs=$2; shift 2
log="$W/logs/x64/try-$tag.log"; mkdir -p "$W/logs/x64"
( env "$@" "$W/build-aok-x64/qemu-system-x86_64-unsigned" -M ${X64_MACH:-q35} -cpu ${X64_CPU:-qemu64,+rdrand} -smp ${X64_SMP:-1} ${X64_ACCEL:+-accel $X64_ACCEL} -m 2048 -display none -monitor none -serial stdio -no-reboot -nic none \
    -L "$W/src-aok/pc-bios" -initrd "$W/initramfs-${X64_GUEST:-x86_64}.cpio" -kernel "$W/kernel/vmlinuz-virt-${X64_GUEST:-x86_64}" -append "console=ttyS0 rdinit=/init quiet random.trust_cpu=on bench=${X64_BENCH:-check}" < /dev/null > "$log" 2>&1 ) &
q=$!
v=TIMEOUT
for ((i = 0; i < secs * 2; i++)); do
    sleep 0.5
    if grep -aq "BUG\|Oops\|panic\|segfault\|general protection\|Segmentation\|not syncing" "$log"; then v=BAD; break; fi
    if grep -aq "${X64_GOOD:-BENCH-END}" "$log"; then v=GOOD; break; fi
    kill -0 $q 2>/dev/null || { v=EXITED; break; }
done
kill -9 $q 2>/dev/null; pkill -9 -P $q 2>/dev/null; wait $q 2>/dev/null
echo "$tag: $v after $((i / 2))s, $(wc -l < "$log" | tr -d ' ') lines"
