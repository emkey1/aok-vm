#!/bin/bash
# vec-image.sh [32] -- the x86_64 gate image with the vector tests, or (32) the 32-bit x86 one, on the Mac
# that drives both build hosts.
#
# x64/vec/*.c are iSH-AOK's x86 vector tests (its tests/manual/x86 at b08154c0f, copied 2026-10-14 and
# this repository's own since): SSE to SSE4.2, VEX (AVX, AVX2, FMA3, F16C, BMI), EVEX (AVX-512), MXCSR and
# the undefined encodings, each carrying its answers (from an AMD Ryzen, or Intel SDE for AVX-512 and the
# #UD tests) and printing a last line that says PASS or FAIL; amd64_evex_step.c, AVX-512 under a debugger's
# single step, is this repository's own. x64/vec32/*.c are the same tests for 32-bit code (iSH-AOK's i386_*
# at e9acddff0, copied 2026-10-18), with the same answers: Intel SDE runs no 32-bit code on camd, and the
# 64-bit and 32-bit forms of these insns compute the same. They are built static on camd (an x86_64 Linux
# with gcc and its 32-bit libraries, SSE2 on as in the Alpine x86 root iSH-AOK builds them in; CAMD names
# it), then added to MBP5's gate image (MBP5 names it) as an overlay with this tree's bench/run1.sh, whose
# `vec` workload runs them all and `vec-NAME` one:
#     X64_CPU=max X64_GUEST=x86_64-vec x64run.sh TAG vec SECONDS
#     X64_CPU=max X64_GUEST=x86-vec x64run.sh TAG vec SECONDS         (vec-image.sh 32)
# (X64_CPU before the command: x64run.sh reads it itself. After SECONDS it only reaches QEMU's environment,
# and the guest runs on qemu64, with no AVX-512 or SSE4.2.)
# writes ~/aok-vm-bench/initramfs-x86_64-vec.cpio (initramfs-x86-vec.cpio) and the kernel's name for it.
set -e
here=$(cd "$(dirname "$0")" && pwd)
CAMD=${CAMD:-camd}
MBP5=${MBP5:-MBP5.local}     # (words: ssh options may come first)
SSH="ssh -o BatchMode=yes"
if [ "$1" = 32 ]; then src=vec32; cc="gcc -m32 -msse2"; guest=x86; else src=vec; cc=gcc; guest=x86_64; fi
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
COPYFILE_DISABLE=1 tar -cf - -C "$here" $src test_common.h | $SSH $CAMD "
    set -e
    rm -rf ~/aokvm-$src && mkdir -p ~/aokvm-$src/out/bench/vec && cd ~/aokvm-$src && tar -xf - 2> /dev/null
    mv $src vec && cd vec && for f in *.c; do $cc -O2 -static -o ../out/bench/vec/\${f%.c} \"\$f\" -lm; done"
$SSH $CAMD "cd ~/aokvm-$src/out && tar -cf - bench" > "$T/vec.tar"
mkdir -p "$T/o" && tar -xf "$T/vec.tar" -C "$T/o" && install -m 755 "$here/../bench/run1.sh" "$T/o/bench/run1.sh"
COPYFILE_DISABLE=1 tar -cf - -C "$T/o" bench | $SSH $MBP5 "
    set -e
    W=~/aok-vm-bench; t=\$(mktemp -d); tar -xf - -C \$t
    (cd \$t && bsdtar -c --format=newc --uid 0 --gid 0 -f overlay.cpio bench)
    cat \$W/initramfs-$guest.cpio \$t/overlay.cpio > \$W/initramfs-$guest-vec.cpio
    ln -sf vmlinuz-virt-$guest \$W/kernel/vmlinuz-virt-$guest-vec
    ls \$t/bench/vec | wc -l | tr -d ' '; ls -la \$W/initramfs-$guest-vec.cpio | cut -c30-; rm -rf \$t"
