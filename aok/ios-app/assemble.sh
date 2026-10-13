#!/bin/bash
# assemble.sh -- stage what the app bundles and generate its Xcode project. Run on the Mac that has the iOS
# build of QEMU (build-ios.sh), in a copy of this directory:
#   Frameworks/  QEMU and the libraries it loads, as build_ios_aok.sh left them in the sysroot
#   Resources/   the guest: kernel, initramfs (the one the Mac race boots) and OpenSBI
# The directory can then be copied to whichever Mac signs and installs, and built there with build.sh.
set -e
W=${W:-$HOME/aok-vm-bench}
cd "$(dirname "$0")"
mkdir -p Frameworks Resources
rsync -a --delete "$W/ios/sysroot-iOS-arm64/Frameworks/" Frameworks/
cp "$W/kernel/Image-lts-riscv64" "$W/initramfs-riscv64.cpio" \
   "$W/src-aok/pc-bios/opensbi-riscv64-generic-fw_dynamic.bin" Resources/
# The arm64 guest, when this QEMU was built with its target (labels that begin "aarch64").
if [ -d Frameworks/qemu-aarch64-softmmu.framework ]; then
    cp "$W/kernel/vmlinuz-virt-aarch64" "$W/initramfs-aarch64.cpio" Resources/
fi
# The two PC guests (labels "x86_64" and "i386"), and the firmware a PC starts with.
if [ -d Frameworks/qemu-x86_64-softmmu.framework ]; then
    cp "$W/kernel/vmlinuz-virt-x86_64" "$W/initramfs-x86_64.cpio" "$W/kernel/vmlinuz-virt-x86" "$W/initramfs-x86.cpio" Resources/
    for f in bios-256k.bin linuxboot_dma.bin kvmvapic.bin vgabios-stdvga.bin; do cp "$W/src-aok/pc-bios/$f" Resources/; done
fi

# Every framework is embedded and signed; none is linked, since the app dlopen()s QEMU and QEMU finds the
# rest through the app's rpath.
deps=""
for f in Frameworks/*.framework; do
    deps="$deps
      - framework: $f
        embed: true
        link: false"
done
python3 - "$deps" <<'PY'
import sys
s = open("project.yml.in").read().replace("@FRAMEWORKS@", sys.argv[1])
open("project.yml", "w").write(s)
PY
xcodegen generate --quiet
ls -d Frameworks/*.framework | wc -l | xargs echo frameworks:
du -sh Frameworks Resources
