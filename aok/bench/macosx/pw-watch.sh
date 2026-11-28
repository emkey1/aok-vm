#!/bin/bash
# on MBP5: pw-watch.sh TAG SECONDS -- while a script runs in the guest's Terminal, answer sudo's prompt whenever
# it is the last line on the screen (the test image's account; the word is the user's, given for this guest).
cd ~/aok-vm-bench/macosx; t=$1; X() { bash ../xb.sh $t "$@"; }
ocr=~/aok-vm-bench/ocr
end=$(( $(date +%s) + $2 ))
while [ $(date +%s) -lt $end ]; do
    X shot $t-w > /dev/null
    o=$($ocr shots/$t-w.png 2>/dev/null | grep -a -v '^$')
    echo "$o" | grep -a -q 'PKG-DONE' && { echo done; break; }
    last=$(echo "$o" | grep -a -n 'Password:' | tail -1 | cut -d: -f1)
    lastpk=$(echo "$o" | grep -a -n 'PKG \|pkg_add\|tar:' | tail -1 | cut -d: -f1)
    if [ -n "$last" ] && [ "${lastpk:-0}" -lt "$last" ] && [ "$last" != "$answered" ]; then
        X type "$(cat ~/aok-vm-bench/macosx/.pw)" key ret > /dev/null; answered=$last; sleep 5
    fi
    sleep 10
done
