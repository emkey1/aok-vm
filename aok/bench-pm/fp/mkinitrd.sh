#!/bin/bash
# on MBP5: mkinitrd.sh -- kit/ppc/initramfs-stress-s.cpio again, with fp/fpstress as /bench/fpstress.
W=$HOME/aok-vm-bench
T=$(mktemp -d); mkdir -p $T/bench; cp $W/fp/fpstress $T/bench/fpstress; chmod 755 $T/bench/fpstress
(cd $T && find bench | cpio -o -H newc 2>/dev/null) > $T/x.cpio
cat $W/kit/ppc/initramfs-stress.cpio $T/x.cpio > $W/kit/ppc/initramfs-stress-s.cpio; rm -rf $T
ls -la $W/kit/ppc/initramfs-stress-s.cpio
