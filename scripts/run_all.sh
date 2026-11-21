#!/usr/bin/env bash
# run_all.sh: run the entire RH verification pipeline in Terminal with live progress.
#
# Usage:
#   bash run_all.sh                           # run (or safely resume) all steps
#   JOBS=2 bash run_all.sh                    # limit parallel Lean jobs (16 GB RAM)
#   STATUS_INTERVAL=10 bash run_all.sh        # refresh interval during step 3 (default: 15s)
#   bash run_all.sh --fresh                   # re-run preflight & setup from scratch
#   bash run_all.sh --pause-after-preflight   # pause after step 1 to review scan output

set -euo pipefail

replay_instructions() {
  cat <<'EOF'

Optional kernel replay after the pipeline finishes
Run one of these commands from the script folder with the same WORK directory.
  bash 5_replay.sh          # check all compiled modules in parallel
  FRESH=1 bash 5_replay.sh  # replay Main and its dependencies in a fresh environment (single-threaded)
Both modes run in the background. Use bash 3_status.sh to check progress.
After replay finishes, run bash 6_report.sh to include its result in REPORT.md.
EOF
}

FRESH=0
PAUSE_AFTER_PREFLIGHT=0
for arg in "$@"; do
  case "$arg" in
    --fresh) FRESH=1 ;;
    --pause-after-preflight) PAUSE_AFTER_PREFLIGHT=1 ;;
    -h|--help)
      sed -n '1d; /^#/!q; s/^# \{0,1\}//p' "$0"
      replay_instructions
      exit 0
      ;;
    *)
      printf 'Unknown option: %s (try --help)\n' "$arg" >&2
      exit 2
      ;;
  esac
done

# Keep the Mac awake across all steps (steps 1, 2, 4, and the monitor).
if [ -z "${RH_CAFFEINATED:-}" ] && command -v caffeinate >/dev/null 2>&1; then
  export RH_CAFFEINATED=1
  exec caffeinate -ims bash "$0" "$@"
fi

cd "$(dirname "$0")"
. ./common.sh

STATUS_INTERVAL="${STATUS_INTERVAL:-15}"
PIPELINE_START=$(date +%s)

# Step state labels
S1="waiting"
S2="waiting"
S3="waiting"
S4="waiting"
S5="waiting"

fmt_dur() {
  local s=$1
  if [ "$s" -ge 3600 ]; then
    printf '%dh %02dm %02ds' $((s / 3600)) $(((s % 3600) / 60)) $((s % 60))
  elif [ "$s" -ge 60 ]; then
    printf '%dm %02ds' $((s / 60)) $((s % 60))
  else
    printf '%ds' "$s"
  fi
}

step_icon() {
  case "$1" in
    done*)    printf '[OK]' ;;
    running*) printf '[>>]' ;;
    FAILED*)  printf '[!!]' ;;
    *)        printf '[  ]' ;;
  esac
}

draw_board() {
  local now elapsed
  now=$(date +%s)
  elapsed=$((now - PIPELINE_START))
  printf '========================================================================\n'
  printf '  RH Lean Verification Pipeline   |   JOBS=%s   |   Elapsed: %s\n' "$JOBS" "$(fmt_dur "$elapsed")"
  printf '  Work dir: %s\n' "$WORK"
  printf '========================================================================\n'
  printf '  %s 1/5 Preflight (download, hash, scan)     : %s\n' "$(step_icon "$S1")" "$S1"
  printf '  %s 2/5 Setup (Lean, Mathlib, Statements)    : %s\n' "$(step_icon "$S2")" "$S2"
  printf '  %s 3/5 Build Main (~175k Lean files)        : %s\n' "$(step_icon "$S3")" "$S3"
  printf '  %s 4/5 Check (statement & axiom verdict)    : %s\n' "$(step_icon "$S4")" "$S4"
  printf '  %s 5/5 Report (generate REPORT.md)          : %s\n' "$(step_icon "$S5")" "$S5"
  printf '========================================================================\n'
}

draw_progress_bar() {
  local pct="$1" done_n="$2" total="$3"
  awk -v p="$pct" -v d="$done_n" -v t="$total" 'BEGIN {
    w = 36
    if (p < 0) p = 0
    if (p > 100) p = 100
    filled = int((p / 100.0) * w + 0.5)
    bar = ""
    for (i = 0; i < w; i++) bar = bar (i < filled ? "#" : "-")
    printf "  Progress: [%s] %5.1f%% (%s / %s files)\n", bar, p, d, t
  }'
}

build_is_running() {
  local pidf="$OUT/build_main.pid" pid=""
  if [ -f "$pidf" ]; then
    IFS= read -r pid < "$pidf" || true
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
  else
    return 1
  fi
}

# ---- Step 1: Preflight ---------------------------------------------------------
if [ "$FRESH" = 0 ] && [ -f "$PROJ/lean-toolchain" ] \
   && [ -f "$OUT/hash.txt" ] && grep -q 'PASS: archive matches the published hash' "$OUT/hash.txt" 2>/dev/null; then
  S1="done (existing — preserving $PROJ)"
else
  S1="running"
  echo
  draw_board
  t0=$(date +%s)
  if bash ./1_preflight.sh; then
    S1="done ($(fmt_dur $(($(date +%s) - t0))))"
  else
    S1="FAILED"
    echo
    draw_board
    die "Step 1 (1_preflight.sh) failed."
  fi
  if [ "$PAUSE_AFTER_PREFLIGHT" = 1 ]; then
    echo
    printf 'Paused after preflight. Review %s/scan_buildtime_code.txt if desired.\n' "$OUT"
    printf 'Press Enter to continue to Step 2 (or Ctrl-C to stop)... '
    IFS= read -r _
  fi
fi

# ---- Step 2: Setup -------------------------------------------------------------
if [ "$FRESH" = 0 ] && [ -f "$OUT/setup.done" ] && [ -f "$PROJ/lean-toolchain" ]; then
  S2="done (existing)"
else
  S2="running"
  echo
  draw_board
  t0=$(date +%s)
  if bash ./2_setup.sh; then
    date -u +%Y-%m-%dT%H:%M:%SZ > "$OUT/setup.done"
    S2="done ($(fmt_dur $(($(date +%s) - t0))))"
  else
    S2="FAILED"
    echo
    draw_board
    die "Step 2 (2_setup.sh) failed."
  fi
fi

# ---- Step 3: Build Main (with live progress dashboard) -------------------------
if [ "$FRESH" = 0 ] && ! build_is_running \
   && [ -f "$OUT/build_result.txt" ] && grep -q '^build_main: OK' "$OUT/build_result.txt" 2>/dev/null; then
  S3="done (existing)"
else
  S3="running"
  t0=$(date +%s)
  if build_is_running; then
    echo
    echo "build_main is already running — attaching live progress monitor..."
  else
    rm -f "$OUT/build_result.txt"
    echo
    draw_board
    bash ./3_build_main.sh
    # Give the detached background process a moment to write its PID file.
    for _ in 1 2 3 4 5; do
      if build_is_running || [ -f "$OUT/build_result.txt" ]; then break; fi
      sleep 1
    done
  fi

  on_detach() {
    printf '\n\nDetached progress monitor. The background build is STILL RUNNING.\n'
    printf '  Re-attach monitor : bash run_all.sh\n'
    printf '  One-shot status   : bash 3_status.sh\n'
    printf '  Stop build safely : bash 3_stop.sh\n'
    exit 130
  }
  trap on_detach INT TERM

  while build_is_running; do
    pid=""
    IFS= read -r pid < "$OUT/build_main.pid" 2>/dev/null || true
    S3="running (PID ${pid:-?}, $(fmt_dur $(($(date +%s) - t0))) watching)"
    status_out=$(bash ./3_status.sh 2>&1 || true)

    # Extract compiled counts & percentage from 3_status.sh output.
    comp_line=$(printf '%s\n' "$status_out" | grep '^compiled:' | head -n 1 || true)
    done_n=0 total=0 pct=0
    if [ -n "$comp_line" ]; then
      # Format: compiled: <done> / <total> files (<pct>%)
      rest=${comp_line#compiled: }
      done_n=${rest%% / *}
      rest=${rest#* / }
      total=${rest%% files*}
      pct=${rest#*(}
      pct=${pct%\%*}
    fi

    if [ -t 1 ]; then
      printf '\033[H\033[2J'
    else
      printf '\n--- %s ---\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    fi
    draw_board
    draw_progress_bar "$pct" "$done_n" "$total"
    printf '========================================================================\n'
    printf '%s\n' "$status_out"
    printf '\n[Updated %s | refreshing every %ss | Ctrl-C detaches monitor only; stop build with: bash 3_stop.sh]\n' \
      "$(date '+%H:%M:%S')" "$STATUS_INTERVAL"

    sleep "$STATUS_INTERVAL"
  done

  trap - INT TERM

  # Wait briefly for build_result.txt to finish flushing if the process just exited.
  for _ in 1 2 3; do
    [ -f "$OUT/build_result.txt" ] && break
    sleep 1
  done

  if [ -f "$OUT/build_result.txt" ] && grep -q '^build_main: OK' "$OUT/build_result.txt" 2>/dev/null; then
    S3="done ($(fmt_dur $(($(date +%s) - t0))))"
  else
    S3="FAILED"
    echo
    draw_board
    [ -f "$OUT/build_result.txt" ] && cat "$OUT/build_result.txt"
    if [ -f "$OUT/build_main.log" ]; then
      echo
      echo "--- Last 25 lines of $OUT/build_main.log ---"
      tail -n 25 "$OUT/build_main.log"
    fi
    die "Step 3 (3_build_main.sh) did not succeed. Fix and rerun: bash run_all.sh"
  fi
fi

# ---- Step 4: Check -------------------------------------------------------------
S4="running"
echo
draw_board
t0=$(date +%s)
if bash ./4_check.sh; then
  S4="done ($(fmt_dur $(($(date +%s) - t0))))"
else
  S4="FAILED"
  echo
  draw_board
  die "Step 4 (4_check.sh) failed."
fi

# ---- Step 5: Report ------------------------------------------------------------
S5="running"
echo
draw_board
t0=$(date +%s)
if bash ./6_report.sh; then
  S5="done ($(fmt_dur $(($(date +%s) - t0))))"
else
  S5="FAILED"
  echo
  draw_board
  die "Step 5 (6_report.sh) failed."
fi

# ---- Final Summary -------------------------------------------------------------
echo
draw_board
if [ -f "$OUT/check_summary.txt" ]; then
  verdict=$(grep '^OVERALL:' "$OUT/check_summary.txt" | head -n 1 || true)
  [ -n "$verdict" ] && printf '  Verdict: %s\n' "$verdict"
fi
printf '  Report : %s/REPORT.md\n' "$OUT"
printf '========================================================================\n'
replay_instructions
