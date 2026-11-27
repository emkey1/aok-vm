#!/bin/bash
# on MBP5: osx-try.sh [brew|new] -- the finished Tiger disk on a throwaway overlay (macosx/work/try.qcow2), with a
# network card and macosx/dl served at 10.0.2.2:8642. QMP: macosx/work/qmp.sock (lookx.sh).
export PATH=/opt/homebrew/bin:$PATH
W=$HOME/aok-vm-bench; M=$W/macosx; cd $M/work
case ${1:-brew} in brew) Q=(qemu-system-ppc) ;; new) Q=($W/build-os9-new/qemu-system-ppc-unsigned -L $W/src-aok/pc-bios) ;; esac
pgrep -f "http.server 8642" > /dev/null || (nohup python3 -I -m http.server 8642 --bind 127.0.0.1 --directory $M/dl > http.log 2>&1 &)
rm -f qmp.sock try.qcow2; qemu-img create -q -f qcow2 -b tiger-final.qcow2 -F qcow2 try.qcow2
nohup "${Q[@]}" -M mac99,via=pmu -m 1024 -boot c -drive file=try.qcow2,format=qcow2,media=disk -nic user,model=sungem \
    -display none -serial file:ser.log -qmp unix:qmp.sock,server=on,wait=off < /dev/null > qemu.log 2>&1 &
echo "pid $!"
