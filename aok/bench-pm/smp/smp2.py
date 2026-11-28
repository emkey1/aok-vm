#!/usr/bin/env python3
# smp2.py TREE -- each CPU of a 32-bit PowerPC guest on a host thread of its own (MTTCG, as 64-bit PowerPC has
# had since 2017), and the front end's stwcx. as an atomic compare-and-swap, which parallel CPUs need.
import sys
T = sys.argv[1]
def edit(path, pairs):
    p = T + '/' + path; s = open(p).read()
    for a, b in pairs:
        assert s.count(a) == 1, (path, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w').write(s)
edit('target/ppc/cpu_init.c', [(
"""  .mttcg_supported = TARGET_LONG_BITS == 64,""",
"""  /*
   * 32-bit too: TCG's stwcx. is a cmpxchg for either, tlbie's global
   * flush is the same synced work, and the 32-bit hash MMU sets R and C a
   * byte at a time, so that two CPUs do not undo one another's.
   */
  .mttcg_supported = true,""")])
edit('target/ppc/tcg/aok/translate.c', [(
"""    if (ea == env->reserve_addr && env->reserve_length == 4) {
        MemOpIdx oi = OI(env, MO_BEUL | MO_ALIGN);
        uint32_t old = cpu_ldl_mmu(env, ea, oi, 0);
        bool ok = old == env->reserve_val;

        cpu_stl_mmu(env, ea, ok ? env->gpr[(insn >> 21) & 31] : old, oi, 0);
        cr0 |= ok ? CRF_EQ : 0;
    }""",
"""    if (ea == env->reserve_addr && env->reserve_length == 4) {
        /*
         * A compare-and-swap with the value lwarx saw, as TCG's code does
         * for a parallel TB: another CPU may store between the two insns.
         * It needs write access whether or not it stores, as the load and
         * store it replaces did.
         */
        MemOpIdx oi = OI(env, MO_BEUL | MO_ALIGN);
        uint32_t old = cpu_atomic_cmpxchgl_be_mmu(env, ea, env->reserve_val,
                                                  env->gpr[(insn >> 21) & 31],
                                                  oi, 0);

        cr0 |= old == env->reserve_val ? CRF_EQ : 0;
    }""")])
print('smp2 applied')
