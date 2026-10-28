#!/bin/bash
# ros-shots.sh DEVICE OUTDIR SECONDS: two staggered loops of device screenshots for SECONDS, each file named by
# the seconds since T0 (env) at the midpoint of its capture.
dev=$1; out=$2; secs=$3; mkdir -p "$out"
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
loop() {
    sleep $1
    while [ "$(perl -e "print $(now) - $T0 < $secs ? 1 : 0")" = 1 ]; do
        a=$(now); xcrun devicectl device capture screenshot --device "$dev" --destination "$out/tmp$1.png" > /dev/null 2>&1
        b=$(now); mv "$out/tmp$1.png" "$out/$(perl -e "printf '%07.2f', ($a + $b) / 2 - $T0").png" 2>/dev/null
    done
}
loop 0 & loop 1.2 & wait
