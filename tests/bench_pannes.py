"""Banc d'audit physique : pannes + types d'arrêts.

Pour chaque panne : déclenchement en pleine croisière (montée chargée ET
descente chargée au contrepoids), 90 s simulées, métriques :
  - v finale, v max post-déclenchement, distance parcourue
  - décélération pic + jerk pic (à-coups)
  - temps pour rejoindre le plafond de panne (si cap)
  - puissance/frein/urgence incohérents (drapeaux)
  - le train s'arrête-t-il pour les pannes stopping/catastrophiques ?

Pour chaque type d'arrêt : depuis 12 m/s (et 6 m/s), montée et descente,
distance, durée, décél moyenne + pic — à comparer aux valeurs réelles.

Exécution : QT_QPA_PLATFORM=offscreen python tests/bench_pannes.py
"""
import math
import os
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import perce_neige_sim as pn  # noqa: E402

DT = 1.0 / 60.0


def make(direction, s0, pax, gpax, v0, cmd=1.0):
    st = pn.GameState()
    st.mode = pn.MODE_RUN
    tr = st.train
    tr.pax_car1 = pax // 2
    tr.pax_car2 = pax - pax // 2
    st.ghost_pax = gpax
    tr.direction = direction
    tr.s = s0
    tr.v = v0
    tr.doors_open = False
    tr.maint_brake = False
    tr.trip_started = True
    st.trip_started = True
    tr.speed_cmd = cmd
    tr.speed_cmd_eff = abs(v0)
    return st, pn.Physics(st)


def run(st, ph, t_max, on_t=None):
    tr = st.train
    hist = []
    t = 0.0
    v_prev = tr.v
    a_prev = 0.0
    while t < t_max:
        if on_t is not None:
            on_t(t, st)
        ph.step(DT)
        a = (tr.v - v_prev) / DT
        jerk = (a - a_prev) / DT
        hist.append((t, tr.v, a, jerk, tr.power_kw, tr.brake,
                     tr.throttle, tr.emergency, tr.overspeed_level, tr.s))
        v_prev, a_prev = tr.v, a
        t += DT
        if abs(tr.v) < 0.02 and t > 5.0 and abs(a) < 0.05:
            break
    return hist


def audit_fault(kind, direction):
    if direction > 0:
        st, ph = make(+1, 1200.0, 250, 8, 10.0)
    else:
        st, ph = make(-1, 2300.0, 8, 250, -10.0)
    trig = {"done": False}

    def on_t(t, st):
        if t >= 2.0 and not trig["done"]:
            pn.trigger_fault(st, kind)
            trig["done"] = True

    hist = run(st, ph, 90.0, on_t)
    tr = st.train
    post = [h for h in hist if h[0] >= 2.0]
    vmax = max(abs(h[1]) for h in post)
    vfin = abs(hist[-1][1])
    decel_pk = max((-h[2] * direction) for h in post)
    jerk_pk = max(abs(h[3]) for h in post)
    dist = abs(hist[-1][9] - 1200.0 if direction > 0 else hist[-1][9] - 2300.0)
    stopped = vfin < 0.1
    cap = tr.speed_fault_cap if tr.speed_fault_cap < pn.V_MAX else None
    t_cap = None
    if cap:
        for h in post:
            if abs(h[1]) <= cap + 0.15:
                t_cap = h[0] - 2.0
                break
    sev = pn.fault_profile(kind).get("severity", "?")
    flags = []
    if sev in ("stopping", "catastrophic") and not stopped:
        flags.append("NE S'ARRÊTE PAS")
    if cap and vfin > cap + 0.3 and not stopped:
        flags.append(f"v_fin {vfin:.1f} > cap {cap}")
    if cap and t_cap is not None and t_cap < (10.0 - cap) / 0.8:
        flags.append(f"cap atteint en {t_cap:.1f}s (trop brutal)")
    if decel_pk > 1.0 and not any(h[7] for h in post):
        flags.append(f"décél {decel_pk:.2f} sans urgence")
    if jerk_pk > 25.0:
        flags.append(f"jerk {jerk_pk:.0f}")
    print(f"  {kind:18s} {'↑' if direction > 0 else '↓'} [{sev:12s}] "
          f"vmax={vmax:5.2f} vfin={vfin:5.2f} decelPk={decel_pk:5.2f} "
          f"d={dist:6.0f}m t={hist[-1][0]:5.1f}s"
          f"{'  ⚠ ' + ' | '.join(flags) if flags else ''}")


def audit_stop(label, v0, direction, setup):
    s0 = 1200.0 if direction > 0 else 2300.0
    pax, gpax = (250, 8) if direction > 0 else (8, 250)
    st, ph = make(direction, s0, pax, gpax, v0 * direction)
    setup(st.train, st)
    hist = run(st, ph, 130.0)
    tr = st.train
    vfin = abs(hist[-1][1])
    dist = abs(hist[-1][9] - s0)
    dur = hist[-1][0]
    decel_pk = max((-h[2] * direction) for h in hist) if hist else 0.0
    mean = (abs(v0) ** 2) / (2 * dist) if dist > 1 else 0.0
    print(f"  {label:34s} {'↑' if direction > 0 else '↓'} v0={abs(v0):4.1f} "
          f"→ d={dist:6.1f}m t={dur:5.1f}s decel moy={mean:4.2f} "
          f"pic={decel_pk:4.2f} vfin={vfin:4.2f}"
          f"{'  ⚠ PAS ARRÊTÉ' if vfin > 0.1 else ''}")


print("=== AUDIT PANNES (déclenchement à t=2 s, croisière 10 m/s) ===")
for kind in pn.FAULT_KINDS:
    for d in (+1, -1):
        audit_fault(kind, d)

print()
print("=== AUDIT TYPES D'ARRÊTS ===")


def s_estop(tr, st):
    tr.electric_stop = True


def s_emerg(tr, st):
    tr.emergency = True


def s_parachute(tr, st):
    tr.emergency = True
    tr.parachute_engaged = True


def s_service(tr, st):
    tr.speed_cmd = 0.0
    tr.brake = 1.0
    tr.autopilot = False


for v0 in (12.0, 6.0):
    for d in (+1, -1):
        audit_stop("Arrêt électrique (service stop)", v0, d, s_estop)
        audit_stop("Urgence commandée (frein poulie)", v0, d, s_emerg)
        audit_stop("Parachute (pinces rail)", v0, d, s_parachute)

print()
print("=== ARRIVÉE, CONSIGNE BAISSÉE PENDANT L'APPROCHE (profil auto) ===")
# Régression PWA 2026-07-24 : le ff de pente de consigne se cumulait avec
# l'enveloppe d'approche → v plongeait à ~0,1 m/s puis réaccélérait à
# 0,75 pour finir. v ne doit jamais descendre sous le creep dans la zone.
st, ph = make(+1, pn.STOP_S - 400.0, 250, 8, 10.0)
tr = st.train
v_min_creep = 99.0
t = 0.0
while t < 240.0 and not st.finished:
    dist = pn.STOP_S - tr.s
    if dist > 200.0:
        tr.speed_cmd = 1.0
    elif dist > 50.0:
        tr.speed_cmd = 0.3 + 0.7 * (dist - 50.0) / 150.0
    elif dist > 8.0:
        tr.speed_cmd = 0.15
    else:
        tr.speed_cmd = 0.0
    ph.step(DT)
    if 3.0 < dist < 40.0:
        v_min_creep = min(v_min_creep, abs(tr.v))
    t += DT
print(f"  v_min zone creep = {v_min_creep:.2f} m/s, "
      f"arrivée = {st.finished}"
      f"{'  ⚠ CREUX' if v_min_creep < 0.55 or not st.finished else '  OK'}")

print()
print("=== RUPTURE CÂBLE EN DESCENTE — pente défavorable (zone 30 %) ===")
# La rame descendante découplée est tirée par TOUT son poids dans son
# sens de marche : décél nette = parachute 3,6 − g·sinθ − résistance.
# Pire cas : pleine charge, pente max, 12 m/s.
for pax, label in ((8, "rame quasi vide"), (334, "rame pleine")):
    st, ph = make(-1, 2000.0, pax, 8, -12.0)
    trig = {"done": False}

    def on_t(t, st):
        if t >= 1.0 and not trig["done"]:
            pn.trigger_fault(st, "cable_rupture")
            trig["done"] = True

    hist = run(st, ph, 130.0, on_t)
    tr = st.train
    post = [h for h in hist if h[0] >= 1.0]
    d = abs(hist[-1][9] - post[0][9])
    theta = pn.slope_angle_at(2000.0)
    net = (abs(12.0) ** 2) / (2 * d) if d > 1 else 0.0
    print(f"  s=2000 m (pente {math.tan(theta)*100:.0f} %), {label:15s} : "
          f"arrêt en {d:6.1f} m, {hist[-1][0] - 1.0:5.1f} s, décél nette "
          f"{net:.2f} m/s² (parachute 3,6 − g·sinθ {9.81*math.sin(theta):.2f})")
