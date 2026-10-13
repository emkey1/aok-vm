#!/bin/bash
# Builds the tctiSH fork of QEMU (11.1, an improved TCTI) the same way build-qemu.sh builds UTM's.
set -euo pipefail
export PATH=/opt/homebrew/bin:$PATH
W=$HOME/aok-vm-bench
[ -d "$W/src-tctish/.git" ] || git clone -q --depth 1 -b tctish-edition https://github.com/tctiSH/qemu "$W/src-tctish"
git -C "$W/src-tctish" log --oneline -1
mkdir -p "$W/build-tctish"
cd "$W/build-tctish"
[ -f build.ninja ] || ../src-tctish/configure --target-list=aarch64-softmmu,riscv64-softmmu --without-default-features \
    --enable-fdt=internal --enable-tcg --disable-werror --disable-docs --enable-tcg-threaded-interpreter
ninja
ls -la "$W"/build-tctish/qemu-system-*
echo BUILD-DONE
