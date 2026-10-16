#!/bin/bash
# build-pm.sh -- the PowerPC and 68k engines for the engine-swap race: UTM's QEMU 10.0.12 with TCTI (what the
# app ships for those machines) and this fork's tree (src-aok, utm-gl) with TCTI, for macOS.
set -e
export PATH=/opt/homebrew/bin:$PATH
W=$HOME/aok-vm-bench
T=--target-list=ppc-softmmu,ppc64-softmmu,m68k-softmmu
COMMON="$T --without-default-features --enable-fdt=internal --enable-tcg --disable-werror --disable-docs --enable-tcg-threaded-interpreter"
mkdir -p $W/build-pm-utm $W/build-pm-aok
(cd $W/build-pm-utm && { [ -f build.ninja ] || ../src/configure $COMMON > /dev/null; } && ninja > $W/logs/build-pm-utm.log 2>&1) && echo "UTM 10 built" || { echo "UTM 10 FAILED"; tail -20 $W/logs/build-pm-utm.log; }
(cd $W/build-pm-aok && { [ -f build.ninja ] || ../src-aok/configure $COMMON --enable-aok-gadgets > /dev/null; } && ninja > $W/logs/build-pm-aok.log 2>&1) && echo "ours built" || { echo "ours FAILED"; tail -20 $W/logs/build-pm-aok.log; }
ls -la $W/build-pm-*/qemu-system-* | awk '{print $5, $9}'
