#!/bin/bash
# cyc-ppc.sh REPS [WORKLOADS] -- the PowerPC front end's race: build-ppc's qemu-system-ppc with QEMU_AOK=0 (TCTI
# alone) against QEMU_AOK=1 (the gadgets), interleaved, host CPU cycles per workload as cycwrap counts them.
W=$HOME/aok-vm-bench; reps=${1:-3}; list=${2:-coremark,nbody,xz,sha256,awk}
q="$W/build-ppc/qemu-system-ppc-unsigned -M mac99,via=pmu -cpu g4 -m 1024 -L $W/src/pc-bios -kernel $W/kit/ppc/vmlinux -initrd $W/kit/ppc/initramfs.cpio"
for r in $(seq $reps); do
  for m in 0 1; do
    env QEMU_AOK=$m "$W/cycwrap" -q "ppc-aok$m-$r" $q -display none -monitor none -serial stdio -no-reboot \
      -append "console=ttyS0 rdinit=/init quiet bench=$list" < /dev/null 2>&1 | grep -a "^WL "
  done
done
echo CYC-DONE
