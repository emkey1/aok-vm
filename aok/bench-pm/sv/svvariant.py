#!/usr/bin/env python3
# svvariant.py NAME SRC -- one deliberate fault in the insns of sv.diff, for a positive control: ctxtest
# (ctx-test.sh) must fail for each, or the kit's Linux not reach the end of its workloads (sc-next).
import sys
name, src = sys.argv[1], sys.argv[2]
T = src + '/target/ppc/tcg/aok/translate.c'
V = {
'sc-next':     ("    env->nip = pc;\n    raise_exception_err_ra(", "    env->nip = pc + 4;\n    raise_exception_err_ra("),   # returns past the insn after the sc
'mfdec-reg':   ("    env->gpr[(insn >> 21) & 31] = helper_load_decr(env);\n", "    env->gpr[(insn >> 16) & 31] = helper_load_decr(env);\n"),
'mfdec-stale': ("    env->gpr[(insn >> 21) & 31] = helper_load_decr(env);\n", "    env->gpr[(insn >> 21) & 31] = env->spr[SPR_DECR];\n"),  # the SPR's word, not the timer
'mtdec-none':  ("    helper_store_decr(env, env->gpr[(insn >> 21) & 31]);\n", "    (void)env;\n"),
'tlbie-none':  ("    helper_tlbie(env, env->gpr[(insn >> 11) & 31]);\n    env->tlb_need_flush |= TLB_NEED_GLOBAL_FLUSH;\n", "    (void)env;\n"),
'lswx-reg':    ("        helper_lswx(env, ea, rt, (insn >> 16) & 31, (insn >> 11) & 31);\n", "        helper_lswx(env, ea, (rt + 1) & 31, (insn >> 16) & 31, (insn >> 11) & 31);\n"),
'stswx-count': ("        helper_stsw(env, ea, env->xer & 0x7f, rt);\n", "        helper_stsw(env, ea, 8, rt);\n"),
'lswx-ea':     ("    unsigned rt = (insn >> 21) & 31;\n    target_ulong ea = ea_x(env, insn);\n", "    unsigned rt = (insn >> 21) & 31;\n    target_ulong ea = env->gpr[(insn >> 11) & 31];\n"),   # rA left out
}
if name == 'list':
    print(' '.join(V)); sys.exit(0)
old, new = V[name]
s = open(T).read()
assert s.count(old) == 1, (name, s.count(old))
open(T, 'w').write(s.replace(old, new))
