# Stabilisation du rebond du câble après l'arrêt — durée d'amortissement
# Exploitation automatique (v1.15.21) : les portes ne s'ouvrent qu'une fois
# l'enveloppe A·e^(−ζωt) de l'oscillation résiduelle sous SEUIL, pour la rame
# pilotée ET pour le contrepoids (celui qui est en bas oscille visiblement).
#
# Exécuter : docker exec sagemath sage /home/sage/work/_pn/stabilisation_rebond.sage

# Constantes copiées de perce_neige_sim.py
LENGTH         = 3474.0
TRAIN_HALF     = 16.0
BUMPER_CLEAR   = 10.0
START_S        = TRAIN_HALF + BUMPER_CLEAR
STOP_S         = LENGTH - TRAIN_HALF - BUMPER_CLEAR
TRAIN_EMPTY_KG = 32300.0
PAX_KG         = 75.0
PAX_MAX        = 334
CABLE_EA_N     = 1.25e8
REBOUND_ZETA   = 0.15
REBOUND_GRAB_A = 0.35

SEUIL = 0.02     # m — enveloppe sous laquelle on considère la rame stabilisée

def modele(s_cabin, m_cabin, m_arriving):
    span  = max(LENGTH - s_cabin, 20.0)
    k     = CABLE_EA_N / span
    omega = sqrt(k / max(m_cabin, 1.0))
    amp   = min(m_arriving * REBOUND_GRAB_A / k, 0.45)
    return (span, k, omega, amp)

def t_stabilisation(omega, amp, seuil):
    # A·e^(−ζωt) = seuil  →  t = ln(A/seuil) / (ζω)
    if amp <= seuil:
        return 0.0
    return log(amp / seuil) / (REBOUND_ZETA * omega)

m_vide  = TRAIN_EMPTY_KG
m_plein = TRAIN_EMPTY_KG + PAX_MAX * PAX_KG

print("Seuil de stabilisation : %.0f mm" % (SEUIL * 1000))
print()
cas = [
    ("Rame pilotée arrivée en BAS, vide",        START_S, m_vide,  m_vide),
    ("Rame pilotée arrivée en BAS, pleine",      START_S, m_plein, m_plein),
    ("Rame pilotée arrivée en HAUT, pleine",     STOP_S,  m_plein, m_plein),
    ("Contrepoids en BAS (rame pleine en haut)", LENGTH - STOP_S, m_vide, m_plein),
    ("Contrepoids en HAUT (rame pleine en bas)", LENGTH - START_S, m_vide, m_plein),
]
print("%-42s %8s %9s %7s %8s %9s" % ("cas", "L (m)", "k (kN/m)", "T (s)", "A (cm)", "t_stab (s)"))
for nom, s, m, m_arr in cas:
    span, k, omega, amp = modele(s, m, m_arr)
    T = 2 * pi / omega
    ts = t_stabilisation(omega, amp, SEUIL)
    print("%-42s %8.1f %9.1f %7.2f %8.1f %9.1f" % (
        nom, float(span), float(k / 1000), float(T), float(amp * 100), float(ts)))

print()
print("Enveloppe résiduelle après t secondes, rame pleine en bas :")
span, k, omega, amp = modele(START_S, m_plein, m_plein)
for t in [0, 5, 10, 15, 20, 25, 30]:
    print("  t = %2d s : %5.1f cm" % (t, float(amp * exp(-REBOUND_ZETA * omega * t) * 100)))

print()
print("Borne haute retenue pour l'automate : 30 s (au-delà, ouverture forcée).")
print("Borne basse : 3 s (le temps que le frein tambour soit serré et le clip d'arrêt fini).")
