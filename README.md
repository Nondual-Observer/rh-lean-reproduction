# Reproducing the build of the Lean proof of the Riemann Hypothesis

Notes and scripts from my attempt to independently reproduce and examine the Lean 4 formalization
announced by Levent Alpöge on 20 November 2026 (`alpo.ge/remark.pdf`, source in `lean.tar.gz`).

**Status: in progress.** My build is still running. Results below marked partial will be updated.
This repository does not claim to verify the proof. The kernel checks that matter were run by
others; see [Andrew Sutherland's page](https://math.mit.edu/~drew/grh/). What I add is a
reproducibility check of the build and a few facts about the source.

## How this was made

I wrote these scripts with help from Claude (an AI assistant) and ran and checked everything
myself. The scripts only read the downloaded source as text, or build it with the pinned Lean
toolchain. Judge them by reading them and running them, not by who wrote them.

## What I checked

| Check | Result | Where |
|---|---|---|
| Source archive hash | `9631b4f0…c7fc`, 239,275,554 bytes: matches the published values | `results/hashes.txt` |
| Import reachability from `Main` | All 175,187 `.lean` files (17,374,215 lines) are in the import closure of `Main`. No unreachable files. Longest import chain: 203 modules. | `results/reach_summary.txt`, `analysis/reach.py` |
| Risky constructs (text census) | 0 each of `sorry`, `admit`, `axiom`, `native_decide`, `unsafe`, `implemented_by`, `extern`, `opaque`. `partial`: 2. `elab`: 4, `macro`: 87, `run_cmd`: 5 (all in `BuildAid`). | `results/census_summary.txt`, `analysis/census.py` |
| Compiled `.olean` files vs Sutherland's manifest (partial) | 20,625 of 20,625 compared files that contain no source path are byte-identical. Every file that differs contains an embedded absolute source path. | `results/olean_comparison_partial.txt`, `scripts/7_compare.sh` |
| Universe levels in the challenge export | Largest concrete level used: 2 (`Type 1`). Full proof export not scanned yet. | `results/levels_challenge_only.txt`, `analysis/levels.py` |

### The `.olean` path finding

`.olean` files store the absolute path of their source file when the module produced warnings.
So any file with a warning contains the path of the machine that built it, and cannot be
byte-identical to a build made in a different directory. In my partial comparison the two groups
do not overlap: no file without a stored path differs, and no file with one matches. This does not
show that the path-carrying files would match if built at the same path. I have not tested that.

## Not done yet

- Finish the build and rerun `scripts/7_compare.sh` for all 175,187 files.
- Compare my own `lean4export` output with the published export (`scripts/8_export_hash.sh`).
- Scan the full export for universe levels (`analysis/levels.py`).
- My build is not sandboxed, so it does not close the sandboxed re-export gap Sutherland lists.
- Note: part of my build ran with the project at `/mnt/rh_ram`, the rest at `/home/<user>/rh`.

## Layout

- `scripts/`: the pipeline I ran (`run_all.sh` runs steps 1 to 6; see `scripts/README.md`), plus
  `7_compare.sh` and `8_export_hash.sh`.
- `analysis/`: `reach.py`, `census.py`, `levels.py`. Text only; run with `python3 -I`.
- `results/`: outputs, with the dates they were taken.

## Environment

Lean v4.33.1, Mathlib v4.33.1, built with `lake build Main` on a Google Cloud VM (377 GB RAM, 94 jobs).
