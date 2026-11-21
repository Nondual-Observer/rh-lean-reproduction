#!/usr/bin/env bash
# 9_dead_code.sh: count exactly how much of the project the RH proof uses.
#
#   bash 9_dead_code.sh [path/to/used_decls.txt.gz]
#
# Needs: the finished build (Main.olean present) and used_decls.txt.gz from export_decls.py.
# Step 1 loads the compiled project (reads oleans only, no re-elaboration) and lists every
# constant each project module defines. Step 2 compares that list with used_decls.
# Run it AFTER the build finishes: loading the whole project at once takes a lot of memory.
cd "$(dirname "$0")"; . ./common.sh
need_proj
HERE="$(pwd)"

USED="${1:-}"
if [ -z "$USED" ]; then
  for c in "$HERE/used_decls.txt.gz" "$HOME/used_decls.txt.gz" "$DL/used_decls.txt.gz" "$HERE/used_decls.txt" "$HOME/used_decls.txt"; do
    [ -s "$c" ] && { USED="$c"; break; }
  done
fi
[ -n "$USED" ] && [ -s "$USED" ] || die "used_decls.txt(.gz) not found. Pass its path: bash 9_dead_code.sh /path/to/used_decls.txt.gz"
[ -d "$PROJ/src" ] || die "no src folder in $PROJ"
[ -f "$PROJ/.lake/build/lib/lean/Main.olean" ] || die "Main.olean is missing: wait for the build to finish."
for f in ListDecls.lean compare_dead.py; do [ -s "$HERE/$f" ] || die "$f is missing next to this script."; done

OUT="$HERE/dead_code"; mkdir -p "$OUT"

log "Step 1: list every constant in the project's modules"
if [ -s "$OUT/all_decls.tsv.gz" ]; then
  echo "already done: $OUT/all_decls.tsv.gz"
else
  TIMER=""; [ -x /usr/bin/time ] && TIMER="/usr/bin/time -v"
  ( cd "$PROJ" && $TIMER lake env lean --run "$HERE/ListDecls.lean" ) \
      > "$OUT/all_decls.tsv" 2> "$OUT/listdecls.log" || { tail -20 "$OUT/listdecls.log"; die "ListDecls failed (log: $OUT/listdecls.log)"; }
  grep -E "project modules|Maximum resident|Elapsed" "$OUT/listdecls.log"
  gzip -f "$OUT/all_decls.tsv"
fi

log "Step 2: compare with $USED"
python3 -I "$HERE/compare_dead.py" "$OUT/all_decls.tsv.gz" "$USED" "$PROJ/src" "$OUT" | tee "$OUT/report.txt"

log "Done"
echo "Download these:"
ls -la "$OUT"/report.txt "$OUT"/modules.tsv "$OUT"/dead_modules.txt "$OUT"/unused_named.txt.gz "$OUT"/all_decls.tsv.gz
