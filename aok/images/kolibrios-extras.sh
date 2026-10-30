#!/bin/bash
# kolibrios-extras.sh KOLIBRIOS_ZIP OUTDIR -- OUTDIR/kolibrios-extras-0.7.7.0-8930.zip, the "KolibriOS with Extras"
# machine: the KolibriOS machine AOK VM carries (KOLIBRIOS_ZIP, kolibrios-0.7.7.0-8930.zip) with a CD in its empty
# CD drive. The CD is KolibriOS's own CD for the same revision (builds.kolibrios.org) less its boot floppy, loaders
# and Wolfenstein 3D: the kolibrios folder of extra programs and games, which KolibriOS's SEARCHAP finds on any disk
# at start and mounts as /kolibrios, where App+ and the menus look for them. Wolfenstein 3D's folder is left out
# because its game data is the full, registered game, still sold (the Doom and Quake data on the CD are their
# shareware episodes, free to pass on). The CD does not boot, so the machine still starts from the floppy.
# On a Mac: curl, bsdtar, hdiutil, PlistBuddy, zip. OUTDIR also keeps the download (~44 MB).
set -euo pipefail
ZIP=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); OUT=$(mkdir -p "$2" && cd "$2" && pwd)
REV=0.7.7.0+8930-d50642c
SEVENZ=kolibrios-$REV-iso.7z
# what builds.kolibrios.org served on 2026-10-30, to the Air and to MBP5 alike; its own sha256sums.txt gives
# cb3bb619... for this name, which matches no copy it serves
SHA=cef44851741081dcbdb9f8fcb221bdb104f3060d7d1061fabf7d7c914c0b5e03
NAME="KolibriOS with Extras"
UUID=5B9E68D9-8D7F-4F3F-B24A-AD5ED0DA6134
T=$(mktemp -d "${TMPDIR:-/tmp}/kosx.XXXXXX"); trap 'rm -rf "$T"' EXIT
[ -f "$OUT/$SEVENZ" ] || curl -fL --max-time 1800 -o "$OUT/$SEVENZ" "https://builds.kolibrios.org/en_US/$SEVENZ"
echo "$SHA  $OUT/$SEVENZ" | shasum -a 256 -c - > /dev/null
mkdir "$T/x" "$T/iso" "$T/cd" "$T/m"
bsdtar -xf "$OUT/$SEVENZ" -C "$T/x" kolibri.iso
bsdtar -xf "$T/x/kolibri.iso" -C "$T/iso"
chmod -R u+rwX,go+rX "$T/iso"
(cd "$T/m" && unzip -q "$ZIP")
cmp -s "$T/iso/kolibri.img" "$T/m/KolibriOS.utm/Data/kolibri.img" ||
    { echo "the CD's floppy is not the machine's: another revision" >&2; exit 1; }
mv "$T/iso/kolibrios" "$T/cd/kolibrios"
rm -rf "$T/cd/kolibrios/games/wolf3d"
cat > "$T/cd/README.TXT" <<EOF
AOK VM: KolibriOS's extras

The kolibrios folder of KolibriOS $REV's CD (builds.kolibrios.org,
$SEVENZ), unchanged but for games/wolf3d, left out: its game
data is the full Wolfenstein 3D, which is still sold. KolibriOS mounts this
folder as /kolibrios when it starts; App+, on its desktop, starts much of it.

KolibriOS is free software under the GNU GPL version 2; its source is at
https://git.kolibrios.org/KolibriOS/kolibrios. The other programs here are
their authors', under their own licences (see each one's folder).
EOF
perl -pi -e 's/\n/\r\n/' "$T/cd/README.TXT"
hdiutil makehybrid -quiet -iso -joliet -default-volume-name KOLIBRIOS_EXTRAS -o "$T/kolibrios-extras.iso" "$T/cd"
M="$T/m/$NAME.utm"
mv "$T/m/KolibriOS.utm" "$M"
mv "$T/kolibrios-extras.iso" "$M/Data/"
P="$M/config.plist"
NOTES="KolibriOS 0.7.7.0+8930 (d50642c), the official boot floppy from builds.kolibrios.org, in the machine \
Mighty-Moth-Boy made (github.com/emkey1/aok-vm/issues/1), with KolibriOS's extras on a CD in its CD drive: the \
kolibrios folder of KolibriOS's own CD for the same revision. App+, on the desktop, starts many of them; the rest \
are in /kolibrios (Eolite, on the desktop, opens it). Among them: Doom and Quake (their shareware episodes), \
Tyrian 2000, DOSBox, ScummVM, emulators for the NES, SNES, Game Boy, Mega Drive and ZX Spectrum, Free Pascal, Tiny \
C, Lua, Oberon, the NetSurf web browser, a PDF reader and a video player. Wolfenstein 3D, on KolibriOS's CD, is \
left out: its game data is the full game, still sold. The machine starts from the floppy and runs from memory; the \
hard disk is empty, for files of your own. If KolibriOS's own shutdown leaves the machine running, stop it with \
the power button in the toolbar.

KolibriOS is free software under the GNU GPL version 2. Its source is at git.kolibrios.org/KolibriOS/kolibrios. \
The other programs on the CD are their authors', under their own licences (README.TXT on the CD)."
[ "$(plutil -extract Drive.0.ImageType raw "$P")" = CD ] || { echo "drive 0 is not the CD" >&2; exit 1; }
plutil -replace Information.Name -string "$NAME" "$P"
plutil -replace Information.UUID -string "$UUID" "$P"
plutil -replace Information.Notes -string "$NOTES" "$P"
plutil -insert Drive.0.ImageName -string kolibrios-extras.iso "$P"
rm -f "$OUT/kolibrios-extras-0.7.7.0-8930.zip"
(cd "$T/m" && zip -q -r -X "$OUT/kolibrios-extras-0.7.7.0-8930.zip" "$NAME.utm")
ls -l "$OUT/kolibrios-extras-0.7.7.0-8930.zip"
shasum -a 256 "$OUT/kolibrios-extras-0.7.7.0-8930.zip"
