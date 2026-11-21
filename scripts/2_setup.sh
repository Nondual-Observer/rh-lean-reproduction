#!/usr/bin/env bash
# 2_setup.sh: install Lean at the pinned version, download prebuilt Mathlib,
# build the 16-line Statements file. About 10 to 20 minutes, mostly downloading.
cd "$(dirname "$0")"; . ./common.sh
need_proj

log "Installing elan (Lean's version manager)"
if [ ! -x "$HOME/.elan/bin/elan" ]; then
  curl -sSf https://elan.lean-lang.org/elan-init.sh | sh -s -- -y --default-toolchain none
else
  echo "elan already installed"
fi
elan_env

cd "$PROJ"
# Read lean-toolchain with builtins (same text as $(cat ...): trailing newlines
# stripped); fall back to cat for missing/unreadable files so errors match.
# read -d '' succeeds only if it hits a NUL byte; $(cat) drops NULs (and bash 5
# warns), so use cat for that rare case too to keep identical output.
if [ -f lean-toolchain ] && [ -r lean-toolchain ]; then
  if IFS= read -r -d '' lean_tc < lean-toolchain; then
    lean_tc=$(cat lean-toolchain) || true
  else
    nl=$'\n'
    while [ "${lean_tc%"$nl"}" != "$lean_tc" ]; do lean_tc=${lean_tc%"$nl"}; done
  fi
else
  lean_tc=$(cat lean-toolchain) || true
fi
log "Installing the pinned Lean version ($lean_tc)"
lean --version

log "Downloading prebuilt Mathlib (several GB)"
lake exe cache get

log "Building Statements (quick sanity check)"
LEAN_NUM_THREADS="$JOBS" lake build Statements 2>&1 | tee "$OUT/build_statements.log"

echo
echo "Setup done. Disk free: $(free_gb) GB."
echo "Next: bash 3_build_main.sh   (the long one; runs in the background)"
