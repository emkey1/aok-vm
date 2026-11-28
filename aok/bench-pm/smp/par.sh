# par.sh -- in the guest: a CPU-bound shell loop alone, then two at once, then four; wall seconds of each.
L() { i=0; while [ $i -lt 60000 ]; do i=$((i+1)); done; }
t() { s=$(date +%s); "$@"; echo $(( $(date +%s) - s )); }
two() { L & L & wait; }
four() { L & L & L & L & wait; }
echo "one: $(t L) s"
echo "two at once: $(t two) s"
echo "four at once: $(t four) s"
