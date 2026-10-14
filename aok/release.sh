#!/bin/bash
# release.sh [publish] -- an AOK VM release from this checkout, on the Mac that signs: one archive, signed by the
# team, and from it the App Store IPA (for TestFlight: upload it with Apple's Transporter, since Xcode's own upload
# fails for this account) and the sideloaders' IPA (utm/sideload-ipa.sh). "publish" then makes the GitHub release
# vVERSION-BUILD of emkey1/aok-vm, with the sideloaders' IPA, at the commit both were built from.
#
# The version and build are Build.xcconfig's MARKETING_VERSION and CURRENT_PROJECT_VERSION. App Store Connect takes
# a build number once, so raise CURRENT_PROJECT_VERSION, commit and push before a new one. Run it once without
# "publish", try the build (TestFlight's internal testing), then again with "publish": an archive of the same
# commit is used again, not rebuilt. Needs what utm/build-utm.sh needs (the sysroot with the engines in it,
# CodeSigning.xcconfig), the three machines in images/bundled (images/README.md), and gh signed in for "publish".
# Out: $OUT (~/aok-utm/archives): AOKVM-VERSION-BUILD.xcarchive, appstore-BUILD/, AOK-VM-VERSION-BUILD.ipa.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$HOME/aok-utm/archives}
DD=${DD:-$HOME/aok-utm/dd-repo}
REPO=emkey1/aok-vm
TESTFLIGHT=https://testflight.apple.com/join/wzDUq3rP
cd "$R"
V=$(sed -n 's/^MARKETING_VERSION = //p' Build.xcconfig)
B=$(sed -n 's/^CURRENT_PROJECT_VERSION = //p' Build.xcconfig)
TEAM=$(sed -n 's/^DEVELOPMENT_TEAM = //p' CodeSigning.xcconfig)
TAG=v$V-$B
ARCHIVE=$OUT/AOKVM-$V-$B.xcarchive
IPA=$OUT/AOK-VM-$V-$B.ipa
HEAD=$(git rev-parse HEAD)
mkdir -p "$OUT"

# A release names a commit anyone can fetch, and what was built from it alone.
if ! git diff --quiet HEAD; then
    [ "$1" = publish ] && { echo "uncommitted changes: commit and push them first" >&2; exit 1; }
    echo "note: uncommitted changes; this build cannot be published" >&2
fi
if [ "$1" = publish ]; then
    git fetch -q origin
    [ -n "$(git branch -r --contains HEAD)" ] || { echo "$HEAD is not pushed" >&2; exit 1; }
    ! gh release view "$TAG" -R $REPO > /dev/null 2>&1 || { echo "$TAG is released already" >&2; exit 1; }
fi

# The archive: again only if it was made from another commit (or from uncommitted changes).
if [ "$(cat "$ARCHIVE/aok-commit" 2> /dev/null)" != "$HEAD" ] || ! git diff --quiet HEAD; then
    rm -rf "$ARCHIVE" "$OUT/appstore-$B"
    echo "archiving AOK VM $V ($B) at ${HEAD:0:8}..."
    xcodebuild -scheme "AOK VM" -destination generic/platform=iOS -configuration Release ARCHS=arm64 \
        -derivedDataPath "$DD" -archivePath "$ARCHIVE" -skipPackagePluginValidation -skipMacroValidation \
        -allowProvisioningUpdates archive > "$OUT/archive-$B.log" 2>&1 ||
        { grep "error:" "$OUT/archive-$B.log" | sort -u | head -20; exit 1; }
    git diff --quiet HEAD && echo "$HEAD" > "$ARCHIVE/aok-commit"
fi
built=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ARCHIVE/Products/Applications/UTM SE.app/Info.plist")
[ "$built" = "$B" ] || { echo "the archive is build $built, Build.xcconfig says $B" >&2; exit 1; }

# The App Store IPA.
if [ ! -f "$OUT/appstore-$B/UTM SE.ipa" ]; then
    cat > "$OUT/appstore-options.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>export</string>
	<key>teamID</key><string>$TEAM</string>
	<key>signingStyle</key><string>automatic</string>
	<key>uploadSymbols</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/appstore-$B" \
        -exportOptionsPlist "$OUT/appstore-options.plist" -allowProvisioningUpdates > "$OUT/appstore-$B.log" 2>&1 ||
        { grep -i "error" "$OUT/appstore-$B.log" | head -10; exit 1; }
fi
echo "App Store (Transporter): $OUT/appstore-$B/UTM SE.ipa"

# The sideloaders' IPA.
bash "$R/aok/utm/sideload-ipa.sh" "$ARCHIVE" "$IPA"

[ "$1" = publish ] || exit 0
NOTES=$(mktemp)
trap 'rm -f "$NOTES"' EXIT
sed '1d' aok/RELEASE-NOTES.md > "$NOTES"
cat >> "$NOTES" <<EOF

## Installing

* **TestFlight:** $TESTFLIGHT
* **Sideloading:** \`$(basename "$IPA")\` is for AltStore, SideStore, Sideloadly and the like, which sign it again under your own Apple ID. AOK VM finds its App Groups under the names that signing gives them. "Share /AOK/persist" reaches iSH-AOK's /AOK/persist when iSH-AOK was sideloaded the same way, with the same Apple ID; otherwise it is a directory of AOK VM's own. A free Apple ID does not get the increased memory limit, and machines are sized to the memory the app is given.

Problems: https://github.com/$REPO/issues
EOF
gh release create "$TAG" -R $REPO --target "$HEAD" --title "AOK VM $V ($B)" --notes-file "$NOTES" "$IPA"
