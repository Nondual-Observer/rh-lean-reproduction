# Reproducing and examining the Lean proof of the Riemann Hypothesis

Ishaan Dixit, 20 November 2026. Work in progress; my build is still running.

On 20 November 2026 Levent Alpöge released a four-page note ([alpo.ge/remark.pdf](https://alpo.ge/remark.pdf)) and a Lean 4 project of 175,187 files and 17.4 million lines that claims to prove the Riemann Hypothesis and the Generalized Riemann Hypothesis for Dirichlet L-functions. Within hours several people had compiled it, and independent kernels (nanoda, con-leche, lean4lean, Pestka, con-agua, nanoclo, tenet) accepted it; see [Andrew Sutherland's page](https://math.mit.edu/~drew/grh/).

This repository is my independent look at the release. It does **not** claim to verify the proof; the kernel checks above do that. What it adds is a set of smaller, checkable facts: about the statement, the structure of the code, the numerical computations inside it, the reproducibility of the build, and how the ideas in the note show up in the code. It also has two interactive pages that explain the structure and the mathematics.

## Summary of findings

| | Finding | Confidence |
|---|---|---|
| 1 | The theorem proves Mathlib's own `RiemannHypothesis`, unchanged at the pinned Mathlib commit, and Mathlib's `riemannZeta` is the usual ζ. | Checked against source |
| 2 | Every one of the 175,187 files is in the import closure of `Main`; nothing is dead at the file level. About 72% of the 1,061,531 declarations are used by the top theorem. | Files: my scan. Declarations: tamnd's index, approximate |
| 3 | No `sorry`, `axiom`, `native_decide`, `unsafe`, `implemented_by`, `extern` or `opaque`. Metaprogramming is small and confined to a few helper files. | Text census; agrees with Deicyde's scan |
| 4 | All the heavy computations the proof asks Lean's kernel to run (124 `decide +kernel` sites) give the claimed results when re-run independently in Python. | Re-run with cross-checks and negative tests |
| 5 | Compiled `.olean` files with no embedded source path match Sutherland's published hashes byte for byte (20,625 of 20,625 so far). Every mismatch carries an absolute source path. | Partial (25% of the build); open question below |
| 6 | Several key words of the note (Stepanov, Guinand–Weil, relative trace formula, Vandiver) never appear in the code, while theta lifts, seesaws and covolumes appear in thousands of files. | Name search only |

## 1. Source and provenance

The 14 parts from alpo.ge join to `lean.tar.gz`: 239,275,554 bytes, sha256 `9631b4f020199e580ba86178cb56c6e9b09f690c2369a80dc4334aa93f49c7fc`, the published values. The project pins Lean v4.33.1 and Mathlib commit `0df444a3`. I also verified the published challenge export (sha256 `bd484ac9…b2b9`) and the hash of Sutherland's manifest of compiled files (`375cbee2…1d25`). Details: `results/hashes.txt`.

## 2. What is proved

`Main.lean` line 4 is `theorem riemannHypothesis : RiemannHypothesis := rhOfAll`, and `RiemannHypothesis` is not redefined anywhere in the project. In Mathlib at the pinned commit (`Mathlib/NumberTheory/LSeries/RiemannZeta.lean`, line 185):

```lean
def RiemannHypothesis : Prop :=
  ∀ (s : ℂ) (_ : riemannZeta s = 0) (_ : ¬∃ n : ℕ, s = -2 * (n + 1)) (_ : s ≠ 1), s.re = 1 / 2
```

The same file proves that `riemannZeta` equals Σ 1/nˢ for Re s > 1 (line 207), has the trivial zeros at −2, −4, … (line 173) and satisfies the functional equation (line 178), so it is the usual ζ. The other four theorems in `Main.lean` concern Dirichlet L-functions. All five follow from one statement the code calls `EveryCharacter`: no Dirichlet L-function has a zero with Re s > ½. The step from there to RH is classical and uses only Mathlib. Details: `results/statement_check.txt`.

## 3. Structure of the code

A text-only import-graph scan (`analysis/reach.py`) finds that all 175,187 files and 17,374,215 lines are reachable from `Main`; the longest import chain is 203 modules, and the only external libraries are Mathlib, Lean and Batteries. This answered a Zulip question about "~400k unreachable lines": at the file level there are none.

At the declaration level the picture is different. Using the declaration index published by [riemann.tamnd.com](https://riemann.tamnd.com) (data CC0), 769,260 of 1,061,531 declarations (72%) are used by `riemannHypothesis`. So roughly 292,000 declarations are compiled but never reached, which may be what the Zulip question was seeing. tamnd's resolver works without Lean, so these counts are close but not exact.

Below `EveryCharacter` the proof runs down a chain of eight short theorems, each a few lines, with the work in large branches hanging off them: a statement about Galois representations attached to automorphic forms (54,225 declarations), a "window bound" on Galois cohomology (56,145), a covolume bound (52,322), and the construction of a 46-field record of hypotheses about unitary groups (89,250 in its largest branch). The interactive map in `visuals/proof-map.html` lays this out.

## 4. Static census

`analysis/census.py` strips comments and strings, then counts constructs across all files (`results/census_summary.txt`). It finds zero `sorry`, `admit`, `axiom`, `native_decide`, `unsafe`, `implemented_by`, `extern` and `opaque`. `partial` occurs twice, both in metaprogramming helper files. There are 4 `elab` declarations in 3 files and 5 `run_cmd` calls, all in `BuildAid`, where each adds one name to a library-suggestion deny list. The `elab` tactics build proof terms that the kernel re-checks, so they cannot make a false proof pass. These results agree with the static scan in [Deicyde/riemann-hypothesis](https://github.com/Deicyde/riemann-hypothesis).

## 5. The proof's numerical computations, re-run independently

Lean checks proofs symbolically and never evaluates ζ. In a few places, though, the proof makes the kernel actually compute something, with `decide +kernel`: 124 call sites in 34 files. I ported each Lean function to Python line by line, keeping Lean's natural-number semantics (truncating subtraction, floor division, x / 0 = 0), ran it, and compared with the claimed result. Where possible I added an independent cross-check, and for each I confirmed that a tampered input fails, so the ports are not vacuous. Scripts: `analysis/kernel-computations/`; output: `results/kernel_computations.txt`.

| Computation | What it does | Result | Used by the RH proof? |
|---|---|---|---|
| `run1`–`run4` | Prime counts in (h/2, h] for h up to 131,072, with an inequality at each step | Pass; counts equal an independent sieve | No |
| `loop_run` | A prime-count bound up to 131,071 | Pass; ends at π(131071) = 12,251 | Yes |
| Three factorial ladders | A lower bound on sums of 1/p, in steps | Pass | Yes |
| `table_ok` | 878 primes in 12 intervals | Pass; every listed number is prime | Yes |
| lcm{1..n} ≤ 3ⁿ (n < 30), ≤ 4ⁿ (n ≤ 100) | Inputs to a ψ estimate | Pass | Yes |
| `BB_disj0` | gcd and divisibility facts for two 12-digit primes | Pass | Yes |
| Five Pratt certificates | Primality, up to a 310-bit prime | Pass; `sympy.isprime` agrees | No |
| Four Lucas certificates and 20 identities | Primality of 63- to 616-bit primes and facts about them | Pass | No |

"Used by the RH proof" comes from tamnd's index and is approximate. Two constants in the cyclotomic file (`d = 599`, `condN = 16·571·599`) were inferred from the file's own identities rather than read from the source; all 24 facts in that file hold with them. A few small finite checks on custom structures were not ported. This confirms the arithmetic and nothing else; the logic is the kernels' job.

## 6. Reproducibility of the build

I built the project with `lake build Main` on a Google Cloud VM (377 GB RAM, 94 parallel jobs), using the scripts in `scripts/`. `scripts/7_compare.sh` hashes every compiled `.olean` and compares it with Sutherland's manifest, whose caveats note that only a 77-module sample of his build had been compared with a real `lake build`.

Partial result (43,717 files, about 25% of the build; `results/olean_comparison_partial.txt`):

| | No source path in file | Source path in file |
|---|---:|---:|
| Identical to manifest | 20,625 | 0 |
| Different | 0 | 23,092 |

The two groups do not overlap. In the one module I examined by hand, the only differing text was the stored source path (`/mnt/rh_ram/lean/src/…` in my build against a relative path in a rebuild), which shifts everything after it. My working explanation is that `.olean` files store messages such as linter warnings, and those carry the absolute path of the build directory, so they cannot match a build made elsewhere.

**Open question.** Jack McCarthy reported on Zulip that two independent builds of his match the sha256 reported by Sutherland's build exactly. If that refers to the per-file hashes, his builds do not embed machine paths, and my explanation needs revisiting (for example, his builds may use a different working directory layout or relative paths). Until that is resolved I treat the path explanation as a hypothesis. The final comparison will be rerun when my build finishes.

`scripts/8_export_hash.sh` will export my build with `lean4export` (v4.33.0, commit `15f6055e`, built and ready) and compare it with the published export hash `5ea74b91…244e`. The export records only kernel declarations, so it should be comparable across machines. My build is not sandboxed, so this does not close the "sandboxed re-export" gap on Sutherland's page.

## 7. The note's vocabulary against the code

The note ends with a 20-step timeline. `analysis/note_terms.py` searches all files for each step's key names, matching whole words in CamelCase identifiers and paths (`results/note_terms.json`). Theta lifts (2,629 files), covolumes (3,670), seesaws (565), Bessel periods (359) and GGP periods (236) are everywhere. **Stepanov, Guinand–Weil, "relative trace formula" and Vandiver never appear**, and "Iwasawa tower or theory" appears in 2 files. So those steps live in the code under other names, or were dropped on the way. A name match is not a semantic match; this is a map for readers, not an analysis of the mathematics.

## 8. Universe levels

`analysis/levels.py` reads a `lean4export` file and reports which universe levels are actually used. On the challenge export (the five statements plus the Mathlib definitions they need) the largest concrete level is 2, that is `Type 1` (`results/levels_challenge_only.txt`). The full proof export is still being scanned. On Zulip, Joël Riou pointed out that the proof uses the derived category of `Shv R : Type 2` over the big étale site, much like the formalization of the Weil conjectures, and that with small sites ZFC should suffice. That is the real answer to the foundations question; my count is only an input to it.

## 9. Interactive pages

Both pages are self-contained; open them in a browser.

- `visuals/proof-map.html`: the structure of the proof. The half-plane that `EveryCharacter` rules out, the eight-theorem trunk with branch sizes, how the declarations split across libraries, the note's 20 steps on a date axis against the name search, and a clearly labelled community reading of the core mechanism.
- `visuals/proof-math.html`: the mathematics, as six interactive plates computed live from real data. (1) ψ(x) − x against Schoenfeld's √x band out to 10⁶. (2) The zeros of ζ and the explicit formula rebuilding the prime staircase, with a slider that moves a zero off the line. (3) How a bound on prime sums clears a half-plane of zeros. (4) RH over finite fields: elliptic-curve point counts inside Hasse's bound for any curve you type. (5) Stepanov's multiplicity trick and its √q balance. (6) The note's chain of about √X theta lifts. Each plate is labelled as established mathematics, from the note, an unverified reading, or schematic. The data for plate 2 comes from `visuals/make_zeta_data.py`.

One small numerical note from building plate 1: the simple form |ψ(x) − x| < √x (log x)² fails for 2 ≤ x < 3 (at x just below 3, ψ = log 2) and holds from x = 3 to 10⁶. Schoenfeld's sharper bound with constant 1/(8π) holds for 73.2 ≤ x ≤ 10⁶, reaching 91.8% of the band.

## 10. What this does not show

- Nothing here checks the logic of the proof. That is done by the independent kernels, and by `lake comparator --paranoid`, which Sutherland expects to finish this weekend.
- The mechanism behind the √X chain of lifts is not understood by anyone yet, me included. The relevant visual is labelled as a reading.
- Declaration-level numbers depend on tamnd's approximate index.
- The `.olean` comparison is partial and has an open question (section 6).

## 11. Related work by others

- [Andrew Sutherland](https://math.mit.edu/~drew/grh/): the main verification record and downloads.
- [Deicyde/riemann-hypothesis](https://github.com/Deicyde/riemann-hypothesis): source mirror, comparator setup, static scan and metaprogramming notes.
- [tamnd/riemann](https://riemann.tamnd.com): a written proof from the top down, with a page per declaration.
- [nasqret/riemann-rev](https://github.com/nasqret/riemann-rev): Bartosz Naskręcki's high-level digest and links.
- [drew2apps/rh-lean-decomposition](https://github.com/drew2apps/rh-lean-decomposition): dominator-tree decomposition of the import graph.
- [kant2002/riemann-hypothesis-supplimentary](https://github.com/kant2002/riemann-hypothesis-supplimentary): folder-level import graph.
- [Infatoshi/rh-verification-receipts](https://github.com/Infatoshi/rh-verification-receipts): an independent build and nanoda run.
- [DevinWatson/rh-weil-bound-toy](https://github.com/DevinWatson/rh-weil-bound-toy): the note's toy finite-field argument.
- [friederrr/riemann-review](https://github.com/friederrr/riemann-review): a pooled AI-written informal write-up.

## 12. Reproduce

```bash
# source, hash check, build (Linux or macOS; see scripts/README.md)
cd scripts && bash run_all.sh
PARTIAL=1 bash 7_compare.sh        # during the build; full run afterwards
bash 8_export_hash.sh              # after the build

# text-only analyses on the extracted source (no code is run)
python3 -I analysis/reach.py ~/rh/lean
python3 -I analysis/census.py ~/rh/lean
python3 -I analysis/note_terms.py ~/rh/lean/src note_terms.json

# kernel computations (needs sympy)
cd analysis/kernel-computations
python3 dyadic.py && python3 certs.py && python3 disjoint.py
python3 more.py ~/rh/lean/src && python3 cyclo.py ~/rh/lean/src
```

## Layout

- `scripts/`: the build pipeline (steps 1 to 6), `7_compare.sh` and `8_export_hash.sh`.
- `analysis/`: `reach.py`, `census.py`, `levels.py`, `note_terms.py`, and `kernel-computations/`.
- `results/`: every output quoted above, with the date it was taken.
- `visuals/`: the two interactive pages and the script for their data.

## How this was made

I wrote the scripts, analyses and pages with help from Claude, an AI assistant, and ran and checked the results myself. The scripts only read the downloaded source as text, or build it with the pinned toolchain. Every number here comes from a file in `results/`; judge the work by rerunning it.
