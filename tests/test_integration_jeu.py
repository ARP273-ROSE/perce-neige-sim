"""Audit d'intégration du 24/11/2026 (« c'est encore trop split entre le pilotage du Perce-Neige et tout le reste ») :
vue 3D plein écran par défaut, touches des jeux (E agir, M carte, H / C / K pour le véhicule où l'on est), pas de F11.

Exécution : QT_QPA_PLATFORM=offscreen pytest tests/test_integration_jeu.py -v
"""
import os
import sys
from pathlib import Path

import pytest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

ICI = Path(__file__).resolve().parent.parent
SCRIPTS = ICI / "godot_project" / "scripts"


@pytest.fixture(scope="module")
def jeu(tmp_path_factory):
    from PyQt6.QtWidgets import QApplication
    import perce_neige_sim as pn
    app = QApplication.instance() or QApplication(sys.argv)
    data = tmp_path_factory.mktemp("pn_integ")
    pn._persistent_data_dir = lambda: Path(data)
    pn._writable_dir = lambda: Path(data)
    try:
        win = pn.MainWindow()
    except Exception as e:
        pytest.skip(f"MainWindow impossible hors écran : {e}")
    win.game.sounds.enabled = False
    yield pn, win.game
    win.close()
    app.processEvents()


def test_vue_3d_plein_ecran_par_defaut(jeu):
    _pn, g = jeu
    g._cabin_view_state = 2
    g._plein_cadre_force = None
    assert g._plein_cadre_3d(), "la vue 3D plein écran doit être la vue par défaut"
    g._plein_cadre_force = False                 # F12 / Échap : le poste du Perce-Neige
    assert not g._plein_cadre_3d()
    g._cabin_view_state = 0                      # sans 3D : le poste
    g._plein_cadre_force = None
    assert not g._plein_cadre_3d()


def test_plus_de_f11_ni_plein_ecran(jeu):
    pn, _g = jeu
    assert "ecran" not in pn.BarrePleinCadre.CLES
    src = (ICI / "perce_neige_sim.py").read_text(encoding="utf-8")
    assert "Key_F11" not in src and "def basculer_plein_ecran" not in src


def test_touches_relayees_a_la_3d(jeu):
    pn, g = jeu
    # C, H, K ne sont plus gardés pour le Perce-Neige en skieur : ils vont au véhicule où l'on est
    from PyQt6.QtCore import Qt
    assert int(Qt.Key.Key_C) not in g.SKIEUR_GARDE
    src = (ICI / "perce_neige_sim.py").read_text(encoding="utf-8")
    assert 'state_dict["skieur_cmd"]' in src and 'state_dict["skieur_carte"]' in src
    sr = (SCRIPTS / "state_receiver.gd").read_text(encoding="utf-8")
    assert "main.agir()" in sr and "main.commande_vehicule(" in sr and "basculer_carte()" in sr


def test_3d_agir_piloter_commandes():
    mg = (SCRIPTS / "main.gd").read_text(encoding="utf-8")
    for f in ("func agir()", "func piloter()", "func commande_vehicule(nom: String)"):
        assert f in mg
    cs = (SCRIPTS / "commandes_skieur.gd").read_text(encoding="utf-8")
    assert '_bouton("PILOTER"' in cs and "func basculer_carte()" in cs
    ex = (SCRIPTS / "exploitation_remontee.gd").read_text(encoding="utf-8")
    assert '"funival": ["phares", "eclairage", "klaxon"]' in ex and '"cmd_vehicule"' in ex
    sj = (SCRIPTS / "skieur_joueur.gd").read_text(encoding="utf-8")
    assert "const V_COURSE: float = 16.0 / 3.6" in sj and "var course: bool = true" in sj


def test_boutons_du_vehicule_au_pupitre(jeu):
    from PyQt6.QtCore import QRectF
    from PyQt6.QtGui import QImage, QPainter
    _pn, g = jeu
    g._recevoir_remontee({"id": "funival", "nom": "Funival", "groupe": "funival", "v": 0.0, "v_nom": 12.0,
                          "kw": 0.0, "etat": "arret_normal", "mode": "auto", "evts": [],
                          "cmd_vehicule": ["phares", "eclairage", "klaxon"], "phares_on": True, "eclairage_on": False})
    img = QImage(400, 760, QImage.Format.Format_ARGB32)
    p = QPainter(img)
    try:
        g._draw_hud_remontee(p, QRectF(0, 0, 390, 740))
    finally:
        p.end()
    cmds = {a[1] for _r, a in g._zones_remontee if a[0] == "cmd"}
    assert {"phares", "eclairage", "klaxon"} <= cmds
