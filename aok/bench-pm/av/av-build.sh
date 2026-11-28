#!/bin/bash
# on MBP5: av-build.sh -- the engine at 818dd75848 plus av/av.diff (the AltiVec gadgets) as src-av / build-av:
# PowerPC only, with pixman. Run again after a new diff.
export PATH=/opt/homebrew/bin:$PATH
set -e
W=$HOME/aok-vm-bench; cd $W
[ -d src-av ] || git -C src-aok worktree add --detach ../src-av 818dd75848 > /dev/null 2>&1
git -C src-av checkout -q -- . && git -C src-av apply $W/av/av.diff
git -C src-av diff --stat | tail -1
mkdir -p build-av && cd build-av
[ -f build.ninja ] || ../src-av/configure --target-list=ppc-softmmu --without-default-features --enable-fdt=internal --enable-tcg --disable-werror --disable-docs --enable-tcg-threaded-interpreter --enable-aok-gadgets --enable-pixman > configure.out 2>&1
ninja > ninja.out 2>&1 && echo "BUILD-OK build-av" || { echo BUILD-FAILED; grep -n -E 'error|FAILED' ninja.out | head -40; }
grep -n 'warning' ninja.out | grep -i 'aok/translate\|aok/gadgets' | head
echo AV-BUILD-DONE
