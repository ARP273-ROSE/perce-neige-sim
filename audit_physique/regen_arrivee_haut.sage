# Question d'un utilisateur (2026-09-27) : « quand une rame pleine arrive en haut,
# pendant la décélération et l'entrée en gare, il y a marqué régénération —
# je ne suis pas sûr ». Bilan des forces à l'arrivée en haut, rame pleine en
# montée, contrepoids vide en bas, avec le modèle complet de l'audit.
#   sage regen_arrivee_haut.sage
import os
ICI = "/home/sage/work/11_perce_neige"
load(os.path.join(ICI, "audit_voyages_lib.sage"))

mA, mB = m_of(PAX_MAX), m_of(0)
M_TOT = mA + mB + CABLE_KG_M * LENGTH          # tout ce qui bouge (rames + câble)
print("\n=== ARRIVÉE EN HAUT, rame PLEINE (%.1f t) en montée, contrepoids VIDE (%.1f t) ===" % (mA / 1e3, mB / 1e3))
print("masse en mouvement (2 rames + câble %.1f t) : %.1f t" % (CABLE_KG_M * LENGTH / 1e3, M_TOT / 1e3))
print("énergie cinétique à 12 m/s : %.1f MJ ; à 6 m/s : %.1f MJ" % (0.5 * M_TOT * 144 / 1e6, 0.5 * M_TOT * 36 / 1e6))
print("(pas de câble lest sur le Perce-Neige — remontees-mecaniques.net : « pas de câble lest ... pas de système de tension dynamique »)")

print("\n--- Termes du bilan (kN, + = s'oppose à la montée) ---")
print("%6s %9s %9s %7s %8s %8s %8s | %8s %8s %8s" % ("s (m)", "rames", "câble", "roul.", "galets", "aéro12", "aéro1", "Σ v=12", "Σ v=6", "Σ v=1"))
for s in [3000, 3200, 3300, 3400, 3448]:
    g = -f_grav_trains(s, mA, mB) / 1e3
    r = -f_rope_weight(s) / 1e3
    ro = f_roll(s, mA, mB) / 1e3
    ga = f_rollers() / 1e3
    a12 = f_aero_total(s, 12.0) / 1e3
    a1 = f_aero_total(s, 1.0) / 1e3
    print("%6d %9.1f %9.1f %7.1f %8.1f %8.1f %8.1f | %8.1f %8.1f %8.1f" % (
        s, g, r, ro, ga, a12, a1,
        f_resist_full(s, 12.0, mA, mB) / 1e3, f_resist_full(s, 6.0, mA, mB) / 1e3, f_resist_full(s, 1.0, mA, mB) / 1e3))

print("\n--- Puissance électrique (kW) : vitesse constante, puis décélération a = −0,5 et −1,0 m/s² ---")
print("F_inertie = M_TOT · a = %.1f kN à −0,5 m/s², %.1f kN à −1,0 m/s² (le moteur doit RETENIR cette force)" % (M_TOT * 0.5 / 1e3, M_TOT * 1.0 / 1e3))
print("%6s %5s | %10s %10s | %10s %10s | %10s %10s" % ("s", "v", "trac cst", "régén cst", "trac −0.5", "régén −0.5", "trac −1.0", "régén −1.0"))
for s in [3300, 3400, 3448]:
    for v in [12.0, 6.0, 3.0, 1.0]:
        F0 = f_resist_full(s, v, mA, mB)
        t0, r0 = puissance(F0, v)
        t5, r5 = puissance(F0 - M_TOT * 0.5, v)
        t1, r1 = puissance(F0 - M_TOT * 1.0, v)
        print("%6d %5.1f | %10.0f %10.0f | %10.0f %10.0f | %10.0f %10.0f" % (s, v, t0, r0, t5, r5, t1, r1))

print("\n--- Comparaison : même rame pleine, à mi-ligne (s=1737) et en bas (s=300), à 12 m/s constant ---")
for s in [300, 1737]:
    t0, r0 = puissance(f_resist_full(s, 12.0, mA, mB), 12.0)
    print("s=%4d : rames %6.1f kN, câble %6.1f kN → traction %5.0f kW, régén %4.0f kW" % (
        s, -f_grav_trains(s, mA, mB) / 1e3, -f_rope_weight(s) / 1e3, t0, r0))

print("\n--- Sans le poids du câble (hypothèse d'un câble lest, qui N'EXISTE PAS ici) ---")
for s in [3400, 3448]:
    for v in [12.0, 1.0]:
        F0 = f_resist_full(s, v, mA, mB) + f_rope_weight(s)
        t0, r0 = puissance(F0, v)
        t5, r5 = puissance(F0 - M_TOT * 0.5, v)
        print("s=%4d v=%4.1f : cst traction %5.0f / régén %4.0f kW ; à −0,5 m/s² traction %5.0f / régén %5.0f kW" % (s, v, t0, r0, t5, r5))
