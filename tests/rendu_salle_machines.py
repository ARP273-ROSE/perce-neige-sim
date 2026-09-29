"""Rendu hors Godot de la salle des machines exportée par
godot_project/bench_salle_machines_3d.gd (repère local : x, y, s).

Trois vues : coupe latérale (tranche x ∈ [−0,7 ; 0,6]), plan de la salle sous
la dalle, et vue plongeante en perspective depuis le quai sur la fin de ligne
(comme la photo RM.net des butoirs). Peintre simple, ombrage Lambert.

    python tests/rendu_salle_machines.py salle.txt sortie.png
"""
import sys

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection


def lire(path):
    tris, cols = [], []
    with open(path) as f:
        for line in f:
            p = line.split()
            if len(p) < 14:
                continue
            cols.append([float(p[1]), float(p[2]), float(p[3]), float(p[4])])
            tris.append(np.array([float(x) for x in p[5:14]]).reshape(3, 3))
    return np.array(tris), np.array(cols)


def subdiviser(tris, cols, lmax=0.6):
    """Coupe les grands triangles (dalle, murs) : le tri du peintre par
    centroïde se trompe sinon, et une grande dalle passait derrière ce
    qu'elle recouvre."""
    out_t, out_c = [], []
    pile = list(zip(tris, cols))
    while pile:
        t, c = pile.pop()
        e = [np.linalg.norm(t[1] - t[0]), np.linalg.norm(t[2] - t[1]), np.linalg.norm(t[0] - t[2])]
        k = int(np.argmax(e))
        if e[k] <= lmax or len(out_t) > 400000:
            out_t.append(t)
            out_c.append(c)
            continue
        a, b = k, (k + 1) % 3
        o = 3 - a - b
        m = (t[a] + t[b]) / 2
        pile.append((np.array([t[a], m, t[o]]), c))
        pile.append((np.array([m, t[b], t[o]]), c))
    return np.array(out_t), np.array(out_c)


def ombrer(tris, cols, light):
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    nn = np.linalg.norm(n, axis=1, keepdims=True)
    n = n / np.where(nn == 0, 1, nn)
    shade = 0.40 + 0.60 * np.abs(n @ light)
    rgb = np.clip(cols[:, :3] * shade[:, None], 0, 1)
    return np.concatenate([rgb, cols[:, 3:4]], axis=1)


def peindre(ax, uv, depth, rgba, titre, lim):
    order = np.argsort(-depth)            # loin d'abord (profondeur croissante = proche)
    pc = PolyCollection([uv[i] for i in order], facecolors=rgba[order],
                        edgecolors="none", antialiased=False)
    ax.add_collection(pc)
    ax.set_xlim(lim[0])
    ax.set_ylim(lim[1])
    ax.set_aspect("equal")
    ax.set_facecolor("#111418")
    ax.set_title(titre, color="w", fontsize=10)
    ax.tick_params(colors="0.6", labelsize=7)


def main():
    tris, cols = lire(sys.argv[1])
    tris, cols = subdiviser(tris, cols)
    light = np.array([0.35, 0.8, -0.3])
    light /= np.linalg.norm(light)
    rgba = ombrer(tris, cols, light)
    c = tris.mean(axis=1)                 # centroïdes (x, y, s)

    fig = plt.figure(figsize=(16, 13), facecolor="#0b0d10")
    # 1. coupe latérale : on regarde depuis +x, u = s, v = y ; tranche centrale
    ax1 = fig.add_subplot(2, 2, 1)
    m = (c[:, 0] > -0.75) & (c[:, 0] < 0.6) & (c[:, 1] < 0.5)
    uv = tris[m][:, :, [2, 1]]
    peindre(ax1, uv, -tris[m][:, :, 0].mean(axis=1) * -1, rgba[m],
            "Coupe dans l'axe de la voie (tranche x ∈ [−0,75 ; 0,6] m)",
            ((-3, 11), (-8, 0.5)))
    ax1.axhline(-1.60, color="0.5", lw=0.5, ls=":")
    ax1.text(-2.8, -1.5, "dalle", color="0.7", fontsize=7)

    # 2. plan de la salle sous la dalle : vue de dessus, u = s, v = −x
    ax2 = fig.add_subplot(2, 2, 2)
    m = c[:, 1] < -1.95
    uv = np.stack([tris[m][:, :, 2], -tris[m][:, :, 0]], axis=2)
    peindre(ax2, uv, -tris[m][:, :, 1].mean(axis=1), rgba[m],
            "Plan de la salle des machines (sous la dalle)", ((-3, 14.5), (-5.5, 5.5)))

    # 3. vue plongeante depuis le quai, perspective
    ax3 = fig.add_subplot(2, 1, 2)
    cam = np.array([1.6, 1.4, -4.2])      # x, y, s : sur le quai, côté droit
    cible = np.array([-0.1, -2.2, 2.2])
    fwd = cible - cam
    fwd /= np.linalg.norm(fwd)
    up0 = np.array([0.0, 1.0, 0.0])
    right = np.cross(fwd, up0)
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    rel = tris - cam
    z = rel @ fwd
    x = rel @ right
    y = rel @ up
    m = (z.min(axis=1) > 0.3) & (c[:, 1] < 2.0) & (c[:, 2] < 12.0)
    f = 1.2
    u = -f * x[m] / z[m]                   # repère main droite (x monde → gauche écran)
    v = f * y[m] / z[m]
    uv = np.stack([u, v], axis=2)
    peindre(ax3, uv, z[m].mean(axis=1), rgba[m],
            "Fin de ligne vue du quai : roue aval entre les butoirs, fosse, batterie de galets",
            ((-1.1, 1.1), (-0.75, 0.45)))
    plt.tight_layout()
    plt.savefig(sys.argv[2], dpi=90, facecolor=fig.get_facecolor())
    print("rendu :", sys.argv[2])


if __name__ == "__main__":
    main()
