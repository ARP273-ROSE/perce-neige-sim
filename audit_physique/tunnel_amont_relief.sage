# Le tunnel « sort » du relief avant la gare amont (07/10/2026) — Kevin :
# « normalement il est souterrain tout le temps, donc soit c'est une
# imprécision de carte ? ».
#
# Données (tunnel_amont_alti.json, préparé en Python : notre tracé
# reconstruit avec la loi de pente du jeu, SlopeProfile, fin de voie
# vérifiée à 0,5 m près ; altitudes IGN RGE ALTI par le service
# d'altimétrie de la Géoplateforme, ponctuelles, tous les 4 m le long de
# notre axe et à ±10, 20, 30 m de part et d'autre, et le long du tracé
# IGN BD TOPO (précision planimétrique 10 m)) ; LiDAR HD IGN, MNT à
# 0,5 m (11/09/2022) sur x −710 → −470, z 3030 → 3270 (repère du jeu).
#
#   docker exec sagemath sage /home/sage/work/pn/tunnel_amont_relief.sage
import json
import numpy as np

D = json.load(open('/home/sage/work/pn/tunnel_amont_alti.json'))
T = np.load('/home/sage/work/pn/lidar_mnt_amont.npy')
X0, X1, Z0, Z1, N = -710.0, -470.0, 3030.0, 3270.0, 480
R_TUNNEL = 2.0          # demi-hauteur du tube au-dessus de l'axe (rayon 1,95 m)


def lidar(x, z):
    fi = (z - Z0) / (Z1 - Z0) * N - 0.5
    fj = (x - X0) / (X1 - X0) * N - 0.5
    if fi < 0 or fj < 0 or fi >= N - 1 or fj >= N - 1:
        return None
    i, j = int(fi), int(fj)
    di, dj = fi - i, fj - j
    return float(T[i, j] * (1 - di) * (1 - dj) + T[i + 1, j] * di * (1 - dj)
                 + T[i, j + 1] * (1 - di) * dj + T[i + 1, j + 1] * di * dj)


# par abscisse : terrain à l'aplomb et sur ±30 m
par_s = {}
for s, off, x, z, y, zr in D['axe']:
    par_s.setdefault(s, {'y': y, 'x': None, 'z': None, 'lat': {}})
    par_s[s]['lat'][off] = zr
    if off == 0:
        par_s[s]['x'], par_s[s]['z'] = x, z

print("s (m)   axe     RGE à l'aplomb  couverture   LiDAR à l'aplomb   meilleur côté (±30 m)")
sorties = []
for s in sorted(par_s):
    e = par_s[s]
    voute = e['y'] + R_TUNNEL
    cz = e['lat'][0] - voute
    li = lidar(e['x'], e['z'])
    best_off = max(e['lat'], key=lambda o: e['lat'][o])
    if cz < 0:
        sorties.append(s)
    if int(round(s - 3150)) % 20 == 0 and s >= 3200:
        print("%6.0f  %7.1f   %7.1f        %+6.1f      %s      %+3d m : %+6.1f" % (
            s, e['y'], e['lat'][0], cz,
            ("%7.1f (%+5.1f)" % (li, li - voute)) if li is not None else "   hors zone   ",
            best_off, e['lat'][best_off] - voute))

print()
if sorties:
    print("Tube au-dessus du terrain (RGE ALTI) de s = %.0f à %.0f m (%d points sur %d)" % (
        min(sorties), max(sorties), len(sorties), len(par_s)))

# LiDAR contre RGE ALTI là où les deux existent : la carte est-elle juste ?
ec = []
for s in sorted(par_s):
    e = par_s[s]
    li = lidar(e['x'], e['z'])
    if li is not None:
        ec.append(li - e['lat'][0])
if ec:
    print("LiDAR 0,5 m − RGE ALTI le long de l'axe : moyenne %+.2f m, écart max %.2f m (%d points)"
          % (float(np.mean(ec)), float(np.max(np.abs(ec))), len(ec)))

# le long du tracé IGN : distance depuis le bout amont
print()
print("Tracé IGN BD TOPO (même distance depuis le bout amont que notre axe) :")
fin_jeu = D['fin_jeu'][0]
for d_fin, x, z, zr in D['ign']:
    if int(round(d_fin)) % 40 < 4:
        s_eq = fin_jeu - d_fin
        e = par_s.get(min(par_s, key=lambda q: abs(q - s_eq)))
        print("  à %4.0f m du bout : terrain IGN %.1f m ; notre voûte à la même distance %.1f m (%+.1f)"
              % (d_fin, zr, e['y'] + R_TUNNEL, zr - e['y'] - R_TUNNEL))

# quelle pente faudrait-il pour passer SOUS le creux tout en arrivant en
# gare à la bonne altitude ?
s_creux = min([q for q in par_s if q < 3430], key=lambda q: par_s[q]['lat'][0] - par_s[q]['y'])
e = par_s[s_creux]
y_requis = e['lat'][0] - R_TUNNEL - 5.0          # 5 m de couverture
y_fin = D['fin_jeu'][2]
pente = (y_fin - y_requis) / (fin_jeu - s_creux)
print()
print("Couverture la plus faible avant la gare : s = %.0f m, terrain %.1f m, notre axe %.1f m" % (
    s_creux, e['lat'][0], e['y']))
print("  couverture %.1f m de roche au-dessus de la voûte" % (e['lat'][0] - e['y'] - R_TUNNEL))

# Le relief 3D du jeu (relief_hauteurs.png, maille 25 m, WMS IGN) contre
# l'altitude IGN ponctuelle aux mêmes points : d'où vient l'écart ?
from PIL import Image
NX, NZ = 345, 411
XO, XE, ZN, ZS = -4762.15, 3827.96, -3908.90, 6332.54
img = np.asarray(Image.open('/home/sage/work/pn/relief_hauteurs.png').convert('RGB')).astype(float)
H = 1700.0 + (img[..., 0] * 256 + img[..., 1]) * 0.1
dx = (XE - XO) / (NX - 1)
dz = (ZS - ZN) / (NZ - 1)


def grille(x, z):
    fx = (x - XO) / dx
    fz = (z - ZN) / dz
    j, i = int(fx), int(fz)
    u, v = fx - j, fz - i
    return float((H[i, j] * (1 - u) + H[i, j + 1] * u) * (1 - v) + (H[i + 1, j] * (1 - u) + H[i + 1, j + 1] * u) * v)


print()
print("Relief du jeu (grille 25 m) contre IGN ponctuel, le long de l'axe :")
diffs = []
for s in sorted(par_s):
    e = par_s[s]
    g = grille(e['x'], e['z'])
    diffs.append((s, g - e['lat'][0]))
    if int(round(s - 3150)) % 40 == 0:
        print("  s %4.0f : grille %.1f, IGN ponctuel %.1f (%+.1f)" % (s, g, e['lat'][0], g - e['lat'][0]))
print("  écart moyen %+.1f m, extrêmes %+.1f / %+.1f m" % (
    float(np.mean([d for s, d in diffs])), min(d for s, d in diffs), max(d for s, d in diffs)))
# décalage de la grille ? on cherche la translation (dx, dz) qui la recale
best = None
for ox in range(-60, 61, 5):
    for oz in range(-60, 61, 5):
        err = [grille(par_s[s]['x'] + ox, par_s[s]['z'] + oz) - par_s[s]['lat'][0] for s in par_s]
        r = float(np.sqrt(np.mean(np.square(err))))
        if best is None or r < best[0]:
            best = (r, ox, oz)
err0 = [grille(par_s[s]['x'], par_s[s]['z']) - par_s[s]['lat'][0] for s in par_s]
print("  écart quadratique sans décalage %.1f m ; meilleur décalage de la grille (%+d m est, %+d m sud) : %.1f m"
      % (float(np.sqrt(np.mean(np.square(err0)))), best[1], best[2], best[0]))
