# M0 for tctiSH's RCG (tctiSH/qemu#6)

Reference numbers for the Rich Code Generator's evaluation: which integer
instructions tctiSH's benchmark suite (`utils/bench` in tctiSH) executes most,
and the AOK gadgets' times, full and near-integer-only, beside current TCTI.
Taken on 2026-10-23 on an M5 Max MacBook Pro (MBP5).

## What ran

| Column | QEMU | How it was started |
|---|---|---|
| TCTI | tctiSH `tctish-edition` f3ebb682b6, x86_64-softmmu, TCTI only | `--backend tcti` |
| AOK | emkey1/qemu `aok-vm` eeb0f03dcd (f3ebb682b6 merged in), same flags plus `--enable-aok-gadgets` | `QEMU_AOK=1` |
| AOK int | the same binary | also `QEMU_AOK_X86_NOX87=1 QEMU_AOK_X86_NOVEC=1 QEMU_AOK_X86_SSEHELPERS=1` |
| counts | tctiSH f3ebb682b6 on the JIT, `--enable-plugins --enable-capstone`, with `mnemcount.c` | `--backend jit` |

Common configure flags: `--target-list=x86_64-softmmu --enable-fdt --enable-tcg
--disable-werror --disable-docs --enable-slirp --disable-dbus-display`
(`--enable-tcg-threaded-interpreter` for the TCTI and AOK builds). The suite's
own machine, CPU and disk (pc-i440fx-11.1, Haswell-v4, 4 vCPUs, disk
d9f049e41fd2). `scripts.txt` has the exact scripts and wrappers.

Timing: three rounds, the three columns alternating round by round, every run
behind `--wait-quiet 1.5`; medians by wall clock, as `bench.py compare`
reports them (`timing.txt`). All 15 checks matched across the columns.

Counts: each workload once, every executed guest instruction counted by
mnemonic with an inline per-vCPU counter (`mnemcount.c`, a TCG plugin), into
`counts/WORKLOAD.txt`. A count is the whole run, the guest's boot included
(`node_startup`'s run is 3.8 G instructions, mostly boot). `summarise.py
counts` folds AT&T's size suffixes and condition codes into families
(`summary.txt`).

## Results

- AOK against TCTI, geometric mean over the 17 workloads (Blender's render
  time, xonsh's median key latency): **0.477, 2.10x faster**; near-integer-only
  **0.499, 2.00x**. Near-integer-only gives up Blender (0.47x becomes 0.98x:
  its AVX goes to TCG) and a little of Node's (node_compute 0.44x to 0.53x).
- 281 G instructions in all: integer 89.8%, vector 10.2% (Blender and nbody),
  x87 and MMX none.
- 21 integer families make up 95% of the integer instructions; mov 25.2%,
  jcc 14.3%, cmp 7.8%, test 5.4%, add 4.8%, movzx 3.3%, lea 3.1%, push 2.7%,
  pop 2.5%, xor 2.5%, and 2.5%, sub 2.0%.
- The evaluation subset (mov, lea, add, sub, and, or, xor, inc, dec, neg,
  not, cmp, test, push, pop) is 60.8% of everything executed, 67.8% of the
  integer instructions.
