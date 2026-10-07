"""Fantômes du skieur jouable : les descentes réelles de Kevin, de la gare
du glacier à Val Claret — régénérable :
    python3 tools_fantomes.py DOSSIER_DES_GPX
      → godot_project/scripts/fantomes_donnees.gd

Kevin, 07/10/2026 : « je t'ai mis mes trajectoires GPX dans le coin, si
jamais ça peut t'aider ».

Les traces brutes restent HORS du dépôt (privées). On n'en garde que les
positions dans le repère du jeu, lissées, une par seconde, et le temps
relatif depuis le départ : ni date, ni heure, ni altitude GPS, ni rien
d'autre.

Une descente : le dernier point à moins de R_HAUT de la gare du glacier
avant d'arriver à moins de R_BAS de la gare de Val Claret. Si la trace
monte d'abord sur le glacier (télésiège), elle part du point le plus proche
de la gare APRÈS le haut de la trace (le point le plus éloigné de Val
Claret) : le fantôme ne remonte pas les remontées. On retire l'attente du
début et de la fin.
"""
import glob
import math
import os
import sys
import xml.etree.ElementTree as ET
from datetime import datetime

LAT_O, LON_O = 45.45188591, 6.89898136       # repère du jeu (tools_relief3d.py)
M_LAT = 111320.0
M_LON = 111320.0 * math.cos(math.radians(LAT_O))
GARE_HAUT = (-588.0, 3157.7)                  # gare du glacier (IGN 45,42352 / 6,89146)
GARE_BAS = (0.0, 0.0)                         # pied de la voie, Val Claret
R_HAUT = 80.0
R_BAS = 160.0
LISSAGE = 5                                   # points (≈ 5 s)


def lire(chemin):
    ns = {"g": "http://www.topografix.com/GPX/1/1"}
    pts = []
    for tp in ET.parse(chemin).getroot().iterfind(".//g:trkpt", ns):
        t = tp.find("g:time", ns)
        if t is None:
            continue
        s = datetime.fromisoformat(t.text.replace("Z", "+00:00")).timestamp()
        la, lo = float(tp.get("lat")), float(tp.get("lon"))
        pts.append((s, (lo - LON_O) * M_LON, -(la - LAT_O) * M_LAT))
    pts.sort()
    return pts


def dist(p, q):
    return math.hypot(p[1] - q[0], p[2] - q[1])


def descentes(pts):
    out = []
    i_haut = None
    for i, p in enumerate(pts):
        if dist(p, GARE_HAUT) < R_HAUT:
            i_haut = i
        elif i_haut is not None and dist(p, GARE_BAS) < R_BAS:
            out.append(pts[i_haut:i + 1])
            i_haut = None
    return out


def couper_glacier(seg):
    i_loin = max(range(len(seg)), key=lambda i: dist(seg[i], GARE_BAS))
    i_dep = min(range(i_loin, len(seg)), key=lambda i: dist(seg[i], GARE_HAUT))
    return seg[i_dep:]


def rogner(seg):
    """Départ : premier point d'où l'on s'éloigne pour de bon (30 m en
    moins de 20 s) ; arrivée : symétrique."""
    def bouge(i, sens):
        j = i
        while 0 <= j < len(seg) and abs(seg[j][0] - seg[i][0]) < 20.0:
            if math.hypot(seg[j][1] - seg[i][1], seg[j][2] - seg[i][2]) > 30.0:
                return True
            j += sens
        return False
    a = 0
    while a < len(seg) - 2 and not bouge(a, 1):
        a += 1
    b = len(seg) - 1
    while b > a + 2 and not bouge(b, -1):
        b -= 1
    return seg[a:b + 1]


def lisser_et_echantillonner(seg):
    n = len(seg)
    lis = []
    for i in range(n):
        a, b = max(0, i - LISSAGE // 2), min(n, i + LISSAGE // 2 + 1)
        lis.append((seg[i][0], sum(p[1] for p in seg[a:b]) / (b - a), sum(p[2] for p in seg[a:b]) / (b - a)))
    t0 = lis[0][0]
    out = []
    k = 0
    t = 0.0
    while t0 + t <= lis[-1][0]:
        while k < n - 2 and lis[k + 1][0] < t0 + t:
            k += 1
        p, q = lis[k], lis[k + 1]
        u = 0.0 if q[0] == p[0] else (t0 + t - p[0]) / (q[0] - p[0])
        u = min(max(u, 0.0), 1.0)
        out.append((p[1] + (q[1] - p[1]) * u, p[2] + (q[2] - p[2]) * u))
        t += 1.0
    return out


tout = []
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.gpx"))):
    for seg in descentes(lire(f)):
        seg = rogner(couper_glacier(seg))
        if len(seg) > 60:
            tout.append(lisser_et_echantillonner(seg))

lignes = []
for k, d in enumerate(tout):
    coords = ", ".join("%.1f, %.1f" % p for p in d)
    lignes.append("\t[%d, [%s]]," % (len(d) - 1, coords))
    print("descente %d : %d min %02d s, %d points" % (k + 1, (len(d) - 1) // 60, (len(d) - 1) % 60, len(d)))
with open("godot_project/scripts/fantomes_donnees.gd", "w", encoding="utf-8") as f:
    f.write(f'''class_name FantomesDonnees
extends RefCounted
## GÉNÉRÉ par tools_fantomes.py — descentes réelles de Kevin (GPS), de la
## gare du glacier à Val Claret. Ne pas éditer à la main.
##
## Positions lissées dans le repère du jeu (x vers l'est, z vers le sud),
## une par seconde depuis le départ ; rien d'autre de la trace d'origine.

## [durée (s), positions à t = 0, 1, 2… s : x0, z0, x1, z1…]
const DESCENTES: Array = [
{chr(10).join(lignes)}
]


## Positions (x, z) de la descente k, une par seconde.
static func points(k: int) -> PackedVector2Array:
\tvar f: Array = DESCENTES[k][1]
\tvar out: PackedVector2Array = PackedVector2Array()
\tfor i in range(0, f.size() - 1, 2):
\t\tout.append(Vector2(f[i], f[i + 1]))
\treturn out
''')
