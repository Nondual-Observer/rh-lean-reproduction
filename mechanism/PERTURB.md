# The m-perturbation experiment: where is √x load-bearing?

**Question.** The trace (TRACE.md sections 12 to 15) says m ≈ √x is a *chosen* literal in `RankVal`, and that only the balance x/m + m needs it. If that is right, raising m should break only the size windows that feed the balance, plus hardcoded numbers that a rescaling repairs. If the arithmetic side (Bloch–Kato counts, divisibility, the theta lifts) needed m ≤ √x for its own reasons, we would see real failures there. Lean can decide this: patch the literal, rebuild, and read the errors.

## Design (Variant A)

| Quantity | Original window (`RankVal`) | Patched window | Why |
|---|---|---|---|
| m | √(x·δ1) ≤ m ≤ 2√(x·δ1) | √(x·δ1)·x^(1/40) ≤ m ≤ 2·√(x·δ1)·x^(1/40) | m ≈ x^0.525 |
| k | x^(9/2+10ε) ≤ k ≤ 2x^(9/2+10ε) | x^(37/8+10ε) ≤ k ≤ 2x^(37/8+10ε) | keeps the m⁵ word count k ≳ m⁵·n (section 12) |
| n | x^(2+8ε) ≤ n ≤ 2x^(2+8ε) | unchanged | n is set by the host frame, outside `RankVal` |

Every *lower* bound gets stronger, so proofs that only use lower bounds compile unchanged. What can break is any proof that needs m or k to be at most their old sizes. δ = 1/40 is a fixed constant, so for small ε it exceeds every ε-sized slack in the windows.

The constructor `exists_ranks_rankVal_frame` is patched to pick m and k in the new windows; its new proof uses only the bounds m ≤ 2x² and k ≥ x⁴. Files: `scripts/perturb/perturb_patch.py` (apply / revert, with `.orig` backups), `scripts/10_perturb.sh` (apply / build / report / revert), `scripts/perturb/perturb_report.py`.

## Prediction (written before running, 20 Nov, 21:10 local)

Arithmetic at the exponent level (m = x^(1/2+δ), n = x^(2+8ε), k = x^(9/2+5δ+10ε)):

| Constraint | Holds after the patch? | Expected failure |
|---|---|---|
| m ≥ x^(1/2−ε) (`winL`) | yes | none |
| **m ≤ x^(1/2+ε/2) (`winA`)** | **no** (δ > ε/2) | **WINDOW**: the balance's T3, the "+m" side |
| x·m ≤ k (`winB`) | yes | none |
| **k ≤ n²·x^(1/2−ε) (`winM`, from `k_up`)** | **no** for 5δ > 5ε | **WINDOW**: T4, because n was not raised (Variant B would raise n by x^(5δ)) |
| k ≳ m⁵·f·L (word count) | yes, by construction | LITERAL failures only: `m_pow_five_mul_f_mul_L_le` states the old bound 128·x^(9/2+9ε) |
| n ≤ 2x^(9/4) (`n_le'`) and other crude bounds | yes | none |

**Expected first round.** Up to about 25 modules downstream of `RankVal` mention the old m bound or the literal exponent 9/2 + 10ε (mostly in `Proofs/GlobalInterpolation`, the size bookkeeping: `MPowFiveMulFMulLLe`, `SzRow*`, `ExistsExplicitParameters`, `DimVRowPos`, `WindowLower`, …). We expect them to fail as **LITERAL**: a rescaled exponent makes each one true again. Several rounds of "patch the literal, rerun" are expected before the windows are reached.

**The claim under test.** After the literal failures are repaired, the **only** remaining failures are `winA` and `winM`, i.e. the size windows of the balance. Any failure classified **REAL** (false at the new exponent, in the arithmetic or automorphic layers) would contradict section 12 and would be the more interesting result.

## Results

(Not run yet. Each round is recorded here: modules rebuilt, first-layer failures, classification, and the patch used to repair each LITERAL.)
