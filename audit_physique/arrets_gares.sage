# Points d'arrêt en gare (v1.15.62, 06/10/2026). Fait d'un utilisateur (témoin) :
# « en haut on s'arrête proche du butoir, à 1,5 m, mais en bas ça
# correspond à environ 4 ou 5 m du butoir du bas pour avoir de la marge
# d'oscillation et d'allongement ».
#
# Abscisses le long de la pente (s = 0 au portail bas). Butoirs
# (stations_builder._build_bumper) : têtes en bois de 0,32 m, centrées à
# 0,10 m du socle, côté ligne.
R = QQ
# Voie rallongée (v1.15.65, fait d'un utilisateur : « la distance parcourue réelle
# de chaque trajet c'est 3 474 m ») : PARCOURS d'arrêt à arrêt = 3 474 m,
# deux tronçons neutres de 20,26 m insérés de part et d'autre de
# l'évitement (pente constante, ligne droite).
PARCOURS = R(3474)
TRAIN_HALF = R(16)
face_bas = R(2) - R(10)/100 + R(16)/100          # socle 2,0 m
jeu_bas = R(45)/10
jeu_haut = R(15)/10
START_S = face_bas + jeu_bas + TRAIN_HALF
STOP_S = START_S + PARCOURS
face_haut = STOP_S + TRAIN_HALF + jeu_haut
LENGTH = face_haut + R(46)/100                    # socle à LENGTH − 0,4, tête 0,46 en deçà
MIROIR = START_S + STOP_S
print("voie : %s m (ancienne 3 474), soit %s m de plus : 2 × %s m" % (LENGTH.n(digits=7),
      (LENGTH - 3474).n(digits=4), ((LENGTH - 3474) / 2).n(digits=4)))
print("faces des butoirs : bas %s m, haut %s m" % (face_bas.n(digits=6), face_haut.n(digits=7)))
print("START_S = %s   STOP_S = %s   miroir START_S + STOP_S = %s" %
      (START_S.n(digits=6), STOP_S.n(digits=7), MIROIR.n(digits=7)))
assert STOP_S - START_S == PARCOURS
# Les deux rames sont liées par le câble : quand l'une est à STOP_S,
# l'autre est à MIROIR − STOP_S = START_S (et réciproquement).
assert MIROIR - STOP_S == START_S and MIROIR - START_S == STOP_S
print("rame en haut : nez à %s m du butoir ; l'autre : arrière à %s m du butoir bas" %
      ((face_haut - (STOP_S + TRAIN_HALF)).n(digits=3), ((MIROIR - STOP_S - TRAIN_HALF) - face_bas).n(digits=3)))
print("galet n° 238 à 2303 × 1,51 = %s m, quai haut à %s m" % ((2303 * R(151)/100).n(digits=7),
      (STOP_S - TRAIN_HALF - 3).n(digits=7)))
# Brin total entre les deux rames (rame 1 → poulie → rame 2) :
# (LENGTH − s1) + (LENGTH − s2) = 2·LENGTH − MIROIR
print("câble entre les deux rames : %s m" % (2 * LENGTH - MIROIR).n(digits=7))

# Allongement du brin de la rame en bas (ordre de grandeur) : T monte de la
# rame (m·g·sin θ, pente 9,5 % en bas) à la poulie (+ w·Δz, 921 m) ;
# δ = ∫ T ds / EA, T supposée linéaire en s.
g = RealField(40)(9.80665)
EA = 1.25e8
w = 11 * g
for (nom, m) in [("vide", 32300), ("pleine (334 pax)", 32300 + 334 * 75)]:
    T_bas = m * g * sin(atan(0.095))
    T_haut = T_bas + w * 921
    delta = (T_bas + T_haut) / 2 * float(LENGTH - START_S) / EA
    print("rame %-17s en bas : T %4.0f → %4.0f kN, allongement du brin ≈ %.2f m"
          % (nom, T_bas / 1000, T_haut / 1000, delta))
print("(l'écart de charge entre vide et pleine déplace la rame en bas de")
print(" quelques décimètres : c'est l'affaissement d'embarquement, plus")
print(" l'oscillation de ±0,3 m — d'où les 4 à 5 m de marge en bas)")

# Recul de la rame pleine pendant l'embarquement (retour d'un utilisateur : « je
# pense qu'en vrai la rame recule d'au moins un mètre quand elle est
# pleine ») : δ = Δm·g·sin θ·L / EA, L = câble de la rame en bas à la
# poulie motrice.
L_bas = float(LENGTH - START_S)
sin_bas = sin(atan(0.084))                       # pente au quai bas (8,4 %)
for (nom, kg) in [("75 kg (modèle)", 75), ("85 kg (skieur équipé)", 85)]:
    dm = 334 * kg
    d = dm * g * sin_bas * L_bas / EA
    print("334 passagers à %-22s : %.2f m de recul (EA = 1,25e8 N)" % (nom, d))
EA_1m = 334 * 75 * g * sin_bas * L_bas / 1.0
print("EA qui donnerait 1,00 m avec 75 kg : %.3g N (%.0f %% de 1,25e8 ; E = %.0f GPa pour 1 250 mm²)"
      % (EA_1m, 100 * EA_1m / EA, EA_1m / 1250e-6 / 1e9))
