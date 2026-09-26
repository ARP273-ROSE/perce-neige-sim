import os, csv, math
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ICI = "/home/sage/work/11_perce_neige"
FIG = os.path.join(ICI, "fig")
os.makedirs(FIG, exist_ok=True)
OUT = None

def say(*a):
    s = " ".join(str(x) for x in a)
    pass

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
