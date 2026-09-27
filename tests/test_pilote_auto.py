"""Pilote automatique du voyage (touche A) : un voyage complet tout seul.

Retour d'essai 2026-09-27 : « le bouton auto ne sert à rien » — il ne
faisait que basculer un drapeau que rien ne lisait. Ce test fait tourner la
fenêtre entière hors écran, avec une horloge factice, appuie A à quai et
vérifie que la rame part, tient 100 %, arrive, et que le pilote se désengage.

Exécution : QT_QPA_PLATFORM=offscreen pytest tests/test_pilote_auto.py -v
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


def _key(win, k):
    win.game.keyPressEvent(QKeyEvent(QEvent.Type.KeyPress, k, Qt.KeyboardModifier.NoModifier))


def test_voyage_complet_sous_pilote_auto(fenetre):
    win, clock = fenetre
    g = win.game
    st = g.state
    g.new_trip()
    st.mode = pn.MODE_RUN
    tr = st.train
    assert not tr.autopilot                   # plus engagé par défaut
    _step(win, clock, 1.0)
    _key(win, Qt.Key.Key_A)
    assert tr.autopilot
    _step(win, clock, 90.0)                   # portes, PRÊT, DÉPART, buzzer
    assert st.trip_started, "la rame n'est pas partie"
    assert tr.speed_cmd == 1.0
    t = 0.0
    while not st.finished and t < 480.0:
        _step(win, clock, 5.0)
        t += 5.0
    assert st.finished, f"pas arrivée après {t:.0f} s (s={tr.s:.0f})"
    assert not tr.autopilot                   # rend la main à l'arrivée


def test_reprise_manuelle_desengage(fenetre):
    win, clock = fenetre
    g = win.game
    st = g.state
    g.new_trip()
    st.mode = pn.MODE_RUN
    tr = st.train
    _key(win, Qt.Key.Key_A)
    _step(win, clock, 90.0)
    assert st.trip_started and tr.autopilot
    g._key_state.add(Qt.Key.Key_Down)         # le conducteur baisse la consigne
    _step(win, clock, 0.5)
    g._key_state.discard(Qt.Key.Key_Down)
    assert not tr.autopilot
