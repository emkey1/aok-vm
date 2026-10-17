#!/bin/bash
# build-utm.sh [device|sim] -- build AOK VM (this repository's iOS-SE target, through the scheme "AOK VM")
# around the sysroot that install-qemu-utm.sh prepared, on the Mac that signs. The product is a signed
# "UTM SE.app" under $DD/Build/Products/Release-iphoneos (or -iphonesimulator); DD is ~/aok-utm/dd unless set.
#
# What has to be in the checkout first:
#   sysroot  UTM's prebuilt dependencies for the platform, unpacked at the repository's root as
#            sysroot-ios-tci-arm64 (sysroot-ios_simulator-tci-arm64 for the simulator): the
#            Sysroot-ios-tci-arm64 artifact of UTM's own Build workflow for the commit this fork is based
#            on (7eadb056, 5.0.6: run 36090554968 on github.com/utmapp/UTM, which GitHub keeps for 90 days),
#            or what UTM's scripts/build_dependencies.sh builds from source
#   engines  aok/utm/build-qemu-utm.sh, then install-qemu-utm.sh: the AOK-gadgets QEMU (emkey1/qemu,
#            branch aok-vm) as the sysroot's riscv64, aarch64, x86_64 (it runs the 32-bit PCs too), ppc, ppc64
#            and m68k QEMU
#
# From Xcode, with no script: with those two in place and CodeSigning.xcconfig written (below), open
# UTM.xcodeproj, choose the scheme "AOK VM" and a device, and press Run. What Xcode does not build is
# the engines.
#
# UTM at that commit needs the released Xcode 27: Xcode 26 lacks iOS 27 APIs it uses, and Xcode 27 beta 3
# cannot compile the SwiftTerm it depends on. CodeSigning.xcconfig (written here if absent) gives the app a
# bundle id of our own, so that it installs beside a UTM SE from the App Store, and UTM's paid-account
# entitlements (Platform/iOS/iOS.entitlements): the App Group group.<prefix>.UTM, the increased memory limit
# and extended virtual addressing. Automatic signing registers them on the team at the first build. The
# App Group is not optional for Vulkan: on a device a sandboxed app may shm_open() only names inside a
# group it is entitled to, UTM's virglrenderer makes the shared memory of a venus context that way
# (APP_SANDBOX_GROUP_ID, which the front end sets from Info.plist whether or not the app is entitled), and
# built without the group every guest's vkCreateInstance failed with "proxy: failed to pre-initialize
# context" in the VM's log -- on an iPad only: the simulator does not enforce it.
#
# What this fork changes in UTM's front end is in its commits (git log 7eadb056..), each with its reason.
set -e
R=$(cd "$(dirname "$0")/../.." && pwd)
DD=${DD:-$HOME/aok-utm/dd}
cd "$R"
[ -f CodeSigning.xcconfig ] || cat > CodeSigning.xcconfig <<'XC'
DEVELOPMENT_TEAM = UYU5FM4LQ4
PRODUCT_BUNDLE_PREFIX = app.ish.aok
DEVELOPER_ACCOUNT_PAID = YES
DEVELOPER_ACCOUNT_VM_ACCESS = NO
CODE_SIGN_IDENTITY_IOS = Apple Development
CODE_SIGN_STYLE_IOS = Automatic
XC
case ${1:-device} in sim) sys=sysroot-ios_simulator-tci-arm64 ;; *) sys=sysroot-ios-tci-arm64 ;; esac
[ -d "$sys/Frameworks/qemu-x86_64-softmmu.framework" ] || { echo "no $sys with the engines in it: see the head of $0" >&2; exit 1; }
mkdir -p "$DD"
case ${1:-device} in
    device) dest='generic/platform=iOS'; extra=-allowProvisioningUpdates; products=Release-iphoneos ;;
    sim)    dest='generic/platform=iOS Simulator'; extra=ONLY_ACTIVE_ARCH=NO; products=Release-iphonesimulator ;;
esac
xcodebuild -scheme "AOK VM" -destination "$dest" -configuration Release ARCHS=arm64 -derivedDataPath "$DD" \
    -skipPackagePluginValidation -skipMacroValidation $extra build > "$DD/build-${1:-device}.log" 2>&1 ||
    { grep "error:" "$DD/build-${1:-device}.log" | sort -u | head -20; exit 1; }
if plutil -p "$DD/Build/Products/$products/UTM SE.app/Settings.bundle/Root.plist" | grep -q 'ExcludeTargets\|"Platform"'; then
    echo "the settings page was not patched for this target (Patch Settings bundle did not run)"; exit 1
fi
ls -d "$DD/Build/Products/$products/UTM SE.app"
