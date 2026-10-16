#!/bin/bash
# ppc-sync.sh [ninja args] -- the PowerPC front end's dev loop: this Mac's ~/git/qemu-aok working tree to MBP5's
# ~/aok-vm-bench/src-ppc, and ninja in build-ppc there (qemu-system-ppc, gadgets on, TCTI). The front end is
# developed on the core branch (aok-gadgets), which lacks utm-se's OpenPIC fix (qemu-aok f2d57747ba): src-ppc
# has it patched in, and the sync leaves those two files alone, so that the irq-47 storm stays out of the gates.
# src-ppc was seeded from src-aok on MBP5 (a full copy over Tailscale is slow).
H=100.116.123.106; SSH="ssh -o BatchMode=yes -o HostKeyAlias=mbp5.local"
rsync -a --delete -e "$SSH" --exclude .git --exclude 'build*/' --exclude .cache --exclude /subprojects/ --exclude /roms/ --exclude /hw/intc/openpic.c --exclude /include/hw/ppc/openpic.h ~/git/qemu-aok/ $H:aok-vm-bench/src-ppc/ || exit 1
$SSH $H 'bash -s' -- "$@" <<'R'
export PATH=/opt/homebrew/bin:$PATH
W=$HOME/aok-vm-bench; mkdir -p $W/build-ppc && cd $W/build-ppc
[ -f build.ninja ] || ../src-ppc/configure --target-list=ppc-softmmu --without-default-features --enable-fdt=internal \
    --enable-tcg --disable-werror --disable-docs --enable-tcg-threaded-interpreter --enable-aok-gadgets > $W/logs/build-ppc-conf.log 2>&1 \
    || { tail -20 $W/logs/build-ppc-conf.log; exit 1; }
ninja "$@" > $W/logs/build-ppc.log 2>&1 && echo "build-ppc OK" || { grep -E 'error|Error' $W/logs/build-ppc.log | head -20; echo "build-ppc FAILED"; exit 1; }
R
