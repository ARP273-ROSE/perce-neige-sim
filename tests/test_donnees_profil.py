"""Données de l'utilisateur hors du dossier d'installation (14/10/2026).

Les versions jusqu'à la 1.19 rangeaient dans app/ (le dossier
d'installation, effacé par le Setup et remplacé par la mise à jour) l'accord
d'envoi des rapports, leur file d'attente et la trace du dernier crash natif.
Au premier démarrage, tout ce qui traîne dans app/ est DÉPLACÉ vers le
profil, sans rien perdre.

Exécution : pytest tests/test_donnees_profil.py -v
"""
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RACINE))

import perce_neige_sim as pn  # noqa: E402

# d'autres essais remplacent pn._writable_dir sans le rétablir : l'original,
# relevé à la collecte (avant tout essai)
_WRITABLE_DIR = pn._writable_dir


def _preparer(tmp_path, monkeypatch):
    app = tmp_path / "app"
    profil = tmp_path / "profil"
    app.mkdir()
    profil.mkdir()
    monkeypatch.setattr(pn, "__file__", str(app / "perce_neige_sim.py"))
    monkeypatch.setattr(pn, "_donnees_reprises", False)
    return app, profil


def test_deplacement_vers_le_profil(tmp_path, monkeypatch):
    app, profil = _preparer(tmp_path, monkeypatch)
    (app / "reglages_rapports.json").write_text('{"envoi_autorise": true}')
    (app / "exploitation.db").write_bytes(b"base")
    (app / "_rapports").mkdir()
    (app / "_rapports" / "1.json").write_text("{}")
    (app / "_crash_natif.log").write_text("trace")
    pn._reprendre_donnees_kit(profil)
    assert (profil / "reglages_rapports.json").read_text() == '{"envoi_autorise": true}'
    assert (profil / "exploitation.db").read_bytes() == b"base"
    assert (profil / "_rapports" / "1.json").exists()
    assert (profil / "_crash_natif.log").read_text() == "trace"
    # déplacés, pas copiés : plus rien dans le dossier d'installation
    for nom in ("reglages_rapports.json", "exploitation.db", "_rapports", "_crash_natif.log"):
        assert not (app / nom).exists(), nom


def test_rien_n_est_ecrase(tmp_path, monkeypatch):
    app, profil = _preparer(tmp_path, monkeypatch)
    (profil / "reglages.json").write_text("profil")
    (app / "reglages.json").write_text("ancien")
    (profil / "challenge_best.json").write_text("{}")
    (app / "challenge_best.json").write_text("{}")
    (profil / "_rapports").mkdir()
    (profil / "_rapports" / "a.json").write_text("profil")
    (app / "_rapports").mkdir()
    (app / "_rapports" / "a.json").write_text("app")
    (app / "_rapports" / "b.json").write_text("app")
    pn._reprendre_donnees_kit(profil)
    assert (profil / "reglages.json").read_text() == "profil"
    assert (profil / "reglages.json.ancien").read_text() == "ancien"      # gardé à côté
    assert not (app / "challenge_best.json").exists()                    # identique : retiré
    assert (profil / "_rapports" / "a.json").read_text() == "profil"
    assert (profil / "_rapports" / "b.json").read_text() == "app"         # fusionné
    assert (app / "_rapports" / "a.json").read_text() == "app"            # jamais perdu


def test_fichier_tenu_copie_puis_reessai(tmp_path, monkeypatch):
    """Fichier verrouillé (autre copie ouverte sous Windows) : copié pour
    l'instant, déplacé à un lancement suivant."""
    app, profil = _preparer(tmp_path, monkeypatch)
    (app / "reglages.json").write_text("x")
    monkeypatch.setattr(pn, "_deplacer", lambda a, b, essais=3: False)
    monkeypatch.setattr(pn.time, "sleep", lambda s: None)
    pn._reprendre_donnees_kit(profil)
    assert (profil / "reglages.json").read_text() == "x"
    assert (app / "reglages.json").exists()
    monkeypatch.undo()                                                    # lancement suivant
    monkeypatch.setattr(pn, "__file__", str(app / "perce_neige_sim.py"))
    monkeypatch.setattr(pn, "_donnees_reprises", False)
    pn._reprendre_donnees_kit(profil)
    assert not (app / "reglages.json").exists()                          # identique : retiré


def test_paquet_ecrit_dans_le_profil(tmp_path, monkeypatch):
    """Dans le paquet du kit, ce que le programme écrivait « à côté de lui »
    (rapports, accord) va dans le profil, jamais dans app/."""
    monkeypatch.setattr(pn, "_paquet_du_kit", lambda: True)
    monkeypatch.setattr(pn, "_persistent_data_dir", lambda: tmp_path / "profil")
    assert _WRITABLE_DIR() == tmp_path / "profil"
