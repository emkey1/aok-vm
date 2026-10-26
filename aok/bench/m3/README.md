# M3 for tctiSH's RCG (tctiSH/qemu#6)

Structure B: RCG's gadgets run as separate streams, each an ordinary TB of
gadget addresses and operand words, beside TCG's TBs. The code is emkey1/qemu
`rcg-m3` at dfd7dbdcde, on tctiSH `tctish-edition` 0c7e606fbb (M1,
b5b12100ad, included). Taken on 2026-10-26 on an M5 Max MacBook Pro (MBP5).

## What ran

| Column | QEMU | How it was started |
|---|---|---|
| TCTI | rcg-m3, x86_64-softmmu, TCTI; rcg off, so tctiSH 0c7e606fbb | `--backend tcti` |
| M3 | the same binary | `-accel tcg,...,rcg=on` (the `rcg` wrapper) |
| AOK | emkey1/qemu `aok-vm` eeb0f03dcd, M0's binary | `QEMU_AOK=1` |

Configure flags as in M0 (`../m0/README.md`); `scripts.txt` has the builds,
the wrappers and the timing loop. The suite's machine, CPU and disk (disk
d9f049e41fd2).

Timing: three rounds, the three columns alternating round by round, every run
behind `--wait-quiet 1.5`; medians by wall clock, as `bench.py compare`
reports them (`timing.txt`). All 15 checks matched across the columns.

Hand-offs: a diagnostic build (`rcg-dbg.py` applied to rcg-m3's
`accel/tcg/cpu-exec.c`; not on the branch) counts, by guest pc, every TCG TB
the main loop runs straight after a stream, with the code bytes there.
`handoffs/WORKLOAD.txt` is its output for one run of each of the four
workloads M3 makes slower, and `handoffs.py` names the instruction at each pc
(`handoffs/summary.txt`). A count is the whole run, boot included: the
kernel's `inc rbp` at ffffffff81385485 and its neighbours, about 62 M, are in
every workload.

## Results

- Against TCTI, geometric mean over the 17 workloads (Blender's render time,
  xonsh's median key latency): **M3 0.920, 1.09x faster**; AOK **0.518,
  1.93x**.
- M3 is faster on 10 workloads (lua_build 0.65x, sympy 0.64x, pybench 0.67x,
  node_prettier 0.66x), level on 3 (blender_render, lean_plausible,
  node_startup) and slower on 4: sha256sum 1.88x, awk_words 1.59x, coremark
  1.42x, nbody 1.17x.
- A stream and a TCG TB never link, so going from one to the other is a trip
  through the main loop. Each of the four slow workloads makes 250 M to 470 M
  of them each way:

| Workload | Streams ending in a TCG TB | At the instruction the stream gave up on |
|---|---:|---|
| coremark | 380 M | imul 51%, inc 24%, a Jcc at a TB's start 7%, dec 4%, shl/shr 6% |
| sha256sum | 466 M | inc 73%, bswap 13%, dec 3% |
| awk_words | 419 M | inc 27%, bt 21%, imul 10%, dec 10% |
| nbody | 248 M | inc 37%, movsd/movapd 41% (no vector gadgets) |

- inc and dec are in the evaluation subset, but `rcg-gen.py` at b5b12100ad
  generates no gadget for them, only the conditions that read their flags.
  They are the largest single gap.
- A Jcc at a TB's start has its flags in an unknown lazy state, and its
  conditions only have gadgets for a known one. That gap is M3's front end's,
  not the generator's.
