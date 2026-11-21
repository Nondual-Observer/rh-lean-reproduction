#!/usr/bin/env python3
"""Search every .lean file for the names of ideas in the 20-step timeline of alpo.ge/remark.pdf.
Whole-word matching on CamelCase-split identifiers and paths. Text only.
Usage: python3 -I note_terms.py PROJECT/src out.json"""
import os, sys, json, re
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
SRC = sys.argv[1]
# timeline step number(s) from remark.pdf -> (label, list of word-sequences; any matches). Words are lowercase CamelCase parts.
TERMS = [
 ("1",  "Stepanov",               [["stepanov"]]),
 ("2",  "Invariant derivation",   [["invariant","derivation"]]),
 ("3",  "Path quadric",           [["quadric"]]),
 ("3",  "Iterated Parseval",      [["parseval"]]),
 ("5",  "Guinand–Weil",           [["guinand"]]),
 ("5",  "von Mangoldt Λ",         [["von","mangoldt"]]),
 ("7",  "GGP periods",            [["ggp"],["gan","gross","prasad"]]),
 ("7",  "Interlacing",            [["interlacing"],["interlace"]]),
 ("8",  "Theta lift",             [["theta","lift"],["theta","lifts"]]),
 ("9",  "Chowla–Selberg",         [["chowla"]]),
 ("9",  "Siegel mass",            [["siegel","mass"]]),
 ("11", "Iwasawa tower/theory",   [["iwasawa","tower"],["iwasawa","theory"],["iwasawa","module"],["iwasawa","algebra"],["iwasawa","main"]]),
 ("12", "Seesaw",                 [["seesaw"]]),
 ("12", "Bessel period",          [["bessel","period"],["bessel","periods"]]),
 ("12", "Rallis",                 [["rallis"]]),
 ("13", "Bost slope inequality",  [["bost"],["slope","inequality"]]),
 ("16", "Relative trace formula", [["relative","trace","formula"]]),
 ("16", "Poincaré series",        [["poincare","series"]]),
 ("17", "Vandiver",               [["vandiver"]]),
 ("18", "Covolume",               [["covol"],["covolume"]]),
 ("19", "Behrend",                [["behrend"]]),
 ("20", "Landau (zero-free)",     [["landau"]]),
 ("–",  "Tate–Shafarevich",       [["shafarevich"],["sha","len"]]),
 ("–",  "Local Langlands",        [["local","langlands"]]),
 ("–",  "Galois representation",  [["galois","rep"],["galois","representation"],["galois","representations"]]),
 ("–",  "Weil representation",    [["weil","representation"]]),
]
SPLIT = re.compile(r"[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z]+|[A-Z]+|\d+")
def words(s):
    out = []
    for tok in re.split(r"[^A-Za-z0-9]+", s):
        out.extend(w.lower() for w in SPLIT.findall(tok))
    return out
def has(ws, seq):
    n = len(seq)
    if n == 1:
        return seq[0] in ws_set_cache.get(id(ws), set())
    first = seq[0]
    for i, w in enumerate(ws):
        if w == first and ws[i:i+n] == seq: return True
    return False
ws_set_cache = {}
def match(ws):
    s = set(ws); hits = []
    for idx, (_, lab, seqs) in enumerate(TERMS):
        for seq in seqs:
            if len(seq) == 1:
                if seq[0] in s: hits.append(idx); break
            elif seq[0] in s and all(x in s for x in seq):
                n = len(seq)
                if any(ws[i:i+n] == seq for i, w in enumerate(ws) if w == seq[0]): hits.append(idx); break
    return hits
def scan(rel):
    try: txt = open(os.path.join(SRC, rel), 'rb').read().decode('utf8', 'replace')
    except OSError: return rel, [], []
    return rel, match(words(rel[:-5])), match(words(txt))
files = []
for r, d, fs in os.walk(SRC):
    for f in fs:
        if f.endswith('.lean'): files.append(os.path.relpath(os.path.join(r, f), SRC))
files.sort()
res = [{"step": st, "label": lab, "path": 0, "content": 0, "by_lib": Counter(), "by_sub": Counter(), "examples": []} for st, lab, _ in TERMS]
with ProcessPoolExecutor(2) as ex:
    for rel, ip, ic in ex.map(scan, files, chunksize=400):
        parts = rel.split('/')
        for i in ip:
            res[i]["path"] += 1
            if len(res[i]["examples"]) < 3: res[i]["examples"].append(rel[:-5].replace('/', '.'))
        for i in ic:
            res[i]["content"] += 1
            res[i]["by_lib"][parts[0]] += 1
            res[i]["by_sub"]["/".join(parts[:2])] += 1
for r in res:
    r["by_lib"] = dict(r["by_lib"].most_common()); r["top_sub"] = r.pop("by_sub").most_common(3)
json.dump({"files": len(files), "res": res}, open(sys.argv[2], 'w'), indent=1)
for r in res:
    print(f"{r['step']:>3} {r['label']:26s} path:{r['path']:6d} files-mentioning:{r['content']:6d}  top:{r['top_sub'][:1]}  ex:{r['examples'][:1]}")
