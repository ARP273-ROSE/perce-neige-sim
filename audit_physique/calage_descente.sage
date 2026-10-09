# Calage du simulateur sur la vidéo de DESCENTE en cabine (06/10/2026) —
# demande d'un utilisateur : « la descente est effectuée à 12 m/s donc tu peux
# calibrer des trucs […] accélérations, espacement […] en fonction de la
# position ».
#
# Données (tools_calage_descente.py ; écran du pupitre lu à l'œil) :
#   * instants de passage des néons au-dessus de la cabine ;
#   * écran « CONDUITE VÉHICULE 1 » (Pro-face, 02/09/2013) : VITESSE
#     VÉHICULE et DISTANCE (position depuis le bas, décroissante en descente).
#
#   docker exec sagemath sage /home/sage/work/pn/calage_descente.sage
import numpy as np

# --- relevés ---------------------------------------------------------------
NEONS_DEPART = [42.57, 45.87, 48.83, 51.37, 53.77, 55.93, 58.03, 59.97, 61.83, 63.53]
NEONS_CROISIERE = [  # trois tronçons où la caméra est stable
    [120.73, 122.37, 124.00, 125.63, 127.27, 128.90, 130.53, 132.20, 133.87, 135.47,
     137.10, 138.73, 140.37, 142.00, 143.63, 145.23, 146.90, 148.57, 150.13, 151.80, 153.43],
    [177.70, 179.33, 180.93, 182.57, 184.20, 185.83, 187.47, 189.10, 190.73],
    [215.17, 216.80, 218.43, 220.07, 221.70, 223.37, 225.00, 226.63, 228.30, 229.93,
     231.57, 233.20, 234.83, 236.47, 238.13, 239.80, 241.43, 243.03, 244.63, 246.30,
     247.93, 249.60, 251.23, 252.83, 254.50, 256.07, 257.73, 259.43, 261.03]]
ECRAN_CROISIERE = [(95, 12.21, 2977), (96, 12.16, 2965)]        # (t s, v m/s, distance m)
ECRAN_HAUT = [(92, 3013), (93, 3002), (94, 2989), (95, 2977), (96, 2965)]
ECRAN_BAS = [(344, 1.56, 42), (345, 0.90, 41), (346, 0.27, 41), (347, 0.18, 40), (348, 0.11, 41),
             (349, 0.88, 40), (350, 0.94, 40), (351, 1.23, 39), (352, 1.24, 37), (353, 0.84, 36),
             (354, 0.29, 36), (355, 0.05, 35), (357, 0.49, 35), (358, 0.97, 34), (359, 1.14, 33),
             (360, 1.03, 32), (361, 0.70, 31), (362, 0.32, 31), (363, 0.17, 30), (364, 0.29, 30),
             (371, 0.26, 25)]
PORTAIL_HAUT = (39.4, 41.0)    # la cabine entre dans le tube rond (images 39,0 → 41,0 s)
CABINE_DEPART = 3496.56 - 16.0 # nez aval de la rame à l'arrêt en haut (STOP_S − TRAIN_HALF)

# --- 1. croisière : vitesse et espacement des néons --------------------------
dts = np.concatenate([np.diff(seg) for seg in NEONS_CROISIERE])
T_c = float(np.median(dts))
v_c = float(np.mean([e[1] for e in ECRAN_CROISIERE]))
# vitesse aussi tirée de la distance affichée (régression)
t_e = np.array([e[0] for e in ECRAN_HAUT]); d_e = np.array([e[1] for e in ECRAN_HAUT])
v_dist = -float(np.polyfit(t_e, d_e, 1)[0])
print("Croisière : un néon toutes les %.3f s (écart-type %.3f s sur %d intervalles)"
      % (T_c, float(np.std(dts)), len(dts)))
print("  vitesse affichée %.2f m/s ; vitesse tirée de la distance affichée %.2f m/s" % (v_c, v_dist))
pas_neon = v_c * T_c
print("  → néons ALLUMÉS tous les %.1f m (%.1f m à 12,0 m/s)" % (pas_neon, 12.0 * T_c))

# --- 2. départ : accélération ------------------------------------------------
t_mil = [(a + b) / 2 for a, b in zip(NEONS_DEPART, NEONS_DEPART[1:])]
v_dep = [pas_neon / (b - a) for a, b in zip(NEONS_DEPART, NEONS_DEPART[1:])]
pente, orig = np.polyfit(t_mil, v_dep, 1)
acc = float(pente)
t0 = float(-orig / pente)
print()
print("Départ : v(t) régression sur %d points → accélération %.3f m/s², départ à t0 = %.1f s"
      % (len(v_dep), acc, t0))
for tm, vv in zip(t_mil, v_dep):
    print("    t = %5.1f s  v = %5.2f m/s  (modèle %5.2f)" % (tm, vv, acc * (tm - t0)))
T_acc = v_c / acc
print("  pleine vitesse atteinte à t = %.1f s, après %.0f m" % (t0 + T_acc, v_c ** 2 / (2 * acc)))
# contrôle avec l'écran à 92 s : distance depuis le départ
d92 = v_c ** 2 / (2 * acc) + v_c * (92 - t0 - T_acc)
print("  contrôle : à 92 s la rame a parcouru %.0f m → distance affichée attendue %.0f (lue 3 013)"
      % (d92, 3498 - d92))

# --- 3. section carrée du haut ------------------------------------------------
print()
for tp in PORTAIL_HAUT:
    dd = 0.5 * acc * (tp - t0) ** 2
    print("Portail haut (tube rond) franchi à %.1f s → %.1f m sous le départ du nez → s = %.0f"
          % (tp, dd, CABINE_DEPART - dd))
s_portail = CABINE_DEPART - 0.5 * acc * ((sum(PORTAIL_HAUT) / 2) - t0) ** 2
print("  retenu : tube rond → caisson carré à s ≈ %.0f m (SQUARE_SECTION_HIGH_START)" % s_portail)

# --- 4. approche en gare basse ------------------------------------------------
tb = np.array([e[0] for e in ECRAN_BAS if e[0] <= 364]); db = np.array([e[2] for e in ECRAN_BAS if e[0] <= 364])
vb = np.array([e[1] for e in ECRAN_BAS if e[0] <= 364])
v_moy = -float(np.polyfit(tb, db, 1)[0])
print()
print("Approche basse (écran) : la position passe de %d à %d m en %d s → vitesse moyenne %.2f m/s"
      % (db[0], db[-1], tb[-1] - tb[0], v_moy))
pics = [344, 351.5, 359, 365.5]
print("  vitesse VÉHICULE oscillante %.2f à %.2f m/s, maxima à %s s → période ≈ %.1f s"
      % (vb.min(), vb.max(), pics, float(np.mean(np.diff(pics)))))
print("  (rame au bout de ≈ 3,45 km de câble : oscillation élastique autour de la vitesse de la poulie)")
