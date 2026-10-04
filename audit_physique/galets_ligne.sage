# Galets de ligne du Perce-Neige : dimensions, vitesse de rotation,
# ralentissement une fois le câble parti (v1.15.56, 05/10/2026).
#
# 1) Dimensions relevées sur la photo du reportage remontees-mecaniques.net
#    « Un galet ainsi que le câble » (© 2015 Olivier Lakatos) : un galet
#    posé à plat, un culot et un bout de câble de 52 mm, même plan.
#    Mesures en pixels (image 900 × 675), à mi-profondeur du galet.
d_cable = 52.0                     # mm
px_cable_corps = 39.0              # largeur du câble, perpendiculaire à son axe
px_cable_bout = 50.0               # section coupée, au premier plan
k_prof = 1.15                      # premier plan ≈ 15 % plus près que le milieu du galet
e1 = d_cable / px_cable_corps      # mm/px
e2 = d_cable / px_cable_bout * k_prof
ech = (e1 + e2) / 2
print("échelle : %.3f et %.3f mm/px → %.3f mm/px" % (e1, e2, ech))
px = dict(joue=516.0, bande=404.0, joues_axe=173.0, bande_axe=88.0)
cos_vue = cos(asin(0.26))          # ellipse des joues : petit/grand axe = 0,26
mm = dict(joue=px['joue']*ech, bande=px['bande']*ech,
          largeur=px['joues_axe']*ech/cos_vue, bande_l=px['bande_axe']*ech/cos_vue)
for k, v in mm.items():
    print("  %-8s %6.0f mm" % (k, v))
# culot (contrôle) : base 102 px, hauteur 205 px → ≈ 2,4·d et 4,8·d
print("culot : base %.0f mm (%.1f d), hauteur %.0f mm (%.1f d)" % (
    102*ech, 102*ech/d_cable, 205*ech, 205*ech/d_cable))

# Retenu (arrondi, échelle ±10 %) : joues Ø 640, bande de roulement
# Ø 500, bande de 100 mm. De joue à joue : 200 mm au lieu des 227 mesurés,
# car les deux galets d'une paire sont à 240 mm d'axe en axe (brins du
# câble) et doivent pouvoir s'incliner de 32° en courbe sans se toucher :
# 240·cos 32° = 204 mm.
R_joue, r_bande, largeur = 0.32, 0.25, 0.20
print("inclinaison maxi d'une paire sans contact : %.1f°" % (acos(largeur/0.24)*180/pi).n())
r_c = r_bande + 0.026              # rayon au centre du câble
for v in [1, 6, 10.1, 12]:
    w = v / r_bande                # le câble roule sur la bande
    print("câble %5.1f m/s → ω = %5.1f rad/s = %4.0f tr/min" % (v, w, w*60/(2*pi)))

# 2) Inertie : ~20 kg (forum remontees-mecaniques.net)
m_joues, m_bande, m_moyeu = 9.0, 5.0, 6.0
I = (m_joues*(0.20^2 + R_joue^2)/2 + m_bande*(0.20^2 + r_bande^2)/2
     + m_moyeu*(0.04^2 + 0.20^2)/2 * 0.35)
print("I ≈ %.3f kg·m²" % I)

# 3) Couple résistant sans câble (2 roulements 6208-2RS1, modèle SKF) :
#    joints : M = K_S1·d_s^β + K_S2 par roulement (K_S1 0,028 ; β 2,25 ;
#    K_S2 2 ; d_s 49,8 mm) ; roulement : G_rr·(ν n)^0,6 (graisse froide
#    ν ≈ 300 mm²/s) ; air : ½·C_M·ρ·ω²·R⁵ (ρ 0,9 kg/m³ à 3 000 m).
M_joints = 2 * (0.028 * 49.8^2.25 + 2) / 1000          # N·m
F_r = m_joues + m_bande + m_moyeu                        # kg → 2 roulements
G_rr = 4.4e-7 * 60^1.96 * (F_r*9.81/2)^0.54
M_joints, G_rr, I = RDF(M_joints), RDF(G_rr), RDF(I)
def M_tot(w):
    w = RDF(w)
    n = w*60/(2*RDF(pi))
    Re = max(w*RDF(R_joue)^2/1.6e-5, RDF(1))
    C_M = 3.87/Re.sqrt()
    return M_joints + 2*G_rr*(300*n)^0.6/1000 + 0.5*C_M*0.9*w^2*RDF(R_joue)^5
w0 = RDF(12/r_bande)
print("couple : joints %.3f N·m ; total à %.0f rad/s : %.3f N·m" % (M_joints, w0, M_tot(w0)))

# 4) Ralentissement : I·ω' = −M(ω), intégré, puis ajusté sur la loi
#    M ≈ M_c + c·ω (forme fermée utilisée par le simulateur)
dt = RDF(0.01); w = w0; t = RDF(0); courbe = []
while w > 0:
    courbe.append((t, w)); w -= M_tot(w)/I*dt; t += dt
t_arret = t
print("arrêt complet en %.0f s depuis %.0f rad/s" % (t_arret, w0))
var('Mc c')
pts = [(float(ww), float(M_tot(ww))) for ww in srange(0.5, float(w0), 0.5)]
fit = find_fit(pts, Mc + c*x, parameters=[Mc, c], variables=[x], solution_dict=True)
Mc_f, c_f = fit[Mc], fit[c]
tau = I/RDF(c_f); a = RDF(Mc_f)/RDF(c_f)
t_ferme = tau*log((w0 + a)/a)
print("ajustement : M_c = %.4f N·m, c = %.6f N·m·s → τ = %.0f s, a = %.2f rad/s" % (Mc_f, c_f, tau, a))
print("arrêt (forme fermée) en %.0f s — écart %.1f %%" % (t_ferme, 100*abs(t_ferme - t_arret)/t_arret))
for tt in [5, 15, 30, 60]:
    print("  t = %3d s : ω = %5.1f rad/s (%3.0f tr/min)" % (tt, max((w0+a)*exp(-tt/tau) - a, 0),
          max((w0+a)*exp(-tt/tau) - a, 0)*60/(2*pi)))
