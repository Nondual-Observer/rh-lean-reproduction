import math, re, sys, time
from functools import reduce
SRC = sys.argv[1]
def nsub(a, b): return a - b if a > b else 0
def ndiv(a, b): return a // b if b else 0
def log2(n): return n.bit_length() - 1 if n > 0 else 0   # Nat.log2 0 = 0

# ---- IRRPrimeRecipSum: ladder ----
def test(F, r, a, b, p):
    return (p + 3 <= a) and (b < 2 * p) and (r < p) and (p < (r + 1) * (r + 1)) and math.gcd(p, F) == 1
def term(M, F, r, a, b, p): return ndiv(M, p) if test(F, r, a, b, p) else 0
def bsum(t, k, lo):            # = sum_{p in [lo, lo + 2^k)} t p  (bsum_eq)
    return sum(t(p) for p in range(lo, lo + 2 ** k))
def chk(M, F, r, a, b):
    return M <= 20 * bsum(lambda p: term(M, F, r, a, b, p), log2(a), b // 2)
def ladder(M, F, r, T, f, a):
    while True:
        if T <= a: return True
        if f == 0: return False
        if not chk(M, F, r, a, a + a // 10): return False
        f, a = f - 1, a + a // 10 + 1

# ---- InvFiveLogLeSumInvPrimes: table_ok ----
def noSmallDiv(p, D):
    return all((p < d * d) or (d < 2) or (p % d != 0) for d in range(1, D + 1))
def sortedB(L): return all(L[i] < L[i + 1] for i in range(len(L) - 1))
def okIv(a, b, j, c, L):
    return (all(2 <= p and p < 17161 and noSmallDiv(p, 130) and b <= 2 * p and p + 3 <= a and p <= c for p in L)
            and sortedB(L) and 2 ** j <= a and 0 < c and c * 10 ** 10 <= 5 * len(L) * j * 6931471803)
def okAll(lo, table, hi):
    for (a, b, j, c, L) in table:
        if not (a <= lo and okIv(a, b, j, c, L)): return False
        lo = b
    return hi <= lo
txt = open(SRC + "/Development/AbelianVarietyTheory/Proofs/DivisorProofs/InvFiveLogLeSumInvPrimes.lean").read()
block = txt[txt.index("def table"):txt.index("theorem table_ok")]
rows = [(int(a), int(b), int(j), int(c), [int(x) for x in L.split(",")])
        for a, b, j, c, L in re.findall(r"\((\d+), (\d+), (\d+), (\d+), \[([\d, ]+)\]\)", block)]

def lcmUpto(n): return reduce(lambda x, y: x * y // math.gcd(x, y), range(1, n + 1), 1)

if __name__ == "__main__":
    for name, args in [("factorial_ladder_thirteen", (10**9, math.factorial(13), 13, 196, 60, 100)),
                       ("factorial_ladder_thirty_one", (10**9, math.factorial(31), 31, 1024, 60, 196)),
                       ("factorial_ladder_one_forty_one", (10**9, math.factorial(141), 141, 20000, 60, 1024))]:
        t = time.time(); print(f"{name}: {ladder(*args)}  ({time.time()-t:.1f}s)")
    print(f"table_ok: rows parsed = {len(rows)}, primes listed = {sum(len(r[4]) for r in rows)}, okAll 100 table 16900 = {okAll(100, rows, 16900)}")
    # independent check: every listed number is really prime
    isp = lambda n: n > 1 and all(n % d for d in range(2, math.isqrt(n) + 1))
    print("   all listed numbers prime (trial division):", all(isp(p) for r in rows for p in r[4]))
    print("lcmUpto_le_three_pow (n < 30):", all(lcmUpto(n) <= 3 ** n for n in range(30)))
    print("lcmUpto_le_four_pow_small (n <= 100):", all(lcmUpto(n) <= 4 ** n for n in range(101)))
    # negative tests
    print("neg: ladder target 20001 w/ same steps ->", ladder(10**9, math.factorial(141), 141, 10**9, 60, 1024),
          "| lcmUpto n <= 2^n for n<30 ->", all(lcmUpto(n) <= 2 ** n for n in range(30)))
