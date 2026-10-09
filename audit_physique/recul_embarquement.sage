# Recul de la rame pleine pendant l'embarquement en gare basse — calage de
# la raideur du câble (v1.15.66, 06/10/2026). Fait d'un utilisateur (témoin, « je
# suis sûr du mètre ») : la rame pleine recule d'AU MOINS 1 m en gare basse.
# Aucune donnée constructeur (Fatzer ne publie pas le module de ses câbles
# à torons) : EA est donc la raideur EFFECTIVE de toute la chaîne (câble,
# tassement, poulies, machinerie), calée sur cette observation.
R = RealField(60)
g = R(9.80665)
LENGTH, START_S, STOP_S = R(3514.52), R(22.56), R(3496.56)
PAX_KG, PAX_MAX, TRAIN_EMPTY_KG = R(75), 334, R(32300)
ZETA, GRAB_A, SEUIL = R(0.15), R(0.35), R(0.02)
# pente du quai bas pour la physique (interpolation linéaire 0,08 → 0,12
# entre 0 et 120 m, SlopeProfile.gradient_phys_at)
pente = R(0.08) + R(0.04) * START_S / 120
L_bas = LENGTH - START_S
dT = PAX_MAX * PAX_KG * g * sin(atan(pente))
print("pente au quai bas %.4f, câble de la rame en bas %.2f m, surtension rame pleine %.2f kN"
      % (pente, L_bas, dT / 1000))
for EA in [R(1.25e8), R(7.5e7), R(7.0e7)]:
    print("  EA = %.3g N : recul de la rame pleine %.3f m" % (EA, dT * L_bas / EA))
EA_1m = dT * L_bas
print("  EA pour 1,000 m exactement : %.4g N" % EA_1m)
EA = R(7.0e7)
print("retenu : EA = 7,0e7 N → %.2f m (« au moins un mètre »)" % (dT * L_bas / EA))
print()

# Conséquences (modèle de stabilisation_rebond.sage) : période et durée
# d'amortissement sous 2 cm après l'arrêt
def modele(s_cabin, m_cabin, m_arriving, EA):
    span = max(LENGTH - s_cabin, R(20))
    k = EA / span
    omega = sqrt(k / m_cabin)
    amp = min(m_arriving * GRAB_A / k, R(0.45))
    ts = 0 if amp <= SEUIL else log(amp / SEUIL) / (ZETA * omega)
    return (2 * pi.n(60) / omega, amp, ts)
m_vide = TRAIN_EMPTY_KG
m_plein = TRAIN_EMPTY_KG + PAX_MAX * PAX_KG
cas = [("rame vide arrivée en bas", START_S, m_vide, m_vide),
       ("rame pleine arrivée en bas", START_S, m_plein, m_plein),
       ("contrepoids en bas (rame pleine en haut)", LENGTH - (STOP_S - START_S) - START_S + START_S, m_vide, m_plein)]
print("%-42s %22s %22s" % ("", "EA = 1,25e8", "EA = 7,0e7"))
for nom, s, m, ma in cas:
    a = modele(s, m, ma, R(1.25e8))
    b = modele(s, m, ma, R(7.0e7))
    print("%-42s T %5.2f s A %4.1f cm %4.1f s | T %5.2f s A %4.1f cm %4.1f s" %
          (nom, a[0], 100 * a[1], a[2], b[0], 100 * b[1], b[2]))
