"""Arrêt électrique en entrant en gare — retour d'essai du 2026-10-03.

« En mode normal, quand on est au ralenti en entrant en gare, l'arrêt
électrique est inopérant. » Dans les CREEP_DIST derniers mètres, le
régulateur imposait la vitesse de rampement (0,75 m/s) sans regarder la
consigne : l'arrêt électrique, qui ramène la consigne à 0 à 0,45 m/s²,
n'avait plus d'effet et la rame rampait jusqu'au quai.

Exécution : QT_QPA_PLATFORM=offscreen pytest tests/test_arret_electrique.py -v
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
    except Exception as e:
        pytest.skip(f"MainWindow impossible hors écran : {e}")
    win.game.sounds.enabled = False
    yield win, clock
    win.close()
    app.processEvents()


def _approche(win, d_quai, sens):
    """Rame en mode Normal, au rampement, à `d_quai` m de son point d'arrêt."""
    g = win.game
    st = g.state
    g.new_trip()
    st.mode = pn.MODE_RUN
    st.run_mode = "normal"
    tr = st.train
    tr.pax_car1, tr.pax_car2, st.ghost_pax = 60, 60, 40
    tr.direction = sens
    st.selected_direction = sens
    tr.s = (pn.STOP_S - d_quai) if sens > 0 else (pn.START_S + d_quai)
    tr.v = pn.CREEP_V * sens
    tr.maint_brake = tr.doors_open = tr.doors_cmd = tr.doors_visual_open = False
    tr.trip_started = st.trip_started = True
    tr.speed_cmd, tr.speed_cmd_eff = 1.0, pn.CREEP_V
    return g, st, tr


def _rouler(g, clock, duree):
    for _ in range(int(duree / DT)):
        clock[0] += DT
        g._tick()


@pytest.mark.parametrize("sens", [+1, -1])
def test_arret_electrique_au_rampement_arrete_la_rame(fenetre, sens):
    win, clock = fenetre
    g, st, tr = _approche(win, 30.0, sens)
    _rouler(g, clock, 2.0)
    assert abs(tr.v) > 0.5, f"pas de rampement (v = {tr.v:.2f})"
    s0 = tr.s
    g.keyPressEvent(QKeyEvent(QEvent.Type.KeyPress, Qt.Key.Key_3,
                              Qt.KeyboardModifier.NoModifier))
    assert tr.electric_stop
    _rouler(g, clock, 10.0)
    assert abs(tr.v) < 0.02, f"v = {tr.v:.3f} m/s 10 s après l'arrêt électrique"
    # à 0,45 m/s² depuis 0,75 m/s : ~0,6 m ; pas jusqu'au quai (30 m)
    assert abs(tr.s - s0) < 3.0, f"{abs(tr.s - s0):.1f} m parcourus"
    s_arret = tr.s
    _rouler(g, clock, 10.0)
    assert abs(tr.s - s_arret) < 0.05, "la rame glisse après l'arrêt"


def test_sans_arret_electrique_le_rampement_docke_toujours(fenetre):
    win, clock = fenetre
    g, st, tr = _approche(win, 30.0, +1)
    _rouler(g, clock, 90.0)
    assert abs(tr.v) < 0.02
    assert abs(pn.STOP_S - tr.s) < 0.5, f"arrêt à {pn.STOP_S - tr.s:.2f} m du point"
