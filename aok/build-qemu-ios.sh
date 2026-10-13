#!/bin/bash
# build-qemu-ios.sh [qemu-only] -- cross-build the AOK-gadgets QEMU (src-aok) and what it links for iOS.
#
# The recipe is tctiSH's: its app's build_dependencies.sh builds pkg-config for the host, then libffi,
# libiconv, gettext-runtime, glib and pixman for the device, then QEMU as a shared library, and wraps every
# dylib as a framework in ios/sysroot-iOS-arm64/Frameworks. ios-app/build_dependencies.patch is what this
# build changes in that script: the riscv64, aarch64 and x86_64 targets (riscv64 with its device tree), TCTI plus --enable-aok-gadgets
# instead of the hybrid backend, a deployment target of iOS 17 so that the A10X can run it, no offline
# Python (Homebrew's has no setuptools), no bison check, and a way to rebuild QEMU alone.
#
# Needs Xcode with an iOS SDK, and from Homebrew: meson ninja pkg-config gettext. About ten minutes from
# nothing on an M5 Max, two for "qemu-only" after a change to QEMU. Then: ios-app/assemble.sh.
set -e
W=${W:-$HOME/aok-vm-bench}
here=$(cd "$(dirname "$0")" && pwd)
export PATH=/opt/homebrew/bin:/opt/homebrew/opt/gettext/bin:$PATH
if [ ! -d "$W/tctish-app" ]; then
    git clone https://github.com/tctiSH/tctiSH "$W/tctish-app"
    git -C "$W/tctish-app" checkout fc318a1
fi
cd "$W/tctish-app"
# The script builds whatever third-party/qemu is: ours.
[ -L third-party/qemu ] || { rmdir third-party/qemu 2>/dev/null || true; ln -s ../../src-aok third-party/qemu; }
if [ ! -f build_ios_aok.sh ]; then
    cp build_dependencies.sh build_ios_aok.sh
    patch -p0 build_ios_aok.sh < "$here/ios-app/build_dependencies.patch"
fi
mkdir -p "$W/ios" && cd "$W/ios"
[ "$1" = qemu-only ] && export QEMU_ONLY=1
"$W/tctish-app/build_ios_aok.sh" > build-ios.log 2>&1 || { tail -20 build-ios.log; exit 1; }
ls sysroot-iOS-arm64/Frameworks
