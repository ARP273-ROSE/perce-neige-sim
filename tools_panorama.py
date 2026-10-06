"""Panorama de montagnes vu des baies vitrées de la gare amont (Grande Motte,
3 032 m), calculé sur le RELIEF RÉEL — régénérable :
    python3 tools_panorama.py  →  godot_project/textures/panorama_glacier.png

Retour de Kevin du 06/10/2026 : « des portes coulissantes avec baies
vitrées et vue sur les montagnes dont le sommet de la Grande Motte ».

Relief : Terrain Tiles (Mapzen, AWS Open Data, encodage « terrarium ») —
sources SRTM, EU-DEM (produit avec des données Copernicus), GMTED ; accès
et cache dans tools_mnt.py.

Rendu en perspective cylindrique depuis la gare amont du funiculaire
(IGN BD TOPO, bout de la voie : 45,42352 °N, 6,89146 °E, 3 029 m), centre de
l'image = cap RÉEL de la voie en arrivée (214,2°, ajusté sur l'IGN, cf.
audit_physique/trace_ign.sage ; = SlopeProfile.heading_at(LENGTH)), sur le
tour complet (la vue extérieure et la vue salle des machines tournent
autour de la gare) ; la Grande Motte (3 653 m) est à 2,3 km au
cap 229°, la Grande Casse (3 855 m) à 5,6 km au cap 244° ; de −25° à +35° en site, mêmes
pixels/degré dans les deux sens. Courbure terrestre et réfraction (k = 0,13)
prises en compte. Habillage hivernal : neige sous 38° de pente, roche
au-delà, forêt dans les fonds de vallée, ombres portées du soleil, voile
atmosphérique.
"""
import math

import numpy as np
from PIL import Image, ImageFilter

from tools_mnt import px_global, tuile

LAT0, LON0 = 45.42352, 6.89146      # gare amont (IGN BD TOPO)
CAP_CENTRE = 214.2                    # cap réel de la voie en gare amont
W, H = 6144, 1024
SPAN_H = 360.0                        # tour complet (vues extérieure et salle des machines)
PX_DEG = W / SPAN_H
SITE_HAUT = 35.0                      # site de la première ligne
HORIZON = SITE_HAUT * PX_DEG          # ligne du site 0°
SOLEIL_AZ, SOLEIL_EL = 128.0, 24.0    # matinée d'hiver, sud-est
R_TERRE = 6371000.0
K_REFRACTION = 0.13
SORTIE = "godot_project/textures/panorama_glacier.png"


class Niveau:
    """Mosaïque de tuiles d'un niveau de zoom + couleurs pré-calculées."""

    def __init__(self, z, rayon_m):
        self.z = z
        dlat = rayon_m / 111320.0
        dlon = rayon_m / (111320.0 * math.cos(math.radians(LAT0)))
        x0, y0 = px_global(LAT0 + dlat, LON0 - dlon, z)
        x1, y1 = px_global(LAT0 - dlat, LON0 + dlon, z)
        self.tx0, self.ty0 = int(x0 // 256), int(y0 // 256)
        tx1, ty1 = int(x1 // 256), int(y1 // 256)
        lignes = []
        for ty in range(self.ty0, ty1 + 1):
            lignes.append(np.concatenate([tuile(z, tx, ty) for tx in range(self.tx0, tx1 + 1)], 1))
        self.h = np.concatenate(lignes, 0)
        self.m_px = 156543.034 * math.cos(math.radians(LAT0)) / 2 ** z
        self.ny, self.nx = self.h.shape

    def local(self, est, nord):
        """(est, nord) en m autour de la gare → pixel de la mosaïque."""
        lat = LAT0 + nord / 111320.0
        lon = LON0 + est / (111320.0 * math.cos(math.radians(LAT0)))
        x, y = px_global(lat, lon, self.z)
        return y - self.ty0 * 256, x - self.tx0 * 256

    def echantillon(self, champ, py, px):
        py = np.clip(py, 0, self.ny - 1.001)
        px = np.clip(px, 0, self.nx - 1.001)
        i0, j0 = py.astype(int), px.astype(int)
        fy, fx = py - i0, px - j0
        if champ.ndim == 3:
            fy, fx = fy[..., None], fx[..., None]
        return (champ[i0, j0] * (1 - fx) * (1 - fy) + champ[i0, j0 + 1] * fx * (1 - fy)
                + champ[i0 + 1, j0] * (1 - fx) * fy + champ[i0 + 1, j0 + 1] * fx * fy)

    def habiller(self):
        h = self.h
        gy, gx = np.gradient(h, self.m_px)
        # ligne y de la mosaïque vers le SUD : la normale « nord » est +gy
        nrm = np.stack([-gx, gy, np.ones_like(h)], -1)
        nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
        az, el = np.radians(SOLEIL_AZ), np.radians(SOLEIL_EL)
        soleil = np.array([np.sin(az) * np.cos(el), np.cos(az) * np.cos(el), np.sin(el)])
        self.lum = (np.clip(nrm @ soleil, 0.0, 1.0) * self.ombres_portees(az, el)).astype(np.float32)
        self.pente = np.degrees(np.arccos(np.clip(nrm[..., 2], -1, 1))).astype(np.float32)

    def ombres_portees(self, az, el):
        """1 au soleil, 0 à l'ombre d'un relief (marche vers le soleil)."""
        h = self.h
        jj, ii = np.meshgrid(np.arange(self.nx, dtype=np.float32), np.arange(self.ny, dtype=np.float32))
        pas = 2.0
        dx, dy = math.sin(az) * pas, -math.cos(az) * pas   # en pixels (y vers le sud)
        montee = math.tan(el) * pas * self.m_px
        ombre = np.zeros_like(h)
        for k in range(1, int(min(self.nx, 5000.0 / (self.m_px * pas)))):
            py, px = ii + dy * k, jj + dx * k
            dedans = (py >= 0) & (py < self.ny - 1) & (px >= 0) & (px < self.nx - 1)
            if not dedans.any():
                break
            hk = self.echantillon(h, py, px)
            ombre = np.maximum(ombre, np.where(dedans, hk - (h + montee * k), -1.0))
            if k > 50 and k % 50 == 0 and ombre.max() < 0:
                break
        return np.clip(1.0 - ombre / 15.0, 0.0, 1.0)


def bruit(e, n, echelle, graine):
    """bruit de valeur (treillis haché, interpolation lissée) en coordonnées
    terrain (m) : grain fin des limites neige / roche, indépendant du MNT"""
    x, y = e / echelle, n / echelle
    i, j = np.floor(x), np.floor(y)
    fx, fy = x - i, y - j
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)

    def h(a, b):
        v = np.sin(a * 127.1 + b * 311.7 + graine * 74.7) * 43758.5453
        return v - np.floor(v)
    return (h(i, j) * (1 - fx) * (1 - fy) + h(i + 1, j) * fx * (1 - fy)
            + h(i, j + 1) * (1 - fx) * fy + h(i + 1, j + 1) * fx * fy)


C_NEIGE = np.array([0.97, 0.97, 1.00])
C_OMBRE = np.array([0.52, 0.62, 0.82])
C_ROCHE = np.array([0.36, 0.33, 0.31])
C_FORET = np.array([0.13, 0.17, 0.14])


def couleur_terrain(h, lum, pente, e, n):
    g1 = bruit(e, n, 3.0, 1)
    g2 = bruit(e, n, 11.0, 2)
    g3 = bruit(e, n, 37.0, 3)
    seuil = 37.0 + 9.0 * (g2 - 0.5) + 10.0 * (g3 - 0.5) + 3.0 * (g1 - 0.5)
    neige = np.clip((seuil - pente) / 2.5, 0.0, 1.0) * np.clip((h - 1500.0) / 200.0, 0, 1)
    foret = np.clip((2050.0 - h) / 150.0, 0, 1) * np.clip((35.0 - pente) / 10.0, 0, 1) * (g2 > 0.42)
    c_n = C_OMBRE + (C_NEIGE - C_OMBRE) * (lum ** 0.9)[:, None]
    c_n = c_n * (0.96 + 0.06 * g1)[:, None]
    c_r = C_ROCHE * (0.70 + 0.45 * g1 + 0.25 * (g2 - 0.5))[:, None] * (0.30 + 0.80 * lum)[:, None]
    c = c_r + (c_n - c_r) * neige[:, None]
    return c + (C_FORET * (0.6 + 0.6 * lum)[:, None] - c) * (foret * 0.8)[:, None]


proche = Niveau(14, 3500.0)
moyen = Niveau(12, 20000.0)
loin = Niveau(10, 70000.0)
for niv in (proche, moyen, loin):
    niv.habiller()
sol = float(proche.echantillon(proche.h, *proche.local(np.array([0.0]), np.array([0.0])))[0])
oz = sol + 2.0                        # œil d'un passager debout devant la gare
print("sol à la gare (MNT) %.0f m, œil %.0f m" % (sol, oz))

# lancer de rayons par colonne, du proche au lointain (y-buffer)
cap = np.radians(CAP_CENTRE + ((np.arange(W) + 0.5) / W - 0.5) * SPAN_H)
de, dn = np.sin(cap), np.cos(cap)
dists = []
d = 3.0
while d < 70000.0:
    dists.append(d)
    d = d * 1.005 + 1.0
dists = np.array(dists, np.float32)
K = len(dists)
ybuf = np.zeros((K, W), np.float32)
coul = np.zeros((K, W, 3), np.float32)
yb = np.full(W, float(H), np.float32)
for k, dk in enumerate(dists):
    niv = proche if dk < 3000.0 else (moyen if dk < 17000.0 else loin)
    py, px = niv.local(de * dk, dn * dk)
    hh = niv.echantillon(niv.h, py, px) - dk * dk / (2 * R_TERRE) * (1 - K_REFRACTION)
    y_top = HORIZON - np.degrees(np.arctan2(hh - oz, dk)) * PX_DEG
    yb = np.minimum(yb, y_top)
    ybuf[k] = yb
    coul[k] = couleur_terrain(hh + dk * dk / (2 * R_TERRE) * (1 - K_REFRACTION),
                              niv.echantillon(niv.lum, py, px), niv.echantillon(niv.pente, py, px),
                              de * dk, dn * dk)

rows = np.arange(H, dtype=np.float32)
site = (HORIZON - rows) / PX_DEG                     # degrés
t = np.clip(site / SITE_HAUT, 0, 1)[:, None, None]
zenith, bas = np.array([0.13, 0.30, 0.66]), np.array([0.66, 0.78, 0.93])
img = np.broadcast_to(bas + (zenith - bas) * t ** 0.6, (H, W, 3)).copy()
# halo du soleil
s_col = ((SOLEIL_AZ - CAP_CENTRE + 540) % 360 - 180 + SPAN_H / 2) * PX_DEG
s_lig = HORIZON - SOLEIL_EL * PX_DEG
ds = np.hypot(np.arange(W)[None, :] - s_col, rows[:, None] - s_lig)
img += (np.exp(-ds / 260.0) * 0.35 + np.exp(-ds / 22.0) * 0.6)[..., None] * np.array([1.0, 0.96, 0.88])
brume = np.array([0.70, 0.79, 0.92])
for c in range(W):
    rev = ybuf[::-1, c]
    k0 = K - np.searchsorted(rev, rows + 0.5, side="right")
    vis = k0 < K
    if not vis.any():
        continue
    kk = k0[vis]
    f = 1.0 - np.exp(-dists[kk] / 45000.0)
    img[vis, c] = coul[kk, c] * (1 - f[:, None]) + brume * f[:, None]
out = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.4))
out.save(SORTIE, optimize=True)
print("panorama", out.size, "rayons", K, "horizon ligne %.0f, %.2f px/°" % (HORIZON, PX_DEG))
