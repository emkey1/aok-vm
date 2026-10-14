#!/bin/bash
# shot.sh NAME [ppm] -- the running machine's screen now, as ROS_DIR/NAME.png (and NAME.ppm, kept, with "ppm",
# for screen.py).
W=${ROS_DIR:-$HOME/aok-vm-bench/reactos}
rm -f "$W/$1.ppm"
echo "screendump $W/$1.ppm" | nc -U -w 2 "$W/mon.sock" > /dev/null
n=0; until [ -s "$W/$1.ppm" ] || [ $n -ge 20 ]; do sleep 0.5; n=$((n+1)); done
sips -s format png "$W/$1.ppm" --out "$W/$1.png" > /dev/null 2>&1
[ "$2" = ppm ] || rm -f "$W/$1.ppm"
