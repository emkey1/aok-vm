#!/bin/bash
# start-vm.sh DEVICE NAME -- start AOK VM on a device with its machine NAME running, no tap needed: the app's
# AOKVM_START launch variable (Platform/Shared/ContentView.swift). Any AOK VM already running is ended first, with
# its machine. Afterwards Documents/NAME.utm/Data/debug.log has the QEMU command line; a screenshot shows the
# machine's screen: xcrun devicectl device capture screenshot --device DEVICE --destination FILE.png.
#   start-vm.sh DEVICE --stop   ends AOK VM, and the machine with it
dev=$1; name=$2
if [ "$name" = --stop ]; then
    t=$(mktemp)
    xcrun devicectl device info processes --device "$dev" --json-output "$t" > /dev/null 2>&1
    pid=$(python3 -c 'import json, sys
for p in json.load(open(sys.argv[1]))["result"]["runningProcesses"]:
    if p.get("executable", "").endswith("UTM%20SE.app/AOK%20VM") or p.get("executable", "").endswith("UTM SE.app/AOK VM"):
        print(p["processIdentifier"])' "$t" | head -1)
    rm -f "$t"
    [ -n "$pid" ] && xcrun devicectl device process terminate --device "$dev" --pid "$pid" > /dev/null 2>&1 &&
        echo "ended AOK VM ($pid)"
    # the screen back to the bench app's hold, so that the device does not lock
    exec "$(dirname "$0")/../ios-app/keep-awake.sh" "$dev" 3600
fi
env=$(python3 -c 'import json, sys; print(json.dumps({"AOKVM_START": sys.argv[1]}))' "$name")
exec xcrun devicectl device process launch --device "$dev" --terminate-existing --environment-variables "$env" \
    app.ish.aok.vm
