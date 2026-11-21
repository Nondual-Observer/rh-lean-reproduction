#!/usr/bin/env python3
"""export_decls.py: list every declaration in a lean4export NDJSON file.

lean4export writes only the requested targets and what they depend on, so this list is exactly the set of
declarations the exported theorems use. Text only; nothing is executed.

Usage (filter with grep first; the export is 61 GB):
  zstd -dc --long=30 solution.ndjson.zst | grep -a -E '^\\{"(in|thm|def|opaque|axiom|quot|inductive)"' \\
     | python3 -I export_decls.py > used_decls.txt
Output: one fully qualified name per line, with its kind: "thm Foo.bar". Inductives also list their
constructors and recursors.
"""
import json, sys

names = {0: ""}
def nm(i):
    return names.get(i, "<%s>" % i)

out = sys.stdout
count = {}
for raw in sys.stdin:
    if raw.startswith('{"in"'):
        o = json.loads(raw)
        if "str" in o:
            p = o["str"]; pre = names.get(p["pre"], "")
            names[o["in"]] = (pre + "." if pre else "") + p["str"]
        elif "num" in o:
            p = o["num"]; pre = names.get(p["pre"], "")
            names[o["in"]] = (pre + "." if pre else "") + str(p["i"])
        continue
    o = json.loads(raw)
    (kind, body), = o.items()
    if kind == "inductive":
        for t in body.get("types", []): out.write("ind " + nm(t["name"]) + "\n"); count["ind"] = count.get("ind", 0) + 1
        for c in body.get("ctors", []): out.write("ctor " + nm(c["name"]) + "\n")
        for r in body.get("recs", []): out.write("rec " + nm(r["name"]) + "\n")
    else:
        out.write(kind + " " + nm(body["name"]) + "\n"); count[kind] = count.get(kind, 0) + 1
print("counts:", count, file=sys.stderr)
