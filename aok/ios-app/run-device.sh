#!/bin/bash
# run-device.sh DEVICE LABEL AOK WORKLOADS [SECONDS] [SMP] -- one run of the app on a device, and its results.
#   DEVICE     a devicectl identifier (UDID or name)
#   LABEL      arch-engine-round for the WL lines, e.g. riscv64-aokq-1 (gadgets) or riscv64-tctish-1 (without)
#   AOK        1 = AOK's gadgets, 0 = the same QEMU with every block left to its own engine
#   WORKLOADS  comma separated, as bench/run1.sh names them
# Waits up to SECONDS (default 900) for the run's DONE line, then prints this run's lines of results.txt.
# AOKQ_ENV adds to the app's environment, as JSON members: AOKQ_ENV='"QEMU_AOK_NO_PAIRS":"1"'.
# The app is launched, never debugged; the device must be unlocked.
dev=$1; label=$2; aok=$3; wl=$4; secs=${5:-900}; smp=${6:-1}
id=app.ish.aok-qemu-bench
out=$(mktemp -d)
env="{\"QEMU_AOK\":\"$aok\",\"AOKQ_LABEL\":\"$label\",\"AOKQ_WORKLOADS\":\"$wl\",\"AOKQ_SMP\":\"$smp\"${AOKQ_ENV:+,$AOKQ_ENV}}"
xcrun devicectl device process launch --device "$dev" --terminate-existing --environment-variables "$env" $id \
    > "$out/launch.log" 2>&1 || { cat "$out/launch.log"; exit 1; }
pull() {
    xcrun devicectl device copy from --device "$dev" --domain-type appDataContainer --domain-identifier $id \
        --source "Documents/$1" --destination "$out/$1" > /dev/null 2>&1
}
end=$((SECONDS + secs))
while [ $SECONDS -lt $end ]; do
    sleep 5
    pull results.txt || continue
    # This run's part: from its last START line on.
    awk -v l="$label" '$1 == "START" && $2 == l { n = 0 } { a[n++] = $0 } END { for (i = 0; i < n; i++) print a[i] }' \
        "$out/results.txt" > "$out/run.txt"
    grep -q "^DONE $label " "$out/run.txt" && break
    grep -q "^ERROR" "$out/run.txt" && break
done
cat "$out/run.txt" 2>/dev/null
if ! grep -q "^DONE $label " "$out/run.txt" 2>/dev/null; then
    echo "-- no DONE within ${secs}s"
    pull qemu.log && tail -5 "$out/qemu.log"
    pull serial.log && tail -5 "$out/serial.log"
    exit 1
fi
