#!/usr/bin/env python3
"""perturb_patch.py: Variant A of the m-perturbation experiment.

Variant A0: loosens only the UPPER bound on m in RankVal, so m may be as large as
2*sqrt(x*delta1)*x^(1/40) (m ~ x^0.525). The lower bound on m and both bounds on n
and k are unchanged word for word. The constructor picks m at the new, larger size.
A proof fails exactly when it needs m <~ sqrt(x) (or, through the word count,
k >~ m^5 n, which is now false for the objects built: an expected COUPLING failure).
Also pre-fixes one certain LITERAL: rank_basic_bounds used m <= x^0.501 for crude
bounds (m <= x, N(m) <= x^402); it now uses m <= x^0.527, and its conjunct 17
restates the loosened window. None of its users takes conjunct 17.

  python3 -I perturb_patch.py apply  <src_dir>   # writes .orig backups first
  python3 -I perturb_patch.py revert <src_dir>   # restores the .orig files

<src_dir> is the project's source root (the folder that contains Main.lean).
"""
import os, shutil, sys

RANKVAL = "Development/AbelianVarietyTheory/Definitions/GlobalTwisting/PairRowIffQdRows.lean"
FRAME = "Development/AbelianVarietyTheory/Proofs/GlobalInterpolation/ExistsRanksRankValFrame.lean"
BASIC = "Development/AbelianVarietyTheory/Proofs/GlobalInterpolation/ExplicitRanksBasicBoundsLargeScale.lean"

EDITS = {
    RANKVAL: [
        ("  (Real.sqrt (s.x * s.delta1) ≤ (R.m : ℝ) ∧ (R.m : ℝ) ≤ 2 * Real.sqrt (s.x * s.delta1)) ∧\n"
         "  (s.x ^ (9 / 2 + 10 * s.eps) ≤ (R.k : ℝ) ∧ (R.k : ℝ) ≤ 2 * s.x ^ (9 / 2 + 10 * s.eps)) ∧",
         "  (Real.sqrt (s.x * s.delta1) ≤ (R.m : ℝ) ∧\n"
         "    (R.m : ℝ) ≤ 2 * (Real.sqrt (s.x * s.delta1) * s.x ^ (1 / 40 : ℝ))) ∧\n"
         "  (s.x ^ (9 / 2 + 10 * s.eps) ≤ (R.k : ℝ) ∧ (R.k : ℝ) ≤ 2 * s.x ^ (9 / 2 + 10 * s.eps)) ∧"),
    ],
    FRAME: [
        ("  obtain ⟨m, hm, hm1, hm2⟩ := exists_even_between _ hA1\n"
         "  obtain ⟨k, hk, hk1, hk2⟩ := exists_even_between (s.x ^ (9 / 2 + 10 * s.eps)) (by linarith)",
         "  have hxd1 : (1 : ℝ) ≤ s.x ^ (1 / 40 : ℝ) := Real.one_le_rpow hx1 (by norm_num)\n"
         "  have hxd2 : s.x ^ (1 / 40 : ℝ) ≤ s.x := by\n"
         "    have h := Real.rpow_le_rpow_of_exponent_le hx1 (show (1 / 40 : ℝ) ≤ 1 by norm_num)\n"
         "    rwa [Real.rpow_one] at h\n"
         "  have hsq0 : 0 ≤ Real.sqrt (s.x * s.delta1) := Real.sqrt_nonneg _\n"
         "  have hA1' : 2 ≤ Real.sqrt (s.x * s.delta1) * s.x ^ (1 / 40 : ℝ) := by nlinarith\n"
         "  have hA2' : Real.sqrt (s.x * s.delta1) * s.x ^ (1 / 40 : ℝ) ≤ s.x ^ 2 := by\n"
         "    calc Real.sqrt (s.x * s.delta1) * s.x ^ (1 / 40 : ℝ) ≤ s.x * s.x :=\n"
         "          mul_le_mul hA2 hxd2 (by linarith) hx0.le\n"
         "      _ = s.x ^ 2 := by ring\n"
         "  obtain ⟨m, hm, hm1, hm2⟩ := exists_even_between _ hA1'\n"
         "  obtain ⟨k, hk, hk1, hk2⟩ := exists_even_between (s.x ^ (9 / 2 + 10 * s.eps)) (by linarith)\n"
         "  have hm1o : Real.sqrt (s.x * s.delta1) ≤ (m : ℝ) := le_trans (le_mul_of_one_le_right hsq0 hxd1) hm1"),
        ("  exact ⟨R, rfl, ⟨he1, hp2⟩, ⟨hm1, hm2⟩, ⟨hk1, hk2⟩, hR⟩",
         "  exact ⟨R, rfl, ⟨he1, hp2⟩, ⟨hm1o, hm2⟩, ⟨hk1, hk2⟩, hR⟩"),
    ],
    BASIC: [
        ("∧ (R.m : ℝ) ≤ 2 * s.x ^ ((1 : ℝ) / 2 - s.eps / 16) := by",
         "∧ (R.m : ℝ) ≤ 2 * (s.x ^ ((1 : ℝ) / 2 - s.eps / 16) * s.x ^ (1 / 40 : ℝ)) := by"),
        ("  have hmu : (R.m : ℝ) ≤ s.x ^ ((501 : ℝ) / 1000) := by\n"
         "    have := ab (C := 2) (a := 1 / 2 - s.eps / 16) (b := 501 / 1000) (by norm_num) (by linarith)\n"
         "    linarith",
         "  have hmu : (R.m : ℝ) ≤ s.x ^ ((527 : ℝ) / 1000) := by\n"
         "    have e : s.x ^ ((1 : ℝ) / 2 - s.eps / 16) * s.x ^ (1 / 40 : ℝ) =\n"
         "        s.x ^ ((1 : ℝ) / 2 - s.eps / 16 + 1 / 40) := (Real.rpow_add hxp _ _).symm\n"
         "    have := ab (C := 2) (a := 1 / 2 - s.eps / 16 + 1 / 40) (b := 527 / 1000) (by norm_num) (by linarith)\n"
         "    rw [e] at hm2\n"
         "    linarith"),
    ],
}


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("apply", "revert"):
        sys.exit(__doc__)
    mode, src = sys.argv[1], sys.argv[2]
    if not os.path.isfile(os.path.join(src, "Main.lean")):
        sys.exit(f"{src} does not contain Main.lean")
    for rel, edits in EDITS.items():
        path = os.path.join(src, rel)
        orig = path + ".orig"
        if mode == "revert":
            if os.path.exists(orig):
                shutil.copy2(orig, path)
                print("restored", rel)
            continue
        if not os.path.exists(orig):
            shutil.copy2(path, orig)
        text = open(orig, encoding="utf-8").read()
        for old, new in edits:
            if text.count(old) != 1:
                sys.exit(f"{rel}: expected exactly one match for an edit, found {text.count(old)}; nothing changed in this file")
            text = text.replace(old, new)
        open(path, "w", encoding="utf-8").write(text)
        print("patched", rel)


if __name__ == "__main__":
    main()
