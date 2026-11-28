#!/bin/bash
# on MBP5: smp-build.sh -- the engine at 61cda07b7b plus smp/smp.diff as src-smp / build-smp (PowerPC only).
export PATH=/opt/homebrew/bin:$PATH
set -e
W=$HOME/aok-vm-bench; cd $W
git -C src-aok fetch -q emkey1 aok-vm 2>/dev/null || true
[ -d src-smp ] || git -C src-aok worktree add --detach ../src-smp 61cda07b7b > /dev/null 2>&1
git -C src-smp checkout -q -- . && git -C src-smp apply $W/smp/smp.diff
git -C src-smp diff --stat | tail -1
mkdir -p build-smp && cd build-smp
[ -f build.ninja ] || ../src-smp/configure --target-list=ppc-softmmu --without-default-features --enable-fdt=internal --enable-tcg --disable-werror --disable-docs --enable-tcg-threaded-interpreter --enable-aok-gadgets --enable-pixman > configure.out 2>&1
ninja > ninja.out 2>&1 && echo "BUILD-OK build-smp" || { echo BUILD-FAILED; grep -n -E 'error|FAILED' ninja.out | head -30; }
echo SMP-BUILD-DONE
