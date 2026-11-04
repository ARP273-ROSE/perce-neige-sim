#!/usr/bin/env python3
"""Sources du pack haute définition PC : relief, hauteur de végétation et orthophoto IGN
(LiDAR HD et BD ORTHO, Licence Ouverte Etalab 2.0), hors du dépôt.

  python tools_relief_hd.py telecharger DOSSIER [mnt|mnh|ortho …]
  python tools_relief_hd.py lambert DOSSIER         MNT sur la grille d'origine du LiDAR, à lancer avant « relief »
  python tools_relief_hd.py relief DOSSIER          pyramide d'altitudes 1/2/4/8 m : DOSSIER/relief.pnhd
  python tools_relief_hd.py arbres DOSSIER          arbres de la hauteur de végétation : DOSSIER/arbres.pnhd

Grille régulière dans le repère du jeu, pas de 1 m environ : les mailles à 25 m du relief divisées
par K = 25 (même alignement que relief_fin). Tuiles de 2000 pixels, reprise possible : une tuile déjà
écrite n'est pas redemandée. Là où le LiDAR HD manque, le MNT reprend le RGE ALTI.
"""
import math
import os
import sys
import time
import urllib.request

LAT_O, LON_O = 45.45188591, 6.89898136
M_LAT = 111320.0
M_LON = M_LAT * math.cos(math.radians(LAT_O))
NX, NZ = 844, 691
X0, X1, Z0, Z1 = -6167.80, 14917.00, -8695.66, 8558.94
K = 25
NJ = (NX - 1) * K + 1
NI = (NZ - 1) * K + 1
PX = (X1 - X0) / (NX - 1) / K
PZ = (Z1 - Z0) / (NZ - 1) / K
T = 2000
WMS = 'https://data.geopf.fr/wms-r?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&STYLES=&CRS=EPSG:4326'
COUCHES = {
    'mnt': ('IGNF_LIDAR-HD_MNT_ELEVATION.ELEVATIONGRIDCOVERAGE.WGS84G', 'image/x-bil;bits=32', 'bin'),
    'mnh': ('IGNF_LIDAR-HD_MNH_ELEVATION.ELEVATIONGRIDCOVERAGE.WGS84G', 'image/x-bil;bits=32', 'bin'),
    'ortho': ('ORTHOIMAGERY.ORTHOPHOTOS', 'image/jpeg', 'jpg'),
}
SECOURS_MNT = 'ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES'


def url(couche, fmt, ti, tj, w, h):
    # nœuds au centre des pixels
    x0 = X0 + (tj - 0.5) * PX
    x1 = x0 + w * PX
    z0 = Z0 + (ti - 0.5) * PZ
    z1 = z0 + h * PZ
    bbox = '%.8f,%.8f,%.8f,%.8f' % (LAT_O - z1 / M_LAT, LON_O + x0 / M_LON, LAT_O - z0 / M_LAT, LON_O + x1 / M_LON)
    return '%s&LAYERS=%s&BBOX=%s&WIDTH=%d&HEIGHT=%d&FORMAT=%s' % (WMS, couche, bbox, w, h, fmt)


def lire(u, attendu=0):
    for essai in range(8):
        try:
            d = urllib.request.urlopen(u, timeout=240).read()
            if attendu and len(d) != attendu:
                raise ValueError('taille %d : %r' % (len(d), d[:120]))
            if not attendu and d[:2] != b'\xff\xd8':
                raise ValueError('pas une image : %r' % d[:120])
            return d
        except Exception as e:
            print('  reprise', essai, str(e)[:160], flush=True)
            time.sleep(5 + 15 * essai)
    raise RuntimeError(u)


def telecharger(dossier, nom):
    import numpy as np
    couche, fmt, ext = COUCHES[nom]
    os.makedirs(os.path.join(dossier, nom), exist_ok=True)
    n = 0
    total = len(range(0, NI, T)) * len(range(0, NJ, T))
    for ti in range(0, NI, T):
        for tj in range(0, NJ, T):
            n += 1
            f = os.path.join(dossier, nom, '%05d_%05d.%s' % (ti, tj, ext))
            if os.path.exists(f):
                continue
            w, h = min(T, NJ - tj), min(T, NI - ti)
            t0 = time.time()
            d = lire(url(couche, fmt, ti, tj, w, h), w * h * 4 if ext == 'bin' else 0)
            if nom == 'mnt':
                a = np.frombuffer(d, '<f4').reshape(h, w).copy()
                # hors LiDAR : le serveur remplit d'une valeur d'absence ou d'un aplat
                vide = (a < -1000) | (a > 9000)
                if vide.any() or (a[:, 1:] == a[:, :-1]).mean() > 0.5:
                    print('  secours RGE ALTI', ti, tj, flush=True)
                    r = np.frombuffer(lire(url(SECOURS_MNT, fmt, ti, tj, w, h), w * h * 4), '<f4').reshape(h, w)
                    masque = vide | ((a == np.roll(a, 1, 1)) & (a == np.roll(a, 1, 0)))
                    a[masque] = r[masque]
                d = a.tobytes()
            with open(f + '.tmp', 'wb') as s:
                s.write(d)
            os.replace(f + '.tmp', f)
            print('%s %d/%d %.0f s' % (nom, n, total, time.time() - t0), flush=True)
            time.sleep(0.2)


COUCHE_L93 = 'IGNF_LIDAR-HD_MNT_ELEVATION.ELEVATIONGRIDCOVERAGE.LAMB93'


def mnt_lambert(dossier):
    """MNT sur la grille d'origine du LiDAR (Lambert 93, mètres entiers), puis rééchantillonné sur celle du
    jeu. Une demande en degrés revient au plus proche voisin : quadrillage de 0,7 m sur les pentes."""
    import numpy as np
    from pyproj import Transformer
    from scipy import ndimage
    os.makedirs(os.path.join(dossier, 'mnt_l93'), exist_ok=True)
    os.makedirs(os.path.join(dossier, 'mnt'), exist_ok=True)
    vers = Transformer.from_crs(4326, 2154, always_xy=True)
    xs = np.array([X0, X1, X0, X1])
    zs = np.array([Z0, Z0, Z1, Z1])
    ex, ny = vers.transform(LON_O + xs / M_LON, LAT_O - zs / M_LAT)
    e0, e1 = int(ex.min()) - 10, int(ex.max()) + 10
    n0, n1 = int(ny.min()) - 10, int(ny.max()) + 10
    W, H = e1 - e0, n1 - n0
    m = np.zeros((H, W), 'f4')
    for ty in range(0, H, T):
        for tx in range(0, W, T):
            w, h = min(T, W - tx), min(T, H - ty)
            f = os.path.join(dossier, 'mnt_l93', '%05d_%05d.bin' % (ty, tx))
            if not os.path.exists(f):
                # lignes du haut vers le bas ; le pixel (0, 0) est centré sur (e0+tx+0,5 ; n1-ty-0,5)
                u = '%s&LAYERS=%%s&BBOX=%d,%d,%d,%d&WIDTH=%d&HEIGHT=%d&FORMAT=image/x-bil;bits=32' % (
                    WMS.replace('EPSG:4326', 'EPSG:2154'), e0 + tx, n1 - ty - h, e0 + tx + w, n1 - ty, w, h)
                a = np.frombuffer(lire(u % COUCHE_L93, w * h * 4), '<f4').reshape(h, w).copy()
                vide = a < 1000.0
                if vide.any():
                    r = np.frombuffer(lire(u % SECOURS_MNT, w * h * 4), '<f4').reshape(h, w)
                    a[vide] = r[vide]
                with open(f + '.tmp', 'wb') as s:
                    s.write(a.tobytes())
                os.replace(f + '.tmp', f)
                print('l93', ty, tx, 'secours %.1f %%' % (vide.mean() * 100), flush=True)
                time.sleep(0.1)
            m[ty:ty + h, tx:tx + w] = np.fromfile(f, '<f4').reshape(h, w)
    print('mosaïque', m.shape, flush=True)
    # correspondance jeu → Lambert : régulière, calculée sur une grille lâche (écart < 1 mm) et interpolée
    pas = 200
    ic = np.arange(0, NI + pas, pas)
    jc = np.arange(0, NJ + pas, pas)
    jg, ig = np.meshgrid(jc, ic)
    ec, nc = vers.transform(LON_O + (X0 + jg * PX) / M_LON, LAT_O - (Z0 + ig * PZ) / M_LAT)
    for ti in range(0, NI, T):
        for tj in range(0, NJ, T):
            h, w = min(T, NI - ti), min(T, NJ - tj)
            jj, ii = np.meshgrid(np.arange(tj, tj + w) / pas, np.arange(ti, ti + h) / pas)
            e = ndimage.map_coordinates(ec, [ii, jj], order=1)
            n = ndimage.map_coordinates(nc, [ii, jj], order=1)
            r = ndimage.map_coordinates(m, [n1 - n - 0.5, e - e0 - 0.5], order=1, mode='nearest').astype('<f4')
            f = os.path.join(dossier, 'mnt', '%05d_%05d.bin' % (ti, tj))
            with open(f + '.tmp', 'wb') as s:
                s.write(r.tobytes())
            os.replace(f + '.tmp', f)
    print('mnt rééchantillonné', flush=True)


def assembler(dossier, nom):
    import numpy as np
    a = np.zeros((NI, NJ), 'f4')
    for ti in range(0, NI, T):
        for tj in range(0, NJ, T):
            h, w = min(T, NI - ti), min(T, NJ - tj)
            a[ti:ti + h, tj:tj + w] = np.fromfile(os.path.join(dossier, nom, '%05d_%05d.bin' % (ti, tj)), '<f4').reshape(h, w)
    return a


def lire_ortho(dossier, ti, tj):
    import numpy as np
    from PIL import Image
    return np.asarray(Image.open(os.path.join(dossier, 'ortho', '%05d_%05d.jpg' % (ti, tj))).convert('RGB'))


def carreler_altitudes(dossier, sortie):
    """Pyramide d'altitudes, voir FORMAT_RELIEF."""
    import numpy as np
    import struct
    import zstandard
    from scipy import ndimage
    a = assembler(dossier, 'mnt')
    # bande nord hors de toute source (0,4 %, loin des pistes) : relief à 25 m du jeu
    v = a < 1400.0  # (absence, et ses mélanges en bordure ; le point le plus bas du domaine est à 1 410 m)
    if v.any():
        from PIL import Image
        im = np.asarray(Image.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'godot_project', 'textures',
                                                'relief_hauteurs.png')).convert('RGB')).astype('f4')
        h = 1300.0 + (256.0 * im[..., 0] + im[..., 1]) * 0.1
        # (l'interpolation en Lambert laisse des valeurs mêlées sur 2 nœuds autour du vide)
        v = ndimage.binary_dilation(v, iterations=3)
        ii, jj = np.nonzero(v)
        a[ii, jj] = ndimage.map_coordinates(h, [ii / K, jj / K], order=1, mode='nearest')
        # raccord adouci sur 30 m, pour ne pas laisser de marche avec le relevé
        c0, c1 = max(0, ii.min() - 60), min(NI, ii.max() + 60)
        bande = a[c0:c1]
        fond = ndimage.gaussian_filter(bande, 8.0)
        d = ndimage.distance_transform_edt(v[c0:c1] == 0)
        d2 = ndimage.distance_transform_edt(v[c0:c1])
        k = np.clip(np.minimum(np.maximum(d, d2), 30.0) / 30.0, 0.0, 1.0)[..., ] 
        a[c0:c1] = fond + (bande - fond) * k
        print('comblés', ii.size, flush=True)
    print('altitudes', float(a.min()), float(a.max()), flush=True)
    cctx = zstandard.ZstdCompressor(level=12, threads=-1)
    corps = []
    index = []
    off = 0
    for niv, pas in enumerate((1, 2, 4, 8)):
        g = a if pas == 1 else ndimage.uniform_filter(a, size=pas + 1, mode='nearest')[::pas, ::pas]
        ni, nj = g.shape
        for ti in range(0, ni - 1, T):
            for tj in range(0, nj - 1, T):
                t = g[ti:ti + T + 1, tj:tj + T + 1]
                base = float(t.min())
                pasq = max(0.02, (float(t.max()) - base) / 65000.0)
                q = np.round((t - base) / pasq).astype('<i4')
                # écart au voisin de gauche, le premier de chaque ligne à celui du dessus
                d = q.copy()
                d[:, 1:] = q[:, 1:] - q[:, :-1]
                d[1:, 0] = q[1:, 0] - q[:-1, 0]
                z = cctx.compress((d & 0xFFFF).astype('<u2').tobytes())
                index.append(struct.pack('<BBHIIHHffQI', niv, 0, 0, ti, tj, t.shape[1], t.shape[0], base, pasq, off, len(z)))
                corps.append(z)
                off += len(z)
        print('niveau', niv, 'pas', pas, 'tuiles', len(index), 'Mo', off >> 20, flush=True)
    tete = struct.pack('<4sIddffIIII', b'PNRH', 1, X0, Z0, PX, PZ, NJ, NI, T, len(index))
    with open(sortie, 'wb') as s:
        s.write(tete)
        s.write(b''.join(index))
        for z in corps:
            s.write(z)
    print('écrit', sortie, os.path.getsize(sortie) >> 20, 'Mo')


FORMAT_RELIEF = """relief.pnhd, petit-boutiste. En-tête : 'PNRH', u32 version, f64 x0, f64 z0, f32 px, f32 pz, u32 nj, u32 ni,
u32 t (2000), u32 n. Puis n entrées de 36 octets (après 48 octets d en-tête) : u8 niveau (pas = 2^niveau × px), u8+u16 réservés, u32 ti, u32 tj (indices au
pas du niveau), u16 largeur, u16 hauteur, f32 base, f32 pas de quantification, u64 position dans le corps, u32 taille. Corps juste
après l'index. Une tuile décompressée (zstd) : largeur × hauteur u16 ; ligne 0 colonne 0 = q, sinon écart modulo 65536 au voisin de
gauche (colonne 0 : au voisin du dessus). Altitude = base + q × pas. Les tuiles partagent leur bord (2001 nœuds)."""



def arbres(dossier, sortie):
    """Arbres détectés sur la hauteur de végétation et l'orthophoto, voir FORMAT_ARBRES."""
    import numpy as np
    import struct
    import zstandard
    from PIL import Image
    from scipy import ndimage
    M = 8
    mnh = assembler(dossier, 'mnh')
    mnt = assembler(dossier, 'mnt')
    cases = {}
    total = 0
    for ti in range(0, NI, T):
        for tj in range(0, NJ, T):
            h, w = min(T, NI - ti), min(T, NJ - tj)
            i0, j0 = max(0, ti - M), max(0, tj - M)
            i1, j1 = min(NI, ti + h + M), min(NJ, tj + w + M)
            m = mnh[i0:i1, j0:j1]
            m = np.where((m < 0) | (m > 60), 0, m)
            s = ndimage.gaussian_filter(m, 1.2)
            pics = (s == ndimage.maximum_filter(s, size=5)) & (s > 2.5)
            # sommet pointu (un toit est plat), emprise de plus de 8 m² (un pylône, un câble sont plus fins)
            pics &= (s - ndimage.uniform_filter(s, size=9)) > 0.35
            pics &= ndimage.uniform_filter((m > 2).astype('f4'), size=5) >= 0.32
            # conifère vu d'avion : sombre et pas bleuté (ombre sur roche), sous la limite des arbres ;
            # en forêt dense, à l'ombre, la couleur ne dit plus rien : c'est la densité qui décide
            o = np.asarray(Image.open(os.path.join(dossier, 'ortho', '%05d_%05d.jpg' % (ti, tj))).convert('RGB')).astype('f4')
            r, g, b = [ndimage.uniform_filter(o[..., k], size=5) for k in range(3)]
            ok = ((r + g + b) / 3 < 125) & (g >= b * 1.02)
            dense = ndimage.uniform_filter((m > 3).astype('f4'), size=41)[ti - i0:ti - i0 + h, tj - j0:tj - j0 + w] > 0.35
            alt = mnt[ti:ti + h, tj:tj + w]
            pics = pics[ti - i0:ti - i0 + h, tj - j0:tj - j0 + w] & (alt < 2450) & (alt > 1000) & (ok | dense)
            ii, jj = np.nonzero(pics)
            hh = np.clip(m[ti - i0:ti - i0 + h, tj - j0:tj - j0 + w][ii, jj], 2.5, 60.0)
            total += ii.size
            x = X0 + (jj + tj) * PX
            z = Z0 + (ii + ti) * PZ
            cx = ((x - X0) // 250).astype('i4')
            cz = ((z - Z0) // 250).astype('i4')
            for u in np.unique(cz * 1000 + cx):
                q = (cz * 1000 + cx) == u
                cases.setdefault(int(u), []).append((x[q], z[q], hh[q]))
            print(ti, tj, ii.size, total, flush=True)
    cctx = zstandard.ZstdCompressor(level=12)
    index = []
    corps = []
    off = 0
    for u in sorted(cases):
        cz, cx = u // 1000, u % 1000
        x = np.concatenate([e[0] for e in cases[u]])
        z = np.concatenate([e[1] for e in cases[u]])
        hh = np.concatenate([e[2] for e in cases[u]])
        rec = np.zeros(x.size, dtype=[('x', '<u2'), ('z', '<u2'), ('h', 'u1'), ('r', 'u1'), ('e', 'u1')])
        rec['x'] = np.clip((x - X0 - cx * 250.0) / 250.0 * 65535.0, 0, 65535)
        rec['z'] = np.clip((z - Z0 - cz * 250.0) / 250.0 * 65535.0, 0, 65535)
        rec['h'] = np.clip(hh * 4.0, 0, 255)
        rec['r'] = np.clip((0.6 + 0.15 * hh) * 10.0, 0, 255)
        d = cctx.compress(rec.tobytes())
        index.append(struct.pack('<HHIQI', cx, cz, x.size, off, len(d)))
        corps.append(d)
        off += len(d)
    with open(sortie, 'wb') as s:
        s.write(struct.pack('<4sIddfI', b'PNAB', 1, X0, Z0, 250.0, len(index)))
        s.write(b''.join(index))
        for d in corps:
            s.write(d)
    print('arbres', total, 'cases', len(index), 'Mo', os.path.getsize(sortie) >> 20)


FORMAT_ARBRES = """arbres.pnhd, petit-boutiste. En-tête 32 octets : 'PNAB', u32 version, f64 x0, f64 z0, f32 côté de case (250 m), u32 n.
Puis n entrées de 20 octets : u16 cx, u16 cz, u32 nombre d'arbres, u64 position dans le corps, u32 taille. Corps juste après l'index.
Une case décompressée (zstd) : enregistrements de 7 octets u16 x, u16 z (relatifs à la case, 65535 = 250 m), u8 h (× 0,25 m),
u8 r rayon de couronne (× 0,1 m, déduit de h), u8 espèce (0 : conifère, seule valeur pour l'instant)."""



if __name__ == '__main__':
    if len(sys.argv) >= 3 and sys.argv[1] == 'telecharger':
        for c in sys.argv[3:] or list(COUCHES):
            telecharger(sys.argv[2], c)
    elif len(sys.argv) >= 3 and sys.argv[1] == 'lambert':
        mnt_lambert(sys.argv[2])
    elif len(sys.argv) >= 3 and sys.argv[1] == 'relief':
        carreler_altitudes(sys.argv[2], os.path.join(sys.argv[2], 'relief.pnhd'))
    elif len(sys.argv) >= 3 and sys.argv[1] == 'arbres':
        arbres(sys.argv[2], os.path.join(sys.argv[2], 'arbres.pnhd'))
    else:
        print(__doc__)
