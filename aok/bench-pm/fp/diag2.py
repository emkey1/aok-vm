#!/usr/bin/env python3
# diag2.py SRC -- on top of diag.py: would a cache of TLB contexts keyed by the sixteen segment registers hit?
# At each local flush the PowerPC target does, the SRs are looked up in a most-recently-used list of the sets
# seen since the last flush that was not a segment register's (tlbie, a BAT, invalidate-all). Counted: flushes
# with a tlbie pending; SR-only flushes by the depth the set was found at (1 = unchanged, 2, 3-4, 5-8, 9-16) or
# not found. Printed at exit with QEMU_AOK_STATS.
import sys
src = sys.argv[1]
def edit(path, pairs):
    p = src + '/' + path; s = open(p).read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, old)
        s = s.replace(old, new)
    open(p, 'w').write(s)
edit('target/ppc/helper_regs.c', [
    ('''uint64_t ppc_diag[8];
''', '''uint64_t ppc_diag[8];
uint64_t ppc_ctx_diag[8];
static uint32_t ppc_ctx_sets[16][16];
static int ppc_ctx_n;
static void ppc_ctx_sim(CPUPPCState *env)
{
    uint32_t cur[16];
    int i, d;

    for (i = 0; i < 16; i++) {
        cur[i] = env->sr[i];
    }
    if (ppc_diag[5]) {          /* a tlbie since the last flush: every context goes */
        ppc_diag[5] = 0;
        ppc_ctx_diag[0]++;
        ppc_ctx_n = 0;
    } else {
        for (d = 0; d < ppc_ctx_n; d++) {
            if (!memcmp(ppc_ctx_sets[d], cur, sizeof(cur))) {
                break;
            }
        }
        if (d == ppc_ctx_n) {
            ppc_ctx_diag[6]++;
        } else {
            ppc_ctx_diag[d == 0 ? 1 : d == 1 ? 2 : d < 4 ? 3 : d < 8 ? 4 : 5]++;
            memmove(ppc_ctx_sets[d], ppc_ctx_sets[d + 1], (ppc_ctx_n - d - 1) * sizeof(cur));
            ppc_ctx_n--;
        }
    }
    if (ppc_ctx_n == 16) {
        ppc_ctx_n = 15;
    }
    memmove(ppc_ctx_sets[1], ppc_ctx_sets[0], ppc_ctx_n * sizeof(cur));
    memcpy(ppc_ctx_sets[0], cur, sizeof(cur));
    ppc_ctx_n++;
}
static void __attribute__((destructor)) ppc_ctx_diag_print(void)
{
    if (getenv("QEMU_AOK_STATS") && ppc_diag[3]) {
        fprintf(stderr, "aok: ppc: diag: local flushes with a tlbie pending %llu; of segment registers only, "
                "by where the set was among those seen since: unchanged %llu, 2nd %llu, 3-4 %llu, 5-8 %llu, "
                "9-16 %llu, not there %llu\\n", (unsigned long long)ppc_ctx_diag[0],
                (unsigned long long)ppc_ctx_diag[1], (unsigned long long)ppc_ctx_diag[2],
                (unsigned long long)ppc_ctx_diag[3], (unsigned long long)ppc_ctx_diag[4],
                (unsigned long long)ppc_ctx_diag[5], (unsigned long long)ppc_ctx_diag[6]);
    }
}
'''),
    ('''        ppc_diag[3]++;
        tlb_flush(cs);''', '''        ppc_diag[3]++;
        ppc_ctx_sim(env);
        tlb_flush(cs);'''),
])
edit('target/ppc/mmu_helper.c', [
    ('''        { extern uint64_t ppc_diag[8]; ppc_diag[0]++; }
''', '''        { extern uint64_t ppc_diag[8]; ppc_diag[0]++; ppc_diag[5] = 1; }
'''),
])
print('diag2 applied')
