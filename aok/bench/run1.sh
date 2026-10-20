#!/bin/sh
# run1.sh NAME... -- run the named workloads once each, in order. Same script under AOK and in the QEMU guests.
# Each is bracketed by a WL-START line and timeit's RESULT line, which the host-side cycwrap watches for.
cd /bench
for w in "$@"; do
    echo "WL-START $w"
    case "$w" in
    coremark) ./timeit coremark ./coremark 0x0 0x0 0x66 4000 7 1 2000 ;;
    nbody)    ./timeit nbody ./nbody 2000000 ;;
    nbody87)  ./timeit nbody87 ./nbody87 2000000 ;;         # 32-bit x86: the same through the x87
    python)   ./timeit python python3 pybench.py 1 ;;
    xz)       ./timeit xz xz -T1 -3 -c data2.bin ;;
    sha256)   ./timeit sha256 sh -c "sha256sum data.bin; sha256sum data.bin" ;;
    awk)      ./timeit awk awk '{ for (i = 1; i <= NF; i++) c[$i]++ } END { n = 0; for (w in c) n += c[w] * length(w); print n }' data1.bin ;;
    check)    ./check.sh; ./timeit check true ;;
    stresst)  # stress's four checks at once, timed: what a guest with several CPUs gains from running them in parallel
              ./timeit stresst sh -c 'for i in 1 2 3 4; do ./check.sh > /tmp/check.$i 2>&1 & done; wait'
              for i in 1 2 3 4; do echo "STRESS $i $(md5sum < /tmp/check.$i | cut -c1-32)"; done ;;
    stress)   # four transcripts at once, for a guest with several CPUs: all four must be the one check prints
              for i in 1 2 3 4; do ./check.sh > /tmp/check.$i 2>&1 & done; wait
              for i in 1 2 3 4; do echo "STRESS $i $(md5sum < /tmp/check.$i | cut -c1-32)"; done
              ./timeit stress true ;;
    fptest)   ./fptest; ./timeit fptest true ;;
    memtest)  ./memtest; ./timeit memtest true ;;
    fptestv)  ./fptest -v; ./timeit fptestv true ;;
    simdtest) ./simdtest; ./timeit simdtest true ;;         # aarch64: every FP/SIMD encoding
    simdtest-*) ./simdtest -b "${w#simdtest-}"; ./timeit "$w" true ;;   # one bucket of it, a line an encoding
    x86test)  ./x86test; ./timeit x86test true ;;           # x86 and x86_64: the integer instructions
    x86testv) ./x86test -v; ./timeit x86testv true ;;       # every result of it
    tsotest)  ./tsotest; ./timeit tsotest true ;;            # x86's memory order between parallel CPUs
    kmovtest) ./kmovtest; ./timeit kmovtest true ;;          # x86_64: AVX-512's opmask moves
    vec)      # x86_64: the vector tests (x64/vec, iSH-AOK's, each with its answers), their last lines
        for t in /bench/vec/*; do printf 'VEC %s: ' "${t##*/}"; "$t" 2>&1 | tail -1; done; ./timeit vec true ;;
    vec-*)    t=/bench/vec/${w#vec-}; printf 'VEC %s: ' "${t##*/}"; "$t" 2>&1 | tail -1; ./timeit "$w" true ;;
    vecv-*)   t=/bench/vec/${w#vecv-}; "$t" 2>&1 | head -120; ./timeit "$w" true ;;   # its first failures, in full
    cpu|cpu-*|cpuv-*) # iSH-AOK's processor tests (cputest/tests.list; cputest/cpu-image.sh puts them in
              # /bench/cpu): each one's output between a CPUTEST line and a CPUTEST-END with its status; cpu-ARCH
              # or cpu-NAME runs some, cpuv-ARCH or cpuv-NAME with -v (what a failure was, in tests that say)
        sel=${w#cpu}; sel=${sel#v}; sel=${sel#-}; v=; case $w in cpuv-*) v=-v ;; esac
        echo 0 > /proc/sys/kernel/randomize_va_space   # (the D tests print addresses; cpu-camd.sh: setarch -R)
        echo "CPUINFO $(uname -m) $(grep -m1 -i '^isa\|^flags\|^Features' /proc/cpuinfo | cut -c1-600)"
        grep -v '^#' cpu/list | while read -r a n s c f; do
            [ -x "cpu/$a/$n" ] || continue
            [ -z "$sel" ] || [ "$sel" = "$n" ] || [ "$sel" = "$a" ] || continue
            echo "CPUTEST $a/$n $c"
            (cd "cpu/$a" && busybox timeout -s KILL 300 "./$n" $v < /dev/null 2>&1)
            echo "CPUTEST-END $a/$n rc=$?"
        done
        ./timeit "$w" true ;;
    dmesg)    dmesg | tail -60 ;;                       # the kernel's last words: a signal's faulting instruction
    diag)     # where a workload's system time goes: the guest's counters around sha256 and around awk, those that
              # moved by more than 200 (interrupts, softirqs, /proc/stat, vmstat), and the cpu line before and after
        snap() { { cat /proc/interrupts /proc/softirqs; grep -E '^(ctxt|intr|softirq|processes) ' /proc/stat
                   cat /proc/vmstat; } > /tmp/diag.$1; grep '^cpu ' /proc/stat; }
        for x in sha256 awk; do
            snap a; sh /bench/run1.sh $x | grep -a '^RESULT'; snap b
            awk 'NR == FNR { for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+$/) { a[$1] = $i; break }; next }
                 { for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+$/) { d = $i - a[$1]; if (d > 200 || d < -200)
                   printf "  %s %d\n", $1, d; break } }' /tmp/diag.a /tmp/diag.b
        done ;;
    dump)     # diag in full, with the kernel's log and the CPU it was given, to the virtio console when there is one
              # (-device virtconsole: QEMU writes it to a file, which a device's machine can be pulled off as)
        o=/dev/hvc0; [ -c $o ] || o=/dev/stdout
        { echo "== dmesg"; dmesg; echo "== cpuinfo"; cat /proc/cpuinfo; echo "== meminfo"; cat /proc/meminfo
          echo "== vmstat before"; cat /proc/vmstat; echo "== interrupts before"; cat /proc/interrupts
          sh /bench/run1.sh awk; echo "== vmstat after"; cat /proc/vmstat; echo "== interrupts after"
          cat /proc/interrupts; echo "== softirqs"; cat /proc/softirqs; echo "== stat"; cat /proc/stat
          echo "== end"; } > $o 2>&1
        echo "dump: to $o" ;;
    faults)   # who takes a workload's page faults: awk's and sha256's own (their shell's cminflt, field 11 of
              # /proc/PID/stat) and every process's minflt before and after, to the virtio console as dump does
        o=/dev/hvc0; [ -c $o ] || o=/dev/stdout
        procs() { for s in /proc/[0-9]*/stat; do read -r l < $s 2>/dev/null && echo "$l"; done |
                  awk '{ p = $1; sub(/^[0-9]+ \(/, ""); split($0, a, ") "); split(a[2], f, " ")
                         print p ":" a[1], f[8] }' | sort; }
        { for x in sha256 awk; do
              procs > /tmp/f.a
              sh -c "sh /bench/run1.sh $x | grep -a '^RESULT'; read -r l < /proc/\$\$/stat; echo \"\$l\"" |
                  awk '/^RESULT/ { print; next } { sub(/^.*\) /, ""); print "  own minflt (cminflt) " $9 }'
              procs > /tmp/f.b
              awk 'NR == FNR { a[$1] = $2; next } $2 - a[$1] > 100 { print "  proc", $1, $2 - a[$1] }' /tmp/f.a /tmp/f.b
          done; echo "== end"; } > $o 2>&1
        echo "faults: to $o" ;;
    x87kat)   ./x87_kat; ./x87_kat_unmasked; ./x87_trans; ./timeit x87kat true ;;   # the x87 against hardware's answers
    x87kat3)  for i in 1 2 3; do ./x87_kat | grep -v fldcw; ./x87_kat_unmasked | grep -v fldcw; done; ./timeit x87kat3 true ;;   # is a failure the same one each time?
    poke)     # a kernel patching its own code under the other CPUs' feet: Linux flips a static key by
              # writing a breakpoint, then the new bytes, and counts on no CPU meeting the breakpoint
              # after that. The scheduler's statistics key sits in paths the three busy shells never leave.
              for i in 1 2 3; do ( while :; do ./check.sh > /dev/null 2>&1; done ) & done
              n=0; while [ $n -lt 1500 ]; do
                  echo 1 > /proc/sys/kernel/sched_schedstats; echo 0 > /proc/sys/kernel/sched_schedstats
                  n=$((n + 1))
              done
              kill $(jobs -p) 2> /dev/null; echo "POKE $n"; ./timeit poke true ;;
    *)        ./timeit "$w" true ;;
    esac
done
