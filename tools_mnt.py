"""Accès au relief réel pour les outils du dépôt (panorama de la gare amont,
coupe de la vue profil du PC) : Terrain Tiles (Mapzen, AWS Open Data,
encodage « terrarium » — sources SRTM, EU-DEM (produit avec des données
Copernicus), GMTED), tuiles mises en cache dans ~/.cache/perce-neige-dem.
"""
import os
import urllib.request

import numpy as np
from PIL import Image

CACHE = os.path.expanduser("~/.cache/perce-neige-dem")


def tuile(z, x, y):
    os.makedirs(CACHE, exist_ok=True)
    f = os.path.join(CACHE, f"{z}_{x}_{y}.png")
    if not os.path.exists(f):
        url = f"https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
        with urllib.request.urlopen(url, timeout=60) as r:
            open(f, "wb").write(r.read())
    a = np.asarray(Image.open(f).convert("RGB"), np.float32)
    return a[..., 0] * 256.0 + a[..., 1] + a[..., 2] / 256.0 - 32768.0


def px_global(lat, lon, z):
    n = 256.0 * 2 ** z
    x = (lon + 180.0) / 360.0 * n
    la = np.radians(lat)
    y = (1.0 - np.log(np.tan(la) + 1.0 / np.cos(la)) / np.pi) / 2.0 * n
    return x, y


def altitude(lat, lon, z=14):
    """Altitude du terrain (m) en des points lat/lon (tableaux numpy),
    interpolée bilinéairement dans les tuiles du niveau z."""
    lat = np.asarray(lat, np.float64)
    lon = np.asarray(lon, np.float64)
    x, y = px_global(lat, lon, z)
    out = np.empty(x.shape, np.float64)
    tx, ty = np.floor(x / 256).astype(int), np.floor(y / 256).astype(int)
    cache = {}
    for k in np.ndindex(x.shape):
        cle = (tx[k], ty[k])
        if cle not in cache:
            cache[cle] = np.pad(tuile(z, *cle), ((0, 1), (0, 1)), mode="edge")
        h = cache[cle]
        fx, fy = x[k] - tx[k] * 256, y[k] - ty[k] * 256
        i0, j0 = int(fy), int(fx)
        u, v = fx - j0, fy - i0
        out[k] = (h[i0, j0] * (1 - u) * (1 - v) + h[i0, j0 + 1] * u * (1 - v)
                  + h[i0 + 1, j0] * (1 - u) * v + h[i0 + 1, j0 + 1] * u * v)
    return out
