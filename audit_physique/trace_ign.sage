# Tracé en plan du simulateur confronté à l'IGN et à OpenStreetMap (06/10/2026)
#
# Demande de Kevin : « vérifie ton tracé avec OpenStreetMap de bas en haut
# sur toute la ligne ».
#
# Données (trace_ign_osm.json, extraites le 06/10/2026) :
#   * IGN BD TOPO V3 « troncon_de_voie_ferree », nature « Funiculaire ou
#     crémaillère », souterrain, saisi sur le Scan25, précision 10 m ;
#   * OpenStreetMap, way « Funiculaire Perce-Neige » (24 nœuds, dont un
#     premier tronçon rectiligne de 1 546 m : tracé grossier).
# Le simulateur décrit le plan par CURVE_PROFILE (cap en fonction de la
# distance le long de la pente s) et la pente par SLOPE_PROFILE
# (slope_profile.gd, identique côté PC). L'orientation absolue n'a aucun
# effet dans le jeu : on compare les FORMES, après la rotation d'ensemble
# qui superpose au mieux (départ commun en gare aval).
#
#   docker exec sagemath sage /home/sage/work/pn/trace_ign.sage
import json, re
import numpy as np
from scipy.optimize import minimize

D = json.load(open('/home/sage/work/pn/trace_ign_osm.json'))
src = open('/home/sage/work/pn/slope_profile.gd').read()


def table(nom):
    blk = src[src.index('const ' + nom):]
    blk = blk[:blk.index('\n]')]
    return [tuple(map(float, m)) for m in re.findall(r'\[\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\]', blk)]


PENTE = table('SLOPE_PROFILE')
# tracé du simulateur AVANT cette vérification (courbes chronométrées sur la
# vidéo à 10,1 m/s, angles estimés 20° + 28°)
CAP = [(0.0, 155.0), (1297.0, 155.0), (1420.0, 165.0), (1541.0, 175.0), (1924.52, 175.0),
       (2165.52, 189.0), (2409.52, 203.0), (3514.52, 203.0)]
LONGUEUR = PENTE[-1][0]
C45 = float(cos(45.44 * pi / 180))


def enu(lat, lon, lat0, lon0):
    return ((lon - lon0) * 111320 * C45, (lat - lat0) * 111320)


lat0, lon0 = D['ign_lon_lat_z'][0][1], D['ign_lon_lat_z'][0][0]
IGN = np.array([enu(p[1], p[0], lat0, lon0) for p in D['ign_lon_lat_z']])
OSM = np.array([enu(p[0], p[1], lat0, lon0) for p in D['osm_lat_lon']])

# notre pas d'intégration : 1 m de pente
S = np.arange(0.0, LONGUEUR, 1.0) + 0.5
Sp = np.array([p[0] for p in PENTE]); Gp = np.array([p[1] for p in PENTE])
COS = 1.0 / np.sqrt(1.0 + np.interp(S, Sp, Gp) ** 2)
HORIZ = np.concatenate([[0.0], np.cumsum(COS)])


def plan(cap_table):
    sc = np.array([c[0] for c in cap_table]); hc = np.array([c[1] for c in cap_table])
    b = np.radians(np.interp(S, sc, hc))
    e = np.concatenate([[0.0], np.cumsum(COS * np.sin(b))])
    n = np.concatenate([[0.0], np.cumsum(COS * np.cos(b))])
    return np.stack([e, n], 1)


def dist_polyligne(P, L):
    """distance de chaque point de P à la polyligne L"""
    a = L[:-1][None]; b = L[1:][None]; p = P[:, None]
    ab = b - a
    t = np.clip(((p - a) * ab).sum(-1) / (ab * ab).sum(-1), 0, 1)
    q = a + t[..., None] * ab
    return np.sqrt(((p - q) ** 2).sum(-1)).min(1)


def ecarts(cap_table, ref, rot=None):
    P = plan(cap_table)
    def tourne(r):
        c, s_ = np.cos(r), np.sin(r)
        return np.stack([P[:, 0] * c + P[:, 1] * s_, -P[:, 0] * s_ + P[:, 1] * c], 1)
    if rot is None:
        rot = minimize(lambda r: (dist_polyligne(tourne(r[0])[::10], ref) ** 2).mean(), [0.2],
                       method='Nelder-Mead').x[0]
    return dist_polyligne(tourne(rot), ref), rot


def resume(nom, cap_table):
    d, r = ecarts(cap_table, IGN)
    dO, _ = ecarts(cap_table, OSM, r)
    print("%-44s IGN : moyen %5.1f m, max %5.1f m (s = %4.0f) | OSM : moyen %5.1f m, max %5.1f m"
          % (nom, d.mean(), d.max(), np.argmax(d), dO.mean(), dO.max()))
    return d


print("Longueurs horizontales : simulateur %.0f m, IGN %.0f m, OSM %.0f m"
      % (HORIZ[-1], np.sum(np.hypot(*np.diff(IGN, axis=0).T)), np.sum(np.hypot(*np.diff(OSM, axis=0).T))))
print("Corde gare aval → gare amont : simulateur %.0f m, IGN %.0f m"
      % (np.hypot(*plan(CAP)[-1]), np.hypot(*IGN[-1])))
print()

# 1) le tracé actuel
d_actuel = resume("tracé d'avant (20° + 28°)", CAP)

# 2) positions des courbes RELEVÉES AU COMPTEUR par Kevin dans la vidéo
#    cabine (06/10/2026) : premier / dernier galet incliné de chaque courbe,
#    au passage du nez de la rame montante. Compteur 0 au départ (nez à
#    START_S + TRAIN_HALF = 38,56 m) → s = compteur + 38,56.
#      courbe 1 : galet 81 à 1 274 m → galet 98 à 1 510 m
#      courbe 2 : galet 126 à 1 857 m → galet 163 à 2 351 m
#    (anciennes positions, chronométrées sur la vidéo à 10,1 m/s :
#     1 297-1 541 et 1 924,52-2 409,52)
NEZ0 = 22.56 + 16.0
S1A, S1B = 1274.0 + NEZ0, 1510.0 + NEZ0
S2A, S2B = 1857.0 + NEZ0, 2351.0 + NEZ0


def table_angles(d1, d2, s1a=S1A, s1b=S1B, s2a=S2A, s2b=S2B):
    h0 = 155.0
    return [(0.0, h0), (s1a, h0), (s1b, h0 + d1), (s2a, h0 + d1), (s2b, h0 + d1 + d2), (LONGUEUR, h0 + d1 + d2)]


def obj_angles(x):
    return (ecarts(table_angles(*x), IGN)[0][::5] ** 2).mean()


fa = minimize(obj_angles, [20.0, 28.0], method='Nelder-Mead', options={'xatol': 0.05, 'fatol': 0.01})
d1, d2 = fa.x
d_angles = resume("positions Kevin, angles ajustés %.1f° + %.1f°" % (d1, d2), table_angles(d1, d2))
fv = minimize(lambda x: (ecarts(table_angles(x[0], x[1], 1297.0, 1541.0, 1924.52, 2409.52), IGN)[0][::5] ** 2).mean(),
              [16.5, 28.3], method='Nelder-Mead', options={'xatol': 0.05, 'fatol': 0.01})
resume("(positions chronométrées, angles ajustés %.1f° + %.1f°)" % tuple(fv.x),
       table_angles(fv.x[0], fv.x[1], 1297.0, 1541.0, 1924.52, 2409.52))

# 3) tout libre : où l'IGN met-il les courbes ?
def obj_libre(x):
    d1_, d2_, a1, b1, a2, b2 = x
    if not (0 < a1 < b1 < a2 < b2 < LONGUEUR - 50):
        return 1e9
    return (ecarts(table_angles(d1_, d2_, a1, b1, a2, b2), IGN)[0][::5] ** 2).mean()


fl = minimize(obj_libre, [d1, d2, S1A, S1B, S2A, S2B], method='Nelder-Mead',
              options={'xatol': 0.5, 'fatol': 0.01, 'maxiter': 4000})
L = fl.x
d_libre = resume("tout libre %.1f° [%.0f-%.0f] + %.1f° [%.0f-%.0f]" % (L[0], L[2], L[3], L[1], L[4], L[5]),
                 table_angles(*L))
print()
print("Profil des écarts à l'IGN (m), tous les 250 m de pente :")
print("   s      avant    angles ajustés   tout libre")
for s_ in range(0, int(LONGUEUR), 250):
    print("  %5d   %6.1f   %14.1f   %10.1f" % (s_, d_actuel[s_], d_angles[s_], d_libre[s_]))
print()
_, rot = ecarts(table_angles(d1, d2), IGN)
h0_reel = 155.0 + float(np.degrees(rot))
print("Rotation d'ensemble qui superpose le tracé ajusté à l'IGN : %+.1f° → caps géographiques : "
      "départ %.1f°, entre les courbes %.1f°, arrivée %.1f°" % (np.degrees(rot), h0_reel, h0_reel + d1, h0_reel + d1 + d2))
_, rot0 = ecarts(CAP, IGN)
print("(tracé d'avant : rotation %+.1f°)" % np.degrees(rot0))
print("Précision planimétrique annoncée par l'IGN : 10 m.")
print("Retenu : positions relevées par Kevin, courbe 1 [%.2f ; %.2f] = %.1f°, courbe 2 [%.2f ; %.2f] = %.1f°, total %.1f°"
      % (S1A, S1B, d1, S2A, S2B, d2, d1 + d2))
