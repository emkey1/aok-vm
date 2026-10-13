#!/bin/bash
# prof-aok.sh WORKLOAD [SECONDS] [SYMBOLS] -- sample the AOK-gadgets QEMU build while it runs WORKLOAD
# (repeated), and print where its time goes by category and by symbol. A breakdown only: sampling perturbs
# speed, so never quote a rate from a run under this.
W=$HOME/aok-vm-bench; wl=$1; secs=${2:-6}
"$W/boot-aok.sh" "$wl,$wl,$wl,$wl" > "$W/prof-$wl.out" 2>&1 &
until grep -aq "WL-START" "$W/prof-$wl.out" 2>/dev/null; do sleep 0.5; done
sleep 1
pid=$(pgrep -f "build-aok/qemu-system" | head -1)
sample "$pid" "$secs" -mayDie -file "$W/prof-$wl.sample" > /dev/null 2>&1
kill -9 "$pid" 2>/dev/null
awk '/^Sort by top of stack/{p=1; next} /^Binary Images/{p=0} p && NF' "$W/prof-$wl.sample" > "$W/prof-$wl.top"
awk '{
    n = $NF; s = $1
    if (s ~ /^aok_gadget_rv_(l[bhwd]u?|s[bhwd]|fl|fs)/) k = "aok memory gadgets"
    else if (s ~ /^aok_gadget_(enter|goto|exit_tb|lookup)|^aok_goto_tail|^aok_lookup_tail|^aok_exit|^aok_tb_exec/) k = "aok enter/goto/exit"
    else if (s ~ /^aok_gadget_rv_(b|jalr|jal)/) k = "aok branch gadgets"
    else if (s ~ /^aok_gadget_/) k = "aok other gadgets"
    else if (s ~ /^aok_rv_helper|mmu_lookup|do_ld|do_st|cpu_ld|cpu_st|riscv_env_mmu_index|tlb_|probe_|victim|riscv_cpu_tlb|get_physical|pmp_/) k = "memory slow path (C)"
    else if (s ~ /^aok_lookup_tb_ptr|tb_lookup|riscv_get_tb_cpu_state|riscv_cpu_virt_mem|riscv_pm_get|cpu_get_.cfi|tb_htable|qht_|check_for_break|curr_cflags|smstateen/) k = "block lookup (C)"
    else if (s ~ /^cpu_tb_exec|cpu_exec|cpu_handle|tb_add_jump|tb_set_jmp|tcg_qemu_tb_exec|align_clocks|cpu_loop/) k = "main loop (C)"
    else if (s ~ /^gadget_|tcti/) k = "TCTI gadgets (fallback TBs)"
    else if (s ~ /^helper_|float|softfloat|riscv_|csr|round|pack|parts_/) k = "TCG helpers (C)"
    else if (s ~ /^__psynch_cvwait|__sigwait|mach_msg|__select|__workq|__semwait|kevent/) { idle += n; next }
    else k = "other"
    c[k] += n; t += n
} END { for (k in c) printf "%5.1f%%  %s\n", 100 * c[k] / t, k }' "$W/prof-$wl.top" | sort -rn
echo "-- top symbols"
grep -v '__psynch_cvwait\|__sigwait\|mach_msg2\|__select\|__workq' "$W/prof-$wl.top" | head -"${3:-14}" | cut -c1-90
