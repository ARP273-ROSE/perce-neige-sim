# -*- coding: utf-8 -*-
# =====================================================================
#  AUDIT PHYSIQUE DU SIMULATEUR PERCE-NEIGE — recalcul indépendant
#  SageMath 10.9 — 2026-09-26
#
#  Tout ce que le document d'audit cite en chiffres sort d'ici.
#  Exécution : docker exec sagemath sage /home/sage/work/11_perce_neige/audit_voyages.sage
#  Entrées   : bench_pc/*.csv (banc tests/bench_voyages.py du simulateur)
#  Sorties   : resultats.txt, fig/*.png
# =====================================================================
import os, csv, math
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ICI = "/home/sage/work/11_perce_neige"
FIG = os.path.join(ICI, "fig")
os.makedirs(FIG, exist_ok=True)
OUT = open(os.path.join(ICI, "resultats.txt"), "w")

def say(*a):
    s = " ".join(str(x) for x in a)
    print(s)
    OUT.write(s + "\n")

# ---------------------------------------------------------------------
# 1. Constantes du simulateur (copiées telles quelles de perce_neige_sim.py)
# ---------------------------------------------------------------------
G = 9.80665
LENGTH = 3474.0
ALT_LOW = 2111.0
ALT_HIGH = 3032.0
DROP = ALT_HIGH - ALT_LOW
V_MAX = 12.0
P_MAX = 2.4e6
F_STALL = 260000.0
MU_ROLL = 0.0025
TRAIN_EMPTY = 32300.0
PAX_KG = 75.0
PAX_MAX = 334
CABLE_KG_M = 11.0
CABLE_EA = 1.25e8
CAR_DIAM = 3.60
TUNNEL_DIAM = 3.9
TRAIN_LEN = 32.0
PASSING_START, PASSING_END = 1611.0, 1813.0
START_S, STOP_S = 26.0, 3448.0
SLOPE_PROFILE = [(0.0, 0.08), (120.0, 0.12), (257.0, 0.16), (400.0, 0.22),
                 (510.0, 0.25), (700.0, 0.28), (914.0, 0.295), (2400.0, 0.295),
                 (3000.0, 0.29), (3200.0, 0.28), (3328.0, 0.27), (3380.0, 0.18),
                 (3420.0, 0.10), (3474.0, 0.06)]

def grad(s):
    t = SLOPE_PROFILE
    if s <= t[0][0]: return t[0][1]
    if s >= t[-1][0]: return t[-1][1]
    for (s0, g0), (s1, g1) in zip(t, t[1:]):
        if s0 <= s <= s1:
            return g0 + (g1 - g0) * (s - s0) / (s1 - s0)
    return t[-1][1]

# altitude : même intégration que _build_geometry (pas 2 m, remise à l'échelle)
DS = 2.0
_z = [ALT_LOW]
_s = 0.0
for _ in range(int(LENGTH / DS)):
    th = math.atan(grad(_s + DS / 2.0))
    _z.append(_z[-1] + DS * math.sin(th))
    _s += DS
_scale = DROP / (_z[-1] - ALT_LOW)
Z = [ALT_LOW + (z - ALT_LOW) * _scale for z in _z]

def alt(s):
    s = max(0.0, min(LENGTH, s))
    i = int(s / DS)
    if i >= len(Z) - 1: return Z[-1]
    k = (s - i * DS) / DS
    return Z[i] + k * (Z[i + 1] - Z[i])

say("=== 1. PROFIL ===")
say("dénivelé intégré = %.2f m (attendu 921), facteur d'échelle %.4f" % (alt(LENGTH) - alt(0), _scale))
say("pente moyenne = %.2f %% ; altitude à s=914 : %.0f m ; s=1737 (mi-ligne) : %.0f m"
    % (100 * DROP / LENGTH, alt(914), alt(1737)))

# ---------------------------------------------------------------------
# 2. Bilan des forces le long de +s (montée de la rame pilotée)
# ---------------------------------------------------------------------
def m_of(pax): return TRAIN_EMPTY + pax * PAX_KG

def f_grav_trains(s, mA, mB):
    thA, thB = math.atan(grad(s)), math.atan(grad(LENGTH - s))
    return -(mA * math.sin(thA) - mB * math.sin(thB)) * G

def f_rope_weight(s):
    """Poids propre du câble : brin A (rame pilotée → poulie amont) pèse
    rho·g·(z_top − z_A) vers −s ; brin B pèse rho·g·(z_top − z_B) dans le
    sens +s de la chaîne. Net = rho·g·(z_A − z_B). Nul à mi-ligne."""
    return CABLE_KG_M * G * (alt(s) - alt(LENGTH - s))

def f_roll(s, mA, mB):
    thA, thB = math.atan(grad(s)), math.atan(grad(LENGTH - s))
    return MU_ROLL * G * (mA * math.cos(thA) + mB * math.cos(thB))

C_ROLLERS = 0.015     # estimation : résistance câble/galets, 1,5 % de la charge normale
def f_rollers():
    # le câble entier (≈ L) repose sur les galets, quel que soit s
    cosm = sum(math.cos(math.atan(grad(x))) for x in range(0, int(LENGTH), 10)) / (LENGTH / 10)
    return C_ROLLERS * CABLE_KG_M * LENGTH * G * cosm

say("\n=== 2. TERMES DU BILAN (kN), rame pilotée en s, contrepoids en L−s ===")
say("poids propre du câble net : s=26 → %.1f kN ; s=1737 → %.1f kN ; s=3448 → %.1f kN"
    % (f_rope_weight(26) / 1e3, f_rope_weight(1737) / 1e3, f_rope_weight(3448) / 1e3))
say("valeur pleine : rho·g·921 = %.1f kN  (= %.1f tonnes-force)" % (CABLE_KG_M * G * DROP / 1e3, CABLE_KG_M * DROP / 1e3))
say("déséquilibre gravitaire max des rames (pleine/vide, zone 29,5 %%) : %.1f kN"
    % (-f_grav_trains(1500, m_of(PAX_MAX), m_of(0)) / 1e3))
say("frottement roulement des 2 rames (pleine/vide) : %.2f kN ; galets du câble (c=%.3f) : %.2f kN"
    % (f_roll(1500, m_of(PAX_MAX), m_of(0)) / 1e3, C_ROLLERS, f_rollers() / 1e3))

# ---------------------------------------------------------------------
# 3. Traînée aérodynamique en tunnel — modèle 1D quasi-stationnaire
# ---------------------------------------------------------------------
def rho_air(z, T0=278.0):
    # atmosphère isotherme ~5 °C (tunnel), p0 = 1013 hPa au niveau de la mer
    return 1013e2 * math.exp(-G * z / (287.05 * T0)) / (287.05 * T0)

R_T = TUNNEL_DIAM / 2.0
A_CIRC = math.pi * R_T ** 2
h_bed = 0.5                                    # radier béton sous les rails (m)
A_BED = R_T ** 2 * math.acos((R_T - h_bed) / R_T) - (R_T - h_bed) * math.sqrt(2 * R_T * h_bed - h_bed ** 2)
A_T = A_CIRC - A_BED                           # section libre du tunnel
say("\n=== 3. AÉRODYNAMIQUE ===")
say("section tunnel Ø3,9 : %.2f m² ; radier (h=%.1f m) : %.2f m² ; section d'air libre A_T = %.2f m²"
    % (A_CIRC, h_bed, A_BED, A_T))
say("section d'une cabine si disque plein Ø3,6 : %.2f m² → beta = %.3f" % (math.pi * 1.8 ** 2, math.pi * 1.8 ** 2 / A_T))
say("rho air : %.3f kg/m³ à 2111 m, %.3f à 3032 m" % (rho_air(ALT_LOW), rho_air(ALT_HIGH)))

LAMBDA = 0.025      # Darcy, parois béton + peau de la rame (Vardy : f_Fanning 0,003–0,010)
K_IN = 0.4          # contraction au nez (arrondi)
def aero_single(v, beta, rho):
    """Tube unique, autre rame présente : la colonne d'air entre les deux
    rames (ou derrière, en s'écartant) ne peut passer que par les
    espaces annulaires. Débit annulaire = v·A_T (repère tunnel)."""
    A_t = beta * A_T
    A_ann = A_T - A_t
    u_rel = v * (2.0 - beta) / (1.0 - beta)
    P_T = 2 * math.pi * R_T
    P_t = 2 * math.pi * math.sqrt(A_t / math.pi)
    D_h = 4 * A_ann / (P_T + P_t)
    k_fric = LAMBDA * TRAIN_LEN / D_h
    K = K_IN + k_fric + beta ** 2            # Borda–Carnot en sortie : (1−A_ann/A_T)² = beta²
    q = 0.5 * rho * u_rel ** 2
    F = K * q * A_t + 0.5 * k_fric * q * A_ann   # pression sur la face + moitié du frottement de peau
    return F, u_rel, K, K * q

def aero_loop(v, beta, rho):
    """Rame dans son tube d'évitement : le 2e tube (203 m, section A_T)
    court-circuite l'annulaire. Partage du débit v·A_T entre les deux
    chemins à perte de charge égale."""
    A_t = beta * A_T
    A_ann = A_T - A_t
    P_T = 2 * math.pi * R_T
    P_t = 2 * math.pi * math.sqrt(A_t / math.pi)
    D_h = 4 * A_ann / (P_T + P_t)
    K = K_IN + LAMBDA * TRAIN_LEN / D_h + beta ** 2
    K2 = 1.5 + LAMBDA * 203.0 / (4 * A_T / P_T)
    Q = v * A_T
    def dp_ann(q_ann):
        return K * 0.5 * rho * (v + q_ann / A_ann) ** 2
    def dp_tube(q_tube):
        return K2 * 0.5 * rho * (q_tube / A_T) ** 2
    # racine de dp_ann(q) − dp_tube(Q−q) = 0 sur [0, Q]
    lo, hi = 0.0, Q
    for _ in range(80):
        mid = 0.5 * (lo + hi)
        if dp_ann(mid) - dp_tube(Q - mid) > 0: hi = mid
        else: lo = mid
    q = 0.5 * (lo + hi)
    dp = dp_ann(q)
    return dp * A_t, dp

say("\nTraînée à 12 m/s, rho = %.3f (mi-ligne), PAR RAME (l'autre rame subit la même) :" % rho_air(alt(1737)))
say("  beta   A_t    u_rel  K     dP(Pa)   F_tube(kN)  P_tube(kW)  |  F_évitement(kN)")
for beta in (0.55, 0.60, 0.65, 0.70, 0.72, 0.75, 0.80, 0.85):
    F, u, K, dp = aero_single(12.0, beta, rho_air(alt(1737)))
    Fl, dpl = aero_loop(12.0, beta, rho_air(alt(1737)))
    say("  %.2f  %5.2f  %5.1f  %.2f  %7.0f   %7.1f    %7.0f     |  %.1f"
        % (beta, beta * A_T, u, K, dp, F / 1e3, F * 12 / 1e3, Fl / 1e3))

BETA = 0.65
def f_aero_total(s, v):
    """Somme des deux rames, chacune dans son régime (tube unique / évitement)."""
    rho = rho_air(alt(s))
    rho_g = rho_air(alt(LENGTH - s))
    in_loop_A = PASSING_START <= s <= PASSING_END
    in_loop_B = PASSING_START <= (LENGTH - s) <= PASSING_END
    FA = (aero_loop(v, BETA, rho)[0] if in_loop_A else aero_single(v, BETA, rho)[0])
    FB = (aero_loop(v, BETA, rho_g)[0] if in_loop_B else aero_single(v, BETA, rho_g)[0])
    return FA + FB

say("beta retenu = %.2f → traînée totale (2 rames) à 12 m/s : %.1f kN en tube unique, %.1f kN quand la rame pilotée est dans l'évitement (s=1700)"
    % (BETA, f_aero_total(1000, 12.0) / 1e3, f_aero_total(1700, 12.0) / 1e3))

# ---------------------------------------------------------------------
# 4. Puissance et tension en régime établi à 12 m/s, cinq chargements
# ---------------------------------------------------------------------
ETA_DRIVE = 0.90   # moteur DC × réducteur × convertisseur (estimation ; = DRIVE_EFF du simulateur)
ETA_REGEN = 0.80   # valeur du simulateur (plage 0,75–0,85)

def f_resist_sim(s, mA, mB):
    """Ce que le simulateur ACTUEL doit vaincre pour tenir v (hors traînée, hors câble)."""
    return -f_grav_trains(s, mA, mB) + f_roll(s, mA, mB)

def f_resist_full(s, v, mA, mB):
    return -f_grav_trains(s, mA, mB) - f_rope_weight(s) + f_roll(s, mA, mB) + f_rollers() + f_aero_total(s, v)

def puissance(F, v):
    """(traction élec. kW, régén élec. kW) pour une force résistante F le long de la marche."""
    if F >= 0: return F * v / ETA_DRIVE / 1e3, 0.0
    return 0.0, -F * v * ETA_REGEN / 1e3

CAS = [("vide/vide", 0, 0), ("pleine/vide", PAX_MAX, 0), ("vide/pleine", 0, PAX_MAX),
       ("pleine/pleine", PAX_MAX, PAX_MAX), ("demi/demi", 167, 167)]
say("\n=== 4. PUISSANCE À 12 m/s LE LONG DE LA MONTÉE (kW élec.) — modèle actuel vs complet ===")
S_GRID = list(range(50, 3450, 50))
prof = {}
for nom, pa, pb in CAS:
    mA, mB = m_of(pa), m_of(pb)
    sim_t = [puissance(f_resist_sim(s, mA, mB), 12.0) for s in S_GRID]
    ful_t = [puissance(f_resist_full(s, 12.0, mA, mB), 12.0) for s in S_GRID]
    prof[nom] = (sim_t, ful_t)
    say("%-14s actuel : Pmax %5.0f kW / Rmax %5.0f kW   complet : Pmax %5.0f kW (à s=%4d) / Rmax %5.0f kW (à s=%4d)"
        % (nom, max(p for p, r in sim_t), max(r for p, r in sim_t),
           max(p for p, r in ful_t), S_GRID[max(range(len(ful_t)), key=lambda i: ful_t[i][0])],
           max(r for p, r in ful_t), S_GRID[max(range(len(ful_t)), key=lambda i: ful_t[i][1])]))

# dimensionnement : force max à 12 m/s vs P_MAX/v et F_STALL
say("\nForce moteur disponible à 12 m/s : P/v = %.0f kN ; F_STALL = %.0f kN (< 9,2 m/s)" % (P_MAX / 12 / 1e3, F_STALL / 1e3))
for nom, pa, pb in CAS[:2]:
    mA, mB = m_of(pa), m_of(pb)
    fmax_sim = max(f_resist_sim(s, mA, mB) for s in S_GRID)
    fmax_ful = max(f_resist_full(s, 12.0, mA, mB) for s in S_GRID)
    say("  %-12s F_résist max : actuel %.0f kN (%.0f %% de P/v) ; complet %.0f kN (%.0f %%)"
        % (nom, fmax_sim / 1e3, 100 * fmax_sim / (P_MAX / 12), fmax_ful / 1e3, 100 * fmax_ful / (P_MAX / 12)))

# beta maximal compatible avec la puissance installée (pleine/vide, marge 10 %)
say("\nBorne sur beta imposée par les 2 400 kW (pleine/vide à 12 m/s, rendement %.2f) :" % ETA_DRIVE)
mA, mB = m_of(PAX_MAX), m_of(0)
for beta in (0.60, 0.65, 0.70, 0.72, 0.75, 0.80):
    BETA = beta
    pk = max(puissance(f_resist_full(s, 12.0, mA, mB), 12.0)[0] for s in S_GRID)
    say("  beta %.2f → pic %4.0f kW  %s" % (beta, pk, "OK" if pk <= 2400 else "DÉPASSE la puissance installée"))
BETA = 0.65

# ---------------------------------------------------------------------
# 5. Tension du câble à la poulie (modèle deux brins du simulateur)
# ---------------------------------------------------------------------
def tension_side(m, s_pos, a_s=0.0):
    th = math.atan(grad(s_pos))
    m_brin = CABLE_KG_M * max(LENGTH - s_pos, 0.0)
    return max(0.0, m * G * math.sin(th) + MU_ROLL * m * G * math.cos(th)
               + CABLE_KG_M * G * max(0.0, ALT_HIGH - alt(s_pos)) + (m + m_brin) * a_s)

say("\n=== 5. TENSION (daN) — brin A (rame pilotée), brin B (contrepoids) ===")
for nom, pa, pb in CAS[:2]:
    mA, mB = m_of(pa), m_of(pb)
    tA = [(s, tension_side(mA, s) / 10) for s in S_GRID]
    tB = [(s, tension_side(mB, LENGTH - s) / 10) for s in S_GRID]
    sA, vA = max(tA, key=lambda x: x[1])
    say("%-12s max brin A %.0f daN à s=%d ; brin B à s=26 : %.0f daN ; sans poids du câble, max brin A serait %.0f daN"
        % (nom, vA, sA, tB[0][1], max((mA * G * math.sin(math.atan(grad(s))) + MU_ROLL * mA * G) / 10 for s in S_GRID)))
say("nominal constructeur 22 500 daN ; rupture 191 200 → coefficient de sécurité au pic pleine/vide = %.1f"
    % (191200 / max(tension_side(m_of(PAX_MAX), s) / 10 for s in S_GRID)))
say("différence des brins à la poulie = effort moteur : à s=26 pleine/vide : %.1f kN ; à s=3448 : %.1f kN"
    % ((tension_side(m_of(PAX_MAX), 26) - tension_side(m_of(0), LENGTH - 26)) / 1e3,
       (tension_side(m_of(PAX_MAX), 3448) - tension_side(m_of(0), LENGTH - 3448)) / 1e3))
say("… et le bilan des forces complet (hors aéro/galets) dit : %.1f kN et %.1f kN → cohérent avec la jauge SI le câble pèse sur le moteur"
    % (-(f_grav_trains(26, m_of(PAX_MAX), m_of(0)) + f_rope_weight(26)) / 1e3 + f_roll(26, m_of(PAX_MAX), m_of(0)) / 1e3,
       -(f_grav_trains(3448, m_of(PAX_MAX), m_of(0)) + f_rope_weight(3448)) / 1e3 + f_roll(3448, m_of(PAX_MAX), m_of(0)) / 1e3))

# ---------------------------------------------------------------------
# 6. Énergie par trajet (∫F ds à 12 m/s, approximation régime établi)
# ---------------------------------------------------------------------
say("\n=== 6. ÉNERGIE PAR TRAJET (kWh élec.) ===")
say("énergie potentielle nette pleine/vide : Δm·g·Δh = %.1f kWh" % (PAX_MAX * PAX_KG * G * DROP / 3.6e6))
for nom, pa, pb in CAS:
    mA, mB = m_of(pa), m_of(pb)
    e_sim = [0.0, 0.0]; e_ful = [0.0, 0.0]
    ds = 10.0
    for s in np.arange(START_S, STOP_S, ds):
        p, r = puissance(f_resist_sim(s, mA, mB), 12.0)
        e_sim[0] += p * ds / 12.0 / 3600; e_sim[1] += r * ds / 12.0 / 3600
        p, r = puissance(f_resist_full(s, 12.0, mA, mB), 12.0)
        e_ful[0] += p * ds / 12.0 / 3600; e_ful[1] += r * ds / 12.0 / 3600
    say("%-14s montée : actuel trac %5.1f / régén %5.1f   complet trac %5.1f / régén %5.1f"
        % (nom, e_sim[0], e_sim[1], e_ful[0], e_ful[1]))

# ---------------------------------------------------------------------
# 7. Affaissement d'embarquement (allongement élastique du brin)
# ---------------------------------------------------------------------
say("\n=== 7. AFFAISSEMENT À L'EMBARQUEMENT ===")
L_bas = LENGTH - START_S
th0 = math.atan(grad(START_S))
dx_pax = PAX_KG * G * math.sin(th0) * L_bas / CABLE_EA
say("gare basse : L = %.0f m, pente %.1f %%, k = EA/L = %.0f N/m → %.2f mm par passager, %.1f cm pour 334 pax"
    % (L_bas, 100 * grad(START_S), CABLE_EA / L_bas, dx_pax * 1e3, dx_pax * PAX_MAX * 100))
L_haut = LENGTH - STOP_S
dx_h = PAX_KG * G * math.sin(math.atan(grad(STOP_S))) * L_haut / CABLE_EA
say("gare haute : L = %.0f m → %.3f mm par passager, %.1f mm pour 334 pax (invisible)" % (L_haut, dx_h * 1e3, dx_h * PAX_MAX * 1e3))
say("période propre rame pleine en bas : T = 2π√(m/k) = %.1f s" % (2 * math.pi * math.sqrt(m_of(PAX_MAX) / (CABLE_EA / L_bas))))

# ---------------------------------------------------------------------
# 8. Confrontation aux séries du banc PC
# ---------------------------------------------------------------------
say("\n=== 8. BANC PC (tests/bench_voyages.py) : cohérence interne ===")
def lire(nom):
    p = os.path.join(ICI, "bench_pc", nom + ".csv")
    with open(p) as f:
        return [{k: float(v) for k, v in r.items()} for r in csv.DictReader(f)]

for nom in ("montee_pleine_vide", "descente_vide_pleine", "montee_vide_vide", "descente_pleine_vide"):
    rows = lire(nom)
    err_p, n = 0.0, 0
    tmax = 0.0
    for r in rows:
        if abs(r["v"]) < 11.9: continue
        # à vitesse stabilisée, la force moteur doit égaler la résistance du modèle ACTUEL
        F = f_resist_sim(r["s"], r["m_main"], r["m_ghost"]) * (1 if "montee" in nom else -1)
        # sens de marche : en descente la rame pilotée descend (v<0) ; la résistance
        # le long de la marche vaut −(f_grav_trains + …) projeté
        F_travel = (-f_grav_trains(r["s"], r["m_main"], r["m_ghost"])) * (1 if "montee" in nom else -1) + f_roll(r["s"], r["m_main"], r["m_ghost"])
        p_att = max(0.0, F_travel * 12.0 / 1e3)
        r_att = max(0.0, -F_travel * 12.0 * 0.8 / 1e3)
        err_p = max(err_p, abs(p_att - r["power_kw"]), abs(r_att - r["regen_kw"]))
        n += 1
        tmax = max(tmax, r["tension_dan"])
    say("%-22s : %d pts à 12 m/s, écart max |P_sim − P_recalc| = %.1f kW ; T max %.0f daN ; durée %.0f s ; E_trac %.1f kWh"
        % (nom, n, err_p, tmax, rows[-1]["t"],
           sum(r["power_kw"] for r in rows) * 0.5 / 3600))

# miroir : montée pleine/vide vs descente vide/pleine à position égale de la rame pleine
up, dn = lire("montee_pleine_vide"), lire("descente_vide_pleine")
def interp_rows(rows, key, x):
    pts = sorted((r[key], r["power_kw"], r["tension_dan"], r["regen_kw"]) for r in rows)
    for a, b in zip(pts, pts[1:]):
        if a[0] <= x <= b[0]:
            k = (x - a[0]) / max(b[0] - a[0], 1e-9)
            return tuple(a[i] + k * (b[i] - a[i]) for i in (1, 2, 3))
    return pts[-1][1:]
dmax = [0.0, 0.0, 0.0]
for x in range(300, 3200, 25):
    a = interp_rows(up, "s", x); b = interp_rows(dn, "s_ghost", x)
    for i in range(3): dmax[i] = max(dmax[i], abs(a[i] - b[i]))
say("MIROIR PC : écart max puissance %.2f kW, tension %.2f daN, régén %.2f kW → %s"
    % (dmax[0], dmax[1], dmax[2], "symétrie exacte" if max(dmax) < 1.0 else "ASYMÉTRIE"))

# ---------------------------------------------------------------------
# 9. Figures
# ---------------------------------------------------------------------
plt.rcParams.update({"font.size": 9})
fig, ax = plt.subplots(2, 1, figsize=(7.2, 6.4), sharex=True)
for nom, col in (("pleine/vide", "C3"), ("vide/vide", "C0"), ("pleine/pleine", "C2")):
    sim_t, ful_t = prof[nom]
    ax[0].plot(S_GRID, [p - r for p, r in sim_t], col + "--", lw=1.2, label=nom + " (actuel)")
    ax[0].plot(S_GRID, [p - r for p, r in ful_t], col + "-", lw=1.6, label=nom + " (complet)")
ax[0].axhline(2400, color="k", lw=0.8, ls=":"); ax[0].text(60, 2450, "2 400 kW installés", fontsize=8)
ax[0].axhline(0, color="k", lw=0.5)
ax[0].set_ylabel("puissance élec. (kW)\n(+ traction, − régénération)")
ax[0].legend(fontsize=7, ncol=2); ax[0].grid(alpha=0.3)
ax[0].axvspan(PASSING_START, PASSING_END, color="0.85"); ax[0].text(1620, -900, "évitement", fontsize=7)
mA, mB = m_of(PAX_MAX), m_of(0)
comp = {"déséquilibre des rames": [-f_grav_trains(s, mA, mB) / 1e3 for s in S_GRID],
        "poids propre du câble": [-f_rope_weight(s) / 1e3 for s in S_GRID],
        "traînée d'air (2 rames)": [f_aero_total(s, 12.0) / 1e3 for s in S_GRID],
        "roulement + galets": [(f_roll(s, mA, mB) + f_rollers()) / 1e3 for s in S_GRID]}
for k, v in comp.items():
    ax[1].plot(S_GRID, v, lw=1.4, label=k)
ax[1].axhline(0, color="k", lw=0.5); ax[1].set_xlabel("position de la rame pilotée s (m)")
ax[1].set_ylabel("force résistante (kN)\nmontée pleine/vide à 12 m/s")
ax[1].legend(fontsize=7); ax[1].grid(alpha=0.3)
ax[1].axvspan(PASSING_START, PASSING_END, color="0.85")
fig.tight_layout(); fig.savefig(os.path.join(FIG, "puissance_forces.png"), dpi=160); plt.close(fig)

fig, ax = plt.subplots(figsize=(7.2, 3.4))
for nom, col in (("pleine/vide", "C3"), ("vide/vide", "C0")):
    pa = PAX_MAX if nom == "pleine/vide" else 0
    ax.plot(S_GRID, [tension_side(m_of(pa), s) / 10 for s in S_GRID], col + "-", label="brin rame pilotée " + nom)
    ax.plot(S_GRID, [tension_side(m_of(0), LENGTH - s) / 10 for s in S_GRID], col + "--", label="brin contrepoids " + nom)
ax.axhline(22500, color="k", ls=":", lw=0.8); ax.text(60, 22800, "nominal 22 500 daN", fontsize=8)
ax.set_xlabel("s (m)"); ax.set_ylabel("tension à la poulie (daN)"); ax.grid(alpha=0.3); ax.legend(fontsize=7)
fig.tight_layout(); fig.savefig(os.path.join(FIG, "tension.png"), dpi=160); plt.close(fig)

fig, ax = plt.subplots(figsize=(7.2, 3.2))
betas = np.linspace(0.5, 0.86, 60)
ax.plot(betas, [aero_single(12.0, b, rho_air(alt(1737)))[0] / 1e3 for b in betas], "C3-", label="tube unique (par rame)")
ax.plot(betas, [aero_loop(12.0, b, rho_air(alt(1737)))[0] / 1e3 for b in betas], "C0-", label="dans l'évitement (par rame)")
ax.axvline(0.65, color="k", ls=":", lw=0.8); ax.text(0.655, 60, "β retenu 0,65", fontsize=8)
ax.set_yscale("log"); ax.set_xlabel("taux de blocage β = A_rame / A_air"); ax.set_ylabel("traînée à 12 m/s (kN)")
ax.grid(alpha=0.3, which="both"); ax.legend(fontsize=8)
fig.tight_layout(); fig.savefig(os.path.join(FIG, "aero_beta.png"), dpi=160); plt.close(fig)

# banc PC : puissance/régén/tension vs s pour les 3 cas
fig, ax = plt.subplots(2, 1, figsize=(7.2, 5.6), sharex=True)
for nom, col in (("montee_pleine_vide", "C3"), ("montee_vide_vide", "C0"), ("descente_pleine_vide", "C2")):
    rows = lire(nom)
    ax[0].plot([r["s"] for r in rows], [r["power_kw"] - r["regen_kw"] for r in rows], col, lw=1.2, label=nom)
    ax[1].plot([r["s"] for r in rows], [r["tension_dan"] for r in rows], col, lw=1.2, label=nom)
ax[0].set_ylabel("banc PC : puissance − régén (kW)"); ax[0].grid(alpha=0.3); ax[0].legend(fontsize=7)
ax[1].set_ylabel("banc PC : tension (daN)"); ax[1].set_xlabel("s (m)"); ax[1].grid(alpha=0.3)
fig.tight_layout(); fig.savefig(os.path.join(FIG, "banc_pc.png"), dpi=160); plt.close(fig)

# ---------------------------------------------------------------------
# 10. APRÈS correction : banc PC v1.13.0 (bench_pc2) vs AVANT (bench_pc)
# ---------------------------------------------------------------------
say("\n=== 10. BANC PC APRÈS CORRECTION (v1.13.0) — kWh élec., kW, daN ===")
def lire2(nom):
    p = os.path.join(ICI, "bench_pc2", nom + ".csv")
    with open(p) as f:
        return [{k: float(v) for k, v in r.items()} for r in csv.DictReader(f)]
say("%-24s %6s %6s %6s %6s %6s %6s | %6s %6s %6s %6s %6s" % ("trajet", "Pmax", "Rmax", "Etrac", "Ereg", "Tmax", "durée", "Pmax0", "Rmax0", "Etr0", "Erg0", "Tmax0"))
for nom in ("montee_vide_vide", "montee_pleine_vide", "descente_pleine_vide", "descente_vide_pleine", "montee_pleine_pleine", "montee_demi_demi"):
    r2, r1 = lire2(nom), lire(nom)
    def stats(rows):
        return (max(r["power_kw"] for r in rows), max(r["regen_kw"] for r in rows),
                sum(r["power_kw"] for r in rows) * 0.5 / 3600, sum(r["regen_kw"] for r in rows) * 0.5 / 3600,
                max(r["tension_dan"] for r in rows), rows[-1]["t"])
    a2, a1 = stats(r2), stats(r1)
    say("%-24s %6.0f %6.0f %6.1f %6.1f %6.0f %6.0f | %6.0f %6.0f %6.1f %6.1f %6.0f" % ((nom,) + a2 + a1[:5]))
# creux de l'évitement sur la puissance (pleine/pleine, après)
rows = lire2("montee_pleine_pleine")
def near(rows, x):
    return min(rows, key=lambda r: abs(r["s"] - x))
say("évitement (pleine/pleine, après) : P à s=1550 %.0f kW → s=1712 %.0f kW → s=1900 %.0f kW"
    % (near(rows, 1550)["power_kw"], near(rows, 1712)["power_kw"], near(rows, 1900)["power_kw"]))
fig, ax = plt.subplots(figsize=(7.2, 3.8))
for nom, col, lab in (("montee_vide_vide", "C0", "montée vide/vide"), ("montee_pleine_vide", "C3", "montée pleine/vide"),
                      ("descente_pleine_vide", "C2", "descente pleine/vide")):
    r1, r2 = lire(nom), lire2(nom)
    ax.plot([r["s"] for r in r1], [r["power_kw"] - r["regen_kw"] for r in r1], col + "--", lw=1.0, label=lab + " — avant")
    ax.plot([r["s"] for r in r2], [r["power_kw"] - r["regen_kw"] for r in r2], col + "-", lw=1.5, label=lab + " — après")
ax.axhline(2400, color="k", ls=":", lw=0.8); ax.axhline(0, color="k", lw=0.5)
ax.axvspan(PASSING_START, PASSING_END, color="0.88"); ax.text(1620, -1150, "évitement", fontsize=7)
ax.set_xlabel("position de la rame pilotée s (m)"); ax.set_ylabel("puissance élec. (kW), − = régén")
ax.grid(alpha=0.3); ax.legend(fontsize=7, ncol=2)
fig.tight_layout(); fig.savefig(os.path.join(FIG, "avant_apres.png"), dpi=160); plt.close(fig)

say("\nfigures écrites dans %s" % FIG)
OUT.close()
