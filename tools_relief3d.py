"""Relief 3D réel du massif autour du funiculaire, pour la vue extérieure de
la PWA — régénérable :
    python3 tools_relief3d.py
      → godot_project/textures/relief_hauteurs.png   (altitudes codées R+G)
      → godot_project/textures/relief_ortho.jpg      (orthophoto)
      → godot_project/scripts/relief_donnees.gd      (emprise, repère)

Demande d'un utilisateur (06/10/2026) : « prolonger [le paysage 3D] jusqu'au tunnel
et jusqu'en bas, jusqu'au lac de Tignes, et dans le rayon autour », pour se
rendre compte d'où passe le tunnel.

Sources (Géoplateforme IGN, Licence Ouverte Etalab 2.0) :
  * relief : RGE ALTI (couche WMS ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES,
    flottants 32 bits), téléchargé à 4 m et lu aux nœuds de la grille ;
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
LAT0, LAT1 = 45.375, 45.530                  # domaine Tignes – Val d'Isère : des Brévières au glacier du Pissaillas (+ marge), retour d'utilisateur 09/10/2026
LON0, LON1 = 6.820, 7.090
PAS_M = 25.0                                 # maille du relief
ORTHO_L = 4096                               # largeur de l'orthophoto (px) — 5,1 m/px sur 21 km
H_BASE = 1300.0                              # altitude codée = H_BASE + valeur / 10 (fonds de vallée à 1 411 m)
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


# --- altitudes : grille nx × nz, ligne 0 = NORD
# 🔴 07/10/2026 : demandé directement à 25 m, le WMS renvoie un relief
# GROSSIER (rééchantillonné depuis un niveau de pyramide plus pauvre) —
# 17 m d'écart quadratique avec l'altitude ponctuelle IGN, 51 m au pire
# dans les barres rocheuses ; le tunnel « sortait » du relief avant la
# gare amont alors qu'il est souterrain (audit_physique/
# tunnel_amont_relief.sage). On télécharge donc à 4 m, par tuiles, et on
# lit la valeur À CHAQUE NŒUD de la grille (centres de pixels alignés).
FIN = 4.0
fin_l = (LON1 - LON0) * M_LON
fin_h = (LAT1 - LAT0) * M_LAT
n_fx = int(round(fin_l / FIN)) + 1
n_fz = int(round(fin_h / FIN)) + 1
TUILE = 1024
dlon = (LON1 - LON0) / (n_fx - 1)
dlat = (LAT1 - LAT0) / (n_fz - 1)
fin_g = np.full((n_fz, n_fx), np.nan)
for i0 in range(0, n_fz, TUILE):
    for j0 in range(0, n_fx, TUILE):
        hh = min(TUILE, n_fz - i0)
        ww = min(TUILE, n_fx - j0)
        # pixels centrés sur les nœuds : bbox élargie d'un demi-pas
        la_n = LAT1 - i0 * dlat + dlat / 2
        la_s = LAT1 - (i0 + hh - 1) * dlat - dlat / 2
        lo_o = LON0 + j0 * dlon - dlon / 2
        lo_e = LON0 + (j0 + ww - 1) * dlon + dlon / 2
        url = ("https://data.geopf.fr/wms-r?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&STYLES="
               f"&LAYERS=ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES&CRS=EPSG:4326&BBOX={la_s},{lo_o},{la_n},{lo_e}"
               f"&WIDTH={ww}&HEIGHT={hh}&FORMAT=image/x-bil;bits=32")
        with urllib.request.urlopen(url, timeout=300) as r:
            fin_g[i0:i0 + hh, j0:j0 + ww] = np.frombuffer(r.read(), "<f4").reshape(hh, ww)
# Au-delà de la frontière italienne (à l'est du Pissaillas, de la Tsanteleina)
# le RGE ALTI n'a pas de valeurs : ces nœuds sont complétés plus bas par les
# Terrain Tiles (tools_mnt : SRTM / EU-DEM), comme le relief lointain.
fin_g[~np.isfinite(fin_g) | (fin_g < 500.0)] = np.nan
if np.isnan(fin_g).mean() > 0.5:
    raise SystemExit("relief IGN incomplet (plus de la moitié absente) : relancer plus tard")
# valeur aux nœuds de la grille de 25 m (bilinéaire dans la grille fine)
gi = np.linspace(0.0, n_fz - 1.0, nz)
gj = np.linspace(0.0, n_fx - 1.0, nx)
I0 = np.clip(np.floor(gi).astype(int), 0, n_fz - 2)
J0 = np.clip(np.floor(gj).astype(int), 0, n_fx - 2)
V = (gi - I0)[:, None]
U = (gj - J0)[None, :]
h = (fin_g[I0][:, J0] * (1 - U) * (1 - V) + fin_g[I0][:, J0 + 1] * U * (1 - V)
     + fin_g[I0 + 1][:, J0] * (1 - U) * V + fin_g[I0 + 1][:, J0 + 1] * U * V)
trous = ~np.isfinite(h)
if trous.any():
    import tools_mnt
    la_n = LAT1 - np.arange(nz) * (LAT1 - LAT0) / (nz - 1)
    lo_n = LON0 + np.arange(nx) * (LON1 - LON0) / (nx - 1)
    LA, LO = np.meshgrid(la_n, lo_n, indexing="ij")
    h[trous] = tools_mnt.altitude(LA[trous], LO[trous], 13)
    print("hors RGE ALTI (Italie) : %d nœuds sur %d complétés par les Terrain Tiles" % (trous.sum(), h.size))
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
    # domaine élargi (09/10/2026)
    ("Les Brévières", 45.51061, 6.91914, 0),
    ("Le Lavachet", 45.47084, 6.91342, 0),
    ("Val d'Isère", 45.44956, 6.97874, 0),
    ("La Daille", 45.46018, 6.96493, 0),
    ("Le Fornet", 45.45032, 7.01106, 0),
    ("Rocher de Bellevarde", 45.44519, 6.95110, 2826),
    ("Tête du Solaise", 45.43167, 6.99320, 2551),
    ("Col de l'Iseran", 45.41711, 7.03085, 2764),
    ("Signal de l'Iseran", 45.43235, 7.04129, 3237),
    ("Glacier du Pissaillas", 45.39800, 7.05500, 0),
    ("Pointe de la Sana", 45.38507, 6.91745, 3435),
    ("Aiguille de la Grande Sassière", 45.50500, 6.99984, 3747),
    ("Tsanteleina", 45.47952, 7.04598, 3601),
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
