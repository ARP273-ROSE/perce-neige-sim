"""Parité PC ↔ PWA : confronte les séries du banc Godot (bench_voyages_3d.gd)
aux CSV du banc Python (tests/bench_voyages.py), à position égale.

    python tests/parite_pwa.py bench_3d.txt bench_out/
"""
import csv
import os
import sys


def lire_3d(path):
    series, sums = {}, {}
    with open(path) as f:
        for line in f:
            if line.startswith("ROW,"):
                p = line.strip().split(",")
                series.setdefault(p[1], []).append(tuple(float(x) for x in p[2:]))
            elif line.startswith("SUM,"):
                p = line.strip().split(",")
                sums[p[1]] = p[2:]
    return series, sums


def lire_pc(dossier, nom):
    with open(os.path.join(dossier, nom + ".csv")) as f:
        return [{k: float(v) for k, v in r.items()} for r in csv.DictReader(f)]


def main():
    series, sums = lire_3d(sys.argv[1])
    dossier = sys.argv[2]
    print(f"{'cas':22s} {'pts':>4s}  écarts p95/max : P, R (kW), T (daN) ; Δdurée")
    pire = 0.0
    # Les deux codes n'ont pas le même repère d'arrêt (PC 26/3448 m, PWA
    # 20/3457 m) : on interpole les séries PC à la position PWA, hors
    # accélération/approche (|v| ≥ 11,9 des deux côtés) et hors ±15 m des
    # bords de l'évitement (la traînée y bascule d'un coup : un décalage
    # d'un pas y vaut 200 kW sans que la physique diffère).
    BORDS = (1611.0, 1813.0, 3474.0 - 1813.0, 3474.0 - 1611.0)

    def interp(pc, key, x):
        pts = sorted((q["s"], q[key], abs(q["v"])) for q in pc)
        for a_, b_ in zip(pts, pts[1:]):
            if a_[0] <= x <= b_[0]:
                if min(a_[2], b_[2]) < 11.9:
                    return None
                k = (x - a_[0]) / max(b_[0] - a_[0], 1e-9)
                return a_[1] + k * (b_[1] - a_[1])
        return None
    for nom, rows3 in series.items():
        pc = lire_pc(dossier, nom)
        ecarts = {"P": [], "R": [], "T": []}
        for (t, s, sg, v, p, r, T, th, rl) in rows3:
            if abs(v) < 11.9 or any(abs(s - b) < 15.0 for b in BORDS):
                continue
            ref = (interp(pc, "power_kw", s), interp(pc, "regen_kw", s),
                   interp(pc, "tension_dan", s))
            if None in ref:
                continue
            ecarts["P"].append(abs(ref[0] - p))
            ecarts["R"].append(abs(ref[1] - r))
            ecarts["T"].append(abs(ref[2] - T))
        n = len(ecarts["P"])
        if n == 0:
            print(f"{nom:22s} aucun point comparable"); continue
        def p95(l):
            l = sorted(l); return l[int(0.95 * (len(l) - 1))]
        dur3 = rows3[-1][0]
        print(f"{nom:22s} {n:4d}  P {p95(ecarts['P']):6.1f}/{max(ecarts['P']):6.1f}  "
              f"R {p95(ecarts['R']):6.1f}/{max(ecarts['R']):6.1f}  "
              f"T {p95(ecarts['T']):6.0f}/{max(ecarts['T']):6.0f}   {dur3 - pc[-1]['t']:+5.1f} s")
        pire = max(pire, p95(ecarts["P"]) / 20.0, p95(ecarts["R"]) / 20.0,
                   p95(ecarts["T"]) / 300.0)
    print("PARITÉ", "OK" if pire <= 1.0 else "ÉCART (p95 > 20 kW ou > 300 daN)")


if __name__ == "__main__":
    main()
