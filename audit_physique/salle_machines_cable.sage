# Salle des machines de la gare amont — géométrie du câble (2026-09-29,
# révisée le 30/09 : roue amont remontée, sommets des deux roues alignés sur
# la pente de la voie en gare amont — demande de Kevin)
# ---------------------------------------------------------------------------
# Repère local de la fin de voie (tunnel.transform_at(LENGTH)) :
#   s le long de la voie (0 = fin du tunnel, > 0 vers la salle des machines),
#   y vertical (m, même origine que la 3D), x latéral (droite +).
# Faits :
#   - poulies motrices ∅ 4160 mm (remontees-mecaniques.net), JAUNES (photos) ;
#   - DEUX roues d'entraînement ; la roue AVAL affleure au niveau de la voie
#     entre les deux bras bleus des butoirs de la gare amont (Kevin) ;
#   - brins le long de la voie : x = ∓0,12 m, axe y = −1,36 (track_builder) ;
#   - principe classique (Wikipedia « Funicular ») : roue à deux gorges, le
#     câble fait un demi-tour, revient par une seconde roue, refait un tour
#     dans la seconde gorge — adhérence doublée.
#   - la pente entre le sommet de la roue amont et celui de la roue aval est
#     celle de la voie en gare amont (Kevin, 30/09) : le repère local suit la
#     voie, donc les deux sommets sont à la même cote y.
# Tracé retenu (déduit, pas de plan publié) : huit (S) entre la roue aval A
# (sens horaire vu depuis +x) et la roue amont B (sens anti-horaire), deux
# passes par roue ; le brin quitte B par son SOMMET, au niveau de la voie, et
# file droit jusqu'à la voie (plus de batterie de galets).
#
# Exécuter : sage audit_physique/salle_machines_cable.sage

from sage.all import *

R      = RDF(2.08)          # rayon primitif (axe du câble) — ∅ 4160 mm
RF     = RDF(2.14)          # rayon extérieur des joues
Y_BRIN = RDF(-1.36)         # axe des brins sur la voie
RAIL   = RDF(-1.24)         # table de roulement
SLAB   = RDF(-1.60)         # dessus de dalle
SLAB_B = RDF(-1.90)         # dessous de dalle
BUT0, BUT1 = RDF(-0.25), RDF(2.15)   # étendue des bras bleus des butoirs (s)
BUT_IN = RDF(0.70)          # face intérieure des bras (|x|)

A = vector(RDF, [0.95, Y_BRIN - R])          # roue aval
B = vector(RDF, [0.95 + 6.60, Y_BRIN - R])          # roue amont, sommet au niveau de A
A_G = [RDF(-0.12), RDF(-0.36)]               # gorges de A (x)
B_G = [RDF(-0.24), RDF(-0.12)]               # gorges de B (x)
LANE_L, LANE_R = RDF(-0.12), RDF(0.12)
A_BODY = (RDF(-0.46), RDF(-0.02))            # étendue latérale de A (joues)

# point où le brin de sortie rejoint la voie droite
S0 = RDF(0.20)

def ang(v):
    return atan2(v[1], v[0])

def vit_cw(t):   # vitesse d'un point d'une roue horaire, à l'angle t
    return vector(RDF, [sin(t), -cos(t)])

def vit_ccw(t):
    return vector(RDF, [-sin(t), cos(t)])

def pt(c, r, t):
    return c + r * vector(RDF, [cos(t), sin(t)])

def tangentes_internes(c1, c2, r):
    """Tangentes croisées entre deux cercles égaux : angles des points de
    contact sur chaque cercle (deux solutions)."""
    M = (c1 + c2) / 2
    d1 = (M - c1).norm()
    phi = acos(r / d1)
    b1 = ang(M - c1)
    b2 = ang(M - c2)
    return [(b1 + phi, b2 + phi), (b1 - phi, b2 - phi)]

def choisir(c1, c2, sols, v1, v2):
    """Garde la tangente parcourue dans le sens des deux roues."""
    for t1, t2 in sols:
        p1, p2 = pt(c1, R, t1), pt(c2, R, t2)
        u = (p2 - p1) / (p2 - p1).norm()
        if u * v1(t1) > 0.99 and u * v2(t2) > 0.99:
            return t1, t2, (p2 - p1).norm()
    raise ValueError("pas de tangente cohérente")

# A → B (A horaire, B anti-horaire)
tA_out, tB_in, L_AB = choisir(A, B, tangentes_internes(A, B, R), vit_cw, vit_ccw)
# B → A
tB_out, tA_in, L_BA = choisir(B, A, tangentes_internes(B, A, R), vit_ccw, vit_cw)

# Sortie : le brin quitte B par son sommet (angle π/2, B tourne en sens
# anti-horaire : son sommet file vers −s, donc vers la voie) et rejoint la
# voie droite en s = S0, au même niveau.
tB_exit = RDF(pi / 2)
P_Bexit = pt(B, R, tB_exit)
P_Kin = vector(RDF, [S0, Y_BRIN])
assert vit_ccw(tB_exit) * (P_Kin - P_Bexit) > 0, "sortie à contresens"
pente_sortie = atan2(P_Kin[1] - P_Bexit[1], -(P_Kin[0] - P_Bexit[0]))

TAU = RDF(2 * pi)

def modulo(a):
    a = RDF(a)
    return a - TAU * floor(a / TAU)

def enroulement_cw(t0, t1):          # de t0 à t1 en tournant en horaire
    return modulo(t0 - t1)

def enroulement_ccw(t0, t1):
    return modulo(t1 - t0)

w_A1 = enroulement_cw(RDF(pi / 2), tA_out)           # arrivée au sommet → vers B
w_B1 = enroulement_ccw(tB_in, tB_out)
w_A2 = enroulement_cw(tA_in, tA_out)
w_B2 = enroulement_ccw(tB_in, tB_exit)
total = w_A1 + w_B1 + w_A2 + w_B2

def deg(x):
    return float(x * 180 / pi)

print("=== Positions")
print(f"A (aval)  : s = {float(A[0]):.2f} m, axe y = {float(A[1]):.2f} m")
print(f"B (amont) : s = {float(B[0]):.2f} m, axe y = {float(B[1]):.2f} m"
      f"   entraxe {float((B - A).norm()):.3f} m")

print("\n=== Affleurement de la roue aval")
print(f"sommet des joues de A : y = {float(A[1] + RF):.3f} m "
      f"(table de roulement {float(RAIL)}, dessus de dalle {float(SLAB)})")
h = SLAB - A[1]                      # hauteur de la dalle au-dessus de l'axe
emerge = sqrt(RF**2 - h**2)
print(f"A dépasse de la dalle entre s = {float(A[0] - emerge):.2f} et "
      f"{float(A[0] + emerge):.2f} m ; bras des butoirs de {float(BUT0)} à {float(BUT1)} m")
print(f"  → entre les bras : {bool(A[0] - emerge >= BUT0 and A[0] + emerge <= BUT1)}")
print(f"  largeur de A de x = {float(A_BODY[0])} à {float(A_BODY[1])} ; bras à |x| = {float(BUT_IN)}"
      f" → entre les bras : {bool(-BUT_IN < A_BODY[0] and A_BODY[1] < BUT_IN)}")

print("\n=== Enroulements (degrés)")
for nom, w in (("A gorge 1 (arrivée)", w_A1), ("B gorge 1", w_B1),
               ("A gorge 2", w_A2), ("B gorge 2 (sortie)", w_B2)):
    print(f"  {nom:22s} {deg(w):7.1f}")
print(f"  total                  {deg(total):7.1f}")
for mu in (RDF(0.20), RDF(0.25)):
    print(f"  Euler-Eytelwein, μ = {float(mu)} : T1/T2 max = {float(exp(mu * total)):.0f}")

print("\n=== Brins croisés (le « huit »)")
print(f"  longueur A→B {float(L_AB):.3f} m, B→A {float(L_BA):.3f} m")
y_min_croise = min(pt(A, R, tA_out)[1], pt(A, R, tA_in)[1])
y_haut_croise = max(pt(A, R, tA_out)[1], pt(A, R, tA_in)[1])
print(f"  point de tangence le plus haut sur A : y = {float(y_haut_croise):.3f} "
      f"(dessous de dalle {float(SLAB_B)}) → sous la dalle : {bool(y_haut_croise + 0.026 < SLAB_B)}"
      f" (sinon : la fosse ouverte les laisse passer)")
seq = [("A1→B1", A_G[0], B_G[0], L_AB), ("B1→A2", B_G[0], A_G[1], L_BA),
       ("A2→B2", A_G[1], B_G[1], L_AB)]
for nom, x0, x1, L in seq:
    print(f"  désaxement {nom} : {float(abs(x1 - x0)):.2f} m sur {float(L):.2f} m → "
          f"{deg(atan(abs(x1 - x0) / L)):.2f}°")

print("\n=== Sommets des roues et sortie")
print(f"  sommet (axe câble) de A : y = {float(A[1] + R):.3f} ; de B : y = {float(B[1] + R):.3f}"
      f" → pente A→B dans le repère de la voie : {deg(atan2(B[1] - A[1], B[0] - A[0])):.2f}° (voie : 0°)")
L_ex = (P_Kin - P_Bexit).norm()
print(f"  brin de sortie : de s = {float(P_Bexit[0]):.2f} à {float(P_Kin[0]):.2f}, pente {deg(pente_sortie):.2f}° sur {float(L_ex):.2f} m")
print(f"  désaxement gorge 2 de B → voie droite : {float(LANE_R - B_G[1]):.2f} m sur {float(L_ex):.2f} m → "
      f"{deg(atan((LANE_R - B_G[1]) / L_ex)):.2f}°")
def x_sortie(s):
    f = (P_Bexit[0] - s) / (P_Bexit[0] - P_Kin[0])
    return B_G[1] + f * (LANE_R - B_G[1])
GUARD_SIDE = RDF(0.08)
x_carter_A = A_BODY[1] + GUARD_SIDE
print(f"  au droit du sommet de A (s = {float(A[0]):.2f}) : brin à x = {float(x_sortie(A[0])):.3f}, "
      f"bord {float(x_sortie(A[0]) - 0.026):.3f} ; flasque du carter de A à x = {float(x_carter_A):.3f}"
      f" → jeu {float(x_sortie(A[0]) - 0.026 - x_carter_A):.3f} m")
h = SLAB - B[1]
emerge = sqrt(RF**2 - h**2)
GUARD_R = RF + RDF(0.10)
emerge_g = sqrt(GUARD_R**2 - h**2)
print(f"  B dépasse du sol du hall entre s = {float(B[0] - emerge):.2f} et {float(B[0] + emerge):.2f} "
      f"(carter : {float(B[0] - emerge_g):.2f} à {float(B[0] + emerge_g):.2f}) ; mur du fond à s = 9,00")
print(f"  hauteur du sommet de B au-dessus du sol du hall : {float(B[1] + RF - SLAB):.2f} m")
y_dep = [pt(A, R, tA_out)[1], pt(A, R, tA_in)[1], pt(B, R, tB_in)[1], pt(B, R, tB_out)[1]]
print(f"  points de départ des brins croisés : y = {', '.join(f'{float(v):.3f}' for v in y_dep)}"
      f" (dessous de dalle {float(SLAB_B)}) → la fosse doit rester ouverte de s ≈ "
      f"{float(pt(A, R, tA_out)[0]):.2f} à {float(pt(B, R, tB_out)[0]):.2f}")

print("\n=== Angles pour la 3D (radians)")
for nom, v in (("tA_out", tA_out), ("tA_in", tA_in), ("tB_in", tB_in),
               ("tB_out", tB_out), ("tB_exit", tB_exit)):
    print(f"  {nom:12s} {float(v):+.5f}")
