#!/bin/sh
# job.sh -- run.sh in the build VM (build.sh), as root: makes each base machine's root disk. The list beside
# it has a line a machine: its disk (vdb, vdc, ...), its distribution and architecture, iSH-AOK's archive
# of its root file system and its serial port. Each disk gets an ext4 file system with, in this order: the
# archive as iSH-AOK ships it, the Alpine kernel's modules, the files of overlay-OS.tar (/AOK/tools,
# aok-update, /AOK/persist; Alpine's init files), and then what depends on the machine.
set -e
J=$(cd "$(dirname "$0")" && pwd)
apk add --no-cache e2fsprogs xz tar > /dev/null
modprobe ext4
mkdir -p /mnt
while read -r dev os arch archive ser; do
    echo "== $dev: $os $arch ($archive)"
    mkfs.ext4 -q -F -L root "/dev/$dev"
    mount "/dev/$dev" /mnt
    xz -dc "$J/in/$archive" | tar -xpf - -C /mnt --numeric-owner
    # (over Devuan's /lib -> usr/lib and the like: without --keep-directory-symlink GNU tar replaces the
    # link with a directory, and the root's programs lose their dynamic loader)
    tar -xpf "$J/in/modules-$arch.tar" -C /mnt --numeric-owner --keep-directory-symlink
    tar -xpf "$J/in/overlay-$os.tar" -C /mnt --numeric-owner --keep-directory-symlink
    printf '/dev/vda / ext4 rw,relatime 0 0\naokpersist /AOK/persist 9p trans=virtio,version=9p2000.L,nofail 0 0\n' \
        > /mnt/etc/fstab
    echo "$os" > /mnt/etc/hostname
    printf '127.0.0.1 localhost\n127.0.1.1 %s\n::1 localhost ip6-localhost ip6-loopback\n' "$os" > /mnt/etc/hosts
    case $os in
    alpine)
        sed -i "s/SERIAL/$ser/g" /mnt/etc/inittab
        desktop=provision-ultimate-alpine.sh ;;
    devuan)
        # Its own inittab already logs root in on tty1; the serial terminal too.
        grep -q '^T0:' /mnt/etc/inittab ||
            echo "T0:2345:respawn:/sbin/getty --autologin root -L 115200 $ser vt100" >> /mnt/etc/inittab
        desktop=provision-ultimate-devuan.sh ;;
    esac
    cat > /mnt/etc/motd <<EOF

  iSH-AOK's $os root file system, as a machine of its own on AOK VM.

    aok-update
        iSH-AOK's /AOK/tools scripts, brought up to date
    sh /AOK/tools/$desktop
        a desktop and the "ultimate" tool set: what you want, downloaded
    /AOK/persist
        iSH-AOK's shared directory, when the machine's Sharing setting gives it

EOF
    df -h /mnt | tail -1
    umount /mnt
done < "$J/list"
echo "JOB DONE"
