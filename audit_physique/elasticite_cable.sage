# Élasticité du câble tracteur du Perce-Neige — ordres de grandeur pour un
# modèle dynamique (question de Kevin du 04/10/2026 : « reproduire la
# physique de l'élasticité du câble en fonction de la longueur déroulée,
# de la masse de la rame et des variations de vitesse »).
# Constantes = celles du simulateur (perce_neige_sim.py).
R = RealField(60)
EA   = R(7.0e7)       # N   raideur EFFECTIVE (câble + machinerie), calée le 06/10/2026 sur le recul observé par Kevin (≥ 1 m rame pleine en bas) : recul_embarquement.sage
rho  = R(11)          # kg/m masse linéique
m_vide  = R(32300 + 75)            # rame vide + conducteur
m_plein = R(32300 + 335*75)        # 334 passagers + conducteur
zeta = R(0.15)        # amortissement du simulateur (REBOUND_ZETA)

print("Onde longitudinale : c = sqrt(EA/rho) =", (EA/rho).sqrt().n(digits=5), "m/s")
print()
print("  L (m) | k (kN/m) | T vide (s) | T pleine (s) | f pleine (Hz) | aller-retour onde (s)")
for L in [25, 100, 500, 1000, 2000, 3000, 3450]:
    L = R(L)
    k = EA / L
    mc = rho * L
    Tv = 2*pi.n(60) * ((m_vide + mc/3) / k).sqrt()
    Tp = 2*pi.n(60) * ((m_plein + mc/3) / k).sqrt()
    print("  %5d | %8.1f | %10.2f | %12.2f | %13.3f | %8.2f" % (L, k/1000, Tv, Tp, 1/Tp, 2*L/(EA/rho).sqrt()))
print()

# Rame pleine en bas (L = 3450 m), accélération programmée 0,30 m/s²
L = R(3450); k = EA/L; m = m_plein + rho*L/3
for a, nom in [(R(0.30), "accélération programmée 0,30"), (R(1.25), "arrêt d'urgence poulie 1,25"), (R(2.5), "frein de service plein 2,5")]:
    dx = m*a/k
    dep = 1 + exp(-zeta*pi.n(60)/(1-zeta^2).sqrt())
    print("%s m/s² : allongement statique %.3f m, surtension %.1f kN ; en échelon, crête ×%.2f → %.3f m / %.1f kN"
          % (nom, dx, k*dx/1000, dep, dep*dx, dep*k*dx/1000))
print()

# Rampe d'accélération de durée tau (à-coup limité) : amplitude résiduelle de
# l'oscillation = |2 sin(w tau/2) / (w tau)| × allongement statique
w = (k/m).sqrt()
print("Rampe 0 → 0,30 m/s² en tau s (rame pleine en bas, T = %.2f s) :" % (2*pi.n(60)/w))
for tau in [0.5, 2, 5, 7, 10, 15]:
    tau = R(tau)
    fac = abs(2*sin(w*tau/2)/(w*tau))
    print("   tau = %4.1f s → oscillation résiduelle %.3f m (×%.2f du statique)" % (tau, fac*m*R(0.30)/k, fac))
