#!/usr/bin/env bash
# 3_status.sh: progress, ETA and memory health for the background build or replay.
# Run it as often as you like; it changes nothing.
cd "$(dirname "$0")"; . ./common.sh
need_proj

for name in build_main replay; do
  pidf="$OUT/$name.pid"
  if [ -f "$pidf" ] && kill -0 "$(cat "$pidf")" 2>/dev/null; then
    echo "$name: RUNNING (PID $(cat "$pidf"))"
  elif [ -f "$OUT/$name.log" ]; then
    echo "$name: not running"
  fi
done
[ -f "$OUT/build_result.txt" ] && { echo; cat "$OUT/build_result.txt"; }

# ---- progress: compiled files vs source files ----------------------------------
find_sources() {
  case "$PROJ" in
    */.lake/*)
      find "$PROJ" -name '*.lean' ! -name 'Check.lean' ! -path '*/.lake/*' -print -o -name '.lake' -prune ;;
    *)
      find "$PROJ" -name '*.lean' ! -name 'Check.lean' -print -o -name '.lake' -prune ;;
  esac
}
# The first line gives the source count. Each remaining line counts toward the build total.
progress=$(
  {
    find_sources | wc -l || exit $?
    if [ -d "$PROJ/.lake/build" ]; then
      find "$PROJ/.lake/build" -name '*.olean' 2>/dev/null || true
    fi
  } | awk 'NR == 1 { t = $1 } END {
    d = NR - 1
    printf "%.0f %.0f %s", d, t, (t > 0 ? sprintf("%.1f", 100*d/t) : "0")
  }'
)
read -r done_n total pct <<< "$progress"
printf '\ncompiled: %s / %s files (%s%%)\n' "$done_n" "$total" "$pct"

if [ -f "$OUT/build_main.start" ]; then
  start=$(<"$OUT/build_main.start")
  { start_n=$(<"$OUT/build_main.start_count"); } 2>/dev/null || start_n=0
  elapsed=$(( $(date +%s) - start ))
  awk -v d="$done_n" -v s="$start_n" -v t="$total" -v e="$elapsed" 'BEGIN{
    printf "this run: %dh %02dm elapsed\n", e/3600, (e%3600)/60
    r = (d - s) / (e > 0 ? e : 1)
    if (r > 0) { left = (t - d) / r; printf "rough ETA: %dh %02dm (assumes the current pace holds; it usually doesn'"'"'t)\n", left/3600, (left%3600)/60 }
  }'
fi

# ---- last lines of the log -----------------------------------------------------
if [ -f "$OUT/build_main.log" ]; then
  echo; echo "last log lines:"; tail -n 3 "$OUT/build_main.log" | cut -c1-160
  errs=$(grep -c 'error' "$OUT/build_main.log" || true)
  [ "$errs" -gt 0 ] && echo "!! $errs lines mention 'error'. Look: grep -n error $OUT/build_main.log | head"
fi

if [ -f "$OUT/replay.log" ]; then
  echo; echo "replay log (last lines):"; tail -n 3 "$OUT/replay.log" | cut -c1-160
  [ -f "$OUT/replay_result.txt" ] && cat "$OUT/replay_result.txt"
fi

# ---- memory health -------------------------------------------------------------
echo
if is_mac; then
  sysctl -n vm.swapusage | awk '{print "swap:", $0}'
  memory_pressure 2>/dev/null | tail -n 1
  echo "(free percentage under ~10% for long stretches means: stop, then rerun with JOBS=2)"
else
  free -g
fi
echo "disk free: $(free_gb) GB"
