#!/usr/bin/env bash
# 11_path_sample.sh: recompile a random sample of the modules whose .olean differs from
# Andrew Sutherland's manifest, this time at HIS build path, and compare with the manifest.
#
# Background (leanprover-community/riemann-hypothesis#6): 98,219 of our 175,187 .olean files
# differ from the manifest, and every one of them stores the absolute source path (linter
# messages are persisted with the file name). Sutherland's build passed sources to `lean` as
#   /home/ubuntu/grh/src/lean/src/<Module/Path>.lean
# If our build is otherwise identical, recompiling a differing module at that path should give
# exactly his bytes. This script tests that on a random sample.
#
#   bash 11_path_sample.sh                  300 modules, 24 at a time
#   N=1000 SAMPLE_JOBS=40 bash 11_path_sample.sh
#
# Safe: it never writes into the build. Outputs go to $OUT/path_sample/. It needs sudo once,
# to create /home/ubuntu/grh/src/lean as a symlink to the project.
#
# Calibration first: it recompiles a few modules at OUR path and checks that the result is
# byte-identical to the .olean our own `lake build` produced. If that fails, the way this
# script calls `lean` differs from Lake's, and it stops before drawing any conclusion.
cd "$(dirname "$0")"; . ./common.sh
need_proj; elan_env

N="${N:-300}"
SJOBS="${SAMPLE_JOBS:-24}"
SEED="${SEED:-20261121}"
SUTH=/home/ubuntu/grh/src/lean
MAN="$DL/project-oleans.sha256"
MIS="$OUT/compare_mismatch.txt"
LIB="$PROJ/.lake/build/lib/lean"
WD="$OUT/path_sample"

[ -s "$MAN" ] || die "manifest missing: run 7_compare.sh first"
[ -s "$MIS" ] || die "$MIS missing: run 7_compare.sh first"
[ -f "$LIB/Main.olean" ] || die "build not finished"
[ -d "$PROJ/src" ] || die "expected sources under $PROJ/src"

# Symlink first, in the foreground, so a sudo password prompt (if any) can be answered.
if [ ! -e "$SUTH" ]; then
  echo "Creating $SUTH -> $PROJ (needs sudo once)"
  sudo mkdir -p "$(dirname "$SUTH")"
  sudo ln -s "$PROJ" "$SUTH"
fi
[ "$(readlink -f "$SUTH")" = "$(readlink -f "$PROJ")" ] || die "$SUTH exists and is not our project"

run_detached path_sample "$PWD/11_path_sample.sh"

# ---- everything below runs in the background -----------------------------------
LOG="$OUT/path_sample.log"
{
echo "=== path sample started $(date) ==="
rm -rf "$WD"; mkdir -p "$WD/ours" "$WD/suth"

log "Symlink"
ls -ld "$SUTH"

log "Lean, search path and options"
cd "$PROJ"
LEAN_BIN=$(lake env which lean)
LP=$(lake env printenv LEAN_PATH)
echo "lean: $LEAN_BIN ($("$LEAN_BIN" --version))"
# Replay Lake's own recorded command for each module. Lake writes the exact command line into
# <module>.trace ("log": [{"message": ".> LEAN_PATH=... lean ... --setup ..."}]). We re-run it,
# changing only (1) the output paths (-o/-i/-c/-b) to a scratch directory, never the build, and
# (2) for the sample, the source path prefix $PROJ -> $SUTH.
mkdir -p "$WD"
cat > "$WD/replay.py" <<'PY'
import json, os, shlex, subprocess, sys
proj, root, rel, od = sys.argv[1:5]
mod = rel[:-len(".olean")]
tr = json.load(open(os.path.join(proj, ".lake/build/lib/lean", mod + ".trace")))
cmds = [e["message"][3:] for e in tr.get("log", []) if e.get("message", "").startswith(".> ")]
if not cmds:
    print("NO_COMMAND", rel); sys.exit(0)
toks = shlex.split(cmds[0])
env = dict(os.environ)
while toks and "=" in toks[0] and not toks[0].startswith("-") and not toks[0].startswith("/"):
    k, v = toks.pop(0).split("=", 1); env[k] = v
out = os.path.join(od, rel); os.makedirs(os.path.dirname(out), exist_ok=True)
base = out[:-len(".olean")]
red = {"-o": out, "-i": base + ".ilean", "-c": base + ".c", "-b": base + ".bc"}
args, k = [], 0
src_ours = os.path.join(proj, "src", mod + ".lean")
src_new = os.path.join(root, "src", mod + ".lean")
while k < len(toks):
    t = toks[k]
    if t in red and k + 1 < len(toks):
        args += [t, red[t]]; k += 2; continue
    long = {"--o=": "-o", "--i=": "-i", "--c=": "-c", "--bc=": "-b"}
    hit = next((f for f in long if t.startswith(f)), None)
    if hit:
        args.append(hit + red[long[hit]]); k += 1; continue
    args.append(src_new if t == src_ours else t); k += 1
with open(base + ".cmd", "w") as fh:
    fh.write(" ".join(shlex.quote(a) for a in args) + "\n")
r = subprocess.run(args, env=env, cwd=root, stdout=open(base + ".log", "w"), stderr=subprocess.STDOUT)
print(("OK " if r.returncode == 0 and os.path.exists(out) else "COMPILE_FAIL ") + rel)
PY
python3 -I - "$MAN" "$MIS" "$N" "$SEED" "$WD" <<'PY'
import random, sys, os
man, mis, n, seed, wd = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
want = {}
for line in open(man):
    h, _, p = line.rstrip("\n").partition("  ")
    want[p[2:] if p.startswith("./") else p] = h
diff = [l.split(None, 1)[1].strip() for l in open(mis) if l.startswith("DIFF ")]
same = sorted(set(want) - set(diff))
rng = random.Random(seed)
cal_diff = rng.sample(diff, 3)
cal_same = rng.sample(same, 2)
rest = sorted(set(diff) - set(cal_diff))
sample = rng.sample(rest, min(n, len(rest)))
w = lambda f, xs: open(os.path.join(wd, f), "w").write("".join(x + "\n" for x in xs))
w("cal_diff.txt", cal_diff); w("cal_same.txt", cal_same); w("sample.txt", sample)
w("manifest_subset.txt", ["{}  {}".format(want[x], x) for x in cal_diff + cal_same + sample])
print("population: {:,} differing, {:,} identical; sample {:,}".format(len(diff), len(same), len(sample)))
PY

# compile ROOT REL OUTDIR: replay Lake's command with the source under ROOT, outputs under OUTDIR
compile() { python3 -I "$WD/replay.py" "$PROJ" "$1" "$2" "$3"; }
export -f compile; export PROJ WD

log "Calibration 1: three differing modules at OUR path must equal our own lake-built .olean"
cal_ok=1
while read -r rel; do
  compile "$PROJ" "$rel" "$WD/ours"
  a=$(sha "$WD/ours/$rel" 2>/dev/null || echo none); b=$(sha "$LIB/$rel")
  if [ "$a" = "$b" ]; then echo "  same as our build: $rel"; else echo "  DIFFERENT from our build: $rel ($a vs $b)"; cal_ok=0; fi
done < "$WD/cal_diff.txt"
log "Calibration 2: two path-free modules must equal the manifest"
while read -r rel; do
  compile "$PROJ" "$rel" "$WD/ours"
  a=$(sha "$WD/ours/$rel" 2>/dev/null || echo none); b=$(grep -F "  $rel" "$WD/manifest_subset.txt" | head -1 | cut -d' ' -f1)
  if [ "$a" = "$b" ]; then echo "  same as manifest: $rel"; else echo "  DIFFERENT from manifest: $rel"; cal_ok=0; fi
done < "$WD/cal_same.txt"
if [ "$cal_ok" != 1 ]; then
  echo "STOP: calibration failed, so this script does not call lean exactly as Lake did."
  echo "Look at $WD/ours/*.log and send the output of this log."
  rm -f "$OUT/path_sample.pid"; exit 1
fi

log "Sample: $(wc -l < "$WD/sample.txt") differing modules recompiled at $SUTH ($SJOBS at a time)"
xargs -P "$SJOBS" -I{} bash -c 'compile "'"$SUTH"'" "$1" "'"$WD"'/suth"' _ {} < "$WD/sample.txt" > "$WD/compile_status.txt"

log "Compare with the manifest"
python3 -I - "$WD" <<'PY' | tee "$OUT/path_sample_result.txt"
import hashlib, os, sys
wd = sys.argv[1]
want = dict((l.split("  ", 1)[1].strip(), l.split("  ", 1)[0]) for l in open(os.path.join(wd, "manifest_subset.txt")))
sample = [l.strip() for l in open(os.path.join(wd, "sample.txt"))]
ok = bad = fail = 0; bads = []
for rel in sample:
    p = os.path.join(wd, "suth", rel)
    if not os.path.exists(p):
        fail += 1; continue
    h = hashlib.sha256(open(p, "rb").read()).hexdigest()
    if h == want[rel]: ok += 1
    else: bad += 1; bads.append(rel)
print("sample size                      : {:,}".format(len(sample)))
print("byte-identical to the manifest   : {:,}".format(ok))
print("different                        : {:,}".format(bad))
print("did not compile                  : {:,}".format(fail))
print("VERDICT: {}".format("ALL MATCH at Sutherland's build path" if ok == len(sample) else "NOT ALL MATCH"))
for r in bads[:20]: print("  different:", r)
PY
echo "=== path sample finished $(date) ==="
rm -f "$OUT/path_sample.pid"
} >> "$LOG" 2>&1
