#!/bin/bash
# install-qemu-utm.sh [ios-tci|ios_simulator-tci] [stock] -- put the AOK-gadgets QEMU into UTM's sysroot as
# its RISC-V, ARM64, x86, PowerPC and 68k engines, or put UTM's own back.
#
# The first run keeps UTM's frameworks and RISC-V firmware under utm/stock-PLATFORM. Then each library that
# build-qemu-utm.sh installed is wrapped as qemu-ARCH-softmmu.framework by UTM's own scripts/fixup.sh
# (which rewrites its imports to the sysroot's frameworks), and the RISC-V firmware of the same QEMU
# (OpenSBI, EDK2) replaces the sysroot's; ARM64's and the PC's firmware stay UTM's. Every other
# architecture's QEMU is left as UTM built it.
#
# PowerPC (ppc, ppc64) and the 68k Mac (m68k) are this tree's TCTI too, since build 7: no gadgets yet, but
# tctiSH's threaded interpreter in place of the QEMU 10 UTM ships (the race: aok/bench-pm). Their firmware
# (OpenBIOS, ppc-ndrvloader, m68k-declrom) stays UTM's.
#
# x86 is one engine for both PCs. The x86-64 QEMU runs 32-bit guests too, and it is the one with the
# gadgets (their operands are offsets into a CPU state whose registers are 64 bits wide, which the i386
# build's are not): the app starts it for UTM's "i386" machines as well (UTMQemuVirtualMachine's
# engineArchitecture), and since build 6 carries no i386 engine (it was a copy, 85 MB). A 32-bit system
# finds a CPU that could do more than it asks for, as on any PC made since 2004.
set -e
W=${W:-$HOME/aok-vm-bench}
U=$W/utm
PLAT=ios-tci
case $1 in ios-tci|ios_simulator-tci) PLAT=$1; shift ;; esac
PREFIX=$U/UTM/sysroot-$PLAT-arm64
STOCK=$U/stock-$PLAT
OUT=$U/qemu-out-$PLAT${AOK_GL:+-gl}     # AOK_GL=1: the build with OpenGL and virglrenderer
ARCHS="riscv64 aarch64 x86_64 ppc ppc64 m68k"
FILES="opensbi-riscv64-generic-fw_dynamic.bin edk2-riscv-code.fd edk2-riscv-vars.fd"

mkdir -p "$STOCK"
for a in $ARCHS; do
    [ -d "$STOCK/qemu-$a-softmmu.framework" ] || cp -a "$PREFIX/Frameworks/qemu-$a-softmmu.framework" "$STOCK/"
done
for f in $FILES; do [ -f "$STOCK/$f" ] || cp -p "$PREFIX/share/qemu/$f" "$STOCK/"; done
if [ "$1" = stock ]; then
    for a in $ARCHS; do
        rsync -a --delete "$STOCK/qemu-$a-softmmu.framework/" "$PREFIX/Frameworks/qemu-$a-softmmu.framework/"
    done
    for f in $FILES; do cp -p "$STOCK/$f" "$PREFIX/share/qemu/"; done
    echo "sysroot: UTM's own RISC-V, ARM64, x86, PowerPC and 68k QEMU"
    exit 0
fi
for a in $ARCHS; do
    "$U/UTM/scripts/fixup.sh" -p "$PLAT" -s "$PREFIX" -m 15.0 "$OUT/lib/libqemu-$a-softmmu.dylib"
done
for f in $FILES; do cp -p "$OUT/share/qemu/$f" "$PREFIX/share/qemu/"; done
for a in $ARCHS; do
    FW=$PREFIX/Frameworks/qemu-$a-softmmu.framework
    [ "$a" = riscv64 ] && otool -L "$FW/qemu-$a-softmmu" | tail -n +2 | awk '{print "  " $1}'
    echo "sysroot: this tree's $a QEMU ($(nm "$FW/qemu-$a-softmmu" | grep -c aok_gadget_) gadgets)"
done
