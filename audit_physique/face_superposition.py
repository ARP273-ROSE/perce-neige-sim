"""Superpose les contours de la face du modèle (pare-brise, portes
d'évacuation en D, silhouette) sur la photo de face 20260426_095511 d'un utilisateur
(sons/photos/, non versée au dépôt) — retour d'utilisateur, 09/10/2026 : « la baie vitrée
est trop large devant le cockpit, superpose tes limites de vitre à une de
mes photos, pareil pour la forme des ouvertures d'évac ».

    python3 audit_physique/face_superposition.py [WS_HALF_W WS_TOP WS_BOT WS_CORNER DOOR_X0 DOOR_TOP DOOR_BOT DOOR_CORNER]

Mise à l'échelle (photo réduite à 1 400 px de large) : largeur de la face
(2 R = 3,44 m) = 710 px, hauteur (sommet → fond plat, 2,93 m) = 617 px ;
axe du tube au milieu de la largeur, x = 630 px, sommet à y = 128 px.
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

R_BODY, Y_CENTER, Y_CUT = 1.72, 0.20, -1.01
FACE_SCALE = (R_BODY + (Y_CENTER - Y_CUT)) / 3.10
a = [float(v) for v in sys.argv[1:]]
WS_HALF_W, WS_TOP, WS_BOT, WS_CORNER = (a[0:4] if len(a) >= 4 else [0.76, 1.50, -0.38, 0.20])
DOOR_X0, DOOR_TOP, DOOR_BOT, DOOR_CORNER = (a[4:8] if len(a) >= 8 else [0.98, 1.02, -1.15, 0.24])
DOOR_RHO = 1.62


def face_y(yr):
    return R_BODY - (1.78 - yr) * FACE_SCALE


def rounded(x0, x1, y0, y1, r, rho_max):
    r = min(r, (x1 - x0) / 2 - 1e-3, (y1 - y0) / 2 - 1e-3)
    cs = [((x1 - r, y0 + r), -math.pi / 2), ((x1 - r, y1 - r), 0.0),
          ((x0 + r, y1 - r), math.pi / 2), ((x0 + r, y0 + r), math.pi)]
    pts = []
    for k in range(4):
        (cx, cy), a0 = cs[k]
        for j in range(11):
            ang = a0 + math.pi / 2 * j / 10
            pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    out = []
    for x, y in pts:
        rho = math.hypot(x, y)
        if rho > rho_max:
            x, y = x * rho_max / rho, y * rho_max / rho
        out.append((x, y))
    return out


ICI = Path(__file__).resolve().parent.parent
im = ImageOps.exif_transpose(Image.open(ICI / "sons/photos/20260426_095511.jpg")).convert("RGB")
im.thumbnail((1400, 1400))
d = ImageDraw.Draw(im)
SX, SY, CX, TOP = 710 / (2 * R_BODY), 617 / (R_BODY + Y_CENTER - Y_CUT), 630.0, 128.0


def px(p):
    return (CX + p[0] * SX, TOP + (R_BODY - p[1]) * SY)


# silhouette : cercle coupé au fond plat
sil = [(R_BODY * math.cos(t), R_BODY * math.sin(t)) for t in
       [i * 2 * math.pi / 200 for i in range(201)]]
sil = [(x, max(y, Y_CUT - Y_CENTER)) for x, y in sil]
d.line([px(p) for p in sil], fill=(0, 160, 255), width=2)
ws = rounded(-WS_HALF_W, WS_HALF_W, face_y(WS_BOT), face_y(WS_TOP), WS_CORNER, 99.0)
d.line([px(p) for p in ws + ws[:1]], fill=(0, 255, 0), width=3)
dr = rounded(DOOR_X0, DOOR_RHO + 0.05, max(face_y(DOOR_BOT), Y_CUT - Y_CENTER + 0.06),
             face_y(DOOR_TOP), DOOR_CORNER, DOOR_RHO)
for sgn in (1, -1):
    pts = [(sgn * x, y) for x, y in dr]
    d.line([px(p) for p in pts + pts[:1]], fill=(255, 0, 255), width=3)


sortie = Path("/tmp/face_superposee.png")
im.save(sortie)
print(sortie)
