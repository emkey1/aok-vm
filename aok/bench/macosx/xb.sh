#!/bin/bash
# on MBP5: xb.sh TAG -- act on a machine left running by osx-run.sh (KEEP=1): xb.sh TAG shot NAME | xb.sh TAG QMP-ARGS...
M=$HOME/aok-vm-bench/macosx; tag=$1; shift
if [ "$1" = shot ]; then python3 -I ~/aok-vm-bench/qmp.py $M/run/qmp-$tag.sock shot $M/shots/$2.ppm > /dev/null; sips -s format png $M/shots/$2.ppm --out $M/shots/$2.png > /dev/null 2>&1; rm -f $M/shots/$2.ppm; echo $M/shots/$2.png
else python3 -I ~/aok-vm-bench/qmp.py $M/run/qmp-$tag.sock "$@"; fi
