#!/bin/bash
# Builds one benchmark userland per guest arch as an AOK root, and the same tree as a QEMU initramfs.
# ARCHES names the ones to build (default: aarch64 riscv64; x86_64 and x86, Alpine's name for i386, are the others).
set -euo pipefail
ARCHES=${ARCHES:-"aarch64 riscv64"}
export PATH=/opt/homebrew/bin:$PATH
W=$HOME/aok-vm-bench
ISH=$HOME/git/ish-AOK/build/ish
FAKEFSIFY=$HOME/git/ish-AOK/build/tools/fakefsify
ALPINE=https://dl-cdn.alpinelinux.org/alpine/v3.24
mkdir -p "$W/dl-roots" "$W/dl-coremark" "$W/dl-kernel" "$W/kernel"
cd "$W/dl-roots"
for a in $ARCHES; do
    [ -f alpine-minirootfs-3.24.2-$a.tar.gz ] || curl -fsLO $ALPINE/releases/$a/alpine-minirootfs-3.24.2-$a.tar.gz
done
cd "$W/dl-coremark"
[ -f coremark.tar.gz ] || curl -fsL -o coremark.tar.gz https://github.com/eembc/coremark/archive/refs/heads/main.tar.gz
cd "$W/dl-kernel"
[ -f linux-virt-aarch64.apk ] || curl -fsL -o linux-virt-aarch64.apk $ALPINE/main/aarch64/linux-virt-6.18.55-r0.apk
[ -f linux-lts-riscv64.apk ] || curl -fsL -o linux-lts-riscv64.apk $ALPINE/main/riscv64/linux-lts-6.18.55-r0.apk
[ -f "$W/kernel/vmlinuz-virt-aarch64" ] || { bsdtar -xOf linux-virt-aarch64.apk boot/vmlinuz-virt > "$W/kernel/vmlinuz-virt-aarch64"; }
[ -f "$W/kernel/vmlinuz-lts-riscv64" ] || { bsdtar -xOf linux-lts-riscv64.apk boot/vmlinuz-lts > "$W/kernel/vmlinuz-lts-riscv64"; }
for a in x86_64 x86; do
    case " $ARCHES " in *" $a "*)
        [ -f linux-virt-$a.apk ] || curl -fsL -o linux-virt-$a.apk $ALPINE/main/$a/linux-virt-6.18.55-r0.apk
        [ -f "$W/kernel/vmlinuz-virt-$a" ] || { bsdtar -xOf linux-virt-$a.apk boot/vmlinuz-virt > "$W/kernel/vmlinuz-virt-$a"; }
        ;;
    esac
done
file "$W"/kernel/*

for a in $ARCHES; do
    R=$W/root-$a
    if [ ! -d "$R" ]; then
        "$FAKEFSIFY" "$W/dl-roots/alpine-minirootfs-3.24.2-$a.tar.gz" "$R"
        "$ISH" -f "$R" /bin/sh -c 'echo nameserver 1.1.1.1 > /etc/resolv.conf'
    fi
    tar -cf - -C "$W" bench | "$ISH" -f "$R" /bin/sh -c 'tar -xf - -C /'
    "$ISH" -f "$R" /bin/sh -c 'mkdir -p /bench/coremark-src && tar -xzf - -C /bench/coremark-src --strip-components=1' < "$W/dl-coremark/coremark.tar.gz"
    "$ISH" -f "$R" /bin/sh -e -c '
        apk add --no-cache python3 xz build-base >/dev/null
        cd /bench
        gcc -O2 -static -o timeit timeit.c
        gcc -O2 -static -o nbody nbody.c -lm
        cd coremark-src
        gcc -O2 -static -I. -Ilinux -Iposix -DFLAGS_STR="\"-O2 -static\"" -DPERFORMANCE_RUN=1 -DITERATIONS=0 \
            core_list_join.c core_main.c core_matrix.c core_state.c core_util.c posix/core_portme.c -o ../coremark -lrt
        cd /bench
        . ./params
        [ -f data.bin ] || python3 gen_data.py data.bin $DATA_MB
        apk del build-base >/dev/null
        rm -rf coremark-src
        cp /bench/init /init && chmod +x /init /bench/run.sh
        cd / && rm -f /bench-root.tar
        tar -cf /bench-root.tar bin etc home lib media mnt opt root run sbin srv usr var bench init
        ls -la /bench /bench-root.tar
        sha256sum /bench/coremark /bench/nbody /bench/data.bin
    '
    bsdtar -c --format=newc -f "$W/initramfs-$a.cpio" "@$R/data/bench-root.tar"
    ls -la "$W/initramfs-$a.cpio"
    bsdtar -tf "$W/initramfs-$a.cpio" | grep -cE '^(init|bench/run.sh|bin/busybox|usr/bin/python3)'
done
echo ROOTS-DONE
