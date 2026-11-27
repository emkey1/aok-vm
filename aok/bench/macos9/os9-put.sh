#!/bin/bash
# on MBP5: put the downloaded archives on the Mac OS 9 disk, in a folder Freeware, from macOS, which reads and
# writes its Mac OS Extended volume. Each gets a type and creator so that a double click opens it in StuffIt
# Expander (creator SITx; SITD an archive, BINA MacBinary). What macOS leaves on a volume is taken off again.
set -e
M=$HOME/aok-vm-bench/macos9; cd $M/hd
[ -f os9-hd-922.img ] || cp os9-hd.img os9-hd-922.img
out=$(hdiutil attach -nobrowse -noverify -owners off -imagekey diskimage-class=CRawDiskImage os9-hd.img)
dev=$(echo "$out" | awk 'NR==1{print $1}'); V=$(echo "$out" | grep Apple_HFS | sed 's/.*Apple_HFS[[:space:]]*//')
echo "attached $dev at [$V]"; [ -d "$V/System Folder" ] || { echo "not the disk"; hdiutil detach $dev; exit 1; }
mdutil -i off "$V" > /dev/null 2>&1 || true
mkdir -p "$V/Freeware"
finfo() { xattr -wx com.apple.FinderInfo "$(printf '%s%s' "$2" "$3" | xxd -p)000000000000000000000000000000000000000000000000" "$1"; }
for f in $M/dl/*/*; do b=$(basename "$f"); cp "$f" "$V/Freeware/$b"
    case $b in *.bin) finfo "$V/Freeware/$b" BINA SITx ;; *) finfo "$V/Freeware/$b" SITD SITx ;; esac; done
ls -la "$V/Freeware" | cut -c25-
xattr -px com.apple.FinderInfo "$V/Freeware/marathon.sit" | head -1
rm -rf "$V/.fseventsd" "$V/.Spotlight-V100" "$V/.Trashes" "$V/.DS_Store" "$V/Freeware/.DS_Store" 2>/dev/null || true
ls -a "$V" | tr '\n' ' '; echo
sync; hdiutil detach $dev | tail -1
