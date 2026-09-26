"""Banc d'audit physique : voyages complets, montée et descente.

Pour chaque combinaison de charge (rame pilotée / contrepoids), un trajet
complet à consigne pleine, dans les deux sens. À chaque pas on note tout
ce que le pupitre affiche (puissance, régénération, tension, frein,
régulateur) et l'état physique (position, pente locale des DEUX rames,
vitesse, accélération, masses). Les séries vont en CSV pour être
recalculées indépendamment (script Sage `audit_voyages.sage`).

Test MIROIR : monter la rame PLEINE avec un contrepoids VIDE est la même
situation physique que descendre la rame VIDE avec un contrepoids PLEIN
(même câble, mêmes deux rames) : la puissance, la régénération et la
tension doivent coïncider, position de la rame pleine pour position de la
rame pleine. L'écart entre les deux séries mesure l'asymétrie du modèle.

Exécution : QT_QPA_PLATFORM=offscreen python tests/bench_voyages.py [dossier_sortie]
"""
import csv
import math
import os
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import perce_neige_sim as pn  # noqa: E402

DT = 1.0 / 60.0
LOG_EVERY = 0.5          # s entre deux lignes de CSV
T_MAX = 900.0

CHARGES = [              # (pax rame pilotée, pax contrepoids), étiquette
    (0, 0, "vide_vide"),
    (334, 0, "pleine_vide"),
    (0, 334, "vide_pleine"),
    (334, 334, "pleine_pleine"),
    (167, 167, "demi_demi"),
]

COLS = ["t", "s", "s_ghost", "v", "a", "grad_main", "grad_ghost", "alt_main",
        "alt_ghost", "m_main", "m_ghost", "throttle", "regen_level", "brake",
        "power_kw", "regen_kw", "tension_dan", "in_loop", "speed_cmd_eff"]


def make(direction, pax, gpax, cmd=1.0):
    st = pn.GameState()
    st.mode = pn.MODE_RUN
    tr = st.train
    tr.pax_car1 = pax // 2
    tr.pax_car2 = pax - pax // 2
    tr.pax1_f = float(tr.pax_car1)
    tr.pax2_f = float(tr.pax_car2)
    st.ghost_pax = gpax
    st.ghost_f = float(gpax)
    tr.direction = direction
    tr.s = pn.START_S if direction > 0 else pn.STOP_S
    st.ghost_s = pn.LENGTH - tr.s
    tr.v = 0.0
    tr.doors_open = False
    tr.doors_cmd = False
    tr.maint_brake = False
    st.trip_started = True
    tr.speed_cmd = cmd
    return st, pn.Physics(st)


def voyage(direction, pax, gpax, cmd=1.0):
    st, ph = make(direction, pax, gpax, cmd)
    tr = st.train
    rows = []
    t = 0.0
    next_log = 0.0
    e_trac = e_regen = 0.0          # kWh
    while not st.finished and t < T_MAX:
        ph.step(DT)
        t += DT
        e_trac += tr.power_kw * DT / 3600.0
        e_regen += tr.regen_kw * DT / 3600.0
        if t >= next_log:
            next_log += LOG_EVERY
            rows.append({
                "t": round(t, 3), "s": tr.s, "s_ghost": st.ghost_s,
                "v": tr.v, "a": tr.a,
                "grad_main": pn.gradient_at(tr.s),
                "grad_ghost": pn.gradient_at(pn.LENGTH - tr.s),
                "alt_main": pn.geom_at(tr.s)[1],
                "alt_ghost": pn.geom_at(pn.LENGTH - tr.s)[1],
                "m_main": tr.mass_kg,
                "m_ghost": pn.TRAIN_EMPTY_KG + st.ghost_pax * pn.PAX_KG,
                "throttle": tr.throttle, "regen_level": tr.regen_level,
                "brake": tr.brake, "power_kw": tr.power_kw,
                "regen_kw": tr.regen_kw, "tension_dan": tr.tension_dan,
                "in_loop": int(pn.is_passing_loop(tr.s)),
                "speed_cmd_eff": tr.speed_cmd_eff,
            })
    resume = {
        "fini": st.finished, "duree_s": t,
        "v_max": max(abs(r["v"]) for r in rows),
        "P_max_kw": max(r["power_kw"] for r in rows),
        "regen_max_kw": max(r["regen_kw"] for r in rows),
        "E_trac_kwh": e_trac, "E_regen_kwh": e_regen,
        "T_max_dan": max(r["tension_dan"] for r in rows),
        "T_min_dan": min(r["tension_dan"] for r in rows[5:] or rows),
        "brake_max": max(r["brake"] for r in rows),
        "frein_et_moteur": sum(1 for r in rows
                               if r["brake"] > 0.05 and r["power_kw"] > 1.0),
        "regen_et_moteur": sum(1 for r in rows
                               if r["regen_kw"] > 1.0 and r["power_kw"] > 1.0),
    }
    return rows, resume


def ecrire(dossier, nom, rows):
    with open(os.path.join(dossier, nom + ".csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=COLS)
        w.writeheader()
        for r in rows:
            w.writerow(r)


def miroir(rows_up, rows_down):
    """Compare montée (pleine/vide) et descente (vide/pleine) à position
    égale de la rame PLEINE : en montée c'est la rame pilotée (s), en
    descente c'est le contrepoids (s_ghost)."""
    def interp(rows, key_pos, key_val, x):
        pts = sorted((r[key_pos], r[key_val]) for r in rows)
        if x <= pts[0][0]:
            return pts[0][1]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            if x0 <= x <= x1:
                return y0 if x1 == x0 else y0 + (y1 - y0) * (x - x0) / (x1 - x0)
        return pts[-1][1]
    out = []
    for s in range(300, 3200, 100):
        p_up = interp(rows_up, "s", "power_kw", s)
        r_up = interp(rows_up, "s", "regen_kw", s)
        t_up = interp(rows_up, "s", "tension_dan", s)
        v_up = abs(interp(rows_up, "s", "v", s))
        p_dn = interp(rows_down, "s_ghost", "power_kw", s)
        r_dn = interp(rows_down, "s_ghost", "regen_kw", s)
        t_dn = interp(rows_down, "s_ghost", "tension_dan", s)
        v_dn = abs(interp(rows_down, "s_ghost", "v", s))
        out.append((s, v_up, v_dn, p_up, p_dn, r_up, r_dn, t_up, t_dn))
    return out


def main():
    dossier = sys.argv[1] if len(sys.argv) > 1 else "bench_out"
    os.makedirs(dossier, exist_ok=True)
    print(f"{'trajet':22s} {'fini':4s} {'durée':>6s} {'vmax':>5s} {'Pmax':>6s} "
          f"{'Rmax':>6s} {'Etrac':>6s} {'Ereg':>6s} {'Tmax':>6s} {'Tmin':>6s} "
          f"{'frein':>5s} {'F&M':>4s} {'R&M':>4s}")
    series = {}
    for pax, gpax, nom in CHARGES:
        for direction, fleche in ((1, "montee"), (-1, "descente")):
            rows, res = voyage(direction, pax, gpax)
            key = f"{fleche}_{nom}"
            series[key] = rows
            ecrire(dossier, key, rows)
            print(f"{key:22s} {'oui' if res['fini'] else 'NON':4s} "
                  f"{res['duree_s']:6.0f} {res['v_max']:5.2f} "
                  f"{res['P_max_kw']:6.0f} {res['regen_max_kw']:6.0f} "
                  f"{res['E_trac_kwh']:6.1f} {res['E_regen_kwh']:6.1f} "
                  f"{res['T_max_dan']:6.0f} {res['T_min_dan']:6.0f} "
                  f"{res['brake_max']:5.2f} {res['frein_et_moteur']:4d} "
                  f"{res['regen_et_moteur']:4d}")
    print("\nMIROIR — montée pleine/vide vs descente vide/pleine, à position "
          "égale de la rame PLEINE :")
    print(f"{'s_pleine':>8s} {'v↑':>5s} {'v↓':>5s} {'P↑':>6s} {'P↓':>6s} "
          f"{'R↑':>6s} {'R↓':>6s} {'T↑':>6s} {'T↓':>6s}")
    for row in miroir(series["montee_pleine_vide"], series["descente_vide_pleine"]):
        s, v_up, v_dn, p_up, p_dn, r_up, r_dn, t_up, t_dn = row
        print(f"{s:8d} {v_up:5.2f} {v_dn:5.2f} {p_up:6.0f} {p_dn:6.0f} "
              f"{r_up:6.0f} {r_dn:6.0f} {t_up:6.0f} {t_dn:6.0f}")


if __name__ == "__main__":
    main()
