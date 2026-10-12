# Son de la salle des machines entendu sur les quais de la gare haute
# (retour d'utilisateur, 07/10/2026 : « quand on attend en gare du haut on entend
# strictement le même son que celui de la vue machinerie, que tu modules en
# fonction de la distance à la machinerie »).
#
# Modèle : la machinerie rayonne par la bouche de son hall comme une source
# ponctuelle dans un demi-espace → l'intensité décroît en 1/d², soit −6 dB
# par doublement de la distance (champ libre), au-delà d'un rayon de
# référence d0 où l'on est « devant la bouche » (gain 1). Dans la gare
# (réverbérante), le niveau ne tombe pas sous un plancher : −24 dB.
#
#   gain(d) = clamp(d0 / max(d, d0), 10^(−24/20), 1)       d0 = 4 m
#
# = main.gd::_gain_machinerie (PWA) et SoundSystem (PC, via skieur_etat[3]).
#   sage audit_physique/son_gare_haute.sage

d0 = 4.0
plancher_db = -24.0
plancher = 10^(plancher_db / 20)

def gain(d):
    return min(max(d0 / max(d, d0), plancher), 1.0)

def db(g):
    return 20 * log(g, 10).n(digits=4)

print("plancher linéaire : %.4f (%.0f dB)" % (plancher.n(), plancher_db))
assert abs(plancher.n() - 0.0631) < 1e-3          # 0.063 dans le code

print("\n d (m)   gain    dB")
for d in [0, 2, 4, 6, 8, 12, 16, 24, 32, 48, 64, 80, 120]:
    g = gain(d)
    print(" %5.0f  %.3f  %6.1f" % (d, g.n(), db(g)))

# −6 dB par doublement entre 4 m et 64 m, puis plancher
assert abs(db(gain(8)) - (-6.02)) < 0.05
assert abs(db(gain(16)) - (-12.04)) < 0.05
assert abs(db(gain(32)) - (-18.06)) < 0.05
assert gain(64) == plancher and gain(120) == plancher
# un quai de la gare haute : 10 à 60 m de la bouche → de −8 dB à −24 dB
print("\nquais du haut (10–60 m) : de %.1f à %.1f dB" % (db(gain(10)), db(gain(60))))
print("OK")

# --- 11/10/2026 (retour d'utilisateur : « en gare du haut le bruit de la
# machinerie diminue trop vite, et à la sortie Génépy on ne l'entend pas du
# tout ») : la gare est un volume RÉVERBÉRANT — le champ diffus soutient le
# niveau, la décroissance est bien plus lente qu'en champ libre. Nouvelle loi :
# −3 dB par doublement au-delà de d0 = 6 m (intensité en 1/d), plancher
# −15 dB ; dans le couloir de la porte Génépy et dehors devant elle (< 45 m
# de la bouche du hall), la même loi atténuée de 6 dB par la paroi.
d0n = 6.0
plancher_n = 10^(-15.0 / 20)
def gain_n(d, dehors=False):
    if dehors and d >= 45:
        return 0
    g = min(max((d0n / max(d, d0n))^0.5, plancher_n), 1.0)
    return g * (10^(-6.0 / 20) if dehors else 1)
print("\nnouvelle loi : plancher %.3f" % plancher_n.n())
for d in [4, 6, 12, 24, 48, 96]:
    g = gain_n(d); gd = gain_n(d, True)
    print(" %3.0f m  quai %.3f (%5.1f dB)   couloir/dehors %.3f (%s)" % (d, g.n(), db(g),
          gd if gd == 0 else gd.n(), "—" if gd == 0 else "%5.1f dB" % db(gd)))
assert abs(db(gain_n(12)) - (-3.01)) < 0.05 and abs(db(gain_n(24)) - (-6.02)) < 0.05
