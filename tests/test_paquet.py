"""Le paquet Windows (kit.json) embarque tous les modules locaux du programme.

Retour d'un utilisateur (06/10/2026) : la 1.15.71 ne démarrait plus du tout sur PC
après la mise à jour — `perce_neige_sim.py` importait le nouveau module
`profil_coupe.py`, absent de la liste « modules » du kit : l'import échouait
au lancement, sans aucun message (application fenêtrée).

Exécution : pytest tests/test_paquet.py -v
"""
import ast
import json
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent


def _imports_locaux(fichier: Path) -> set:
    arbre = ast.parse(fichier.read_text(encoding="utf-8"))
    noms = set()
    for n in ast.walk(arbre):
        if isinstance(n, ast.Import):
            noms.update(a.name.split(".")[0] for a in n.names)
        elif isinstance(n, ast.ImportFrom) and n.module and n.level == 0:
            noms.add(n.module.split(".")[0])
    return {m for m in noms if (RACINE / f"{m}.py").exists()}


def test_modules_locaux_dans_le_kit():
    kit = json.loads((RACINE / "kit.json").read_text(encoding="utf-8"))
    embarques = set(kit["modules"])
    a_voir = [kit["point_entree"]]
    vus = set()
    while a_voir:
        f = a_voir.pop()
        if f in vus:
            continue
        vus.add(f)
        for m in _imports_locaux(RACINE / f):
            a_voir.append(f"{m}.py")
    manquants = sorted(vus - embarques)
    assert not manquants, f"modules importés mais absents du paquet (kit.json) : {manquants}"


def test_verification_import_du_kit():
    kit = json.loads((RACINE / "kit.json").read_text(encoding="utf-8"))
    assert "perce_neige_sim" in kit["verification_import"], \
        "la CI doit importer le programme principal dans le paquet construit"
