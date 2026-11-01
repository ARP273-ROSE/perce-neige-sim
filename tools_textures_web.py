#!/usr/bin/env python3
"""Versions allégées des grandes textures pour la PWA (textures/web/).

Sur le web, charger l'original coûtait deux fois : envoi à la carte graphique
puis relecture avant réduction. Ces fichiers ont déjà la taille voulue ;
les originaux sont exclus de l'export Web (exclude_filter du préréglage).
"""
from pathlib import Path
from PIL import Image

T = Path(__file__).parent / "godot_project" / "textures"
TAILLES = {
    "relief_ortho.jpg": (2048, None),
    "relief_lointain.jpg": (1024, None),
    "panorama_glacier.png": (3072, None),
    "pistes_masque.png": (2048, "L"),
}
(T / "web").mkdir(exist_ok=True)
for nom, (l, mode) in TAILLES.items():
    im = Image.open(T / nom)
    if mode:
        im = im.convert(mode)
    im = im.resize((l, round(im.height * l / im.width)), Image.LANCZOS)
    sortie = T / "web" / nom
    if sortie.suffix == ".jpg":
        im.convert("RGB").save(sortie, quality=88, optimize=True)
    else:
        im.save(sortie, optimize=True)
    print(nom, im.size, sortie.stat().st_size)
