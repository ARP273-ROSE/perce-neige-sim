# Plaque du réducteur de la salle des machines (photo de Kevin, 30/09/2026)
# ---------------------------------------------------------------------------
# « Changement de la vitesse seulement en arrêt », 1990, type A.KFW 560/W3/S,
# huile DIN 51517 CLP 220 (ou 320, flou). Levier à deux positions :
#   entrée électrique  : arbre de sortie n = 55 (i = 21,8)  ou n = 36 (i = 33,3)
#   entrée hydraulique : arbre de sortie n = 9,2 (i = 192,2) ou n = 6 (i = 293,4)
# Les puissances d'entrée sont illisibles (flou) ; on ne s'en sert pas.
# Vérifie : régime d'entrée n × i, et vitesse du câble π D n / 60 avec la
# poulie de 4,16 m (remontees-mecaniques.net).
#
# Exécuter : sage audit_physique/reducteur_plaque.sage

from sage.all import *

D = RDF(4.16)
lignes = [("électrique, 1re", RDF(55), RDF(21.8)),
          ("électrique, 2e", RDF(36), RDF(33.3)),
          ("hydraulique, 1re", RDF(9.2), RDF(192.2)),
          ("hydraulique, 2e", RDF(6), RDF(293.4))]
print(f"{'entrée':18s} {'n sortie':>9s} {'i':>7s} {'n entrée':>9s} {'v câble':>9s}")
for nom, n, i in lignes:
    v = pi * D * n / 60
    print(f"{nom:18s} {float(n):7.1f}/min {float(i):7.1f} {float(n*i):7.0f}/min {float(v):6.2f} m/s")
print()
print("→ 55 tr/min sur la poulie de 4,16 m = 11,98 m/s : la vitesse maxi de 12 m/s du")
print("  simulateur est bien celle de la machine ; le moteur tourne alors à 1 200 tr/min.")
print("→ l'entraînement hydraulique de secours (diesel) mène le câble à 2,0 ou 1,3 m/s.")
