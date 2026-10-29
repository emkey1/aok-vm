#!/bin/bash
# install-app.sh DEVICE [VMDIR] -- install the AOK VM build on a device (a devicectl identifier) and copy the
# virtual machines of make-vm.py (default ~/aok-vm-work/vms) into its Documents, where the app lists them.
# start-vm.sh starts one with no tap (AOKVM_START). Afterwards Documents/NAME.utm/Data/debug.log holds the
# QEMU command line and QEMU's messages.
set -e
dev=$1; vms=${2:-$HOME/aok-vm-work/vms}; id=app.ish.aok.vm
xcrun devicectl device install app --device "$dev" "$HOME/aok-vm-work/dd/Build/Products/Release-iphoneos/AOK VM.app" |
    grep -E "bundleID|ERROR"
for v in "$vms"/*.utm; do
    [ -e "$v" ] || continue   # none there: the app alone
    xcrun devicectl device copy to --device "$dev" --domain-type appDataContainer --domain-identifier $id \
        --source "$v" --destination "Documents/$(basename "$v")" > /dev/null
    echo "copied $(basename "$v")"
done
