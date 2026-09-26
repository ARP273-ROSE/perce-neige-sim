# -*- coding: utf-8 -*-
# Redémarrage en pleine pente (30 %), rame pleine, contrepoids vide, s = 1500 m
# Question : la puissance monte-t-elle « trop progressivement » ?
# SageMath 10.9 — 2026-09-26
import math, os, csv
ICI = "/home/sage/work/11_perce_neige"
load(os.path.join(ICI, "audit_voyages_lib.sage"))

s0 = 1500.0
mA, mB = m_of(PAX_MAX), m_of(0)
M = mA + mB + CABLE_KG_M * LENGTH                 # masse en mouvement (rames + câble)
F_static = f_resist_full(s0, 0.0, mA, mB)        # à v = 0 : pas de traînée
F_aero12 = f_aero_total(s0, 12.0)
print("=== REDÉMARRAGE s = %.0f m (pentes %.1f %% / %.1f %%), pleine/vide ===" % (s0, 100*grad(s0), 100*grad(LENGTH-s0)))
print("masse en mouvement M = %.0f t ; effort statique à vaincre F0 = %.1f kN" % (M/1e3, F_static/1e3))
print("  dont déséquilibre des rames %.1f kN, câble %.1f kN, roulement+galets %.1f kN"
      % (-f_grav_trains(s0, mA, mB)/1e3, -f_rope_weight(s0)/1e3, (f_roll(s0, mA, mB)+f_rollers())/1e3))
print("traînée à 12 m/s (2 rames) : %.1f kN" % (F_aero12/1e3))

# Pertes électriques (estimation) : cuivre ∝ F², 4 % du nominal au courant nominal
# (F_rated = P_MAX / 12 m/s = 200 kN) ; excitation + auxiliaires du drive 15 kW.
ETA = 0.90
P_CU_RATED = 0.04 * P_MAX
F_RATED = P_MAX / 12.0
P_FIELD = 15e3

def p_elec(F, v):
    return max(0.0, F * v) / ETA + P_CU_RATED * (max(F, 0.0) / F_RATED) ** 2 + P_FIELD

def simulate(a_law, dt=0.01, t_end=45.0):
    """Intègre v(t) avec la loi d'accélération a_law(v, a_prev, dt) ; retourne (t, v, F, Pm, Pe)."""
    t, v, a = 0.0, 0.0, 0.0
    rows = []
    while t <= t_end:
        F = f_resist_full(s0, v, mA, mB) + M * a
        rows.append((t, v, F, F * v, p_elec(F, v)))
        a = a_law(v, a, dt)
        v = min(12.0, v + a * dt)
        t += dt
    return rows

def loi_sim(v, a_prev, dt):
    """Simulateur actuel : démarrage doux 0,12 → 0,32 m/s² entre 0 et 2 m/s, puis 0,30."""
    cap = 0.12 + (0.32 - 0.12) * min(1.0, v / 2.0)
    return min(0.30, cap) if v < 12.0 else 0.0

def loi_franche(v, a_prev, dt):
    """Rampe programmée 0,30 m/s² atteinte en 1,2 s (jerk 0,25 m/s³), sans creep de quai."""
    return min(0.30, a_prev + 0.25 * dt) if v < 12.0 else 0.0

for nom, loi in (("SIMULATEUR ACTUEL (démarrage doux de quai)", loi_sim), ("RAMPE FRANCHE 0,30 m/s² (jerk 0,25)", loi_franche)):
    rows = simulate(loi)
    print("\n--- %s ---" % nom)
    print("  t (s)   v (m/s)   F (kN)   P méca (kW)   P élec (kW)")
    for tt in (0, 0.5, 1, 2, 3, 5, 8, 10, 15, 20, 30, 40):
        r = min(rows, key=lambda q: abs(q[0] - tt))
        print("  %5.1f   %6.2f   %6.1f     %7.0f       %7.0f" % r)
    t12 = next((q[0] for q in rows if q[1] >= 11.99), None)
    print("  12 m/s atteints à t = %s s" % ("%.1f" % t12 if t12 else "—"))

# À v = 0, couple appliqué contre le frein tambour (pré-tension) : l'afficheur
# électrique ne peut pas être à zéro.
print("\nÀ l'instant du décollage (F = F0 + M·a, v = 0) : P élec ≈ %.0f kW (pertes cuivre %.0f + excitation %.0f)"
      % (p_elec(F_static + M*0.30, 0.0)/1e3, P_CU_RATED*((F_static+M*0.30)/F_RATED)**2/1e3, P_FIELD/1e3))
print("Pente de montée de la puissance en régime d'accélération constante : dP/dt = F·a ≈ %.0f kW/s (F = %.0f kN, a = 0,30)"
      % ((F_static + M*0.30) * 0.30 / 1e3, (F_static + M*0.30)/1e3))
