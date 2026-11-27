#!/bin/bash
# on MBP5: the engine with the single-precision FP gadgets (worktree src-fp: src-flush's commit + fp-single.diff,
# or VARIANT's edit on top for a control) as build-fp[-VARIANT]: PowerPC only, with pixman.
export PATH=/opt/homebrew/bin:$PATH
set -e
W=$HOME/aok-vm-bench; cd $W; v=${1:+-$1}
if [ ! -d src-fp$v ]; then
    git -C src-aok worktree add --detach ../src-fp$v $(git -C src-flush rev-parse HEAD) > /dev/null 2>&1
    git -C src-fp$v apply $W/fp/fp-single.diff
    [ -n "$1" ] && python3 -I $W/fp/variant.py $1 src-fp$v/target/ppc/tcg/aok/gadgets.S
fi
git -C src-fp$v diff --stat | tail -1
mkdir -p build-fp$v && cd build-fp$v
[ -f build.ninja ] || ../src-fp$v/configure --target-list=ppc-softmmu --without-default-features --enable-fdt=internal --enable-tcg --disable-werror --disable-docs --enable-tcg-threaded-interpreter --enable-aok-gadgets --enable-pixman > configure.out 2>&1
ninja > ninja.out 2>&1 && echo "BUILD-OK build-fp$v" || { echo "BUILD-FAILED build-fp$v"; grep -n -E 'error|FAILED' ninja.out | head -20; }
