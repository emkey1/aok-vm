#!/bin/bash
# build.sh [ROS_DIR] -- ReactOS for AOK VM, from the release CD to ROS_DIR/reactos.qcow2, the disk that
# make-vm.py puts in "ReactOS.utm" (ARCH=i386 REACTOS_DISK=ROS_DIR/reactos.qcow2). On a Mac with Homebrew's
# QEMU (brew install qemu: qemu-system-i386 for its screen dump, qemu-img), in about twenty minutes, by
# itself. ROS_DIR defaults to ~/aok-vm-bench/reactos.
#
#  1. The release (SourceForge), checked against its SHA-256, and the CD image inside it.
#  2. The CD's files with two changes: freeldr.ini starts text-mode setup after a second (the release starts
#     the live system after three), and i386/unattend.inf is unattend.inf here, which is what text-mode
#     setup reads (reactos/unattend.inf is the live system's installer's, and stays as it is): the whole
#     first disk, one FAT partition, C:\ReactOS, US English, 1024x768 in 32 bits, and two registry
#     settings run at the first logon so that every later start logs in as Administrator by itself.
#  3. A CD of them: ISO 9660 and Joliet, booting the release's own isoboot.bin.
#  4. The install, on the machine AOK VM gives ReactOS (ros-run.sh): text-mode setup, a restart (the CD's
#     boot sector boots the disk when no key is pressed), the graphical stage, a restart, the first logon
#     (which runs unattend.inf's two registry settings), and off.
#  5. The questions setup leaves to a person: the machine has two devices ReactOS has no driver for, QEMU's
#     firmware configuration device (ACPI QEMU0002, "Other ACPI device") and the guest agent's
#     virtio-serial port, which UTM gives every x86 machine (PCI 1af4:1003, "Communication device"), and
#     the New Hardware Wizard asks about each. Answered as a person would, with keys through the monitor:
#     Next, "Do not show this dialog anymore", Finish. The wizard is found on the screen (screen.py). Not
#     at the first logon: there the wizard can come up behind the shell, and keys go to the shell; on the
#     next start it has the keyboard. (A device whose wizard was shown is not asked about again even
#     unanswered: the port's wizard is the first logon's, and the second start asks only about the other.)
#  6. The installed usbhub.sys, the USB hub driver, replaced by the CD's with one change (usbhub-wait/: it
#     waits for the root hub to be ready, at most the second it used to sleep at every start).
#  7. Start again, and check that the desktop comes, that no wizard does, on the screen or in the debug
#     output (neither device is tried), and that the USB tablet's driver loads.
#  8. The disk compressed.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
export ROS_DIR=${1:-${ROS_DIR:-$HOME/aok-vm-bench/reactos}}
W=$ROS_DIR
VER=0.4.16
ZIP=ReactOS-$VER-i386.zip
SHA256=e5851510cf5b79ef51a76b8155dd5ef7faca1155f44d0a1d41c35b77ece4ce2a
URL=https://sourceforge.net/projects/reactos/files/ReactOS/$VER/$ZIP/download
QIMG=/opt/homebrew/bin/qemu-img
mkdir -p "$W/dl"
cd "$W"
say() { echo "[$(date +%H:%M:%S)] $*"; }
mon() { echo "$1" | nc -U -w 1 "$W/mon.sock" > /dev/null; }
# down TIMEOUT: wait for QEMU to exit (the guest powered off)
down() { local n=0; while kill -0 "$qpid" 2> /dev/null; do sleep 1; n=$((n + 1)); [ $n -lt "$1" ] || return 1; done; }
# until_log PATTERN TIMEOUT: wait for the guest's debug output to say PATTERN
until_log() {
    local n=0
    until grep -qF "$1" serial.log 2> /dev/null; do
        sleep 5; n=$((n + 5))
        kill -0 "$qpid" 2> /dev/null || { say "QEMU exited"; return 1; }
        [ $n -lt "$2" ] || { say "timed out waiting for: $1"; return 1; }
    done
}
# tried DEVICE: has the guest tried to install DEVICE (a part of its instance path) since it started?
tried() { grep -F "Installing:" serial.log | grep -qF "$1"; }
# wizard_shown TIMEOUT [active]: wait for the wizard to be on the screen (and to have the keyboard)
wizard_shown() {
    local n=0
    until "$here/shot.sh" w ppm && python3 -I "$here/screen.py" w.ppm ${2:-}; do
        sleep 5; n=$((n + 5)); [ $n -lt "$1" ] || return 1
    done
}
start() {
    rm -f mon.sock serial.log
    "$here/ros-run.sh" > qemu.out 2>&1 &
    qpid=$!
    local n=0; until [ -S mon.sock ]; do sleep 0.5; n=$((n + 1)); [ $n -lt 20 ] || { cat qemu.out; exit 1; }; done
}
trap '[ -n "${qpid:-}" ] && kill "$qpid" 2> /dev/null; true' EXIT

# 1
if ! echo "$SHA256  dl/$ZIP" | shasum -a 256 -c --status 2> /dev/null; then
    say "downloading $ZIP"
    curl -fL --retry 3 -o "dl/$ZIP" "$URL"
    echo "$SHA256  dl/$ZIP" | shasum -a 256 -c
fi
rm -f dl/*.iso && unzip -q -o "dl/$ZIP" '*.iso' -d dl
ISO=$(ls dl/*.iso)

# 2
say "the CD's files"
rm -rf tree && mkdir mnt.$$ && hdiutil attach -readonly -nobrowse -mountpoint "$W/mnt.$$" "$ISO" > /dev/null
cp -R "mnt.$$/" tree; hdiutil detach "$W/mnt.$$" > /dev/null; rmdir "mnt.$$"
chmod -R u+w tree
sed -i '' -e 's/^DefaultOS=LiveImg/DefaultOS=Setup/' -e 's/^TimeOut=3/TimeOut=1/' tree/freeldr.ini
grep -q '^DefaultOS=Setup' tree/freeldr.ini
sed 's/$/\r/' "$here/unattend.inf" > tree/i386/unattend.inf

# 3
say "the CD"
rm -f ros-unattend.iso
hdiutil makehybrid -quiet -o ros-unattend.iso tree -iso -joliet -default-volume-name REACTOS \
    -eltorito-boot tree/loader/isoboot.bin -no-emul-boot -hide-iso boot.catalog -hide-joliet boot.catalog

# 4
say "installing (text mode, then graphical; about a quarter of an hour)"
rm -f ros.qcow2 && "$QIMG" create -q -f qcow2 ros.qcow2 10G
export ROS_CD=$W/ros-unattend.iso
start
until_log "rshell.dll" 3600            # explorer
wizard_shown 300 || { say "no wizard at the first logon (w.png)"; exit 1; }
say "first logon"
sleep 30
mon system_powerdown
down 120 || { say "did not power off"; exit 1; }

# 5
say "starting again, without the CD"
unset ROS_CD
start
DEVICES=('ACPI\QEMU0002' 'VEN_1AF4&DEV_1003')
answered=0
while wizard_shown 90; do
    if ! python3 -I "$here/screen.py" w.ppm active; then
        mon "sendkey alt-tab"; sleep 3
        wizard_shown 10 active || { say "no wizard with the keyboard (w.png)"; exit 1; }
    fi
    [ $answered -lt ${#DEVICES[@]} ] || { say "more wizards than devices without a driver (w.png)"; exit 1; }
    say "a wizard: Next"
    mon "sendkey alt-n"; sleep 8
    "$here/shot.sh" w2 ppm
    python3 -I "$here/screen.py" w2.ppm active || { say "not the wizard's last page (w2.png)"; exit 1; }
    say "Do not show this dialog anymore; Finish"
    mon "sendkey spc"; sleep 2; mon "sendkey ret"; sleep 8
    answered=$((answered + 1))
done
say "answered $answered"
mon system_powerdown
down 120 || { say "did not power off"; exit 1; }

# 6
say "the USB hub driver's change"
rm -f usb.qcow2
USBHUB_SYS=$W/tree/reactos/system32/drivers/usbhub.sys bash "$here/usbhub-wait/patch-disk.sh" ros.qcow2 usb.qcow2
"$QIMG" commit -q usb.qcow2 && rm -f usb.qcow2

# 7
say "starting again"
start
until_log "rshell.dll" 600
sleep 60
"$here/shot.sh" desktop ppm
python3 -I "$here/screen.py" desktop.ppm && { say "a wizard came back (desktop.png)"; exit 1; }
for d in "${DEVICES[@]}"; do
    ! tried "$d" || { say "$d was tried again"; exit 1; }
done
grep -qF 'drivers\mouhid.sys' serial.log || { say "the tablet's driver did not load"; exit 1; }
mon system_powerdown
down 120 || { say "did not power off"; exit 1; }
qpid=

# 8
say "compressing"
rm -f reactos.qcow2 && "$QIMG" convert -c -O qcow2 ros.qcow2 reactos.qcow2
rm -f ./*.ppm
say "done: $W/reactos.qcow2 ($(du -h reactos.qcow2 | cut -f1)), its desktop in $W/desktop.png"
