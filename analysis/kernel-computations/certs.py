import math, sys
sys.setrecursionlimit(10000)
def nsub(a, b): return a - b if a > b else 0
def ndiv(a, b): return a // b if b else 0
def powMod(a, m, k, e):
    # Nat.rec (fun _ => 1) (fun _ ih e => (ih (e / 2) ^ 2 * a ^ (e % 2)) % m) k  -- applied to e
    if k == 0: return 1
    return (powMod(a, m, k - 1, e // 2) ** 2 * a ** (e % 2)) % m
def prod(l):
    r = 1
    for x in l: r *= x
    return r
def prime_of_cert(p, a, k, N, l):
    c = {"1<p": 1 < p, "p<2^k": p < 2 ** k,
         "p-1 | prod(l)^N": (prod(l) ** N) % (p - 1) == 0,
         "a^(p-1)=1": powMod(a, p, k, p - 1) % p == 1,
         "a^((p-1)/q)!=1 all q": all(powMod(a, p, k, ndiv(p - 1, q)) % p != 1 for q in l)}
    return all(c.values()), c
CERTS = [
 ("foundations_prime_fact_ter", 10944929, 3, 24, 5, [2, 571, 599]),
 ("prime_128860109809", 128860109809, 13, 40, 4, [2, 3, 47, 167, 571, 599]),
 ("foundations_prime_fact", 328347841, 11, 32, 6, [2, 3, 5, 571, 599]),
 ("foundations_prime_fact_bis", 1395478321, 11, 32, 4, [2, 3, 5, 17, 571, 599]),
 ("siteGood_prime_torsion", 1 + 599 * (123 * (16 * 571 * 599 * (10944929 * 128860109809) ** 2)) ** 2,
   5, 320, 8, [2, 3, 41, 571, 599, 10944929, 128860109809]),
]
if __name__ == "__main__":
    import sympy
    for name, p, a, k, N, l in CERTS:
        ok, c = prime_of_cert(p, a, k, N, l)
        print(f"{name}: p has {p.bit_length()} bits; certificate checks {ok}; sympy.isprime(p)={sympy.isprime(p)}; listed q all prime={all(sympy.isprime(q) for q in l)}")
        if not ok: print("   ", c)
    # negative: perturb p by 2
    print("neg (p+2 with same cert):", prime_of_cert(10944929 + 2, 3, 24, 5, [2, 571, 599])[0])
