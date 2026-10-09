# Variation CONTINUE de la pente (retour d'un utilisateur du 06/10/2026 : « la
# variation de la pente en haut avant l'entrée en gare n'est pas continue
# alors qu'elle l'est dans la réalité »).
#
# Le profil de pente est une table de points (SLOPE_PROFILE). Entre deux
# points, le PC interpolait LINÉAIREMENT (la variation de pente change par
# paliers aux points) et la 3D de la PWA lissait chaque intervalle à part
# (la variation retombe à ZÉRO à chaque point). Désormais, partout : cubique
# monotone de Fritsch-Carlson (PCHIP) — pente ET variation continues, sans
# dépasser les valeurs de la table. On vérifie ici notre implémentation
# contre scipy.interpolate.PchipInterpolator et on chiffre les sauts.
#
#   docker exec sagemath sage /home/sage/work/pn/pente_continue.sage
import re
import numpy as np
from scipy.interpolate import PchipInterpolator

src = open('/home/sage/work/pn/slope_profile.gd').read()
blk = src[src.index('const SLOPE_PROFILE'):]
blk = blk[:blk.index('\n]')]
T = [tuple(map(float, m)) for m in re.findall(r'\[\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\]', blk)]
X = np.array([p[0] for p in T]); Y = np.array([p[1] for p in T])


def pentes(X, Y):
    n = len(X); h = np.diff(X); d = np.diff(Y) / h; m = np.zeros(n)
    for k in range(1, n - 1):
        if d[k - 1] * d[k] <= 0:
            m[k] = 0.0
        else:
            w1 = 2 * h[k] + h[k - 1]; w2 = h[k] + 2 * h[k - 1]
            m[k] = (w1 + w2) / (w1 / d[k - 1] + w2 / d[k])

    def bout(h0, h1, d0, d1):
        mb = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
        if np.sign(mb) != np.sign(d0):
            return 0.0
        if np.sign(d0) != np.sign(d1) and abs(mb) > abs(3 * d0):
            return 3 * d0
        return mb
    m[0] = bout(h[0], h[1], d[0], d[1]); m[-1] = bout(h[-1], h[-2], d[-1], d[-2])
    return m


M = pentes(X, Y)


def g(s):
    k = min(max(np.searchsorted(X, s) - 1, 0), len(X) - 2)
    hk = X[k + 1] - X[k]; t = (s - X[k]) / hk
    return ((2*t**3 - 3*t**2 + 1) * Y[k] + (t**3 - 2*t**2 + t) * hk * M[k]
            + (-2*t**3 + 3*t**2) * Y[k + 1] + (t**3 - t**2) * hk * M[k + 1])


ref = PchipInterpolator(X, Y)
S = np.linspace(X[0], X[-1], 20001)
ecart = max(abs(g(s) - ref(s)) for s in S)
print("notre PCHIP contre scipy : écart max %.2e (pente)" % ecart)
print("dépassement de la table : min %.4f / max %.4f (table %.4f / %.4f)"
      % (min(g(s) for s in S), max(g(s) for s in S), Y.min(), Y.max()))
print()
print("Variation de la pente (‰ par mètre) de part et d'autre des points du haut :")
print("    point      linéaire avant/après        PCHIP avant/après")
eps = 0.01
for xk in X[-5:-1]:
    lin_av = (np.interp(xk, X, Y) - np.interp(xk - 1, X, Y)) * 1000
    lin_ap = (np.interp(xk + 1, X, Y) - np.interp(xk, X, Y)) * 1000
    p_av = (g(xk) - g(xk - eps)) / eps * 1000
    p_ap = (g(xk + eps) - g(xk)) / eps * 1000
    print("  %8.2f     %+6.3f / %+6.3f              %+6.3f / %+6.3f" % (xk, lin_av, lin_ap, p_av, p_ap))
print()
# rayon de courbure verticale minimal sur l'entrée en gare haute
Sh = np.linspace(3300.0, X[-1], 4001)
th = np.arctan([g(s) for s in Sh])
k = np.abs(np.gradient(th, Sh))
i = np.argmax(k)
print("entrée en gare haute : rayon vertical minimal %.0f m à s = %.0f (pente %.1f %%)"
      % (1 / k[i], Sh[i], 100 * g(Sh[i])))
print("pente au galet 238 (s = 3 477,53) : %.2f %%" % (100 * g(3477.53)))
