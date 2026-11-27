#!/bin/bash
# on MBP5: look.sh NAME [QMP-ARGS...] -- do the actions, then a picture: macos9/hd/NAME.png
cd ~/aok-vm-bench/macos9/hd; n=$1; shift
python3 -I ~/aok-vm-bench/qmp.py qmp.sock "$@" shot $PWD/$n.ppm > /dev/null; sips -s format png $n.ppm --out $n.png > /dev/null 2>&1; rm -f $n.ppm; ls $n.png
