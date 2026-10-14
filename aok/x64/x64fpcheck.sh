#!/bin/bash
# x64fpcheck.sh TAG [TAG32] -- a gate transcript's floating point against the hardware's, on the Mac that drives both
# build hosts. The gate's references (logs/x64/ref-*.log) are QEMU_AOK=0's, and TCG's SSE is not x86's where fptest
# looks (which of two NaNs, for one), so their FP lines are the AOK engine's once this has found them the hardware's:
# fptest -- the very binary in the gate image -- run natively on camd (CAMD names it), its transcript against TAG's
# (an x86_64 run with fptest in its list) and its md5 against TAG's CHECK line; TAG32 likewise for the 32-bit guest's
# check; and fptest -v against logs/x64/aok-fpv.log's when there is one. Prints a line a comparison, SAME or DIFFERENT.
set -e
CAMD=${CAMD:-camd}
MBP5=${MBP5:-MBP5.local}     # (words: ssh options may come first)
SSH="ssh -o BatchMode=yes"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
tag=$1 tag32=$2
L='~/aok-vm-bench/logs/x64'
# The guest's transcript of a workload: its lines between WL-START and RESULT.
wl() { $SSH $MBP5 "tr -d '\r' < $L/$1.log | sed -n '/^WL-START $2\$/,/^RESULT $2 /p' | grep -av '^WL-START\|^RESULT\|^\['"; }
$SSH $MBP5 'bsdtar -xOf ~/aok-vm-bench/initramfs-x86_64.cpio bench/fptest' > "$T/fptest"
$SSH $CAMD 'f=$(mktemp); cat > $f; chmod +x $f; $f; rm -f $f' < "$T/fptest" > "$T/hw"
wl "$tag" fptest > "$T/aok"
cmp -s "$T/hw" "$T/aok" && v=SAME || v=DIFFERENT
echo "fptest (x86_64): $tag's $(wc -l < "$T/aok" | tr -d ' ') lines $v as camd's $(wc -l < "$T/hw" | tr -d ' ')"
c=$($SSH $MBP5 "grep -a '^CHECK fptest' $L/$tag.log | tr -d '\r' | cut -d' ' -f3")
h=$(md5 -q "$T/hw" 2>/dev/null || md5sum "$T/hw" | cut -c1-32)
[ "$c" = "$h" ] && v=SAME || v=DIFFERENT
echo "CHECK fptest (x86_64): $tag's $c $v as camd's $h"
if [ -n "$tag32" ]; then
    $SSH $MBP5 'bsdtar -xOf ~/aok-vm-bench/initramfs-x86.cpio bench/fptest' > "$T/fptest32"
    h=$($SSH $CAMD 'f=$(mktemp); cat > $f; chmod +x $f; $f | md5sum | cut -c1-32; rm -f $f' < "$T/fptest32")
    c=$($SSH $MBP5 "grep -a '^CHECK fptest' $L/$tag32.log | tr -d '\r' | cut -d' ' -f3")
    [ "$c" = "$h" ] && v=SAME || v=DIFFERENT
    echo "CHECK fptest (i386): $tag32's $c $v as camd's $h"
fi
if $SSH $MBP5 "test -f $L/aok-fpv.log"; then
    h=$($SSH $CAMD 'f=$(mktemp); cat > $f; chmod +x $f; $f -v | md5sum | cut -c1-32; rm -f $f' < "$T/fptest")
    c=$(wl aok-fpv fptestv | (md5 -q 2>/dev/null || md5sum | cut -c1-32))
    [ "$c" = "$h" ] && v=SAME || v=DIFFERENT
    echo "fptest -v (x86_64): aok-fpv's $c $v as camd's $h"
fi
