#!/bin/bash
# on MBP5: lookx.sh NAME [QMP-ARGS...] -- act on the Tiger work machine, then a picture: macosx/work/NAME.png
cd ~/aok-vm-bench/macosx/work; n=$1; shift
python3 -I ~/aok-vm-bench/qmp.py qmp.sock "$@" shot $PWD/$n.ppm > /dev/null; sips -s format png $n.ppm --out $n.png > /dev/null 2>&1; rm -f $n.ppm; ls $n.png
