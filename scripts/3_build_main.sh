#!/usr/bin/env bash
# 3_build_main.sh: THE LONG ONE. Compiles all ~175,000 proof files (~17M lines).
# Expect many hours to a day or more on a 16 GB laptop.
#
# - Detaches into the background and keeps the Mac awake (caffeinate), so you can
#   close Terminal. Keep it plugged in with the lid open.
# - Resumable: stopping (3_stop.sh) or a crash loses nothing that already finished.
#   Just run this script again.
# - Watch it with 3_status.sh.
cd "$(dirname "$0")"; . ./common.sh
need_proj; elan_env

run_detached build_main "$PWD/3_build_main.sh"

# ---- everything below runs in the background -----------------------------------
cd "$PROJ"
export LEAN_NUM_THREADS="$JOBS"
date +%s > "$OUT/build_main.start"
# find fails (no build dir etc.) -> pipefail; || true keeps the wc count anyway
n=$(find .lake/build -name '*.olean' 2>/dev/null | wc -l) || true
echo "${n// /}" > "$OUT/build_main.start_count"
echo "=== build started $(date) with LEAN_NUM_THREADS=$JOBS ===" >> "$OUT/build_main.log"

if lake build Main >> "$OUT/build_main.log" 2>&1; then
  mins=$(( ($(date +%s) - $(< "$OUT/build_main.start")) / 60 ))
  msg="build_main: OK (this run took $mins min)"
  {
    echo "$msg"
    echo "Next: bash 4_check.sh"
  } > "$OUT/build_result.txt"
  echo "$msg"
else
  msg="build_main: FAILED (see $OUT/build_main.log; search it for 'error')"
  echo "$msg" > "$OUT/build_result.txt"
  echo "$msg"
fi
rm -f "$OUT/build_main.pid"
