"""Coupe du terrain le long du funiculaire pour la vue profil du programme PC
(perce_neige_sim.py, « vue en coupe ») — relief RÉEL, régénérable :
    python3 tools_profil_coupe.py  →  profil_coupe.py

Demande de Kevin du 06/10/2026 : refonte complète de la vue profil (« dans
cette vue-là on peut redesigner complètement les rames et le reste »).
Les montagnes de l'ancienne vue étaient des sinusoïdes et le dessus du
relief une ligne à 160 m au-dessus de la voie.

- Terrain : RGE ALTI de l'IGN (service d'altimétrie de la Géoplateforme),
  à défaut les Terrain Tiles.
- Terrain au-dessus de la ligne : le tracé IGN BD TOPO
  (audit_physique/trace_ign_osm.json), échantillonné à fraction égale de sa
  longueur horizontale, le programme le cale sur sa propre longueur
  horizontale (H_MAX).
- En deçà de la gare aval : 1 200 m dans le prolongement du premier tronçon
  (vers le lac de Tignes).
- Au-delà de la gare amont : le long du téléphérique de la Grande Motte
  (gare aval, pylône, gare amont, OpenStreetMap), puis le sommet (3 653 m) et
  600 m de redescente.
- Crêtes de fond : la vue regarde vers l'EST (l'amont, au sud, est à
  droite) ; pour chaque point de la coupe, l'altitude maximale du terrain
  dans une bande perpendiculaire à l'est, de 0,8 à 4 km (crêtes moyennes)
  et de 4 à 18 km (lointaines), courbure terrestre comprise.
Relief : tools_mnt.py (Terrain Tiles : SRTM, EU-DEM, GMTED).
"""
import json
import math
import urllib.request

import numpy as np

from tools_mnt import altitude

SOMMET = (45.41062, 6.86997)        # sommet de la Grande Motte (maximum du MNT)
N_LIGNE = 340
PAS = 10.0
AVAL_M = 1200.0
APRES_SOMMET_M = 600.0
R_TERRE = 6371000.0
K_REFRACTION = 0.13
M_LAT = 111320.0


def m_lon(lat):
    return 111320.0 * math.cos(math.radians(lat))


ign = json.load(open("audit_physique/trace_ign_osm.json"))["ign_lon_lat_z"]
lat0 = ign[0][1]
E = np.array([(p[0] - ign[0][0]) * m_lon(lat0) for p in ign])
N = np.array([(p[1] - lat0) * M_LAT for p in ign])
L = np.concatenate([[0.0], np.cumsum(np.hypot(np.diff(E), np.diff(N)))])


def vers_latlon(e, n):
    return lat0 + n / M_LAT, ign[0][0] + e / m_lon(lat0)


# --- points de la coupe : (est, nord, cap local en degrés)
pts_ligne = []
for i in range(N_LIGNE + 1):
    d = L[-1] * i / N_LIGNE
    k = min(np.searchsorted(L, d, side="right") - 1, len(L) - 2)
    u = (d - L[k]) / (L[k + 1] - L[k])
    cap = math.degrees(math.atan2(E[k + 1] - E[k], N[k + 1] - N[k]))
    pts_ligne.append((E[k] + u * (E[k + 1] - E[k]), N[k] + u * (N[k + 1] - N[k]), cap))
cap0 = pts_ligne[0][2]
pts_aval = []
for j in range(int(AVAL_M / PAS), 0, -1):
    d = j * PAS
    pts_aval.append((E[0] - d * math.sin(math.radians(cap0)), N[0] - d * math.cos(math.radians(cap0)), cap0))
# au-delà de la gare amont, la coupe suit le TÉLÉPHÉRIQUE de la Grande Motte
# (OpenStreetMap way 23140026 : gare aval, pylône P1, gare amont), puis le
# sommet et 600 m au-delà
TPH = {"aval": (45.4233091, 6.8904986), "pylone": (45.4154529, 6.8776271),
       "amont": (45.4135843, 6.874556)}


def en_m(ll):
    return (ll[1] - ign[0][0]) * m_lon(lat0), (ll[0] - lat0) * M_LAT


sommets = [(E[-1], N[-1])] + [en_m(TPH[k]) for k in ("aval", "pylone", "amont")] + [en_m(SOMMET)]
d_cum = [0.0]
for (e0, n0), (e1, n1) in zip(sommets, sommets[1:]):
    d_cum.append(d_cum[-1] + math.hypot(e1 - e0, n1 - n0))
pts_amont = []
total = d_cum[-1] + APRES_SOMMET_M
d = PAS
while d <= total:
    k = min(len(d_cum) - 2, max(0, int(np.searchsorted(d_cum, d, side="right") - 1)))
    (e0, n0), (e1, n1) = sommets[k], sommets[min(k + 1, len(sommets) - 1)]
    if d > d_cum[-1]:
        (e0, n0), (e1, n1) = sommets[-2], sommets[-1]
        u = (d - d_cum[-2]) / (d_cum[-1] - d_cum[-2])
    else:
        u = (d - d_cum[k]) / max(d_cum[k + 1] - d_cum[k], 1e-9)
    cap = math.degrees(math.atan2(e1 - e0, n1 - n0))
    pts_amont.append((e0 + u * (e1 - e0), n0 + u * (n1 - n0), cap))
    d += PAS
d_s = d_cum[-1]
TPH_X = {"aval": d_cum[1], "pylone": d_cum[2], "amont": d_cum[3]}
TPH_CALC = json.load(open("audit_physique/telepherique_resultat.json"))


def rge_alti(la, lo):
    """altitudes IGN RGE ALTI (service d'altimétrie de la Géoplateforme,
    Licence Ouverte) ; None si le service ne répond pas"""
    out = []
    try:
        for a in range(0, len(la), 100):
            url = ("https://data.geopf.fr/altimetrie/1.0/calcul/alti/rest/elevation.json?lon=%s&lat=%s"
                   "&resource=ign_rge_alti_wld&zonly=true"
                   % ("|".join("%.6f" % x for x in lo[a:a + 100]), "|".join("%.6f" % x for x in la[a:a + 100])))
            out += json.load(urllib.request.urlopen(url, timeout=60))["elevations"]
    except OSError:
        return None
    return np.array(out) if len(out) == len(la) and min(out) > 0 else None


def surface(pts):
    """terrain au-dessus des points : RGE ALTI de l'IGN (1-5 m), à défaut
    les Terrain Tiles (SRTM / EU-DEM, ~30 m, plus lisses de ~10 m)"""
    la, lo = vers_latlon(np.array([p[0] for p in pts]), np.array([p[1] for p in pts]))
    z = rge_alti(la, lo)
    return z if z is not None else altitude(la, lo, 14)


def cretes(pts, d0, d1, pas):
    """altitude max apparente dans la bande [d0, d1] à l'est de chaque point"""
    out = []
    dists = np.arange(d0, d1, pas)
    chute = dists ** 2 / (2 * R_TERRE) * (1 - K_REFRACTION)
    for e, n, cap in pts:
        az = math.radians(cap - 90.0)           # à gauche en montant = à l'est
        la, lo = vers_latlon(e + dists * math.sin(az), n + dists * math.cos(az))
        out.append(float(np.max(altitude(la, lo, 12) - chute)))
    return out


def arrondi(v):
    return [round(float(x), 1) for x in v]


tous = pts_aval + pts_ligne + pts_amont
grossier = tous[::4]
def lisser(v, n=2):
    """moyenne glissante sur 2n+1 points : un maximum sur une bande saute
    d'un sommet à l'autre et ferait des pointes"""
    v = np.array(v)
    return [float(np.mean(v[max(0, i - n):i + n + 1])) for i in range(len(v))]


mi = lisser(cretes(grossier, 800.0, 4000.0, 60.0))
loin = lisser(cretes(grossier, 4000.0, 18000.0, 150.0))
sortie = f'''"""Coupe du terrain le long du funiculaire — GÉNÉRÉ par tools_profil_coupe.py
(relief réel : IGN RGE ALTI au-dessus de la ligne, Terrain Tiles SRTM / EU-DEM
pour les crêtes de fond ; tracé IGN BD TOPO).
Ne pas éditer à la main : relancer l'outil."""

# Terrain au-dessus de la ligne, à fraction égale f = i / N_LIGNE de la
# longueur horizontale de la ligne (le programme la cale sur H_MAX).
N_LIGNE = {N_LIGNE}
SURFACE_LIGNE = {arrondi(surface(pts_ligne))}

# En deçà de la gare aval, tous les {PAS:.0f} m (le premier est le plus loin).
PAS_PROLONGEMENT = {PAS}
SURFACE_AVAL = {arrondi(surface(pts_aval))}

# Au-delà de la gare amont, tous les {PAS:.0f} m, le long du téléphérique de la
# Grande Motte puis jusqu'au sommet (à {d_s:.0f} m), et {APRES_SOMMET_M:.0f} m au-delà.
SURFACE_AMONT = {arrondi(surface(pts_amont))}
SOMMET_AMONT_M = {d_s:.1f}

# Téléphérique de la Grande Motte (Von Roll 1975, bicâble va-et-vient
# 115 + 1 places) : distances horizontales depuis le bout de la voie du
# funiculaire le long de la coupe ; hauteur du pylône et paramètre de
# chaînette a = T/w des porteurs DÉDUITS (audit_physique/telepherique.sage :
# survol maximal 152 m et pente maximale 55 % de la fiche technique).
TPH_X_AVAL = {TPH_X["aval"]:.1f}
TPH_X_PYLONE = {TPH_X["pylone"]:.1f}
TPH_X_AMONT = {TPH_X["amont"]:.1f}
TPH_Z_GARE_AVAL = 3034.0
TPH_Z_GARE_AMONT = 3456.0
TPH_Z_SELLE_AVAL = {TPH_CALC["z_selle_aval"]}
TPH_Z_SELLE_AMONT = {TPH_CALC["z_selle_amont"]}
TPH_H_PYLONE = {TPH_CALC["h_pylone"]}
TPH_A_CHAINETTE = {TPH_CALC["a"]}

# Crêtes de fond à l'est, un point sur quatre de la suite
# aval + ligne + amont ci-dessus.
CRETES_MOYENNES = {arrondi(mi)}
CRETES_LOINTAINES = {arrondi(loin)}
'''
open("profil_coupe.py", "w").write(sortie)
print("ligne %d pts, aval %d, amont %d (sommet à %.0f m), crêtes %d"
      % (len(pts_ligne), len(pts_aval), len(pts_amont), d_s, len(mi)))
print("terrain en gare aval %.0f m, en gare amont %.0f m, sommet %.0f m"
      % (surface(pts_ligne[:1])[0], surface(pts_ligne[-1:])[0], max(surface(pts_amont))))
