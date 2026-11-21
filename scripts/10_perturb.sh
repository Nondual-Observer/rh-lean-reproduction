#!/usr/bin/env bash
# 10_perturb.sh: the m-perturbation experiment (Variant A).
#
# Moves the chain length from m ~ sqrt(x) to m ~ x^(1/2 + 1/40) in RankVal (and k up
# by x^(1/8) so the m^5 word count still fits), rebuilds what depends on it, and lists
# exactly which proofs break. See mechanism/PERTURB.md for the design and the prediction.
#
# Run ONLY after the receipts are done (4_check, 6_report, 7_compare, 9_dead_code):
# this changes two source files and rebuilds about 13,000 modules in place.
#
#   bash 10_perturb.sh apply     # back up and patch the two files
#   bash 10_perturb.sh build     # rebuild in the background; failures do not stop other jobs
#   bash 10_perturb.sh report    # write out/perturb_report.txt from the build log
#   bash 10_perturb.sh revert    # restore the original files (a rebuild then restores the oleans)
cd "$(dirname "$0")"; . ./common.sh
need_proj
SRC="$PROJ/src"; [ -f "$SRC/Main.lean" ] || SRC="$PROJ"
LOGF="$OUT/perturb_build.log"

case "${1:-}" in
  apply)
    [ -f "$OUT/build_result.txt" ] && grep -q "OK" "$OUT/build_result.txt" || die "the main build has not finished OK yet"
    python3 -I "$PWD/perturb/perturb_patch.py" apply "$SRC"
    echo "Patched. Next: bash 10_perturb.sh build"
    ;;
  build)
    elan_env
    run_detached perturb_build "$PWD/10_perturb.sh"
    ;;
  report)
    [ -f "$LOGF" ] || die "no perturb build log yet"
    python3 -I "$PWD/perturb/perturb_report.py" "$LOGF" "$SRC" > "$OUT/perturb_report.txt"
    cat "$OUT/perturb_report.txt"
    ;;
  revert)
    python3 -I "$PWD/perturb/perturb_patch.py" revert "$SRC"
    echo "Reverted. Run bash 3_build_main.sh to rebuild the original oleans if you need them."
    ;;
  "")
    # background part of `build` (run_detached re-enters with no argument)
    run_detached perturb_build "$PWD/10_perturb.sh"   # in the background copy this only records the PID
    elan_env
    cd "$PROJ"
    export LEAN_NUM_THREADS="$JOBS"
    echo "=== perturb build started $(date) ===" >> "$LOGF"
    if lake build Main >> "$LOGF" 2>&1; then echo "perturb_build: everything compiled" > "$OUT/perturb_result.txt"
    else echo "perturb_build: finished with failures (expected); run: bash 10_perturb.sh report" > "$OUT/perturb_result.txt"; fi
    rm -f "$OUT/perturb_build.pid"
    ;;
  *) die "usage: bash 10_perturb.sh apply|build|report|revert" ;;
esac
