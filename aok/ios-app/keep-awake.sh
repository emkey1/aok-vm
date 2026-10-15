#!/bin/bash
# keep-awake.sh DEVICE [SECONDS] -- keep a device's screen on, so it does not lock between test runs: the
# bench app is launched to do nothing but hold the screen for SECONDS (default 3600), then let go and quit.
# The next run-device.sh replaces it (--terminate-existing). The device must be unlocked when this starts.
dev=$1; secs=${2:-3600}
exec xcrun devicectl device process launch --device "$dev" --terminate-existing \
    --environment-variables "{\"AOKQ_HOLD_ONLY\":\"1\",\"AOKQ_HOLD\":\"$secs\",\"AOKQ_EXIT\":\"1\"}" app.ish.aok-qemu-bench
