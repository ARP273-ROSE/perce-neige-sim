"""Rendu orthographique (face, flanc, dessus, trois-quarts) de la carrosserie
exportée par godot_project/bench_train_mesh_3d.gd — pour juger le modèle
sans GPU. Peintre simple : triangles triés par profondeur, ombrage Lambert.

    python tests/rendu_rame.py rame_mesh.txt sortie.png
"""
import sys

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection


def lire(path):
    tris, cols, alphas = [], [], []
    with open(path) as f:
        for line in f:
            p = line.split()
            if len(p) < 14:
                continue
            cols.append([float(p[1]), float(p[2]), float(p[3])])
            alphas.append(float(p[4]))
            v = np.array([float(x) for x in p[5:14]]).reshape(3, 3)
            tris.append(v)
    return np.array(tris), np.array(cols), np.array(alphas)


def vue(ax, tris, cols, alphas, R, light, titre, lim=None):
    """R : matrice 3×3 monde→(u, v, profondeur)."""
    P = tris @ R.T                       # (n, 3, 3) → colonnes u, v, d
    depth = P[:, :, 2].mean(axis=1)
    order = np.argsort(depth)            # loin d'abord
    # normale monde
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    nn = np.linalg.norm(n, axis=1, keepdims=True)
    n = n / np.where(nn == 0, 1, nn)
    shade = 0.45 + 0.55 * np.clip(n @ light, 0, 1)
    facecols = np.clip(cols * shade[:, None], 0, 1)
    rgba = np.concatenate([facecols, alphas[:, None]], axis=1)
    polys = [P[i, :, :2] for i in order]
    pc = PolyCollection(polys, facecolors=rgba[order], edgecolors="none", antialiased=False)
    ax.add_collection(pc)
    ax.set_aspect("equal")
    ax.set_facecolor("#1d2430")
    if lim is not None:
        ax.set_xlim(lim[0]); ax.set_ylim(lim[1])
    else:
        ax.autoscale_view()
    ax.set_title(titre, color="w", fontsize=9)
    ax.tick_params(colors="0.6", labelsize=7)


def main():
    tris, cols, alphas = lire(sys.argv[1])
    fig, axs = plt.subplots(2, 2, figsize=(12, 8), facecolor="#101418")
    light = np.array([0.4, 0.8, -0.45]); light /= np.linalg.norm(light)
    # face avant : on regarde vers +Z (la rame vient vers nous), u = −x, v = y
    R_face = np.array([[-1, 0, 0], [0, 1, 0], [0, 0, -1]], dtype=float)
    vue(axs[0, 0], tris, cols, alphas, R_face, light, "face avant (vue depuis −Z)", ((-2.2, 2.2), (-1.2, 2.2)))
    # flanc droit : on regarde vers −X, u = −z (avant à droite), v = y, d = x
    R_flanc = np.array([[0, 0, -1], [0, 1, 0], [1, 0, 0]], dtype=float)
    vue(axs[0, 1], tris, cols, alphas, R_flanc, light, "flanc (avant à droite)", ((-17, 17), (-1.2, 2.2)))
    # dessus : u = −z (avant à droite), v = x, d = y
    R_top = np.array([[0, 0, -1], [1, 0, 0], [0, 1, 0]], dtype=float)
    vue(axs[1, 0], tris, cols, alphas, R_top, light, "dessus", ((-17, 17), (-2.2, 2.2)))
    # trois-quarts avant : rotation yaw 35°, pitch 20°
    yaw, pitch = np.radians(35), np.radians(18)
    Ry = np.array([[np.cos(yaw), 0, np.sin(yaw)], [0, 1, 0], [-np.sin(yaw), 0, np.cos(yaw)]])
    Rx = np.array([[1, 0, 0], [0, np.cos(pitch), -np.sin(pitch)], [0, np.sin(pitch), np.cos(pitch)]])
    R34 = np.array([[-1, 0, 0], [0, 1, 0], [0, 0, -1]], dtype=float) @ Rx @ Ry
    vue(axs[1, 1], tris, cols, alphas, R34, light, "trois-quarts avant")
    for a in axs.flat:
        a.grid(alpha=0.15)
    fig.tight_layout()
    fig.savefig(sys.argv[2], dpi=110)
    print("rendu →", sys.argv[2])


if __name__ == "__main__":
    main()
