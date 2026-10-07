# Pente de construction des paliers et des bancs des voitures (07/10/2026).
# Fait de Kevin : « les bancs sont horizontaux lorsque la pente du wagon est
# celle des gares ». Pentes des voitures rame arrêtée (sonde Godot, axe de
# chaque voiture, rame à START_S puis STOP_S) :
#   gare basse : voiture 1  9,24 %, voiture 2  8,68 %
#   gare haute : voiture 1  7,29 %, voiture 2  9,06 %
#   pleine ligne (s = 1500) : 30,07 %
#     docker exec sagemath sage /home/sage/work/pn/pente_paliers.sage
gares = [9.24, 8.68, 7.29, 9.06]
g = sum(QQ(p) / 100 for p in gares) / len(gares)
print("pente retenue (moyenne des 4 voitures en gare) : %.4f = %.2f %%" % (g, 100 * g))
deg = lambda x: float(atan(x) * 180 / pi)
for p in gares:
    print("  voiture à %.2f %% : palier incliné de %+.2f°" % (p, deg(p / 100) - deg(g)))
print("en pleine ligne (30,07 %%) : palier incliné de %+.2f° (avant plus haut)" % (deg(0.3007) - deg(g)))
pas = 1.30 + 0.10
print("contremarche (pas %.2f m) : %.3f m ; relèvement STEP_LIFT : %.3f m" % (pas, pas * g, pas * g / 2))
print("ancienne pente 26,5 %% : bancs inclinés de %+.2f° en gare (arrière plus haut)" % (deg(g) - deg(0.265)))
