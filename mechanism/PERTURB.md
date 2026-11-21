# The m-perturbation experiment: where is √x load-bearing?

**Question.** The trace (TRACE.md sections 12 to 15) says m ≈ √x is a *chosen* literal in `RankVal`, and that only the balance x/m + m needs it. If that is right, raising m should break only the size windows that feed the balance, plus hardcoded numbers that a rescaling repairs. If the arithmetic side (Bloch–Kato counts, divisibility, the theta lifts) needed m ≤ √x for its own reasons, we would see real failures there. Lean can decide this: patch the literal, rebuild, and read the errors.

## Design (Variant A0: loosen the upper bound on m only)

| Quantity | Original window (`RankVal`) | Patched window |
|---|---|---|
| m | √(x·δ1) ≤ m ≤ 2√(x·δ1) | √(x·δ1) ≤ m ≤ **2·√(x·δ1)·x^(1/40)** (the constructor picks m ≈ x^0.525) |
| n, k | unchanged | unchanged |

The lower bound on m and all bounds on n and k are unchanged **word for word**, so proofs that use only those (including the many that restate them with explicit types) compile as before. **A proof fails exactly when it needs m ≲ √x.** One certain LITERAL is pre-fixed: `rank_basic_bounds` used m ≤ x^0.501 only for crude bounds (m ≤ x, N(m) ≤ x^402); it now uses m ≤ x^0.527, and its conjunct 17 restates the loosened window. None of its five users takes conjunct 17 (Exact: read).

Files: `scripts/perturb/perturb_patch.py` (apply / revert, with `.orig` backups; 3 files), `scripts/10_perturb.sh`, `scripts/perturb/perturb_report.py`.

**Design history (before running).** A first draft also raised every lower bound; reading the consumers showed that dozens of proofs restate the old lower bounds with explicit types, so they would fail as noise. A second draft also raised k by x^(1/8) to keep the word count; reading `rank_basic_bounds` showed that k's polynomial bookkeeping is tuned to ε < 1/52 (for example r ≤ x^4.694 against k ≤ 2x^(9/2+10ε)), so it would set off a cascade of exponent failures unrelated to √x.

## A structural fact found while designing (Exact arithmetic from the stated windows)

m and k are locked together by the m⁵ word count. With k fixed, `m_pow_five_mul_f_mul_L_le` (m⁵·f·L ≤ 128·x^(9/2+9ε), against k ≥ x^(9/2+10ε)) leaves m about **x^(0.3ε)** of headroom above √(x·δ1). The balance window `winA` (m ≤ x^(1/2+ε/2)) has x^(ε/2 + ε/16) of headroom. So **m cannot be raised far enough to break the balance window without first breaking the word count**, unless k is raised too. In the construction as written, the word count, not the window, is the first wall a larger m hits.

## Prediction for round 1 (written before running, 20 Nov, 21:25 local)

| Where | Expected | Label |
|---|---|---|
| `szRow_rankSizes` (`SzRowRankSizes.lean`, proves `SizeM` from `RankVal`): m ≤ x^(ε/100)·√(x·δ1) | fails | **WINDOW** (feeds `winA`, the "+m" side of the balance) |
| `m_pow_five_mul_f_mul_L_le` and `sizeKRel_of_rankVal` (k ≳ m⁵·f·L) | fail | **COUPLING** (expected; blocks about 13,000 downstream modules) |
| `rankVal_crude`, `f_mul_r_mul_L_le_pow_fourteen`, `objOn_narrow_iff_scheme` and other crude uses of √(x·δ1) ≤ x | may fail | LITERAL |
| anything in the arithmetic or automorphic layers | not reached in round 1 (blocked behind the word count) | |

**What round 1 can and cannot show.** It can confirm that `SizeM` is where m ≲ √x enters and list every first-layer consumer of the m upper bound. It **cannot** test the arithmetic layers, because they sit behind the word-count failure. Testing them needs Variant A (raise k as well), which means rewriting the size bookkeeping in `GlobalInterpolation` for the new exponents: a multi-round job.

The source-level answer to that question is already in TRACE.md sections 14 to 16 and in the table of consumers read for this design: every consumer of the m upper bound outside `SizeM` uses it only in crude forms (m ≤ x) that survive m ≈ x^0.525.

## Results

(Not run yet. Each round is recorded here: modules rebuilt, first-layer failures, classification, and the patch used to repair each LITERAL.)
