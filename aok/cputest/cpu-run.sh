#!/bin/bash
# cpu-run.sh GUEST MODE TAG [WORKLOAD] [SECONDS] -- on MBP5: GUEST's image of the processor tests (cpu-image.sh)
# booted and its `cpu` workload (or WORKLOAD: cpu-ARCH, cpu-NAME) run, the transcript in logs/cpu/TAG.log.
# GUEST: x86_64 (x86_64 and i386 tests), aarch64, riscv64. MODE:
#   engine  the AOK gadgets (the Mac builds build-aok-x64, build-aok-a64, build-aok: TCTI and the gadgets)
#   tcg     the same binary with QEMU_AOK=0: QEMU's own translator, TCTI alone
#   hvf     aarch64 only: Homebrew's QEMU with Hypervisor.framework, the tests on this Mac's own cores
# CPU sets -cpu (default: x86_64 max,-la57 and aarch64 max, what the engine offers; riscv64 rv64, the app's
# default; hvf host). SMP sets -smp.
W=$HOME/aok-vm-bench; guest=$1 mode=$2 tag=$3 wl=${4:-cpu} secs=${5:-3600}
mkdir -p "$W/logs/cpu"
env=() acc=()
[ "$mode" = tcg ] && env=(QEMU_AOK=0)
case $guest in
x86_64)  q=$W/build-aok-x64/qemu-system-x86_64-unsigned; cpu=${CPU:-max,-la57}
         m=(-M q35 -L "$W/src-aok/pc-bios" -nic none); k=$W/kernel/vmlinuz-virt-x86_64; con=ttyS0
         extra="random.trust_cpu=on" ;;
aarch64) q=$W/build-aok-a64/qemu-system-aarch64-unsigned; cpu=${CPU:-max}
         m=(-M virt); k=$W/kernel/vmlinuz-virt-aarch64; con=ttyAMA0; extra=
         if [ "$mode" = hvf ]; then q=/opt/homebrew/bin/qemu-system-aarch64; cpu=${CPU:-host}; acc=(-accel hvf); fi ;;
riscv64) q=$W/build-aok/qemu-system-riscv64-unsigned; cpu=${CPU:-rv64}
         m=(-M virt -L "$W/src-aok/pc-bios"); k=$W/kernel/Image-lts-riscv64; con=ttyS0; extra= ;;
*)       echo "usage: $0 x86_64|aarch64|riscv64 engine|tcg|hvf TAG [WORKLOAD] [SECONDS]" >&2; exit 1 ;;
esac
( env "${env[@]}" "$q" "${m[@]}" "${acc[@]}" -cpu "$cpu" -smp "${SMP:-1}" -m 2048 -display none -monitor none \
    -serial stdio -no-reboot -initrd "$W/initramfs-$guest-cpu.cpio" -kernel "$k" \
    -append "console=$con rdinit=/init quiet $extra bench=$wl" < /dev/null > "$W/logs/cpu/$tag.log" 2>&1 ) &
p=$!
( sleep "$secs"; kill -9 $p 2>/dev/null; pkill -9 -P $p 2>/dev/null ) > /dev/null 2>&1 &
w=$!
wait $p 2>/dev/null
kill $w 2>/dev/null
echo "$tag: $(grep -ac '^CPUTEST-END' "$W/logs/cpu/$tag.log") tests ran"
