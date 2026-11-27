#!/bin/bash
# on MBP5: the freeware the user approved for the Tiger disk (2026-11-27), each file in a directory of its own
# under macosx/dl: from the projects' own hosts, and TextWrangler from Macintosh Garden (2.1.3 is what it has).
D=$HOME/aok-vm-bench/macosx/dl; mkdir -p $D
get() { n=$1; f=$2; u=$3; mkdir -p "$D/$n"; ( cd "$D/$n" && curl -sSL -C - --retry 5 --max-time 7200 -A "curl/8" -o "$f" "$u" ); echo "$n: $(ls -la "$D/$n/$f" 2>/dev/null | awk '{print $5}') bytes  $(file -b "$D/$n/$f" | cut -c1-60)"; }
get tenfourfox TenFourFox7400-FPR32.5.app.zip "https://sourceforge.net/projects/tenfourfox/files/fpr32.5/TenFourFox7400-FPR32.5.app.zip/download"
get vlc        vlc-2.0.10-powerpc.dmg         "https://download.videolan.org/pub/videolan/vlc/2.0.10/macosx/vlc-2.0.10-powerpc.dmg"
get xbench     Xbench_1.3.dmg                 "http://www.xbench.com/Xbench_1.3.dmg"
get dosbox     DOSBox-0.74-2_Universal.dmg    "https://sourceforge.net/projects/dosbox/files/dosbox/0.74-2/DOSBox-0.74-2_Universal.dmg/download"
get scummvm    scummvm-1.2.1-macosx.dmg       "https://downloads.scummvm.org/frs/scummvm/1.2.1/scummvm-1.2.1-macosx.dmg"
get supertux   supertux-0.1.3-macosx-universal.dmg "https://github.com/SuperTux/supertux/releases/download/v0.1.3/supertux-0.1.3-macosx-universal.dmg"
page=apps/textwrangler-213
u=$(curl -sL --max-time 60 -A "Mozilla/5.0 (Macintosh)" "https://macintoshgarden.org/$page" | grep -o '//download.macintoshgarden.org/apps/[^"]*' | head -1)
if [ -n "$u" ]; then f=$(basename "${u%%\?*}"); mkdir -p $D/textwrangler; ( cd $D/textwrangler && curl -sSL --max-time 900 -A "Mozilla/5.0 (Macintosh)" -e "https://macintoshgarden.org/$page" -o "$f" "https:$u" ); echo "textwrangler: $(ls -la "$D/textwrangler/$f" | awk '{print $5}') bytes  $(file -b "$D/textwrangler/$f" | cut -c1-60)  [$f]"; else echo "textwrangler: no link on $page"; fi
get wesnoth    Wesnoth_1.8.6.dmg              "https://sourceforge.net/projects/wesnoth/files/wesnoth-1.8/wesnoth-1.8.6/Wesnoth_1.8.6.dmg/download"
( cd $D && shasum -a 256 */* | cut -c1-16,65- )
echo DL2-DONE
