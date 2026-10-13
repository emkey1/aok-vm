#!/bin/bash
# a64hang.sh TRIES [ENV=VAL...]: boot the 4-CPU guest until one boot hangs, then ask the monitor where its CPUs are
W=$HOME/aok-vm-bench; n=$1; shift
for i in $(seq $n); do
  rm -f /tmp/a64mon.sock
  env "$@" "$W/build-aok-a64/qemu-system-aarch64-unsigned" -M virt -cpu ${A64_CPU:-cortex-a72} -smp ${A64_SMP:-4} -m 2048 -display none -monitor unix:/tmp/a64mon.sock,server,nowait -serial stdio -no-reboot -initrd "$W/initramfs-aarch64.cpio" -kernel "$W/kernel/vmlinuz-virt-aarch64" -append "console=ttyAMA0 earlycon rdinit=/init bench=none" < /dev/null > "$W/logs/a64/hang.log" 2>&1 &
  q=$!
  sleep 7
  if grep -aq "Run /init" "$W/logs/a64/hang.log"; then kill -9 $q; wait $q 2>/dev/null; continue; fi
  echo "trial $i hung after: $(tail -1 "$W/logs/a64/hang.log" | cut -c1-80)"
  ( printf "info cpus\ninfo registers -a\n"; sleep 2 ) | nc -U /tmp/a64mon.sock > "$W/logs/a64/hang.mon" 2>&1
  sample $q 1 -file "$W/logs/a64/hang.sample" > /dev/null 2>&1
  kill -9 $q; wait $q 2>/dev/null
  exit 0
done
echo "no hang in $n"
