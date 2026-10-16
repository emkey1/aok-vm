#!/bin/bash
# build-kit.sh -- run in debian:trixie with this directory at /kit: the race guests for the PowerPC Mac
# (mac99, 32-bit, big-endian) and the 68k Mac (q800): a Linux kernel each (Debian's linux-source-6.12,
# pmac32_defconfig and mac_defconfig with the serial console and an initramfs), and an initramfs each with
# a static busybox and xz, and the race's programs (timeit, CoreMark, n-body, fptest, memtest) and data,
# under the same /init and /bench/run1.sh as the other four guests.
#   docker run --rm -v ~/aok-guest-kit:/kit -v aok-kit-build:/build debian:trixie bash /kit/build-kit.sh [ppc|m68k ...]
# The kit directory holds this script, coremark.tar.gz (setup-roots.sh fetches it), aok/bench's init, run1.sh,
# check.sh, timeit.c, nbody.c, fptest.c, memtest.c and gen_data.py, and this directory's mixer.c. Out: KIT/ppc and
# KIT/m68k, a vmlinux and an initramfs.cpio each, which cyc-pm.sh boots from ~/aok-vm-bench/kit on MBP5. Docker
# here is colima (give it CPUs).
set -e
ARCHES=${*:-ppc m68k}
export DEBIAN_FRONTEND=noninteractive
sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources
apt-get update -qq
apt-get install -y -qq --no-install-recommends gcc libc6-dev gcc-powerpc-linux-gnu gcc-m68k-linux-gnu libc6-dev-powerpc-cross \
    libc6-dev-m68k-cross make bc bison flex libssl-dev libelf-dev cpio xz-utils dpkg-dev python3 \
    linux-source-6.12 ca-certificates file > /dev/null
B=/build; mkdir -p $B; cd $B
[ -d busybox-src ] || { apt-get source -qq busybox > /dev/null 2>&1; mv busybox-[0-9]* busybox-src; }
[ -d xz-src ] || { apt-get source -qq xz-utils > /dev/null 2>&1; mv xz-utils-[0-9]* xz-src; }
[ -d linux ] || { tar -xf /usr/src/linux-source-6.12.tar.xz; mv linux-source-6.12 linux; }
[ -d coremark ] || { mkdir coremark; tar -xzf /kit/coremark.tar.gz -C coremark --strip-components=1; }

for a in $ARCHES; do
    case $a in
    ppc)  KA=powerpc; CC_=powerpc-linux-gnu; DEFC=pmac32_defconfig ;;
    m68k) KA=m68k;    CC_=m68k-linux-gnu;    DEFC=mac_defconfig ;;
    esac
    O=/kit/$a; mkdir -p $O
    echo "== $a: kernel"
    K=$B/k-$a; mkdir -p $K
    make -s -C $B/linux O=$K ARCH=$KA CROSS_COMPILE=$CC_- $DEFC
    $B/linux/scripts/config --file $K/.config -e BLK_DEV_INITRD -e RD_GZIP -e SERIAL_PMACZILOG \
        -e SERIAL_PMACZILOG_CONSOLE -e DEVTMPFS -e DEVTMPFS_MOUNT -e PROC_FS -e SYSFS -e TMPFS
    [ $a = m68k ] && $B/linux/scripts/config --file $K/.config -e SERIAL_PMACZILOG_TTYS
    # The PowerMac's sound (snd-powermac: AWACS/Screamer through DBDMA), with OSS's /dev/dsp for the "sound"
    # workload, which plays data through it for QEMU's wav audiodev to record.
    [ $a = ppc ] && $B/linux/scripts/config --file $K/.config -e SOUND -e SND -e SND_POWERMAC -e SND_OSSEMUL \
        -e SND_PCM_OSS -e SND_MIXER_OSS -e I2C -e I2C_POWERMAC
    make -s -C $B/linux O=$K ARCH=$KA CROSS_COMPILE=$CC_- olddefconfig
    make -s -C $B/linux O=$K ARCH=$KA CROSS_COMPILE=$CC_- -j"$(nproc)" vmlinux
    cp $K/vmlinux $O/vmlinux
    echo "== $a: busybox"
    BB=$B/bb-$a; rm -rf $BB; cp -a $B/busybox-src $BB
    make -s -C $BB defconfig > /dev/null
    sed -i -e 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' -e 's/^CONFIG_TC=y/# CONFIG_TC is not set/' \
        -e 's/^CONFIG_FEATURE_TC_INGRESS=y/# CONFIG_FEATURE_TC_INGRESS is not set/' $BB/.config
    yes "" | make -s -C $BB oldconfig > /dev/null
    make -s -C $BB CROSS_COMPILE=$CC_- -j"$(nproc)" > /dev/null
    echo "== $a: xz"
    X=$B/xz-$a; rm -rf $X; cp -a $B/xz-src $X
    (cd $X && ./configure -q --host=$CC_ --disable-shared --enable-static --disable-nls --disable-doc \
        > /dev/null && make -s -j"$(nproc)" LDFLAGS=-all-static > /dev/null)
    echo "== $a: the race's programs"
    R=$B/root-$a; rm -rf $R; mkdir -p $R/bench $R/bin $R/sbin $R/usr/bin $R/usr/sbin $R/proc $R/sys $R/dev $R/tmp $R/etc
    make -s -C $BB CROSS_COMPILE=$CC_- CONFIG_PREFIX=$R install > /dev/null
    rm -f $R/usr/bin/xz         # busybox's applet link: a copy onto it would overwrite busybox
    cp $X/src/xz/xz $R/usr/bin/xz
    G="$CC_-gcc -static"
    $G -O2 -o $R/bench/timeit /kit/timeit.c
    $G -O2 -o $R/bench/nbody /kit/nbody.c -lm
    $G -O1 -ffp-contract=off -fno-math-errno -o $R/bench/fptest /kit/fptest.c -lm
    $G -O2 -o $R/bench/memtest /kit/memtest.c
    [ $a = ppc ] && $G -O2 -o $R/bench/mixer /kit/mixer.c
    (cd $B/coremark && $G -O2 -I. -Ilinux -Iposix -DFLAGS_STR="\"-O2 -static\"" -DPERFORMANCE_RUN=1 -DITERATIONS=0 \
        core_list_join.c core_main.c core_matrix.c core_state.c core_util.c posix/core_portme.c -o $R/bench/coremark -lrt)
    cp /kit/run1.sh /kit/check.sh $R/bench/; cp /kit/init $R/init; chmod +x $R/init $R/bench/*.sh
    # "sound": 256 KB through /dev/dsp (the kit's own workload, added to its copy of run1.sh)
    printf '%s\n' '#!/bin/sh' 'cat /proc/asound/cards; ls /dev/dsp* 2>&1; /bench/mixer' \
        'dd if=/bench/data1.bin of=/dev/dsp bs=4096 count=64 2>&1 | tail -1; echo "SOUND rc=$?"' > $R/bench/sound.sh
    chmod +x $R/bench/sound.sh
    sed -i 's|^    \*)        ./timeit "$w" true ;;|    sound)    sh /bench/sound.sh; ./timeit sound true ;;\n    *)        ./timeit "$w" true ;;|' $R/bench/run1.sh
    grep -q '^    sound)' $R/bench/run1.sh || { echo "run1.sh: no sound case"; exit 1; }
    [ -f /kit/data.bin ] || python3 /kit/gen_data.py /kit/data.bin 8
    cp /kit/data.bin $R/bench/data.bin
    head -c 2097152 /kit/data.bin > $R/bench/data2.bin
    head -c 1048576 /kit/data.bin > $R/bench/data1.bin
    (cd $R && find . | cpio -o -H newc --quiet) > $O/initramfs.cpio
    file $O/vmlinux $R/bench/coremark $R/bin/busybox $R/usr/bin/xz | cut -c1-150
    if file $R/bin/busybox $R/usr/bin/xz $R/bench/* | grep -q 'dynamically linked'; then echo "NOT STATIC"; exit 1; fi
    ls -la $O
done
