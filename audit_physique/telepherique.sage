# Téléphérique de la Grande Motte dans la vue en coupe du PC (06/10/2026) —
# demande d'un utilisateur : « représenter dans la vue en coupe le profil avec pylône,
# les deux gares et les câbles avec la courbe cosh du téléphérique de la
# Grande Motte, qui part dans la foulée du funi ».
#
# Faits (remontees-mecaniques.net, reportage TPH115 ; Wikipédia FR) :
#   bicâble à va-et-vient Von Roll 1975, 115 + 1 places, gare MOTRICE aval ;
#   aval 3 034 m, amont 3 456 m, dénivelée 421 m, longueur développée
#   1 696 m, pente maximale 55 %, UN pylône en treillis, « hauteur maximale
#   de la ligne : 152 mètres » au-dessus du terrain ; 10 m/s, 5,2 m/s au
#   passage du pylône, 5 min de montée.
# Positions (OpenStreetMap, way 23140026) : gare aval 45,42331 / 6,89050,
#   pylône P1 45,41545 / 6,87763, gare amont 45,41358 / 6,87456.
# Terrain sous la ligne : IGN RGE ALTI (audit_physique/telepherique_profil.json).
#
# INCONNUS — valeurs du simulateur, pas des données :
#   * hauteur du pylône : MESURÉE sur une photo du reportage (≈ 30 m) ;
#     le survol maximal de 152 m est « sur la partie située en aval du
#     pylône » (reportage) ;
#   * paramètre de chaînette des câbles porteurs a = T/w : déduit du survol
#     de 152 m avec ce pylône ; la « pente maximale : 55 % » se retrouve
#     avec une cabine pleine au ras du pylône (non publié) ;
#   * selles des porteurs : 8 m au-dessus du quai en gare.
#
#   docker exec sagemath sage /home/sage/work/pn/telepherique.sage
import json
import numpy as np
from scipy.optimize import brentq

D = json.load(open('/home/sage/work/pn/telepherique_profil.json'))
prof = np.array(D['profil_horiz_alt'])
X, Z = prof[:, 0], prof[:, 1]
L1 = X[160]                       # gare aval → pylône (horizontal)
L2 = X[-1] - L1                   # pylône → gare amont
Z_AVAL, Z_AMONT = 3034.0 + 8.0, 3456.0 + 8.0
Z_PIED = Z[160]


def chainette(x0, z0, x1, z1, a):
    """chaînette z = c + a·cosh((x − m)/a) passant par (x0, z0) et (x1, z1)"""
    # m tel que a(cosh((x1−m)/a) − cosh((x0−m)/a)) = z1 − z0
    f = lambda m: a * (cosh((x1 - m) / a) - cosh((x0 - m) / a)) - (z1 - z0)
    m = brentq(f, x0 - 20 * a, x1 + 20 * a)
    c = z0 - a * cosh((x0 - m) / a)
    return lambda x: c + a * np.cosh((x - m) / a), m


def survol_max(h, a):
    cat, _ = chainette(0.0, Z_AVAL, L1, Z_PIED + h, a)
    k = X <= L1
    return float(np.max(cat(X[k]) - Z[k]))


def pente_max_1(a):
    h = brentq(lambda hh: survol_max(hh, a) - 152.0, -300.0, 600.0)
    cat, _ = chainette(0.0, Z_AVAL, L1, Z_PIED + h, a)
    return float((cat(L1) - cat(L1 - 0.5)) / 0.5)


print("Portées : gare aval → pylône %.0f m, pylône → gare amont %.0f m (horizontal)" % (L1, L2))
print("Terrain : %.0f m au plus bas (à %.0f m de la gare aval), %.0f m au pied du pylône"
      % (Z.min(), X[np.argmin(Z)], Z_PIED))
print()
print("Hauteur du pylône donnant 152 m de survol maximal :")
for a in (3000.0, 4000.0, 5000.0, 8000.0):
    h = brentq(lambda h: survol_max(h, a) - 152.0, -100.0, 300.0)
    print("  a = %5.0f m  →  pylône de %5.1f m, pente max %.0f %%" % (a, h, 100 * pente_max_1(a)))



# Hauteur du pylône MESURÉE sur la photo du reportage (P1030395, « Partie
# milieu de la ligne – pylône 1 ») : une cabine juste passée le pylône, à la
# même distance ; caisse ≈ 27 px pour ≈ 3,0 m, partie visible du pylône
# ≈ 218 px → ≈ 24 m, pied caché derrière la crête de neige → ≈ 30 m.
H_PHOTO = 30.0
A_CAT = brentq(lambda a: brentq(lambda hh: survol_max(hh, a) - 152.0, -300.0, 600.0) - H_PHOTO,
               1500.0, 8000.0)
print()
print("Pylône mesuré sur photo ≈ %.0f m → avec le survol de 152 m : a = %.0f m" % (H_PHOTO, A_CAT))
# La « pente maximale 55 % » de la fiche se retrouve AVEC LA CABINE : une
# charge concentrée W sur un porteur de tension horizontale H casse sa pente
# de W/H ; cabine au ras du pylône, la pente y monte d'autant.
W_CAB = 6000.0 + 116 * 75.0          # cabine + chariot (estimé) + 116 personnes, kg
W_PAR_PORTEUR = W_CAB / 2.0
for w_m in (11.0, 13.0, 15.0):       # poids linéique du porteur (kg/m), non publié
    H_t = A_CAT * w_m / 1000.0
    pm = pente_max_1(A_CAT) + W_PAR_PORTEUR / 1000.0 / H_t
    print("  porteur %2.0f kg/m : tension ≈ %3.0f t, pente avec cabine pleine au pylône ≈ %.0f %%"
          % (w_m, H_t, 100 * pm))
H_PYL = brentq(lambda h: survol_max(h, A_CAT) - 152.0, -100.0, 300.0)
print()
cat1, m1 = chainette(0.0, Z_AVAL, L1, Z_PIED + H_PYL, A_CAT)
cat2, m2 = chainette(L1, Z_PIED + H_PYL, X[-1], Z_AMONT, A_CAT)
k1 = X <= L1
i_max = int(np.argmax(cat1(X[k1]) - Z[k1]))
print("Retenu (a = %.0f m) : pylône de %.0f m, sommet à %.0f m d'altitude" % (A_CAT, H_PYL, Z_PIED + H_PYL))
print("  survol maximal %.0f m à %.0f m de la gare aval" % (float(cat1(X[i_max]) - Z[i_max]), X[i_max]))
# flèche au milieu de chaque portée (par rapport à la corde)
for nom, cat, x0, x1, z0, z1 in (("1re portée", cat1, 0.0, L1, Z_AVAL, Z_PIED + H_PYL),
                                  ("2e portée", cat2, L1, X[-1], Z_PIED + H_PYL, Z_AMONT)):
    xm = (x0 + x1) / 2
    print("  %s : flèche à mi-portée %.1f m" % (nom, (z0 + z1) / 2 - float(cat(xm))))
# angles des câbles au passage du pylône
eps = 0.5
p_av = float((cat1(L1) - cat1(L1 - eps)) / eps)
p_ap = float((cat2(L1 + eps) - cat2(L1)) / eps)
print("  pente des porteurs au pylône : %.1f %% avant, %.1f %% après (déviation %.1f°)"
      % (100 * p_av, 100 * p_ap, float(np.degrees(np.arctan(p_av) - np.arctan(p_ap)))))
pente_max = max(float(np.max(np.abs(np.gradient(cat1(X[k1]), X[k1])))),
                float(np.max(np.abs(np.gradient(cat2(X[~k1]), X[~k1])))))
print("  pente maximale des porteurs %.0f %% (fiche : 55 %% pour la ligne)" % (100 * pente_max))
L_dev = float(np.sum(np.hypot(np.diff(X), np.diff(np.concatenate([cat1(X[k1]), cat2(X[~k1])])))))
print("  longueur développée %.0f m (fiche : 1 696 m)" % L_dev)
json.dump({k: float("%.1f" % v) for k, v in (("h_pylone", H_PYL), ("a", A_CAT), ("z_selle_aval", Z_AVAL),
                                                ("z_selle_amont", Z_AMONT), ("L1", L1), ("L2", L2))},
          open('/home/sage/work/pn/telepherique_resultat.json', 'w'))
