#!/bin/bash
# on MBP5: end the Tiger work machine (by the pid of the process that holds its QMP socket's directory open as cwd
# is not needed: its command line names the work disk) and throw the work copy away; the next osx-work.sh copies anew.
cd ~/aok-vm-bench/macosx/work || exit 1
for q in $(pgrep -x qemu-system-ppc); do ps -o command= -p $q | grep -q 'media=disk -nic user,model=sungem' && { kill $q; echo "ended $q"; }; done
sleep 2; rm -f tiger.qcow2 qmp.sock; ls
shasum -a 256 ../installed/osx-tiger_10.4.11_installed.qcow2 | cut -c1-16
