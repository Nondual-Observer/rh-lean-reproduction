#!/usr/bin/env bash
# 5_replay.sh: OPTIONAL and also long. Re-checks the compiled proof in Lean's
# kernel with leanchecker (built into Lean since v4.28; this project pins v4.33.1).
# It catches "environment hacking": a metaprogram slipping a declaration in
# without the kernel checking it. Runs in the background like step 3; watch with
# 3_status.sh, stop with 3_stop.sh.
#
#   default:   bash 5_replay.sh          parallel, re-checks every compiled module
#   strongest: FRESH=1 bash 5_replay.sh  replays everything Main depends on into a
#              fresh environment. Single-threaded: expect it to be much slower.
if [ "${RH_FOREGROUND:-0}" = 1 ]; then
  exec 3< <(date; exec date +%s)
fi
case $0 in */*) _d=${0%/*}; cd "${_d:-/}" ;; esac
mkdir() {
  if [ "$#" = 3 ] && [ "$1" = -p ] && [ -d "$2" ] && [ -d "$3" ]; then
    return 0
  fi
  command mkdir "$@"
}
. ./common.sh
unset -f mkdir
need_proj; elan_env
_script="$PWD/5_replay.sh"
cd "$PROJ"
if [ "${RH_FOREGROUND:-0}" = 1 ]; then
  command -v leanchecker >/dev/null 2>&1 || lake env which leanchecker >/dev/null 3<&- \
    || die "leanchecker not found in this toolchain ($(< "$PROJ/lean-toolchain"))"
else
  command -v leanchecker >/dev/null 2>&1 || lake env which leanchecker >/dev/null \
    || die "leanchecker not found in this toolchain ($(< "$PROJ/lean-toolchain"))"
fi

run_detached replay "$_script"

# ---- everything below runs in the background -----------------------------------
exec >> "$OUT/replay.log" 2>&1
IFS= read -r _now <&3 || :
if [ "${FRESH:-0}" = 1 ]; then
  echo "=== replay (fresh, single-threaded) started $_now ==="
  cmd=(lake env leanchecker --fresh Main)
else
  echo "=== replay (parallel, all modules) started $_now ==="
  cmd=(lake env leanchecker)
fi
res="$OUT/replay_result.txt"
if LEAN_NUM_THREADS="$JOBS" "${cmd[@]}" 3<&-; then
  IFS= read -r start <&3 || :
  exec 3<&-
  if { [ ! -e "$res" ] && [ ! -L "$res" ] && [ -w "$OUT" ]; } || { [ -f "$res" ] && [ -w "$res" ]; }; then
    rm -f "$OUT/replay.pid" &
    _rm=$!
    _end=$(date +%s)
    msg="replay: OK (${cmd[*]}) in $(( (_end - start) / 60 )) min"
    printf '%s\n' "$msg" > "$res"
    printf '%s\n' "$msg"
    wait "$_rm"
    exit $?
  fi
  msg="replay: OK (${cmd[*]}) in $(( ($(date +%s) - start) / 60 )) min"
  echo "$msg" | tee "$res"
  exec rm -f "$OUT/replay.pid"
else
  exec 3<&-
  msg="replay: FAILED (${cmd[*]}; see $OUT/replay.log)"
  if { [ ! -e "$res" ] && [ ! -L "$res" ] && [ -w "$OUT" ]; } || { [ -f "$res" ] && [ -w "$res" ]; }; then
    printf '%s\n' "$msg" > "$res"
    printf '%s\n' "$msg"
  else
    echo "$msg" | tee "$res"
  fi
  exec rm -f "$OUT/replay.pid"
fi
