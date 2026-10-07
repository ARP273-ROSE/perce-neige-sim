# Sortie de secours du tunnel : débouché sur la piste donné par Kevin
# (Google Earth, 07/10/2026) : 45°26'04,26" N, 6°54'02,60" E, 2 655,89 m,
# entre les pistes Double M et Face. Chambre de la sortie dans le tunnel :
# s = 2 150,56 (galet 145, vidéo de montée), repère relevé par la sonde Godot.
#
#   docker exec sagemath sage /home/sage/work/pn/sortie_secours.sage
from sage.all import *
RR30 = RealField(100)
# repère du jeu (tools_relief3d.py) : x vers l'est, z vers le sud
LAT_O = RR30('45.45188591'); LON_O = RR30('6.89898136')
M_LAT = RR30(111320)
M_LON = M_LAT * cos(LAT_O * pi / 180)
lat = RR30(45) + RR30(26) / 60 + RR30('4.26') / 3600
lon = RR30(6) + RR30(54) / 60 + RR30('2.60') / 3600
alt = RR30('2655.89')
x = (lon - LON_O) * M_LON
z = -(lat - LAT_O) * M_LAT
print("Débouché : lat %.7f lon %.7f → x = %.2f m, z = %.2f m, y = %.2f m" % (lat, lon, x, z, alt))
# chambre (sonde Godot, transform_at(2150.56)) : origine et base
o = vector(RR30, [146.5893, 2662.466, 2047.36])
bx = vector(RR30, [-0.937377, 0.0, -0.348317])        # droite (sens montée)
bz = vector(RR30, [0.333556, -0.288029, -0.897652])    # −avant
av = -bz
p = vector(RR30, [x, alt, z])
d = p - o
lat_m = d.dot_product(bx)            # vers la droite du tunnel
along = d.dot_product(vector(RR30, [av[0], 0, av[2]]).normalized())
print("Depuis la chambre : %.1f m à droite, %.1f m le long du tunnel (− = vers le bas), %.1f m plus bas" % (lat_m, along, d[1]))
print("Distance en plan : %.1f m ; angle avec l'axe du tunnel : %.1f°" % (
    sqrt(d[0]**2 + d[2]**2), atan2(lat_m, abs(along)) * 180 / pi))
# galerie en deux tronçons : 8 m perpendiculaire à droite depuis le point de
# la paroi (rayon 1,95 m), puis droit vers le débouché
r = RR30('1.95')
p1 = o + bx * (r + 8)
p1 = vector(RR30, [p1[0], o[1] - RR30('1.4'), p1[2]])     # sol de la galerie 1,4 m sous l'axe
sol_portail = p
l2 = sqrt((p[0] - p1[0])**2 + (p[2] - p1[2])**2)
print("Tronçon 2 : %.1f m en plan, pente %.1f %% (%.2f m de descente), cap %.1f°" % (
    l2, (p[1] - p1[1]) / l2 * 100, p[1] - p1[1], atan2(p[0] - p1[0], -(p[2] - p1[2])) * 180 / pi))
print("Pour main.gd / sortie_secours.gd : PORTAIL = Vector3(%.2f, %.2f, %.2f)" % (x, alt, z))
