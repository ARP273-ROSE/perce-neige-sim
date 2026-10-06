# Points d'arrêt en gare (v1.15.62, 06/10/2026). Fait de Kevin (témoin) :
# « en haut on s'arrête proche du butoir, à 1,5 m, mais en bas ça
# correspond à environ 4 ou 5 m du butoir du bas pour avoir de la marge
# d'oscillation et d'allongement ».
#
# Abscisses le long de la pente (s = 0 au portail bas). Butoirs
# (stations_builder._build_bumper) : têtes en bois de 0,32 m, centrées à
# 0,10 m du socle, côté ligne.
R = QQ
LENGTH = R(3474)
TRAIN_HALF = R(16)
face_bas = R(2) - R(10)/100 + R(16)/100          # socle 2,0 m
face_haut = (LENGTH - R(4)/10) + R(10)/100 - R(16)/100
jeu_bas = R(45)/10
jeu_haut = R(15)/10
START_S = face_bas + jeu_bas + TRAIN_HALF
STOP_S = face_haut - jeu_haut - TRAIN_HALF
MIROIR = START_S + STOP_S
print("faces des butoirs : bas %s m, haut %s m" % (face_bas.n(digits=6), face_haut.n(digits=7)))
print("START_S = %s   STOP_S = %s   miroir START_S + STOP_S = %s" %
      (START_S.n(digits=6), STOP_S.n(digits=7), MIROIR.n(digits=6)))
# Les deux rames sont liées par le câble : quand l'une est à STOP_S,
# l'autre est à MIROIR − STOP_S = START_S (et réciproquement).
assert MIROIR - STOP_S == START_S and MIROIR - START_S == STOP_S
print("rame en haut : nez à %s m du butoir ; l'autre : arrière à %s m du butoir bas" %
      ((face_haut - (STOP_S + TRAIN_HALF)).n(digits=3), ((MIROIR - STOP_S - TRAIN_HALF) - face_bas).n(digits=3)))
print("avant : miroir LENGTH − s, PWA START_S 20 / STOP_S 3457 → l'autre rame à %s m du butoir bas (dans le butoir)" %
      ((LENGTH - 3457 - TRAIN_HALF) - face_bas).n(digits=3))
print("        PC START_S 26 / STOP_S 3448 : %s m en haut, %s m en bas" %
      ((face_haut - (3448 + TRAIN_HALF)).n(digits=3), ((26 - TRAIN_HALF) - face_bas).n(digits=3)))
# Brin total entre les deux rames (rame 1 → poulie → rame 2) :
# (LENGTH − s1) + (LENGTH − s2) = 2·LENGTH − MIROIR
print("câble entre les deux rames : %s m, soit %s m de moins que la voie"
      % ((2 * LENGTH - MIROIR).n(digits=6), (MIROIR - LENGTH).n(digits=3)))

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
