#!/usr/bin/env python3
"""reach.py: how much of the RH Lean project is actually reachable from Main?

Reads the .lean files as TEXT ONLY. Nothing is compiled or executed, so it is
safe to run on the untrusted archive on any machine.

Usage (run with -I so Python ignores the project's folder on sys.path):

    python3 -I reach.py PROJECT_DIR                # e.g. ~/rh/lean
    python3 -I reach.py PROJECT_DIR --root Main --out reach_out
    python3 -I reach.py PROJECT_DIR --src PROJECT_DIR/src   # override auto-detect

What it reports:
  * every .lean file under the source dir, and how many are in Main's import closure
  * physical lines (newline count) reachable vs unreachable
  * breakdown by top-level folder
  * external libraries imported (Mathlib, Lean, Std, ...)
  * how many files do a bare `import Mathlib`
  * longest import chain from Main
  * the largest unreachable files
Writes reach_modules.csv and reach_by_dir.csv into the --out folder.

Method notes (so you can state them when you post numbers):
  * "lines" = physical lines in the file, not code-only lines.
  * An import of a module that is not a file in the source dir is "external".
  * Only the import header is parsed. Comments and `public`/`meta`/`import all`
    forms are handled. `/-!` and `/--` docstrings end the header.
  * This measures FILE reachability. A reachable file can still contain unused
    declarations; that needs the compiler's dependency data, not this script.
"""
import argparse
import csv
import os
import re
import sys
from collections import Counter, defaultdict, deque
from concurrent.futures import ProcessPoolExecutor


# ---------------------------------------------------------------- header parsing
def parse_header(text):
    """Return the list of module names imported in the file header."""
    i, n = 0, len(text)

    def skip():
        nonlocal i
        while i < n:
            c = text[i]
            if c.isspace():
                i += 1
            elif text.startswith("--", i):
                j = text.find("\n", i)
                i = n if j < 0 else j + 1
            elif text.startswith("/-", i) and not text.startswith(("/-!", "/--"), i):
                depth, i = 1, i + 2
                while i < n and depth:
                    if text.startswith("/-", i):
                        depth += 1
                        i += 2
                    elif text.startswith("-/", i):
                        depth -= 1
                        i += 2
                    else:
                        i += 1
            else:
                break

    def token():
        nonlocal i
        skip()
        j = i
        while j < n and not text[j].isspace():
            j += 1
        tok = text[i:j]
        k = tok.find("--")
        if k > 0:  # `import Foo--comment`
            tok, j = tok[:k], i + k
        i = j
        return tok

    imports = []
    while True:
        tok = token()
        if tok in ("module", "prelude"):
            continue
        while tok in ("public", "meta"):
            tok = token()
        if tok != "import":
            break
        name = token()
        if name == "all":
            name = token()
        if not name:
            break
        imports.append(name)
    return imports


def scan_file(args):
    """Worker: returns (relpath, lines, imports)."""
    root, rel = args
    path = os.path.join(root, rel)
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError as e:
        return rel, 0, [], str(e)
    lines = data.count(b"\n") + (1 if data and not data.endswith(b"\n") else 0)
    text = data[:200_000].decode("utf-8", errors="replace")
    return rel, lines, parse_header(text), ""


# ---------------------------------------------------------------- project layout
def find_src(project):
    lf = os.path.join(project, "lakefile.toml")
    if os.path.isfile(lf):
        try:
            m = re.search(r'srcDir\s*=\s*"([^"]+)"', open(lf, encoding="utf-8", errors="replace").read())
        except OSError:
            m = None
        if m:
            cand = os.path.normpath(os.path.join(project, m.group(1)))
            if os.path.isdir(cand):
                return cand, f"lakefile.toml srcDir = {m.group(1)}"
    best = None
    for dp, dn, fn in os.walk(project):
        dn[:] = [d for d in dn if d not in (".lake", ".git")]
        if "Main.lean" in fn:
            depth = dp[len(project):].count(os.sep)
            if best is None or depth < best[0]:
                best = (depth, dp)
    if best:
        return best[1], "directory containing Main.lean"
    return project, "fallback: project dir"


def list_lean(src):
    out = []
    for dp, dn, fn in os.walk(src, followlinks=False):
        dn[:] = [d for d in dn if d not in (".lake", ".git")]
        for f in fn:
            if f.endswith(".lean"):
                p = os.path.join(dp, f)
                if not os.path.islink(p):
                    out.append(os.path.relpath(p, src))
    out.sort()
    return out


def modname(rel):
    return rel[:-5].replace(os.sep, ".")


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("project")
    ap.add_argument("--src", help="source dir that module names are relative to")
    ap.add_argument("--root", default="Main", help="root module (default Main)")
    ap.add_argument("--out", default="reach_out")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 2)
    a = ap.parse_args()

    project = os.path.abspath(a.project)
    if not os.path.isdir(project):
        sys.exit(f"not a directory: {project}")
    src, why = (os.path.abspath(a.src), "--src") if a.src else find_src(project)
    print(f"source dir : {src}  ({why})")
    files = list_lean(src)
    if not files:
        sys.exit("no .lean files found; check --src")
    print(f"lean files : {len(files):,}")

    info = {}  # module -> dict
    errors = 0
    with ProcessPoolExecutor(max_workers=a.jobs) as ex:
        for rel, lines, imps, err in ex.map(scan_file, [(src, r) for r in files], chunksize=500):
            if err:
                errors += 1
            info[modname(rel)] = {"path": rel, "lines": lines, "imports": imps}
    if errors:
        print(f"WARNING: {errors} files could not be read")

    if a.root not in info:
        sys.exit(f"root module {a.root!r} not found among the project modules")

    # edges (project-internal) and external imports
    ext_by_lib = Counter()
    bare_mathlib = 0
    for m, d in info.items():
        d["internal"] = []
        d["external"] = []
        for imp in d["imports"]:
            (d["internal"] if imp in info else d["external"]).append(imp)
        if "Mathlib" in d["imports"]:
            bare_mathlib += 1

    # reachability from root
    seen = {a.root}
    q = deque([a.root])
    while q:
        m = q.popleft()
        for t in info[m]["internal"]:
            if t not in seen:
                seen.add(t)
                q.append(t)
    for m, d in info.items():
        d["reach"] = m in seen

    # external libs used by the reachable part
    bare_mathlib_reach = 0
    for m in seen:
        for imp in info[m]["external"]:
            ext_by_lib[imp.split(".")[0]] += 1
        if "Mathlib" in info[m]["imports"]:
            bare_mathlib_reach += 1

    # longest import chain from root (Kahn over reachable subgraph)
    indeg = {m: 0 for m in seen}
    for m in seen:
        for t in set(info[m]["internal"]):
            indeg[t] += 1
    order, dq = [], deque([m for m, k in indeg.items() if k == 0])
    while dq:
        m = dq.popleft()
        order.append(m)
        for t in set(info[m]["internal"]):
            indeg[t] -= 1
            if indeg[t] == 0:
                dq.append(t)
    cyc = len(seen) - len(order)
    depth = {m: 1 for m in seen}
    for m in order:
        for t in set(info[m]["internal"]):
            if depth[m] + 1 > depth[t]:
                depth[t] = depth[m] + 1
    longest = max(depth.values()) if depth else 0

    # totals
    tot_files = len(info)
    tot_lines = sum(d["lines"] for d in info.values())
    r_files = len(seen)
    r_lines = sum(info[m]["lines"] for m in seen)
    u_files, u_lines = tot_files - r_files, tot_lines - r_lines

    def pct(x, y):
        return f"{100.0 * x / y:.1f}%" if y else "n/a"

    print()
    print("=" * 66)
    print(f"root module                     : {a.root}")
    print(f"files   total / reachable / not : {tot_files:,} / {r_files:,} / {u_files:,}  ({pct(r_files, tot_files)} reachable)")
    print(f"lines   total / reachable / not : {tot_lines:,} / {r_lines:,} / {u_lines:,}  ({pct(r_lines, tot_lines)} reachable)")
    print(f"longest import chain from root  : {longest:,} modules" + (f"  (WARNING: {cyc} modules in import cycles)" if cyc else ""))
    print(f"files with bare `import Mathlib`: {bare_mathlib:,} total, {bare_mathlib_reach:,} reachable")
    print("external libraries imported by reachable files (import statements):")
    for lib, c in ext_by_lib.most_common(10):
        print(f"    {lib:<14}{c:>9,}")
    print("=" * 66)

    # by top-level folder
    byd = defaultdict(lambda: [0, 0, 0, 0])  # files, lines, rfiles, rlines
    for m, d in info.items():
        top = d["path"].split(os.sep)[0] if os.sep in d["path"] else "(root)"
        row = byd[top]
        row[0] += 1
        row[1] += d["lines"]
        if d["reach"]:
            row[2] += 1
            row[3] += d["lines"]
    print(f"\n{'top-level folder':<34}{'files':>9}{'lines':>13}{'reach files':>13}{'reach lines':>13}")
    for top, (f, l, rf, rl) in sorted(byd.items(), key=lambda kv: -kv[1][1])[:20]:
        print(f"{top:<34}{f:>9,}{l:>13,}{rf:>13,}{rl:>13,}")

    unreach = sorted((d["lines"], d["path"]) for d in info.values() if not d["reach"])[::-1][:15]
    if unreach:
        print("\nlargest unreachable files:")
        for l, p in unreach:
            print(f"  {l:>9,}  {p}")
    else:
        print("\nno unreachable files: every file under the source dir is in the closure of", a.root)

    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, "reach_modules.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["module", "path", "lines", "reachable", "chain_depth_from_root", "imports_internal", "imports_external"])
        for m in sorted(info):
            d = info[m]
            w.writerow([m, d["path"], d["lines"], int(d["reach"]), depth.get(m, ""), len(d["internal"]), len(d["external"])])
    with open(os.path.join(a.out, "reach_by_dir.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["top_level_folder", "files", "lines", "reachable_files", "reachable_lines"])
        for top, (fl, l, rf, rl) in sorted(byd.items()):
            w.writerow([top, fl, l, rf, rl])
    print(f"\nwrote {os.path.join(a.out, 'reach_modules.csv')} and reach_by_dir.csv")


if __name__ == "__main__":
    main()
