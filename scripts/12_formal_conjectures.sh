#!/usr/bin/env bash
# 12_formal_conjectures.sh: run leanprover-community/riemann-hypothesis#88 (a second Comparator
# setup whose challenge is formal-conjectures' own RH and GRH) against the REAL compiled proof.
#
# The PR says what it has not checked:
#   * FormalConjecturesSolution.lean has not been compiled against the real Main.lean.
#   * The challenge-export sha256 in the README came from a macOS run; Linux may differ.
# This script closes both, on our finished v4.33.1 build of the published archive.
#
#   bash 12_formal_conjectures.sh            phases A-C (minutes for A-B, hours for C's export)
#   FULL=1 bash 12_formal_conjectures.sh     also phase D: full `lake comparator` (many hours)
#
# A  fetch the PR's files at its head commit; compile the three files against our build
#    (with -DwarningAsError=true, as CI does); #print axioms on the two theorems
# B  step 1b: export the challenge from a clean formal-conjectures clone at the pinned commit
#    and compare its sha256 with the README's value
# C  step 3b's export of the solution, then con-leche --compare (branch compare, 5dc36dc1),
#    the fast independent statement matcher Sutherland used
# D  step 4b: lake comparator with the PR's comparator.json (Lean v4.36.0, no sandbox; both
#    exports are made here from files we trust)
#
# Writes only under $OUT/fc88 and $WORK/fc88. The project tree gets one new directory,
# formal-conjectures/, outside src/; no existing file or .olean is touched.
cd "$(dirname "$0")"; . ./common.sh
need_proj; elan_env

PR_SHA=c018a709ff1c290dcedd636de32fce34cc7587d4
FC_REV=d8d031d4998c78575159ccab9a7a9e95ce043883
README_CHALLENGE_SHA=75aa4a26e43ba9ea2998ba28ebdec4d72c43b43944e6c333963c4cfeda08c2c1
CONLECHE_PREFIX=5dc36dc1
RAW="https://raw.githubusercontent.com/leanprover-community/riemann-hypothesis/$PR_SHA"
FILES="formal-conjectures/comparator.json formal-conjectures/export-targets.txt formal-conjectures/FormalConjecturesStatement.lean formal-conjectures/FormalConjecturesBridge.lean formal-conjectures/FormalConjecturesSolution.lean"

R="$OUT/fc88"; W="$WORK/fc88"; mkdir -p "$R" "$W"
RES="$R/RESULT.txt"
LIB="$PROJ/.lake/build/lib/lean"
EXPBIN="$WORK/lean4export/.lake/build/bin/lean4export"
FCO="$PROJ/.lake/formal-conjectures"
note(){ echo "$*" | tee -a "$RES"; }

[ -f "$LIB/Main.olean" ] || die "build not finished: $LIB/Main.olean missing"
[ -f "$LIB/Statements.olean" ] || die "$LIB/Statements.olean missing"
[ -x "$EXPBIN" ] || die "lean4export missing; run 8_export_hash.sh once (it builds it)"

run_detached fc88 "$PWD/12_formal_conjectures.sh"
exec >> "$OUT/fc88.log" 2>&1
export LEAN_ABORT_ON_PANIC=1
# leantar unpacks the Mathlib cache with one thread per core; on a large VM that exceeds the
# default limit of 1024 open files ("No file descriptors available (os error 24)").
ulimit -n "$(ulimit -Hn)" 2>/dev/null || ulimit -n 65536 2>/dev/null || true
: > "$RES"
note "12_formal_conjectures.sh  started $(date -u +%FT%TZ)"
note "PR #88 head $PR_SHA; formal-conjectures $FC_REV; project $PROJ"

# ---------------------------------------------------------------- A
log "A. fetch the PR files and compile them against the real build"
for f in $FILES; do
  mkdir -p "$PROJ/$(dirname "$f")"
  curl -sSfL --retry 3 -o "$PROJ/$f" "$RAW/$f" || die "download failed: $f"
  echo "$(sha "$PROJ/$f")  $f"
done | tee "$R/pr_files.sha256"
mkdir -p "$FCO"
cd "$PROJ"
okA=1
for m in FormalConjecturesStatement FormalConjecturesBridge FormalConjecturesSolution; do
  s=$(date +%s)
  if LEAN_PATH="$FCO" lake env lean -DwarningAsError=true --root=formal-conjectures \
       -o "$FCO/$m.olean" "formal-conjectures/$m.lean" > "$R/compile_$m.log" 2>&1; then
    note "A  compile $m: OK ($(( $(date +%s) - s )) s)"
  else
    note "A  compile $m: FAILED (see $R/compile_$m.log)"; okA=0; tail -20 "$R/compile_$m.log"
  fi
done
[ "$okA" = 1 ] || { note "STOP: compile failed"; rm -f "$OUT/fc88.pid"; exit 1; }

cat > "$W/Axioms.lean" <<'EOF'
import FormalConjecturesSolution
#print axioms RiemannHypothesis.riemannHypothesis
#print axioms GRH.generalized_riemann_hypothesis
#check @GRH.generalized_riemann_hypothesis
EOF
LEAN_PATH="$FCO" lake env lean "$W/Axioms.lean" > "$R/axioms.log" 2>&1 || true
cat "$R/axioms.log"
if python3 -I - "$R/axioms.log" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
ax = re.findall(r"depends on axioms: \[([^\]]*)\]", t)
ok = len(ax) == 2 and all(sorted(a.replace(" ", "").split(",")) == ["Classical.choice", "Quot.sound", "propext"] for a in ax)
sys.exit(0 if ok and "sorryAx" not in t else 1)
PY
then
  note "A  #print axioms: both theorems use only propext, Classical.choice, Quot.sound"
else
  note "A  #print axioms: UNEXPECTED, see $R/axioms.log"
fi

# ---------------------------------------------------------------- B
log "B. step 1b: challenge export from formal-conjectures"
FC="$W/formal-conjectures"
if [ ! -d "$FC/.git" ]; then
  git init --quiet "$FC"
  (cd "$FC" && git fetch --quiet --depth 1 https://github.com/google-deepmind/formal-conjectures "$FC_REV" && git checkout --quiet FETCH_HEAD)
fi
[ "$(cd "$FC" && git rev-parse HEAD)" = "$FC_REV" ] || die "formal-conjectures is not at $FC_REV"
if cmp -s "$PROJ/lean-toolchain" "$FC/lean-toolchain"; then note "B  formal-conjectures lean-toolchain = project's"; else note "B  lean-toolchain DIFFERS"; fi
mrev(){ python3 -I -c 'import json,sys;print(next(p["rev"] for p in json.load(open(sys.argv[1]))["packages"] if p["name"]=="mathlib"))' "$1"; }
if [ "$(mrev "$PROJ/lake-manifest.json")" = "$(mrev "$FC/lake-manifest.json")" ]; then note "B  same Mathlib commit $(mrev "$FC/lake-manifest.json")"; else note "B  Mathlib commit DIFFERS"; fi
(cd "$FC" && lake exe cache get > "$R/fc_cache.log" 2>&1 && lake build FormalConjectures.Millennium.RiemannHypothesis > "$R/fc_build.log" 2>&1) \
  || die "formal-conjectures build failed (see $R/fc_build.log)"
# shellcheck disable=SC2046
(cd "$FC" && lake env "$EXPBIN" FormalConjectures.Millennium.RiemannHypothesis \
   -- $(cat "$PROJ/formal-conjectures/export-targets.txt") > "$W/fc-challenge.export")
got=$(sha "$W/fc-challenge.export")
note "B  fc-challenge.export: $(fsize "$W/fc-challenge.export") bytes, sha256 $got"
if [ "$got" = "$README_CHALLENGE_SHA" ]; then note "B  MATCHES the README's sha256 (macOS value holds on Linux)"
else note "B  DIFFERS from the README's sha256 $README_CHALLENGE_SHA"; fi

# ---------------------------------------------------------------- C
log "C. step 3b export of the solution, then con-leche --compare"
[ "$(free_gb)" -ge 80 ] || die "need about 80 GB free for the solution export; have $(free_gb) GB"
cd "$PROJ"
s=$(date +%s)
# shellcheck disable=SC2046
LEAN_PATH="$FCO" lake env "$EXPBIN" FormalConjecturesSolution \
  -- $(cat "$PROJ/formal-conjectures/export-targets.txt") > "$W/fc-solution.export" \
  || die "solution export failed"
note "C  fc-solution.export: $(fsize "$W/fc-solution.export") bytes, sha256 $(sha "$W/fc-solution.export"), $(( $(date +%s) - s )) s"

CL="$W/con-leche"
if [ ! -d "$CL/.git" ]; then git clone --quiet https://github.com/leanprover/con-leche "$CL"; fi
(cd "$CL" && git fetch --quiet origin compare && git checkout --quiet FETCH_HEAD)
c=$(cd "$CL" && git rev-parse HEAD); note "C  con-leche compare branch at $c"
case $c in "$CONLECHE_PREFIX"*) ;; *) note "C  (note: not $CONLECHE_PREFIX, the commit Sutherland used)";; esac
(cd "$CL" && ELAN_TOOLCHAIN=leanprover/lean4:v4.36.0 lake build con-leche > "$R/conleche_build.log" 2>&1) || die "con-leche build failed"
s=$(date +%s)
if "$CL/.lake/build/bin/con-leche" --compare "$W/fc-challenge.export" "$W/fc-solution.export" > "$R/conleche_compare.log" 2>&1; then
  note "C  con-leche --compare: exit 0 ($(( $(date +%s) - s )) s)"
else
  note "C  con-leche --compare: exit $? ($(( $(date +%s) - s )) s), see $R/conleche_compare.log"
fi
grep -i "justified\|accepted\|reject\|error" "$R/conleche_compare.log" | head -20 | tee -a "$RES"

# ---------------------------------------------------------------- D
if [ "${FULL:-0}" = 1 ]; then
  log "D. step 4b: lake comparator (Lean v4.36.0)"
  J="$W/judge"; mkdir -p "$J"; cd "$J"
  echo leanprover/lean4:v4.36.0 > lean-toolchain
  PATH="$(lean --print-prefix)/bin:$PATH"
  s=$(date +%s)
  if lake comparator --inadvisably-no-sandbox --config "$PROJ/formal-conjectures/comparator.json" \
       --challenge-from-export "$W/fc-challenge.export" --solution-from-export "$W/fc-solution.export" \
       > "$R/comparator.log" 2>&1; then
    note "D  lake comparator: exit 0 ($(( $(date +%s) - s )) s)"
  else
    note "D  lake comparator: exit $? ($(( $(date +%s) - s )) s)"
  fi
  tail -5 "$R/comparator.log" | tee -a "$RES"
fi

note "finished $(date -u +%FT%TZ)"
rm -f "$OUT/fc88.pid"
