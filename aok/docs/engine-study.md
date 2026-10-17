# AOK's CPU engine inside UTM SE: speed race and plug-in study

Status: **the RISC-V plug-in is built and working (2026-10-11); see section
8.** Sections 1 to 7 are the study that led to it, as written before any of
it existed. It answered two questions that came out of a Discord suggestion to
run a real Linux kernel:

1. Is AOK's gadget engine enough faster than the engine UTM SE ships to be
   worth putting inside UTM SE?
2. If so, where does it plug into QEMU, and what exactly would it have to
   provide?

The goal behind both: boot unmodified Linux, FreeDOS and old Windows on an
iPad or iPhone, at better than UTM SE speed, and offer the work to UTM as a
pull request rather than ship a competing app.

## Summary

- **AOK's engine is much faster than the one UTM SE ships.** For identical
  programs on the same machine, UTM SE's engine needs **7.8x the CPU cycles
  on an arm64 guest and 6.5x on a riscv64 guest** (geometric mean of six
  workloads; range 3.1x to 14.5x). The ratio is the same on the Mac's fastest
  cores and on its mid-tier cores.
- **It is still about 3x ahead of the best version of that engine.** An
  active fork, `tctiSH/qemu` (QEMU 11.1), has made UTM SE's engine about 2.4x
  faster. Against it AOK leads by **3.3x on arm64 and 2.8x on riscv64**
  (range 1.6x to 4.5x). That fork, not UTM's QEMU 10, is the base to build
  on: UTM plans to move to QEMU 11.1 (section 1, "The moving target").
- **AOK is within about 1.5x of QEMU's real JIT** on the same workloads, and
  ahead of it on floating point. The JIT is what UTM uses where Apple allows
  code generation; an App Store app cannot.
- **A full VM still pays for an emulated kernel.** Whatever the engine,
  syscall-heavy work will be slower in a VM than in AOK today, where the
  kernel is native code.

- **The plug-in now exists for RISC-V guests, and delivers most of that
  lead** (section 8). Inside QEMU it needs 1.5x to 2.9x fewer host cycles
  than the tctiSH fork's engine on the same six workloads, and 2.9x to 7.2x
  fewer than UTM SE as shipped, with program output and floating-point
  results identical to QEMU's own. On iPads it measures the same: 2.0x the
  fork's engine on an M4 (the six workloads in 9.8 s instead of 20.5 s) and
  1.8x on an A10X (31 s instead of 58 s).

- **Plug-in point: a second block generator inside QEMU's existing engine,
  not a new accelerator.** UTM SE's engine and AOK's use the same dispatch
  scheme, down to the host register that holds the stream pointer. A block
  AOK generates can live in QEMU's translation cache beside the blocks QEMU
  generates, be entered and left the same way, and call QEMU's own C helpers
  for everything privileged. AOK would not have to implement kernel mode, the
  MMU, interrupts or any device.
- **Every block AOK declines falls back to QEMU's own translator.** That makes
  the work incremental: day one it handles nothing and UTM SE behaves exactly
  as it does today; each instruction class added afterwards makes it faster.
- **x86 guests (FreeDOS, Windows) keep QEMU's engine** until someone ports
  AOK's x86 gadgets the same way. They lose nothing in the meantime.
- **The shipped engine has a defect the fork has already fixed**: in QEMU 10
  it makes a C call for every guest memory access, because its inline fast
  path only covers table offsets that current QEMU no longer uses (section 2).
  Nothing to contribute there.
- **UTM accepts AI-assisted pull requests**, under rules listed in section 5.

## 1. Speed race

### Rig

| | |
|---|---|
| Host | MBP5.local, Apple M5 Max (6 Super + 12 Performance cores), macOS 26 |
| AOK | `build/ish` CLI at `54f2b227`, `debugoptimized` (-O2), default settings (HLE off) |
| UTM SE's engine | UTM's QEMU 10.0.12 (`utmapp/qemu` release tarball), `--enable-tcg-threaded-interpreter` -- the flag UTM's `build_dependencies.sh` uses for its `ios-tci` platform. QEMU's configure calls it "TCTI (TCG with threaded-dispatch bytecode interpreter, experimental and slow; but faster than TCI)" |
| QEMU's JIT | the same source configured without that flag. Not available to App Store apps; here as the ceiling |
| Guests | arm64 (`-M virt -cpu cortex-a72`, UTM's default) and riscv64 (`-M virt -cpu rv64`), one CPU, 2 GB |
| Kernel under QEMU | Alpine 3.24's stock `linux-virt` / `linux-lts` 6.18.55, unmodified |
| Userland | one Alpine 3.24.2 tree per architecture, built once. AOK runs it as a fakefs root; QEMU boots the *same files* as an initramfs. Every program on both sides is byte-identical |

Workloads, each a single process: CoreMark (4000 iterations), a
double-precision n-body simulation (2M steps), a pure-Python mix, `xz -3` of
2 MB of text, busybox `sha256sum` of 16 MB, and a busybox `awk` word count
over 1 MB.

### Method, and why it is not wall-clock time

The first attempt timed each workload from inside the guest. On this Mac the
same AOK binary on the same input then varied **3x** between runs minutes
apart: the machine was also running a local LLM and throttling, and macOS
moved the benchmark between the Super cores at 4.3 GHz and the mid-tier cores
at about 1.4 GHz. Ratios taken that way were wrong by up to 3x per row,
because the two engines being compared had run in different states.

So the figures below are **host CPU cycles**, with host instructions beside
them. A small wrapper (`cycwrap`) starts the engine, watches its output, and
reads the process's cycle and instruction counters (`proc_pid_rusage`) when the
guest prints a start marker and again when it prints the result line. Nothing
is subtracted: a QEMU guest's boot happens before the first marker. Cycles do
not move with clock speed or with time-slicing. They do move with the core
class a run lands on (AOK's CoreMark costs 4.0 G cycles on a Super core and
4.7 G on a mid-tier one), so the wrapper also records what share of each
sample's instructions ran on the Super cores, and samples are sorted into
"Super" (at least 90%), "mid-tier" (at most 10%) and discarded (16 of 216
straddled the two). Six rounds were run, strictly one process at a time,
while the machine moved between the two states on its own.

### Results

Billions of host CPU cycles to finish the same work; lower is better. "UTM SE
needs" is UTM SE's engine divided by AOK. The last column repeats that ratio
for samples that ran on the mid-tier cores while the machine was throttled.

**arm64 guest**

| Workload | AOK | UTM SE's engine | QEMU's JIT | UTM SE needs | AOK vs JIT | UTM SE needs (mid-tier cores) |
|---|--:|--:|--:|--:|--:|--:|
| CoreMark | 4.0 | 20.2 | 1.6 | 5.1x | 2.4x | 5.4x |
| n-body (floating point) | 2.7 | 24.5 | 4.7 | 9.1x | 0.6x | 7.8x |
| Python | 7.0 | 90.9 | 5.2 | 13.0x | 1.4x | 13.1x |
| xz | 3.6 | 28.9 | 2.7 | 8.1x | 1.3x | 8.5x |
| sha256sum | 2.5 | 8.2 | 0.7 | 3.3x | 3.6x | 3.9x |
| awk | 2.5 | 35.9 | 2.0 | 14.6x | 1.2x | 17.1x |
| Geometric mean | | | | **7.9x** | 1.5x | 8.2x |

**riscv64 guest**

| Workload | AOK | UTM SE's engine | QEMU's JIT | UTM SE needs | AOK vs JIT | UTM SE needs (mid-tier cores) |
|---|--:|--:|--:|--:|--:|--:|
| CoreMark | 4.6 | 21.4 | 2.6 | 4.6x | 1.8x | 4.9x |
| n-body (floating point) | 3.2 | 22.5 | 5.1 | 7.1x | 0.6x | 6.4x |
| Python | 8.6 | 92.2 | 5.9 | 10.8x | 1.5x | 10.4x |
| xz | 4.3 | 21.7 | 2.9 | 5.0x | 1.5x | 5.6x |
| sha256sum | 3.1 | 9.6 | 1.0 | 3.2x | 3.2x | 2.9x |
| awk | 2.8 | 36.5 | 2.6 | 13.1x | 1.1x | 15.1x |
| Geometric mean | | | | **6.5x** | 1.4x | 6.6x |

In seconds on the fastest cores at 4.3 GHz, arm64 guest (AOK / UTM SE's
engine / QEMU's JIT): CoreMark 0.93 / 5.0 / 0.38; n-body 0.63 / 6.1 / 1.10;
Python 1.62 / 26.1 / 1.20; xz 0.82 / 6.7 / 0.63; sha256sum 0.57 / 1.9 / 0.16;
awk 0.57 / 8.4 / 0.48.

Each cell is the median of one to four samples in that machine state (most
have two or three); within a state, repeat samples agree to a few percent.
Counting host *instructions* instead of cycles gives smaller ratios, 2.2x to
8.6x, because UTM SE's engine also runs fewer instructions per cycle than AOK
(for Python on arm64, 2.1 against 3.9).

### The moving target: the tctiSH fork

UTM's tracker (utmapp/UTM#7930, opened 2026-09-30) points at
`github.com/tctiSH/qemu`, "a fork of QEMU that plays host to the TCTI
pseudo-JIT": QEMU 11.1.2 with dozens of recent commits to this engine. Among
them are fused gadgets for loading and storing guest state, a memory fast
path for every privilege level, in-stream indirect jumps (`goto_ptr`), a
larger block-lookup cache, and host floating point for x86 guests. Its author
offered it to UTM; UTM's maintainer answered that QEMU 11.1 is planned for
UTM 5.1 and he will revisit the engine then. He is also considering a
WebAssembly backend.

The same race against that fork (`ded0cff`, built the same way), fastest
cores, billions of host cycles:

**arm64 guest**

| Workload | AOK | tctiSH fork | UTM SE today | fork needs | UTM SE today needs | fork vs UTM SE today |
|---|--:|--:|--:|--:|--:|--:|
| CoreMark | 4.0 | 10.7 | 20.2 | 2.7x | 5.1x | 1.9x faster |
| n-body (floating point) | 2.7 | 10.5 | 24.5 | 3.9x | 9.0x | 2.3x faster |
| Python | 7.1 | 32.0 | 90.9 | 4.5x | 12.8x | 2.8x faster |
| xz | 3.6 | 11.0 | 28.9 | 3.1x | 8.1x | 2.6x faster |
| sha256sum | 2.5 | 4.5 | 8.2 | 1.8x | 3.3x | 1.8x faster |
| awk | 2.5 | 11.0 | 35.9 | 4.4x | 14.5x | 3.3x faster |
| Geometric mean | | | | **3.3x** | 7.8x | 2.4x faster |

**riscv64 guest**

| Workload | AOK | tctiSH fork | UTM SE today | fork needs | UTM SE today needs | fork vs UTM SE today |
|---|--:|--:|--:|--:|--:|--:|
| CoreMark | 4.6 | 11.8 | 21.4 | 2.6x | 4.6x | 1.8x faster |
| n-body (floating point) | 3.2 | 10.1 | 22.5 | 3.2x | 7.1x | 2.2x faster |
| Python | 8.6 | 33.4 | 92.2 | 3.9x | 10.8x | 2.8x faster |
| xz | 4.4 | 9.5 | 21.7 | 2.2x | 5.0x | 2.3x faster |
| sha256sum | 3.1 | 5.0 | 9.6 | 1.6x | 3.1x | 1.9x faster |
| awk | 2.8 | 11.4 | 36.5 | 4.1x | 13.1x | 3.2x faster |
| Geometric mean | | | | **2.8x** | 6.5x | 2.3x faster |

All of these samples ran on the Super cores at about 4.3 GHz (three per
cell for the fork, five or six for AOK). The fork is improving week by week,
so this gap may narrow further; the part it cannot remove without changing
design is one dispatch per intermediate operation.

### Reading the numbers

- **The lead is largest where code is branchy and touches memory** (Python,
  awk, xz) and smallest on long runs of register arithmetic (sha256sum).
  Section 2 explains why.
- **AOK beats QEMU's JIT on floating point** because AOK runs guest FP on the
  host's FP unit and QEMU computes it in software.
- **awk is partly a kernel measurement.** Under QEMU it spends a large share
  of its time inside the guest kernel (41% under the JIT in an early run),
  serving memory-allocation syscalls. Under AOK the same syscalls are native
  C and took 0.5%.
- **These are AOK's numbers as a user-mode emulator with its own kernel.**
  Inside QEMU the same gadgets would use QEMU's software TLB and run the
  guest kernel too. The per-instruction cost should carry over; it has not
  been measured.

### What this does not measure

- **AOK in kernel mode.** AOK has none today. Under QEMU the guest kernel's own
  instructions run through the engine, so syscall-heavy and page-fault-heavy
  work pays for them; under AOK they are native C. `awk` is the one workload
  here where that shows.
- **An iPad or iPhone**, in this race. The plug-in has since been measured
  on one against the fork's engine (section 8, "On an iPad"), and the ratio
  did carry over. UTM SE as shipped and AOK's own app have not been raced
  on a device.
- **x86 guests.** UTM SE's engine does more work per x86 instruction (flags,
  segments) than per arm64 or RISC-V instruction; AOK's x86 engines were not
  raced.
- **Devices.** Disk, network and display emulation are QEMU's either way.

## 2. How UTM SE runs guest code

UTM is an Apache-2.0 front end around QEMU. It builds QEMU 10.0.12 from
`utmapp/qemu` plus one patch that touches display, virtual-GPU and hypervisor
code, not the CPU engine.
On iOS without JIT ("UTM SE", platform `ios-tci`) it configures QEMU with
`--enable-tcg-threaded-interpreter`, which selects the back end in
`tcg/aarch64-tcti/` (about 4,800 lines; not in mainline QEMU).

QEMU's engine (TCG) works in two halves:

1. A per-guest **front end** (`target/riscv`, `target/arm`, `target/i386`)
   turns a block of guest instructions into QEMU's intermediate operations.
   This is also where all the kernel-mode behaviour lives: privilege checks,
   control registers, page-table walks, exceptions. It is large: about 34,000
   lines for RISC-V and 88,000 for ARM.
2. A per-host **back end** turns those operations into something runnable.
   Normally that is machine code. TCTI instead emits a stream of *addresses of
   precompiled gadgets*, one per operation, each gadget ending in "load the
   next address, jump to it".

That is the same scheme as AOK's JIT, at a different granularity: TCTI
dispatches once per intermediate operation, AOK once per guest instruction.
Facts from the source that matter for plugging in:

| | UTM SE's engine (TCTI) | AOK |
|---|---|---|
| Dispatch | `ldr x27, [x28], #8; br x27` | the same, `_ip` is `x28` |
| Guest CPU state | pointer in `x14` | pointer in `x1` (`_cpu`) |
| Guest registers | cached in host `x0`-`x15` within a block, written back at block ends and before C calls | read and written in the state structure by each gadget |
| Guest memory | inline lookup in QEMU's software TLB (`addr_read`, `addr_write`, `addend`), C helper on a miss | inline lookup in AOK's TLB (`page`, `page_if_writable`, `data_minus_addr`), C on a miss |
| Direct branches | a slot in the stream, patched when the target block exists | chained blocks |
| Indirect branches, returns | **leave the stream and go back through QEMU's C main loop** to find the next block (TCTI has no `goto_ptr`) | a target cache looked up inside the gadget (`jit/guest-arm64/control.S`) |
| Floating point | QEMU's software float library through C helpers | host FP instructions |
| Gadget count | one per operation *per register combination*: the binary is 320 MB | one per instruction form |

A profile of UTM SE's engine running the Python workload (`sample`, 8 s,
arm64 and riscv64 guests alike) puts its active time at roughly:

| Share | Where |
|--:|---|
| 64% | ordinary gadgets, a large part of them loading and storing guest registers and constants |
| 23% | guest memory access through the **slow path**: a C call per load or store |
| 10% | returning to QEMU's main loop to find the next block |
| 3% | other |

The memory figure is a defect rather than a design cost. TCTI has inline
TLB-lookup gadgets only for five fixed offsets of the TLB table (-32, -48,
-64, -96, -128 from the CPU state; `LOOKUP_SPECIAL_CASE_LDST_GADGET` in
`tcg-target.c.inc`), which matched common privilege levels in older QEMU.
In QEMU 10 every guest has 16 slots, the ones arm64 and riscv64 guests use
fall outside those five, and every access takes the `_slowpath_` gadget and a
C helper. No fast-path memory gadget appeared in either profile.

## 3. Where AOK's engine could plug in

### A. As a QEMU accelerator (`-accel aok`): not recommended

This is the interface KVM and Apple's Hypervisor.framework use
(`include/system/accel-ops.h`: create and kick CPU threads, synchronise
register state, deliver interrupts). It is small, but it assumes the
accelerator *is* a complete CPU. Hardware virtualisation gets kernel mode from
the real processor. AOK would have to supply it: control registers, the
page-table walker, exception entry and return, timers, for every guest
architecture. QEMU already has all of that, but inside its own engine, where
an accelerator cannot reach it. The existing glue gives the scale of what
would be left to write even *with* a CPU that does kernel mode itself:
`target/arm/hvf/hvf.c` is 2,557 lines and `target/riscv/kvm/kvm-cpu.c` 2,178,
and device code carries a few dozen `kvm_enabled()` special cases that a new
accelerator would have to add to.

### B. As a second block generator inside QEMU's engine: recommended

QEMU builds a block in `setjmp_gen_code()` (`accel/tcg/translate-all.c`): the
guest's front end produces intermediate operations, then `tcg_gen_code()` runs
the back end. The hook goes in front of that pair: offer the block to AOK's
generator first; if it returns a stream, use it; if it declines, carry on as
today. The block is the same `TranslationBlock` either way, in the same cache,
entered through the same `tcg_qemu_tb_exec()`.

What that buys:

- **No kernel mode to write.** Privileged and rare instructions are calls to
  the C helpers QEMU already has (`helper_csrrw`, `helper_sret`, `helper_wfi`,
  about 1,180 helper declarations for RISC-V), or simply a declined block.
- **No MMU to write.** Gadgets look addresses up in QEMU's software TLB and
  call QEMU's miss helpers, which walk the guest's page tables, raise faults,
  reach devices and catch writes to translated code.
- **No interrupt or device work.** Unchanged.
- **Incremental and safe to ship half-done.** Anything unhandled is a declined
  block.
- **A contained diff**: a few dozen lines in `accel/tcg`, a new directory for
  the generator and its gadgets.

What it costs: AOK's gadgets and decoder for that guest have to be retargeted
to QEMU's data structures (section 4), and the result is tied to QEMU
internals that change between QEMU releases. UTM pins its QEMU version
(10.0.12 today), so the rebase comes when UTM moves.

### C. Improving TCTI in place

Some of AOK's advantage can be had with no new front end at all, by fixing
the worst costs in TCTI itself (the slow-path memory access above, and the trip back to the main loop on every indirect branch). The tctiSH fork has done exactly this, and
more, and got about 2.4x (section 1). It helps every guest, x86 included.
What remains is the roughly 3x that comes from the design itself: dispatching
per intermediate operation rather than per guest instruction.

## 4. What AOK's engine would have to provide (option B)

The generator is called with the guest CPU state, the block's start address,
and the block's flags. It must produce the following, or decline.

| # | Requirement | Where QEMU defines it | AOK today |
|---|---|---|---|
| 1 | **A gadget stream in QEMU's code buffer**, entered with the state pointer in `x14` and the stream pointer in `x28` | `tcg_qemu_tb_exec()` in `tcg/aarch64-tcti/tcg-target.c.inc` | Same dispatch; needs an entry gadget that moves `x14` to `_cpu`, and gadgets built against QEMU's state layout |
| 2 | **Guest state at QEMU's offsets**: `CPURISCVState.gpr[]`, `fpr[]`, `pc`, vector registers; `CPUARMState` for arm64 | `target/*/cpu.h` | Offsets come from `jit/offsets.c`; regenerate against QEMU's structures |
| 3 | **Memory access through QEMU's software TLB**, per privilege level (`mmu_idx` is fixed per block); on a miss call `helper_ld*_mmu` / `helper_st*_mmu` | `include/exec/tlb-common.h`, `accel/tcg/cputlb.c` | Two macros per guest (`load_gadget`, `store_gadget` in `jit/guest-riscv64/memory.S`); the entry layouts are near-identical |
| 4 | **Honour the block's flags or decline**: privilege level, FP and vector enable state, address width, and so on | `TB_FLAGS` in `target/riscv/cpu.h` (22 fields); `TBFLAG_A64` in `target/arm/cpu.h` (37 fields) | New. AOK's generators assume user mode with everything enabled. Start by declining any block whose flags are not the plain case |
| 5 | **Check for a pending exit at block entry** (`icount_decr`), returning `TB_EXIT_REQUESTED` | `accel/tcg/translator.c` | AOK has an equivalent poke check; different field |
| 6 | **Leave the block the way QEMU expects**: return `block pointer | exit index`; direct jumps through `jmp_target_addr[]` slots that QEMU patches and resets | `tb_target_set_jmp_target()`, `tcg_out_goto_tb()` | Replaces AOK's own chaining for these blocks |
| 7 | **Indirect branches**: at minimum exit to the main loop, as TCTI does; better, an in-gadget lookup against QEMU's per-CPU jump cache | `tb_lookup()` in `accel/tcg/cpu-exec.c`, `tb-jmp-cache.h` | AOK's return and indirect-target cache has to be re-pointed at QEMU's |
| 8 | **Precise state when a helper faults**: per-instruction records (`gen_insn_data`, `gen_insn_end_off`) so QEMU can recover the guest PC from a stream position | `encode_search()`, `cpu_restore_state()` | New bookkeeping in the generator; TCTI shows the mechanism (`tcti_call_return_address`) |
| 9 | **Read guest code through QEMU** so a block that crosses a page is tracked and writes to it invalidate the block | `translator_ld*`, `tb_set_page_addr1()` | Replaces AOK's own self-modifying-code tracking for these blocks |
| 10 | **Floating-point state QEMU can read**: rounding mode and accrued exception flags live in QEMU's `float_status`; they must be written back before any helper or control-register read can see them | `target/riscv/fpu_helper.c`, `target/arm/vfp_helper.c` | AOK runs guest FP on the host FPU (`emu/fpenv.c`); needs a sync at block boundaries. The most error-prone item on this list |
| 11 | **Decline when QEMU needs its own translation**: single-stepping, breakpoints, instruction counting, record/replay, plugins | `cflags` | New, trivial |
| 12 | **Thread safety**: one host thread per guest CPU, one shared cache, generation under QEMU's lock | `accel/tcg/tcg-accel-ops-mttcg.c` | AOK's generator is per-process; needs no shared mutable state of its own |

Reused from QEMU without change: every device, firmware and BIOS, disk
formats, networking, display, the monitor, snapshots, the whole of UTM's
front end and VM format, and kernel-mode CPU behaviour for every guest.

Size of what would be ported, for scale: AOK's riscv64 gadgets are about
16,300 lines of assembly and its arm64 gadgets about 12,100, plus the
per-guest decoders in `jit/gen.c`.

## 5. Offering it upstream

- **Target.** Build on `tctiSH/qemu` (QEMU 11.1), not on UTM's QEMU 10: it is
  the QEMU version UTM is moving to, the engine there is the one a fallback
  block should run on, and its author is actively taking engine work. TCTI is
  not in mainline QEMU, so mainline is not a target. To survive whichever
  back end UTM ends up with, AOK's generator should not emit TCTI's stream
  format: it should enter and leave its own blocks itself and depend only on
  QEMU's generic engine code (`accel/tcg`), which mainline maintains.
- **UTM's rules for AI-assisted contributions** (`CONTRIBUTING.md`): one
  well-defined feature or fix per pull request; a human must test the change
  before the PR is opened; no unrelated files touched; an
  `Assisted-by: AGENT:MODEL` tag rather than `Co-authored-by`; and their
  `/utm-review` and `/utm-submit` skills where the tool supports them.
- **Size.** "One well-defined feature" argues for a sequence: first the hook
  with a generator that declines everything, then one guest's integer core,
  then memory, branches, FP, vectors. Each is testable on its own because of
  the fallback.
- **Licence.** QEMU is GPLv2 (most files "or later"). AOK's riscv64 guest
  engine is entirely this fork's own commits, so it can be offered under
  whatever QEMU needs; `LICENSE.md` already names QEMU as a reason for the
  GPLv2 grant. Shared files with upstream iSH history need a per-file check
  before anything is copied. **The arm64 engine is not all ours**
  (corrected 2026-10-13): `docs/CREDITS-aarch64.md` lists what was adapted
  from OpenMinis/ish-arm64, a GPLv3 fork of iSH -- `gadgets.h`, `math.S`,
  `control.S`, and the SIMD files `simd_arith.S`, `simd_misc.S`,
  `simd_shift.S` and `crypto.S`, with much of their decoding in `jit/gen.c`.
  None of that has been copied into the QEMU fork, and none should be
  without that project's word on GPLv2. What is there from the arm64 engine
  is `frag.h` and `alu_spec.S`, which are this fork's own (section 11).
- **Mainline QEMU** is a separate matter and not needed for this: TCTI itself
  is not there.

## 6. Risks and unknowns

- **Not yet measured on a device**, nor with AOK's gadgets actually running
  against QEMU's TLB and state layout. The projection assumes the cost per
  instruction carries over.
- **Kernel-heavy work stays slow relative to AOK today**, because the kernel
  is emulated in any full VM. This is a property of the product, not of the
  engine.
- **Floating-point state** (item 10) is where a subtle wrong-result bug would
  hide. QEMU's own test suites for the guest are the oracle.
- **Maintenance against QEMU.** The generator depends on internals
  (`TranslationBlock`, the TLB entry layout, helper signatures). A QEMU version
  bump in UTM means a rebase.
- **Binary size.** TCTI is already 320 MB per QEMU binary; AOK's gadgets add
  megabytes, not hundreds.
- **Whether UTM wants it.** Not asked yet.

## 7. Next steps

1. ~~Build option B for riscv64 on the tctiSH fork.~~ Done: section 8.
2. **Talk to the fork's author and UTM's maintainer.** There is now a result
   to show and a published branch to point at. On hold: the project owner's
   call, and no one has been contacted.
3. ~~Measure on an iPad.~~ Done for the plug-in against the fork's engine, on
   an M4 iPad Pro and an A10X one: section 8.
4. Re-run this race when either engine changes: `aok/`.

## 8. The RISC-V plug-in

Built on `tctiSH/qemu` at `ded0cff` (QEMU 11.1.2), as the branch
`aok-gadgets` of `~/git/qemu-aok`: five commits, 8 new files of about 2,900
lines, and 200 lines added to 13 existing QEMU files (4 lines changed).
Published at <https://github.com/emkey1/qemu> (branch `aok-gadgets`), a fork
of `tctiSH/qemu`. No pull request has been opened.
Its own documentation is `docs/devel/aok-gadgets.rst` in that tree.

It is option B of section 3, with one difference from section 4's sketch:
AOK's blocks do **not** use TCTI's stream format or entry point. They have
their own (`aok_tb_exec`), so the plug-in depends only on QEMU's generic
engine code and works whichever back end UTM ends up with.

### What it does

- Translates RV64 integer code (base, M, A, Zba, Zbb, Zbs, Zicond, C), loads
  and stores, branches and jumps, CSR accesses, and F and D floating point.
  Everything else ends the block and is QEMU's: `ecall`, `sret`, vectors.
- 99.8% of the blocks in a boot and workload run are AOK's.
- Double-precision arithmetic runs on the host's FP unit where that gives
  QEMU's software-float answer exactly, flags included, and calls software
  float where it might not.

### Results

Host CPU cycles on the M5's Super cores, RV64 guest, one CPU, lower is
better. "Plug-in" is AOK's gadgets inside QEMU; "tctiSH" is the same QEMU
binary with them switched off (`QEMU_AOK=0`); the three were run interleaved.

| Workload | AOK CLI | Plug-in | tctiSH fork | UTM SE today | Plug-in vs fork | Plug-in vs UTM SE today |
|---|--:|--:|--:|--:|--:|--:|
| CoreMark | 4.2 | 6.8 | 11.7 | 21.4 | 1.7x | 3.2x |
| n-body (floating point) | 3.1 | 3.4 | 10.1 | 22.5 | 2.9x | 6.5x |
| Python | 7.8 | 13.0 | 34.1 | 92.2 | 2.6x | 7.1x |
| xz | 4.4 | 5.8 | 9.7 | 21.7 | 1.7x | 3.8x |
| sha256sum | 2.8 | 3.4 | 5.2 | 9.6 | 1.5x | 2.9x |
| awk | 2.4 | 5.1 | 12.2 | 36.5 | 2.4x | 7.2x |
| Geometric mean | | | | | **2.1x** | **4.7x** |

A whole guest boot and shutdown, which is mostly kernel code: 11.6 G cycles
on the fork's engine, 6.0 G with the plug-in.

The plug-in is still about 1.5x behind AOK's own CLI (1.1x to 2.1x). What
separates them is mostly what AOK's generator does beyond one gadget per
instruction (fused pairs, cached register runs), which had not been carried
over when this was measured (section 10 carries over the pairs of integer
gadgets), and for awk the emulated kernel.

### On an iPad

The same QEMU, cross-built for iOS as a shared library with tctiSH's
dependency recipe, inside a small benchmark app (`aok/ios-app`)
that boots the same kernel and userland and reads its own process's cycle
counters at the same guest marker lines. One QEMU binary, gadgets on or off
at launch (`QEMU_AOK`), three rounds interleaved.

iPad Pro 13" (M4, iPad16,4), iPadOS 27.0, thermal state nominal throughout,
every instruction on the performance cores, so seconds mean something here:

| Workload | Plug-in G cycles | Fork G cycles | Plug-in s | Fork s | Plug-in vs fork |
|---|--:|--:|--:|--:|--:|
| CoreMark | 6.8 | 11.9 | 1.56 | 2.75 | 1.8x |
| n-body (floating point) | 3.8 | 10.2 | 0.90 | 2.47 | 2.7x |
| Python | 16.1 | 38.4 | 3.73 | 8.87 | 2.4x |
| xz | 5.9 | 9.2 | 1.38 | 2.16 | 1.6x |
| sha256sum | 3.4 | 5.2 | 0.82 | 1.23 | 1.5x |
| awk | 6.1 | 12.7 | 1.42 | 3.00 | 2.1x |
| Geometric mean | | | | | **2.0x** |

All six together: 9.8 s with the plug-in, 20.5 s without. The ratios are the
Mac's to within a tenth, which is what two engines with the same dispatch
scheme on the same kind of core should give. Python and awk cost about 20%
more cycles on the M4 than on the M5 under both engines.

iPad Pro 12.9" (A10X, iPad7,2), iPadOS 17.7, the oldest core this is likely
to meet, thermal state nominal throughout:

| Workload | Plug-in G cycles | Fork G cycles | Plug-in s | Fork s | Plug-in vs fork |
|---|--:|--:|--:|--:|--:|
| CoreMark | 10.3 | 15.9 | 4.20 | 6.49 | 1.5x |
| n-body (floating point) | 7.0 | 15.6 | 2.83 | 6.36 | 2.2x |
| Python | 29.8 | 58.1 | 12.18 | 23.76 | 2.0x |
| xz | 11.2 | 18.9 | 4.59 | 7.71 | 1.7x |
| sha256sum | 6.3 | 7.8 | 2.55 | 3.21 | 1.3x |
| awk | 12.1 | 25.5 | 4.96 | 10.42 | 2.1x |
| Geometric mean | | | | | **1.8x** |

All six together: 31.3 s with the plug-in, 57.9 s without. The lead is a
little smaller than on the M4. The host instruction counts are the same on
both devices (the plug-in runs fewer, except for sha256sum, where the two
engines run the same number); what differs is how much faster the plug-in's
instructions go than the fork's: 1.4x the instructions per cycle on the M4
for CoreMark, 1.2x here. Why the older core gains less has not been looked
into.

On both devices the program transcript and the floating-point transcript
(139 lines) are identical with the gadgets on and off, identical between the
two devices, and the program transcript is identical to the Mac's reference.

Not measured on a device: UTM SE as shipped, and AOK's own app on the same
userland.

### How it was checked

The reference is QEMU's own engine in the same binary. Three guest-side
tests, each compared between the two:

- **Program transcript** (`bench/check.sh`): CoreMark's checksums, Python
  big-integer and float arithmetic, xz and gzip, four hashes, sort, awk,
  shell loops, and a hash of every binary in the image. Identical with one
  guest CPU and with four.
- **Floating-point transcript** (`bench/fptest.c`): each double-precision
  operation over 67 awkward operands in all four rounding modes, hashing
  every result's bits with the exception flags it raised. Identical on all
  120 lines. Its first run found a real defect in the first version of the
  FP gadgets (6 lines differed): a product equal to the smallest normal can
  have been rounded up from a tiny value, and then RISC-V raises underflow
  and AArch64's flag cannot be used to tell.
- **Stress**: four transcripts at once on a four-CPU guest, all four equal
  to the reference.

### Bugs worth remembering

- **QEMU 11.1 stores its per-mode TLB tables in reverse order**
  (`tlb.f[mmuidx_to_fast_index()]`). Probing `tlb.f[mmu_idx]` found some
  other mode's table: every access missed and took the slow path. Correct
  output, four times slower than the engine being replaced.
- **`GETPC()` is a variable under TCTI.** A helper called from a gadget saw
  the position of the last helper call some *other* block had made, and when
  it raised an exception QEMU unwound the CPU to that unrelated block.
  OpenSBI probes for CSRs by trapping, so the firmware hung with the wrong
  hart id.
- Both of these produced a system that booted and gave right answers, or
  hung, rather than one that quietly computed wrong results.

### Not done

- GL-accelerated displays in the UTM build (section 9).
- x86 guests. (arm64: section 11.)
- Single-precision FP natively, and `ecall`/`sret` without leaving the stream.
- AOK's fused pairs with a load, a store or a branch in them, and its cached
  register runs (section 10 has the pairs of integer gadgets).
- QEMU's own TCG test suites for RISC-V have not been run against it.

## 9. Inside UTM SE

UTM's iOS front end (the "iOS-SE" scheme, UTM 5.0.6 at `7eadb056`) built
around this QEMU, installed on the M4 and the A10X iPad Pro as its own app
(`app.ish.aok.UTM-SE`, beside any UTM SE from the App Store).

### What was built

- **UTM itself is unmodified.** Its source at that commit, its own prebuilt
  dependencies (the `Sysroot-ios-tci-arm64` artifact of its CI), its own
  QEMU 10.0.12 for every guest architecture but one.
- **RISC-V guests get the plug-in's QEMU** (11.1.2, tctiSH fork, AOK gadgets
  on by default), built against UTM's dependencies with UTM's flags and put
  in the sysroot in place of UTM's `qemu-riscv64-softmmu.framework`, with
  the RISC-V firmware (OpenSBI, EDK2) of the same QEMU.
- **Two small additions to that QEMU**, on a branch of their own (`utm-se`
  in `~/git/qemu-aok`, local), because UTM's front end assumes UTM's QEMU
  fork: the `virtio-ramfb` display device it gives every "virt" machine
  (ported from the fork), and building against the spice-server 0.14.3 UTM
  ships while accepting the `gl=off` UTM always passes.

### What was checked

- On the M4 iPad, by hand: a machine made the way UTM's wizard makes them
  (UEFI, virtio-ramfb display, USB input, sound, network) reaches the
  firmware's shell on the display, and a direct-boot Alpine guest runs the
  six workloads and gives a shell on UTM's terminal. UTM's debug log shows
  its ordinary argument list accepted, with only deprecation and socket
  warnings from QEMU.
- In the iOS simulator, driven from here: the same guest with its console on
  the display (the guest's virtio-gpu driver on virtio-ramfb), an address by
  DHCP from QEMU's user network, and keyboard input.
- **The gadgets are on inside UTM.** The same VM in the same app, launched
  with `QEMU_AOK=0` in the app's environment, is slower on every workload
  (1.4x to 2.4x on a busy laptop's simulator, which is not a measurement).
- Typing into the guest's display console at 20 and at 50 keys a second
  through QEMU's monitor arrives intact with the gadgets on and off.

### Limits

- **GL: OpenGL only so far.** See "The accelerated display" below.
- Not measured against UTM SE as shipped on a device. `install-engines.sh
  stock` puts UTM's own RISC-V QEMU back for that.
- UTM for iOS has no way to start a VM from outside, so every device check
  needs a tap.
- UTM at this commit builds only with the released Xcode 27.

### The accelerated display

UTM's GL display on iOS is not in QEMU: it is changes in UTM's QEMU fork
(10.0), about 3,000 lines over some 30 files. EGL comes from ANGLE rather
than a GBM device, a scanout goes to UTM's SPICE client as an IOSurface
rather than a dmabuf, and virglrenderer renders on Metal. Without them a
machine with a `-gl` display card does not start, and that is the card UTM
suggests.

The display half is now carried to the plug-in's QEMU 11, on a third branch
(`utm-gl`, local):

- `ui/console.c`, `ui/egl-helpers.c`, the shaders and the `include/ui`
  headers by a three-way merge of the fork's changes onto QEMU 11's files.
- `ui/spice-display.c` could not be merged that way. QEMU 11 rewrote its GL
  half around multi-plane dmabufs and remote clients, which do not exist
  without GBM. The GL section therefore exists twice: QEMU 11's own where
  there is GBM, the fork's IOSurface code where there is not.
- `hw/display` keeps QEMU 11's own virgl code. UTM's front end asks for
  Vulkan (`venus`), Direct3D (`neptune`) and blob resources by default; the
  device at first accepted those options on Apple hosts and ran with OpenGL
  only (see "Vulkan" below for why that was not needed).

Checked in the iOS simulator inside UTM SE, with the arguments UTM passes by
default: virglrenderer comes up on ANGLE's Metal renderer, the guest's
kernel reports `+virgl` with two capability sets, and its virtio-gpu console
is drawn through the GL path. That build is the one on both iPads now, with
a fourth machine (`AOK RISC-V Display GL`).

**A guest program on the host's GPU needs a guest that can ask for it.**
Alpine's RISC-V Mesa (26.1.6) is built without the virgl driver: its loader
says `virtio_gpu: driver missing` and falls back to llvmpipe, so
`bench/gltest.sh` there draws its cube in software (and reports exactly
that), whatever QEMU does.

### Devuan

So the machine to judge by is Devuan 6 "Excalibur", whose RISC-V port is
official and whose Mesa (25.0.7) has virgl. `app/build-devuan-disk.sh` makes
it: a 6 GB disk with Devuan's own kernel (6.12), sysvinit, network by DHCP
and Mesa, built by running debootstrap natively inside the Alpine RISC-V
guest on the build Mac's stock QEMU, with the packages fetched on the host
over many connections (the mirrors gave one connection 85 kB/s).
`utm/make-vm.py` wraps it as `Devuan RISC-V.utm`: direct kernel boot, the
disk on virtio-blk, the GL display device, four CPUs.

- Under the plug-in's QEMU on the Mac (gadgets on): Devuan's kernel boots,
  mounts the disk, sysvinit brings the system up, root is logged in on the
  serial port, and it shuts down cleanly.
- In the iOS simulator inside UTM SE: the boot is on the display, the
  network has its address, and `gltest` says **renderer: "virgl"**, OpenGL
  ES 3.0, Mesa 25.0.7. A guest program is rendering on the host's GPU
  through this QEMU. (Devuan's kmscube ran its frames and exited without an
  error; no frame of it was captured.)

**And none of those frames was shown.** That last parenthesis was the gap.
The first real use of the GL device, the desktop below started on an M4
iPad, was a black screen with a cursor that moved, and the simulator showed
why: the compositor drew every frame with GLES2 (its own screenshot had the
terminal window) and none reached UTM's screen, with atomic modesetting or
legacy, on a still desktop or one whose terminal printed four times a
second. kmscube was black too. What did reach the screen went through a
dumb buffer: the text console, and a compositor drawing in software.

The cause was in the port. UTM's virglrenderer, drawing on Metal through
ANGLE, names a resource's Metal texture in a field that is a union with the
Direct3D one, and says which it is in another. QEMU 11's
`virgl_cmd_set_scanout()`, which the port had kept, knows only Direct3D, so
the display code was handed a Metal texture labelled as something it has no
path for, turned its Metal scanout off, and blitted the resource's GL
texture id: right for a resource the guest only uploads to, empty for one a
guest context renders into. `524b5e9` on `utm-gl` takes the type into
account, as UTM's fork does.

With it, in the simulator: kmscube's cube is on UTM's screen, labwc
composites with GLES2 and is on the screen, and es2gears turns in a window
on that desktop, drawn by the host's GPU from end to end. The lesson is in
the first paragraph: a renderer string and a frame count are not a picture.

**Vulkan.** I had this wrong for a day, and told the user the VM had no
Vulkan. The paragraph that stood here said Vulkan waited on the fork's work
in `virtio-gpu-virgl.c`, and the port cleared `venus` and `blob` at start.
The user pointed at the "Vulkan Driver" setting in the app. Everything was
already there: the front end passes `venus=true` and names the MoltenVK it
bundles, UTM's virglrenderer is built with venus and runs its render server
as a thread, Devuan's riscv64 Mesa ships `libvulkan_virtio.so`, and the
device code is QEMU's own since 9.2. With the flags left alone the guest saw
the capability set and failed in `vkCreateInstance` for one reason, which
the engine printed once asked to:

    map(fixed) res 4 at offset 0x21000 size 0x100000 failed: Invalid argument

QEMU 11 maps a blob at a fixed address inside one mapping of the whole
host-visible region. The guest allots the region in its 4K pages and an
Apple host's are 16K, so `mmap()` refuses the address. `1983c8d` leaves fixed
mappings out on Darwin (a blob becomes a subregion, as before QEMU 11) and
with them the region's backing, 8G of address space as UTM asks for it.

In the simulator, with that: `vulkaninfo` says "Virtio-GPU Venus (Apple iOS
simulator GPU)", and the GLES2 desktop and es2gears are on the screen as
before. No swapchain can be made there, by vkcube or by vkmark's headless
mode: the host side gives a guest's window-system images linear tiling, and
MoltenVK does not render to linear images in the simulator (`MVK_OS_SIMULATOR`
sets `renderLinearTextures` false; every Apple GPU family has it otherwise).
So a cube on a screen is for an iPad to show.

The iPad's first answer was no device at all: `vkCreateInstance` failed
again, and the VM's log, pulled off the M4, said `proxy: failed to
pre-initialize context`. That is the host side failing to make the shared
memory of a venus context. UTM's virglrenderer makes it with `shm_open()`
under a name inside the app's App Group, because a sandboxed app on a device
may open no other; I had built the app with UTM's free-account settings,
which sign it with no App Group, and the simulator does not enforce the
rule. The app is now signed with UTM's own entitlements (the group, the
increased memory limit, extended virtual addressing; the user's yes was
asked for, since it registers them on the team). Direct3D (`neptune`) does rest
on the fork and is still switched off, as are the fork's own refinements of
the blob and fence code (an unmap that does not hold the queue, fences
retired off the poll timer).

### The "ultimate" machine: AOK's own scripts in a VM

The Devuan machine is provisioned by the scripts an AOK root is provisioned
with, not by copies of them. `provision-ultimate-devuan.sh` and
`-alpine.sh`, `setup-wayland.sh` and `start-wayland.sh` now know a machine
with a kernel of its own (no `/proc/ish`) and leave out or change what only
the app can do there:

- chrony keeps the distribution's configuration and disciplines the clock,
  which under AOK is the device's and is only watched;
- nothing follows the device's timezone, and there are no native programs to
  link;
- `setup-wayland.sh` also installs seatd and puts the logins in its group;
- `start-wayland.sh` puts the desktop on the machine's own display when
  there is a DRM card: the compositor takes the card and the input devices
  through its seat, nothing is headless and no VNC bridge runs. The seeded
  configuration, menu, theme and panel are the ones AOK's Display applet
  shows.

Under AOK every one of them takes the path it took before.

`build-devuan-disk.sh ultimate` puts them in the machine's `/AOK/tools` and
runs them *in the machine*, booted with its own kernel, through a hook in its
`rc.local` (`aokjob=` on the kernel command line), as its owner would. What
comes out (1.3 GB compressed, 1.8 GB used of 6):

- the tool set of the provision script, sshd, cron, rsyslog, chrony;
- a login `aok`, without a password and with sudo, on the display's console;
  root on the serial terminal;
- labwc, foot, waybar, Xwayland and a few desktop programs; `desktop` starts
  them.

`build-devuan-disk.sh desktop-test` boots it with a display nobody watches,
starts the desktop as `aok` and takes a picture through QEMU's monitor: a
foot terminal in AOK's window theme under the panel. On the AOK-gadgets
binary, whose Mac build has no monitor screenshot, the picture was taken in
the guest instead (grim), once with the gadgets and once with QEMU's own
engine: 1280x800, and the two differ in nine rows of the panel, where the
clock and the load figures are. 1.3 million pairs were fused getting there.

The desktop on the GL display device was not run before the image went to
the iPads, and there it was a black screen: the engine's GL scanout (above),
which no desktop had exercised. While that was open `start-wayland.sh`
composited in software there (`e9c583c78`); with the engine fixed, the card
decides (`ca22eab3c`): GLES2 on a virtio-gpu that negotiated virgl, pixman
on one that did not, wlroots' own choice on any other card, and
`desktop soft` for pixman whatever the card. In the simulator, on the fixed
engine, `desktop` says `renderer: gles2` and is on UTM's screen with
es2gears turning in a window, and `desktop soft` says pixman and is on the
screen too. On an iPad it has been seen by nobody yet.

The Alpine guests carry the Alpine script and the Wayland ones as well, to
try: they live in memory, and their Mesa has no virgl driver.

### First use on an iPad, and what it found

The first evening of somebody using the machine on an M4 iPad found these,
none of which a test of mine had, each in a different layer:

- **Nothing drawn with GL was shown** (the engine; "The accelerated
  display" above).
- **The trackpad of the keyboard did nothing** (UTM's front end). UTM asks
  the system for the pointer lock whenever a VM runs and takes movement from
  GCMouse, which reports none without the lock; the VM's log showed mouse
  devices coming and going and not one movement. Finger drags worked, so the
  path into the guest was sound. `utm-frontend.patch` makes the system's own
  pointer position the guest's cursor, with no lock, for any guest that has a
  tablet; capture remains for one that has not, and as a setting. What was
  asked and what the system granted now goes to the VM's log. In the
  simulator the tablet path works end to end on this QEMU (the QMP switch to
  the tablet, a tap landing where it was made); a trackpad itself the
  simulator cannot be given, so that half is the user's to confirm.
- **The machine shut down under its user, twice in twenty minutes** (the
  guest and the front end together). Its own `auth.log`, read off the disk
  pulled from the iPad, has `Power key pressed short. Powering off...` each
  time: UTM passes a keyboard's power key (HID usage 0x66) to the guest, and
  elogind obeys it. Which key of that keyboard it is, is not known. The
  patch stops passing it, and the image tells elogind to ignore it
  (`build-devuan-disk.sh desktop-test` now presses it four times: "4
  pressed, 0 obeyed, and still up").
- **UTM SE crashed whenever a guest powered off** (the engine): three crash
  reports, one stack, a use after free in spice-server's
  `inputs_release_keys` under `qemu_spice_cleanup`. QEMU 11 tears its spice
  server down at exit; UTM's spice-server (0.14.3, which this tree was made
  to build against) cannot remove the keyboard interface QEMU frees first.
  `9d51cf6` leaves a server of that age standing. With it QEMU exits with
  code 0 and UTM SE quits on its own account, as it does after any VM.
- **"I tried starting up dillo, and nothing happens"** -- and nothing else
  in the menu did either, though as root, in a desktop started later, it all
  worked (the engine and the front end together). The front end has two
  pointer devices in the guest, a USB mouse and a USB tablet, and switches
  between them with `mouse_set` as the kind of input changes. A tap that
  caused a switch was pressed on the mouse and released on the tablet: an
  event logger in the guest shows `Mouse BTN_LEFT down` and never an up.
  libinput counts a button per seat, so the compositor dropped every later
  left click from the tablet; submenus still opened, on hover. Proof before
  any fix: the logger wrote a release into the mouse's event device, and the
  entry under the cursor started at once. `d38b069` (ui/input.c) releases the
  buttons a pointer holds when another takes its place, which is right for
  any front end; the patch to UTM's sends the click of such a tap once the
  switch is through, where the finger landed (before, it went to wherever the
  old cursor was, or nowhere). The root desktop "worked" only because a
  compositor that starts later does not learn of a button already down.
  Why a tap straddled a switch so readily came out a day later, from the
  same machine's log: 2783 switches in seven minutes, up to 153 in a
  second. My trackpad patch let the system's pointer position the cursor
  (the tablet) and left UTM's GCMouse handler asking for the relative mouse
  on every movement; on this iPad both report an unlocked pointer. GCMouse
  is now listened to only under the pointer lock.
- **Two faults of the desktop itself**, found on the way. Under a GL
  compositor Xwayland draws with GL too (glamor), and on virgl every glyph of
  an X program came out as a filled black box: `start-wayland.sh` now sets
  `XWAYLAND_NO_GLAMOR` on a virgl card. And an apostrophe in a comment inside
  the single-quoted awk program of `list-apps.sh` (#620) had made the script
  a syntax error, and the Applications menu empty. The script is the one AOK
  itself runs, so that held there too.

What reading the evidence took, for the next time: the VM's `debug.log` and
its disk come off the device with `devicectl device copy from`; crash
reports with `idevicecrashreport -k -f UTM`; and the disk's logs through the
build VM (the image as a read-only second disk, a job that tars `/var/log`).

## 10. One source for both

Until 2026-10-12 the plug-in's integer gadgets were AOK's, copied and
rewritten for the plug-in's registers. Whatever AOK's RISC-V engine gained
afterwards was a port waiting to be done, and its fused pairs (two guest
instructions in one gadget, one dispatch) had never been ported.

Now the plug-in assembles AOK's files. `jit/guest-riscv64/alu.S`, `frag.h`
and `pairs.h` build under a second host unchanged, and the plug-in keeps
copies it does not edit:

- `frag.h` states what a second host supplies ("A second host"): registers
  for the guest state and the stream, how a gadget begins and ends, and which
  of the gadgets the pair list names it has. A shared body may use x0 and
  x9-x15, and does not fault, call out or end a block. What is AOK's alone
  (how a block ends, chains and returns) sits between `RV_GADGET_HOST`
  guards.
- **AOK's own object code is byte for byte what it was.** The change to AOK
  is guards and a comment.
- `tools/check-shared-gadgets.sh` assembles the three files as a stand-in
  host with different registers and fails on a body that needs `gadgets.h`,
  refers to a symbol outside itself, or touches a register outside the
  contract. Run it after changing them. All three failures were planted and
  caught.
- In the plug-in's tree, `scripts/aok-gadgets-sync.sh` copies the files from
  an AOK checkout, records the commit, and works out which gadgets the
  plug-in has from the assembled object. `--check` says whether the copies
  are current. The plug-in's hand copies are deleted (909 lines of gadgets
  to 570).
- The stream pass that fuses pairs is ported as `aok_gen_pair` in the
  plug-in's generic code. It is a second copy of `jit_pair_fuse`
  (`jit/gen.c`), not shared source yet.

So a change to an integer gadget, or a pair added to `pairs.h`, reaches UTM
by running one script.

### What came with it

118 of AOK's 332 pairs: the ones made of two integer gadgets. In a boot and
workload run 48,800 pairs were fused, 19,400 of them handing the first's
result to the second in a host register, out of 698,000 translated
instructions.

Host cycles on the M5 (all on Super cores), three interleaved runs each,
without the pairs (`QEMU_AOK_NO_PAIRS=1`) and with them:

| Workload | Without | With pairs | Ratio |
|---|---|---|---|
| CoreMark | 6.60 G | 6.37 G | 1.036 |
| n-body | 3.40 G | 3.39 G | 1.000 |
| Python | 13.18 G | 12.20 G | 1.080 |
| xz -3 | 5.52 G | 5.28 G | 1.046 |
| sha256sum | 3.35 G | 3.22 G | 1.039 |
| awk | 5.26 G | 4.96 G | 1.062 |

Geometric mean 1.044. On AOK itself shorter gadgets have not always been
faster on the iPads, so the M4 iPad had its own run: the benchmark app
(section 8) with the new engine, four interleaved rounds, the guest's own
milliseconds, median:

| Workload | Without | With pairs | Ratio |
|---|---|---|---|
| CoreMark | 1708 | 1630 | 1.048 |
| n-body | 942 | 934 | 1.009 |
| Python | 3958 | 3714 | 1.066 |
| xz -3 | 1433 | 1393 | 1.029 |
| sha256sum | 852 | 810 | 1.052 |
| awk | 1390 | 1336 | 1.040 |

Geometric mean 1.040, thermal state nominal throughout. (Read the guest's
times from the WL lines, not the host's: the host cuts workloads apart where
it sees their lines on the serial port, and three of 48 samples were cut in
the wrong place.) The A10X has the same build installed and has not been
timed: it was locked.

The program and FP transcripts are identical to QEMU's own engine with the
pairs, with forwarding off, and with four guest CPUs.

### Loads, stores and branches

The other 214 pairs contain a load, a store or a branch, and those bodies
named AOK's registers, its TLB macros and its block chaining. Since
`7db3de6cd` they reach guest memory and leave a block through names the host
supplies, and the plug-in (`bea9939`) supplies them:

- **Memory.** A load or store body computes the address and makes the access
  itself. Between the two the host turns a guest address into a host one
  (`read_prep`, `write_prep`): AOK's TLB probe and miss handlers, or QEMU's
  memory fast path. On a miss in the plug-in QEMU does the whole access in C,
  and the body's own access is made of a scratch word, where a load finds
  what C read.
- **Ways out.** A branch body names its two ways out by parameter words it
  does not read, and `branch_leave` takes one: AOK's tagged chain word, or
  QEMU's linked-jump slot. The plug-in's is a copy per way out, as AOK's is,
  so each ends in an indirect branch of its own; that alone was 1.7% of the
  cycles (xz 4.8%).
- **`jalr`** stays each host's own, since it ends in that host's block
  lookup, but the plug-in writes its own as a body under AOK's name
  (`jalr_cached`) and takes the pairs that end in it.
- AOK's `alu.o`, `memory.o` and `core.o` are byte for byte what they were.
  The check script now stands in for a host with a memory model and a way
  out of its own: 137 gadgets and 326 pairs assemble under it, and four
  planted violations were caught.

All 332 pairs are built in the plug-in. In a boot and the six workloads
220,000 pairs are fused out of 697,000 translated instructions (it was
49,000), 66,000 of them forwarding a register.

Host cycles on the M5, all on Super cores, five interleaved runs each of the
same build without pairs, with them, and QEMU's own engine in that build:

| Workload | Without | With pairs | Ratio | Fork's engine | AOK gadgets faster by |
|---|---|---|---|---|---|
| CoreMark | 6.72 G | 6.23 G | 1.080 | 11.62 G | 1.87x |
| n-body | 3.37 G | 3.25 G | 1.035 | 9.99 G | 3.07x |
| Python | 12.92 G | 11.80 G | 1.095 | 32.96 G | 2.79x |
| xz -3 | 5.58 G | 4.88 G | 1.144 | 8.33 G | 1.71x |
| sha256sum | 3.36 G | 3.09 G | 1.087 | 5.01 G | 1.62x |
| awk | 5.02 G | 4.65 G | 1.080 | 11.35 G | 2.44x |

Geometric mean 1.086 from the pairs, and 2.18x the fork's engine.

On the M4 iPad (the benchmark app of section 8, seven interleaved rounds,
the guest's own milliseconds, median, thermal state nominal throughout):

| Workload | Without | With pairs | Ratio |
|---|---|---|---|
| CoreMark | 1664 | 1523 | 1.093 |
| n-body | 927 | 899 | 1.031 |
| Python | 3760 | 3238 | 1.161 |
| xz -3 | 1439 | 1267 | 1.136 |
| sha256sum | 849 | 769 | 1.104 |
| awk | 1349 | 1203 | 1.121 |

Geometric mean 1.107, and its program, FP and memory transcripts are the
Mac's, line for line. The A10X has the build and no figures or transcript
yet: its run was cut short when another app was brought to the front. With
the integer pairs alone it had gained more than the M4 did (1.072 against
1.040, three rounds).

A new transcript guards this: `memtest` (aok/bench), every access
size, signed and unsigned, at every alignment and across a page boundary,
and pointer walks over pages that fault on first touch and are restarted by a
signal handler that hashes each fault's address and pc. A pair that repeated
its first instruction after a fault in its second, or reported the wrong
instruction, changes it. It is identical to QEMU's own engine with pairs,
without, with forwarding off and with four CPUs, as the program and FP
transcripts are. (Flipping one bit of what the plug-in's slow path returns
does not get as far as the test: the kernel does not boot.)

### What is not shared yet

- **The fusing pass**: `aok_gen_pair` in the plug-in is a second copy of
  `jit_pair_fuse` (`jit/gen.c`). Queued in `docs/TODO.md`.
- **The idioms AOK's translator folds into one gadget** before the pair pass
  sees them: a shift pair (`sll_srl`, `sll_sra`), a shift and an add
  (`sll_add`), a constant or a bit test and the branch on it (`beq_ri`,
  `andi_beqz` and their kin), an add and the load through its result. The
  gadgets are assembled in the plug-in; its translator does not select them,
  so the pairs that name them never occur there, and the pair list was
  measured on streams that have them.
- **Constants that are code addresses.** QEMU's blocks are position
  independent, so `auipc` is the plug-in's own gadget rather than AOK's
  `mov_const`, and pairs that begin with it are not taken.
- **Cached register runs** need host registers the plug-in uses for QEMU's
  bookkeeping.
- One thing got slower: with pairs off, CoreMark costs 2.5% more on the
  shared load, store and branch bodies than it did on the plug-in's
  hand-written ones (the other five workloads: within 1%). Not understood
  yet. With pairs on, the finished build is about 2% ahead of the previous
  one (integer pairs only) on CoreMark and 5% to 8% on the other five
  (medians of separate runs).

## 11. The AArch64 plug-in

Added 2026-10-13, in the same fork (`emkey1/qemu`, branch `aok-gadgets`,
`target/arm/tcg/aok`; `docs/devel/aok-gadgets.rst` there has the design).
The guest here is the host's own architecture, which is what AOK's arm64
engine was built on: an instruction is most often the same instruction with
its registers read from the CPU state and written back.

### What it does

| Part | How |
|------|-----|
| Integer, conditional selects and compares | AOK's operand-specialised gadgets (`jit/guest-arm64/alu_spec.S`), assembled in the fork unchanged, plus the fork's own for what AOK does with run-time decoding |
| Loads, stores, pairs (X and W) | AOK's bodies (`jit/guest-arm64/frag.h`) with QEMU's softmmu fast path in place of AOK's TLB; the slow path is one call into QEMU's cputlb, which may raise |
| Branches | direct ones linked as TCG links them; indirect ones through QEMU's per-CPU jump cache, probed in the gadget |
| System registers, exclusives, `svc`, `eret`, DAIF | one call to C each, with the helpers QEMU's own code calls; `mrs xt, sp_el0` (a kernel's "current") and plain fields are moves |
| Floating point and SIMD | the instruction itself: every encoding of the class is assembled in the fork on fixed registers, as a two-instruction thunk, and a gadget loads the registers, calls the thunk and stores the result. The host's FPCR is the guest's while they run |

The FP and SIMD part is the fork's own and shares nothing with AOK: AOK's
SIMD gadget files are the ones ported from OpenMinis/ish-arm64 (GPLv3; see
"Licence" in section 5), and they decode register numbers at run time
anyway. A thunk table needs no list of mnemonics, only the shape of the
encoding space, so what the translator decides is which encodings exist for
the guest's CPU (the base architecture's tables; half-precision arithmetic
and every later extension stay QEMU's).

### Results

An Alpine arm64 guest (`-M virt -cpu cortex-a72`, UTM's default CPU), one
CPU, on an Apple M5, in host CPU cycles, against the same binary with the
plug-in off (QEMU's threaded interpreter), two runs each, the boot
subtracted from the workloads:

| Workload | QEMU's engine | AOK gadgets | Ratio |
|----------|--------------:|------------:|------:|
| Boot to the test script | 12.10 G | 4.75 G | 2.5 |
| CoreMark | 10.61 G | 4.19 G | 2.5 |
| n-body (doubles) | 10.74 G | 3.12 G | 3.4 |
| Python | 31.18 G | 9.83 G | 3.2 |
| xz -3 | 9.96 G | 4.37 G | 2.3 |
| sha256sum | 4.17 G | 1.95 G | 2.1 |
| awk | 10.59 G | 4.12 G | 2.6 |

99.9% of the guest's translated blocks are gadget streams, and QEMU's main
loop enters its own engine's code 3,700 times in a boot and the check
programs (44 million times before FP and SIMD were added). No fused pairs
yet: this is one gadget an instruction.

### How it was checked

The same way as RISC-V (section 8), against the same binary with the plug-in
off: the check programs, the FP test, the memory test (now with B, H, S, D
and Q registers and pairs of them, in each addressing mode, across page
boundaries and over faulting pages), with one guest CPU and with four, and
with `-cpu max`.

And one new program, `aok/bench/simdtest.c`: all 560,640
encodings of the scalar FP and Advanced SIMD data-processing space on fixed
registers, each run on four sets of inputs (one under round-to-zero with
flush-to-zero and default NaN), the result, the flags and FPSR hashed, and a
SIGILL hashed as that. It checks both which instructions a guest CPU has and
what each computes. Against stock QEMU 11.0.3 with its JIT backend the
transcript is identical.

### Bugs worth remembering

- **QEMU's threaded interpreter computes three SIMD instructions wrongly**,
  in the fork's base and so presumably in UTM SE: `cmlt #0` and `cmle #0` on
  8-, 16- and 32-bit lanes, and `sshl` on 16- and 32-bit lanes. simdtest
  found it as 18 encodings where the plug-in and the reference differed; the
  plug-in, QEMU's JIT backend and the hardware (the same guest under HVF)
  agree with each other. Not reported: it waits with everything else for
  the maintainers (`docs/TODO.md`).
- `sev` and `sevl` were NOPs in the first version. This QEMU models the
  event register a `wfe` waits for, so the kernel's `sevl; wfe`
  (`smp_cond_load_relaxed`, the spinlock slow path) went to sleep on an
  event that had not been set, and a guest with four CPUs hung in one boot
  out of three while bringing them up. One CPU never showed it.
- An `ARMCPRegInfo` belongs to one CPU and a translated block to all of
  them: a register's descriptor found at translation must not be kept in
  the stream. QEMU's own code looks it up again at run time, and so does
  the plug-in now.

### On an iPad, and in UTM SE

The on-device test app (`aok/ios-app`, a label that begins
`aarch64`) ran the gates on the M4 iPad, 2026-10-13: the check, FP and
memory transcripts are identical to the Mac's reference, simdtest to stock
QEMU's JIT, and the four-CPU stress hashes to the Mac's. The six workloads
there, in the guest's own milliseconds, QEMU's engine against the gadgets:

| Workload | QEMU's engine | AOK gadgets | Ratio |
|----------|--------------:|------------:|------:|
| CoreMark | 2,614 | 1,058 | 2.5 |
| n-body | 2,527 | 904 | 2.8 |
| Python | 8,974 | 2,798 | 3.2 |
| xz -3 | 3,282 | 1,167 | 2.8 |
| sha256sum | 1,174 | 529 | 2.2 |
| awk | 3,031 | 1,101 | 2.8 |

UTM SE (section 9) is now built with both engines: `build-engines.sh` and
`install-engines.sh` build and install the riscv64 and the aarch64
library, and the rest of the pipeline takes `ARCH=aarch64`:
`update-roots.sh` makes the arm64 guest with its kernel's modules,
`build-devuan-disk.sh` builds Devuan arm64 in it (on the Mac's own CPU, so
the whole "ultimate" machine takes ten minutes where RISC-V's takes over an
hour), and `make-vm.py` writes "AOK ARM64 Console.utm" and "Devuan Ultimate
ARM64.utm". UTM starts an arm64 machine as `-cpu cortex-a72 -machine
virt,virtualization=on,gic-version=3`: EL2 present and a GIC of system
registers, neither of which the first gates had. They pass with those
options too.

In the simulator the Devuan machine boots through UTM's front end in about a
minute and `desktop` brings up labwc, waybar and foot on the GL display
(`aok/a64/pictures/devuan-arm64-desktop-sim.png`). Both iPads
have the app and the two machines; on a device the machines have not been
started yet, which takes a tap.

On that desktop the main loop still entered QEMU's code a third as often as
streams (6.4 million times in a boot and three minutes of desktop), almost
all of it for `ld1`/`st1`, which the check programs hardly use. Those, the
other structure loads and stores and `ldpsw` were added the same day
(qemu-aok 734639c): in a boot and the check,
FP and memory programs QEMU's code is now entered about a hundred times. The
M4 passes the gates with that engine too, and both iPads' UTM SE have it.

### Not done

- The LSE atomics (not on a cortex-a72).
- Fused pairs (AOK's arm64 pair list, `jit/guest-arm64/pairs.h`).
- A CPU newer than the base: with `-cpu max` the guest is correct but
  hardly faster, because pointer authentication, BTI's indirect branches,
  LSE and LSE2 are all left to QEMU.
- The A10X: it has the app and the machines, and has run nothing of this.

## 12. The x86 plug-in

Added 2026-10-13/14, in the same fork (`target/i386/tcg/aok`, commits
6ddec90 to 05421d9). The user's aim for it is a PC guest on an iPad, down to
Windows XP, so it translates two kinds of code with one translator: long
mode's 64-bit code, and 32-bit protected-mode code with flat segments and a
32-bit stack, which is what a 32-bit system and its programs run in. Real
mode, 16-bit segments and virtual-8086 mode stay QEMU's: they are a
firmware's and a boot loader's.

Nothing in it is AOK's. AOK's own x86 gadgets are built around its register
cache and its flags; these are written against QEMU's `CPUX86State`, and
the fork's `docs/devel/aok-gadgets.rst` has the design. The two things worth
knowing here:

- **The flags are QEMU's lazy ones.** A gadget that sets flags stores
  `cc_dst`, `cc_src` and `cc_op` as QEMU's own code would, so an exception,
  an interrupt or one of QEMU's blocks finds them right. It computes with
  the host's flag-setting instruction, and the translator tracks what the
  host's NZCV then says of the guest's flags: a `jcc` after a `cmp` tests
  the host's and reads nothing.
- **A 32-bit guest runs on the x86-64 engine.** The gadgets' operands are
  offsets into a CPU state whose registers are 64 bits wide, which the i386
  build's are not, so there is no front end there. For the VM app the
  x86-64 engine is installed a second time under the i386 name: a 32-bit
  system finds a CPU that could do more than it asks of it, as on any PC
  made since 2004.

### Results

All four guests the engine has a front end for, the six workloads, one
guest CPU, on an Apple M5, in host CPU cycles between a workload's first
line and its last (`aok/cyc4.sh`, the least of three
interleaved runs), against the same binary with the plug-in off
(`QEMU_AOK=0`: QEMU's threaded interpreter, which is what UTM SE ships):

| Workload | RISC-V | | ARM64 | | x86-64 | | x86 32-bit | |
|----------|-------:|--:|------:|--:|-------:|--:|-----------:|--:|
| CoreMark | 11.92 → 6.12 | 1.9 | 10.72 → 4.26 | 2.5 | 11.26 → 4.72 | 2.4 | 13.28 → 5.23 | 2.5 |
| n-body (doubles) | 10.10 → 3.26 | 3.1 | 10.93 → 3.08 | 3.6 | 9.22 → 5.19 | 1.8 | 10.62 → 5.38 | 2.0 |
| Python | 33.32 → 10.40 | 3.2 | 31.62 → 9.78 | 3.2 | 31.02 → 9.31 | 3.3 | 49.05 → 14.18 | 3.5 |
| xz -3 | 8.45 → 4.69 | 1.8 | 9.84 → 4.37 | 2.3 | 9.38 → 4.63 | 2.0 | 17.63 → 7.65 | 2.3 |
| sha256sum | 4.95 → 3.09 | 1.6 | 4.35 → 1.97 | 2.2 | 3.94 → 2.37 | 1.7 | 7.68 → 3.27 | 2.4 |
| awk | 11.82 → 4.63 | 2.6 | 10.73 → 4.23 | 2.5 | 32.69 → 13.35 | 2.5 | 16.64 → 7.18 | 2.3 |

(Billions of cycles, QEMU's engine → the gadgets, and how many times fewer.
The guests are Alpine 3.24's own builds of the same programs, so columns
compare engines and not architectures: awk is busybox's on three of them.)

Doubles in SSE run on the host's FP unit only where it gives softfloat's
answer and flags (normal numbers and zeros under a plain MXCSR); single
precision and MMX are still QEMU's helpers.

### The x87

Added the day after, when the user asked why it had not been ported.
iSH-AOK has the x87 as gadgets: the 80-bit arithmetic in integer registers,
the register stack with its tags and faults, every D8-DF form, the
transcendentals correctly rounded, 5,000 lines held to 167,517 answers
recorded on an AMD Ryzen. Three quarters of that was nobody's in particular
and sat between that engine's CPU state and its way to memory. It is the
aok-gadgets repository's `x87/` now (five files, written against a host's
macros; iSH-AOK's object code is byte for byte what it was), and the
engine's side is 300 lines: QEMU keeps TOP beside the status word and a tag
byte a register, where the shared code has TOP in the word and a bit a
register, so four macros convert.

| | QEMU's x87 (softfloat) | The gadgets |
|---|---:|---:|
| Every D8-DF form, 4 rounding x 4 precision modes (122,880 answers) | 40,081 wrong | 0 |
| The same with exceptions unmasked (27,648) | 10,519 wrong | 0 |
| The transcendentals (16,989) | 8,559 wrong | 0 |
| n-body compiled for the x87, 32-bit guest, host cycles | 107 G | 39 G |

"Wrong" is against the hardware: stack faults that QEMU does not raise, the
denormal-operand flag, C1, and `fsin`, `fcos` and `fptan`, which are a
double's there. The gate's transcripts against QEMU's engine did not move,
because ordinary programs stay away from all of that. Both PC guests pass
(`bench=x87kat`).

### How it was checked

Against the same binary with the plug-in off, as the other two: the check
programs, the FP test and the memory test with one CPU, four, and four on
threads of their own (QEMU's multi-threaded mode, which is its default for
an x86 guest here), the FP test printing every result (370,000 lines), all
identical, for the 64-bit guest and the 32-bit one
(`aok/x64/x64gate.sh`).

Two programs are new. `bench/x86test.c` is the integer instructions on
awkward and random operands with the flags hashed in: what Linux's
compilers seldom emit and other systems' code is full of (`rep` with the
direction flag set, `repne scas`, `loop`, `cmpxchg8b`, rotates whose flags
are read, segment registers pushed and loaded, `lahf`/`sahf`, every
condition after every kind of flag-setting instruction with a load or a
store between). And `poke` (`bench/run1.sh`) is not a transcript but a
guest that must stay up: three CPUs busy in the scheduler while the fourth
flips the scheduler's static key three thousand times, which makes Linux
patch its own running code.

### Bugs worth remembering

- **A store into a page with code is invalidated before it is made, and
  nothing held the page in between** (QEMU's own, in `notdirty_write`). A
  block another CPU translates in that gap is made of the old bytes and
  stays valid. Linux patches running code with a breakpoint first and
  counts on no CPU meeting it afterwards; a block with the breakpoint in it
  that outlived the patch was `Oops: int3` at `sched_clock_cpu+0xd`, in 9 of
  180 boots of the 32-bit guest with four CPUs beside other load. QEMU's
  engine seldom loses the race, because its block there begins some
  instructions earlier; the front end ends a block before a breakpoint, so
  the next one begins at the very byte. With the gap made a few microseconds
  wider QEMU's engine died the same way in 5 of 6. Fixed in the store path
  for both engines (qemu-aok 4f86691): the storing CPU leaves its block at
  the block's end and invalidates the range once more. After: `poke` 16 of
  16 (0 of 16 before), the boot 100 of 100. What told them apart was a
  detector, not thought: a line printed whenever a breakpoint was executed
  that memory no longer had, with the block's flags (valid, QEMU's, one
  byte long), and then the same guest under QEMU's engine as the control.
- A gadget that calls C after it has set the host's flags must save them:
  the slow path of a read-modify-write store did not, `lock sub; je` read
  garbage, and the boot died in `__put_cred`.
- QEMU's per-CPU jump cache holds one block per pc, and kernel code is
  entered under two flag sets (the stack segment a system call leaves and
  the one an interrupt leaves). The lookup gadget tried its second slot only
  when the pc differed: 265 million lookups went to C until it also tried it
  on a flags mismatch. One macro for the three front ends now.
- QEMU never links a jump into a block that spans two pages; a hot loop with
  an instruction across a page boundary went through the main loop every
  time round until its jump was pointed at the stream's own lookup.
- **An x86 Linux guest with no entropy source spends a quarter of a minute
  in its scheduler making some** before the first program that asks for
  random numbers runs, under any engine. It looked like "Python is no
  faster". Every x86 machine here has `rdrand` and `random.trust_cpu=on`.
- A test line that read the flags after a call hashed the stack pointer's,
  and stack randomisation gave it one of two values at every start, on
  either engine: it looked like a 32-bit-only difference in the newest
  instructions. Flags are read in the statement that sets them.
- Two compare scripts run at once shared their temporary files and could
  call a difference identical. Each has its own now, and every gate was
  compared again one at a time.
- **The instruction a fault returns to begins a block of another kind**: the
  resume flag is in a block's flags, and the front end left such blocks to
  QEMU. So after any page fault the rest of that block ran in QEMU's code
  once and in a stream every other time, which nothing could see until the
  x87 had two implementations that disagree: one or two of 150,000 known
  answers failed in a run, never the same ones, each with softfloat's
  answer. Found by printing the failing cases beside iSH-AOK's own output of
  the same case; the block now clears the flag in its first gadget.

### On an iPad

The M4, 2026-10-14, in the device test app (`aok/ios-app/x86-device.sh`):
the check, FP, memory and `x86test` transcripts of both PC guests are
identical to the Mac's with the plug-in off, and the six workloads, in host
cycles, QEMU's engine against the gadgets (two rounds, before the x87):

| Workload | x86-64 | | x86 32-bit | |
|----------|-------:|--:|-----------:|--:|
| CoreMark | 11.63 → 5.01 | 2.3 | 15.05 → 5.64 | 2.7 |
| n-body | 9.40 → 5.56 | 1.7 | 11.06 → 5.93 | 1.9 |
| Python | 35.31 → 11.05 | 3.2 | 59.19 → 18.58 | 3.2 |
| xz -3 | 11.84 → 4.89 | 2.4 | 22.12 → 8.56 | 2.6 |
| sha256sum | 4.43 → 2.45 | 1.8 | 8.01 → 3.42 | 2.3 |
| awk | 35.62 → 15.34 | 2.3 | 20.11 → 7.47 | 2.7 |

### In the app

AOK VM is built with the x86-64 engine as its `x86_64` and `i386` QEMU, and
`make-vm.py` makes "AOK x86-64 Console" and "AOK x86 32-bit Console" (the
same Alpine guests, `ARCH=x86_64` and `ARCH=i386`). In the simulator both
boot through UTM's front end and run the six workloads. A PC has no device
tree to say which engine runs it, so with the gadgets on the processor's
name ends in "(AOK gadgets)": `model name` in `/proc/cpuinfo`, and the
processor line of a Windows system's properties.

### Not done

- **Windows XP itself.** No image here; nothing of Windows has run on it.
  What XP adds to what Linux exercises: a BIOS boot through real mode
  (QEMU's), far more 16-bit-operand code, x87 everywhere, `sysenter` and
  `int 2e`, and data and code sharing pages.
- MMX, single-precision SSE on the host, anything with VEX; of the x87,
  `fninit` and the environment forms (`fxsave` and its kin), and the
  last-instruction pointers, which the gadgets do not write.
- The rotates through carry, 16-bit `adc`/`sbb` and stack operations,
  16-bit addressing, string I/O, `cmpxchg16b`.
- A store into the block that is running does not stop that block at the
  store (QEMU's "precise" self-modifying code): an instruction that rewrites
  one further on in its own block still runs the old one once.
- On a device: see `docs/TODO.md`.

## Appendix: reproducing the race

The harness is in `aok/`, exactly as it ran. It expects to be
copied to `~/aok-vm-bench` on a Mac that has an AOK checkout with `build/ish`
and `build/tools/fakefsify`, plus Homebrew's `glib`, `pixman`, `meson` and
`ninja`. Order: `build-qemu.sh`, `setup-roots.sh`, `update-roots.sh`,
`cc -O2 -o cycwrap cycwrap.c`, `race.sh 3 > race.log`, then
`summarize.py race.log`.

| File | Purpose |
|---|---|
| `build-qemu.sh` | downloads UTM's QEMU 10.0.12 and builds it twice (TCTI, JIT) |
| `build-qemu-tctish.sh` | clones and builds the tctiSH fork (engine name `tctish` in `race.sh`) |
| `setup-roots.sh`, `update-roots.sh` | build the per-arch Alpine userland as an AOK root and as an initramfs |
| `bench/` | workload sources and the guest-side scripts |
| `cycwrap.c` | per-workload host cycles, instructions and Super-core share |
| `profile-tcti.sh` | samples UTM SE's engine during one workload |
| `race.sh` | the race: rounds x arch x engine, one process at a time |
| `summarize.py` | the tables above |
| `boot-aok.sh`, `run-aok.sh` | boot the RISC-V guest on the plug-in build (`~/aok-vm-bench/build-aok`), gadgets on or off |
| `bench/check.sh`, `bench/fptest.c` | the program and floating-point transcripts of section 8 |
| `prof-aok.sh` | where the plug-in build's time goes, by category |
| `build-qemu-ios.sh` | cross-builds the plug-in QEMU and its libraries for iOS (tctiSH's recipe; `ios-app/build_dependencies.patch` is what it changes) |
| `ios-app/` | the device benchmark app: `assemble.sh` stages QEMU and the guest and generates the project (XcodeGen), `build.sh` builds and signs, `run-device.sh` launches one run and fetches its results |
| `utm/` | UTM SE with the plug-in (section 9): `build-engines.sh` and `install-engines.sh` build this QEMU against UTM's sysroot and put it there (`AOK_GL=1` for the build with the accelerated display), `build-app.sh` builds and signs UTM, `make-vm.py` writes ready-made virtual machines, `install-app.sh` puts both on a device |
| `bench/init`, `bench/udhcpc.sh` | the guest's init; in the VM image (the race's plus the kernel's modules) it also loads drivers and takes an address |
| `bench/gltest.sh` | in a guest: installs Mesa and runs kmscube, which names the renderer it was given |
| `app/build-devuan-disk.sh`, `app/devuan-provision.sh`, `app/fetch-debs.py` | the Devuan RISC-V disk: built natively in the Alpine guest (its `/init` runs a job from a tar disk with `script=vdb`), packages fetched in parallel on the host |
