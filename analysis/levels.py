#!/usr/bin/env python3
"""levels.py: which universe levels does a lean4export file actually use?

Reads a lean4export NDJSON stream on stdin. TEXT ONLY: nothing is executed.

Why: on Zulip (metakuntyyy, Mario Carneiro, 4:46-4:53 PM) people asked whether the proof
needs more than ZFC, i.e. how many universes it really uses. The exported proof is the
ground truth for that: every universe level that appears in a `Sort` or in the level
arguments of a constant is a level record in the export.

Usage (pre-filter with grep so Python only sees the relevant lines; ~100x faster):

  zstd -dc --long=30 solution.ndjson.zst \
    | grep -a -E '^\\{"(il|in)"|"sort":|"us":' | python3 -I levels.py

  # or from your own export (KEEP=1 8_export_hash.sh):
  grep -a -E '^\\{"(il|in)"|"sort":|"us":' $HOME/rh/out/solution.export | python3 -I levels.py

What it prints:
  * how many level records, and how many are concrete (no parameters)
  * a histogram of CONCRETE levels used in `Sort` and in constant arguments
  * the largest concrete level and the first constants/sorts that use it
  * the largest "offset" over a parameter (e.g. u+3), for universe-polymorphic code

Reading the numbers: `Type n` is `Sort (n+1)`. The levels are those that APPEAR in the
export. A universe-polymorphic declaration instantiated at a concrete level shows up as a
concrete level in a constant's `us` list, so those are counted. This is a census of the
levels that occur, not a proof-theoretic bound: turning it into "ZFC plus k inaccessibles
suffices" needs a logician. Treat it as the input for that question, not the answer.
"""
import json
import sys
from collections import Counter


def main():
    conc = {0: 0}
    off = {0: 0}
    in_raw = {}          # name id -> raw JSON bytes (parsed lazily only if needed)
    used_sort = {}       # level id -> count
    used_const = {}      # level id -> count
    examples = {}        # level id -> list of up to 3 (kind, detail_or_name_id)
    n_level = 0

    loads = json.loads
    conc_get = conc.get
    off_get = off.get
    us_get = used_sort.get
    uc_get = used_const.get
    ex_get = examples.get
    _int = int

    for raw in sys.stdin.buffer:
        if raw.startswith(b'{"in"'):
            if raw[5:6] == b':':
                comma = raw.find(b',', 6)
                if comma != -1:
                    try:
                        in_raw[_int(raw[6:comma])] = raw
                        continue
                    except ValueError:
                        pass
            o = loads(raw)
            in_raw[o["in"]] = raw
            continue

        if raw.startswith(b'{"il"'):
            o = loads(raw)
            i = o["il"]
            n_level += 1
            if "succ" in o:
                s = o["succ"]
                c = conc_get(s)
                conc[i] = None if c is None else c + 1
                off[i] = off_get(s, 0) + 1
            elif "param" in o:
                conc[i] = None
                off[i] = 0
            elif "max" in o:
                a, b = o["max"]
                ca = conc_get(a)
                cb = conc_get(b)
                conc[i] = None if (ca is None or cb is None) else (ca if ca >= cb else cb)
                da = off_get(a, 0)
                db = off_get(b, 0)
                off[i] = da if da >= db else db
            elif "imax" in o:
                a, b = o["imax"]
                ca = conc_get(a)
                cb = conc_get(b)
                if ca is None or cb is None:
                    conc[i] = None
                else:
                    conc[i] = 0 if cb == 0 else (ca if ca >= cb else cb)
                da = off_get(a, 0)
                db = off_get(b, 0)
                off[i] = da if da >= db else db
            continue

        # Fast path for compact lean4export expr lines: {"ie":...,"sort":...} or {"ie":...,"const":{"name":...,"us":[...]}}
        if raw.startswith(b'{"ie":'):
            comma = raw.find(b',', 6)
            if comma != -1:
                if raw.startswith(b',"const":{"name":', comma):
                    us_idx = raw.find(b',"us":[', comma + 17)
                    if us_idx != -1:
                        end_b = raw.find(b']', us_idx + 7)
                        if end_b != -1:
                            us_bytes = raw[us_idx + 7:end_b]
                            if not us_bytes:
                                continue
                            try:
                                cname = _int(raw[comma + 17:us_idx])
                                if b',' not in us_bytes:
                                    l = _int(us_bytes)
                                    used_const[l] = uc_get(l, 0) + 1
                                    ex = ex_get(l)
                                    if ex is None:
                                        examples[l] = [("const", cname)]
                                    elif len(ex) < 3:
                                        ex.append(("const", cname))
                                else:
                                    for tok in us_bytes.split(b','):
                                        l = _int(tok)
                                        used_const[l] = uc_get(l, 0) + 1
                                        ex = ex_get(l)
                                        if ex is None:
                                            examples[l] = [("const", cname)]
                                        elif len(ex) < 3:
                                            ex.append(("const", cname))
                                continue
                            except ValueError:
                                pass
                elif raw.startswith(b',"sort":', comma):
                    end_b = raw.find(b'}', comma + 8)
                    if end_b != -1:
                        try:
                            l = _int(raw[comma + 8:end_b])
                            used_sort[l] = us_get(l, 0) + 1
                            ex = ex_get(l)
                            if ex is None:
                                examples[l] = [("Sort", _int(raw[6:comma]))]
                            elif len(ex) < 3:
                                ex.append(("Sort", _int(raw[6:comma])))
                            continue
                        except ValueError:
                            pass

        # Fallback for non-compact JSON or other records
        if b'"sort"' not in raw and b'"const"' not in raw:
            continue
        o = loads(raw)
        l = o.get("sort")
        if l is not None:
            used_sort[l] = us_get(l, 0) + 1
            ex = ex_get(l)
            if ex is None:
                examples[l] = [("Sort", o["ie"])]
            elif len(ex) < 3:
                ex.append(("Sort", o["ie"]))
        else:
            c = o.get("const")
            if c is not None:
                us = c.get("us")
                if us:
                    cname = c["name"]
                    for l in us:
                        used_const[l] = uc_get(l, 0) + 1
                        ex = ex_get(l)
                        if ex is None:
                            examples[l] = [("const", cname)]
                        elif len(ex) < 3:
                            ex.append(("const", cname))

    name_cache = {0: ""}

    def resolve_name(nid):
        res = name_cache.get(nid)
        if res is not None:
            return res
        raw = in_raw.get(nid)
        if raw is None:
            return "<name %s>" % nid
        o = loads(raw)
        if "str" in o:
            p = o["str"]
            pre = resolve_name(p["pre"]) if p["pre"] in in_raw or p["pre"] == 0 else ""
            val = (pre + "." if pre else "") + p["str"]
        elif "num" in o:
            p = o["num"]
            pre = resolve_name(p["pre"]) if p["pre"] in in_raw or p["pre"] == 0 else ""
            val = (pre + "." if pre else "") + str(p["i"])
        else:
            val = "<name %s>" % nid
        name_cache[nid] = val
        return val

    print("level records            : {:,}".format(n_level))
    print("concrete (no parameters) : {:,}".format(sum(1 for v in conc.values() if v is not None)))

    hist_s, hist_c = Counter(), Counter()
    for l, k in used_sort.items():
        v = conc_get(l)
        if v is not None:
            hist_s[v] += k
    for l, k in used_const.items():
        v = conc_get(l)
        if v is not None:
            hist_c[v] += k

    print("\nconcrete level -> uses in Sort | uses as a constant's level argument")
    keys = sorted(set(hist_s) | set(hist_c))
    for v in keys:
        print("  {:>3}  {:>14,}  {:>14,}".format(v, hist_s[v], hist_c[v]))

    top = keys[-1] if keys else None
    print("\nlargest concrete level used: {}   (Type {} = Sort {})".format(
        top, None if top is None else max(top - 1, 0), top))
    if top is not None:
        print("first uses of that level:")
        for l, ex in examples.items():
            if conc_get(l) == top:
                for kind, d in ex:
                    if kind == "Sort":
                        print("   ", kind, "expr %s" % d)
                    else:
                        print("   ", kind, resolve_name(d))

    sym = [off_get(l, 0) for l in set(used_sort) | set(used_const) if conc_get(l) is None]
    if sym:
        print("\nlargest offset over a parameter (u+k) in used levels: k = {}".format(max(sym)))


if __name__ == "__main__":
    main()
