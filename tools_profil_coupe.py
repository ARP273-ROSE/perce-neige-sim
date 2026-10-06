"""Coupe du terrain le long du funiculaire pour la vue profil du programme PC
(perce_neige_sim.py, « vue en coupe ») — relief RÉEL, régénérable :
    python3 tools_profil_coupe.py  →  profil_coupe.py

Demande de Kevin du 06/10/2026 : refonte complète de la vue profil (« dans
cette vue-là on peut redesigner complètement les rames et le reste »).
Les montagnes de l'ancienne vue étaient des sinusoïdes et le dessus du
relief une ligne à 160 m au-dessus de la voie.

- Terrain au-dessus de la ligne : le tracé IGN BD TOPO
  (audit_physique/trace_ign_osm.json), échantillonné à fraction égale de sa
  longueur horizontale, le programme le cale sur sa propre longueur
  horizontale (H_MAX).
- En deçà de la gare aval : 1 200 m dans le prolongement du premier tronçon
  (vers le lac de Tignes).
- Au-delà de la gare amont : la montée du glacier jusqu'au sommet de la
  Grande Motte (3 653 m), puis 600 m de redescente.
- Crêtes de fond : la vue regarde vers l'EST (l'amont, au sud, est à
  droite) ; pour chaque point de la coupe, l'altitude maximale du terrain
  dans une bande perpendiculaire à l'est, de 0,8 à 4 km (crêtes moyennes)
  et de 4 à 18 km (lointaines), courbure terrestre comprise.
Relief : tools_mnt.py (Terrain Tiles : SRTM, EU-DEM, GMTED).
"""
import json
import math

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
e_s = (SOMMET[1] - ign[0][0]) * m_lon(lat0)
n_s = (SOMMET[0] - lat0) * M_LAT
cap_s = math.degrees(math.atan2(e_s - E[-1], n_s - N[-1]))
d_s = math.hypot(e_s - E[-1], n_s - N[-1])
pts_amont = []
for j in range(1, int((d_s + APRES_SOMMET_M) / PAS) + 1):
    d = j * PAS
    pts_amont.append((E[-1] + d * math.sin(math.radians(cap_s)), N[-1] + d * math.cos(math.radians(cap_s)), cap_s))


def surface(pts):
    la, lo = vers_latlon(np.array([p[0] for p in pts]), np.array([p[1] for p in pts]))
    return altitude(la, lo, 14)


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
(relief réel : Terrain Tiles SRTM / EU-DEM / GMTED ; tracé IGN BD TOPO).
Ne pas éditer à la main : relancer l'outil."""

# Terrain au-dessus de la ligne, à fraction égale f = i / N_LIGNE de la
# longueur horizontale de la ligne (le programme la cale sur H_MAX).
N_LIGNE = {N_LIGNE}
SURFACE_LIGNE = {arrondi(surface(pts_ligne))}

# En deçà de la gare aval, tous les {PAS:.0f} m (le premier est le plus loin).
PAS_PROLONGEMENT = {PAS}
SURFACE_AVAL = {arrondi(surface(pts_aval))}

# Au-delà de la gare amont, tous les {PAS:.0f} m, vers le sommet de la Grande
# Motte (à {d_s:.0f} m) puis {APRES_SOMMET_M:.0f} m au-delà.
SURFACE_AMONT = {arrondi(surface(pts_amont))}
SOMMET_AMONT_M = {d_s:.1f}

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
