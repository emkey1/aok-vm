#!/bin/bash
# drive.sh TEST... -- run Drive's tests (by name, in order) on the A10X (U= another device), then always give the
# screen back to the bench app's hold, so that the device never sits locked-out between steps (its Auto-Lock is ten
# minutes, and nobody is there to unlock it). A sequence, as build 8 was checked:
#   drive.sh testKeepAwake      AOK VM's "Disable screen dimming when idle" on: a running machine holds the screen
#   drive.sh test68k            the 68k console from the list; testShowDisplay, testShowSerial pick its window
#   drive.sh testPowerOff       the toolbar's Power Off (AOK VM exits with the machine)
#   drive.sh testPPC            the PowerPC console; testGuestPowerOff types "poweroff -f" at its shell
# The project is XcodeGen's, from project.yml (xcodegen is on MBP5, not on the Mac that signs).
D=$(cd "$(dirname "$0")" && pwd); U=${U:-5c56dee8545a5a555e052ecd50aa0e3ca9334a3b}
only=(); for t in "$@"; do only+=("-only-testing:AOKDriverUITests/Drive/$t"); done
n=$(date +%H%M%S); rm -rf "$D/r-$n.xcresult"
xcodebuild test -project "$D/AOKDriver.xcodeproj" -scheme AOKDriver -destination id=$U -allowProvisioningUpdates \
    -derivedDataPath "$D/dd" -resultBundlePath "$D/r-$n.xcresult" "${only[@]}" > "$D/run-$n.log" 2>&1
rc=$?
# A running machine holds the screen itself (AOK VM's "Disable screen dimming when idle" is on); otherwise the
# bench app takes it back.
if xcrun devicectl device info processes --device $U 2>/dev/null | grep -q 'UTM SE.app/AOK VM'; then
    echo "AOK VM running: no hold"
else
    "$HOME/git/aok-vm/aok/ios-app/keep-awake.sh" $U 3600 > /dev/null 2>&1 || echo "HOLD FAILED (locked?)"
fi
grep -E '^DRIVE |Test Case .*(passed|failed)|error: |Failed to initialize' "$D/run-$n.log" | cut -c1-400
echo "rc=$rc log=$D/run-$n.log result=$D/r-$n.xcresult"
