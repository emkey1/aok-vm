#!/bin/bash
# irq47-mig.sh BUILD [SECS]: run coremark on the ppc kit, save the VM to a file after SECS, restore it in
# a new QEMU, and see the run finish and power off there. The save is live: a source stopped first would
# restore paused.
W=$HOME/aok-vm-bench; B=$1; S=${2:-10}; D=/tmp/irq47/mig; rm -rf $D; mkdir -p $D
ND=$W/src/pc-bios/ppc-ndrvloader
q() { $B/qemu-system-ppc-unsigned -L $W/src/pc-bios -M mac99,via=pmu -m 512 -nographic -nodefaults -serial stdio \
    -audio none -device loader,addr=0x4000000,file=$ND -prom-env "boot-command=init-program go" \
    -device virtio-tablet-pci -kernel $W/kit/ppc/vmlinux -initrd $W/kit/ppc/initramfs.cpio \
    -append "console=ttyS0 rdinit=/init bench=${BENCH:-coremark,nbody,xz} then=poweroff" -no-reboot "$@"; }
mon() { python3 - "$1" "$2" <<'P'
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); s.settimeout(2)
def rd():
    out = b''
    try:
        while True:
            c = s.recv(4096)
            if not c: break
            out += c
    except socket.timeout: pass
    return out.decode(errors='replace')
rd()
for cmd in sys.argv[2].split(';'):
    s.sendall((cmd + '\n').encode()); time.sleep(0.5); print(rd().strip().splitlines()[-1:] if cmd else '')
P
}
q -monitor unix:$D/mon1,server,nowait > $D/out1.txt 2>&1 & p=$!
sleep $S
mon $D/mon1 "migrate file:$D/state.bin"
for i in $(seq 1 60); do grep -q completed <(mon $D/mon1 "info migrate" 2>/dev/null) && break; sleep 1; done
mon $D/mon1 "info migrate"; mon $D/mon1 "quit"; wait $p
ls -la $D/state.bin; tail -2 $D/out1.txt
q -monitor none -incoming file:$D/state.bin > $D/out2.txt 2>&1 & p=$!
for i in $(seq 1 240); do kill -0 $p 2>/dev/null || break; sleep 1; done; kill -9 $p 2>/dev/null
echo "restored run (${i}s):"; tail -5 $D/out2.txt
