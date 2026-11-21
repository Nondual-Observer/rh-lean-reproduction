#!/usr/bin/env python3
"""compare_dead.py: how much of the project does the RH proof actually use?

Inputs
  all_decls.tsv   from ListDecls.lean: every constant defined in the project's own modules
  used_decls.txt  from export_decls.py: every constant the exported theorems depend on (.gz is fine)
  src             the project's source folder (for line counts per module)

Usage
  python3 -I compare_dead.py all_decls.tsv used_decls.txt.gz path/to/src  [outdir]

Writes a report to stdout and, in outdir (default: dead_code/):
  modules.tsv          per module: status, lines, constants, named, named_used
  dead_modules.txt     modules that define constants but none of them is used
  unused_named.txt.gz  every unused hand-named constant, with its module

"Used" means: appears in the kernel-level dependency closure of the exported theorems. A constant
can be unused there and still be needed to build the project (tactics, macros, notation and
attributes act during elaboration, not in the final proof term), so "unused" is not the same as
"safe to delete".
"""
import gzip, os, re, sys
from collections import Counter, defaultdict

if len(sys.argv) < 4:
    sys.exit(__doc__)
all_path, used_path, src = sys.argv[1:4]
outdir = sys.argv[4] if len(sys.argv) > 4 else "dead_code"
os.makedirs(outdir, exist_ok=True)

def opener(p):
    return gzip.open(p, "rt", encoding="utf-8") if p.endswith(".gz") else open(p, encoding="utf-8")

used = set()
with opener(used_path) as f:
    for line in f:
        k, _, n = line.rstrip("\n").partition(" ")
        used.add(n)

# Names Lean generates on its own. A constant is "named" (written by hand, or the main object a
# hand-written command produces) if none of these patterns match.
AUTO_LAST = {"rec", "recOn", "casesOn", "noConfusion", "noConfusionType", "injEq", "inj", "sizeOf_spec",
             "below", "brecOn", "binductionOn", "ibelow", "induct", "mutual_induct", "ctorIdx", "toCtorIdx",
             "ctorElim", "ctorElimType", "elim", "eq_def", "eq_unfold", "fun_cases", "functional_induction"}
AUTO_RE = re.compile(r"^(match|proof|eq|simp|aux|cstage|spec|lambda|unary|binary|mutual)_\d+$")
PRIV = re.compile(r"^_private\.(?:[^.]+\.)*?0\.")

def is_named(kind, name):
    if kind in ("rec", "none"):
        return False
    base = PRIV.sub("", name)
    parts = base.split(".")
    if any(p.startswith("_") for p in parts):
        return False
    last = parts[-1]
    return last not in AUTO_LAST and not AUTO_RE.match(last)

mods = {}   # module -> [constants, named, used, named_used]
kinds = Counter(); kinds_used = Counter()
named_tot = named_used = 0
proj_names = set()
unused_named = []
with opener(all_path) as f:
    for line in f:
        kind, name, mod = line.rstrip("\n").split("\t")
        m = mods.setdefault(mod, [0, 0, 0, 0])
        if kind == "none":
            continue
        proj_names.add(name)
        u = name in used
        nm = is_named(kind, name)
        m[0] += 1; m[2] += u
        kinds[kind] += 1; kinds_used[kind] += u
        if nm:
            m[1] += 1; m[3] += u; named_tot += 1; named_used += u
            if not u:
                unused_named.append((kind, name, mod))

def lines_of(mod):
    p = os.path.join(src, *mod.split(".")) + ".lean"
    try:
        with open(p, "rb") as fh:
            return sum(1 for _ in fh)
    except OSError:
        return -1

# Project files that never appear as a module (not imported by the roots)
src_mods = set()
for d, _, fs in os.walk(src):
    for fn in fs:
        if fn.endswith(".lean"):
            rel = os.path.relpath(os.path.join(d, fn), src)[:-5]
            src_mods.add(rel.replace(os.sep, "."))
not_loaded = sorted(src_mods - set(mods))

status_ct = Counter(); status_lines = Counter()
folder = defaultdict(lambda: Counter())
rows = []
for mod, (c, n, u, nu) in mods.items():
    st = "empty" if c == 0 else ("dead" if u == 0 else ("live" if nu == n else "partial"))
    ln = lines_of(mod)
    status_ct[st] += 1; status_lines[st] += max(ln, 0)
    top = ".".join(mod.split(".")[:2])
    folder[top][st] += 1; folder[top][st + "_lines"] += max(ln, 0)
    folder[top]["named"] += n; folder[top]["named_used"] += nu
    rows.append((mod, st, ln, c, n, nu))

rows.sort()
with open(os.path.join(outdir, "modules.tsv"), "w") as fh:
    fh.write("module\tstatus\tlines\tconstants\tnamed\tnamed_used\n")
    for r in rows:
        fh.write("\t".join(map(str, r)) + "\n")
with open(os.path.join(outdir, "dead_modules.txt"), "w") as fh:
    for mod, st, ln, *_ in rows:
        if st == "dead":
            fh.write(f"{mod}\t{ln}\n")
with gzip.open(os.path.join(outdir, "unused_named.txt.gz"), "wt") as fh:
    for k, n, m in sorted(unused_named, key=lambda t: (t[2], t[1])):
        fh.write(f"{k}\t{n}\t{m}\n")

pct = lambda a, b: f"{100*a/b:.1f}%" if b else "n/a"
tot_mods = len(mods); tot_lines = sum(status_lines.values())
proj_used = len(used & proj_names)
print("== Constants defined in the project")
print(f"all constants     : {sum(kinds.values()):>10,}   used {sum(kinds_used.values()):>10,}  ({pct(sum(kinds_used.values()), sum(kinds.values()))})")
for k in sorted(kinds):
    print(f"  {k:<8}        : {kinds[k]:>10,}   used {kinds_used[k]:>10,}  ({pct(kinds_used[k], kinds[k])})")
print(f"hand-named        : {named_tot:>10,}   used {named_used:>10,}  ({pct(named_used, named_tot)})")
print(f"unused hand-named : {named_tot - named_used:>10,}")
print()
print("== Used constants by origin")
print(f"from the project  : {proj_used:>10,}")
print(f"from Lean/Mathlib : {len(used) - proj_used:>10,}")
print()
print("== Modules (files)")
print(f"{'status':<9}{'files':>9}{'lines':>14}")
for st in ("live", "partial", "dead", "empty"):
    print(f"{st:<9}{status_ct[st]:>9,}{status_lines[st]:>14,}   ({pct(status_lines[st], tot_lines)} of lines)")
print(f"{'total':<9}{tot_mods:>9,}{tot_lines:>14,}")
print("  live    = every hand-named constant is used")
print("  partial = some constant used, some hand-named constant unused")
print("  dead    = defines constants, none used")
print("  empty   = defines no constants (imports only)")
print(f"source files never loaded from the roots: {len(not_loaded)}")
for m in not_loaded[:20]:
    print("   ", m)
print()
print("== By folder (top two levels), sorted by dead lines")
print(f"{'folder':<42}{'files':>8}{'dead':>8}{'dead lines':>12}{'named':>10}{'used':>10}")
for top, c in sorted(folder.items(), key=lambda kv: -kv[1]["dead_lines"])[:40]:
    files = sum(c[s] for s in ("live", "partial", "dead", "empty"))
    print(f"{top:<42}{files:>8,}{c['dead']:>8,}{c['dead_lines']:>12,}{c['named']:>10,}{c['named_used']:>10,}")
print()
print("Caveat: unused here means outside the kernel dependency closure of the exported theorems.")
print("Elaboration-time code (tactics, macros, notation, attributes) can be unused and still needed to build.")
print(f"Files written to {outdir}/")
