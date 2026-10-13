#!/bin/bash
# x64cyc.sh REPS [WORKLOADS]: the x86_64 guest's workloads in host CPU cycles, QEMU's engine (TCTI) against the AOK plug-in.
# One boot runs them all; cycwrap counts what the QEMU process spends between a workload's first line and its last.
W=$HOME/aok-vm-bench; reps=${1:-2}; list=${2:-coremark,nbody,python,xz,sha256,awk}
one() { # one TAG [ENV...]
  tag=$1; shift
  env "$@" "$W/cycwrap" -q "$tag" "$W/build-aok-x64/qemu-system-x86_64-unsigned" -M q35 -cpu qemu64,+rdrand -smp 1 -m 2048 -display none -monitor none -serial stdio -no-reboot -nic none -L "$W/src-aok/pc-bios" -initrd "$W/initramfs-x86_64.cpio" -kernel "$W/kernel/vmlinuz-virt-x86_64" -append "console=ttyS0 rdinit=/init quiet random.trust_cpu=on bench=$list" < /dev/null 2>&1 | grep -a "^WL "
}
for r in $(seq $reps); do
  one tcti QEMU_AOK=0
  one aok X=1
done
echo CYC-DONE
