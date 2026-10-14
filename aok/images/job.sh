#!/bin/sh
# job.sh -- run.sh in the build VM (build.sh), as root: makes each base machine's root disk. The list beside
# it has a line a machine: its disk (vdb, vdc, ...), its distribution and architecture, iSH-AOK's archive
# of its root file system and its serial port. Each disk gets an ext4 file system with, in this order: the
# archive as iSH-AOK ships it, the Alpine kernel's modules, the files of overlay-OS.tar (/AOK/tools,
# aok-update, /AOK/persist; Alpine's init files), and then what depends on the machine.
set -e
J=$(cd "$(dirname "$0")" && pwd)
apk add --no-cache e2fsprogs xz tar kmod > /dev/null
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
    # Uncompressed, with their indexes made again: Devuan's kmod cannot load Alpine's gzipped modules
    # ("could not insert ...: Function not implemented"), which left a Devuan machine unable to load any
    # driver after its boot (udev's for the USB keyboard among them). The disk is compressed anyway.
    find /mnt/lib/modules -name '*.ko.gz' -exec gunzip {} +
    for v in /mnt/lib/modules/*; do depmod -b /mnt "${v##*/}"; done
    tar -xpf "$J/in/overlay-$os.tar" -C /mnt --numeric-owner --keep-directory-symlink
    printf '/dev/vda / ext4 rw,relatime 0 0\naokpersist /AOK/persist 9p trans=virtio,version=9p2000.L,nofail 0 0\n' \
        > /mnt/etc/fstab
    echo "$os" > /mnt/etc/hostname
    printf '127.0.0.1 localhost\n127.0.1.1 %s\n::1 localhost ip6-localhost ip6-loopback\n' "$os" > /mnt/etc/hosts
    case $os in
    alpine)
        # OpenRC, as an Alpine machine is expected to have it (rc-service, rc-update, services at boot):
        # iSH-AOK's root has none, iSH-AOK starting no services. Added for the machine's architecture
        # without its install scripts (they are the machine's programs, not this VM's), with the runlevels
        # a booted Alpine has, less the hardware ones; networking takes eth0 by DHCP as the initramfs did.
        apkarch=$(cat /mnt/etc/apk/arch)
        apk --root /mnt --arch "$apkarch" --no-cache --no-scripts add openrc > /dev/null
        rl() {  # rl LEVEL SERVICE...: those of the services this OpenRC has, in that runlevel
            lvl=$1; shift; mkdir -p "/mnt/etc/runlevels/$lvl"
            for s; do
                [ -e "/mnt/etc/init.d/$s" ] && ln -sf "/etc/init.d/$s" "/mnt/etc/runlevels/$lvl/$s"
            done
            return 0
        }
        rl sysinit sysfs devfs dmesg      # (sysfs: /sys, which OpenRC mounts only through this service)
        rl boot hostname bootmisc sysctl seedrng networking localmount
        rl default local
        rl shutdown killprocs mount-ro savecache
        mkdir -p /mnt/etc/network
        printf 'auto lo\niface lo inet loopback\n\nauto eth0\niface eth0 inet dhcp\n' > /mnt/etc/network/interfaces
        # Alpine's own inittab (OpenRC), with root logged in on the display and on the serial terminal
        sed -i 's|^tty1::respawn:/sbin/getty 38400 tty1$|tty1::respawn:/sbin/getty -n -l /etc/aok-vm/autologin 38400 tty1|' /mnt/etc/inittab
        grep -q "^$ser::" /mnt/etc/inittab ||
            echo "$ser::respawn:/sbin/getty -n -l /etc/aok-vm/autologin -L 115200 $ser vt100" >> /mnt/etc/inittab
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
        the /AOK/tools scripts, brought up to date
    sh /AOK/tools/$desktop
        a desktop and the "ultimate" tool set: what you want, downloaded
    /AOK/persist
        iSH-AOK's shared directory, when the machine's Sharing setting gives it

EOF
    df -h /mnt | tail -1
    umount /mnt
done < "$J/list"
echo "JOB DONE"
