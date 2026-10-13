#!/bin/sh
# devuan-provision.sh -- runs as run.sh inside the Alpine RISC-V build VM (build-devuan-disk.sh), as root:
# makes Devuan 6 "Excalibur" on /dev/vda with debootstrap, natively, and hands its kernel and initrd out as
# a tar on /dev/vdc. The result is a machine for a VM front end: Devuan's own kernel, sysvinit, a network
# that comes up by DHCP, Mesa, and root logged in on the console and the serial port (no password is set:
# it is a local test machine).
#
# Two passes, because the mirrors can be slow per connection and the kernel alone is 112 MB. With the file
# "mode" (beside this script) saying "list", it installs the base system and writes the list of packages
# still to fetch to /dev/vdc; the host fetches them in parallel and serves them at 10.0.2.2:8642. With
# "install" it takes them from there and finishes. Either pass can be repeated: what is done is kept.
# A third mode, "tools", only brings an existing disk's /AOK/tools and boot-time hooks up to date.
set -ex
MODE=$(cat "$(dirname "$0")/mode")
MIRROR=http://pkgmaster.devuan.org/merged
# The build VM's architecture is the machine's: Debian's name for it, and its serial console.
case $(uname -m) in
aarch64) DEB=arm64; SER=ttyAMA0 ;;
*) DEB=riscv64; SER=ttyS0 ;;
esac
PKGS="sysvinit-core eudev kmod ifupdown isc-dhcp-client iproute2 iputils-ping netbase procps less nano
    curl wget pciutils e2fsprogs linux-image-$DEB initramfs-tools
    libgl1-mesa-dri libegl1 libgles2 libgbm1 kmscube mesa-utils"
apk add --no-cache debootstrap e2fsprogs > /dev/null
modprobe ext4
mkdir -p /mnt
if ! mount /dev/vda /mnt 2>/dev/null || [ ! -f /mnt/etc/devuan_version ]; then
    umount /mnt 2>/dev/null || true
    mkfs.ext4 -q -F -L devuan /dev/vda
    mount /dev/vda /mnt
    # Alpine's debootstrap does not know Devuan's suite names: Debian's script for sid is the one they use.
    # The archive key comes in with devuan-keyring, so apt checks signatures from then on.
    debootstrap --arch=$DEB --variant=minbase --no-check-gpg \
        --include=devuan-keyring,ca-certificates excalibur /mnt $MIRROR /usr/share/debootstrap/scripts/sid
fi
mount -t proc proc /mnt/proc; mount -t sysfs sys /mnt/sys; mount -o bind /dev /mnt/dev
cp /etc/resolv.conf /mnt/etc/resolv.conf
echo "deb $MIRROR excalibur main" > /mnt/etc/apt/sources.list
printf 'Acquire::http::Timeout "30";\nAcquire::Retries "5";\n' > /mnt/etc/apt/apt.conf.d/80aok-build
# (On a fast machine apt's helpers can still be leaving the chroot when the script gets here: the arm64
# build, on the Mac's own CPU, found /mnt busy.)
finish() {
    umount /mnt/dev /mnt/sys /mnt/proc
    sync
    umount /mnt || { sleep 3; umount /mnt || umount -l /mnt; }
    sync
}

# What the machine carries of iSH-AOK's tools (the job brings them in tools/): the provisioning and
# Wayland scripts that the same distribution uses under the app, which know a machine of its own when they
# are on one. And rc.local's two hooks, read from the kernel command line:
#   gltest=FRAMES  run gltest once the machine is up, on the console
#   aokjob=DEV     DEV holds a tar with run.sh: run it as root on the console, then power off. This is how
#                  build-devuan-disk.sh runs those scripts in the machine itself, as its owner would.
install_tools() {
    here=$(dirname "$0")
    if [ -d "$here/tools" ]; then
        mkdir -p /mnt/AOK/tools
        cp -r "$here"/tools/* /mnt/AOK/tools/
        chmod -R u+rwX,go+rX /mnt/AOK/tools
        # `desktop`: the Wayland desktop on this machine's display, once setup-wayland.sh has run.
        # `desktop soft`: composited without the GPU, for a display whose GL path does not show.
        cat > /mnt/usr/local/bin/desktop <<'D'
#!/bin/sh
[ "$1" = soft ] && { shift; export WLR_RENDERER=pixman; }
exec sh /AOK/tools/start-wayland.sh "$@"
D
        chmod 755 /mnt/usr/local/bin/desktop
        # `sudo aok-update`: these scripts again from the repository, for a machine whose disk is by then
        # its user's (vm-update.sh).
        [ -f "$here/vm-update.sh" ] && install -m 755 "$here/vm-update.sh" /mnt/usr/local/bin/aok-update
    fi
    # `aok-engine`, and a line at login: which engine runs this machine (the AOK gadget engine says so).
    cat > /mnt/usr/local/bin/aok-engine <<'E'
#!/bin/sh
# aok-engine -- which engine runs this machine's CPU. The AOK gadget engine says so itself: in the device
# tree (/chosen, "aok,engine") where the machine has one, and in a fw_cfg file that rc.local copies to
# /run/aok-engine at boot. Neither is there under QEMU's own engine.
if [ -d /proc/ish ]; then echo "iSH-AOK"; exit 0; fi
e=$(tr -d '\000' < /proc/device-tree/chosen/aok,engine 2> /dev/null)
[ -n "$e" ] || e=$(cat /run/aok-engine 2> /dev/null)
echo "${e:-QEMU, without the AOK gadgets}"
E
    chmod 755 /mnt/usr/local/bin/aok-engine
    cat > /mnt/etc/profile.d/aok-engine.sh <<'E'
# (aok-engine) one line at login: which engine this machine runs on
case $- in *i*) command -v aok-engine > /dev/null 2>&1 && printf '  engine: \033[1m%s\033[0m\n' "$(aok-engine)" ;; esac
E
    cat > /mnt/etc/rc.local <<'R'
#!/bin/sh
# (aok-engine) the engine's fw_cfg file, for machines with no device tree
modprobe -q qemu_fw_cfg 2> /dev/null
cat /sys/firmware/qemu_fw_cfg/by_name/opt/aok/engine/raw > /run/aok-engine 2> /dev/null || rm -f /run/aok-engine
for x in $(cat /proc/cmdline); do
    case $x in
    gltest=*) (sleep 4; /usr/local/bin/gltest "${x#gltest=}" > /dev/console 2>&1) & ;;
    aokjob=*) (mkdir -p /run/aokjob && tar -xf "/dev/${x#aokjob=}" -C /run/aokjob &&
               sh /run/aokjob/run.sh > /dev/console 2>&1; echo "AOKJOB-DONE rc=$?" > /dev/console
               sync; poweroff) & ;;
    esac
done
exit 0
R
    chmod +x /mnt/etc/rc.local
}

if [ "$MODE" = tools ]; then
    install_tools
    ls -la /mnt/AOK/tools
    finish
    echo DEVUAN-TOOLS-OK
    exit 0
fi

if [ "$MODE" = list ]; then
    chroot /mnt /bin/sh -ex -c "export LC_ALL=C; apt-get -q update;
        apt-get -q -y --no-install-recommends install --print-uris $(echo $PKGS) > /tmp/uris.txt"
    grep "^'" /mnt/tmp/uris.txt > /tmp/uris.txt
    wc -l < /tmp/uris.txt
    (cd /tmp && tar -cf /dev/vdc uris.txt)
    finish
    echo DEVUAN-LIST-OK
    exit 0
fi

# What the host fetched, into apt's cache: apt checks each against the archive's hashes before using it.
while read -r url name rest; do
    # a name can hold an escaped epoch (%3a), which has to reach the server as it is
    [ -s "/mnt/var/cache/apt/archives/$name" ] ||
        wget -q -O "/mnt/var/cache/apt/archives/$name" "http://10.0.2.2:8642/$(echo "$name" | sed 's/%/%25/g')" ||
        rm -f "/mnt/var/cache/apt/archives/$name"
done < "$(dirname "$0")/uris.txt"
ls /mnt/var/cache/apt/archives/*.deb | wc -l
echo devuan > /mnt/etc/hostname
printf '127.0.0.1 localhost\n127.0.1.1 devuan\n' > /mnt/etc/hosts
printf '/dev/vda / ext4 errors=remount-ro 0 1\n' > /mnt/etc/fstab
cat > /mnt/usr/sbin/policy-rc.d <<'P'
#!/bin/sh
exit 101
P
chmod +x /mnt/usr/sbin/policy-rc.d
chroot /mnt /bin/sh -ex -c "export DEBIAN_FRONTEND=noninteractive LC_ALL=C;
    apt-get -q -y --no-install-recommends install $(echo $PKGS); apt-get clean"
rm /mnt/usr/sbin/policy-rc.d /mnt/etc/apt/apt.conf.d/80aok-build
echo "deb http://deb.devuan.org/merged excalibur main" > /mnt/etc/apt/sources.list
# eth0 whatever the bus calls it (the machine is started with net.ifnames=0), by DHCP.
printf 'auto lo\niface lo inet loopback\n\nauto eth0\niface eth0 inet dhcp\n' > /mnt/etc/network/interfaces
# root on the display's console and on the serial port, without asking.
sed -i -e 's|^1:2345:respawn:.*|1:2345:respawn:/sbin/agetty --autologin root --noclear tty1 linux|' \
       -e "s|^#T0:23:respawn:.*|T0:23:respawn:/sbin/agetty --autologin root -L $SER 115200 vt100|" /mnt/etc/inittab
grep -q '^T0:' /mnt/etc/inittab ||
    echo "T0:23:respawn:/sbin/agetty --autologin root -L $SER 115200 vt100" >> /mnt/etc/inittab
# gltest: which renderer a GL program gets -- "virgl (...)" is the host's GPU, "llvmpipe" the guest's CPU.
cat > /mnt/usr/local/bin/gltest <<'G'
#!/bin/sh
dmesg | grep -iE "\[drm\].*(features|cap sets)" | sed 's/^\[[^]]*\] */GLTEST kernel: /'
EGL_LOG_LEVEL=debug LIBGL_DEBUG=verbose kmscube -c "${1:-300}" > /tmp/gltest.log 2>&1
grep -iE "virgl|virtio|fail|fallback|cannot|unable|driver missing" /tmp/gltest.log | head -6 | cut -c1-110 | sed 's/^ */GLTEST mesa: /'
grep -iE "renderer|vendor|version" /tmp/gltest.log | grep -viE "extensions|shading" | sed 's/^ */GLTEST /'
grep "Rendered" /tmp/gltest.log | tail -1 | sed 's/^/GLTEST /'
G
chmod +x /mnt/usr/local/bin/gltest
install_tools
echo "Devuan 6 (Excalibur) $DEB, built for the AOK QEMU. gltest: is the display accelerated?" > /mnt/etc/motd
ls -la /mnt/boot
(cd /mnt/boot && tar -cf /dev/vdc vmlinu* initrd.img* config-*)
chroot /mnt dpkg-query -W -f '${Package} ${Version}\n' linux-image-$DEB libgl1-mesa-dri kmscube
ls /mnt/usr/lib/$(uname -m)-linux-gnu/dri 2>/dev/null | tr '\n' ' '
df -h /mnt | tail -1
finish
echo DEVUAN-PROVISION-OK
