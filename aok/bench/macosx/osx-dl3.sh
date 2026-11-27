#!/bin/bash
# on MBP5: the versions that run on Mac OS X 10.4, in place of three that need 10.5 (VLC 2.0.10: libiconv;
# TextWrangler 3.5.3: _kUTTypeImage; Wesnoth 1.8.6: ___stack_chk_guard in its Lua). Same titles and sources.
D=$HOME/aok-vm-bench/macosx/dl
mkdir -p $D/vlc-tiger $D/textwrangler-tiger $D/wesnoth-tiger
( cd $D/vlc-tiger && curl -sSL -C - --retry 5 -O https://download.videolan.org/pub/videolan/vlc/0.9.10/macosx/vlc-0.9.10-powerpc.dmg; ls -la vlc-0.9.10-powerpc.dmg | awk '{print "vlc " $5}' )
page=apps/textwrangler-213
u=$(curl -sL --max-time 60 -A "Mozilla/5.0 (Macintosh)" "https://macintoshgarden.org/$page" | grep -o '//download.macintoshgarden.org/apps/TextWrangler_3.1.dmg[^"]*' | head -1)
[ -n "$u" ] && ( cd $D/textwrangler-tiger && curl -sSL --max-time 900 -A "Mozilla/5.0 (Macintosh)" -e "https://macintoshgarden.org/$page" -o TextWrangler_3.1.dmg "https:$u"; ls -la TextWrangler_3.1.dmg | awk '{print "textwrangler " $5}' )
cd $D/wesnoth-tiger
for i in $(seq 1 40); do curl -sSL -C - --max-time 7200 -A curl/8 -o Wesnoth_1.6.5.dmg "https://sourceforge.net/projects/wesnoth/files/wesnoth-1.6/wesnoth-1.6.5/Wesnoth_1.6.5.dmg/download" 2>/dev/null; [ "$(stat -f %z Wesnoth_1.6.5.dmg 2>/dev/null)" = 233422600 ] && break; sleep 5; done
ls -la Wesnoth_1.6.5.dmg | awk '{print "wesnoth " $5}'
( cd $D && shasum -a 256 vlc-tiger/* textwrangler-tiger/* wesnoth-tiger/* | cut -c1-16,65- )
echo DL3-DONE
