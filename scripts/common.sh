# common.sh: shared settings and helpers. Every step sources this; don't run it directly.
# Written for macOS (M-series MacBook, 16 GB RAM) but also works on Linux.

set -euo pipefail

# ---- settings you might change -------------------------------------------------
WORK="${WORK:-$HOME/rh}"     # everything goes here (needs roughly 60+ GB free)
# How many Lean files compile at once. Each one can use several GB of RAM, so on a
# 16 GB Mac the default is 4. Lower it if the Mac starts swapping heavily.
JOBS="${JOBS:-}"

# ---- the published archive -----------------------------------------------------
BASE_URL="https://alpo.ge/lean.tar.gz.part"
NPARTS=14
EXPECTED_SHA="9631b4f020199e580ba86178cb56c6e9b09f690c2369a80dc4334aa93f49c7fc"
EXPECTED_BYTES=239275554

DL="$WORK/download"     # untrusted archive
PROJ="$WORK/lean"       # untrusted project tree (extracted)
OUT="$WORK/out"         # our logs and results
[ -d "$DL" ] && [ -d "$OUT" ] || mkdir -p "$DL" "$OUT"

# ---- helpers -------------------------------------------------------------------
log()  { printf '\n==> %s\n' "$*"; }
die()  { printf '\nFAIL: %s\n' "$*" >&2; exit 1; }
rh_os= rh_os_ok=; is_mac(){ [ -n "$rh_os_ok" ] || { rh_os=$(uname) || :; rh_os_ok=1; }; [ "$rh_os" = Darwin ]; }  # uname cached
rh_cpu= rh_cpu_st=; rh_get_cpu(){ rh_cpu=$(r=0; sysctl -n hw.ncpu || r=$?; echo .; exit $r) && rh_cpu_st=0 || rh_cpu_st=$?; }; cores(){ if is_mac; then if [ -n "$rh_cpu_st" ]; then printf '%s' "${rh_cpu%.}"; return "$rh_cpu_st"; fi; sysctl -n hw.ncpu; else nproc; fi; }  # raw sysctl output cached (sentinel keeps trailing newlines)
rh_mem= rh_mem_ok=; rh_get_mem(){ rh_mem=$(sysctl -n hw.memsize); }; ram_gb(){ if is_mac; then local m=$rh_mem; [ -n "$rh_mem_ok" ] || m=$(sysctl -n hw.memsize) || :; echo $(( $m / 1073741824 )); else awk '/MemTotal/{printf "%d", $2/1048576}' /proc/meminfo; fi; }  # memsize cached
free_gb(){ df -k "$WORK" | awk 'NR==2{printf "%d", $4/1048576}'; }
sha()  { local s r=0; if command -v sha256sum >/dev/null; then s=$(sha256sum "$1") || r=$?; else s=$(shasum -a 256 "$1") || r=$?; fi; case $s in '') ;; *$'\n'*) printf '%s\n' "$s" | cut -d' ' -f1 ;; *) printf '%s\n' "${s%% *}" ;; esac; return $r; }
fsize(){ local n r=0; n=$(wc -c < "$1") || r=$?; [ -z "$n" ] || printf '%s\n' "${n// /}"; return $r; }

need_proj(){ [ -f "$PROJ/lean-toolchain" ] || die "project not downloaded yet; run 1_preflight.sh first"; }
elan_env(){
  if [ -f "$HOME/.elan/env" ]; then . "$HOME/.elan/env"; fi
  command -v lake >/dev/null || die "Lean is not installed yet; run 2_setup.sh first"
}

default_jobs(){
  local j=$(( $(ram_gb) / 4 )); local c; c=$(cores)
  [ "$j" -lt 1 ] && j=1
  [ "$j" -gt "$c" ] && j=$c
  echo "$j"
}
[ -n "$JOBS" ] || { if is_mac; then rh_get_mem && rh_mem_ok=1 || rh_mem_ok=2; case $rh_mem in *[!0-9]*|0?*|'') ;; *) [ ${#rh_mem} -gt 18 ] || rh_get_cpu ;; esac; fi; JOBS=$(default_jobs); [ "$rh_mem_ok" != 2 ] || rh_mem_ok=; [ "$rh_cpu_st" = 0 ] || rh_cpu_st=; }  # fetch sysctl values in the parent so default_jobs and later calls reuse them; failed results are used once only

# Run the calling script in the background so it survives closing Terminal, and
# keep the Mac awake with caffeinate. Call as: run_detached <name> "$0"
run_detached(){
  local name="$1" script="$2" pidf="$OUT/$1.pid"
  if [ -f "$pidf" ] && kill -0 "$(cat "$pidf")" 2>/dev/null; then
    die "$name is already running (PID $(cat "$pidf")). Check progress with: bash 3_status.sh"
  fi
  if [ "${RH_FOREGROUND:-0}" = 1 ]; then echo $$ > "$pidf"; return 0; fi
  local keep=""
  if command -v caffeinate >/dev/null; then keep="caffeinate -ims"; fi
  # shellcheck disable=SC2086
  RH_FOREGROUND=1 nohup $keep bash "$script" >> "$OUT/$name.nohup" 2>&1 &
  sleep 2
  echo "Started $name in the background."
  echo "  progress:  bash 3_status.sh"
  echo "  live log:  tail -f $OUT/$name.log"
  echo "  stop:      bash 3_stop.sh   (safe; rerunning picks up where it left off)"
  echo "Keep the Mac plugged in with the lid open. Closing the lid still sleeps it."
  exit 0
}
