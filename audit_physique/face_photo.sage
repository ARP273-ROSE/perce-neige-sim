# Face de la rame relevée sur la photo frontale d'un utilisateur (09/10/2026,
# « superpose tes limites de vitre à une de mes photos, pareil pour la forme
# des ouvertures d'évac »). Pixels lus sur la photo 2000 × 1500, recadrée de
# (350, 150) : relevés en coordonnées du recadrage.
# Axe : milieu du pare-brise et des deux bords intérieurs des D (x = 506 px) ;
# échelle : demi-largeur moyenne de la face (464 et 549 px, perspective) pour
# R = 1,72 m, sommet de la face à y = 30 px.
R = RealField(40)
R_BODY, FACE_SCALE = R(1.72), (R(1.72) + R(0.20) + R(1.01)) / R(3.10)
cx, ytop = R(506), R(30)
s = ((R(506) - 42) + (R(1055) - 506)) / 2 / R_BODY          # px par mètre
X = lambda px: (R(px) - cx) / s
Y = lambda py: R_BODY - (R(py) - ytop) / s                  # y relatif à l'axe
reel = lambda yr: R(1.78) - (R_BODY - yr) / FACE_SCALE       # inverse de _face_y
print("échelle %.1f px/m" % s)
ws = dict(g=X(305), d=X(705), haut=Y(115), bas=Y(680), r_haut=R(100)/s, r_bas=R(45)/s)
print("pare-brise : x %.3f → %.3f (demi-largeur %.3f), haut %.3f (WS_TOP_REAL %.3f), bas %.3f (WS_BOT_REAL %.3f), coins %.2f / %.2f m"
      % (ws['g'], ws['d'], (ws['d'] - ws['g']) / 2, ws['haut'], reel(ws['haut']), ws['bas'], reel(ws['bas']), ws['r_haut'], ws['r_bas']))
d_in = (abs(X(265)) + X(750)) / 2
print("D : bord intérieur %.3f ; sommet de l'arche x %.3f y %.3f (DOOR_TOP_REAL %.3f) ; départ de l'arche y %.3f ; arrivée sur le flanc x %.3f y %.3f ; bas %.3f (DOOR_BOT_REAL %.3f)"
      % (d_in, abs(X(215)), Y(268), reel(Y(268)), Y(330), abs(X(95)), Y(420), Y(825), reel(Y(825))))
print("flanc des D : ρ gauche %.3f, droite %.3f, moyenne %.3f"
      % (sqrt(X(85)^2 + Y(600)^2), sqrt(X(1000)^2 + Y(600)^2), (sqrt(X(85)^2 + Y(600)^2) + sqrt(X(1000)^2 + Y(600)^2)) / 2))
