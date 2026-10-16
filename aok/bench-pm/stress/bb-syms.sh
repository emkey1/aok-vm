#!/bin/bash
# bb-syms.sh -- in debian:trixie with the kit at /kit: the PowerPC busybox build-kit.sh makes, kept unstripped,
# for symbols to read a guest's core with (corewalk.py CORE /kit/dbg/busybox.syms). The build is the kit's to the
# byte but for its build ID and time, which it says by comparing with /kit/dbg/busybox.orig, the kit's own
# (copy it there first). Out: /kit/dbg/busybox_unstripped{,.map}, /kit/dbg/busybox.syms
#   mkdir -p ~/aok-guest-kit/dbg && cp bb-syms.sh ~/aok-guest-kit/dbg/
#   docker run --rm -v ~/aok-guest-kit:/kit debian:trixie bash /kit/dbg/bb-syms.sh
set -e
export DEBIAN_FRONTEND=noninteractive
sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources
apt-get update -qq
apt-get install -y -qq --no-install-recommends gcc libc6-dev gcc-powerpc-linux-gnu libc6-dev-powerpc-cross make dpkg-dev \
    binutils-powerpc-linux-gnu ca-certificates file > /dev/null
mkdir -p /build && cd /build
apt-get source -qq busybox > /dev/null 2>&1; mv busybox-[0-9]* busybox-src
BB=/build/bb-ppc; cp -a busybox-src $BB
make -s -C $BB defconfig > /dev/null
sed -i -e 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' -e 's/^CONFIG_TC=y/# CONFIG_TC is not set/' \
    -e 's/^CONFIG_FEATURE_TC_INGRESS=y/# CONFIG_FEATURE_TC_INGRESS is not set/' $BB/.config
yes "" | make -s -C $BB oldconfig > /dev/null
make -s -C $BB CROSS_COMPILE=powerpc-linux-gnu- -j"$(nproc)" > /dev/null
cp $BB/busybox_unstripped $BB/busybox /kit/dbg/
cp $BB/busybox_unstripped.map /kit/dbg/ 2>/dev/null || true
powerpc-linux-gnu-nm -n $BB/busybox_unstripped > /kit/dbg/busybox.syms
cmp $BB/busybox /kit/dbg/busybox.orig && echo "IDENTICAL to the kit's" || echo "differs from the kit's"
