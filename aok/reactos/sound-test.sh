#!/bin/bash
# sound-test.sh -- does ReactOS make a sound on the machine's sound card (AC97)? Boots an overlay of the finished
# disk twice with ros-run.sh's ROS_SOUND=wav, which records what the card plays to sound.wav. The first boot is the
# disk meeting the card (screenshots show any New Hardware Wizard), then plays ReactOS_Startup.wav with mplay32,
# typed in the Run box; the second is the next start, where ReactOS plays that sound by itself at logon. Each
# boot's loudest sample is printed (0 = silence). On MBP5, beside ros-run.sh; Homebrew's QEMU (screen dumps).
K=$(cd "$(dirname "$0")" && pwd); B=~/aok-vm-bench
export ROS_DIR=$B/ros-sound ROS_SOUND=wav ROS_NONET=1; W=$ROS_DIR
rm -rf $W; mkdir -p $W; cd $W
/opt/homebrew/bin/qemu-img create -q -f qcow2 -b ${ROS_BASE:-$B/reactos-build/reactos.qcow2} -F qcow2 ros.qcow2
mon() { echo "$1" | nc -U -w 1 $W/mon.sock > /dev/null; }
key() { # type a string through the monitor
    perl -e '
        my %m = (" "=>"spc", "/"=>"slash", "."=>"dot", "-"=>"minus", "_"=>"shift-minus", "\\"=>"backslash",
                 ":"=>"shift-semicolon");
        for my $c (split //, $ARGV[0]) {
            my $k = $m{$c} // ($c =~ /[A-Z]/ ? "shift-" . lc $c : $c);
            print "sendkey $k\n";
        }' "$1" | while read -r l; do mon "$l"; sleep 0.05; done
}
peak() { # the loudest 16-bit sample in a wav, after its 44-byte header
    perl -e 'local $/; open my $f, "<", $ARGV[0] or die; binmode $f; my $d = <$f>; my $m = 0;
             for (unpack "s<*", substr($d, 44)) { my $a = abs; $m = $a if $a > $m } print "$m\n"' "$1"
}
boot() { # boot N: start, wait for the desktop, then run the rest of the arguments
    local n=$1; shift
    rm -f serial.log sound.wav
    QEMU=/opt/homebrew/bin/qemu-system-i386 bash $K/ros-run.sh > q$n.out 2>&1 &
    for i in $(seq 120); do grep -qF 'AllFolders' serial.log 2>/dev/null && break; sleep 2; done
    echo "[$(date +%T)] boot $n: desktop"
    "$@"
    mon "system_powerdown"
    for i in $(seq 90); do pgrep -f "ros-sound/ros.qcow2" > /dev/null || break; sleep 2; done
    pkill -f "ros-sound/ros.qcow2"; sleep 1
    cp serial.log serial$n.log
    echo "boot $n: sound.wav $(stat -f %z sound.wav) bytes, loudest sample $(peak sound.wav)"
    grep -a -i -E 'ac97|newdev|portcls|wdmaud|SETUP' serial.log | sort | uniq -c | sort -rn | head -8
}
first() {
    local s; for s in 1 2 3 4; do sleep 15; mon "screendump $W/b1-$s.ppm"; done
    mon "sendkey meta_l-r"; sleep 3
    key 'mplay32 C:\ReactOS\Media\ReactOS_Startup.wav'; sleep 1; mon "sendkey ret"
    echo "[$(date +%T)] mplay32"
    sleep 20; mon "screendump $W/b1-play.ppm"
}
second() { sleep 30; mon "screendump $W/b2.ppm"; }
boot 1 first
boot 2 second
for f in *.ppm; do sips -s format png "$f" --out "${f%.ppm}.png" > /dev/null 2>&1; done
