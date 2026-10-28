#!/bin/bash
# device-step.sh: MBP5's sysroot x86_64 engine into the app, the app built and installed on the M4, and ReactOS's
# debug output read from COM1 for 40 s. Exit 0 = output came (good), 1 = none (bad), 2 = setup failed.
D=00008132-000948C93483001C; R=100.116.123.106; L=/Users/mke/git/aok-vm/sysroot-ios-tci-arm64/Frameworks
F=qemu-x86_64-softmmu.framework; APP="$HOME/aok-vm-work/dd/Build/Products/Release-iphoneos/AOK VM.app"
rsync -a --delete -e "ssh -o HostKeyAlias=mbp5.local" $R:aok-vm-bench/engines/UTM/sysroot-ios-tci-arm64/Frameworks/$F/ $L/$F/ || exit 2
(cd /Users/mke/git/aok-vm && bash aok/app/build-app.sh device > ~/aok-vm-work/build-bisect.log 2>&1) || { tail -3 ~/aok-vm-work/build-bisect.log; exit 2; }
u1=$(dwarfdump --uuid "$APP/Frameworks/$F/qemu-x86_64-softmmu" | awk '{print $2}'); u2=$(dwarfdump --uuid "$L/$F/qemu-x86_64-softmmu" | awk '{print $2}')
[ "$u1" = "$u2" ] || { echo "app does not embed the new engine"; exit 2; }
xcrun devicectl device install app --device $D "$APP" > /dev/null 2>&1 || exit 2
cd /Users/mke/git/aok-vm
bash aok/app/start-vm.sh $D "ReactOS Timing C" > /dev/null 2>&1
# the iPad's link-local address changes with each connection: whichever neighbour answers on 4555
host=
for i in $(seq 60); do
    ping -c 1 -t 1 169.254.255.255 > /dev/null 2>&1
    for ip in $(arp -an | awk '/169\.254\./ && !/permanent/ && !/incomplete/ && !/255\.255/ { gsub(/[()]/, "", $2); print $2 }'); do
        nc -z -G 1 $ip 4555 2> /dev/null && { host=$ip; break; }
    done
    [ -n "$host" ] && break; sleep 0.3
done
[ -n "$host" ] || { echo "no serial port answered"; exit 2; }
out=$(mktemp); nc -d $host 4555 > $out & N=$!; sleep 40; kill $N 2>/dev/null
n=$(wc -c < $out | tr -d ' '); rm -f $out
bash aok/app/start-vm.sh $D --stop > /dev/null 2>&1
echo "engine $u1: serial $n bytes"
[ "$n" -gt 1000 ]
