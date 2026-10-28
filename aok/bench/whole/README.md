# Structure A's rich ops: a whole-output change, and where the time goes

After inc/dec (tctiSH/qemu#7, `../incdec`) timed level against structure A,
three questions. Does a small change to how TCG handles a rich op pay? Where
does A spend its time, beside TCTI? And what does that say about the other
ways to make it faster? Taken on 2026-10-28 on an M4 Pro Mac mini (m4), as
MBP5 was off the network.

The same day tctiSH replaced `structure-a` with `tctish-edition` 5835f7c1cd,
which already writes a rich op's outputs whole (below), so the change here
is not for upstream, and its timing was stopped after one round. What stands
is the profiles, the coverage and the mixing experiment: A + both is close
to `tctish-edition` with #8 (inc/dec, rebased) on it.

## The change: TCG_RICH_WHOLE

A rich op's outputs were treated as read as well as written: a gadget may
write only part of a register (an 8- or 16-bit write), so the value before
had to be in memory. TCG therefore stored any output a TCG register held
before the gadget ran, and kept alive whatever computed it, even where the
gadget overwrites it whole. The flags state is the large case: structure A
computes ROR's CF and OF in TCG ops after the gadget, and the next
flag-setting gadget's outputs kept that computation, and its store, alive.

`TCG_RICH_WHOLE(i)`, a flag beside `TCG_RICH_MAY_FAULT`, says the gadget
writes all of output i and does not read it. Liveness then marks it dead
before the op rather than dead and in memory, and the register allocator
frees it rather than storing it (unless the op may fault, when every global
must be in memory anyway). The x86 front end sets it for cc_dst and cc_src,
for eip after JMP and RET, and for a register that MOV, LEA, POP, MOVZX,
MOVSX, MOVSXD or the zeroing XOR write at 32 or 64 bits; a gadget that also
reads one of these (`lea (%rbx,%rbx),%rbx`) has it taken away.

`tctish-edition` 5835f7c1cd (dated 2026-10-27) does the same its own way: an
output's value before the op is dead unless it is also an input, and a
gadget that writes part of a register, or reads it, lists it as an input as
well. So upstream has this; ours stays on the branches below for the record.

| Branch (emkey1/qemu) | Base | Commits |
|---|---|---|
| `rcg-whole-a` | tctiSH `structure-a` fed47ac5dd | 62a0939eaf (test), 237ad4afa9 (change) |
| `rcg-whole` | `rcg-incdec` 3cc89a22c1 (#7) | b3d4690569 (test), 2ea183a7ea (change) |

The test, `tests/tcg/x86_64/system/rcg-mix.c`, puts gadgets right after
instructions RCG has none for (IMUL, BSWAP, a shift by CL, STC, ADC), so a
register or the flags state is in a TCG register when the gadget writes,
reads or partly writes it: 33 cases, three multipliers each, compared with
rcg=off. On both branches rcg-insns matches its reference, rcg-faults has 0
failures in 27684 checks, and rcg-mix matches. Each of the change's three
guards (only 32- and 64-bit writes, not with MAY_FAULT, not where the gadget
also reads it) makes rcg-mix fail when taken away.

## What ran

| Column | QEMU | rcg |
|---|---|---|
| TCTI | `structure-a` fed47ac5dd, TCTI | off |
| A | the same binary | on |
| A + inc/dec | `rcg-incdec` 3cc89a22c1 | on |
| A + change | `rcg-whole-a` 237ad4afa9 | on |
| A + both | `rcg-whole` 2ea183a7ea | on |

Configure flags as in `../incdec`. The bench disk was made on the M4 the same
day, so its Alpine edge packages are newer than MBP5's (disk 1f6adbcc2cfc, not
d9f049e41fd2), and the times here are not comparable with `../incdec`'s;
the columns are with one another. tctiSH's `prepare.sh` needed a one-line
local change to build it (`scripts.txt`, at the end).

The timing (three rounds, the five columns alternating) was stopped in its
first round when `tctish-edition` superseded the base. The profiled runs
below are one each, slowed a little by `sample` alike:

| Seconds | TCTI | A | A + both |
|---|---|---|---|
| coremark | 14.43 | 14.52 | 13.49 |
| sha256sum | 13.01 | 13.55 | 12.06 |
| pybench | 25.98 | 13.40 | 14.09 |

## Where the time goes

`sample`, 8 s inside each workload (from 2 s after bench.py's boot time:
20.6 s under TCTI, 10.8 s under A), the vCPU threads' samples by the
function they were in (`profsum.py`; `profiles.txt` has the top functions
and gadgets):

| Share of vCPU time | TCTI | A | A + both |
|---|---|---|---|
| **pybench** (A about 2x faster than TCTI) | env load/store 51%, arithmetic 20%, guest memory 13%, branches and TB exits 12% | gadgets 69%, C 14% (`helper_lookup_tb_ptr` 11%), TB exits 9% | gadgets 60%, C 24% (lookup 9%, TLB misses 7%: the window caught start-up) |
| **sha256sum** (A level with TCTI) | arithmetic 54% (`ext32u` alone 21%), env load/store 34% | gadgets 83%; ROR's dead flags about 11% (TCG ops, env stores, `helper_cc_compute_all`) | gadgets 93%; the dead flags gone |
| **coremark** (A level with TCTI) | env load/store 40%, arithmetic 27%, branches 19%, guest memory 7% | gadgets 65%, TB exits 12%, C 10% (lookup 10%) | the same as A |

- **Where A wins**: pybench is interpreter code, its TBs a few instructions
  long. TCTI spends half its time loading guest registers from env and
  storing them back (`_gadget_st` alone 21%), each store a gadget dispatch of
  its own. A's gadgets do the same loads and stores inside the one dispatch.
- **Where it doesn't**: sha256sum's and coremark's loops are long TBs whose
  values TCTI keeps in host registers. A gives each instruction its own
  gadget, loading and storing through env: on sha256sum, MOV between two
  registers alone is 18% of A's time, where TCG's would be a register copy.
  It comes out about even.
- TCTI is not slow at guest memory: its fused `qemu_ld`/`qemu_st` gadgets are
  6% to 13%. Its cost is dispatches, of env traffic and of 32-bit results'
  zero extension (`ext32u`, 21% of sha256sum).
- The change shows on sha256sum as its profile says it should: the ROR flag
  work that no reader needed is gone (single runs while profiled: A 13.55 s,
  A + both 12.06 s).

## Coverage is not the limit

`coverage.txt` (`coverage.py`, from M0's counts in `../m0/counts`): the
instruction families A has gadgets for are 90% to 98% of the instructions
of every workload but Blender and nbody (34% and 70% vector), coremark
(95.9%) and sha256sum (97.4%) included. In most, inc and dec are the largest
families it lacks, 0.4% to 3.4% (which is why #7 could buy little); imul is
2.2% of coremark and under 1% elsewhere; then bt and nop. More gadgets of
the kind #7 adds cannot move the two workloads where A is level.

## Mixing gadgets and TCG ops costs

`rcg-exp.diff`, an experiment on `rcg-whole-a`, never for upstream:
`RCG_EXP=mem` gives gadgets only to instructions that access guest memory,
leaving register-only ones to TCG; `RCG_EXP=nocond` gives none to Jcc,
SETcc and CMOVcc. One round each against A + change (`exp.txt`):

| | coremark | sha256sum | pybench | awk_words |
|---|---|---|---|---|
| mem | 1.01x | 1.04x | **1.31x slower** | **1.18x slower** |
| nocond | 0.99x | 0.95x | **1.26x slower** | 1.03x |

Taking gadgets away makes it slower, not faster, even for register-only
instructions. Under A each change between a gadget and TCG's ops costs
stores and loads of the registers they share; a register-only gadget pays
for itself by keeping a run of instructions inside gadgets. So the choice is
per run of instructions, not per instruction, and neither direction is the
tweak.

## Options this points to

1. **Outputs written whole** (this change): `tctish-edition` has it. On
   sha256sum it takes away about a tenth of A's time.
2. **Pair gadgets**: one gadget for a common pair of instructions, so the
   pair takes one dispatch and one set of env loads and stores. On
   sha256sum a MOV between registers is 18% of A's time; with the operation
   after it, it would cost little of its own. Which pairs are worth it wants
   counting first. It would come from rcg-gen.py and the front end looking
   one instruction ahead, without changing the rich op.
3. **An inline TB lookup**: `helper_lookup_tb_ptr`, the C lookup of the
   next TB where it cannot be chained (RET, indirect calls and jumps), is 9%
   to 11% of A's time on coremark and pybench. A gadget that probes the
   jump cache first and calls the helper only on a miss would help TCTI
   too.
4. **For TCTI itself**: fused 32-bit operations that zero-extend their
   result, as the 21% of sha256sum in `ext32u` suggests.
