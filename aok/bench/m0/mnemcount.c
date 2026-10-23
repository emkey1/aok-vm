/*
 * mnemcount: a TCG plugin that counts executed guest instructions by mnemonic
 * (for tctiSH/qemu#6 M0: which instructions a workload runs most).
 *
 * Each instruction is disassembled once, at translation, and given an inline
 * per-vCPU counter for its mnemonic (a "rep"/"lock" prefix is kept with it).
 * At exit the totals go to the file named by the plugin's out= argument, or
 * to stderr: "count mnemonic" per line, most first, after a "total" line.
 *
 *   -plugin ./libmnemcount.dylib,out=/tmp/counts.txt
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include <glib.h>
#include <stdio.h>
#include <string.h>
#include <qemu-plugin.h>

QEMU_PLUGIN_EXPORT int qemu_plugin_version = QEMU_PLUGIN_VERSION;

typedef struct {
    char *name;
    struct qemu_plugin_scoreboard *score;
} Mnem;

static GHashTable *mnems;
static GMutex lock;
static char *out_path;

static char *mnemonic_of(const char *disas)
{
    /* "rep movsb ...", "lock xadd ...", "movq %rax, %rbx": keep a prefix
     * with the mnemonic it applies to; drop the operands. */
    gchar **w = g_strsplit_set(disas, " \t", 3);
    char *m;
    if (w[0] && w[1] && (!strcmp(w[0], "rep") || !strcmp(w[0], "repz") ||
                         !strcmp(w[0], "repe") || !strcmp(w[0], "repnz") ||
                         !strcmp(w[0], "repne") || !strcmp(w[0], "lock") ||
                         !strcmp(w[0], "data16") || !strcmp(w[0], "addr32"))) {
        m = g_strdup_printf("%s %s", w[0], w[1]);
    } else {
        m = g_strdup(w[0] ? w[0] : "?");
    }
    /* AT&T spells a vector, MMX or x87 operand with its register; tag the
     * mnemonic with it, as movq is both a GPR move and a vector one. */
    const char *ops = strchr(disas, ' ');
    const char *tag = !ops ? "" :
        (strstr(ops, "%xmm") || strstr(ops, "%ymm") || strstr(ops, "%zmm")) ? ".vec" :
        strstr(ops, "%mm") ? ".mmx" : strstr(ops, "%st") ? ".x87" : "";
    if (*tag) {
        char *t = g_strconcat(m, tag, NULL);
        g_free(m);
        m = t;
    }
    g_strfreev(w);
    return m;
}

static Mnem *mnem_for(const char *name)
{
    Mnem *m;
    g_mutex_lock(&lock);
    m = g_hash_table_lookup(mnems, name);
    if (!m) {
        m = g_new0(Mnem, 1);
        m->name = g_strdup(name);
        m->score = qemu_plugin_scoreboard_new(sizeof(uint64_t));
        g_hash_table_insert(mnems, m->name, m);
    }
    g_mutex_unlock(&lock);
    return m;
}

static void tb_trans(struct qemu_plugin_tb *tb, void *userdata)
{
    size_t n = qemu_plugin_tb_n_insns(tb);
    for (size_t i = 0; i < n; i++) {
        struct qemu_plugin_insn *insn = qemu_plugin_tb_get_insn(tb, i);
        char *d = qemu_plugin_insn_disas(insn);
        char *name = mnemonic_of(d ? d : "?");
        Mnem *m = mnem_for(name);
        qemu_plugin_register_vcpu_insn_exec_inline_per_vcpu(
            insn, QEMU_PLUGIN_INLINE_ADD_U64,
            qemu_plugin_scoreboard_u64(m->score), 1);
        g_free(name);
        g_free(d);
    }
}

static gint by_count(gconstpointer a, gconstpointer b, gpointer total)
{
    uint64_t x = qemu_plugin_u64_sum(qemu_plugin_scoreboard_u64(((Mnem *)a)->score));
    uint64_t y = qemu_plugin_u64_sum(qemu_plugin_scoreboard_u64(((Mnem *)b)->score));
    return x < y ? 1 : x > y ? -1 : 0;
}

static void at_exit(void *p)
{
    GList *all = g_list_sort_with_data(g_hash_table_get_values(mnems), by_count, NULL);
    uint64_t total = 0;
    for (GList *l = all; l; l = l->next) {
        total += qemu_plugin_u64_sum(qemu_plugin_scoreboard_u64(((Mnem *)l->data)->score));
    }
    FILE *f = out_path ? fopen(out_path, "w") : NULL;
    if (!f) {
        f = stderr;
    }
    fprintf(f, "%" PRIu64 " total\n", total);
    for (GList *l = all; l; l = l->next) {
        Mnem *m = l->data;
        uint64_t c = qemu_plugin_u64_sum(qemu_plugin_scoreboard_u64(m->score));
        if (c) {
            fprintf(f, "%" PRIu64 " %s\n", c, m->name);
        }
    }
    if (f != stderr) {
        fclose(f);
    }
    g_list_free(all);
}

QEMU_PLUGIN_EXPORT int qemu_plugin_install(qemu_plugin_id_t id, const qemu_info_t *info,
                                           int argc, char **argv)
{
    for (int i = 0; i < argc; i++) {
        if (g_str_has_prefix(argv[i], "out=")) {
            out_path = g_strdup(argv[i] + 4);
        }
    }
    mnems = g_hash_table_new(g_str_hash, g_str_equal);
    qemu_plugin_register_vcpu_tb_trans_cb(id, tb_trans, NULL);
    qemu_plugin_register_atexit_cb(id, at_exit, NULL);
    return 0;
}
