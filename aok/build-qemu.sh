#!/bin/bash
# Builds UTM's QEMU 10.0.12 twice: with UTM SE's threaded interpreter (TCTI) and with the stock TCG JIT.
set -euo pipefail
export PATH=/opt/homebrew/bin:$PATH
W=$HOME/aok-vm-bench
mkdir -p "$W/dl" "$W/src" "$W/build-tcti" "$W/build-jit"
cd "$W/dl"
[ -f qemu.tar.xz ] || curl -fL --retry 3 -o qemu.tar.xz https://github.com/utmapp/qemu/releases/download/v10.0.12-utm/qemu-10.0.12-utm.tar.xz
shasum -a 256 qemu.tar.xz
[ -f "$W/src/configure" ] || tar -xf qemu.tar.xz -C "$W/src" --strip-components=1
COMMON="--target-list=aarch64-softmmu,riscv64-softmmu --without-default-features --enable-fdt=internal --enable-tcg --disable-werror --disable-docs"
cd "$W/build-tcti"
[ -f build.ninja ] || ../src/configure $COMMON --enable-tcg-threaded-interpreter
ninja
cd "$W/build-jit"
[ -f build.ninja ] || ../src/configure $COMMON
ninja
ls -la "$W"/build-*/qemu-system-*
echo BUILD-DONE
