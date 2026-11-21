import sys, json, gzip, subprocess, os
def fnv(s):
    h = 0x811c9dc5
    for b in s.encode(): h ^= b; h = (h * 0x01000193) & 0xffffffff
    return h
CACHE = "/home/claude/dk/shards"; os.makedirs(CACHE, exist_ok=True); _m = {}
def shard(sh):
    p = f"{CACHE}/{sh}.gz"
    if not os.path.exists(p) or os.path.getsize(p) < 1000:
        subprocess.run(["curl", "-sS", "-m", "30", "-A", "Mozilla/5.0", "-o", p, f"https://riemann.tamnd.com/api/decl/{sh}.json.gz"], check=True)
    if sh not in _m:
        raw = open(p, "rb").read()
        try: raw = gzip.decompress(raw)
        except Exception: pass
        _m[sh] = {r["n"]: r for r in json.loads(raw)}
    return _m[sh]
def get(n): return shard("%03x" % (fnv(n) % 4096)).get(n)
if __name__ == "__main__":
    for n in sys.argv[1:]:
        r = get(n)
        if not r: print(f"{n}: NOT IN INDEX"); continue
        x = r.get("x"); t = r.get("t") or []
        print(f"\n## {n}\n   file {r['f']}:{r['l']}  kind {r['k']}")
        print(f"   used by riemannHypothesis: {'yes, depth %d' % x['d'] if x else 'no'}")
        if t: print("   trail: " + "  ->  ".join(s.split('.')[-1] for s in t))
        print(f"   uses {len(r.get('u',[]))} names; used by {len(r.get('b',[]))}: {[b.split('.')[-1] for b in r.get('b',[])[:6]]}")
