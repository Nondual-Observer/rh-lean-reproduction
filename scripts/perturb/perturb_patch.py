#!/usr/bin/env python3
"""perturb_patch.py: Variant A of the m-perturbation experiment.

Loosens only the UPPER bounds in RankVal: m may now be as large as
2*sqrt(x*delta1)*x^(1/40) (so m ~ x^0.525) and k as large as 2*x^(37/8 + 10 eps).
Lower bounds are unchanged, word for word, so any proof that uses only lower
bounds compiles as before. The constructor picks m and k at the new, larger
sizes. A proof fails exactly when it needs an upper bound on m or k.
n is NOT changed.

  python3 -I perturb_patch.py apply  <src_dir>   # writes .orig backups first
  python3 -I perturb_patch.py revert <src_dir>   # restores the .orig files

<src_dir> is the project's source root (the folder that contains Main.lean).
"""
import os, shutil, sys

RANKVAL = "Development/AbelianVarietyTheory/Definitions/GlobalTwisting/PairRowIffQdRows.lean"
FRAME = "Development/AbelianVarietyTheory/Proofs/GlobalInterpolation/ExistsRanksRankValFrame.lean"

EDITS = {
    RANKVAL: [
        ("  (Real.sqrt (s.x * s.delta1) ≤ (R.m : ℝ) ∧ (R.m : ℝ) ≤ 2 * Real.sqrt (s.x * s.delta1)) ∧\n"
         "  (s.x ^ (9 / 2 + 10 * s.eps) ≤ (R.k : ℝ) ∧ (R.k : ℝ) ≤ 2 * s.x ^ (9 / 2 + 10 * s.eps)) ∧",
         "  (Real.sqrt (s.x * s.delta1) ≤ (R.m : ℝ) ∧\n"
         "    (R.m : ℝ) ≤ 2 * (Real.sqrt (s.x * s.delta1) * s.x ^ (1 / 40 : ℝ))) ∧\n"
         "  (s.x ^ (9 / 2 + 10 * s.eps) ≤ (R.k : ℝ) ∧ (R.k : ℝ) ≤ 2 * s.x ^ (37 / 8 + 10 * s.eps)) ∧"),
    ],
    FRAME: [
        ("  have hB : s.x ^ 4 ≤ s.x ^ (9 / 2 + 10 * s.eps) := by",
         "  have hB : s.x ^ 4 ≤ s.x ^ (37 / 8 + 10 * s.eps) := by"),
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
         "  obtain ⟨k, hk, hk1, hk2⟩ := exists_even_between (s.x ^ (37 / 8 + 10 * s.eps)) (by linarith)\n"
         "  have hm1o : Real.sqrt (s.x * s.delta1) ≤ (m : ℝ) := le_trans (le_mul_of_one_le_right hsq0 hxd1) hm1\n"
         "  have hk1o : s.x ^ (9 / 2 + 10 * s.eps) ≤ (k : ℝ) :=\n"
         "    le_trans (Real.rpow_le_rpow_of_exponent_le hx1 (by linarith)) hk1"),
        ("  exact ⟨R, rfl, ⟨he1, hp2⟩, ⟨hm1, hm2⟩, ⟨hk1, hk2⟩, hR⟩",
         "  exact ⟨R, rfl, ⟨he1, hp2⟩, ⟨hm1o, hm2⟩, ⟨hk1o, hk2⟩, hR⟩"),
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
