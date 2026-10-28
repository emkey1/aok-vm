# inc/dec for tctiSH's RCG (tctiSH/qemu#7)

The PR adds gadgets for inc and dec to RCG's structure A. Here it is timed
against structure A without it, with TCTI beside them. The code is tctiSH
`structure-a` at fed47ac5dd, and emkey1/qemu `rcg-incdec` at 3cc89a22c1 (the
PR, on it). Taken on 2026-10-28 on an M5 Max MacBook Pro (MBP5).

## What ran

| Column | QEMU | How it was started |
|---|---|---|
| TCTI | structure-a, x86_64-softmmu, TCTI; rcg off | `--backend tcti` |
| A | the same binary | `-accel tcg,...,rcg=on` (the `sa` wrapper) |
| A + inc/dec | rcg-incdec | `-accel tcg,...,rcg=on` (the `incdec` wrapper) |

Configure flags as in M3 (`../m3/scripts.txt`); `scripts.txt` has the builds,
the wrappers and the timing loops. The suite's machine, CPU and disk (disk
d9f049e41fd2).

Timing: three rounds, the three columns alternating round by round, every run
behind `--wait-quiet 1.5`; medians by wall clock, as `bench.py compare`
reports them (`timing.txt`). All 15 checks matched across the columns. xz
swung from 6.7 s to 11.6 s within a column, so it ran again on its own: six
rounds, A and A + inc/dec alternating (the second table in `timing.txt`).

## Results

- Against TCTI, geometric mean over the 17 workloads (Blender's render time,
  xonsh's median key latency): **A 0.650, 1.54x faster**. tctiSH measured
  1.57x on their M2 Max.
- **The PR against A: 0.997, level.** Every workload is between 0.967 and
  1.014: coremark 0.996, sha256sum 1.012, awk_words 1.013, nbody 0.977. xz,
  six rounds each, 10.86 s and 10.89 s.
- In M3 (`../m3`), inc and dec were the largest gap: each instruction with no
  gadget there was a trip through the main loop, 250 M to 470 M of them on
  each slow workload. In A it is TCG's own ops in the same TB, which by these
  numbers cost about what the gadget does.
- A leaves coremark (0.98x), nbody (1.00x) and sha256sum (1.03x) where TCTI
  has them, with or without inc/dec.
