#!/bin/sh
# Runs every workload once, in a fixed order. The same script runs under AOK and inside the QEMU guests.
cd /bench
. ./params
./timeit sleep1 sleep 1
./timeit coremark ./coremark 0x0 0x0 0x66 $COREMARK_ITERS 7 1 2000
./timeit nbody ./nbody $NBODY_STEPS
./timeit python python3 pybench.py $PY_SCALE
./timeit xz xz -T1 -$XZ_LEVEL -c data.bin
./timeit sha256 sh -c "for i in $SHA_LOOPS; do sha256sum data.bin; done"
./timeit awk awk '{ for (i = 1; i <= NF; i++) c[$i]++ } END { n = 0; for (w in c) n += c[w] * length(w); print n }' data.bin
