#!/bin/bash
# a64smp.sh TRIALS SECONDS [ENV=VAL...]: how often does the 4-CPU aarch64 guest reach its init?
W=$HOME/aok-vm-bench; n=$1; secs=$2; shift 2; ok=0; where=
for i in $(seq $n); do
  ( env "$@" "$W/build-aok-a64/qemu-system-aarch64-unsigned" -M virt -cpu ${A64_CPU:-cortex-a72} -smp ${A64_SMP:-4} -m 2048 -display none -monitor none -serial stdio -no-reboot -initrd "$W/initramfs-aarch64.cpio" -kernel "$W/kernel/vmlinuz-virt-aarch64" -append "console=ttyAMA0 earlycon rdinit=/init bench=none" < /dev/null > "$W/logs/a64/smp.log" 2>&1 & q=$!; sleep "$secs"; kill -9 $q ) 2>/dev/null
  if grep -aq "Run /init" "$W/logs/a64/smp.log"; then ok=$((ok+1)); else where="$where | $(tail -1 "$W/logs/a64/smp.log" | cut -c16-60)"; cp "$W/logs/a64/smp.log" "$W/logs/a64/smp-fail.log"; fi
done
echo "$*: $ok/$n reach init$where"
