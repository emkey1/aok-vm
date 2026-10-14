#!/bin/bash
# build.sh [OS-ARCH ...] -- AOK VM's base machines: iSH-AOK's own root file systems, Alpine 3.24.2 and
# Devuan 6 for aarch64, x86_64, i386 (iSH-AOK's "x86") and riscv64, each as a machine of its own. Without
# arguments all eight; an argument is e.g. devuan-aarch64. On the build Mac (MBP5), in about ten minutes.
#
# A machine is three files: an Alpine kernel (linux-virt, linux-lts on riscv64: the same kernels as the
# Alpine guests of this directory, in $W/kernel and $W/dl-kernel), an initramfs made here (busybox, and the
# drivers that reach the root disk; init), and a root disk: an 8 GB qcow2 with the archive iSH-AOK ships
# for that OS and architecture, the kernel's modules, /AOK/tools (iSH-AOK's scripts, as aok-update brings
# them), aok-update, and the few files that make it start by itself (job.sh says which). The disks are made
# in the arm64 Alpine build VM of build-devuan-disk.sh, on the Mac's own CPU, where an ext4 file system can
# be made with the files' owners; the rest is done here.
#
#   ROOTFS  where iSH-AOK's archives are (default $OUT/rootfs): devuan-minirootfs-6.0-ARCH.tar.xz and
#           alpine-minirootfs-3.24.2-ARCH.tar.xz, ARCH being iSH-AOK's names (aarch64, x86_64, x86, riscv64):
#           the repository root has the two aarch64 ones, emkey1/ish-AOK-rootfs the rest
#   ISH     an iSH-AOK checkout, for opt/AOK/tools and tests/bench-utm/utm/vm-update.sh (default ~/git/ish-AOK)
#   OUT     where the machines go (default $W/images): OUT/machines/NAME.utm, and the zip AOK VM carries
#           or downloads in OUT/zips (alpine-3.24.2-ARCH.zip, devuan-6-ARCH.zip; index.py lists them)
set -e
here=$(cd "$(dirname "$0")" && pwd)
W=${W:-$HOME/aok-vm-bench}
OUT=${OUT:-$W/images}
ROOTFS=${ROOTFS:-$OUT/rootfs}
ISH=${ISH:-$HOME/git/ish-AOK}
export PATH=/opt/homebrew/bin:$PATH
all="alpine-aarch64 alpine-x86_64 alpine-i386 alpine-riscv64 devuan-aarch64 devuan-x86_64 devuan-i386 devuan-riscv64"
want=${*:-$all}
S=$OUT/stage; rm -rf "$S"; mkdir -p "$S/job/in" "$OUT/machines" "$OUT/zips"

ish_arch() { case $1 in i386) echo x86 ;; *) echo "$1" ;; esac; }
serial() { case $1 in aarch64) echo ttyAMA0 ;; *) echo ttyS0 ;; esac; }
kpkg() { case $1 in riscv64) echo "$W/dl-kernel/linux-lts-riscv64.apk" ;; *) echo "$W/dl-kernel/linux-virt-$(ish_arch "$1").apk" ;; esac; }
kimage() { case $1 in riscv64) echo "$W/kernel/Image-lts-riscv64" ;; *) echo "$W/kernel/vmlinuz-virt-$(ish_arch "$1")" ;; esac; }
archive() { case $1 in alpine) echo "alpine-minirootfs-3.24.2-$(ish_arch "$2").tar.xz" ;; devuan) echo "devuan-minirootfs-6.0-$(ish_arch "$2").tar.xz" ;; esac; }
zipname() { case $1 in alpine) echo "alpine-3.24.2-$(ish_arch "$2").zip" ;; devuan) echo "devuan-6-$(ish_arch "$2").zip" ;; esac; }
tools() { echo "start-wayland.sh setup-wayland.sh provision-ultimate-$1.sh setup-games.sh aok-sdl-game"; }

arches=; oses=
for m in $want; do
    os=${m%%-*}; arch=${m#*-}
    [ -f "$ROOTFS/$(archive "$os" "$arch")" ] || { echo "no $ROOTFS/$(archive "$os" "$arch")"; exit 1; }
    case " $arches " in *" $arch "*) ;; *) arches="$arches $arch" ;; esac
    case " $oses " in *" $os "*) ;; *) oses="$oses $os" ;; esac
done

# Per architecture: the kernel's modules (for the disk) and the initramfs.
for arch in $arches; do
    echo "== $arch: modules, initramfs"
    k=$S/k-$arch; rm -rf "$k"; mkdir -p "$k"
    bsdtar -xf "$(kpkg "$arch")" -C "$k" lib/modules
    bsdtar -cf "$S/job/in/modules-$arch.tar" --uid 0 --gid 0 -C "$k" lib
    ver=$(ls "$k/lib/modules")
    i=$S/i-$arch; rm -rf "$i"; mkdir -p "$i/bin" "$i/lib/modules/$ver/kernel"
    # busybox and the libc it links to, from the same architecture's Alpine root
    a=$(archive alpine "$arch")
    bsdtar -xf "$ROOTFS/$a" -C "$i" ./bin/busybox './lib/ld-musl-*'
    # the drivers between the kernel and the root: VirtIO, the disk, ext4 and what it needs
    m=$k/lib/modules/$ver
    (cd "$m" && cp modules.* "$i/lib/modules/$ver/" &&
        find kernel/drivers/virtio kernel/drivers/block/virtio_blk* kernel/fs/ext4 kernel/fs/jbd2 \
             kernel/fs/mbcache* kernel/crypto kernel/lib -name '*.ko*' 2> /dev/null |
        while read -r f; do mkdir -p "$i/lib/modules/$ver/$(dirname "$f")"; cp "$f" "$i/lib/modules/$ver/$f"; done)
    install -m 755 "$here/init" "$i/init"
    install -m 755 "$here/udhcpc.sh" "$i/udhcpc.sh"
    (cd "$i" && bsdtar -cf - --format=newc --uid 0 --gid 0 .) | gzip -9 > "$S/initramfs-$arch"
    cp "$(kimage "$arch")" "$S/vmlinuz-$arch"
done

# What every machine of a distribution gets on its disk.
for os in $oses; do
    o=$S/o-$os; rm -rf "$o"; mkdir -p "$o/AOK/tools" "$o/AOK/persist" "$o/usr/local/bin"
    for t in $(tools "$os"); do install -m 755 "$ISH/opt/AOK/tools/$t" "$o/AOK/tools/$t"; done
    install -m 755 "$ISH/tests/bench-utm/utm/vm-update.sh" "$o/usr/local/bin/aok-update"
    if [ "$os" = alpine ]; then
        mkdir -p "$o/etc/aok-vm"
        install -m 644 "$here/alpine/inittab" "$o/etc/inittab"
        for f in boot stop autologin; do install -m 755 "$here/alpine/$f" "$o/etc/aok-vm/$f"; done
    fi
    bsdtar -cf "$S/job/in/overlay-$os.tar" --uid 0 --gid 0 -C "$o" .
done

# The disks, in the build VM.
letters=(b c d e f g h i j k l m)
n=0; drives=
: > "$S/job/list"
for m in $want; do
    os=${m%%-*}; arch=${m#*-}
    a=$(archive "$os" "$arch")
    [ -f "$S/job/in/$a" ] || cp "$ROOTFS/$a" "$S/job/in/$a"
    echo "vd${letters[$n]} $os $arch $a $(serial "$arch")" >> "$S/job/list"
    rm -f "$S/$m.raw" && truncate -s 8G "$S/$m.raw"
    drives="$drives -drive file=$S/$m.raw,format=raw,if=none,id=d$n -device virtio-blk-pci,drive=d$n"
    n=$((n + 1))
done
cp "$here/job.sh" "$S/job/run.sh"
tar -cf "$S/job.tar" -C "$S/job" . && truncate -s "$(( ($(stat -f %z "$S/job.tar") / 1048576 + 1) * 1048576 ))" "$S/job.tar"
echo "== the disks ($n), in the build VM"
qemu-system-aarch64 -M virt -accel hvf -cpu host -smp 8 -m 4096 -display none -serial stdio -monitor none \
    -no-reboot -kernel "$W/kernel/vmlinuz-virt-aarch64" -initrd "$W/initramfs-aarch64-vm.cpio" \
    -append "console=ttyAMA0 rdinit=/init quiet bench=none script=vda" \
    -drive "file=$S/job.tar,format=raw,if=none,id=j,readonly=on" -device virtio-blk-pci,drive=j $drives \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 -device virtio-rng-pci < /dev/null > "$S/job.log" 2>&1
grep -q "JOB DONE" "$S/job.log" || { echo "the build VM failed: $S/job.log"; tail -20 "$S/job.log"; exit 1; }
grep -E '^== |/dev/vd' "$S/job.log" | tr -d '\r'

# The machines.
for m in $want; do
    os=${m%%-*}; arch=${m#*-}
    d=$S/$m; mkdir -p "$d"
    qemu-img convert -c -O qcow2 "$S/$m.raw" "$d/disk.qcow2" && rm -f "$S/$m.raw"
    cp "$S/vmlinuz-$arch" "$d/vmlinuz"; cp "$S/initramfs-$arch" "$d/initramfs"
    b=$(python3 "$here/machine.py" "$os" "$arch" "$d" "$OUT/machines")
    z=$OUT/zips/$(zipname "$os" "$arch")
    (cd "$OUT/machines" && rm -f "$z" && zip -qr -X "$z" "${b##*/}")
    echo "$(du -sh "$b" | cut -f1) $(du -h "$z" | cut -f1) zipped  ${b##*/}"
done
