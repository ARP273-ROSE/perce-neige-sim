"""Relief 3D réel du massif autour du funiculaire, pour la vue extérieure de
la PWA — régénérable :
    python3 tools_relief3d.py
      → godot_project/textures/relief_hauteurs.png   (altitudes codées R+G)
      → godot_project/textures/relief_ortho.jpg      (orthophoto)
      → godot_project/scripts/relief_donnees.gd      (emprise, repère)

Demande de Kevin (06/10/2026) : « prolonger [le paysage 3D] jusqu'au tunnel
et jusqu'en bas, jusqu'au lac de Tignes, et dans le rayon autour », pour se
rendre compte d'où passe le tunnel.

Sources (Géoplateforme IGN, Licence Ouverte Etalab 2.0) :
  * relief : RGE ALTI (couche WMS ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES,
    flottants 32 bits) ;
  * texture : orthophotographie (ORTHOIMAGERY.ORTHOPHOTOS).

Repère du jeu (SlopeProfile.build_path_points) : origine au pied de la voie
(s = 0, bout aval du tracé IGN BD TOPO, 45,45189 °N 6,89898 °E), x vers
l'EST, z vers le SUD, y = altitude en mètres. Les caps de la voie sont
géographiques depuis la v1.15.68 (tracé calé sur l'IGN), donc le relief se
pose sans rotation.
"""
import io
import math
import urllib.request

import numpy as np
from PIL import Image

LAT_O, LON_O = 45.45188591, 6.89898136      # pied de la voie (IGN BD TOPO)
LAT0, LAT1 = 45.395, 45.487                  # du sommet de la Grande Motte au lac de Tignes
LON0, LON1 = 6.838, 6.948
PAS_M = 25.0                                 # maille du relief
ORTHO_L = 2048                               # largeur de l'orthophoto (px)
H_BASE = 1700.0                              # altitude codée = H_BASE + valeur / 10
M_LAT = 111320.0
M_LON = 111320.0 * math.cos(math.radians(LAT_O))

larg_m = (LON1 - LON0) * M_LON
haut_m = (LAT1 - LAT0) * M_LAT
nx = int(round(larg_m / PAS_M)) + 1
nz = int(round(haut_m / PAS_M)) + 1


def wms(couche, fmt, w, h):
    url = ("https://data.geopf.fr/wms-r?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&STYLES="
           f"&LAYERS={couche}&CRS=EPSG:4326&BBOX={LAT0},{LON0},{LAT1},{LON1}"
           f"&WIDTH={w}&HEIGHT={h}&FORMAT={fmt}")
    with urllib.request.urlopen(url, timeout=180) as r:
        return r.read()


# --- altitudes : grille nx × nz, ligne 0 = NORD (haut de l'image WMS)
brut = wms("ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES", "image/x-bil;bits=32", nx, nz)
h = np.frombuffer(brut, "<f4").reshape(nz, nx).astype(np.float64)
if not np.isfinite(h).all() or h.min() < 500.0:
    raise SystemExit("relief IGN incomplet (valeurs absentes) : relancer plus tard")
code = np.clip(np.round((h - H_BASE) * 10.0), 0, 65535).astype(np.uint32)
rgb = np.zeros((nz, nx, 3), np.uint8)
rgb[..., 0] = code >> 8
rgb[..., 1] = code & 255
Image.fromarray(rgb, "RGB").save("godot_project/textures/relief_hauteurs.png", optimize=True)

# --- orthophoto
ortho_h = int(round(ORTHO_L * haut_m / larg_m))
img = Image.open(io.BytesIO(wms("ORTHOIMAGERY.ORTHOPHOTOS", "image/jpeg", ORTHO_L, ortho_h))).convert("RGB")
img.save("godot_project/textures/relief_ortho.jpg", quality=86, optimize=True)

# --- lieux nommés (OpenStreetMap, © contributeurs, ODbL ; altitudes OSM)
LIEUX = [
    ("Lac de Tignes", 45.46569, 6.90396, 0),
    ("Tignes le Lac", 45.46973, 6.90759, 0),
    ("Val Claret", 45.45631, 6.89997, 0),
    ("Grande Motte", 45.41079, 6.86988, 3653),
    ("Dôme de Pramecou", 45.43437, 6.87810, 3081),
    ("Pointe de Pramecou", 45.43728, 6.86880, 3009),
    ("Rochers de la Grande Balme", 45.44316, 6.88515, 2882),
    ("Col de la Leisse", 45.42451, 6.90810, 2761),
    ("La Tovière", 45.45616, 6.91995, 2696),
    ("Lac du Chevril", 45.48211, 6.94246, 0),
    ("Grand Lac de Chardonet", 45.46568, 6.88303, 0),
    ("Aiguille Percée", 45.48351, 6.89017, 2748),
]
lieux_gd = "".join('\t["%s", %.1f, %.1f, %d],\n' % (n, (lo - LON_O) * M_LON, -(la - LAT_O) * M_LAT, a)
                   for n, la, lo, a in LIEUX)

# --- emprise dans le repère du jeu
x0 = (LON0 - LON_O) * M_LON
x1 = (LON1 - LON_O) * M_LON
z_nord = -(LAT1 - LAT_O) * M_LAT
z_sud = -(LAT0 - LAT_O) * M_LAT
with open("godot_project/scripts/relief_donnees.gd", "w", encoding="utf-8") as f:
    f.write(f'''class_name ReliefDonnees
extends RefCounted
## GÉNÉRÉ par tools_relief3d.py — relief IGN RGE ALTI + orthophoto IGN
## (Licence Ouverte Etalab 2.0). Ne pas éditer à la main.
##
## Emprise dans le repère du jeu (x vers l'est, z vers le sud, origine au
## pied de la voie) ; la ligne 0 de relief_hauteurs.png est au NORD (z_nord).

const NX: int = {nx}
const NZ: int = {nz}
const X_OUEST: float = {x0:.2f}
const X_EST: float = {x1:.2f}
const Z_NORD: float = {z_nord:.2f}
const Z_SUD: float = {z_sud:.2f}
const H_BASE: float = {H_BASE}
const H_ECHELLE: float = 0.1     # altitude = H_BASE + (256·R + G) × H_ECHELLE

## Lieux nommés (OpenStreetMap) : [nom, x, z, altitude affichée (0 = aucune)]
const LIEUX: Array = [
{lieux_gd}]
''')
print("relief %d × %d (maille %.1f m), %.0f-%.0f m ; orthophoto %d × %d ; emprise %.0f × %.0f m"
      % (nx, nz, PAS_M, h.min(), h.max(), ORTHO_L, ortho_h, larg_m, haut_m))
print("au pied de la voie : %.1f m" % h[int(round((LAT1 - LAT_O) * M_LAT / PAS_M)),
                                         int(round((LON_O - LON0) * M_LON / PAS_M))])
