#!/bin/sh
# check.sh -- a deterministic transcript: every line must be identical whichever engine ran it. Used to
# compare an engine under test with a trusted one (race.sh's workloads only report how long they took).
cd /bench
echo "CHECK coremark $(./coremark 0x0 0x0 0x66 600 7 1 2000 | grep -E 'crc|seedcrc|Correct' | tr '\n' ' ')"
echo "CHECK nbody $(./nbody 20000 | tr '\n' ' ')"
echo "CHECK python $(python3 pybench.py 1)"
echo "CHECK pybig $(python3 -c '
import hashlib
a = 3**2000 + 7; b = 5**900 - 11; h = hashlib.sha256()
for i in range(400):
    a = (a * b + i) % (2**4099 - 1); b = (b ^ (a >> 13)) + (a // (i + 3)) % 10**40
    h.update(str((a << (i % 61)) - b * (b % 1000003)).encode())
print(h.hexdigest(), a % 10**30, divmod(-a, 12345678901234567), (a & b).bit_length())')"
echo "CHECK pyfloat $(python3 -c '
import math
s = 0.0
for i in range(1, 20000): s += math.sin(i) * math.sqrt(i) / (1.0 + math.log(i)) - (i % 7) ** 0.5
print(repr(s), repr(math.fsum(1.0 / k for k in range(1, 5000))), 10**20 / 3, float(2**70) % 1e5, int(1e18 / 7))')"
echo "CHECK xz $(xz -T1 -3 -c data1.bin | sha256sum)"
echo "CHECK xzrt $(xz -T1 -1 -c data1.bin | xz -dc | sha256sum)"
echo "CHECK gzip $(gzip -9 -c data1.bin | sha256sum) $(gzip -1 -c data1.bin | gunzip -c | md5sum)"
echo "CHECK sha $(sha256sum data2.bin) $(sha512sum data1.bin | cut -c1-64) $(md5sum data2.bin | cut -c1-32) $(sha1sum data1.bin | cut -c1-40)"
echo "CHECK awk $(awk '{ for (i = 1; i <= NF; i++) c[$i]++ } END { n = 0; for (w in c) n += c[w] * length(w); print n }' data1.bin)"
echo "CHECK awkf $(awk 'BEGIN { s = 0; for (i = 1; i < 30000; i++) s += sqrt(i) * sin(i) / (i % 13 + 1); printf "%.10f %d\n", s, 2^31 * 3 / 7 }')"
echo "CHECK sort $(tr ' ' '\n' < data1.bin | sort | uniq -c | sort -rn | head -200 | md5sum) $(tr ' ' '\n' < data1.bin | sort -u | wc -l)"
echo "CHECK shell $(i=0; s=0; while [ $i -lt 20000 ]; do s=$(( (s * 31 + i * i) % 1000003 )); i=$((i + 1)); done; echo $s) $(seq 1 3000 | sed 's/7/x/g' | tr -d '\n' | md5sum | cut -c1-32)"
echo "CHECK find $(find /usr/lib /bin /sbin -type f | sort | xargs cat 2>/dev/null | sha256sum | cut -c1-64)"
echo "CHECK dd $(dd if=data.bin bs=4096 skip=37 count=1500 2>/dev/null | od -An -tx8 | md5sum | cut -c1-32) $(od -An -tu2 -N 4096 data2.bin | awk '{ for (i = 1; i <= NF; i++) s += $i * NR } END { print s }')"
echo "CHECK fptest $(./fptest | md5sum | cut -c1-32)"
echo CHECK-END
