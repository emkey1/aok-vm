#!/bin/bash
# on MBP5: sv-build.sh -- the engine at dd744be8ea plus sv/sv.diff (sc, the decrementer, tlbie, tlbsync, lswx
# and stswx) as src-sv / build-sv: PowerPC only, with pixman. Run again after a new diff.
export PATH=/opt/homebrew/bin:$PATH
set -e
W=$HOME/aok-vm-bench; cd $W
[ -d src-sv ] || git -C src-aok worktree add --detach ../src-sv dd744be8ea > /dev/null 2>&1
git -C src-sv checkout -q -- . && git -C src-sv apply $W/sv/sv.diff
git -C src-sv diff --stat | tail -1
mkdir -p build-sv && cd build-sv
[ -f build.ninja ] || ../src-sv/configure --target-list=ppc-softmmu --without-default-features --enable-fdt=internal --enable-tcg --disable-werror --disable-docs --enable-tcg-threaded-interpreter --enable-aok-gadgets --enable-pixman > configure.out 2>&1
ninja > ninja.out 2>&1 && echo "BUILD-OK build-sv" || { echo BUILD-FAILED; grep -n -E 'error|FAILED' ninja.out | head -40; }
grep -n 'warning' ninja.out | grep -i 'aok/translate\|aok/gadgets' | head
echo SV-BUILD-DONE
