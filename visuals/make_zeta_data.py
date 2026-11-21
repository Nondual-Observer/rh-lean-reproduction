#!/usr/bin/env python3
"""Data embedded in proof-math.html: the first 100 zeros of zeta and Hardy's Z(t) for 0 <= t <= 60.
Run: python3 make_zeta_data.py  (needs mpmath). Writes zdata.json."""
import json, mpmath
mpmath.mp.dps = 20
zeros = [round(float(mpmath.zetazero(n).imag), 6) for n in range(1, 101)]
zt = [round(float(mpmath.siegelz(0.05 * i)), 4) for i in range(1201)]
json.dump({"zeros": zeros, "zt": zt, "dt": 0.05}, open("zdata.json", "w"))
print(len(zeros), "zeros; first", zeros[0], "last", zeros[-1])
