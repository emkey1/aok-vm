#!/bin/sh
# i.sh -- run in the Tiger guest (Terminal): fetch the freeware from the host (10.0.2.2 is the Mac that runs QEMU,
# serving macosx/dl) and put each application in /Applications, with the guest's own hdiutil and ditto.
# A disk image that asks for a licence to be accepted is left alone and named: sh i.sh NAME... does some only.
H=http://10.0.2.2:8642; W=/Users/Shared/Freeware; mkdir -p $W; cd $W || exit 1
L=$W/install.log; : >> $L
say() { echo "$*"; echo "$*" >> $L; }
dmg() {   # NAME DIR FILE
    curl -s -f -O "$H/$2/$3" || { say "$1: not fetched"; return; }
    out=$(hdiutil attach -nobrowse -noverify -noautoopen "$3" < /dev/null 2>&1) || { say "$1: the image did not attach (a licence to accept?): $(echo "$out" | tail -1)"; return; }
    m=$(echo "$out" | grep '/Volumes/' | tail -1 | sed 's/.*\(\/Volumes\/.*\)/\1/')
    n=0
    # Only real directories on the image itself: find does not follow links, and many images carry a link to
    # /Applications, through which a wildcard reaches the guest's own applications. Nothing is ever removed:
    # an application already in /Applications is left as it is.
    find "$m" -maxdepth 2 -type d -name '*.app' > $W/apps.txt 2> /dev/null
    while read -r a; do
        case $a in "$m"/*) ;; *) continue ;; esac
        b=$(basename "$a")
        if [ -e "/Applications/$b" ]; then say "$1: /Applications/$b is there already, left alone"; n=1; continue; fi
        ditto "$a" "/Applications/$b" && { say "$1: installed $b"; n=1; }
    done < $W/apps.txt
    rm -f $W/apps.txt
    [ $n = 1 ] || say "$1: no application found in $m: $(ls "$m" | tr '\n' ' ')"
    hdiutil detach "$m" > /dev/null 2>&1; rm -f "$3"
}
zip() {   # NAME DIR FILE
    curl -s -f -O "$H/$2/$3" || { say "$1: not fetched"; return; }
    mkdir -p $W/unz && ditto -x -k "$3" $W/unz && for a in $W/unz/*.app; do b=$(basename "$a")
        if [ -e "/Applications/$b" ]; then say "$1: /Applications/$b is there already, left alone"; else mv "$a" /Applications/ && say "$1: installed $b"; fi; done
    rm -rf $W/unz "$3"
}
want() { [ $# -eq 0 ] && return 0; for x in "$@"; do [ "$x" = "$N" ] && return 0; done; return 1; }
for N in tenfourfox vlc xbench dosbox scummvm supertux textwrangler wesnoth; do
    want "$@" || continue
    case $N in
    tenfourfox)   zip TenFourFox tenfourfox TenFourFox7400-FPR32.5.app.zip ;;
    vlc)          dmg VLC vlc vlc-2.0.10-powerpc.dmg ;;
    xbench)       dmg Xbench xbench Xbench_1.3.dmg ;;
    dosbox)       dmg DOSBox dosbox DOSBox-0.74-2_Universal.dmg ;;
    scummvm)      dmg ScummVM scummvm scummvm-1.2.1-macosx.dmg ;;
    supertux)     dmg SuperTux supertux supertux-0.1.3-macosx-universal.dmg ;;
    textwrangler) dmg TextWrangler textwrangler TextWrangler_3.5.3.dmg ;;
    wesnoth)      dmg Wesnoth wesnoth Wesnoth_1.8.6.dmg ;;
    esac
done
say "done: $(date)"; df -h / | tail -1
