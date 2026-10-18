#!/bin/sh
# build-in.sh ARCH -- inside an Alpine root of ARCH (iSH-AOK's test roots, which have gcc): tests.list's tests for
# ARCH, static, into out/ARCH, the compiler's messages into out/ARCH.log and a BUILD-FAIL line for each that did
# not build. vfork_exec_stale_jit's twelve peers (vfork_exec_stale_jit_peer0-11, -DSTALE_JIT_PAD_PAGES) go
# beside it, as iSH-AOK's setup-regressions.sh builds them.
a=$1
mkdir -p "out/$a"
: > "out/$a.log"
grep -v '^#' tests.list | while read -r arch name src check flags; do
    [ "$arch" = "$a" ] || continue
    o=out/$a/$name
    echo "+ $name" >> "out/$a.log"
    case "$flags" in
    asm*)         cc ${flags#asm} -nostdlib -static -Wl,-e,_start -o "$o" "src/$src" ;;
    *-nostdlib*)  cc $flags -static -o "$o" "src/$src" ;;
    *)            cc ${flags:--O2} -static -pthread -Isrc -o "$o" "src/$src" -lm -ldl ;;
    esac >> "out/$a.log" 2>&1 || echo "BUILD-FAIL $name" >> "out/$a.log"
    if [ "$name" = vfork_exec_stale_jit ]; then
        p=0
        while [ $p -lt 12 ]; do
            cc -O2 -static -pthread -DSTALE_JIT_PAD_PAGES=$p -Isrc -o "out/$a/vfork_exec_stale_jit_peer$p" \
                src/vfork_exec_stale_jit_peer.c -lm -ldl >> "out/$a.log" 2>&1 ||
                echo "BUILD-FAIL vfork_exec_stale_jit_peer$p" >> "out/$a.log"
            p=$((p + 1))
        done
    fi
done
echo "built $(ls "out/$a" | wc -l) for $a"
