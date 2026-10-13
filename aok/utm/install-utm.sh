#!/bin/bash
# install-utm.sh DEVICE [VMDIR] -- install the UTM SE build on a device (a devicectl identifier) and copy the
# virtual machines of make-vm.py (default ~/aok-utm/vms) into its Documents, where UTM lists them.
# Starting a VM takes a tap: UTM for iOS has no way to start one from outside. Afterwards
# Documents/NAME.utm/Data/debug.log holds the QEMU command line and QEMU's messages.
set -e
dev=$1; vms=${2:-$HOME/aok-utm/vms}; id=app.ish.aok.UTM-SE
xcrun devicectl device install app --device "$dev" "$HOME/aok-utm/dd/Build/Products/Release-iphoneos/UTM SE.app" |
    grep -E "bundleID|ERROR"
for v in "$vms"/*.utm; do
    xcrun devicectl device copy to --device "$dev" --domain-type appDataContainer --domain-identifier $id \
        --source "$v" --destination "Documents/$(basename "$v")" > /dev/null
    echo "copied $(basename "$v")"
done
