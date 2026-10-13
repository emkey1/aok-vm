#!/bin/bash
# a64cmp.sh RUN REF: compare two a64run.sh transcripts (logs/a64/RUN.log against logs/a64/REF.log)
W=$HOME/aok-vm-bench/logs/a64
ext() { tr -d "\r" < "$1" | sed -n "/^BENCH-START/,/^BENCH-END/p" | grep -av "^RESULT\|^aok:\|^BENCH-START"; }
# (files of this run's own: two compares at once must not read each other's)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ext "$W/$1.log" > "$T/a"; ext "$W/$2.log" > "$T/b"
n=$(wc -l < "$T/a" | tr -d " ")
if [ "$n" -gt 0 ] && cmp -s "$T/a" "$T/b"; then v=IDENTICAL; else v="DIFFERENT ($(wc -l < "$T/b" | tr -d " ") in ref)"; fi
echo "$1 vs $2: $n lines $v; $(grep -a "^RESULT" "$W/$1.log" | cut -d" " -f2,3 | tr "\n" ";") ref $(grep -a "^RESULT" "$W/$2.log" | cut -d" " -f2,3 | tr "\n" ";")"
