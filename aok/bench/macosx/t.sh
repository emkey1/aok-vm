#!/bin/sh
# t.sh -- run in the Tiger guest: does each added application start? Its program is run for 15 s; one that is
# still there is counted as started and ended again; one that has gone has its first words printed.
for a in "$@"; do
    d=/Applications/$a.app; e=$(defaults read "$d/Contents/Info" CFBundleExecutable 2> /dev/null)
    [ -x "$d/Contents/MacOS/$e" ] || { echo "$a: no program ($e)"; continue; }
    "$d/Contents/MacOS/$e" > /tmp/t.$a 2>&1 &
    p=$!; sleep 15
    if kill -0 $p 2> /dev/null; then echo "$a: RUNS (still there after 15 s)"; kill $p; sleep 2; kill -9 $p 2> /dev/null
    else echo "$a: EXITED: $(head -4 /tmp/t.$a | tr '\n' ' ' | cut -c1-150)"; fi
done
echo "t.sh done"
