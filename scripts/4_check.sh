#!/usr/bin/env bash
# 4_check.sh: the verdict. Checks that the proved statement is really Mathlib's
# Riemann Hypothesis and that every headline theorem uses only Lean's 3 standard
# axioms. Needs 3_build_main.sh to have finished. A few minutes.
cd "$(dirname "$0")"; . ./common.sh
need_proj; elan_env
cd "$PROJ"

main_file=$(find . -path ./.lake -prune -o -name Main.lean -print | head -1)
[ -n "$main_file" ] || die "Main.lean not found"
if grep -qE '^[[:space:]]*namespace[[:space:]]' "$main_file"; then
  echo "NOTE: $main_file opens a namespace; theorem names below may need a prefix."
fi
_nl=$'\n' _ws=$' \t' names=
if [[ -f $main_file && -r $main_file ]] && ! IFS= read -r -d '' -n 256 _s < "$main_file"; then
  _rest=$_nl$_s$_nl _found=0
  while [[ $_rest == *theorem* ]]; do
    _pre=${_rest%%theorem*}
    _after=${_rest#*theorem}
    _pre=${_pre##*$_nl}
    if [[ $_pre != *[![:space:]]* && $_after == [[:space:]]* && $_after != $_nl* ]]; then
      _found=1
      _l=$_pre"theorem"${_after%%$_nl*}
      _l=${_l#"${_l%%[!$_ws]*}"}
      _l=${_l#"${_l%%[$_ws]*}"}
      _l=${_l#"${_l%%[!$_ws]*}"}
      names+=${_l%%[$_ws]*}$_nl
    fi
    _rest=$_nl${_after#*$_nl}
  done
  [ "$_found" = 1 ]
else
  _raw=$(grep '^[[:space:]]*theorem[[:space:]]' "$main_file")
  _rest=$_raw$_nl
  while [[ $_rest ]]; do
    _l=${_rest%%$_nl*}
    _rest=${_rest#*$_nl}
    _l=${_l#"${_l%%[!$_ws]*}"}
    _l=${_l#"${_l%%[$_ws]*}"}
    _l=${_l#"${_l%%[!$_ws]*}"}
    names+=${_l%%[$_ws]*}$_nl
  done
fi
while [[ $names == *$_nl ]]; do names=${names%$_nl}; done
case $names in
  ''|[!-]*|-*[!neE]*|-) printf 'Headline theorems in %s:\n  %s\n' "$main_file" "${names//$_nl/$_nl  }" ;;
  -*n*) printf 'Headline theorems in %s:\n' "$main_file" ;;
  *) printf 'Headline theorems in %s:\n  \n' "$main_file" ;;
esac
unset _nl _ws _s _rest _found _pre _after _l _raw

cat > Check.lean <<'LEAN'
import Main

open Lean Elab Command in
run_cmd do
  let env ← getEnv
  -- (a) Where does RiemannHypothesis come from?
  --     Expect: some Mathlib.NumberTheory.LSeries.RiemannZeta
  let m ← findModuleOf? ``RiemannHypothesis
  logInfo m!"STATEMENT-MODULE: {toString m}"
  -- (b) Is the proved theorem's type literally Mathlib's constant? Compared as
  --     terms, so no notation or macro tricks can fake it. Expect: true
  match env.find? `riemannHypothesis with
  | some ci => logInfo m!"STATEMENT-EXACT: {toString (ci.type == mkConst ``RiemannHypothesis)}"
  | none    => logInfo m!"STATEMENT-EXACT: riemannHypothesis not found (namespaced?)"

-- (c) RH written by hand from Mathlib terms only. If this typechecks,
--     the proof proves this exact statement.
theorem myRH : ∀ s : ℂ, riemannZeta s = 0 →
    (¬ ∃ n : ℕ, s = -2 * (n + 1)) → s ≠ 1 → s.re = 1 / 2 := by
  intro s h1 h2 h3
  exact (riemannHypothesis : RiemannHypothesis) s h1 h2 h3

-- (d) Axioms. Clean = exactly propext, Classical.choice, Quot.sound
#print axioms myRH
LEAN
for n in $names; do echo "#print axioms $n" >> Check.lean; done

log "Running Check.lean"
LEAN_NUM_THREADS="$JOBS" lake env lean Check.lean > "$OUT/check_output.txt" 2>&1 || true
cat "$OUT/check_output.txt"

log "Verdict"
python3 -I - "$OUT/check_output.txt" <<'PY' | tee "$OUT/check_summary.txt"
import re, sys
txt = open(sys.argv[1]).read()
allowed = {"propext", "Classical.choice", "Quot.sound"}
problems = 0
mod = re.search(r"STATEMENT-MODULE: (.*)", txt)
exact = re.search(r"STATEMENT-EXACT: (.*)", txt)
print("statement module :", mod.group(1).strip() if mod else "not reported")
print("statement exact  :", exact.group(1).strip() if exact else "not reported")
if not (exact and exact.group(1).strip() == "true"):
    problems += 1
seen = 0
for name, lst in re.findall(r"'([^']+)' depends on axioms: \[([^\]]*)\]", txt, re.S):
    seen += 1
    ax = {a.strip() for a in lst.replace("\n", " ").split(",") if a.strip()}
    extra = ax - allowed
    problems += bool(extra)
    print(f"{'PASS' if not extra else 'FAIL'}  {name}: {', '.join(sorted(ax))}")
for name in re.findall(r"'([^']+)' does not depend on any axioms", txt):
    seen += 1
    print(f"PASS  {name}: (no axioms)")
errs = re.findall(r"error:.*", txt)
if errs:
    problems += 1
    print("Lean errors:", *errs[:5], sep="\n  ")
if seen == 0:
    problems += 1
print("myRH typechecked :", "yes" if "'myRH'" in txt and not errs else "no")
print("OVERALL:", "CLEAN" if problems == 0 else f"PROBLEMS ({problems})")
PY
echo
echo "Next: bash 6_report.sh"
