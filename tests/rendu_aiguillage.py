"""Rendu hors Godot de l'aiguillage Abt bas exporté par
godot_project/bench_aiguillage_3d.gd (repère local de la fourche : x, y, s).

Trois vues : plan de l'aiguillage, vue en perspective depuis la voie unique
en regardant vers l'amont (comme la photo d'aiguillage de Kevin), gros plan
d'une fenêtre où le câble opposé passe sous la tête du rail intérieur.

    python tests/rendu_aiguillage.py aiguillage.txt sortie.png
"""
import sys

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from rendu_salle_machines import lire, subdiviser, ombrer, peindre  # noqa: E402


def perspective(ax, tris, rgba, cam, cible, titre, lim, f=1.2, zmin=0.2):
    fwd = cible - cam
    fwd = fwd / np.linalg.norm(fwd)
    right = np.cross(fwd, np.array([0.0, 1.0, 0.0]))
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    rel = tris - cam
    z = rel @ fwd
    x = rel @ right
    y = rel @ up
    m = z.min(axis=1) > zmin
    u = -f * x[m] / z[m]      # repère main droite : x monde → gauche écran
    v = f * y[m] / z[m]
    peindre(ax, np.stack([u, v], axis=2), z[m].mean(axis=1), rgba[m], titre, lim)


def main():
    tris, cols = lire(sys.argv[1])
    tris, cols = subdiviser(tris, cols, lmax=0.35)
    light = np.array([0.3, 0.85, -0.35])
    light /= np.linalg.norm(light)
    rgba = ombrer(tris, cols, light)

    fig = plt.figure(figsize=(16, 21), facecolor="#0b0d10")
    gs = fig.add_gridspec(3, 2, height_ratios=[0.8, 1.0, 1.0])
    # 1. plan : u = s, v = −x (gauche de la montée en haut), largeurs × 5
    ax1 = fig.add_subplot(gs[0, :])
    m = tris[:, :, 1].mean(axis=1) < 0.0
    uv = np.stack([tris[m][:, :, 2], -tris[m][:, :, 0] * 5.0], axis=2)
    peindre(ax1, uv, -tris[m][:, :, 1].mean(axis=1), rgba[m],
            "Aiguillage Abt bas vu de dessus : 0 = fourche, montée vers la droite (largeurs × 5)",
            ((-7, 46), (-10.5, 10.5)))
    ax1.set_aspect("auto")
    for s_, lab in ((-4.0, "pointes des langues"), (17.36, "lacunes du câble"),
                    (27.45, "cœur en X")):
        ax1.axvline(s_, color="0.6", lw=0.6, ls=":")
        ax1.text(s_ + 0.3, 9.4, lab, color="0.85", fontsize=9)

    # 2. comme la photo : debout sur la voie unique, vers l'amont
    ax2 = fig.add_subplot(gs[1, 0])
    perspective(ax2, tris, rgba, np.array([0.0, 0.45, -5.0]), np.array([0.0, -1.30, 16.0]),
                "Debout sur la voie unique, vers l'amont", ((-0.75, 0.75), (-0.75, 0.30)),
                f=1.3)
    ax3 = fig.add_subplot(gs[1, 1])
    perspective(ax3, tris, rgba, np.array([0.0, -0.30, 19.0]), np.array([0.0, -1.30, 30.0]),
                "Le cœur en X, où les deux rails intérieurs se croisent",
                ((-0.75, 0.75), (-0.75, 0.30)), f=1.3)
    # 3. gros plans
    ax4 = fig.add_subplot(gs[2, 0])
    perspective(ax4, tris, rgba, np.array([-0.72, -1.02, 15.6]), np.array([-0.36, -1.33, 17.4]),
                "Lacune : le câble opposé passe entre les deux bouts de rail",
                ((-0.6, 0.6), (-0.45, 0.35)), f=1.4, zmin=0.05)
    ax5 = fig.add_subplot(gs[2, 1])
    perspective(ax5, tris, rgba, np.array([0.10, -0.85, 19.9]), np.array([-0.55, -1.40, 22.0]),
                "Galet porteur et galet de déviation incliné (22 m)",
                ((-0.6, 0.6), (-0.45, 0.35)), f=1.4, zmin=0.05)
    plt.tight_layout()
    plt.savefig(sys.argv[2], dpi=85, facecolor=fig.get_facecolor())
    # zoom_lacune : plan à l'échelle réelle autour des deux lacunes basses
    fig2 = plt.figure(figsize=(16, 6), facecolor="#0b0d10")
    ax = fig2.add_subplot(1, 1, 1)
    m2 = (tris[:, :, 1].mean(axis=1) < 0.0) & (tris[:, :, 2].mean(axis=1) > 13) & (tris[:, :, 2].mean(axis=1) < 22)
    uv2 = np.stack([tris[m2][:, :, 2], -tris[m2][:, :, 0]], axis=2)
    peindre(ax, uv2, -tris[m2][:, :, 1].mean(axis=1), rgba[m2],
            "Les deux lacunes du câble, vues de dessus à l'échelle (s de 13 à 22 m après la fourche)",
            ((13, 22), (-1.35, 1.35)))
    plt.tight_layout()
    fig2.savefig(sys.argv[2].replace(".png", "_lacunes.png"), dpi=85, facecolor=fig2.get_facecolor())
    return
    plt.savefig(sys.argv[2], dpi=85, facecolor=fig.get_facecolor())
    print("rendu :", sys.argv[2])


if __name__ == "__main__":
    main()
