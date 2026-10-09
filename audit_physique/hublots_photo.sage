# Hublots de la rame mesurés sur les photos de Kevin (09/10/2026, gare haute).
# Relevés en pixels sur la photo n°2 (2000x1500), panneau-porte coulissé, vu
# presque de face ; recoupés sur la photo n°1 (même cadrage, même rapports).
# Références du modèle : pas d'un panneau = PANEL_L + RIB_W ; baie de porte
# du plancher au haut du vantail (DOOR_TOP_T).
R  = RealField(60)
R_BODY, Y_CENTER, Y_FLOOR = R(1.72), R(0.20), R(-0.95)
PANEL_L = (R(16) - 1 - R(0.25) - 2*R(0.33) - R(0.10)*19) / 18
pas = PANEL_L + R(0.10)
h_baie = Y_CENTER + R_BODY*cos(R(54)*pi/180) - Y_FLOOR     # haut de baie / plancher

# photo 2 : panneau 345 px de joint à joint, vitre 192 px de large, 545 px de haut ;
# baie de porte voisine 840 px ; haut de vitre 185 px sous le haut de baie, bas
# de vitre 110 px au-dessus du seuil.  Photo 1 : 335 / 185 / 820 / 185 / 105 px.
mes = [dict(pan=345, w=192, h=545, baie=840, dh=185, db=110),
       dict(pan=335, w=185, h=530, baie=820, dh=185, db=105)]
for m in mes:
    m['larg'] = R(m['w'])/m['pan']*pas
    m['haut'] = h_baie*(1 - R(m['dh'])/m['baie'])
    m['bas']  = h_baie*R(m['db'])/m['baie']
    print("photo : largeur %.3f m (%.0f %% du pas), haut %.2f m, bas %.2f m du plancher"
          % (m['larg'], 100*R(m['w'])/m['pan'], m['haut'], m['bas']))
larg = sum(m['larg'] for m in mes)/len(mes)
haut = sum(m['haut'] for m in mes)/len(mes)
bas  = sum(m['bas'] for m in mes)/len(mes)
def angle(h):      # angle depuis le sommet du tube pour une hauteur au-dessus du plancher
    return arccos((Y_FLOOR + h - Y_CENTER)/R_BODY)*180/pi
print("pas du panneau %.4f m, PANEL_L %.4f m, haut de baie %.3f m" % (pas, PANEL_L, h_baie))
print("RETENU largeur %.3f m, haut %.3f m -> WIN_T0 %.1f deg, bas %.3f m -> WIN_T1 %.1f deg"
      % (larg, haut, angle(haut), bas, angle(bas)))
print("rapport hauteur/largeur sur la photo : %.2f" % (R(545)/192))
# Forme : super-ellipse |u/a|^n + |v/b|^n = 1, n = 3,0 (moitié haute) et 3,4
# (moitié basse), a = 0,215 m, calée par superposition du contour projeté sur
# la photo n°2 (hublots_superposition.py : python3 hublots_superposition.py
# 72.1 120.4 0.43 3.0 3.4 853 → superpose.png ; la photo n'est pas versée au
# dépôt).
