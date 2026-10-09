# Rupture du câble tracteur — ce que montre la 3D (2026-10-01)
# ---------------------------------------------------------------------------
# Retour d'un utilisateur : « quand le câble casse, il doit se détendre, casser
# quelque part et la machinerie doit s'arrêter, là elle s'emballe ».
# Données du simulateur : EA = 1,25·10⁸ N (rebond élastique, TrainPhysics),
# 11 kg/m, ligne 3 474 m ; géométrie de track_builder (plancher −1,85,
# dalle 0,25, blochets 0,20, longrine 0,06, câble Ø 52 mm, galets Ø 300 mm
# tous les 13,57 m).
#
# Exécuter : sage audit_physique/rupture_cable.sage

from sage.all import *

EA = RDF(1.25e8)
RHO = RDF(11.0)
L = RDF(3474)
G = RDF(9.80665)
RC = RDF(0.026)
PAS = RDF(3474) / 256

print("=== Onde de détente le long du câble")
c = sqrt(EA / RHO)
print(f"  célérité longitudinale √(EA/ρ) = {float(c):.0f} m/s → toute la ligne en {float(L / c):.2f} s")
print("  → la détente est quasi instantanée à l'échelle de l'œil : le câble entier se relâche d'un coup")

print("\n=== Chute du câble sur la longrine")
y_axe = RDF(-1.85) + RDF(0.25) + RDF(0.20) + RDF(0.04)       # axe au sommet des galets
y_pose = RDF(-1.85) + RDF(0.25) - RDF(0.01) + RDF(0.06) + RC   # axe posé sur la longrine
h = y_axe - y_pose
t_chute = sqrt(2 * h / G)
print(f"  axe sur galets {float(y_axe):.3f} m, posé sur la longrine {float(y_pose):.3f} m → chute {float(h) * 100:.1f} cm")
print(f"  chute libre : {float(t_chute):.3f} s (RUPTURE_FALL_S = 0,18 s)")
print(f"  flèche d'un câble TENDU à 22 500 daN entre galets : {float(RHO * G * PAS**2 / (8 * 225000)) * 1000:.1f} mm (rien à voir)")

print("\n=== Rétraction des bouts (allongement élastique rendu)")
for T_dan in (5000, 15000, 22500, 28000):
    T = RDF(T_dan * 10)
    eps = T / EA
    print(f"  T = {T_dan:6d} daN : ε = {float(eps * 1000):.2f} ‰ → bout haut sur 2 000 m : {float(eps * 2000):.2f} m ; "
          f"bout bas sur 100 m : {float(eps * 100) * 100:.1f} cm")
print("  (le code borne à 8 m en haut et 2 m en bas ; tension mini retenue 5 000 daN)")
# durée : le bout libre est rappelé par la tension, vitesse de la particule u = ε·c
for T_dan in (15000, 22500):
    eps = RDF(T_dan * 10) / EA
    print(f"  vitesse de rappel du bout libre u = ε·c = {float(eps * c):.1f} m/s (T = {T_dan} daN)")
print("  → le bout recule à u = ε·c pendant L/c (temps de parcours de l'onde) : c'est ce que fait le rendu")

print("\n=== Arrêt de la machinerie")
A = RDF(2.0)
for v0 in (12.0, 14.4):
    v0 = RDF(v0)
    print(f"  à {float(v0):.1f} m/s, freinage de {float(A)} m/s² à la jante : arrêt en {float(v0 / A):.1f} s, "
          f"{float(v0**2 / (2 * A)):.0f} m de câble défilé, "
          f"{float(v0**2 / (2 * A) / (2 * pi * 2.08)):.1f} tours de roue")
print("  (14,4 m/s = +20 % de V_MAX : la rupture du mode Défi)")
