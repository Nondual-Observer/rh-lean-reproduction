# Faithful Python ports of Lean `decide +kernel` computations.
# Lean Nat semantics: a - b truncates at 0; a / b is floor and a / 0 = 0.
import math, sys, time
def nsub(a, b): return a - b if a > b else 0
def ndiv(a, b): return a // b if b else 0

# ---- PI.PrimesDyadicRS.K (DyadicPrimeIntervals/SmallLoop.lean) ----
def tstR(h, d):
    return (0 < d) and (2 ** (ndiv(7680000000000 * (h + 1), 10 * d * 6931471803) + 257) <= h ** 256)
def pr(Q, m):
    if m <= 362:
        return 1 if math.gcd(m, math.factorial(nsub(m, 1))) == 1 else 0
    return 1 if math.gcd(m, Q) == 1 else 0
def nxt(Q, h, d):
    return nsub(d + pr(Q, h + 1), pr(Q, (h + 1) // 2) if (h + 1) % 2 == 0 else 0)
def loop_K(Q, hT, dT, k, h, d):
    # iterative form of the structural recursion; && short-circuits like Lean's Bool.and
    while k > 0:
        if not (h < 41 or tstR(h, d)):
            return False, h, d
        h, d, k = h + 1, nxt(Q, h, d), k - 1
    return (h == hT and d == dT), h, d
def run(hT, dT, k, h, d):
    return loop_K(math.factorial(362), hT, dT, k, h, d)

# ---- PI.PC (ChebyshevPrimeBounds/SmallLoop.lean) ----
def tst(n, c):
    return n ** 256 < 2 ** ndiv(nsub(3225600000000 * n, 1), c * 6931471808)
def loop_PC(B, k, n, c, Q):
    while k > 0:
        if math.gcd(n, Q) == 1:
            if not tst(n, c + 1): return False, n, c
            n, c, Q = n + 1, c + 1, (Q * n if n <= B else Q)
        else:
            if not tst(n, c): return False, n, c
            n = n + 1
        k -= 1
    return True, n, c

if __name__ == "__main__":
    cases = [("run1", (32768, 1612, 32766, 2, 1)), ("run2", (65536, 3030, 32768, 32768, 1612)),
             ("run3", (98304, 4388, 32768, 65536, 3030)), ("run4", (131072, 5709, 32768, 98304, 4388))]
    for name, a in cases:
        t = time.time(); ok, h, d = run(*a)
        print(f"{name}: run{a} = {ok}   (ended at h={h}, d={d})  {time.time()-t:.1f}s")
    t = time.time(); ok, n, c = loop_PC(362, 131070, 2, 0, 1)
    print(f"loop_run: loop 362 131070 2 0 1 = {ok}   (ended at n={n}, c={c})  {time.time()-t:.1f}s")
