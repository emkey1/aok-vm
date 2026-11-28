#!/bin/bash
# sim-os9.sh -- AOK VM (the simulator build under ~/aok-vm-work/dd-repo) in the Air's iPad simulator with "Mac OS 9
# Test" (Mac OS 9's CD: nothing is written): a picture every 10 s until the screen reads as the Finder's, then
# the app's log lines about the engine. The simulator is shut down again afterwards.
D=BD7A0A11-C59A-4DE6-964D-7ACE7DCF7AA0
S=/private/tmp/claude-501/-Users-mke-git-ish-AOK/7b3fb99e-2b30-444a-9291-e34744be360f/scratchpad/up
APP=$HOME/aok-vm-work/dd-repo/Build/Products/Release-iphonesimulator/"AOK VM.app"
wd() { perl -e 'alarm shift; exec @ARGV' "$@"; }
xcrun simctl boot $D 2>/dev/null; wd 120 xcrun simctl bootstatus $D > /dev/null 2>&1
xcrun simctl install $D "$APP"
c=$(xcrun simctl get_app_container $D app.ish.aok.vm data)
[ -d "$c/Documents/Mac OS 9 Test.utm" ] || cp -R "$S/dev/Mac OS 9 Test.utm" "$c/Documents/"
ls "$c/Documents" | tr '\n' '|'; echo
SIMCTL_CHILD_AOKVM_START="Mac OS 9 Test" SIMCTL_CHILD_QEMU_AOK_STATS=1 xcrun simctl launch $D app.ish.aok.vm > /dev/null; t0=$(date +%s); up=
for i in $(seq 1 18); do
    sleep 10; wd 30 xcrun simctl io $D screenshot $S/sim/os9-$i.png > /dev/null 2>&1; t=$(( $(date +%s) - t0 ))
    f=$($S/a10x/ocr $S/sim/os9-$i.png | grep -a -c -E '^(File|Special|Finder)|Mac OS 9|Trash')
    echo "t=$t: finder-words $f"
    [ "$f" -gt 1 ] && { up=$t; break; }
done
echo "the Finder's screen after ${up:-more than $t} s"; cp $S/sim/os9-$i.png $S/sim/os9-last.png
grep -a -E 'engine|aok|Error|error' "$c/Documents/Mac OS 9 Test.utm/Data/debug.log" 2>/dev/null | grep -av 'Could not connect' | head -6 | cut -c1-200
xcrun simctl terminate $D app.ish.aok.vm > /dev/null 2>&1; sleep 2
grep -a 'aok:' "$c/Documents/Mac OS 9 Test.utm/Data/debug.log" 2>/dev/null | tail -6 | cut -c1-220
xcrun simctl shutdown $D
echo SIM-OS9-DONE
