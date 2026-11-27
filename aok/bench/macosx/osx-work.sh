#!/bin/bash
# on MBP5: osx-work.sh -- the Tiger disk being prepared (macosx/work/tiger.qcow2, a copy of the installed image)
# on Homebrew's QEMU with a network card, and macosx/dl served to the guest at 10.0.2.2:8642 (this Mac's loopback).
# QMP: macosx/work/qmp.sock.
export PATH=/opt/homebrew/bin:$PATH
M=$HOME/aok-vm-bench/macosx; mkdir -p $M/work; cd $M/work
[ -f tiger.qcow2 ] || { cp $M/installed/osx-tiger_10.4.11_installed.qcow2 tiger.qcow2; chmod u+w tiger.qcow2; }
pgrep -f "http.server 8642" > /dev/null || (nohup python3 -I -m http.server 8642 --bind 127.0.0.1 --directory $M/dl > http.log 2>&1 &)
rm -f qmp.sock
nohup qemu-system-ppc -M mac99,via=pmu -m 1024 -boot c -drive file=tiger.qcow2,format=qcow2,media=disk -nic user,model=sungem \
    -display none -serial file:ser.log -qmp unix:qmp.sock,server=on,wait=off < /dev/null > qemu.log 2>&1 &
echo "pid $!"
