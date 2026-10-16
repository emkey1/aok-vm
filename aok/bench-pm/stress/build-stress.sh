#!/bin/bash
# build-stress.sh -- the PowerPC kit's initramfs with the stress tests added: fpstress, heapstress and tlbfold, each
# built static by Debian's cross compiler (docker, colima here), and a cpio with them and a run1.sh that knows them
# and the looped workloads below, appended to the kit's initramfs.cpio (the kernel unpacks the second archive over the
# first). Out: KIT/stress/initramfs-stress.cpio, which ppc-run.sh boots with INITRD set to it:
# INITRD=... ppc-run.sh 1 fpstress OUT.
#
#   sortloop   check.sh's sort pipeline 25 times: SORTLOOP bad N of 25
#   checkloop  check.sh three times (its sort went wrong more often after the rest of it)
#   corecheck  check.sh four times with core dumps on, each core then sent out on the console, gzipped, in base64
#              between CORE-BEGIN and CORE-END: coreget.py takes them off the console log, corewalk.py reads them.
#              A sleep killed by SIGABRT first is the positive control: its core is always there.
set -e
KIT=${KIT:-$HOME/aok-guest-kit}
H=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$KIT/stress/root/bench" && cp "$H/fpstress.c" "$H/heapstress.c" "$H/tlbfold.c" "$KIT/stress/"
cat > "$KIT/stress/run1-cases.sh" <<'C'
    sound)    sh /bench/sound.sh; ./timeit sound true ;;
    fpstress) ./timeit fpstress ./fpstress ;;
    heapstress) ./heapstress; ./timeit heapstress true ;;
    tlbfold)  ./tlbfold; ./timeit tlbfold true ;;
    sortloop) n=0; bad=0
              while [ $n -lt 25 ]; do
                  r=$(tr ' ' '\n' < data1.bin | sort | uniq -c | sort -rn | head -200 | md5sum)
                  [ "$r" = "771062dd5be60e845fc93a82d0ed2f00  -" ] || { bad=$((bad + 1)); echo "SORTBAD $n $r"; }
                  n=$((n + 1))
              done
              echo "SORTLOOP bad $bad of $n"; ./timeit sortloop true ;;
    checkloop) for i in 1 2 3; do ./check.sh; done; ./timeit checkloop true ;;
    corecheck) ulimit -c unlimited; echo "/tmp/core.%e.%p" > /proc/sys/kernel/core_pattern
              echo 1 > /proc/sys/kernel/printk    # nothing from the kernel in the middle of the base64
              sleep 30 & p=$!; kill -ABRT $p; wait $p
              for i in 1 2 3 4; do ./check.sh; done
              for c in /tmp/core.*; do
                  [ -f "$c" ] || continue
                  echo "CORE-BEGIN $c $(wc -c < "$c")"; gzip -c "$c" | base64; echo "CORE-END"
              done
              ./timeit corecheck true ;;
C
python3 - "$KIT" <<'P'
import sys
kit = sys.argv[1]
s = open(kit + '/run1.sh').read()
o = '    *)        ./timeit "$w" true ;;'
assert s.count(o) == 1
s = s.replace(o, open(kit + '/stress/run1-cases.sh').read() + o)
open(kit + '/stress/root/bench/run1.sh', 'w').write(s)
P
chmod +x "$KIT/stress/root/bench/run1.sh"
docker run --rm -v "$KIT":/kit debian:trixie bash -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends gcc-powerpc-linux-gnu libc6-dev-powerpc-cross cpio > /dev/null 2>&1 && cd /kit/stress && for t in fpstress heapstress tlbfold; do powerpc-linux-gnu-gcc -static -O2 -o root/bench/$t $t.c || exit 1; done && cd root && find . | cpio -o -H newc --quiet > /kit/stress/overlay.cpio'
cat "$KIT/ppc/initramfs.cpio" "$KIT/stress/overlay.cpio" > "$KIT/stress/initramfs-stress.cpio"
ls -la "$KIT/stress/initramfs-stress.cpio"
