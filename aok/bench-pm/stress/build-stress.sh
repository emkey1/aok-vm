#!/bin/bash
# build-stress.sh -- the PowerPC kit's initramfs with fpstress added: fpstress.c built static by Debian's
# cross compiler (docker, colima here), and a cpio with it and a run1.sh that knows it, appended to the kit's
# initramfs.cpio (the kernel unpacks the second archive over the first). Out: KIT/stress/initramfs-stress.cpio,
# which ppc-run.sh boots with INITRD set to it: INITRD=... ppc-run.sh 1 fpstress OUT.
set -e
KIT=${KIT:-$HOME/aok-guest-kit}
H=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$KIT/stress/root/bench" && cp "$H/fpstress.c" "$KIT/stress/"
python3 - "$KIT" <<'P'
import sys
kit = sys.argv[1]
s = open(kit + '/run1.sh').read()
o = '    *)        ./timeit "$w" true ;;'
assert s.count(o) == 1
s = s.replace(o, '    sound)    sh /bench/sound.sh; ./timeit sound true ;;\n    fpstress) ./timeit fpstress ./fpstress ;;\n' + o)
open(kit + '/stress/root/bench/run1.sh', 'w').write(s)
P
chmod +x "$KIT/stress/root/bench/run1.sh"
docker run --rm -v "$KIT":/kit debian:trixie bash -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends gcc-powerpc-linux-gnu libc6-dev-powerpc-cross cpio > /dev/null 2>&1 && cd /kit/stress && powerpc-linux-gnu-gcc -static -O2 -o root/bench/fpstress fpstress.c && cd root && find . | cpio -o -H newc --quiet > /kit/stress/overlay.cpio'
cat "$KIT/ppc/initramfs.cpio" "$KIT/stress/overlay.cpio" > "$KIT/stress/initramfs-stress.cpio"
ls -la "$KIT/stress/initramfs-stress.cpio"
