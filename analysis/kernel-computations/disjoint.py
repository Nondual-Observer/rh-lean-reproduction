import math
from sympy import isprime
def nsub(a, b): return a - b if a > b else 0
def prod(l):
    r = 1
    for x in l: r *= x
    return r
def prodPowSubOne(g): return prod(nsub(g ** (i + 1), 1) for i in range(9))
A, B = 413718278401, 603339156001
L = [2, 3, 5, 7, 11, 13, 37, 571, 599]
pa, pb = prodPowSubOne(A), prodPowSubOne(B)
print("Primes.lean / BB_disj0")
print("  A, B prime:", isprime(A), isprime(B))
print("  not A | prodPowSubOne B:", pb % A != 0)
print("  not B | prodPowSubOne A:", pa % B != 0)
g = math.gcd(pa, pb)
print("  gcd(prodPowSubOne A, prodPowSubOne B) | prod(L)^52:", (prod(L) ** 52) % g == 0, " gcd =", g)
print("  every q in L prime:", all(isprime(q) for q in L))
key = all(any((nsub(A ** d, 1) % (l ** (k + 1)) != 0) and l ** (4 * k) <= A ** d for k in range(20))
          for l in L for d in range(10) if 1 <= d)
print("  key (for each l, d in 1..9 some k<20 works):", key)

print("FoundationsPrimeFact / bb_disjoint")
G1, G2 = 10944929, 128860109809
L2 = [2, 3, 5, 7, 19, 571, 599]
n = math.gcd(G1 * prod(nsub(G1 ** (i + 1), 1) for i in range(9)), G2 * prod(nsub(G2 ** (i + 1), 1) for i in range(9)))
print("  gcd(...) | prod(L2)^43:", (prod(L2) ** 43) % n == 0)
print("  128860109809 not in L2:", G2 not in L2)
hall = all(1 < x and x ** (4 * k) <= G2 and all(nsub(G2 ** e, 1) % (x ** (k + 1)) != 0 for e in range(1, 10))
           for x, k in [(2, 7), (3, 3), (5, 1), (7, 2), (19, 1), (571, 1), (599, 1)])
print("  hall:", hall)
