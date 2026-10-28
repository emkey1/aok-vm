#!/bin/bash
# bisect-build.sh: build qemu-system-x86_64 (Mac, AOK gadgets) from src-bisect as it is checked out, in build-bisect.
export PATH=/opt/homebrew/bin:$PATH
B=~/aok-vm-bench
cd $B/src-bisect || exit 1
for d in berkeley-softfloat-3 berkeley-testfloat-3 dtc keycodemapdb libucontext slirp; do
    [ -d subprojects/$d ] || cp -a $B/src-aok/subprojects/$d subprojects/
done
mkdir -p $B/build-bisect && cd $B/build-bisect
[ -f build.ninja ] || ../src-bisect/configure --target-list=x86_64-softmmu --without-default-features --enable-fdt=internal \
    --enable-tcg --disable-werror --disable-docs --enable-tcg-threaded-interpreter --enable-aok-gadgets > configure.out 2>&1 ||
    { tail -5 configure.out; exit 1; }
ninja qemu-system-x86_64 > ninja.out 2>&1 || { grep -m5 -E "error|FAILED" ninja.out; exit 1; }
echo "built $(git -C $B/src-bisect log --oneline -1 | cut -c1-60)"
