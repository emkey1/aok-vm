#!/bin/bash
# boot-aok.sh WORKLOADS [extra qemu args...] -- boot the riscv64 guest under the AOK-gadgets build and run the
# named workloads (comma separated; "none" just boots). Environment: QEMU_AOK=0 turns the gadgets off.
W=$HOME/aok-vm-bench; wl=${1:-none}; shift
exec "$W/build-aok/qemu-system-riscv64-unsigned" -M virt -cpu rv64 -L "$W/src-aok/pc-bios" -smp 1 -m 2048 \
    -display none -monitor none -serial stdio -no-reboot -initrd "$W/initramfs-riscv64.cpio" \
    -kernel "$W/kernel/Image-lts-riscv64" -append "console=ttyS0 rdinit=/init quiet bench=$wl" "$@" < /dev/null
