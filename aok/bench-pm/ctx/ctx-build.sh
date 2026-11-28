#!/bin/bash
# on MBP5: ctx-build.sh -- the engine at 30e130b9a6 plus ctx/ctx-all.diff (the FP commit and the TLB context
# cache) as src-ctx / build-ctx: the four guests with a gate, with pixman. Run again after a new diff.
export PATH=/opt/homebrew/bin:$PATH
set -e
W=$HOME/aok-vm-bench; cd $W
[ -d src-ctx ] || git -C src-aok worktree add --detach ../src-ctx 30e130b9a6 > /dev/null 2>&1
git -C src-ctx checkout -q -- . && git -C src-ctx apply $W/ctx/ctx-all.diff
git -C src-ctx diff --stat | tail -1
mkdir -p build-ctx && cd build-ctx
[ -f build.ninja ] || ../src-ctx/configure --target-list=ppc-softmmu,x86_64-softmmu,aarch64-softmmu,riscv64-softmmu --without-default-features --enable-fdt=internal --enable-tcg --disable-werror --disable-docs --enable-tcg-threaded-interpreter --enable-aok-gadgets --enable-pixman > configure.out 2>&1
ninja > ninja.out 2>&1 && echo "BUILD-OK $(ls qemu-system-*-unsigned | tr '\n' ' ')" || { echo BUILD-FAILED; grep -n -E 'error|FAILED' ninja.out | head -20; }
grep -n 'warning' ninja.out | grep -i 'cputlb\|helper_regs\|mmu_helper' | head
echo CTX-BUILD-DONE
