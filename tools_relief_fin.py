#!/usr/bin/env python3
"""Relief fin (cran 0, PC) : données et hauteurs de pylônes.

  python tools_relief_fin.py source  DOSSIER   altitude IGN (RGE ALTI) sur l'emprise du jeu, calée sur
                                               la grille de la source, sans rééchantillonnage serveur
  python tools_relief_fin.py ecart   DOSSIER   écrit godot_project/data/relief_fin/domaine.bin
  python tools_relief_fin.py hauteurs DOSSIER [DOSSIER…]
        réunit les sorties geometrie_fin_*.json du précalcul (precalcul_geometrie.gd --relief-fin)
        et les hauteurs posées à la main, dans godot_project/data/remontees/geometrie_fin.json

Hypothèse sur la source : la grille WMS du service est de 360/2^23 degré (3,35 × 4,78 m ici) ; ce
n'est pas une résolution garantie du relevé. Le DOSSIER de la source (310 Mo) reste hors du dépôt.
La grille du jeu subdivise les mailles à 25 m (K = 5), en demi-flottants quantifiés à 5 cm.
"""
import glob
import json
import math
import os
import sys
import time
import urllib.request

RACINE = os.path.dirname(os.path.abspath(__file__))
PROJET = os.path.join(RACINE, 'godot_project')
K = 5
FONDU = 64.0
LAT_O, LON_O = 45.45188591, 6.89898136
M_LAT = 111320.0
M_LON = M_LAT * math.cos(math.radians(LAT_O))
NX, NZ = 844, 691
X0, X1, Z0, Z1 = -6167.80, 14917.00, -8695.66, 8558.94
P = 360.0 / 2 ** 23

# Hauteurs posées à la main, par rang dans les données (k), hors de toute optimisation.
# Leissières : crête et bornes selon la trace GPS, ligne exclue du précalcul (HAUTEURS_A_LA_MAIN).
LEISSIERES = [7.2, 11, 8, 6.5, 9, 15, 12, 7, 6.6, 9.2, 14.2, 20, 16, 7]
# Borsat : l'outil laissait P21 à sa borne de 12 m et 11,5° de trop aux galets, quel que soit le poids
# de la garde (aucun véhicule n'y touche, 2 m de marge) : P21 et P22 reprennent leurs hauteurs à 25 m.
REGLAGES = {'tsd4_borsat_express': {20: 11.33, 21: 11.75}}


def source(dossier):
    import numpy as np
    os.makedirs(dossier, exist_ok=True)
    lo_o = math.floor((LON_O + X0 / M_LON) / P - 2)
    lo_e = math.ceil((LON_O + X1 / M_LON) / P + 2)
    la_s = math.floor((LAT_O - Z1 / M_LAT) / P - 2)
    la_n = math.ceil((LAT_O - Z0 / M_LAT) / P + 2)
    W, H = lo_e - lo_o, la_n - la_s
    T = 2000
    A = np.zeros((H, W), 'f4')
    for ty in range(0, H, T):
        for tx in range(0, W, T):
            w, h = min(T, W - tx), min(T, H - ty)
            nord = la_n - ty
            sud = nord - h
            ouest = lo_o + tx
            est = ouest + w
            nom = os.path.join(dossier, 's_%05d_%05d.bin' % (ty, tx))
            if not os.path.exists(nom):
                u = ('https://data.geopf.fr/wms-r?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&STYLES='
                     '&LAYERS=ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES&CRS=EPSG:4326'
                     f'&BBOX={sud * P:.10f},{ouest * P:.10f},{nord * P:.10f},{est * P:.10f}'
                     f'&WIDTH={w}&HEIGHT={h}&FORMAT=image/x-bil;bits=32')
                for essai in range(4):
                    try:
                        b = urllib.request.urlopen(u, timeout=300).read()
                        assert len(b) == w * h * 4, b[:200]
                        with open(nom + '.tmp', 'wb') as f:
                            f.write(b)
                        os.replace(nom + '.tmp', nom)
                        break
                    except Exception as e:
                        print('essai', essai, e, flush=True)
                        time.sleep(15 * (essai + 1))
                else:
                    raise SystemExit('abandon')
                time.sleep(1)
            A[ty:ty + h, tx:tx + w] = np.fromfile(nom, '<f4').reshape(h, w)
    np.save(os.path.join(dossier, 'source.npy'), A)
    np.save(os.path.join(dossier, 'origine.npy'), np.array([lo_o, la_n, P]))
    print('source : %d × %d pixels' % (W, H))


def ecart(dossier):
    """Écart à relief_hauteurs.png sur la grille fine, annulé en fondu au bord du domaine et
    autour des trous de donnée (Italie)."""
    import zlib
    import numpy as np
    from PIL import Image
    from scipy.ndimage import distance_transform_edt
    Image.MAX_IMAGE_PIXELS = None
    sortie = os.path.join(PROJET, 'data', 'relief_fin', 'domaine.bin')
    DX, DZ = (X1 - X0) / (NX - 1), (Z1 - Z0) / (NZ - 1)
    A = np.load(os.path.join(dossier, 'source.npy'))
    lo_o, la_n, p = np.load(os.path.join(dossier, 'origine.npy'))
    png = np.array(Image.open(os.path.join(PROJET, 'textures', 'relief_hauteurs.png')).convert('RGB')).astype('f4')
    h0 = 1300.0 + (png[..., 0] * 256 + png[..., 1]) * 0.1
    n, m = (NZ - 1) * K + 1, (NX - 1) * K + 1
    fz, fx = np.arange(n) / K, np.arange(m) / K
    i = np.minimum(fz.astype(int), NZ - 2)
    j = np.minimum(fx.astype(int), NX - 2)
    v = (fz - i)[:, None].astype('f4')
    u = (fx - j)[None, :].astype('f4')
    a, b, c, d = h0[np.ix_(i, j)], h0[np.ix_(i, j + 1)], h0[np.ix_(i + 1, j)], h0[np.ix_(i + 1, j + 1)]
    tri = np.where(u + v <= 1.0, a + (b - a) * u + (c - a) * v, d + (c - d) * (1 - u) + (b - d) * (1 - v))
    x = X0 + np.arange(m) * DX / K
    z = Z0 + np.arange(n) * DZ / K
    gx = (LON_O + x / M_LON) / p - lo_o - 0.5
    gy = la_n - (LAT_O - z / M_LAT) / p - 0.5
    jj = np.clip(gx.astype(int), 0, A.shape[1] - 2)
    ii = np.clip(gy.astype(int), 0, A.shape[0] - 2)
    uu = (gx - jj)[None, :].astype('f4')
    vv = (gy - ii)[:, None].astype('f4')
    a, b, c, d = A[np.ix_(ii, jj)], A[np.ix_(ii, jj + 1)], A[np.ix_(ii + 1, jj)], A[np.ix_(ii + 1, jj + 1)]
    g = (a * (1 - uu) + b * uu) * (1 - vv) + (c * (1 - uu) + d * uu) * vv
    sans = (a < 500) | (b < 500) | (c < 500) | (d < 500)
    e = np.where(sans, 0.0, g - tri).astype('f4')
    libre = ~sans
    libre[0, :] = libre[-1, :] = False
    libre[:, 0] = libre[:, -1] = False
    dist = distance_transform_edt(libre, sampling=(DZ / K, DX / K)).astype('f4')
    t = np.clip(dist / FONDU, 0, 1)
    e *= t * t * (3 - 2 * t)
    q = (np.round(e * 20) / 20).astype('<f2')
    z_ = zlib.compress(q.tobytes(), 9)
    with open(sortie + '.tmp', 'wb') as f:
        f.write(z_)
    os.replace(sortie + '.tmp', sortie)
    print('nœuds %d × %d, fichier %.2f Mo' % (n, m, len(z_) / 1e6))


def hauteurs(dossiers):
    """Les sorties sont lues dans l'ordre : la dernière gagne (lignes relancées à part)."""
    d = {}
    for dos in dossiers:
        for f in sorted(glob.glob(os.path.join(dos, 'geometrie_fin_*.json'))):
            with open(f, encoding='utf8') as h:
                d.update(json.load(h))
    d['tsd6_leissieres'] = [{'h': h, 'k': k} for k, h in enumerate(LEISSIERES)]
    for cle, regl in REGLAGES.items():
        for e in d[cle]:
            if e.get('k') in regl:
                e['h'] = regl[e['k']]
    p = os.path.join(PROJET, 'data', 'remontees', 'geometrie_fin.json')
    with open(p + '.tmp', 'w', encoding='utf8') as f:
        json.dump(d, f, ensure_ascii=False, indent=1, sort_keys=True)
    os.replace(p + '.tmp', p)
    print('%d lignes, %d hauteurs' % (len(d), sum(len(v) for v in d.values())))


if __name__ == '__main__':
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    if sys.argv[1] == 'source':
        source(sys.argv[2])
    elif sys.argv[1] == 'ecart':
        ecart(sys.argv[2])
    elif sys.argv[1] == 'hauteurs':
        hauteurs(sys.argv[2:])
    else:
        raise SystemExit(__doc__)
