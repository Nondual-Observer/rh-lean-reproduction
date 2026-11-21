#!/usr/bin/env bash
# 7_compare.sh: compare YOUR compiled .olean files with Andrew Sutherland's manifest
# (project-oleans.sha256: one sha256 per compiled file, 175,187 lines).
#
# Why: his page says only 77 modules were compared against a real `lake build`.
# Your build is a real `lake build`, so a full match is a new, checkable result.
#
#   bash 7_compare.sh                full comparison (run after step 3 finishes)
#   PARTIAL=1 bash 7_compare.sh      only files that exist so far; safe DURING the build
#   HASH_JOBS=4 bash 7_compare.sh    hashing threads (default 4, so the build keeps its CPUs)
#
# Reads only. It never touches the build. A hash mismatch is NOT proof of a problem:
# first check whether the same file also differs between two builds of your own.
cd "$(dirname "$0")"; . ./common.sh
need_proj

MANIFEST_URL="https://math.mit.edu/~drew/grh/project-oleans.sha256"
MANIFEST_SHA="375cbee2fc3fc0f5088ef2e6dc9a5ac5530924310dc62422ec65aac9dc4c1d25"
MAIN_OLEAN_SHA="9146dfb4148e24d2252e04c50742f3e49dd126dfcc5006d10bf5f873ddf796ad"
PARTIAL="${PARTIAL:-0}"
HASH_JOBS="${HASH_JOBS:-4}"
MAN="$DL/project-oleans.sha256"

log "Manifest"
if [ ! -s "$MAN" ]; then
  curl -fL --retry 5 --retry-delay 5 -o "$MAN.tmp" "$MANIFEST_URL"
  mv "$MAN.tmp" "$MAN"
fi
got=$(sha "$MAN")
[ "$got" = "$MANIFEST_SHA" ] || die "manifest hash mismatch (got $got). Do not compare against it."
echo "manifest ok: $(wc -l < "$MAN" | tr -d ' ') entries"

log "Locating your compiled files"
LIB=""
for d in "$PROJ/.lake/build/lib/lean" "$PROJ/.lake/build/lib"; do
  if [ -d "$d/BuildAid" ] || [ -f "$d/Main.olean" ]; then LIB="$d"; break; fi
done
[ -n "$LIB" ] || die "no compiled files under $PROJ/.lake/build/lib yet. Is step 3 running?"
echo "olean dir: $LIB"
if [ "$PARTIAL" != 1 ] && [ ! -f "$LIB/Main.olean" ]; then
  die "Main.olean is missing: the build is not finished. Use PARTIAL=1 to compare what exists."
fi

log "Hashing and comparing (threads: $HASH_JOBS)"
rc=0
python3 -I - "$MAN" "$LIB" "$OUT" "$PARTIAL" "$HASH_JOBS" "$MAIN_OLEAN_SHA" <<'PY' || rc=$?
import hashlib, os, sys
from concurrent.futures import ThreadPoolExecutor
man, lib, out, partial, jobs, main_sha = sys.argv[1:7]
partial = partial == "1"; jobs = int(jobs)

want = {}
for line in open(man, encoding="utf-8", errors="replace"):
    h, _, p = line.rstrip("\n").partition("  ")
    want[p[2:] if p.startswith("./") else p] = h

have = set()
for r, _d, fs in os.walk(lib):
    for f in fs:
        if f.endswith(".olean"):
            have.add(os.path.relpath(os.path.join(r, f), lib))

def sha(rel):
    h = hashlib.sha256(); hp = False; tail = b""
    with open(os.path.join(lib, rel), "rb") as fh:
        for blk in iter(lambda: fh.read(1 << 22), b""):
            h.update(blk)
            if not hp and b".lean" in tail + blk:
                hp = True
            tail = blk[-8:]
    return rel, h.hexdigest(), hp

todo = sorted(set(want) & have)
ok, bad = 0, []
split = {(True, False): 0, (True, True): 0, (False, False): 0, (False, True): 0}
with ThreadPoolExecutor(jobs) as ex:
    for i, (rel, h, hp) in enumerate(ex.map(sha, todo, chunksize=64), 1):
        same = h == want[rel]
        split[(same, hp)] += 1
        if same:
            ok += 1
        else:
            bad.append((rel, want[rel], h))
        if i % 20000 == 0:
            print("  hashed {:,} / {:,}".format(i, len(todo)), flush=True)

missing = sorted(set(want) - have)          # in manifest, not built yet
extra = sorted(have - set(want))            # built here, not in manifest
main_got = next((h for r, w, h in bad if r == "Main.olean"), None)
main_ok = ("Main.olean" in have) and main_got is None

lines = []
lines.append("manifest entries      : {:,}".format(len(want)))
lines.append("files built here      : {:,}".format(len(have)))
lines.append("compared              : {:,}".format(len(todo)))
lines.append("identical             : {:,}".format(ok))
lines.append("DIFFERENT             : {:,}".format(len(bad)))
lines.append("not built yet/missing : {:,}".format(len(missing)))
lines.append("extra (not in manifest): {:,}".format(len(extra)))
lines.append("  identical, no source path : {:,}".format(split[(True, False)]))
lines.append("  identical, has source path: {:,}".format(split[(True, True)]))
lines.append("  DIFFERENT, no source path : {:,}   <- must be 0; anything else is a real lead".format(split[(False, False)]))
lines.append("  DIFFERENT, has source path: {:,}   <- expected: the build dir path is stored in warnings".format(split[(False, True)]))
lines.append("Main.olean            : {}".format("identical" if main_ok else
             ("DIFFERENT (yours {})".format(main_got) if main_got else "not built yet")))
if not partial:
    full = (not bad) and (not missing) and (not extra)
    lines.append("VERDICT               : {}".format(
        "FULL MATCH: all {:,} compiled files are byte-identical to the manifest".format(len(want))
        if full else "NOT A FULL MATCH (see compare_mismatch.txt)"))
else:
    lines.append("VERDICT               : PARTIAL run, {:,} of {:,} files checked so far".format(len(todo), len(want)))
txt = "\n".join(lines)
print("\n" + txt)
open(os.path.join(out, "compare_result.txt"), "w").write(txt + "\n")
with open(os.path.join(out, "compare_mismatch.txt"), "w") as fh:
    for r, w, h in bad:
        fh.write("DIFF  {}\n  manifest {}\n  yours    {}\n".format(r, w, h))
    for r in extra:
        fh.write("EXTRA {}\n".format(r))
    if not partial:
        for r in missing:
            fh.write("MISSING {}\n".format(r))
sys.exit(0 if not bad else 3)
PY
echo
echo "Result written to $OUT/compare_result.txt"
echo "Details (if any): $OUT/compare_mismatch.txt"
exit $rc
