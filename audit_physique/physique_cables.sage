# Physique des câbles et véhicules — perce-neige-sim, 24/11/2026
g = 9.81; PAX = 80
def kink(P,H): return P/H            # cassure (rad) d'un câble tendu H sous une charge P
print("=== A. Monocâbles (câble Ø47, H = 300 kN) ===")
d = 47; MBF = 0.85*pi/4*d^2*1.96e3/1e3   # N/mm2 * mm2 → kN approx (câble compacté 1960)
print("rupture estimée %.0f kN, coef. sécurité à 330 kN : %.1f" % (MBF, MBF/330))
H = 300e3
for nom, m0, pl, e in [("TSD6 siège", 95*6+80, 6, 12.0), ("TCD10 cabine", 850, 10, 30.0)]:
    for etat, n in [("vide", 0), ("plein", pl)]:
        P = (m0 + PAX*n)*g
        k = kink(P,H)
        dz = P*e/(8*H)       # écart corde/parabole entre deux véhicules = montée-descente en un point fixe
        print("%-13s %-5s P=%5.1f kN  cassure %.2f°  bosse entre véhicules %.1f cm" % (nom, etat, P/1e3, float(k*180/pi), float(dz*100)))
print()
print("=== B. Téléphériques (charge sur la voie : 2 porteurs) ===")
for nom, m0, pl, H, n_paires, pas_paire, pas_galet in [("Grande Motte", 6200, 115, 1.3e6, 6, 0.74, 0.37), ("Fornet", 5600, 80, 1.1e6, 6, 0.84, 0.42)]:
    for etat, n in [("vide", 0), ("pleine", pl)]:
        P = (m0 + PAX*n)*g
        k = kink(P,H)
        lc = (n_paires-1)*pas_paire + pas_galet       # entre galets extrêmes
        R = H*lc/P                                     # rayon du câble sous le chariot (charge répartie sur les galets)
        fl = lc^2/(8*R)                                # flèche de l'arc sous le chariot
        a_bout = (lc/2 - pas_paire/2)/R                # inclinaison de la paire de bout / chariot
        print("%-12s %-6s P=%6.1f kN cassure %.2f°  R=%5.1f m  arc sous le chariot %.1f cm  paire de bout %.2f°" % (nom, etat, P/1e3, float(k*180/pi), float(R), float(fl*100), float(a_bout*180/pi)))
print("Fornet : contrepoids 4×108 t → si moufle 2:1, T porteur = %.0f kN, voie = %.2f MN ; porteur Ø44 clos rupture ≈ %.0f kN → coef %.1f" % (54e3*g/1e3, 2*54e3*g/1e6, 0.85*pi/4*44^2*1.57, 0.85*pi/4*44^2*1.57/(54*g)))
print()
print("=== C. 3S Olympique (2 porteurs Ø57, rupture 3789 kN chacun, H voie 1.1 MN) ===")
H = 1.1e6
for etat, m in [("vide", 2950), ("pleine", 5350)]:
    P = m*g
    lc = 1.6 + 0.6
    R = H*lc/P
    print("%-6s P=%.1f kN cassure %.2f°  R=%.0f m  arc sous chariot %.1f cm ; coef sécurité porteurs %.1f" % (etat, P/1e3, float(kink(P,H)*180/pi), float(R), float(lc^2/(8*R)*100), float(2*3789/1100)))
print()
print("=== D. Pendule ===")
for nom, L, zeta in [("télécabine", 3.0, 90/850), ("3S", 4.36, 90/2950), ("TPH GM", 7.0, 90/6200)]:
    w0 = sqrt(g/L); T = 2*pi/w0
    t_demi = log(2)/(zeta*w0)
    print("%-10s L=%.2f m T=%.2f s ζ=%.3f amplitude /2 en %.0f s (littérature télécabine ζ≈0,0035 → %.0f s)" % (nom, L, float(T), float(zeta), float(t_demi), float(log(2)/(0.0035*w0))))
a = 1.8
print("lanceur 3S a=%.1f m/s² : inclinaison d'équilibre %.1f°, lâché d'un coup → amplitude %.1f°" % (a, float(atan(a/g)*180/pi), float(atan(a/g)*180/pi)))
