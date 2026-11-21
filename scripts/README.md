# Verify the claimed Lean proof of the Riemann Hypothesis on your Mac

Independent check of Levent Alpöge's Nov 20, 2026 release (`alpo.ge/lean.tar.gz.part01..14`).
Everything goes into `~/rh` (change it with `WORK=/some/path`). You'll need roughly 60+ GB free.

Run the whole pipeline in Terminal with live progress:

```bash
bash run_all.sh          # runs (or safely resumes) steps 1 -> 2 -> 3 -> 4 -> 6
JOBS=2 bash run_all.sh   # optional: lower parallelism on a 16 GB Mac
```

Or run each step individually from Terminal in this folder with `bash <script>`:

| Step | Script | Runs code from the archive? | Time on a 16 GB M4 |
|---|---|---|---|
| 1 | `1_preflight.sh` | No (download, hash, text scan) | ~5 min |
| 2 | `2_setup.sh` | Barely (installs Lean, gets Mathlib, builds 16-line Statements) | 10 to 20 min |
| **3** | **`3_build_main.sh`** | **Yes: compiles all ~175k files** | **many hours to a day+ (background)** |
| 3 | `3_status.sh` | No: progress, ETA, swap/memory | instant |
| 3 | `3_stop.sh` | No: stops safely; rerun step 3 to resume | instant |
| 4 | `4_check.sh` | Yes (the check file) | a few minutes |
| 5 | `5_replay.sh` | Yes (optional kernel re-check, background) | long; `FRESH=1` is longer |
| 6 | `6_report.sh` | No: writes `~/rh/out/REPORT.md` | instant |

Optional kernel replay after `run_all.sh` finishes (using the same `WORK` directory):

```bash
bash 5_replay.sh          # check all compiled modules in parallel (background)
FRESH=1 bash 5_replay.sh  # replay Main in a fresh environment (single-threaded)
```

Watch replay progress with `bash 3_status.sh`, stop with `bash 3_stop.sh`, and re-run `bash 6_report.sh` afterward to include `replay_result` in `REPORT.md`.

## What "pass" looks like

- Step 1: `PASS: archive matches the published hash`. Ideally no CRITICAL scan hits; hits inside comments are fine.
- Step 3: `build_main: OK`
- Step 4:
  ```
  statement module : (some Mathlib.NumberTheory.LSeries.RiemannZeta)
  statement exact  : true
  PASS  myRH: Classical.choice, Quot.sound, propext
  PASS  riemannHypothesis: Classical.choice, Quot.sound, propext
  ...
  OVERALL: CLEAN
  ```
- Step 5: `replay: OK`

## Memory on a 16 GB Mac

`JOBS` (default = RAM / 4, so 4) sets how many files compile at once. If `3_status.sh` shows heavy swap
or memory pressure stays low for a long time:

```bash
bash 3_stop.sh
JOBS=2 bash 3_build_main.sh     # resumes; nothing already compiled is lost
```

## Notes

- Keep the Mac plugged in with the lid open. The scripts use `caffeinate`, but closing the lid still sleeps it.
- `3_stop.sh` also stops any other `lean` process (such as a VS Code Lean server).
- Step 3 runs code from a stranger's archive with your user's permissions. Step 1's `buildtime_code`
  scan shows you exactly which lines do that; skim them first.
