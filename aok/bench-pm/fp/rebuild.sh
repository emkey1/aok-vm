#!/bin/bash
# on MBP5: put the current fp-single.diff into src-fp (replacing the one applied before) and build build-fp.
export PATH=/opt/homebrew/bin:$PATH
set -e
W=$HOME/aok-vm-bench; cd $W
git -C src-fp checkout -- target/ppc/tcg/aok/gadgets.S target/ppc/tcg/aok/translate.c
git -C src-fp apply $W/fp/fp-single.diff
git -C src-fp diff --stat | tail -1
cd build-fp
ninja > ninja.out 2>&1 && echo "BUILD-OK build-fp" || { echo "BUILD-FAILED build-fp"; grep -n -E 'error|FAILED' ninja.out | head -30; }
