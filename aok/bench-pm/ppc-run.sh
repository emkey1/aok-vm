#!/bin/bash
# ppc-run.sh MODE WORKLOADS OUT [SECS] [extra qemu args] -- the PowerPC kit on build-ppc's qemu-system-ppc, QEMU_AOK=MODE,
# to poweroff; the console to OUT (QEMU_AOK_STATS=1's report at its end).
W=$HOME/aok-vm-bench; MODE=$1; WL=$2; OUT=$3; SECS=${4:-600}; shift 4 2>/dev/null
ND=$W/src/pc-bios/ppc-ndrvloader
QEMU_AOK=$MODE QEMU_AOK_STATS=${QEMU_AOK_STATS-1} $W/build-ppc/qemu-system-ppc-unsigned -L $W/src/pc-bios -M mac99,via=pmu -m 512 \
  -nographic -nodefaults -serial stdio -monitor none -audio none -device loader,addr=0x4000000,file=$ND \
  -prom-env "boot-command=init-program go" -device virtio-tablet-pci -kernel $W/kit/ppc/vmlinux \
  -initrd ${INITRD:-$W/kit/ppc/initramfs.cpio} -append "console=ttyS0 rdinit=/init bench=$WL then=poweroff" -no-reboot "$@" > $OUT 2>&1 &
p=$!; for i in $(seq 1 $SECS); do kill -0 $p 2>/dev/null || break; sleep 1; done
kill -0 $p 2>/dev/null && { kill -9 $p; echo "TIMEOUT after ${SECS}s" >> $OUT; }; wait $p 2>/dev/null; echo "exit $? after ${i}s"
