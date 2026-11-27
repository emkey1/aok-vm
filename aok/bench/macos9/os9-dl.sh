#!/bin/bash
# on MBP5: the freeware the user approved (2026-11-27), each file in a directory of its own under macos9/dl.
# Classilla and MacSSH from SourceForge, the Marathon trilogy from Bungie's release, three small ones from
# Macintosh Garden (whose links carry a token, so its page is read first).
D=$HOME/aok-vm-bench/macos9/dl; mkdir -p $D
get() { n=$1; f=$2; u=$3; mkdir -p "$D/$n"; ( cd "$D/$n" && [ -s "$f" ] || curl -sSL --max-time 900 -A "curl/8" -o "$f" "$u" ); echo "$n: $(ls -la "$D/$n/$f" 2>/dev/null | awk '{print $5}') bytes  $(file -b "$D/$n/$f" | cut -c1-50)"; }
get classilla  "Classilla 9.3.3.sit"   "https://sourceforge.net/projects/classilla/files/9.3.3/Classilla%209.3.3.sit/download"
get macssh     "MacSSHPPC-2.1fc3.sit"  "https://sourceforge.net/projects/macssh/files/MacSSH%20PPC/2.1fc3/MacSSHPPC-2.1fc3.sit/download"
get marathon   "marathon.sit"          "http://files3.bungie.org/trilogy/marathon.sit"
get marathon2  "marathon_2.sit"        "http://files3.bungie.org/trilogy/marathon_2.sit"
get marathoninf "marathon_infinity.sit" "http://files3.bungie.org/trilogy/marathon_infinity.sit"
mg() { n=$1; page=$2; pat=$3; f=$4
    u=$(curl -sL --max-time 60 -A "Mozilla/5.0 (Macintosh)" "https://macintoshgarden.org/$page" | grep -o "//download.macintoshgarden.org/apps/$pat?[^\"]*" | head -1)
    [ -n "$u" ] || { echo "$n: no link on $page"; return; }
    mkdir -p "$D/$n"; ( cd "$D/$n" && [ -s "$f" ] || curl -sSL --max-time 600 -A "Mozilla/5.0 (Macintosh)" -e "https://macintoshgarden.org/$page" -o "$f" "https:$u" )
    echo "$n: $(ls -la "$D/$n/$f" | awk '{print $5}') bytes  $(file -b "$D/$n/$f" | cut -c1-50)"; }
mg bbeditlite apps/bbedit-lite-612 'bbedit_lite_612.smi_.bin' bbedit_lite_612.smi.bin
mg soundapp   apps/soundapp        'SoundAppPPC273.sit_.bin'  SoundAppPPC273.sit.bin
mg gaugepro   apps/gauge-pro       'GaugePRO11.sit'           GaugePRO11.sit
( cd $D && shasum -a 256 */* | cut -c1-16,65- )
echo DL-DONE
