#!/bin/bash
# make-cd.sh OUT.iso [DL] -- a CD of open-source programs for ReactOS.utm that installs them with no network: the
# downloads of manifest.txt (each checked against its SHA-1; kept in DL, default ~/aok-vm-work/ros-software-dl, and
# not fetched again), INSTALL.CMD (double-click it on the CD in ReactOS: each installer with its silent switch, a
# log in C:\AOK-install.log), SHORTCUTS.VBS and README.TXT. On a Mac (hdiutil). For a machine with no network, or
# to save the downloads; with a network, ReactOS's Applications Manager installs the same programs (SOFTWARE.md).
# The machine needs a CD drive for it: README.md, "Software from a CD".
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?OUT.iso}
DL=${2:-$HOME/aok-vm-work/ros-software-dl}
mkdir -p "$DL"
T=$(mktemp -d "${TMPDIR:-/tmp}/ros-cd.XXXXXX"); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/cd/SETUP" "$T/cd/APPS"
sha1() { shasum -a 1 "$1" 2> /dev/null | cut -d' ' -f1; }
while read -r kind sha url dir; do
    case $kind in ""|\#*) continue ;; esac
    f=$DL/$(basename "$url")
    [ "$(sha1 "$f")" = "$sha" ] || curl -fsSL --retry 3 -o "$f" "$url"
    [ "$(sha1 "$f")" = "$sha" ] || { echo "$url: not the SHA-1 in manifest.txt" >&2; exit 1; }
    case $kind in
        setup) cp "$f" "$T/cd/SETUP/" ;;
        zip)   mkdir -p "$T/cd/APPS/$dir"; unzip -q -o "$f" -d "$T/cd/APPS/$dir" ;;
    esac
done < "$here/manifest.txt"
for f in INSTALL.CMD SHORTCUTS.VBS README.TXT; do
    sed 's/$/\r/' "$here/$f" > "$T/cd/$f"   # CRLF, as ReactOS's cmd and Notepad want them
done
rm -f "$OUT"
hdiutil makehybrid -quiet -o "$OUT" "$T/cd" -iso -joliet -default-volume-name AOK_PROGRAMS
ls -l "$OUT"
