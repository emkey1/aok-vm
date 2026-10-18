#!/bin/bash
# cpu-camd.sh TAG [cpu|cpu-ARCH|cpu-NAME] -- the x86 oracle: the x86_64 and i386 tests cpu-image.sh built (on
# MBP5, /tmp/cpukit/out) run on camd's own cores (a Ryzen 5 3500U, Zen+: no AVX-512, so what needs it fails
# there), as run1.sh's cpu workload runs them in the guest, as camd's user (the guest runs them as root). The
# transcript goes to MBP5's logs/cpu/TAG.log, for cpu-cmp.py.
set -e
CAMD=${CAMD:-camd}
MBP5=${MBP5:-MBP5.local}     # (words: ssh options may come first)
SSH="ssh -o BatchMode=yes"
tag=$1; sel=${2:-cpu}; sel=${sel#cpu}; sel=${sel#-}
$SSH $MBP5 "cd /tmp/cpukit && tar -cf - tests.list out/x86_64 out/i386" |
    $SSH $CAMD "rm -rf ~/aokvm-cpu && mkdir -p ~/aokvm-cpu && tar -xf - -C ~/aokvm-cpu"
$SSH $CAMD "cd ~/aokvm-cpu/out && echo \"CPUINFO \$(uname -m) \$(grep -m1 '^flags' /proc/cpuinfo | cut -c1-600)\"
    grep -v '^#' ../tests.list | while read -r a n s c f; do
        [ -x \"\$a/\$n\" ] || continue
        [ -z '$sel' ] || [ '$sel' = \"\$n\" ] || [ '$sel' = \"\$a\" ] || continue
        echo \"CPUTEST \$a/\$n \$c\"
        (cd \"\$a\" && timeout -s KILL 300 \"./\$n\" < /dev/null 2>&1)
        echo \"CPUTEST-END \$a/\$n rc=\$?\"
    done" | $SSH $MBP5 "mkdir -p ~/aok-vm-bench/logs/cpu && cat > ~/aok-vm-bench/logs/cpu/$tag.log"
echo "$tag: $($SSH $MBP5 "grep -c '^CPUTEST-END' ~/aok-vm-bench/logs/cpu/$tag.log") tests ran"
