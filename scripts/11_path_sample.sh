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
# leanOptions / moreLeanArgs from lakefile.toml, merged per module (package, then its lean_lib),
# passed the way Lake passes them (-Dkey=value with dotted keys).
mkdir -p "$WD"
cat > "$WD/opts.py" <<'PY'
import sys, os, re, tomllib
c = tomllib.load(open(os.path.join(sys.argv[1], "lakefile.toml"), "rb"))
mod = sys.argv[2]
def flat(d, pre=""):
    for k, v in d.items():
        if isinstance(v, dict):
            yield from flat(v, pre + k + ".")
        else:
            yield pre + k, (str(v).lower() if isinstance(v, bool) else str(v))
def matches(lib, m):
    globs = lib.get("globs") or [lib["name"]]
    for g in globs:
        if g.endswith(".+"):
            if m.startswith(g[:-2] + "."): return True
        elif g.endswith(".*"):
            if m == g[:-2] or m.startswith(g[:-2] + "."): return True
        elif m == g:
            return True
    return False
opts = dict(flat(c.get("leanOptions") or {})); more = list(c.get("moreLeanArgs") or [])
libs = [l for l in c.get("lean_lib", []) if matches(l, mod)]
for l in libs:
    opts.update(flat(l.get("leanOptions") or {})); more += list(l.get("moreLeanArgs") or [])
print("\n".join(["-D{}={}".format(k, v) for k, v in opts.items()] + more))
PY
modopts() { python3 -I "$WD/opts.py" "$PROJ" "$(echo "${1%.olean}" | tr / .)"; }
echo "options for a Development module:"; modopts Development/X.olean | sed "s/^/  /"
[ -f "$PROJ/lakefile.lean" ] && echo "NOTE: lakefile.lean present; its options are not parsed. Calibration will tell."

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

# compile ROOT REL OUTDIR: compile <ROOT>/src/<mod>.lean as Lake does, output to OUTDIR/<rel>
compile() {
  local root="$1" rel="$2" od="$3" mod="${2%.olean}"
  local out="$od/$rel"; mkdir -p "$(dirname "$out")"
  local -a opts; mapfile -t opts < <(modopts "$rel")
  ( cd "$root" && LEAN_PATH="$LP" "$LEAN_BIN" "${opts[@]}" -R "$root/src" \
      -o "$out" -i "${out%.olean}.ilean" "$root/src/$mod.lean" ) > "${out%.olean}.log" 2>&1 \
    || { echo "COMPILE_FAIL $rel"; return 0; }
  echo "OK $rel"
}
export -f compile modopts; export LP LEAN_BIN PROJ WD

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
