"""Pistes de ski autour du funiculaire, pour le skieur jouable — régénérable :
    python3 tools_pistes.py [cache.json]
      → godot_project/textures/pistes_masque.png  (neige damée, même emprise
                                                    et même taille que
                                                    relief_ortho.jpg)
      → godot_project/scripts/pistes_donnees.gd    (tracés, noms, couleurs)

Demande de Kevin (07/10/2026) : « tu me mets de la neige sur la piste, ça
m'évitera d'abîmer mes skis » ; « tu as balisé les pistes ? ».

Source : OpenStreetMap (© contributeurs OpenStreetMap, licence ODbL),
requête Overpass sur l'emprise du relief (tools_relief3d.py) : les chemins
`piste:type=downhill`. Une piste est un tracé (axe) ou une surface
(`area=yes`). Les itinéraires hors-piste (`piste:difficulty=freeride`) ne
sont ni damés ni balisés.

Valeurs du simulateur : largeur damée d'un tracé (LARGEUR) ; OSM ne donne
que l'axe.
Couleurs (France) : novice = verte, easy = bleue, intermediate = rouge,
advanced et expert = noire.
"""
import json
import math
import sys
import urllib.parse
import urllib.request

from PIL import Image, ImageDraw, ImageFilter

# emprise et repère : les mêmes que tools_relief3d.py
LAT_O, LON_O = 45.45188591, 6.89898136
LAT0, LAT1 = 45.375, 45.530                  # domaine Tignes – Val d'Isère : des Brévières au glacier du Pissaillas (+ marge), Kevin 09/10/2026
LON0, LON1 = 6.820, 7.090
M_LAT = 111320.0
M_LON = 111320.0 * math.cos(math.radians(LAT_O))
X_OUEST = (LON0 - LON_O) * M_LON
X_EST = (LON1 - LON_O) * M_LON
Z_NORD = -(LAT1 - LAT_O) * M_LAT
Z_SUD = -(LAT0 - LAT_O) * M_LAT

LARGEUR = 30.0             # m, largeur damée d'une piste donnée par son axe
TOLERANCE = 4.0            # m, simplification des tracés
COULEURS = {"novice": 0, "easy": 1, "intermediate": 2, "advanced": 3, "expert": 3}
NOMS_COULEURS = ["verte", "bleue", "rouge", "noire"]

REQUETE = f"""[out:json][timeout:120];
way["piste:type"="downhill"]({LAT0},{LON0},{LAT1},{LON1});
out body geom;"""


def charger():
    if len(sys.argv) > 1:
        return json.load(open(sys.argv[1], encoding="utf-8"))
    erreur = None
    for url in ("https://overpass-api.de/api/interpreter",
                "https://overpass.kumi.systems/api/interpreter",
                "https://overpass.private.coffee/api/interpreter",
                "https://maps.mail.ru/osm/tools/overpass/api/interpreter"):
        req = urllib.request.Request(
            url, data=urllib.parse.urlencode({"data": REQUETE}).encode(),
            headers={"User-Agent": "perce-neige-sim (tools_pistes.py)"})
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.load(r)
        except Exception as e:          # serveur saturé : le suivant
            erreur = e
    raise SystemExit("Overpass indisponible : %s" % erreur)


def xz(p):
    return ((p["lon"] - LON_O) * M_LON, -(p["lat"] - LAT_O) * M_LAT)


def simplifier(pts, tol):
    """Douglas-Peucker."""
    if len(pts) < 3:
        return pts
    a, b = pts[0], pts[-1]
    dx, dz = b[0] - a[0], b[1] - a[1]
    n = math.hypot(dx, dz) or 1e-9
    dmax, imax = 0.0, 0
    for i in range(1, len(pts) - 1):
        d = abs(dz * (pts[i][0] - a[0]) - dx * (pts[i][1] - a[1])) / n
        if d > dmax:
            dmax, imax = d, i
    if dmax <= tol:
        return [a, b]
    return simplifier(pts[:imax + 1], tol)[:-1] + simplifier(pts[imax:], tol)


donnees = charger()
W, H = Image.open("godot_project/textures/relief_ortho.jpg").size
px_m = W / (X_EST - X_OUEST)


def pix(p):
    return ((p[0] - X_OUEST) / (X_EST - X_OUEST) * W, (p[1] - Z_NORD) / (Z_SUD - Z_NORD) * H)


masque = Image.new("L", (W, H), 0)
dessin = ImageDraw.Draw(masque)
pistes = []
n_surf = 0
for e in donnees["elements"]:
    t = e.get("tags", {})
    if e.get("type") != "way" or t.get("piste:type") != "downhill":
        continue
    diff = t.get("piste:difficulty")
    if diff == "freeride":
        continue
    pts = [xz(p) for p in e.get("geometry", [])]
    if len(pts) < 2:
        continue
    surface = e["nodes"][0] == e["nodes"][-1] and t.get("area") == "yes"
    if surface:
        dessin.polygon([pix(p) for p in pts], fill=255)
        n_surf += 1
        continue
    larg = max(2, int(round(LARGEUR * px_m)))
    dessin.line([pix(p) for p in pts], fill=255, width=larg, joint="curve")
    r = larg / 2.0
    for p in (pts[0], pts[-1]):
        u, v = pix(p)
        dessin.ellipse((u - r, v - r, u + r, v + r), fill=255)
    pistes.append((t.get("name") or t.get("piste:name") or "", COULEURS.get(diff, -1),
                   simplifier(pts, TOLERANCE)))
masque = masque.filter(ImageFilter.GaussianBlur(1.2))
masque.save("godot_project/textures/pistes_masque.png", optimize=True)

pistes.sort(key=lambda p: (p[0] == "", p[0], p[1]))
lignes = []
for nom, c, pts in pistes:
    coords = ", ".join("%.1f, %.1f" % (x, z) for x, z in pts)
    lignes.append('\t["%s", %d, [%s]],' % (nom.replace('"', "'"), c, coords))
with open("godot_project/scripts/pistes_donnees.gd", "w", encoding="utf-8") as f:
    f.write(f'''class_name PistesDonnees
extends RefCounted
## GÉNÉRÉ par tools_pistes.py — pistes de ski d'OpenStreetMap
## (© contributeurs OpenStreetMap, licence ODbL). Ne pas éditer à la main.
##
## Repère du jeu (x vers l'est, z vers le sud, origine au pied de la voie).
## La neige damée est dans textures/pistes_masque.png (emprise du relief).

## Largeur damée d'une piste donnée par son axe (valeur du simulateur).
const LARGEUR: float = {LARGEUR:.1f}
## Couleur : 0 verte, 1 bleue, 2 rouge, 3 noire, −1 inconnue.
const NOMS_COULEURS: Array = {json.dumps(NOMS_COULEURS, ensure_ascii=False)}
## [nom, couleur, axe : x0, z0, x1, z1…]
const PISTES: Array = [
{chr(10).join(lignes)}
]


## Axe de la piste i en points (x, z).
static func axe(i: int) -> PackedVector2Array:
\tvar f: Array = PISTES[i][2]
\tvar out: PackedVector2Array = PackedVector2Array()
\tfor k in range(0, f.size() - 1, 2):
\t\tout.append(Vector2(f[k], f[k + 1]))
\treturn out
''')
print("%d tracés, %d surfaces, masque %d×%d (%.2f m/px)" % (len(pistes), n_surf, W, H, 1 / px_m))
