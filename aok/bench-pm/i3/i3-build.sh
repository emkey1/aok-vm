#!/bin/bash
# on MBP5: i3-build.sh -- the engine at 30e130b9a6 plus i3/i3-all.diff (FP, TLB contexts, and the item 3
# gadgets) as src-i3 / build-i3: PowerPC only, with pixman. Run again after a new diff.
export PATH=/opt/homebrew/bin:$PATH
set -e
W=$HOME/aok-vm-bench; cd $W
[ -d src-i3 ] || git -C src-aok worktree add --detach ../src-i3 30e130b9a6 > /dev/null 2>&1
git -C src-i3 checkout -q -- . && git -C src-i3 apply $W/i3/i3-all.diff
git -C src-i3 diff --stat | tail -1
mkdir -p build-i3 && cd build-i3
[ -f build.ninja ] || ../src-i3/configure --target-list=ppc-softmmu --without-default-features --enable-fdt=internal --enable-tcg --disable-werror --disable-docs --enable-tcg-threaded-interpreter --enable-aok-gadgets --enable-pixman > configure.out 2>&1
ninja > ninja.out 2>&1 && echo "BUILD-OK build-i3" || { echo BUILD-FAILED; grep -n -E 'error|FAILED' ninja.out | head -30; }
grep -n 'warning' ninja.out | grep -i 'aok/translate\|aok/gadgets' | head
echo I3-BUILD-DONE
