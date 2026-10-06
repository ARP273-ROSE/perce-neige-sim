# Le câble entre les galets et le culot (v1.15.59, 06/10/2026).
# Retour de Kevin : « le câble semble collé au sommet des galets et s'en
# décolle au dernier moment ; il vaudrait mieux respecter la courbure en
# cosh, qu'il se décolle du galet un peu avant l'attache et sans angle ».
#
# Le culot est h = 0,12 m au-dessus de la ligne des galets (au-dessus de
# leurs joues). Sous la tension T, le câble de poids linéique w (composante
# perpendiculaire à la pente, w·cos α) suit une chaînette de paramètre
# a = T / (w cos α). Posé sur les galets, il les quitte TANGENTIELLEMENT au
# sommet de la chaînette (pente nulle par rapport à la ligne des galets),
# puis monte jusqu'au culot :
#     y(x) = a (cosh((x0 − x)/a) − 1),   y(0) = h  →  x0 = a·acosh(1 + h/a)
# (x : distance depuis le culot vers l'amont, y : hauteur au-dessus de la
# ligne des galets).
g = 9.80665
w_lin = 11.0 * g                  # N/m (PNConstants.CABLE_KG_M)
h = 0.12
for T_dan in [13000, 14000, 17000, 22500, 28000]:
    for pente_pct in [8.3, 29.5]:
        alpha = atan(pente_pct / 100)
        a = T_dan * 10 / (w_lin * cos(alpha))
        x0 = a * arccosh(1 + h / a)
        pente_culot = sinh(x0 / a)
        print("T = %5d daN, pente %4.1f %% : a = %6.0f m, décollage à x0 = %5.2f m, "
              "angle au culot %.2f°" % (T_dan, pente_pct, a.n(), x0.n(), (atan(pente_culot) * 180 / pi).n()))
# hauteur au-dessus d'un galet rencontré à 7 m et 14 m du culot (T nominale)
a = 22500 * 10 / (w_lin * cos(atan(0.29)))
x0 = a * arccosh(1 + h / a)
for x in [3, 7, 10, 14]:
    if x < x0:
        print("à %2d m du culot : câble %.1f cm au-dessus du galet" % (x, (100 * a * (cosh((x0 - x) / a) - 1)).n()))
# approximation parabolique utilisée : x0 ≈ sqrt(2 a h)
print("écart x0 exact / sqrt(2ah) : %.2e" % (abs(x0 - sqrt(2 * a * h)) / x0).n())
