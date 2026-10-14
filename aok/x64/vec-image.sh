#!/bin/bash
# vec-image.sh -- the x86_64 gate image with the vector tests, on the Mac that drives both build hosts.
#
# x64/vec/*.c are iSH-AOK's x86 vector tests (its tests/manual/x86 at b08154c0f, copied 2026-10-14 and
# this repository's own since): SSE to SSE4.2, VEX (AVX, AVX2, FMA3, F16C, BMI), EVEX (AVX-512), MXCSR and
# the undefined encodings, each carrying its answers (from an AMD Ryzen, or Intel SDE for AVX-512 and the
# #UD tests) and printing a last line that says PASS or FAIL; amd64_evex_step.c, AVX-512 under a debugger's
# single step, is this repository's own. They are built static on camd (an x86_64
# Linux with gcc; CAMD names it), then added to MBP5's gate image (MBP5 names it) as an overlay with this
# tree's bench/run1.sh, whose `vec` workload runs them all and `vec-NAME` one:
#     X64_GUEST=x86_64-vec x64run.sh TAG vec SECONDS X64_CPU=max
# writes ~/aok-vm-bench/initramfs-x86_64-vec.cpio and the kernel's name for it.
set -e
here=$(cd "$(dirname "$0")" && pwd)
CAMD=${CAMD:-camd}
MBP5=${MBP5:-MBP5.local}     # (words: ssh options may come first)
SSH="ssh -o BatchMode=yes"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
COPYFILE_DISABLE=1 tar -cf - -C "$here" vec test_common.h | $SSH $CAMD '
    set -e
    rm -rf ~/aokvm-vec && mkdir -p ~/aokvm-vec/out/bench/vec && cd ~/aokvm-vec && tar -xf - 2> /dev/null
    cd vec && for f in *.c; do gcc -O2 -static -o ../out/bench/vec/${f%.c} "$f" -lm; done' 
$SSH $CAMD 'cd ~/aokvm-vec/out && tar -cf - bench' > "$T/vec.tar"
mkdir -p "$T/o" && tar -xf "$T/vec.tar" -C "$T/o" && install -m 755 "$here/../bench/run1.sh" "$T/o/bench/run1.sh"
COPYFILE_DISABLE=1 tar -cf - -C "$T/o" bench | $SSH $MBP5 '
    set -e
    W=~/aok-vm-bench; t=$(mktemp -d); tar -xf - -C $t
    (cd $t && bsdtar -c --format=newc --uid 0 --gid 0 -f overlay.cpio bench)
    cat $W/initramfs-x86_64.cpio $t/overlay.cpio > $W/initramfs-x86_64-vec.cpio
    ln -sf vmlinuz-virt-x86_64 $W/kernel/vmlinuz-virt-x86_64-vec
    ls $t/bench/vec | wc -l | tr -d " "; ls -la $W/initramfs-x86_64-vec.cpio | cut -c30-; rm -rf $t'
