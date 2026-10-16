#!/bin/bash
# irq47.sh BUILD TRIES [trace...]: boot the ppc kit to poweroff TRIES times; count irq-47 storms
W=$HOME/aok-vm-bench; B=$1; N=${2:-8}; shift 2
ND=$W/src/pc-bios/ppc-ndrvloader; mkdir -p /tmp/irq47
T=(); for t in "$@"; do T+=(-trace "$t"); done
storms=0
for try in $(seq 1 $N); do
  out=/tmp/irq47/$(basename $B)-out-$try.txt; tr=/tmp/irq47/$(basename $B)-trace-$try.log; rm -f $tr
  $B/qemu-system-ppc-unsigned -L $W/src/pc-bios -M mac99,via=pmu -m 512 -nographic -nodefaults -serial stdio \
    -monitor none -audio none -device loader,addr=0x4000000,file=$ND -prom-env "boot-command=init-program go" \
    -device virtio-tablet-pci -kernel $W/kit/ppc/vmlinux -initrd $W/kit/ppc/initramfs.cpio \
    -append "console=ttyS0 rdinit=/init bench=none then=poweroff" -no-reboot "${T[@]}" ${T:+-D $tr} > $out 2>&1 &
  p=$!; for i in $(seq 1 120); do kill -0 $p 2>/dev/null || break; sleep 1; done; kill -9 $p 2>/dev/null; wait $p 2>/dev/null
  if grep -q 'nobody cared' $out; then storms=$((storms+1)); echo "try $try: STORM"; else echo "try $try: ok (${i}s)"; fi
done
echo "storms $storms/$N"
