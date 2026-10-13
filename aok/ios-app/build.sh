#!/bin/bash
# build.sh -- build and sign the app for a device, on the Mac that holds the signing identity.
# The product is build/Build/Products/Release-iphoneos/AOKQemuBench.app.
set -e
cd "$(dirname "$0")"
xcodebuild -project AOKQemuBench.xcodeproj -scheme AOKQemuBench -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates "$@" build
