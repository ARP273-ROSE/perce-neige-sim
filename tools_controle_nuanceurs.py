#!/usr/bin/env python3
"""Contrôle avant publication : nuanceurs et scripts du viewer, en fenêtre.

Les bancs sans écran ne compilent aucun nuanceur : un nuanceur refusé par le moteur leur
échappe, et le sol s'affiche sans sa photo. Ce contrôle ouvre une fenêtre pour chaque chemin
de rendu et échoue sur la moindre erreur de nuanceur, de script ou d'analyse.

    python tools_controle_nuanceurs.py --godot CHEMIN_GODOT --pack DOSSIER_PACK_HD

GODOT4 peut remplacer --godot. Sans --pack, les chemins du pack comptent comme un échec, sauf
avec --sans-pack, qui les passe en le disant. Code de sortie : 0 si tout est bon.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import threading
import time
from pathlib import Path

RACINE = Path(__file__).resolve().parent
PROJET = RACINE / "godot_project"
# ce que le moteur écrit quand un nuanceur ou un script est refusé
ERREURS = re.compile(
    r"SHADER ERROR|Shader compilation failed|SCRIPT ERROR|Parse Error|Failed to load script|NUANCEURS_ECHEC")
FIN = "NUANCEURS_FIN"
ATTENTE_S = 900


def chemins(pack: str | None) -> list[tuple[str, list[str], list[str]]]:
    """[nom, arguments du moteur, arguments du jeu] de chaque chemin de rendu."""
    sans = ["--sans-hd", "--attendu=sans_hd"]
    liste = [
        ("sans pack, cran 0", [], ["--cran=0", *sans]),
        ("sans pack, cran 4 allégé", [], ["--cran=4", "--allege", *sans]),
        ("sans pack ni normales, cran 4 allégé", [], ["--cran=4", "--allege", "--sans-normales", *sans]),
        ("OpenGL, cran 4 allégé", ["--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3"],
         ["--cran=4", "--allege", *sans]),
    ]
    if pack:
        p = f"--pack-hd={pack}"
        liste += [
            ("pack niveau 2, cran 0", [], ["--cran=0", "--hd-niveau=2", p, "--attendu=hd"]),
            ("pack niveau 1, cran 1", [], ["--cran=1", "--relief-fin", "--hd-niveau=1", p, "--attendu=hd"]),
            ("pack niveau 1, cran 4 allégé", [], ["--cran=4", "--allege", "--relief-fin", "--hd-niveau=1", p, "--attendu=hd"]),
        ]
    return liste


def controler(godot: str, nom: str, moteur: list[str], jeu: list[str]) -> bool:
    cmd = [godot, "--resolution", "1280x720", "--path", str(PROJET), *moteur,
           "-s", "bench_nuanceurs_3d.gd", "--", "--mode=normal", *jeu]
    # (une erreur d'analyse peut laisser le moteur en attente : arrêté 5 s après la première erreur)
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding="utf-8", errors="replace")
    lignes: list[str] = []
    lecteur = threading.Thread(target=lambda: lignes.extend(p.stdout), daemon=True)
    lecteur.start()
    debut = time.monotonic()
    t_faute = None
    while p.poll() is None:
        time.sleep(0.5)
        if t_faute is None and any(ERREURS.search(ligne) for ligne in list(lignes)):
            t_faute = time.monotonic()
        if (t_faute is not None and time.monotonic() - t_faute > 5.0) or time.monotonic() - debut > ATTENTE_S:
            p.kill()
            break
    p.wait()
    lecteur.join(5.0)
    if t_faute is None and time.monotonic() - debut > ATTENTE_S:
        print(f"ÉCHEC  {nom} : pas fini en {ATTENTE_S} s", flush=True)
        return False
    lignes = [ligne.rstrip() for ligne in lignes]
    fautes = [ligne for ligne in lignes if ERREURS.search(ligne)]
    fini = any(FIN in ligne for ligne in lignes)
    bilan = next((ligne for ligne in reversed(lignes) if ligne.startswith("[Nuanceurs] ") and "points" in ligne), "")
    if fautes or not fini:
        print(f"ÉCHEC  {nom} : {len(fautes)} erreurs, fin {'atteinte' if fini else 'NON atteinte'}, code {p.returncode}", flush=True)
        for ligne in fautes[:12]:
            print("    " + ligne[:200])
        if not fautes:
            for ligne in lignes[-8:]:
                print("    " + ligne[:200])
        return False
    # (une sortie en erreur APRÈS la fin du contrôle ne dit rien des nuanceurs : on la signale)
    note = "" if p.returncode == 0 else f" ; attention, code {p.returncode} en quittant"
    print(f"OK     {nom} : {bilan.removeprefix('[Nuanceurs] ')}{note}", flush=True)
    return True


def main() -> int:
    a = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    a.add_argument("--godot", default=os.environ.get("GODOT4"), help="exécutable console de Godot 4")
    a.add_argument("--pack", help="dossier du pack haute définition")
    a.add_argument("--sans-pack", action="store_true", help="passer les chemins du pack, en le disant")
    a.add_argument("--seul", default="", help="seulement les chemins dont le nom contient ce texte")
    o = a.parse_args()
    if not o.godot:
        a.error("--godot ou GODOT4 requis")
    if o.pack and not (Path(o.pack) / "relief.pnhd").is_file():
        a.error(f"pas de relief.pnhd dans {o.pack}")
    bons = True
    if not o.pack:
        print(("PASSÉ " if o.sans_pack else "ÉCHEC ") + " chemins du pack : --pack absent")
        bons = o.sans_pack
    for nom, moteur, jeu in chemins(o.pack):
        if o.seul not in nom:
            continue
        bons = controler(o.godot, nom, moteur, jeu) and bons
    print("CONTRÔLE " + ("OK" if bons else "EN ÉCHEC"))
    return 0 if bons else 1


if __name__ == "__main__":
    sys.exit(main())
