#!/bin/bash
# profile-tcti.sh ARCH WORKLOAD -- boots UTM SE's engine, waits for the workload to start, samples the process
# for 8 seconds and prints where its time goes (a breakdown only: sampling perturbs speed).
set -u
W=$HOME/aok-vm-bench; a=$1; wl=$2
common=(-smp 1 -m 2048 -display none -monitor none -serial stdio -no-reboot -initrd "$W/initramfs-$a.cpio")
case $a in
aarch64) cmd=("$W/build-tcti/qemu-system-aarch64-unsigned" -M virt -cpu cortex-a72 "${common[@]}" -kernel "$W/kernel/vmlinuz-virt-aarch64" -append "console=ttyAMA0 rdinit=/init quiet bench=$wl") ;;
riscv64) cmd=("$W/build-tcti/qemu-system-riscv64-unsigned" -M virt -cpu rv64 -L "$W/src/pc-bios" "${common[@]}" -kernel "$W/kernel/Image-lts-riscv64" -append "console=ttyS0 rdinit=/init quiet bench=$wl") ;;
esac
"${cmd[@]}" > "$W/profile-$a-$wl.out" 2>&1 < /dev/null &
pid=$!
until grep -aq "WL-START" "$W/profile-$a-$wl.out" 2>/dev/null; do sleep 0.5; done
sleep 1
sample $pid 8 -mayDie -file "$W/profile-$a-$wl.sample" > /dev/null 2>&1
kill -9 $pid 2>/dev/null
# Top-of-stack symbols across all threads, heaviest first.
awk '/^Sort by top of stack/{p=1; next} /^Binary Images/{p=0} p && NF' "$W/profile-$a-$wl.sample" | head -45
