# Décollage du câble au premier galet, jeu dans la gorge, poulie de
# déviation (v1.15.61, 06/10/2026). Retour d'un utilisateur : « au point de contact
# avec le galet le câble semble s'interrompre, et le décollement est
# toujours brusque avec un angle ».
#
# Notations : culot à h = 0,12 m au-dessus de la ligne des galets, galets
# espacés de L, premier galet touché (R1) à D du culot, chaînette de
# paramètre a = T / (w cos α), T = 140 kN + w·Δz (track_builder.a_chainette).
R = RealField(60)
g = R(9.80665)
w = 11 * g                         # N/m (PNConstants.CABLE_KG_M)
h = R(0.12)

print("== 1. Tension : la même pour le tronçon libre et les portées ==")
for (nom, dz, pente) in [("bas (s = 50)", 4.4, 0.0950), ("s = 1000", 222.7, 0.2950),
                         ("haut (s = 3400)", 914.2, 0.1400)]:
    T = 140000 + w * R(dz)
    a = T / (w * cos(atan(R(pente))))
    print("  %-16s T = %6.1f kN, a = %6.1f m" % (nom, T / 1000, a))
print("  (avec la tension de la jauge pour le tronçon libre et T(Δz) pour les")
print("   portées, le câble pliait vers le haut sur certains premiers galets)")

print()
print("== 2. Coude sur un galet ordinaire : 2·sinh(L/2a) ≈ L/a ==")
for a in [1308, 1585, 2233]:
    for L in [14.5, 15.1]:
        # pente en arrivant +sinh(L/2a), en repartant −sinh(L/2a)
        k = 2 * atan(sinh(R(L) / (2 * a)))
        print("  a = %4d m, L = %4.1f m : %.3f°" % (a, L, (k * 180 / pi)))

print()
print("== 3. Premier galet : critère de hauteur ⇔ coude vers le bas ==")
# Tronçon libre : chaînette de (0, h) à (D, 0) ; portée suivante : flèche
# vers (D + L, 0). Coude en R1 (sortante − entrante) et hauteur de la
# chaînette (0, h) → (D + L, 0) au droit de R1, approximation parabolique :
var('D L a x')
y_in = h * (1 - x / D) - x * (D - x) / (2 * a)          # sous la corde de la flèche
pente_in = diff(y_in, x).subs(x=D)
pente_out = -L / (2 * a)
coude = (pente_out - pente_in).simplify_full()
y_long = h * (1 - x / (D + L)) - x * (D + L - x) / (2 * a)
haut = y_long.subs(x=D).simplify_full()
h_q = QQ(12) / 100
coude_q = -(D^2 + D*L - 2*a*h_q) / (2*D*a)
haut_q = -L * (D^2 + D*L - 2*a*h_q) / (2*(D + L)*a)
assert bool((coude_q - (pente_out - diff(h_q * (1 - x / D) - x * (D - x) / (2 * a), x).subs(x=D))).simplify_full() == 0)
assert bool((haut_q - (h_q * (1 - x / (D + L)) - x * (D + L - x) / (2 * a)).subs(x=D)).simplify_full() == 0)
print("  coude(R1)           = −(D² + D·L − 2ah) / (2·D·a)")
print("  hauteur au droit R1 = −L·(D² + D·L − 2ah) / (2·(D + L)·a)")
print("  hauteur / coude     =", (haut_q / coude_q).simplify_full(), " (> 0 : mêmes signes)")
print("  ⇒ coude ≤ 0 (le galet porte) ⇔ la chaînette plus longue passe sous R1 ;")
print("    au changement de R1 les deux s'annulent : le câble quitte le galet")
print("    tangentiellement, à 0 mm, sans angle.")
# vérification en cosh exact
def chy(xx, DD, hh, aa):
    sh = sinh(DD / (2 * aa))
    xm = DD / 2 + aa * asinh(hh / (2 * aa * sh))
    return aa * (cosh((xx - xm) / aa) - cosh(xm / aa)) + hh
aa = R(1585); LL = R(15.1)
Dc = find_root(lambda DD: chy(DD, DD + LL, h, aa), 2, 40)
pin = (chy(Dc, Dc, h, aa) - chy(Dc - 1e-6, Dc, h, aa)) / 1e-6
pout = -sinh(LL / (2 * aa))
print("  cosh exact, a = 1585 m, L = 15,1 m : D critique = %.3f m, coude = %.2e °" % (Dc, (pout - pin) * 180 / pi))
print("  (ancien critère D(D + L) ≥ 2ah : D = %.3f m)" % ((-LL + sqrt(LL^2 + 8 * aa * h)) / 2))

print()
print("== 4. Jeu latéral dans la gorge du galet (RollerMesh) ==")
R_JOUE = R(0.32); R_BANDE = R(0.25); LARG = R(0.20); BANDE = R(0.10)
EP = R(0.006); HG = R(0.032); rc = R(0.026)
k = (R_JOUE - R_BANDE - EP) / ((LARG - BANDE) / 2)
var('hh')
flanc = BANDE / 2 + (rc + hh - EP - rc * sqrt(1 + k^2)) / k
fond = HG * sqrt(hh / EP)
print("  pente du flanc k = %.3f ; flanc : e(h) = %.4f + %.4f·h" % (k, flanc.subs(hh=0), diff(flanc, hh)))
hx = find_root(flanc - fond, 1e-4, 0.02)
print("  fond de gorge e = 3,2 cm·√(h/6 mm) ; il rejoint le flanc à h = %.2f mm" % (1000 * hx))
for hv in [0, 0.0005, 0.002, 0.006, 0.02, 0.05, 0.07]:
    print("    h = %5.1f mm : jeu = %5.1f mm" % (1000 * hv, 1000 * min(flanc.subs(hh=hv), fond.subs(hh=hv))))
print("  lèvres à h = R_JOUE − R_BANDE = %.0f mm : au-delà le câble passe par-dessus" % (1000 * (R_JOUE - R_BANDE)))

print()
print("== 5. Poulie de déviation (inclinée de β = 30°) : chanfrein de la jante ==")
# coupe : a = n·Δ = cos β·L − sin β·h (vers la poulie), b = sin β·L + cos β·h
# (le long de son axe) ; contrainte a ≤ c·(b − t/2). Bord : L(h), pente :
var('c L0 h0 t')
beta = pi / 6
bord = solve(cos(beta) * L0 - sin(beta) * h0 == c * (sin(beta) * L0 + cos(beta) * h0 - t / 2), L0)[0].rhs()
dLdh = diff(bord, h0).simplify_full()
print("  dL/dh =", dLdh)
print("  unicité de la position (contrainte monotone en L) : c < cotan β = %.3f" % (cot(beta)))
for cv in [0, 0.5, 1.0, 1.5]:
    print("    c = %.1f : %5.2f cm d'écart latéral par cm de levée" % (cv, dLdh.subs(c=cv)))
print("  retenu c = 0,5 (arête vive : saut de 3,6 cm mesuré au banc)")
