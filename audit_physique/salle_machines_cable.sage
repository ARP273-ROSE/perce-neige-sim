# Salle des machines de la gare amont — géométrie du câble
# ---------------------------------------------------------------------------
# 2026-09-29, révisée le 30/09/2026 d'après les indications d'un utilisateur :
#   - roue amont remontée : sommets des deux roues alignés sur la pente de la
#     voie en gare amont (repère local = celui de la voie : même cote y) ;
#   - les deux roues ALIGNÉES latéralement, deux gorges chacune (gauche et
#     droite, vu vers l'amont) aux mêmes x que les brins de la voie ;
#   - parcours, vu vers l'amont : le câble de la rame 1 entre sur le HAUT de
#     la roue aval, gorge gauche ; descend en bas de la roue amont, s'y
#     enroule côté gauche, sort par le haut ; descend s'enrouler en bas de la
#     roue aval côté droit, sort par le haut ; redescend en bas de la roue
#     amont, s'enroule côté droit, sort en haut ; passe sur des galets
#     AU-DESSUS du sommet de la roue aval (photo des butoirs bleus) et file
#     vers la rame 2.
# Repère local de la fin de voie (tunnel.transform_at(LENGTH)) : s le long de
# la voie (> 0 vers la salle), y vertical local, x à droite vu vers l'amont.
#
# Exécuter : sage audit_physique/salle_machines_cable.sage

from sage.all import *

R      = RDF(2.08)          # rayon primitif (axe du câble) — ∅ 4160 mm
RF     = RDF(2.14)          # rayon extérieur des joues
RC     = RDF(0.026)         # rayon du câble
Y_BRIN = RDF(-1.36)         # axe des brins sur la voie
RAIL   = RDF(-1.24)         # table de roulement
SLAB   = RDF(-1.60)         # dessus de dalle (sol du hall)
BUT0, BUT1 = RDF(-0.25), RDF(2.15)   # étendue des bras bleus des butoirs (s)
BUT_IN = RDF(0.70)          # face intérieure des bras (|x|)
GAUCHE, DROITE = RDF(-0.12), RDF(0.12)   # gorges = brins de la voie
CORPS = (RDF(-0.22), RDF(0.22))          # étendue latérale d'une roue (joues)
GS = RDF(0.08)                           # jeu latéral roue / flasques du carter

A = vector(RDF, [0.95, Y_BRIN - R])          # roue aval, sommet au niveau des brins
B = vector(RDF, [0.95 + 6.60, Y_BRIN - R])   # roue amont, même cote

# brin de sortie au-dessus de la roue aval, sur deux galets qui l'encadrent
EXIT_Y = RDF(-1.24)         # axe du brin au-dessus du sommet de A
R_GALET = RDF(0.10)
S_GALETS = [RDF(0.05), RDF(1.85)]

def ang(v):
    return atan2(v[1], v[0])

def vit_cw(t):
    return vector(RDF, [sin(t), -cos(t)])

def vit_ccw(t):
    return vector(RDF, [-sin(t), cos(t)])

def pt(c, r, t):
    return c + r * vector(RDF, [cos(t), sin(t)])

def tangentes_internes(c1, c2, r):
    M = (c1 + c2) / 2
    phi = acos(r / (M - c1).norm())
    b1, b2 = ang(M - c1), ang(M - c2)
    return [(b1 + phi, b2 + phi), (b1 - phi, b2 - phi)]

def choisir(c1, c2, sols, v1, v2):
    for t1, t2 in sols:
        p1, p2 = pt(c1, R, t1), pt(c2, R, t2)
        u = (p2 - p1) / (p2 - p1).norm()
        if u * v1(t1) > 0.99 and u * v2(t2) > 0.99:
            return t1, t2, (p2 - p1).norm()
    raise ValueError("pas de tangente cohérente")

# A horaire (son sommet file vers l'amont, là où le brin de la rame 1 entre)
tA_out, tB_in, L_AB = choisir(A, B, tangentes_internes(A, B, R), vit_cw, vit_ccw)
tB_out, tA_in, L_BA = choisir(B, A, tangentes_internes(B, A, R), vit_ccw, vit_cw)

# sortie : tangente de B (anti-horaire) vers le sommet du galet amont
Q = vector(RDF, [S_GALETS[1], EXIT_Y])
dq = Q - B
beta = ang(dq)
gq = acos(R / dq.norm())
tB_exit = None
for t in (beta + gq, beta - gq):
    p = pt(B, R, t)
    u = (Q - p) / (Q - p).norm()
    if u * vit_ccw(t) > 0.99:
        tB_exit = t
assert tB_exit is not None

TAU = RDF(2 * pi)
def modulo(a):
    a = RDF(a)
    return a - TAU * floor(a / TAU)
def enroulement_cw(t0, t1):
    return modulo(t0 - t1)
def enroulement_ccw(t0, t1):
    return modulo(t1 - t0)
def deg(x):
    return float(x * 180 / pi)

w_A1 = enroulement_cw(RDF(pi / 2), tA_out)
w_B1 = enroulement_ccw(tB_in, tB_out)
w_A2 = enroulement_cw(tA_in, tA_out)
w_B2 = enroulement_ccw(tB_in, tB_exit)
total = w_A1 + w_B1 + w_A2 + w_B2

print("=== Positions")
print(f"A (aval) : s = {float(A[0]):.2f}, axe y = {float(A[1]):.2f} ; B (amont) : s = {float(B[0]):.2f}, "
      f"axe y = {float(B[1]):.2f} ; entraxe {float((B - A).norm()):.3f} m")
print(f"pente sommet A → sommet B dans le repère de la voie : {deg(atan2(B[1] - A[1], B[0] - A[0])):.2f}° (voie : 0°)")
print(f"roues alignées : gorges gauche x = {float(GAUCHE)}, droite x = {float(DROITE)} sur les deux roues")

print("\n=== Affleurement de la roue aval")
h = SLAB - A[1]
em = sqrt(RF**2 - h**2)
print(f"A dépasse du sol entre s = {float(A[0] - em):.2f} et {float(A[0] + em):.2f} ; bras de "
      f"{float(BUT0)} à {float(BUT1)} → {bool(A[0] - em >= BUT0 and A[0] + em <= BUT1)}")
print(f"largeur avec carter : x = {float(CORPS[0] - GS)} à {float(CORPS[1] + GS)} ; bras à |x| = {float(BUT_IN)}"
      f" → {bool(CORPS[1] + GS < BUT_IN)}")

print("\n=== Parcours et enroulements (degrés)")
for nom, w, t0, t1 in (("A gauche : entrée au sommet → départ", w_A1, pi / 2, tA_out),
                       ("B gauche : bas → sommet → départ", w_B1, tB_in, tB_out),
                       ("A droite : bas → sommet → départ", w_A2, tA_in, tA_out),
                       ("B droite : bas → sommet → sortie", w_B2, tB_in, tB_exit)):
    print(f"  {nom:38s} {deg(w):6.1f}   (de {deg(modulo(t0)):6.1f}° à {deg(modulo(t1)):6.1f}°)")
print(f"  total {deg(total):.1f}")
for mu in (RDF(0.20), RDF(0.25)):
    print(f"  Euler-Eytelwein, μ = {float(mu)} : T1/T2 max = {float(exp(mu * total)):.0f}")

print("\n=== Brins croisés")
print(f"  A→B {float(L_AB):.3f} m : gauche→gauche puis droite→droite, désaxement nul")
print(f"  B gauche → A droite : {float(DROITE - GAUCHE):.2f} m sur {float(L_BA):.2f} m → "
      f"{deg(atan((DROITE - GAUCHE) / L_BA)):.2f}°")
print(f"  au croisement : brins A→B à x = ±0,12, brin B→A à x = 0 → jeu entre câbles "
      f"{float(DROITE - 2 * RC) * 1000:.0f} mm")

print("\n=== Sortie au-dessus de la roue aval")
p_ex = pt(B, R, tB_exit)
print(f"  quitte B à {deg(modulo(tB_exit)):.2f}° (s = {float(p_ex[0]):.3f}, y = {float(p_ex[1]):.3f}),"
      f" monte de {deg(atan2(EXIT_Y - p_ex[1], p_ex[0] - Q[0])):.2f}° jusqu'au galet en s = {float(Q[0])}")
jeu_sommet = EXIT_Y - RC - (A[1] + RF)
print(f"  au-dessus du sommet de A : axe à y = {float(EXIT_Y)}, dessous du câble {float(EXIT_Y - RC):.3f},"
      f" joues de A à {float(A[1] + RF):.3f} → jeu {float(jeu_sommet) * 1000:.0f} mm")
for s_g in S_GALETS:
    yc = EXIT_Y - RC - R_GALET
    jeu = min(yc - sqrt(R_GALET**2 - (s - s_g)**2) - (A[1] + sqrt(RF**2 - (s - A[0])**2))
              for s in [s_g + k * R_GALET / 10 for k in range(-9, 10)])
    print(f"  galet en s = {float(s_g):.2f} : centre y = {float(yc):.3f}, jeu mini avec les joues de A {float(jeu) * 1000:.0f} mm")
s_last = RDF(255.5 * 13.57 - 3474)
y0 = Y_BRIN + (EXIT_Y - Y_BRIN) * (0 - s_last) / (S_GALETS[0] - s_last)
print(f"  vers la rame 2 : descend du galet (s = {float(S_GALETS[0])}) au dernier galet du tunnel "
      f"(s = {float(s_last):.3f}) : pente {deg(atan((EXIT_Y - Y_BRIN) / (S_GALETS[0] - s_last))):.2f}°, "
      f"y = {float(y0):.4f} à la fin de voie")
print(f"  au niveau de la table de roulement : {float(EXIT_Y - RAIL) * 1000:.0f} mm (entre les butoirs, la rame n'y va pas)")

print("\n=== Roue amont dans le hall")
hb = SLAB - B[1]
emb = sqrt(RF**2 - hb**2)
emg = sqrt((RF + 0.10)**2 - hb**2)
print(f"  B dépasse du sol de s = {float(B[0] - emb):.2f} à {float(B[0] + emb):.2f} (carter {float(B[0] - emg):.2f} à "
      f"{float(B[0] + emg):.2f}), de {float(B[1] + RF - SLAB):.2f} m")

print("\n=== Angles pour la 3D (radians)")
for nom, v in (("tA_out", tA_out), ("tA_in", tA_in), ("tB_in", tB_in),
               ("tB_out", tB_out), ("tB_exit", tB_exit)):
    print(f"  {nom:8s} {float(v):+.5f}")
