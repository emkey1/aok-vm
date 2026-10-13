#!/bin/bash
# race.sh ROUNDS [ARCHS] [ENGINES] -- strictly one process at a time: for each round and guest arch, run the
# whole workload list under AOK, QEMU's JIT and UTM SE's interpreter (tcti), each wrapped in cycwrap.
set -u
W=$HOME/aok-vm-bench; ISH=$HOME/git/ish-AOK/build/ish
ROUNDS=${1:-3}; ARCHS=${2:-"aarch64 riscv64"}; ENGINES=${3:-"aok jit tcti"}
LIST=${WORKLOADS:-"coremark,nbody,python,xz,sha256,awk"}
for r in $(seq "$ROUNDS"); do
    for a in $ARCHS; do
        common=(-smp 1 -m 2048 -display none -monitor none -serial stdio -no-reboot -initrd "$W/initramfs-$a.cpio")
        for eng in $ENGINES; do
            case $eng-$a in
            aok-*) "$W/cycwrap" "$a-$eng-$r" "$ISH" -f "$W/root-$a" /bench/run1.sh ${LIST//,/ } ;;
            *-aarch64) "$W/cycwrap" "$a-$eng-$r" "$W/build-$eng/qemu-system-aarch64-unsigned" -M virt -cpu cortex-a72 "${common[@]}" \
                           -kernel "$W/kernel/vmlinuz-virt-aarch64" -append "console=ttyAMA0 rdinit=/init quiet bench=$LIST" ;;
            *-riscv64) "$W/cycwrap" "$a-$eng-$r" "$W/build-$eng/qemu-system-riscv64-unsigned" -M virt -cpu rv64 -L "$W/src/pc-bios" "${common[@]}" \
                           -kernel "$W/kernel/Image-lts-riscv64" -append "console=ttyS0 rdinit=/init quiet bench=$LIST" ;;
            esac
        done
    done
done
echo RACE-DONE
