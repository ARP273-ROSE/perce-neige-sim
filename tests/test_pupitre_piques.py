"""Piques des remontées au pupitre du PC (16/11/2026) : la vue 3D envoie la pique tirée dans les deux langues
({"pique_remontee": {n, evt, ligne, fr, en}}) ; le PC l'ajoute au journal et l'affiche quelques secondes en bas du
pupitre de la remontée, dans sa propre langue.

Exécution : QT_QPA_PLATFORM=offscreen pytest tests/test_pupitre_piques.py -v
"""
import os
import sys
from pathlib import Path

import pytest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pupitre_remontee as pr  # noqa: E402

ICI = Path(__file__).resolve().parent.parent
PIQUE = {"n": 3, "evt": "ARRIVEE", "ligne": "TSD6 Marmottes Express",
         "fr": "Arrivé en haut. Maintenant, il faut redescendre.", "en": "Made it up. Now you have to get down."}


# --- modèle (sans Qt) ---

def test_pique_recue_puis_effacee():
    m = pr.ModeleRemontee()
    v0 = m.version
    assert m.recevoir_pique(PIQUE, maintenant=100.0)
    assert m.version > v0
    assert m.pique_active(100.0) == (PIQUE["fr"], PIQUE["en"], PIQUE["ligne"])
    assert m.pique_active(100.0 + m.PIQUE_S - 0.1) is not None
    assert m.pique_active(100.0 + m.PIQUE_S + 0.1) is None


def test_meme_numero_pas_rejoue():
    m = pr.ModeleRemontee()
    assert m.recevoir_pique(PIQUE, maintenant=0.0)
    assert not m.recevoir_pique(PIQUE, maintenant=1.0)
    autre = dict(PIQUE, n=4, fr="Deuxième.", en="Second.")
    assert m.recevoir_pique(autre, maintenant=2.0)
    assert m.pique_active(2.0)[0] == "Deuxième."


def test_une_seule_langue_et_paquets_invalides():
    m = pr.ModeleRemontee()
    assert not m.recevoir_pique(None)
    assert not m.recevoir_pique({"n": 1})
    assert not m.recevoir_pique({"n": 2, "fr": "  ", "en": ""})
    # une seule langue : l'autre la reprend
    assert m.recevoir_pique({"n": 5, "fr": "Seulement en français."}, maintenant=0.0)
    assert m.pique_active(0.0)[:2] == ("Seulement en français.", "Seulement en français.")


# --- côté 3D : la paire est bien envoyée ---

def test_vue_3d_envoie_les_deux_langues():
    main = (ICI / "godot_project" / "scripts" / "main.gd").read_text(encoding="utf-8")
    assert '"pique_remontee"' in main
    assert '"fr": paire[0]' in main and '"en": paire[1]' in main
    pq = (ICI / "godot_project" / "scripts" / "piques_remontees.gd").read_text(encoding="utf-8")
    assert "static func pique_paire(" in pq


# --- PC : journal et dessin ---

@pytest.fixture(scope="module")
def fenetre(tmp_path_factory):
    from PyQt6.QtWidgets import QApplication
    import perce_neige_sim as pn
    app = QApplication.instance() or QApplication(sys.argv)
    data = tmp_path_factory.mktemp("pn")
    pn._persistent_data_dir = lambda: Path(data)
    pn._writable_dir = lambda: Path(data)
    try:
        win = pn.MainWindow()
    except Exception as e:
        pytest.skip(f"MainWindow impossible hors écran : {e}")
    win.game.sounds.enabled = False
    yield pn, win
    win.close()
    app.processEvents()


def test_journal_et_pupitre(fenetre):
    pn, win = fenetre
    g = win.game
    n0 = len(g.state.events)
    g._message_3d({"pique_remontee": dict(PIQUE, n=101)})
    nouveaux = g.state.events[n0:]
    assert any(e.key == "pique" and PIQUE["fr"] in e.message_fr and PIQUE["en"] in e.message_en for e in nouveaux)
    # renvoi du même numéro : pas de doublon au journal
    n1 = len(g.state.events)
    g._message_3d({"pique_remontee": dict(PIQUE, n=101)})
    assert len(g.state.events) == n1
    # pupitre d'une remontée avec la pique en bas : se dessine sans erreur, dans les deux tailles
    from PyQt6.QtCore import QRectF
    from PyQt6.QtGui import QImage, QPainter
    g._recevoir_remontee({"id": "tsd6_marmottes_express", "nom": "TSD6 Marmottes Express", "groupe": "tsd",
                          "desc": "Télésiège débrayable 6 places", "v": 5.0, "v_nom": 5.0, "kw": 300.0,
                          "etat": "marche", "mode": "auto", "evts": []})
    for compact in (False, True):
        img = QImage(520, 900, QImage.Format.Format_ARGB32)
        p = QPainter(img)
        try:
            g._draw_hud_remontee(p, QRectF(0, 0, 520, 900), compact=compact)
        finally:
            p.end()
    assert g._remontee.pique_active() is not None
