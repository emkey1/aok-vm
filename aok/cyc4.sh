#!/bin/bash
# cyc4.sh REPS [WORKLOADS] -- the six workloads in each guest the AOK VM engine has a front end for
# (riscv64, aarch64, x86_64, and x86, Alpine's 32-bit one), under QEMU's own engine there (the threaded
# interpreter: QEMU_AOK=0, the same binary) and under the AOK gadgets. One boot runs all the workloads;
# cycwrap counts what the QEMU process spends between a workload's first line and its last, in host CPU
# cycles, which do not move with the machine's load or clock speed. GUESTS narrows the list.
#   cyc4.sh 2 | tee cyc4.log; python3 cyc4.py cyc4.log
W=$HOME/aok-vm-bench; reps=${1:-2}; list=${2:-coremark,nbody,python,xz,sha256,awk}
common="-smp 1 -m 2048 -display none -monitor none -serial stdio -no-reboot"
one() { # one GUEST ENGINE [ENV]
  g=$1; eng=$2; shift 2; extra=
  case $g in
    riscv64) q="$W/build-aok/qemu-system-riscv64-unsigned -M virt -cpu rv64 -L $W/src-aok/pc-bios $common
                -initrd $W/initramfs-riscv64.cpio -kernel $W/kernel/Image-lts-riscv64"; con=ttyS0 ;;
    aarch64) q="$W/build-aok-a64/qemu-system-aarch64-unsigned -M virt -cpu cortex-a72 $common
                -initrd $W/initramfs-aarch64.cpio -kernel $W/kernel/vmlinuz-virt-aarch64"; con=ttyAMA0 ;;
    # (rdrand, and the kernel told to trust it: an x86 guest with no entropy waits for it, whatever runs it)
    x86_64)  q="$W/build-aok-x64/qemu-system-x86_64-unsigned -M q35 -cpu qemu64,+rdrand -nic none -L $W/src-aok/pc-bios $common
                -initrd $W/initramfs-x86_64.cpio -kernel $W/kernel/vmlinuz-virt-x86_64"; con=ttyS0; extra=random.trust_cpu=on ;;
    x86)     q="$W/build-aok-x64/qemu-system-x86_64-unsigned -M q35 -cpu qemu32,+rdrand -nic none -L $W/src-aok/pc-bios $common
                -initrd $W/initramfs-x86.cpio -kernel $W/kernel/vmlinuz-virt-x86"; con=ttyS0; extra=random.trust_cpu=on ;;
  esac
  env "$@" "$W/cycwrap" -q "$g-$eng" $q -append "console=$con rdinit=/init quiet $extra bench=$list" < /dev/null 2>&1 | grep -a "^WL "
}
for r in $(seq $reps); do
  for g in ${GUESTS:-riscv64 aarch64 x86_64 x86}; do
    one $g qemu QEMU_AOK=0
    one $g aok X=1
  done
done
echo CYC-DONE
