#!/bin/bash
# cpu-image.sh [ARCH...] -- iSH-AOK's processor tests (tests.list) built and added to MBP5's guest images, on the
# Mac that drives it. ARCH: x86_64, i386, aarch64, riscv64 (default all four).
#
# src/ is iSH-AOK's tests/manual x86/, arm64/, riscv64/, the portable tests about the processor and the
# assembly tests of tests/arm64 and tests/riscv64 (iSH-AOK 8cebcdb86, copied 2026-10-18), without the ones
# that check iSH-AOK's own CPU (cpu_identity, x86_cpuid_xgetbv, x86_xsave), its syscall 0xacc0 (crypto/,
# aes_gcm_accel) or what Linux does not offer (riscv64 single-step). Each is built static inside iSH-AOK's
# Alpine root of its architecture on MBP5 (build-in.sh; ~/git/ish-AOK/build/ish and its roots, as
# update-roots.sh builds fptest), the toolchain iSH-AOK's own runs use. The binaries go into an overlay of
# the guest's initramfs under /bench/cpu/ARCH, with tests.list as /bench/cpu/list: x86_64 and i386 (32-bit
# programs, whose answers are a 64-bit kernel's) into initramfs-x86_64-cpu.cpio, aarch64 and riscv64 into
# initramfs-aarch64-cpu.cpio and initramfs-riscv64-cpu.cpio. run1.sh's `cpu` workload runs them; cpu-run.sh
# boots a guest on the engine or an oracle (cpu-camd.sh: x86 on camd's own cores), cpu-cmp.py compares.
set -e
here=$(cd "$(dirname "$0")" && pwd)
MBP5=${MBP5:-MBP5.local}     # (words: ssh options may come first)
SSH="ssh -o BatchMode=yes"
arches=${*:-x86_64 i386 aarch64 riscv64}
COPYFILE_DISABLE=1 tar -cf - -C "$here" src tests.list build-in.sh -C "$here/../bench" run1.sh |
    $SSH $MBP5 "mkdir -p /tmp/cpukit && rm -rf /tmp/cpukit/src && tar -xf - -C /tmp/cpukit"
$SSH $MBP5 "arches='$arches' bash -s" <<'REMOTE'
set -e
W=~/aok-vm-bench; K=/tmp/cpukit; ISH=~/git/ish-AOK/build/ish; R=~/git/ish-AOK/build
root() { case $1 in x86_64) echo $R/alpine-amd64-test ;; i386) echo $R/alpine-i386-test ;;
                    aarch64) echo $R/alpine-arm64-324 ;; riscv64) echo $R/alpine-riscv64-test ;; esac; }
for a in $arches; do
    rm -rf $K/out/$a
    ( cd $K && tar -cf - src tests.list build-in.sh |
        $ISH -f $(root $a) /bin/sh -e -c "rm -rf /tmp/cpukit && mkdir -p /tmp/cpukit && cd /tmp/cpukit &&
            tar -xf - && sh build-in.sh $a > /dev/null && tar -cf - out" | tar -xf - -C $K ) &
done
wait
for a in $arches; do
    echo "$a: $(ls $K/out/$a | wc -l | tr -d ' ') built, $(grep -c BUILD-FAIL $K/out/$a.log) failed"
    grep BUILD-FAIL $K/out/$a.log | head -20 || true
done
for g in x86_64 aarch64 riscv64; do
    case $g in x86_64) parts="x86_64 i386" ;; *) parts=$g ;; esac
    t=$(mktemp -d); mkdir -p $t/bench/cpu; n=0
    for a in $parts; do if [ -d $K/out/$a ]; then cp -R $K/out/$a $t/bench/cpu/$a; n=1; fi; done
    if [ $n = 0 ]; then rm -rf $t; continue; fi
    cp $K/tests.list $t/bench/cpu/list; install -m 755 $K/run1.sh $t/bench/run1.sh
    (cd $t && bsdtar -c --format=newc --uid 0 --gid 0 -f overlay.cpio bench)
    cat $W/initramfs-$g.cpio $t/overlay.cpio > $W/initramfs-$g-cpu.cpio
    echo "initramfs-$g-cpu.cpio: $(du -h $W/initramfs-$g-cpu.cpio | cut -f1)"; rm -rf $t
done
REMOTE
