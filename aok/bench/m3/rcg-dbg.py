# Applies a temporary diagnostic (RCG_DEBUG_PROF) to accel/tcg/cpu-exec.c. Not for the branch.
import sys
p = sys.argv[1] + '/accel/tcg/cpu-exec.c'
s = open(p).read()
anchor = '''static inline TranslationBlock * QEMU_DISABLE_CFI
cpu_tb_exec(CPUState *cpu, TranslationBlock *itb, int *tb_exit)'''
dbg = r'''
/* DIAGNOSTIC ONLY (RCG_DEBUG_PROF=file): where streams hand off to TCG. */
static bool rcg_dbg;
static uint64_t rcg_dbg_stream, rcg_dbg_tcg, rcg_dbg_ret0, rcg_dbg_retslot;
uint64_t rcg_dbg_lookup_stream, rcg_dbg_lookup_tcg, rcg_dbg_lookup_none;
#define RCG_DBG_N 65536
static struct RcgDbg { uint64_t pc, n; uint8_t b[12]; } rcg_dbg_prof[RCG_DBG_N];
static uint64_t rcg_dbg_dropped;

static void rcg_dbg_note(CPUState *cpu, uint64_t pc)
{
    unsigned h = (pc >> 1) * 0x9e3779b97f4a7c15ull >> 48;

    for (int i = 0; i < 32; i++) {
        struct RcgDbg *e = &rcg_dbg_prof[(h + i) % RCG_DBG_N];

        if (e->n && e->pc == pc) {
            e->n++;
            return;
        }
        if (!e->n) {
            e->pc = pc;
            e->n = 1;
            cpu_memory_rw_debug(cpu, pc, e->b, sizeof(e->b), false);
            return;
        }
    }
    rcg_dbg_dropped++;
}

static int rcg_dbg_cmp(const void *a, const void *b)
{
    const struct RcgDbg *x = a, *y = b;

    return x->n < y->n ? 1 : x->n > y->n ? -1 : 0;
}

static void rcg_dbg_print(void)
{
    FILE *f = fopen(getenv("RCG_DEBUG_PROF"), "w");

    if (!f) {
        return;
    }
    fprintf(f, "stream entries %" PRIu64 ", TCG TB entries %" PRIu64
            ", streams back with no TB %" PRIu64 ", by a slot %" PRIu64 "\n",
            rcg_dbg_stream, rcg_dbg_tcg, rcg_dbg_ret0, rcg_dbg_retslot);
    fprintf(f, "C lookups from streams: stream %" PRIu64 ", TCG TB %" PRIu64
            ", none %" PRIu64 "\n", rcg_dbg_lookup_stream,
            rcg_dbg_lookup_tcg, rcg_dbg_lookup_none);
    qsort(rcg_dbg_prof, RCG_DBG_N, sizeof(rcg_dbg_prof[0]), rcg_dbg_cmp);
    for (int i = 0; i < 300 && rcg_dbg_prof[i].n; i++) {
        fprintf(f, "%10" PRIu64 " %016" PRIx64 " ", rcg_dbg_prof[i].n,
                rcg_dbg_prof[i].pc);
        for (int j = 0; j < 12; j++) {
            fprintf(f, "%02x", rcg_dbg_prof[i].b[j]);
        }
        fprintf(f, "\n");
    }
    fprintf(f, "dropped %" PRIu64 "\n", rcg_dbg_dropped);
    fclose(f);
}

static void __attribute__((constructor)) rcg_dbg_init(void)
{
    if (getenv("RCG_DEBUG_PROF")) {
        rcg_dbg = true;
        atexit(rcg_dbg_print);
    }
}

'''
assert s.count(anchor) == 1
s = s.replace(anchor, dbg + anchor)
old = '''        ret = rcg_stream_exec(env, tb_ptr, &rcg);
        trace_rcg_stream_exec(itb, ret);
    } else
#endif
    {
        ret = tcg_qemu_tb_exec(cpu_env(cpu), tb_ptr);
    }'''
new = '''        ret = rcg_stream_exec(env, tb_ptr, &rcg);
        trace_rcg_stream_exec(itb, ret);
        if (rcg_dbg) {
            rcg_dbg_stream++;
            *(ret & ~(uintptr_t)TB_EXIT_MASK ? &rcg_dbg_retslot
                                             : &rcg_dbg_ret0) += 1;
        }
    } else
#endif
    {
        if (rcg_dbg) {
            rcg_dbg_tcg++;
            rcg_dbg_note(cpu, *(uint64_t *)((void *)cpu_env(cpu) +
                                            cpu->cc->tcg_ops->rcg_pc_offset));
        }
        ret = tcg_qemu_tb_exec(cpu_env(cpu), tb_ptr);
    }'''
assert s.count(old) == 1
s = s.replace(old, new)
old = '''    tb = tb_lookup(cpu, s);
    if (tb == NULL || !tb->rcg_stream) {
        return NULL;
    }'''
new = '''    tb = tb_lookup(cpu, s);
    if (rcg_dbg) {
        *(tb == NULL ? &rcg_dbg_lookup_none : tb->rcg_stream ?
          &rcg_dbg_lookup_stream : &rcg_dbg_lookup_tcg) += 1;
    }
    if (tb == NULL || !tb->rcg_stream) {
        return NULL;
    }'''
assert s.count(old) == 1
s = s.replace(old, new)
open(p, 'w').write(s)
print("patched")
