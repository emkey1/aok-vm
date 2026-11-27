#!/usr/bin/env python3
# diag.py SRC -- counters for a diagnosis, not for a commit: why and how often the PowerPC target flushes the
# TLB, and how many jump-cache flushes found the cache clean. Printed at exit when QEMU_AOK_STATS is set.
import sys
src = sys.argv[1]
def edit(path, pairs):
    p = src + '/' + path; s = open(p).read()
    for old, new in pairs:
        assert s.count(old) >= 1, (path, old)
        s = s.replace(old, new)
    open(p, 'w').write(s)
edit('target/ppc/helper_regs.c', [
    ('''void check_tlb_flush(CPUPPCState *env, bool global)
{''', '''uint64_t ppc_diag[8];
static void __attribute__((destructor)) ppc_diag_print(void)
{
    if (getenv("QEMU_AOK_STATS") && ppc_diag[3]) {
        fprintf(stderr, "aok: ppc: diag: tlbie %llu, sr writes that changed %llu, BAT flushes %llu, "
                "local flushes done %llu, invalidate-all %llu\\n", (unsigned long long)ppc_diag[0],
                (unsigned long long)ppc_diag[1], (unsigned long long)ppc_diag[2],
                (unsigned long long)ppc_diag[3], (unsigned long long)ppc_diag[4]);
    }
}
void check_tlb_flush(CPUPPCState *env, bool global)
{'''),
    ('''        env->tlb_need_flush &= ~TLB_NEED_LOCAL_FLUSH;
        tlb_flush(cs);
    }
}''', '''        env->tlb_need_flush &= ~TLB_NEED_LOCAL_FLUSH;
        ppc_diag[3]++;
        tlb_flush(cs);
    }
}'''),
])
edit('target/ppc/mmu_helper.c', [
    ('''    if (env->sr[srnum] != value) {
        env->sr[srnum] = value;''', '''    if (env->sr[srnum] != value) {
        { extern uint64_t ppc_diag[8]; ppc_diag[1]++; }
        env->sr[srnum] = value;'''),
    ('''         * account, we just mark the TLB to be flushed later (context
         * synchronizing event or sync instruction on 32-bit).
         */
        env->tlb_need_flush |= TLB_NEED_LOCAL_FLUSH;''', '''         * account, we just mark the TLB to be flushed later (context
         * synchronizing event or sync instruction on 32-bit).
         */
        { extern uint64_t ppc_diag[8]; ppc_diag[0]++; }
        env->tlb_need_flush |= TLB_NEED_LOCAL_FLUSH;'''),
    ('''static inline void do_invalidate_BAT(CPUPPCState *env, target_ulong BATu,
''', '''extern uint64_t ppc_diag[8];
static inline void do_invalidate_BAT(CPUPPCState *env, target_ulong BATu,
'''),
    ('''void ppc_tlb_invalidate_all(CPUPPCState *env)
{''', '''void ppc_tlb_invalidate_all(CPUPPCState *env)
{
    ppc_diag[4]++;'''),
])
s = open(src + '/target/ppc/mmu_helper.c').read()
i = s.index('static inline void do_invalidate_BAT'); j = s.index('tlb_flush(cs);', i)
s = s[:j] + 'ppc_diag[2]++; ' + s[j:]
open(src + '/target/ppc/mmu_helper.c', 'w').write(s)
edit('accel/tcg/translate-all.c', [
    ('''    if (!qatomic_read(&jc->dirty)) {
        return;
    }''', '''    { extern uint64_t tcg_jc_diag[2]; tcg_jc_diag[!qatomic_read(&jc->dirty)]++; }
    if (!qatomic_read(&jc->dirty)) {
        return;
    }'''),
    ('''void tcg_flush_jmp_cache(CPUState *cpu)
{''', '''uint64_t tcg_jc_diag[2];
static void __attribute__((destructor)) tcg_jc_diag_print(void)
{
    if (getenv("QEMU_AOK_STATS") && (tcg_jc_diag[0] | tcg_jc_diag[1])) {
        fprintf(stderr, "aok: diag: jump-cache flushes: %llu of a cache with TBs in it, %llu of a clean one\\n",
                (unsigned long long)tcg_jc_diag[0], (unsigned long long)tcg_jc_diag[1]);
    }
}
void tcg_flush_jmp_cache(CPUState *cpu)
{'''),
])
print('diag applied')
