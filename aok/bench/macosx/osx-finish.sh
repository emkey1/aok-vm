#!/bin/bash
# on MBP5: osx-finish.sh OUT -- with the guest's Apple menu open at Shut Down: confirm, wait for the machine to
# power off, and write the work overlay and its base as one disk, macosx/work/OUT.
export PATH=/opt/homebrew/bin:$PATH
cd ~/aok-vm-bench/macosx/work || exit 1
python3 -I ~/aok-vm-bench/qmp.py qmp.sock key ret sleep 3 key ret
for i in $(seq 1 24); do sleep 10; pgrep -x qemu-system-ppc > /dev/null || break; done
pgrep -x qemu-system-ppc > /dev/null && { echo "still running after $((i*10)) s"; exit 1; }
echo "powered off after $((i*10)) s"
rm -f "$1"; qemu-img convert -O qcow2 try.qcow2 "$1" && qemu-img check "$1" | tail -1
ls -la "$1" | awk '{print $5, $9}'; shasum -a 256 "$1" | cut -c1-16
