#!/usr/bin/env bash
# 3_stop.sh: stop the background build or replay. Safe: finished files are kept,
# and rerunning 3_build_main.sh resumes the build.
cd "$(dirname "$0")"; . ./common.sh

nl=$'\n'
later=
for name in build_main replay; do
  pidf="$OUT/$name.pid"
  if [ -f "$pidf" ]; then
    # Read the pid file once with builtins; mimic $(cat f): strip only trailing newlines.
    pid=
    IFS= read -r -d '' pid < "$pidf" || true
    pid=${pid%"${pid##*[!$nl]}"}
    if kill -0 "$pid" 2>/dev/null; then
      echo "Stopping $name (PID $pid)"
      kill "$pid" 2>/dev/null || true
    fi
  fi
  # Skip rm -f when the path is absent inside a searchable $OUT, and batch
  # build_main's rm -f with replay's when both exist in a writable non-sticky $OUT.
  if [ ! -e "$pidf" ] && [ ! -L "$pidf" ] && [ -d "$OUT" ] && [ -x "$OUT" ]; then
    if [ "$name" = replay ] && [ -n "$later" ]; then
      rm -f "$later"
    fi
  elif [ "$name" = build_main ] && [ -f "$pidf" ] && [ -w "$OUT" ] && [ -x "$OUT" ] \
       && [ ! -k "$OUT" ] && [ ! -L "$OUT/replay.pid" ]; then
    later=$pidf
  elif [ -n "$later" ]; then
    rm -f "$later" "$pidf"
  else
    rm -f "$pidf"
  fi
done
pkill -f 'lake build Main' 2>/dev/null || true
pkill -f 'leanchecker' 2>/dev/null || true
pkill -x lean 2>/dev/null || true
pkill -f 'caffeinate -ims bash' 2>/dev/null || true
echo "Stopped. To resume: JOBS=2 bash 3_build_main.sh   (JOBS optional)"
