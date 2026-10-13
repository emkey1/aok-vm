#!/bin/bash
# a64cyc.sh REPS: the aarch64 guest's workloads in host CPU cycles, QEMU's engine (TCTI) against the AOK plug-in
W=$HOME/aok-vm-bench; reps=${1:-2}
one() { # one TAG WORKLOAD [ENV...]
  tag=$1; wl=$2; shift 2
  env "$@" /usr/bin/time -l "$W/build-aok-a64/qemu-system-aarch64-unsigned" -M virt -cpu cortex-a72 -smp 1 -m 2048 -display none -monitor none -serial stdio -no-reboot -initrd "$W/initramfs-aarch64.cpio" -kernel "$W/kernel/vmlinuz-virt-aarch64" -append "console=ttyAMA0 rdinit=/init quiet bench=$wl" < /dev/null > /tmp/a64cyc.out 2> /tmp/a64cyc.time
  echo "CYC $tag $wl $(awk '/cycles elapsed/{print $1}' /tmp/a64cyc.time) $(grep -a "^RESULT $wl " /tmp/a64cyc.out | awk '{print $3}')"
}
for r in $(seq $reps); do
  for wl in none coremark nbody python xz sha256 awk; do
    one tcti $wl QEMU_AOK=0
    one aok $wl X=1
    one aoknofp $wl QEMU_AOK_NO_FP=1
  done
done
echo CYC-DONE
