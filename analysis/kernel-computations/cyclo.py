import re
from sympy import isprime
SRC = "/home/claude/rh-src/lean/src/Formalism/LocalToGlobal/Columns/CyclotomicIsCyclotomicExtension.lean"
txt = open(SRC).read()
val = lambda n: int(re.search(rf"def {n} : ℕ := (\d+)", txt).group(1))
t1, t2, nT, cB, nN = (val(n) for n in ["toyFirstParameter", "toySecondParameter", "nd2T", "columnDegreeBound", "nd2N"])
d, condN = 599, 16 * 571 * 599          # inferred above, not read from source
def nsub(a, b): return a - b if a > b else 0
def ndPowMod(m, f, a, e):
    if f == 0: return 1
    return (a if e % 2 == 1 else 1) * ndPowMod(m, f - 1, a * a % m, e // 2) % m
def lucas(p, a, f, L):
    prodv = 1
    for q, k in L: prodv *= q ** k
    return {"1<p": 1 < p, "prod = p-1": prodv == p - 1, "p-1<2^f": p - 1 < 2 ** f,
            "a^(p-1)=1": ndPowMod(p, f, a, p - 1) == 1,
            "a^((p-1)/q)!=1": all(ndPowMod(p, f, a, (p - 1) // q) % p != 1 for q, _ in L)}
checks = {}
for name, p, a, f, L in [("example_first_prime", t1, 5, 63, [(2, 10), (3, 4), (571, 2), (599, 3)]),
                         ("example_second_prime", t2, 5, 74, [(2, 24), (3, 2), (571, 2), (599, 3)]),
                         ("nd2T_prime", nT, 5, 614, [(2, 12), (3, 4), (13, 2), (571, 2), (599, 3), (t1, 4), (t2, 4)]),
                         ("columns_prime_fact", cB, 5, 616, [(2, 12), (3, 4), (23, 2), (571, 2), (599, 3), (t1, 4), (t2, 4)])]:
    c = lucas(p, a, f, L); checks[name] = all(c.values())
    print(f"{name}: {p.bit_length()}-bit; Lucas certificate {all(c.values())}; sympy.isprime {isprime(p)}")
K = condN * (t1 * t2) ** 2
facts = {
 "example_level_pos": 0 < nN, "condN | nd2N (cyclotomic_mono_of_dvd)": nN % condN == 0, "example_conductor_pos": 0 < condN,
 "first_norm_form": 1 + d * (condN * 18) ** 2 == t1, "second_norm_form": 1 + d * (condN * 768) ** 2 == t2,
 "num_nT": 1 + d * (K * 468) ** 2 == nT, "one_sq_add_d_mul_sq_eq_nd2T1": 1 + d * (K * 828) ** 2 == cB,
 "columns_num_fact": -((cB - 1) // 2) * 2 + (1 + d * (K * 828) ** 2) == 1,
 "columns_num_fact_bis": cB % condN == 1 % condN,
 "columns_num_fact_ter": cB != t1 and cB != t2 and nT != cB,
 "first_prime_identity": -((t1 - 1) // 2) * 2 + (1 + d * (condN * 18) ** 2) == 1,
 "second_prime_identity": -((t2 - 1) // 2) * 2 + (1 + d * (condN * 768) ** 2) == 1,
 "num_cT": -((nT - 1) // 2) * 2 + (1 + d * (K * 468) ** 2) == 1,
 "first_prime_modEq_one": t1 % condN == 1, "second_prime_modEq_one": t2 % condN == 1, "num_mT": nT % condN == 1,
 "primes_distinct": t1 != t2 and nT != t1 and nT != t2, "primes_gt_sixteen": 16 < t1 and 16 < t2,
 "primes_dvd_level": all(nN % x == 0 for x in [t1, t2, t1 - 1, t2 - 1, nT, cB]),
 "ChainInst h4 (both ≡ 1 mod 4)": t1 % 4 == 1 and t2 % 4 == 1,
 "ChainInst h1 (t1 ∤ condN·18)": (condN * 18) % t1 != 0, "ChainInst h2 (t2 ∤ condN·768)": (condN * 768) % t2 != 0,
}
for k, v in facts.items(): print(f"  {k}: {v}")
print("ALL:", all(checks.values()) and all(facts.values()))
print("neg (condN*2 breaks modEq):", t1 % (condN * 2) == 1 and t2 % (condN * 2) == 1 and nT % (condN * 2) == 1)
