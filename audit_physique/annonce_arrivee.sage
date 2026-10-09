# Quand déclencher l'annonce d'arrivée en gare haute (fichier 11, « Le
# funiculaire vous emmène en zone Grande Motte ») pour qu'elle se termine
# AVANT l'arrêt — retour d'un utilisateur du 06/10/2026 : « comme le quai est plus
# court, l'annonce d'arrivée en haut se déclenche trop tard et est coupée
# par l'arrêt en haut, mets-la plus tôt, calcule quand c'est bon ».
#
# Elle partait au début du rampement (|v| < 1 m/s). Depuis la v1.15.67 le
# rampement ne commence qu'au galet 238, à 35,03 m de l'arrêt (55 m avant) :
# il ne reste plus assez de temps pour ses 54,24 s.
#
# Profil d'approche du régulateur (train_physics.gd / perce_neige_sim.py),
# d = distance restante jusqu'à l'arrêt (position du centre de la rame) :
#   d > D_C   : enveloppe v = √(V_C² + 2·a·(d − D_C)), a = 0,25 (montée en
#               roue libre) ou 0,30 m/s² (gravité motrice)
#   D_P < d ≤ D_C : rampement à V_C = 0,75 m/s
#   d ≤ D_P   : accostage v = √(2·0,15·d), qui passe sous V_C à D_P = V_C²/0,3
#
#   docker exec sagemath sage /home/sage/work/pn/annonce_arrivee.sage
V_C = 0.75
D_C = 35.03          # CREEP_DIST : rampement dès le galet 238
A_PARK = 0.15
D_P = V_C^2 / (2 * A_PARK)
DUREE = 54.238250    # ffprobe du fichier 11
MARGE = 3.0          # s : l'annonce finit avant l'arrêt, même si la rame
                     # suit l'enveloppe un peu au-dessus

d, x, t = var('d x t')
t_accostage = integrate(1 / sqrt(2 * A_PARK * d), d, 0, D_P)
t_rampement = (D_C - D_P) / V_C
print("accostage final : %.2f s sur %.3f m" % (t_accostage, D_P))
print("rampement : %.2f s sur %.2f m" % (t_rampement, D_C - D_P))
print("du galet 238 à l'arrêt : %.2f s (annonce %.2f s : il manque %.2f s)"
      % (t_accostage + t_rampement, DUREE, DUREE - t_accostage - t_rampement))


def t_arret(dd, a):
    """temps jusqu'à l'arrêt depuis la distance dd, en suivant le profil"""
    if dd <= D_P:
        return float(2 * sqrt(dd / (2 * A_PARK)))
    if dd <= D_C:
        return float(t_accostage + (dd - D_P) / V_C)
    xx = dd - D_C
    return float(t_accostage + t_rampement + (sqrt(V_C^2 + 2 * a * xx) - V_C) / a)


print()
for a in (0.25, 0.30):
    besoin = DUREE + MARGE - t_accostage - t_rampement
    # temps passé dans l'enveloppe sur x mètres = (√(V_C²+2ax) − V_C)/a
    x_sol = (V_C + a * besoin)^2 / (2 * a) - V_C^2 / (2 * a)
    d_sol = D_C + x_sol
    print("a = %.2f m/s² : déclencher à %.1f m de l'arrêt (vitesse d'enveloppe %.2f m/s) ; "
          "temps jusqu'à l'arrêt %.2f s" % (a, d_sol, sqrt(V_C^2 + 2 * a * x_sol), t_arret(d_sol, a)))

D_ANNONCE = 51.0
print()
print("Retenu : déclenchement à %.0f m de l'arrêt, quelle que soit la vitesse" % D_ANNONCE)
for a in (0.25, 0.30):
    print("  a = %.2f : %.2f s avant l'arrêt, l'annonce finit %.2f s avant"
          % (a, t_arret(D_ANNONCE, a), t_arret(D_ANNONCE, a) - DUREE))
