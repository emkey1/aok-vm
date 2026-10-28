# The next TB looked up in a gadget, not helper_lookup_tb_ptr()

Option 3 of `../whole`: after an indirect jump, a call through memory or a
return, a TCTI TB ends with a call of `helper_lookup_tb_ptr()` and
`goto_ptr`. Under RCG (structure A) that call and the helper were 9% to 11%
of coremark's and pybench's host time on the M4, 16.6% of pybench's on MBP5.
A gadget does the helper's common case instead. Built, tested and timed on
2026-10-28 on MBP5 (M5 Max).

## The change

emkey1/qemu `tcti-lookup` e8de46aece, on tctiSH `tctish-edition` 5835f7c1cd
(`lookup.patch`; 8 files, 231 lines). Not offered to tctiSH yet.

- `include/tcg/lookup-key.h`: where the TB state comes from, as data. The
  target says how its `get_tb_cpu_state()` makes flags and pc in its common
  case (x86, in `tcg_x86_init()`: 64-bit code only, hflags ORed with
  eflags' IOPL, TF, RF, VM and AC; pc from eip; cs_base 0). accel/tcg fills
  in the CPUState fields that `curr_cflags()` and `check_for_breakpoints()`
  read, beside `helper_lookup_tb_ptr()`, with build checks on the jump
  cache's shape (2^14 entries of 16 bytes after an rcu_head).
- `lookup_tb`, a TCTI gadget: checks one_insn_per_tb, the log bits that
  want each TB, single-stepping and breakpoints; makes flags, pc and cflags
  from env; hashes pc as `tb_jmp_cache_hash_func()` does and probes both
  ways of the jump cache as `tb_lookup()` does (pc, cs_base 0, flags,
  cflags). On a hit it sets can_do_io and returns the TB's code in x0, as
  the helper would; anything else calls the helper as before.
- `tcg_out_call()` emits it for `helper_lookup_tb_ptr()` under 4 KiB guest
  pages, and drops the R0 = env it no longer needs.

Only x86 sets the key, so only x86 guests get the gadget (other targets
leave pc_ofs 0 and keep the call), and only 64-bit code takes its fast
path; other modes call the helper from it.

Tests, as `ci-check-tcg.sh` runs RCG: rcg-insns matches TCG's reference
with rcg on, off and `tcti-ordered=off`; rcg-faults has 0 of 27684 checks
failed with rcg on and off. The build has no warnings; checkpatch has no
errors (one MAINTAINERS warning, for the new header).

## Timing

`timing.txt`: three rounds, the four columns alternating, `--wait-quiet 2`,
medians by wall clock, disk d9f049e41fd2. All 15 checks matched.

| Column | QEMU | rcg |
|---|---|---|
| l-teoff | `tctish-edition` 5835f7c1cd | off |
| l-lkoff | `tcti-lookup` e8de46aece | off |
| l-te | `tctish-edition` 5835f7c1cd | on |
| l-lk | `tcti-lookup` e8de46aece | on |

Geometric means over the 17 workloads (Blender's render time, xonsh's
median key latency), with `../whole/geo.py`:

- **RCG + the gadget against RCG: 0.979, 2.1% faster.** From code_reuse
  0.878 and xz 0.918 (both noisy: ±7% and ±10%) to sha256sum 1.010:
  pybench 0.963, node_compute 0.965, sympy 0.986, coremark 0.994.
- **TCTI + the gadget against TCTI: 0.997, level** (code_reuse 0.954 to
  xonsh_keys 1.029, within each column's noise).
- RCG against TCTI: 0.654 (1.53x faster); RCG + the gadget 0.640 (1.56x).

## Profiles

`profiles.txt` (`../whole/profsum.py`, which now counts `lookup_tb` as a TB
exit): pybench, one run each, vCPU threads' own samples.

| | helper + call_env0 | lookup_tb | run (s) |
|---|---|---|---|
| RCG | 12.5% + 4.1% | | 10.40 |
| RCG + the gadget | 0.0% + 0.1% | 11.7% | 10.02 |
| TCTI | 4.0% + 1.9% | | 19.95 |
| TCTI + the gadget | 0.0% + 0.0% | 3.9% | 20.30 |

So it is taken under both. The gadget saves about the same time per lookup
either way (about 0.4 s of pybench), which is 3.7% of RCG's pybench and
half that of TCTI's, where it is within the noise.

## Why the gain is modest

The gadget is still 11.7% of RCG's pybench: most of the helper's cost was
never the C call but the jump cache itself. Its 2^14 entries of 16 bytes are
256 KiB, larger than the core's L1, so the probe misses in L1 whichever
code does it. Beyond this, a smaller or per-TB cache (a TB remembering its
last indirect target, checked before the jump cache) would be the next
step, and would change accel/tcg, not just TCTI.

## What it is for

For tctiSH, an option at their word: 2% by geomean under RCG, more on
branchy workloads (pybench, node), nothing on loop code. If offered, the
commit's two long lines wrap, and its "15% to 17%" (MBP5) becomes the M4's
12% to 14% or both are given.

One cost to fix first: qemu-system-i386 sets the key too, but never runs
64-bit code, so there (and in 32-bit code under x86-64) every lookup pays
the gadget's checks before the helper call. Setting the key only for
TARGET_X86_64 removes it from qemu-system-i386; 32-bit code under x86-64
would want its own mode in the key.
