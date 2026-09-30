# Aiguillage Abt et câble tendu entre les galets (2026-09-30)
# ---------------------------------------------------------------------------
# Géométrie du simulateur (tunnel_builder / track_builder) :
#   évitement de PASSING_START = 1611 m à PASSING_END = 1813 m,
#   écart de chaque voie d(s) = 3,50 · sin²(π k), k = (s − 1611) / 202,
#   écartement 1,20 m, tête de rail 75 mm, patin 150 mm,
#   brins de câble à ∓(d + 0,12) m (brin gauche = rame 1, voie gauche),
#   câble Ø 52 mm, 11 kg/m, tension nominale 22 500 daN (source CFD),
#   galets Ø 300 mm tous les 13,57 m (256 paires, source CFD).
# Principe Abt : rails extérieurs continus ; roues extérieures à double
# boudin, roues intérieures plates et larges ; les rails intérieurs naissent
# contre le rail extérieur opposé (lacune pour le boudin de l'autre rame),
# se croisent en X (cœur sans ornière : roues plates), et « le câble du
# véhicule opposé passe dans un trou ménagé dans la voie intérieure »
# (dossier remontees-mecaniques.net).
#
# Exécuter : sage audit_physique/aiguillage_abt_cable.sage

from sage.all import *

S0, S1 = RDF(1611), RDF(1813)
LL = S1 - S0
D = RDF(3.50)
HG = RDF(0.60)             # demi-écartement
HEAD = RDF(0.075)          # largeur de tête
FOOT = RDF(0.150)          # largeur de patin
WEB = RDF(0.020)
BASE = RDF(0.12)           # décalage du brin par rapport à l'axe de sa voie
RC = RDF(0.026)            # rayon du câble
ORNIERE = RDF(0.060)       # boudin (30 mm) + jeu : lacune mini au nez
JEU = RDF(0.015)           # jeu câble / acier dans la fenêtre
PAS = RDF(3474) / 256      # entraxe moyen des galets
W = RDF(11 * 9.80665)      # poids linéique du câble (N/m)
T_NOM = RDF(225e3)         # N
R_GALET = RDF(0.15)

var('s')
k = (s - S0) / LL
d = D * sin(pi * k)**2
dp = diff(d, s)
dpp = diff(d, s, 2)

def resout(expr_val, lo, hi):
    return RDF(find_root(expr_val, lo, hi))

print("=== Évitement : d(s) = 3,50 sin²(πk)")
kmax = RDF(dpp.subs(s=S0))
print(f"  courbure latérale maxi d''(1611) = {float(kmax):.3e} /m → rayon {float(1/kmax):.0f} m")
print(f"  divergence maxi (k = 1/4) : {float(atan(dp.subs(s=S0 + LL/4)) * 180 / pi):.2f}°")

# 1. Nez des rails intérieurs : la tête du rail intérieur de la voie gauche
#    (x = −d + 0,6) doit laisser l'ornière du boudin de l'autre rame contre la
#    tête du rail extérieur droit (x = d + 0,6) : 2d − 75 mm ≥ ornière.
d_nez = (HEAD + ORNIERE) / 2
s_nez = resout(d - d_nez, S0 + 0.01, S0 + 40)
print("\n=== Nez des rails intérieurs")
print(f"  écart voulu d = {float(d_nez):.4f} m → nez à s = {float(s_nez):.2f} m "
      f"(fourche + {float(s_nez - S0):.2f} m) ; en haut à {float(S1 - (s_nez - S0)):.2f} m")

# 2. Croisement en X des deux rails intérieurs (x = 0 ⇔ d = 0,6)
s_x = resout(d - HG, S0 + 1, S0 + 60)
ang_x = 2 * atan(RDF(dp.subs(s=s_x)))
print("\n=== Cœur en X")
print(f"  croisement à s = {float(s_x):.2f} m (fourche + {float(s_x - S0):.2f} m), "
      f"angle {float(ang_x * 180 / pi):.2f}°")
print(f"  recouvrement des têtes : {float(HEAD / tan(ang_x)):.2f} m de long")

# 3. Traversée du brin opposé : brin gauche x = −(d + 0,12), rail intérieur
#    de la voie droite x = d − 0,6 → égalité pour d = (0,6 − 0,12) / 2
d_c = (HG - BASE) / 2
s_c = resout(d - d_c, S0 + 0.01, S0 + 60)
rel = 2 * RDF(dp.subs(s=s_c))        # pente relative brin / rail
ang_c = atan(rel)
L_ame = 2 * (RC + WEB / 2 + JEU) / rel
L_patin = 2 * (RC + FOOT / 2 + JEU) / rel
print("\n=== Passage du câble opposé dans le rail intérieur")
print(f"  écart d = {float(d_c):.3f} m → s = {float(s_c):.2f} m (fourche + {float(s_c - S0):.2f} m)")
print(f"  angle câble / rail : {float(ang_c * 180 / pi):.2f}°")
print(f"  âme découpée sur {float(L_ame):.2f} m, patin sur {float(L_patin):.2f} m")
print(f"  (en haut : s = {float(S1 - (s_c - S0)):.2f} m)")
y_cable, y_tete_bas = RDF(-1.36), RDF(-1.41 + 0.140)
print(f"  dessus du câble {float(y_cable + RC):.3f} ; dessous de tête {float(y_tete_bas):.3f} "
      f"→ jeu {float(y_tete_bas - y_cable - RC) * 1000:.0f} mm sous la tête")
# un galet ne doit pas tomber sur le rail : support étroit (galet 80 mm +
# joue 40 mm = 0,10 m de chaque côté du brin) + demi-patin + 2 cm
ecart_mini = RDF(0.10) + FOOT / 2 + RDF(0.02)
print(f"  pas de galet à moins de {float(ecart_mini / rel):.2f} m de la traversée")

# 4. Câble tendu en ligne droite entre les galets : flèche de corde
print("\n=== Corde entre deux galets (câble tendu, pas moyen 13,57 m)")
def smoothstep_kmax(dv_deg, ds):
    return RDF(1.5 * dv_deg * pi / 180 / ds)       # max de la dérivée du smoothstep
courbes = [("courbe 1a (155→165°, 1297→1420 m)", smoothstep_kmax(10, 123)),
           ("courbe 1b (165→175°, 1420→1541 m)", smoothstep_kmax(10, 121)),
           ("courbe 2 (175→189°, 1884→2125 m)", smoothstep_kmax(14, 241)),
           ("courbe 2 (189→203°, 2125→2369 m)", smoothstep_kmax(14, 244)),
           ("évitement, fourche", kmax)]
for nom, kap in courbes:
    fl = PAS**2 * kap / 8
    dth = PAS * kap
    print(f"  {nom:36s} R = {float(1/kap):5.0f} m  flèche {float(fl*100):4.1f} cm  "
          f"déviation par galet {float(dth*180/pi):.2f}°")
print(f"  affaissement sous son poids (T nominale) : {float(W * PAS**2 / (8 * T_NOM) * 1000):.1f} mm → négligé")

# 5. Inclinaison des galets de courbe : charge latérale T·Δθ contre le poids
print("\n=== Inclinaison requise d'un galet de courbe (T = 22 500 daN)")
for nom, kap in courbes:
    lat = T_NOM * PAS * kap
    ver = W * PAS * cos(atan(RDF(0.295)))
    phi = atan2(lat, ver)
    print(f"  {nom:36s} latéral {float(lat/1e3):5.2f} kN, poids {float(ver/1e3):4.2f} kN "
          f"→ {float(phi*180/pi):4.1f}°")
print("  les deux galets d'une paire sont à 0,24 m : au-delà de 32° d'inclinaison ils")
print("  se touchent ; le reste de l'effort latéral passe par le flanc de la gorge")
print("  (flanc de 46° au moins pour 78° — hypothèse, pas de plan de galet publié)")
r_g, ep = R_GALET, RDF(0.08)
for deg_ in (32, 45):
    a_ = RDF(deg_ * pi / 180)
    emp = r_g * sin(a_) + ep / 2 * cos(a_)
    print(f"  inclinaison {deg_}° : chaque galet déborde de {float(emp*100):.1f} cm → "
          f"jeu entre les deux galets {float((RDF(0.24) - 2 * emp)*100):+.1f} cm")
seuil = tan(RDF(32 * pi / 180)) * W * PAS / (T_NOM * PAS)
print(f"  l'inclinaison sature à 32° dès que R < {float(1/seuil):.0f} m")

# 6. Courbe verticale concave du bas (pente 0,08 → 0,295) : le câble se
#    soulève-t-il entre les galets ? Oui si T · κ_v > w cos α.
print("\n=== Soulèvement dans la concavité du bas")
segs = [(0, 120, 0.08, 0.12), (120, 257, 0.12, 0.16), (257, 400, 0.16, 0.22),
        (400, 510, 0.22, 0.25), (510, 700, 0.25, 0.28), (700, 914, 0.28, 0.295)]
kv = max(RDF(1.5 * (atan(RDF(g1)) - atan(RDF(g0))) / (b - a)) for a, b, g0, g1 in segs)
T_lim = W * cos(atan(RDF(0.16))) / kv
print(f"  courbure verticale maxi {float(kv):.2e} /m (R = {float(1/kv):.0f} m)")
print(f"  soulèvement si T > {float(T_lim/1e3):.0f} kN ; au bas de la ligne la tension vaut "
      f"≈ m g (sin α + 0,005) = {float(58800 * 9.80665 * (sin(atan(RDF(0.16))) + 0.005) / 1e3):.0f} kN")
