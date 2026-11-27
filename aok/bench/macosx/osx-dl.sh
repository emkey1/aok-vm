#!/bin/bash
# on MBP5: Mac OS X 10.4 (PowerPC) for testing, from archive.org's item mac-osx-tiger-10.4-ppc-installed-qcow2-image
# (the user's choice, 2026-11-27): an installed disk as qcow2 in a 7z, and the install DVD. Each in a directory of
# its own under ~/aok-vm-bench/macosx; the 7z is unpacked with bsdtar into a third.
M=$HOME/aok-vm-bench/macosx; U=https://archive.org/download/mac-osx-tiger-10.4-ppc-installed-qcow2-image
mkdir -p $M/installed-7z $M/dvd $M/installed
( cd $M/installed-7z && curl -sSL -C - --retry 5 -O $U/osx-tiger_10.4.11_installed.qcow2.7z; echo "7z rc=$? $(ls -la osx-tiger_10.4.11_installed.qcow2.7z | awk '{print $5}')"
  [ "$(stat -f %z osx-tiger_10.4.11_installed.qcow2.7z)" = 1929055939 ] && cd $M/installed && tar -xf $M/installed-7z/osx-tiger_10.4.11_installed.qcow2.7z && echo "unpacked: $(ls -la | tail -n +2 | awk '{print $5, $9}' | tr '\n' ' ')" ) > $M/dl-7z.log 2>&1 &
( cd $M/dvd && curl -sSL -C - --retry 5 -O $U/OSX_Tiger_4.6_installation_dvd.img; echo "dvd rc=$? $(ls -la OSX_Tiger_4.6_installation_dvd.img | awk '{print $5}')" ) > $M/dl-dvd.log 2>&1 &
wait; echo OSX-DL-DONE
