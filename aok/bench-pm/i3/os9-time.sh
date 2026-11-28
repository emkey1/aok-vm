#!/bin/bash
# os9-time.sh TAG [APP] -- on the A10X: (install APP,) start "Mac OS 9 Test" (it boots Mac OS 9's CD: nothing is
# written) and say how long until the screen reads as the Finder's, a look every few seconds; twice. Then the
# machine is ended and the bench app holds the screen.
U=5c56dee8545a5a555e052ecd50aa0e3ca9334a3b
S=/private/tmp/claude-501/-Users-mke-git-ish-AOK/7b3fb99e-2b30-444a-9291-e34744be360f/scratchpad/up/a10x
SV=/Users/mke/git/aok-vm/aok/app/start-vm.sh; tag=$1; app=$2; cd $S
[ -n "$app" ] && { echo "$(date +%T) $tag: install build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist") ($(stat -f %Sm "$app/AOK VM"))"; xcrun devicectl device install app --device $U "$app" 2>&1 | grep -E 'ERROR|error' | cut -c1-140; }
for r in 1 2; do
    bash $SV $U "Mac OS 9 Test" > /dev/null 2>&1; t0=$(date +%s); up=
    for i in $(seq 1 40); do
        xcrun devicectl device capture screenshot --device $U --destination "$S/$tag-t.png" > /dev/null 2>&1
        t=$(( $(date +%s) - t0 ))
        f=$(./ocr $tag-t.png | grep -a -c -E '^(File|Special|Finder)|Mac OS 9|Trash')
        [ "$f" -gt 1 ] && { up=$t; break; }
        sleep 2
    done
    cp $tag-t.png $tag-up$r.png
    echo "$(date +%T) $tag run $r: the Finder's screen after ${up:-more than $t} s ($i looks)"
    bash $SV $U --stop > /dev/null 2>&1; sleep 4
done
echo "OS9-TIME-DONE $tag"
