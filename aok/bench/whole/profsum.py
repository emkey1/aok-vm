#!/usr/bin/env python3
# profsum.py FILE...: the vCPU threads' host time in each `sample` file, by kind of code (each function's own samples).
import re, sys, collections
# __gettimeofday: inside pthread_cond_wait, for a timed wait (thread-pool workers).
IDLE = re.compile(r"(kevent|__select|poll|mach_msg|psynch|semwait|workq|__wait4|nanosleep|sigsuspend|ppoll|"
                  r"qemu_poll_ns|qemu_cond_wait|g_main|__ulock_wait|__sigwait|__gettimeofday)")
def kind(sym):
    sym = "_" + sym.lstrip("_")
    if sym.startswith("_rcg_"):
        return "rcg gadget (whole instruction)"
    if sym.startswith("_gadget_"):
        f = re.sub(r"_(arg\d+|imm\w*|i\d+_?\w*)$", "", sym)
        f = re.sub(r"(_arg\d+)+.*$", "", sym)
        if f.startswith("_gadget_qemu_"):
            return "tcti: guest memory (qemu_ld/st)"
        if re.search(r"(brcond|_br$|goto|exit_tb|goto_ptr|call|setcond|movcond)", f):
            return "tcti: branch/compare/call, TB exits"
        if re.match(r"_gadget_(ld|st)\d*[su]?(_|$)", f) or "_env" in f:
            return "tcti: env load/store (globals, spills)"
        return "tcti: arithmetic, moves"
    return "C: helpers, translator, main loop"


# Each function's own samples, from the call graph: a node's count less its children's. (The "Sort by top
# of stack" summary leaves out every symbol under 5 samples, which is most of TCTI's register-specialised
# gadgets.)
NODE = re.compile(r"^([ +!:|]*?)(\d+) (\S+)  \(in ")


def self_counts(text):
    graph = text.split("Call graph:")[1].split("Total number in stack")[0]
    own = collections.Counter()
    stack = []  # (column, symbol, count, children's sum)
    def close(upto):
        while stack and stack[-1][0] >= upto:
            col, sym, n, kids = stack.pop()
            own[sym] += n - kids
    vcpu = False
    for line in graph.splitlines():
        if re.match(r"^\s+\d+ Thread_", line):
            # Only the vCPU threads ("CPU n/TCG"): an I/O thread's fsync is not the guest's time.
            close(0)
            vcpu = "/TCG" in line
            continue
        m = NODE.match(line)
        if not m or not vcpu:
            continue
        col, n, sym = len(m.group(1)), int(m.group(2)), m.group(3)
        close(col)
        if stack:
            stack[-1][3] += n
        stack.append([col, sym, n, 0])
    close(0)
    return own


fams = {}
for path in sys.argv[1:]:
    t = open(path).read()
    k = collections.Counter(); fam = collections.Counter()
    for sym, n in self_counts(t).items():
        if IDLE.search(sym):
            continue
        k[kind(sym)] += n
        s = "_" + sym.lstrip("_")
        fam[re.sub(r"(_arg\d+|_imm\w*|_i\d+)+.*$", "", s) if s.startswith("_gadget_") else
            ("_rcg_*" if s.startswith("_rcg_") else sym)] += n
    tot = sum(k.values())
    print(f"== {path.split('/')[-1]}: {tot} busy samples")
    for name, n in k.most_common():
        print(f"  {100 * n / tot:5.1f}%  {name}")
    print("  top:", ", ".join(f"{s} {100 * n / tot:.1f}%" for s, n in fam.most_common(12)))
    rcg = collections.Counter()
    for sym, n in self_counts(t).items():
        if sym.lstrip("_").startswith("rcg_"):
            g = re.sub(r"^rcg_gadget_", "", sym.lstrip("_"))
            rcg[re.sub(r"_(ord|b|bi\d|i\d|bd|s)$", "", re.sub(r"_(ord)$", "", g))] += n
    print("  rcg:", ", ".join(f"{s} {100 * n / tot:.1f}%" for s, n in rcg.most_common(10)))
