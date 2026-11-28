#!/usr/bin/env python3
# ctxvariant.py NAME SRC -- one deliberate fault in the TLB context cache, for a positive control of ctxtest.bin:
#   no-drop         a flush of the TLB leaves the contexts set aside as they are            (T2 must fail)
#   no-taint        an entry made under a changed segment register stays                    (T3, both)
#   no-jc           the jump cache is not exchanged with the TLB                            (T4)
#   no-dirty        tlb_reset_dirty() does not reach the contexts set aside                 (T5)
#   no-reuse-flush  a context given up is put to use again with what it held                (T6)
#   short-key       only the first four segment registers are compared                      (T1)
import sys
name, src = sys.argv[1], sys.argv[2]
def one(path, old, new):
    p = src + '/' + path; s = open(p).read()
    assert s.count(old) == 1, (name, s.count(old), old)
    open(p, 'w').write(s.replace(old, new))
C = 'accel/tcg/cputlb.c'
if name == 'no-drop':
    one(C, "    tlb_contexts_drop_locked(cpu);\n\n    all_dirty = cpu->neg.tlb.c.dirty;\n", "\n    all_dirty = cpu->neg.tlb.c.dirty;\n")
elif name == 'no-taint':
    one('target/ppc/mmu_helper.c', "            !mmuidx_real(mmu_idx) && ppc_tlb_sr_contexts(env)) {\n            env->tlb_need_flush |= TLB_NEED_LOCAL_FLUSH;\n",
        "            !mmuidx_real(mmu_idx) && ppc_tlb_sr_contexts(env)) {\n")
elif name == 'no-jc':
    one(C, "    qatomic_set(&cpu->tb_jmp_cache, to->jc);\n", "")
elif name == 'no-dirty':
    one(C, "        if (!c->valid) {\n            continue;\n        }\n        for (MMUIdxMap work = c->dirty;", "        if (1) {\n            continue;\n        }\n        for (MMUIdxMap work = c->dirty;")
elif name == 'no-reuse-flush':
    one(C, "    if (!found && !fresh) {\n        /* It holds what it was discarded with, or lost its turn with. */\n", "    if (0) {\n")
elif name == 'short-key':
    one(C, "        if (c->valid && !memcmp(c->key, new_key, len)) {\n", "        if (c->valid && !memcmp(c->key, new_key, 16)) {\n")
else:
    sys.exit('no such variant')
