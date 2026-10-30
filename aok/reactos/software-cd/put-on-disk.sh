#!/bin/bash
# put-on-disk.sh IN.qcow2 OUT.qcow2 -- OUT: IN (an installed ReactOS disk, build.sh's) with "Get Programs" on it:
# C:\AOK\Programs\ holding GET.CMD, GETFILE.EXE (getfile.c, built here), INSTALL.CMD, SHORTCUTS.VBS, README.TXT
# and FILES.TXT (manifest.txt with each download's file name, for GET.CMD), and "Get Programs" on the desktop,
# which starts GET.CMD. GET.CMD downloads the programs from their makers' sites and installs them, as the CD does
# (SOFTWARE.md): nothing of theirs is on the disk. Written into the FAT file system with mtools, no mount; OUT is
# uncompressed. build.sh's step 7; on a Mac with Homebrew's qemu, mtools and zig.
set -euo pipefail
PATH=/opt/homebrew/bin:$PATH
IN=${1:?IN.qcow2}; OUT=${2:?OUT.qcow2}
here=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/getprogs.XXXXXX"); trap 'rm -rf "$T"' EXIT
qemu-img convert -O raw "$IN" "$T/disk.raw"   # sparse
# the first partition's start, from the MBR
AT=$(python3 -I - "$T/disk.raw" <<'EOF'
import struct, sys
mbr = open(sys.argv[1], "rb").read(512)
assert mbr[510:512] == b"\x55\xaa", "no MBR"
print(struct.unpack_from("<I", mbr, 446 + 8)[0] * 512)
EOF
)
export MTOOLS_SKIP_CHECK=1
C="$T/disk.raw@@$AT"
DESK="::/Documents and Settings/All Users/Desktop"
mdir -i "$C" -b "$DESK" > /dev/null || { echo "no All Users desktop on $IN" >&2; exit 1; }
crlf() { sed 's/$/\r/' "$1" > "$2"; }   # as ReactOS's cmd and Notepad want them
mkdir "$T/p"
for f in GET.CMD INSTALL.CMD SHORTCUTS.VBS README.TXT; do crlf "$here/$f" "$T/p/$f"; done
# GETFILE.EXE: Win32 alone, for NT 5.1 and later (ReactOS is 5.2), zig's mingw headers and import libraries
ZLIB=$(zig env | sed -n 's/^ *\.lib_dir = "\(.*\)",*$/\1/p')
zig cc -target x86-windows-gnu -Os -s -nostdlib -isystem "$ZLIB/libc/include/any-windows-any" \
    -fno-stack-protector -mno-stack-arg-probe -Wall -Wextra -Wno-unused-parameter -Werror \
    -Wl,--entry=start -Wl,--subsystem,console -Wl,--major-os-version,5 -Wl,--minor-os-version,1 \
    -Wl,--major-subsystem-version,5 -Wl,--minor-subsystem-version,1 \
    "$here/getfile.c" -lkernel32 -luser32 -lwininet -ladvapi32 -lshell32 -o "$T/p/GETFILE.EXE"
perl -ne 'if (/^#/ || !/\S/) { print; next } chomp; my ($kind, $sha, $url, $dir) = split / /, $_, 4;
          (my $name = $url) =~ s{.*/}{}; print join(" ", $kind, $sha, $name, $url, $dir // ()), "\n"' \
    "$here/manifest.txt" > "$T/files.txt"
{ echo "# FILES.TXT: what GET.CMD downloads, KIND SHA-1 FILE URL [DIR], from manifest.txt:"; cat "$T/files.txt"; } \
    > "$T/files2.txt"
crlf "$T/files2.txt" "$T/p/FILES.TXT"
printf '@call "C:\\AOK\\Programs\\GET.CMD"\r\n' > "$T/launch.cmd"
mmd -i "$C" ::/AOK 2> /dev/null || true
mmd -i "$C" ::/AOK/Programs 2> /dev/null || true
mcopy -i "$C" -o "$T"/p/* ::/AOK/Programs/
mcopy -i "$C" -o "$T/launch.cmd" "$DESK/Get Programs.cmd"
mdir -i "$C" -b ::/AOK/Programs "$DESK"
rm -f "$OUT"
qemu-img convert -O qcow2 "$T/disk.raw" "$OUT"
