#!/bin/bash
# build-qemu-utm.sh [ios-tci|ios_simulator-tci] [configure] -- cross-build the AOK-gadgets QEMU (src-aok,
# branch utm-se) as UTM SE's RISC-V, ARM64 and x86 engines, for devices (the default) or for the arm64 simulator.
#
# UTM's iOS-SE app loads one QEMU shared library per guest architecture from its sysroot's Frameworks. This
# builds ours for riscv64, aarch64 and x86_64 the way UTM's scripts/build_dependencies.sh builds QEMU for the "ios-tci" platform
# (same compiler setup, same configure flags, same deployment target) against UTM's prebuilt dependencies,
# plus --enable-aok-gadgets, and without OpenGL: UTM's GL display path is patches to its own QEMU fork that
# this tree does not carry. The result is installed under utm/qemu-out-PLATFORM; install-qemu-utm.sh puts it
# in the sysroot.
#
# Needs: utm/UTM (UTM's checkout) with sysroot-PLATFORM-arm64 unpacked in it (the Sysroot-PLATFORM-arm64
# artifact of UTM's Build workflow), Xcode, and Homebrew's meson ninja pkg-config.
set -e
W=${W:-$HOME/aok-vm-bench}
U=$W/utm
PLAT=ios-tci
case $1 in ios-tci|ios_simulator-tci) PLAT=$1; shift ;; esac
PREFIX=$U/UTM/sysroot-$PLAT-arm64
OUT=$U/qemu-out-$PLAT${AOK_GL:+-gl}
export PATH=/opt/homebrew/bin:$PATH

# The sysroot's .pc files name the CI machine's path. A corrected copy, so that the sysroot stays as shipped.
PC=$U/pc-$PLAT
mkdir -p "$PC"
for f in "$PREFIX"/lib/pkgconfig/*.pc "$PREFIX"/share/pkgconfig/*.pc; do
    sed -e "s|^prefix=.*|prefix=$PREFIX|" "$f" > "$PC/$(basename "$f")"
done
export PKG_CONFIG_LIBDIR=$PC
export PKG_CONFIG_PATH=

# As build_dependencies.sh sets them for the platform, arm64.
ARCH=arm64; SDKMINVER=15.0
case $PLAT in
    ios-tci)           SDK=iphoneos;        CFLAGS_TARGET="-target $ARCH-apple-ios$SDKMINVER" ;;
    ios_simulator-tci) SDK=iphonesimulator; CFLAGS_TARGET="-target $ARCH-apple-ios$SDKMINVER-simulator" ;;
esac
SDKROOT_IOS=$(xcrun --sdk $SDK --show-sdk-path)
export CC="$(xcrun --sdk $SDK --find gcc) $CFLAGS_TARGET"
export CPP="$(xcrun --sdk $SDK --find gcc) -E"
export CXX="$(xcrun --sdk $SDK --find g++)"
export OBJCC="$(xcrun --sdk $SDK --find clang)"
export LD="$(xcrun --sdk $SDK --find ld)" AR="$(xcrun --sdk $SDK --find ar)" NM="$(xcrun --sdk $SDK --find nm)"
export RANLIB="$(xcrun --sdk $SDK --find ranlib)" STRIP="$(xcrun --sdk $SDK --find strip)"
export CFLAGS="-arch $ARCH -isysroot $SDKROOT_IOS -I$PREFIX/include -F$PREFIX/Frameworks"
export CPPFLAGS="$CFLAGS $CFLAGS_TARGET" CXXFLAGS="$CFLAGS $CFLAGS_TARGET" OBJCFLAGS="$CFLAGS $CFLAGS_TARGET"
export LDFLAGS="-arch $ARCH -isysroot $SDKROOT_IOS -L$PREFIX/lib -F$PREFIX/Frameworks $CFLAGS_TARGET"
# Host tools meson builds must not get the iOS SDK.
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"

# GL=1: with OpenGL (UTM's ANGLE-backed epoxy) and virglrenderer, which needs the utm-gl branch.
GL="--disable-opengl --disable-virglrenderer"
[ -n "$AOK_GL" ] && GL="--enable-opengl --enable-virglrenderer --disable-dbus-display"
mkdir -p "$U/build-qemu-$PLAT${AOK_GL:+-gl}" && cd "$U/build-qemu-$PLAT${AOK_GL:+-gl}"
if [ ! -f build.ninja ] || [ "$1" = configure ]; then
    "$W/src-aok/configure" --prefix="$OUT" --host=aarch64-apple-darwin --cross-prefix="" --objcc="$OBJCC" \
        --enable-shared-lib --disable-cocoa --disable-sdl --disable-coreaudio --disable-slirp-smbd \
        --enable-ucontext --with-coroutine=libucontext \
        --enable-tcg-threaded-interpreter --target-list=riscv64-softmmu,aarch64-softmmu,x86_64-softmmu \
        --extra-cflags=-Wno-unused-command-line-argument --extra-ldflags=-Wl,-no_deduplicate \
        --extra-ldflags=-Wl,-random_uuid --extra-ldflags=-Wl,-no_compact_unwind \
        --enable-aok-gadgets --enable-spice --enable-spice-protocol --enable-slirp --enable-fdt=system \
        $GL --disable-tools --disable-guest-agent --disable-docs \
        --disable-hvf --disable-werror --disable-debug-info
fi
ninja
ninja install
ls -la "$OUT/lib/libqemu-riscv64-softmmu.dylib" "$OUT/lib/libqemu-aarch64-softmmu.dylib" \
    "$OUT/lib/libqemu-x86_64-softmmu.dylib"
