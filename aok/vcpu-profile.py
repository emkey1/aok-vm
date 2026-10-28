#!/usr/bin/env python3
# vcpu-profile.py SAMPLE.txt [N]: the vCPU thread ("CPU 0/TCG") of a macOS `sample` file of QEMU, its self time
# by category (the nearest ancestor that names one: translation, code invalidation, device I/O, the gadgets, TCTI,
# the main loop...) and the N heaviest self-time symbols. __psynch_cvwait is the vCPU idle (halted).
import re, sys, collections
CATS = [  # first match from the leaf upward wins
    ("translate", re.compile(r"^(tb_gen_code|setjmp_gen_code|gen_intermediate_code|x86_aok_translate_code|tcg_gen_code)$")),
    ("invalidate (SMC)", re.compile(r"^(tb_invalidate_phys|tb_invalidate|page_collection|notdirty_write|tb_phys_invalidate)")),
    ("TLB fill", re.compile(r"^(tlb_fill|x86_cpu_tlb_fill|tlb_set_page|mmu_translate|get_physical_address|cputlb)")),
    ("device I/O", re.compile(r"^(memory_region_dispatch|address_space_rw|address_space_.*_cached|cpu_inb|cpu_outb|cpu_inw|cpu_outw|cpu_inl|cpu_outl|helper_in|helper_out|ide_|vga_|portio|pci_)")),
    ("interrupt/exception", re.compile(r"^(x86_cpu_exec_interrupt|do_interrupt|raise_interrupt|cpu_handle_interrupt|cpu_handle_exception|helper_raise)")),
    ("TCG helpers", re.compile(r"^helper_")),
    ("AOK gadgets", re.compile(r"^aok_gadget_")),
    # an assembly label, the jump-cache probe of ret, indirect call and jmp, and lookup: not C
    ("AOK jump-cache probe", re.compile(r"^aok_x86_lookup_pc$")),
    ("AOK C", re.compile(r"^aok_")),
    ("TCTI (TCG code)", re.compile(r"^gadget_")),
    ("main loop", re.compile(r"^(cpu_exec|cpu_tb_exec|tb_lookup|tb_htable_lookup|tb_find|cpu_exec_loop|cpu_loop_exit|tcg_cpu_exec)")),
]
lines = open(sys.argv[1], errors="replace").read().split("\n")
pat = re.compile(r"^([\s+!:|]*?)(\d+) (\S.*?)\s+\(in ([^)]+)\)")
start = next(i for i, l in enumerate(lines) if "CPU 0/TCG" in l)
base = len(lines[start]) - len(lines[start].lstrip())
nodes = []  # (depth, count, sym)
for l in lines[start + 1:]:
    m = pat.match(l)
    if not m:
        if re.match(r"^\s*\d+ Thread_", l) or l.startswith("Total number"):
            break
        continue
    nodes.append((len(m.group(1)), int(m.group(2)), m.group(3).split(" ")[0]))
total = int(re.search(r"(\d+) Thread", lines[start]).group(1))
selfc = collections.Counter(); cat = collections.Counter(); stack = []
for i, (d, n, s) in enumerate(nodes):
    while stack and stack[-1][0] >= d:
        stack.pop()
    stack.append((d, s))
    kids = 0; j = i + 1
    while j < len(nodes) and nodes[j][0] > d:
        if all(not (nodes[k][0] > d and nodes[k][0] < nodes[j][0]) for k in range(i + 1, j)):
            kids += nodes[j][1]
        j += 1
    me = n - kids
    if me <= 0: continue
    selfc[s] += me
    c = "other"
    for _, a in reversed(stack):
        hit = next((name for name, r in CATS if r.search(a)), None)
        if hit: c = hit; break
    cat[c] += me
print("vCPU thread %d samples" % total)
for k, v in cat.most_common(): print("  %6d %5.1f%%  %s" % (v, 100.0 * v / total, k))
for k, v in selfc.most_common(int(sys.argv[2]) if len(sys.argv) > 2 else 25): print("  %6d %5.1f%%  %s" % (v, 100.0 * v / total, k))
