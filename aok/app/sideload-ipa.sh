#!/bin/bash
# sideload-ipa.sh ARCHIVE OUT.ipa -- the sideloaders' IPA (AltStore, SideStore, Sideloadly) of an AOK VM archive:
# the same app as the App Store IPA made from that archive, without its provisioning profiles and signed ad hoc,
# with the app's entitlements.
#
# A sideloading tool signs the app again under its user's Apple ID, and asks Apple for what the entitlements of
# the app it is given name: an IPA with none (CODE_SIGNING_ALLOWED=NO, as UTM's own unsigned IPAs and iSH-AOK's
# once were) comes out with no App Groups, and then neither virglrenderer's shared memory (Vulkan) nor iSH-AOK's
# /AOK/persist works. So the archive's own entitlements are kept, less what names our team and the debugger
# (application-identifier, the team identifier, get-task-allow); the tool renames the groups for its team, and
# the app finds them under their new names at run time (UTMSignedAppGroups).
set -e
ARCHIVE=$1
[ -d "$ARCHIVE/Products/Applications" ] && [ -n "$2" ] || { echo "usage: $0 ARCHIVE OUT.ipa" >&2; exit 1; }
OUT=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
APP=$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' | head -1)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir "$T/Payload"
cp -R "$APP" "$T/Payload/"
A="$T/Payload/$(basename "$APP")"
find "$A" -name embedded.mobileprovision -delete

# The app's entitlements, as the archive has them, less the team's and the debugger's.
codesign -d --entitlements - --xml "$APP" > "$T/archived.plist" 2> /dev/null
cp "$T/archived.plist" "$T/app.plist"
for key in application-identifier com.apple.developer.team-identifier get-task-allow keychain-access-groups; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$T/app.plist" 2> /dev/null || true
done
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups' "$T/app.plist" > /dev/null ||
    { echo "the archive's app has no App Groups: is it AOK VM's archive?" >&2; exit 1; }

# Inside out: frameworks and the helper extension (its entitlements are only the team's), then the app.
find "$A/Frameworks" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) -exec codesign --force --sign - --timestamp=none {} \; 2> /dev/null
find "$A/Extensions" "$A/PlugIns" -maxdepth 1 -name '*.appex' -exec codesign --force --sign - --timestamp=none {} \; 2> /dev/null || true
codesign --force --sign - --timestamp=none --entitlements "$T/app.plist" --generate-entitlement-der "$A" 2> /dev/null
codesign --verify --deep --strict "$A"

# What a sideloading tool will read.
codesign -d --entitlements - --xml "$A" 2> /dev/null > "$T/signed.plist"
for group in $(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups' "$T/app.plist" | sed '1d;$d'); do
    grep -q "<string>$group</string>" "$T/signed.plist" || { echo "$group is missing from the signed app" >&2; exit 1; }
done

rm -f "$OUT"
(cd "$T" && zip -qry -X "$OUT" Payload)
echo "$OUT ($(du -h "$OUT" | cut -f1)), signed ad hoc with: $(plutil -convert json -o - "$T/app.plist")"
