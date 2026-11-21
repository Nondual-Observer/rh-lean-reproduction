#!/usr/bin/env bash
# 8_export_hash.sh: export YOUR compiled proof with lean4export and compare its sha256
# with the published one. Run it AFTER step 3 has finished (Main.olean must exist).
#
# Why this check: the export holds only the kernel declarations (names, types, proofs).
# It does not hold warnings or source paths, so unlike the .olean files it should be
# byte-identical across machines. If your hash equals Sutherland's, an independent build
# reproduced the same 61.6 GB export. That does NOT say the proof is correct (the kernels
# do that); it says the build and export are reproducible.
#
#   bash 8_export_hash.sh              hash only (streams the export; writes no big file)
#   KEEP=1 bash 8_export_hash.sh       also save $OUT/solution.export (about 61.6 GB, needs the disk)
#
# Recipe copied from the Deicyde/riemann-hypothesis README, step 3:
#   lake env lean4export Main -- $(cat export-targets.txt) > solution.export
# with lean4export at tag v4.33.0 (commit 15f6055e), built with Lean v4.33.1.
#
# NOTE: not yet run end to end by the author of this script. Read the log if it stops.
# Runs in the background like step 3. Progress: tail -f $OUT/export_hash.log
cd "$(dirname "$0")"; . ./common.sh
need_proj; elan_env

TARGETS_URL="https://raw.githubusercontent.com/Deicyde/riemann-hypothesis/main/export-targets.txt"
EXPORTER_REPO="https://github.com/leanprover/lean4export"
EXPORTER_TAG="v4.33.0"
EXPORTER_COMMIT_PREFIX="15f6055e"
EXPECTED_EXPORT_SHA="5ea74b912147c5c93cc2b6d70cc727cf908df2f62ac6a20480a3fa02f6be244e"
EXPECTED_EXPORT_BYTES=61570595788
EXP_DIR="$WORK/lean4export"
TARGETS="$DL/export-targets.txt"
KEEP="${KEEP:-0}"

[ -f "$PROJ/.lake/build/lib/lean/Main.olean" ] || die "Main.olean is missing: finish step 3 first."

run_detached export_hash "$PWD/8_export_hash.sh"

# ---- everything below runs in the background -----------------------------------
LOG="$OUT/export_hash.log"
{
  echo "=== export check started $(date) ==="

  log "lean4export $EXPORTER_TAG"
  if [ ! -d "$EXP_DIR/.git" ]; then
    git clone --branch "$EXPORTER_TAG" "$EXPORTER_REPO" "$EXP_DIR"
  fi
  commit=$(git -C "$EXP_DIR" rev-parse HEAD)
  case "$commit" in
    "$EXPORTER_COMMIT_PREFIX"*) echo "exporter commit ok: $commit" ;;
    *) echo "FAIL: exporter commit is $commit, expected $EXPORTER_COMMIT_PREFIX..." ; rm -f "$OUT/export_hash.pid"; exit 1 ;;
  esac
  if [ ! -x "$EXP_DIR/.lake/build/bin/lean4export" ]; then
    (cd "$EXP_DIR" && ELAN_TOOLCHAIN=leanprover/lean4:v4.33.1 lake build)
  fi
  EXPBIN="$EXP_DIR/.lake/build/bin/lean4export"
  [ -x "$EXPBIN" ] || { echo "FAIL: exporter did not build"; rm -f "$OUT/export_hash.pid"; exit 1; }

  log "Export targets"
  [ -s "$TARGETS" ] || curl -fL --retry 5 -o "$TARGETS" "$TARGETS_URL"
  targets_sha=$(sha "$TARGETS")
  echo "targets sha256: $targets_sha"

  log "Exporting Main (single-threaded, can take a long time; no progress output)"
  cd "$PROJ"
  export LEAN_ABORT_ON_PANIC=1
  start=$(date +%s)
  keepfile="-"; [ "$KEEP" = 1 ] && keepfile="$OUT/solution.export"
  # shellcheck disable=SC2046
  res=$(lake env "$EXPBIN" Main -- $(cat "$TARGETS") | python3 -I -c '
import hashlib, sys
h = hashlib.sha256(); n = 0
out = open(sys.argv[1], "wb") if sys.argv[1] != "-" else None
for b in iter(lambda: sys.stdin.buffer.read(1 << 24), b""):
    h.update(b); n += len(b)
    if out: out.write(b)
if out: out.close()
print(h.hexdigest(), n)
' "$keepfile") || { echo "FAIL: export pipeline failed (see lines above)"; rm -f "$OUT/export_hash.pid"; exit 1; }
  secs=$(( $(date +%s) - start ))
  got_sha=${res%% *}; got_bytes=${res##* }

  verdict="DIFFERENT from the published export"
  if [ "$got_sha" = "$EXPECTED_EXPORT_SHA" ] && [ "$got_bytes" = "$EXPECTED_EXPORT_BYTES" ]; then
    verdict="MATCH: byte-identical to the published export"
  fi
  {
    echo "export sha256 (yours)    : $got_sha"
    echo "export sha256 (published): $EXPECTED_EXPORT_SHA"
    echo "export bytes (yours)     : $got_bytes"
    echo "export bytes (published) : $EXPECTED_EXPORT_BYTES"
    echo "VERDICT                  : $verdict"
    echo "lean4export commit       : $commit"
    echo "export-targets.txt sha256: $targets_sha"
    echo "export wall time         : $((secs / 60)) min"
    echo "lean version             : $(cat "$PROJ/lean-toolchain")"
  } | tee "$OUT/export_result.txt"
  echo "=== export check finished $(date) ==="
  rm -f "$OUT/export_hash.pid"
} >> "$LOG" 2>&1
