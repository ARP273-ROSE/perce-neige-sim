"""Retour de la vue 3D vers le PC (07/10/2026) : boutons du pupitre 3D et
mode skieur.

Kevin : « sur le PC, les boutons marchent mais il ne se passe rien ensuite,
le bouton éclairage cabine ne marche pas, alors que dans la PWA ça
fonctionne ; là je fais fermer les portes et rien ne se passe » ; « comment
je passe en mode skieur sur le PC ? ».

La vue 3D est remplacée par un faux pont (GodotBridge) : on lui fait
« envoyer » les messages que la 3D enverrait.

Exécution : QT_QPA_PLATFORM=offscreen pytest tests/test_retour_3d.py -v
"""
import os
import sys
from pathlib import Path

import pytest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from PyQt6.QtCore import QEvent, Qt  # noqa: E402
from PyQt6.QtGui import QKeyEvent  # noqa: E402
from PyQt6.QtWidgets import QApplication  # noqa: E402

import perce_neige_sim as pn  # noqa: E402

DT = 1.0 / 60.0


class FauxPont:
    """Remplace GodotBridge : la « 3D » tourne, on lui lit l'état envoyé
    et on lui fait poster des messages."""

    def __init__(self):
        self.a_poster = []
        self.etats = []
        self.bundled_dir = None

    def is_running(self):
        return True

    def poll_messages(self):
        out, self.a_poster = self.a_poster, []
        return out

    def send_state(self, d):
        self.etats.append(d)

    def is_available(self):
        return True, ""

    def find_window_id_once(self):
        return None

    def stop(self):
        pass


@pytest.fixture(scope="module")
def fenetre(tmp_path_factory):
    app = QApplication.instance() or QApplication(sys.argv)
    data = tmp_path_factory.mktemp("pn")
    pn._persistent_data_dir = lambda: Path(data)
    pn._writable_dir = lambda: Path(data)
    clock = [1000.0]
    pn.time.monotonic = lambda: clock[0]
    try:
        win = pn.MainWindow()
    except Exception as e:  # pas d'audio, pas de base : on ne teste pas ici
        pytest.skip(f"MainWindow impossible hors écran : {e}")
    win.game.sounds.enabled = False
    yield win, clock
    win.close()
    app.processEvents()


def _step(win, clock, seconds):
    for _ in range(int(seconds * 60)):
        clock[0] += DT
        win.game._tick()


def _brancher(g):
    """Faux pont + vue 3D affichée (état 2), sans fenêtre embarquée."""
    pont = FauxPont()
    g._godot_bridge = pont
    g._cabin_view_state = 2
    g._sync_godot_overlay_visibility = lambda: None
    return pont


def _depart_a_quai(win, clock):
    g = win.game
    if g.auto_ops.enabled:
        g.auto_ops.toggle()
    g._skieur = False
    g.new_trip()
    g.state.mode = pn.MODE_RUN
    _step(win, clock, 1.0)
    return g


def test_pupitre_3d_eclairage_portes_klaxon(fenetre):
    win, clock = fenetre
    g = _depart_a_quai(win, clock)
    pont = _brancher(g)
    tr = g.state.train
    # éclairage cabine : chaque appui bascule, comme C
    avant = tr.lights_cabin
    pont.a_poster = [{"pupitre": "cabine", "enfonce": True},
                     {"pupitre": "cabine", "enfonce": False}]
    _step(win, clock, 0.1)
    assert tr.lights_cabin != avant
    # portes : ouverture si fermées, fermeture si ouvertes (comme D)
    if not tr.doors_cmd:
        pont.a_poster = [{"pupitre": "ouverture_0", "enfonce": True}]
        _step(win, clock, 12.0)
        assert tr.doors_cmd
    pont.a_poster = [{"pupitre": "ouverture_1", "enfonce": True}]   # déjà ouvertes : rien
    _step(win, clock, 0.1)
    assert tr.doors_cmd
    pont.a_poster = [{"pupitre": "fermeture_0", "enfonce": True}]
    _step(win, clock, 0.1)
    assert not tr.doors_cmd, "« je fais fermer les portes et rien ne se passe »"
    # klaxon : tenu tant que le bouton est enfoncé
    pont.a_poster = [{"pupitre": "klaxon", "enfonce": True}]
    _step(win, clock, 0.5)
    assert tr.horn
    pont.a_poster = [{"pupitre": "klaxon", "enfonce": False}]
    _step(win, clock, 0.1)
    assert not tr.horn
    # −VITE / +VITE : tenus comme les flèches
    pont.a_poster = [{"pupitre": "vite_plus", "enfonce": True}]
    _step(win, clock, 0.1)
    assert Qt.Key.Key_Up in g._mouse_hold
    pont.a_poster = [{"pupitre": "vite_plus", "enfonce": False}]
    _step(win, clock, 0.1)
    assert Qt.Key.Key_Up not in g._mouse_hold


def test_skieur_f9_auto_attend_puis_ferme(fenetre):
    win, clock = fenetre
    g = _depart_a_quai(win, clock)
    pont = _brancher(g)
    ao = g.auto_ops
    g.keyPressEvent(QKeyEvent(QEvent.Type.KeyPress, Qt.Key.Key_F9,
                              Qt.KeyboardModifier.NoModifier))
    assert g._skieur, "F9 n'a pas lancé le mode skieur"
    assert ao.enabled and ao.force_any_hours, "le funiculaire doit tourner tout seul"
    _step(win, clock, 0.2)
    assert pont.etats[-1]["skieur"] is True
    # touches de marche transmises à la 3D (bits de skieur_joueur.gd)
    g._key_state.update({Qt.Key.Key_Z, Qt.Key.Key_Shift})
    assert g._skieur_touches() == 1 | 16
    g._key_state.clear()
    # embarquement : le skieur attend sur le quai → la rame l'attend
    t = 0.0
    while ao.phase != ao.PHASE_BOARDING and t < 120.0:
        _step(win, clock, 1.0)
        t += 1.0
    assert ao.phase == ao.PHASE_BOARDING, ao.phase
    pont.a_poster = [{"skieur_etat": [False, True, 1]}]
    _step(win, clock, ao.station_dwell_s + 30.0)
    assert ao.phase == ao.PHASE_BOARDING, "parti sans le skieur resté sur le quai"
    assert g.sounds.skieur_dehors, "sur le quai : plus de son de cabine"
    # il monte : fermeture des portes dès qu'il est dedans
    pont.a_poster = [{"skieur_etat": [True, False, 0]}]
    _step(win, clock, 2.5)
    assert ao.phase != ao.PHASE_BOARDING, "portes pas fermées alors qu'il est à bord"
    assert not g.sounds.skieur_dehors
    # CONDUIRE (au poste) : fin du mode skieur et de l'AUTO
    pont.a_poster = [{"skieur_conduire": True}]
    _step(win, clock, 0.1)
    assert not g._skieur and not ao.enabled
    assert pont.etats[-1]["skieur"] is False


def test_skieur_refuse_sans_vue_3d(fenetre):
    win, clock = fenetre
    g = _depart_a_quai(win, clock)
    _brancher(g)
    g._cabin_view_state = 0
    g.basculer_skieur()
    assert not g._skieur
