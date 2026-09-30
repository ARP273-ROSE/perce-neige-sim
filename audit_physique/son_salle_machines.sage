# Son de la salle des machines : calage sur la vidéo « [FUNI284] Funiculaire
# du Perce-Neige | Tignes (marche complète à 12 m/s) », chaîne YouTube
# « Transports câblés », id CTrkgn4mvyE, filmée en août 2013 en « version
# statique en G2 » (caméra fixe en gare haute, sur la roue aval entre les
# butoirs bleus). Demande de Kevin du 30/09/2026.
#
# Données : son_salle_machines_suivi.csv — suivi de la raie tonale de la
# machinerie (pic 40-240 Hz, fenêtres de 0,74 s tous les 0,25 s) et niveau
# RMS sur 1 s, produits par le script d'extraction (python-lab).
# La raie est proportionnelle à la vitesse du câble : v = 12 × f / f_12.
#
# Exécuter : sage audit_physique/son_salle_machines.sage

from sage.all import *
import csv, os

ici = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else "."
rows = list(csv.DictReader(open(os.path.join(ici, "son_salle_machines_suivi.csv"))))
T = [RDF(r["t"]) for r in rows]
F = [RDF(r["f"]) if r["f"] else None for r in rows]
P = [RDF(r["rms"]) ** 2 for r in rows]

def mediane(v):
    v = sorted(v)
    n = len(v)
    return v[n // 2] if n % 2 else (v[n // 2 - 1] + v[n // 2]) / 2

f12 = mediane([f for t, f in zip(T, F) if f is not None and 110 <= t <= 335])
print("=== Raie de la machinerie")
print(f"  à 12 m/s (médiane de la marche 110-335 s) : f_12 = {float(f12):.2f} Hz")
fm = [f for t, f in zip(T, F) if f is not None and 110 <= t <= 335]
print(f"  dérive pendant la marche : {float(min(fm)):.1f} à {float(max(fm)):.1f} Hz "
      f"(± {float((max(fm) - min(fm)) / 2 / f12 * 100):.1f} % : régulation du variateur)")
print(f"  moteur à 12 m/s : 1199 tr/min = {float(RDF(1199) / 60):.2f} Hz (reducteur_plaque.sage) → raie = "
      f"{float(f12 / (RDF(1199) / 60)):.2f} × la rotation moteur")

V = [RDF(12) * f / f12 if f is not None else None for f in F]

def regression(xs, ys):
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    b = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sum((x - mx) ** 2 for x in xs)
    return b, my - b * mx

print("\n=== Démarrage et arrivée à 12 m/s (réels)")
acc = [(t, v) for t, v in zip(T, V) if v is not None and 70 <= t <= 94]
a, b = regression([p[0] for p in acc], [p[1] for p in acc])
t0 = -b / a
print(f"  accélération (70-94 s, 5,9 → 11 m/s) : {float(a):.3f} m/s² ; droite prolongée à v = 0 : t = {float(t0):.1f} s")
dec = [(t, v) for t, v in zip(T, V) if v is not None and 342 <= t <= 355]
ad, bd = regression([p[0] for p in dec], [p[1] for p in dec])
t1 = -bd / ad
print(f"  freinage (342-355 s) : {float(ad):.3f} m/s² ; droite prolongée à v = 0 : t = {float(t1):.1f} s")
d_marche = sum((V[i] + V[i + 1]) / 2 * (T[i + 1] - T[i]) for i in range(len(T) - 1)
               if V[i] is not None and V[i + 1] is not None)
print(f"  distance parcourue pendant les {len([v for v in V if v is not None])} points suivis : {float(d_marche):.0f} m"
      f" (la ligne fait 3 474 m ; le reste se fait sous 5 m/s, raie masquée)")

print("\n=== Niveau sonore en fonction de la vitesse")
P_repos = mediane([p for t, p in zip(T, P) if 370 <= t <= 412])
P_12 = mediane([p for t, p in zip(T, P) if 110 <= t <= 335])
print(f"  repos (370-412 s) : {float(10 * log(P_repos, 10)):.1f} dBFS ; marche à 12 m/s : {float(10 * log(P_12, 10)):.1f} dBFS")
print(f"  part de la machinerie à 12 m/s : {float(10 * log(P_12 - P_repos, 10)):.1f} dBFS")
pts = [(log(v / 12), log((p - P_repos) / (P_12 - P_repos))) for t, v, p in zip(T, V, P)
       if v is not None and 4.5 <= v <= 11.5 and p > P_repos and (70 <= t <= 100 or 340 <= t <= 356)]
k, c = regression([p[0] for p in pts], [p[1] for p in pts])
print(f"  puissance de la machinerie ∝ v^{float(k):.2f} (ajustement sur {len(pts)} points, 4,5-11,5 m/s)")
print(f"  soit un gain d'amplitude ∝ v^{float(k / 2):.2f}")
for v in (1, 2, 4, 6, 8, 10, 12):
    Pm = (P_12 - P_repos) * (RDF(v) / 12) ** k
    print(f"    v = {v:2d} m/s : machinerie {float(10 * log(Pm, 10)):6.1f} dBFS, total {float(10 * log(Pm + P_repos, 10)):6.1f} dBFS")

print("\n=== Pour le simulateur")
print(f"  boucle « marche » extraite à 12 m/s, jouée à la hauteur v/12 (la raie suit la vitesse)")
print(f"  gain de la boucle marche : (v/12)^{float(k / 2):.2f} ; boucle « repos » toujours présente")
