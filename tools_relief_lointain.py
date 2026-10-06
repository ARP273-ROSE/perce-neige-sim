"""Relief LOINTAIN autour du bloc détaillé, pour la vue extérieure de la PWA
(refonte du 06/10/2026) — régénérable :
    python3 tools_relief_lointain.py
      → godot_project/textures/relief_lointain_hauteurs.png  (altitudes R+G)
      → godot_project/textures/relief_lointain.jpg           (orthophoto)
      → godot_project/scripts/relief_lointain_donnees.gd     (emprise)

Pourquoi : le bloc détaillé (tools_relief3d.py, maille 25 m) s'arrête à
5 km de la ligne ; au-delà, il n'y avait que le panorama photographié depuis
la gare du haut, une image fixe à 10 km — vu d'ailleurs que la gare, c'était
« la vue panoramique du haut, statique, en lévitation » (Kevin). Cet anneau
de 44 × 44 km, maille 200 m, prolonge le vrai relief jusqu'à l'horizon.

Sources :
  * altitudes : Terrain Tiles (AWS Open Data, encodage terrarium, niveau 12 ;
    SRTM, EU-DEM produit avec des données Copernicus, GMTED) — tools_mnt.py ;
  * texture : orthophotographie IGN (Géoplateforme, Licence Ouverte Etalab
    2.0), qui couvre aussi la frange italienne à l'est.
La rotondité de la Terre est appliquée (abaissement d²/2R × (1 − k), k = 0,13
pour la réfraction), comptée depuis le pied de la voie : 33 m au bord.
Même repère que le bloc détaillé : x vers l'est, z vers le sud, origine au
pied de la voie, lat/lon linéaires (approximation plane commune aux deux).
"""
import io
import math
import urllib.request

import numpy as np
from PIL import Image

import tools_mnt

LAT_O, LON_O = 45.45188591, 6.89898136      # pied de la voie (IGN BD TOPO)
M_LAT = 111320.0
M_LON = 111320.0 * math.cos(math.radians(LAT_O))
CX, CZ = -470.0, 1210.0                      # centre du bloc détaillé
DEMI = 22000.0                               # demi-côté (m)
PAS = 200.0
ORTHO_L = 2048
H_ECHELLE = 0.25                             # altitude = (256·R + G) × 0,25 m
R_TERRE, K_REFR = 6371000.0, 0.13

n = int(round(2 * DEMI / PAS)) + 1
xs = CX - DEMI + PAS * np.arange(n)
zs = CZ - DEMI + PAS * np.arange(n)
X, Z = np.meshgrid(xs, zs)                   # ligne 0 = NORD (z le plus petit)
lon = LON_O + X / M_LON
lat = LAT_O - Z / M_LAT
h = tools_mnt.altitude(lat, lon, 12)
h -= (X ** 2 + Z ** 2) / (2.0 * R_TERRE) * (1.0 - K_REFR)
if not np.isfinite(h).all() or h.min() < 300.0:
    raise SystemExit("relief incomplet : relancer plus tard")
code = np.clip(np.round(h / H_ECHELLE), 0, 65535).astype(np.uint32)
rgb = np.zeros((n, n, 3), np.uint8)
rgb[..., 0] = code >> 8
rgb[..., 1] = code & 255
Image.fromarray(rgb, "RGB").save("godot_project/textures/relief_lointain_hauteurs.png", optimize=True)

lat0, lat1 = LAT_O - (CZ + DEMI) / M_LAT, LAT_O - (CZ - DEMI) / M_LAT
lon0, lon1 = LON_O + (CX - DEMI) / M_LON, LON_O + (CX + DEMI) / M_LON
url = ("https://data.geopf.fr/wms-r?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&STYLES="
       f"&LAYERS=ORTHOIMAGERY.ORTHOPHOTOS&CRS=EPSG:4326&BBOX={lat0},{lon0},{lat1},{lon1}"
       f"&WIDTH={ORTHO_L}&HEIGHT={ORTHO_L}&FORMAT=image/jpeg")
with urllib.request.urlopen(url, timeout=300) as r:
    img = Image.open(io.BytesIO(r.read())).convert("RGB")
img.save("godot_project/textures/relief_lointain.jpg", quality=84, optimize=True)

with open("godot_project/scripts/relief_lointain_donnees.gd", "w", encoding="utf-8") as f:
    f.write(f'''class_name ReliefLointainDonnees
extends RefCounted
## GÉNÉRÉ par tools_relief_lointain.py — Terrain Tiles (SRTM / EU-DEM /
## GMTED) + orthophoto IGN (Licence Ouverte Etalab 2.0). Ne pas éditer.
##
## Anneau de relief lointain, {2 * DEMI / 1000:.0f} × {2 * DEMI / 1000:.0f} km, maille {PAS:.0f} m, rotondité
## de la Terre incluse ; ligne 0 de relief_lointain_hauteurs.png au NORD.

const N: int = {n}
const X_OUEST: float = {CX - DEMI:.1f}
const Z_NORD: float = {CZ - DEMI:.1f}
const PAS: float = {PAS:.1f}
const H_ECHELLE: float = {H_ECHELLE}   # altitude = (256·R + G) × H_ECHELLE
''')
print("anneau %d × %d (maille %.0f m), %.0f-%.0f m ; lat %.4f-%.4f, lon %.4f-%.4f"
      % (n, n, PAS, h.min(), h.max(), lat0, lat1, lon0, lon1))
