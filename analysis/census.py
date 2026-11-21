#!/usr/bin/env python3
"""census.py: count risky or noteworthy Lean constructs in the RH project.

Reads the .lean files as TEXT ONLY. Nothing is compiled or executed, so it is
safe to run on the untrusted archive on any machine.

Usage (run with -I so Python ignores the project's folder on sys.path):

    python3 -I census.py PROJECT_DIR
    python3 -I census.py PROJECT_DIR --src PROJECT_DIR/src --out census_out --jobs 4

What it reports, per pattern: occurrences, number of files, and the exact
file:line of every hit when a pattern is rare (--show-max, default 60).

Pattern groups:
  unsound     sorry, admit, axiom, native_decide, decide +native, unsafe,
              implemented_by, extern, opaque, partial
  meta        macro, macro_rules, syntax, elab, elab_rules, declare_syntax_cat,
              initialize, builtin_initialize, run_cmd, run_elab, run_meta,
              import Lean, open Lean
  rebinding   notation, infix, infixl, infixr, prefix, postfix, local instance,
              attribute [local ...], #exit, #eval
  options     set_option, split by option name

Method notes (state them when you post numbers):
  * Comments (`--`, nested `/- -/`, docstrings) and string literals are blanked
    before matching, so a word inside a comment or string is NOT counted.
  * Matching is textual. A word match is not proof of use. `partial` can be an
    ordinary word in a name; check the listed lines.
  * This is a census, not a verdict. Counting a construct says nothing about
    whether the proof is sound. Soundness is the kernels' job.
  * Character literals are not parsed. An apostrophe is treated as part of an
    identifier, never as a quote.
"""
import argparse
import csv
import os
import re
import sys
from collections import Counter, defaultdict
from concurrent.futures import ProcessPoolExecutor

IDENT = r"[\w.'!?]"
# (name, group, regex). `kw` builds a whole-token keyword regex.


def kw(word):
    return r"(?<!%s)%s(?!%s)" % (IDENT, re.escape(word), IDENT)


PATTERNS = []


def add(group, name, rx):
    PATTERNS.append((name, group, re.compile(rx)))


for w in ["sorry", "admit", "axiom", "native_decide", "unsafe",
          "implemented_by", "extern", "opaque", "partial"]:
    add("unsound", w, kw(w))
add("unsound", "decide +native", r"(?<!%s)decide\s*\+\s*native(?!%s)" % (IDENT, IDENT))
for w in ["macro", "macro_rules", "syntax", "elab", "elab_rules",
          "declare_syntax_cat", "initialize", "builtin_initialize",
          "run_cmd", "run_elab", "run_meta"]:
    add("meta", w, kw(w))
PATTERNS.append(("import Lean", "meta", re.compile(r"^[ \t]*(?:public[ \t]+|meta[ \t]+)*import[ \t]+(?:all[ \t]+)?Lean(?![\w'])", re.M)))
add("meta", "open Lean", r"(?<!%s)open[ \t]+(?:[\w.']+[ \t]+)*Lean(?:\.[\w.']+)?(?![\w'])" % IDENT)
for w in ["notation", "infix", "infixl", "infixr", "prefix", "postfix"]:
    add("rebinding", w, kw(w))
add("rebinding", "local instance", r"(?<!%s)local[ \t]+instance(?!%s)" % (IDENT, IDENT))
add("rebinding", "attribute [local", r"(?<!%s)attribute[ \t]+\[[ \t]*local(?!%s)" % (IDENT, IDENT))
add("rebinding", "#exit", r"#exit(?![\w'])")
add("rebinding", "#eval", r"#eval(?![\w'])")
add("options", "set_option", kw("set_option"))

OPT_RX = re.compile(r"(?<!%s)set_option[ \t]+([\w.]+)" % IDENT)

# One cheap pre-filter: any trigger word in the raw text.
TRIGGER = re.compile(
    r"sorry|admit|axiom|native|unsafe|implemented_by|extern|opaque|partial|"
    r"macro|syntax|elab|initialize|run_cmd|run_elab|run_meta|"
    r"import[ \t]+(?:all[ \t]+)?Lean|open[ \t]+[\w.' \t]*Lean|"
    r"notation|infix|prefix|postfix|local|#exit|#eval|set_option")

TOK = re.compile(r'/-|-/|--[^\n]*|"(?:\\.|[^"\\])*"', re.S)


def blank(text):
    """Return text of identical length with comments and strings blanked.

    Newlines are kept, so offsets and line numbers stay valid."""
    out = []
    pos = 0
    depth = 0
    start = 0
    for m in TOK.finditer(text):
        t = m.group(0)
        if depth > 0:
            if t == "/-":
                depth += 1
            elif t == "-/":
                depth -= 1
                if depth == 0:
                    out.append(re.sub(r"[^\n]", " ", text[start:m.end()]))
                    pos = m.end()
            continue
        if t == "/-":
            out.append(text[pos:m.start()])
            depth = 1
            start = m.start()
        elif t == "-/":
            continue  # stray close outside a comment; leave as is
        else:  # line comment or string literal
            out.append(text[pos:m.start()])
            out.append(re.sub(r"[^\n]", " ", t))
            pos = m.end()
    if depth > 0:  # unterminated block comment: blank to end of file
        out.append(re.sub(r"[^\n]", " ", text[start:]))
    else:
        out.append(text[pos:])
    return "".join(out)


def scan_file(args):
    root, rel = args
    try:
        raw = open(os.path.join(root, rel), "rb").read().decode("utf-8", "replace")
    except OSError:
        return rel, None, None, 0
    nlines = raw.count("\n") + (0 if raw.endswith("\n") or not raw else 1)
    if not TRIGGER.search(raw):
        return rel, {}, {}, nlines
    text = blank(raw)
    counts = {}
    hits = {}
    for name, _g, rx in PATTERNS:
        ms = list(rx.finditer(text))
        if ms:
            counts[name] = len(ms)
            hits[name] = [text.count("\n", 0, m.start()) + 1 for m in ms[:200]]
    opts = Counter(m.group(1) for m in OPT_RX.finditer(text))
    for k, v in opts.items():
        counts["opt:" + k] = v
    return rel, counts, hits, nlines


def find_src(project, override):
    if override:
        return os.path.abspath(override)
    lf = os.path.join(project, "lakefile.toml")
    if os.path.isfile(lf):
        m = re.search(r'^\s*srcDir\s*=\s*"([^"]+)"', open(lf, encoding="utf-8").read(), re.M)
        if m:
            return os.path.join(project, m.group(1))
    return project


def list_lean(src):
    res = []
    for r, dirs, files in os.walk(src):
        dirs[:] = [d for d in dirs if d not in (".lake", ".git")]
        for f in files:
            p = os.path.join(r, f)
            if f.endswith(".lean") and not os.path.islink(p):
                res.append(os.path.relpath(p, src))
    return sorted(res)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("project")
    ap.add_argument("--src")
    ap.add_argument("--out", default="census_out")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 2)
    ap.add_argument("--show-max", type=int, default=60,
                    help="list file:line for patterns with at most this many hits")
    a = ap.parse_args()

    project = os.path.abspath(a.project)
    src = find_src(project, a.src)
    files = list_lean(src)
    print("source dir :", src)
    print("lean files : {:,}".format(len(files)))
    os.makedirs(a.out, exist_ok=True)

    total = Counter()
    nfiles = Counter()
    where = defaultdict(list)       # pattern -> [(rel, line)]
    per_dir = defaultdict(Counter)  # top folder -> pattern -> count
    lines_total = 0
    rows = []
    with ProcessPoolExecutor(a.jobs) as ex:
        for rel, counts, hits, nl in ex.map(scan_file, [(src, f) for f in files], chunksize=200):
            if counts is None:
                continue
            lines_total += nl
            top = rel.split(os.sep)[0] if os.sep in rel else "(root)"
            for k, v in counts.items():
                total[k] += v
                nfiles[k] += 1
                per_dir[top][k] += v
                rows.append((rel, k, v))
            for k, ls in hits.items():
                for ln in ls:
                    where[k].append((rel, ln))

    groups = defaultdict(list)
    for name, g, _rx in PATTERNS:
        groups[g].append(name)

    print("lines scanned: {:,}\n".format(lines_total))
    print("=" * 66)
    for g in ["unsound", "meta", "rebinding", "options"]:
        print("[{}]".format(g))
        print("  {:<24}{:>12}{:>10}".format("pattern", "occurrences", "files"))
        for name in groups[g]:
            print("  {:<24}{:>12,}{:>10,}".format(name, total[name], nfiles[name]))
        print()
    opts = sorted(((k[4:], v) for k, v in total.items() if k.startswith("opt:")), key=lambda x: -x[1])
    print("set_option by option name (top 25):")
    print("  {:<34}{:>12}{:>10}".format("option", "occurrences", "files"))
    for k, v in opts[:25]:
        print("  {:<34}{:>12,}{:>10,}".format(k, v, nfiles["opt:" + k]))
    print("=" * 66)

    shown = False
    for name, g, _rx in PATTERNS:
        n = total[name]
        if g in ("unsound", "meta", "rebinding") and 0 < n <= a.show_max:
            if not shown:
                print("\nExact locations for rare patterns (<= {} hits):".format(a.show_max))
                shown = True
            print("\n  {}  ({} hits)".format(name, n))
            for rel, ln in sorted(where[name]):
                print("    {}:{}".format(rel, ln))

    with open(os.path.join(a.out, "census_by_file.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["file", "pattern", "count"])
        w.writerows(sorted(rows))
    with open(os.path.join(a.out, "census_by_dir.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        pats = [n for n, _g, _r in PATTERNS]
        w.writerow(["top_folder"] + pats)
        for d in sorted(per_dir):
            w.writerow([d] + [per_dir[d][p] for p in pats])
    with open(os.path.join(a.out, "census_locations.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["pattern", "file", "line"])
        for name, _g, _r in PATTERNS:
            for rel, ln in sorted(where[name]):
                w.writerow([name, rel, ln])
    print("\nwrote census_by_file.csv, census_by_dir.csv, census_locations.csv in", a.out)
    print("(locations CSV keeps at most 200 hits per pattern per file)")


if __name__ == "__main__":
    sys.exit(main())
