"""Mode Défi (retour d'utilisateur, 09/10/2026) : « on ne peut pas partir les portes
ouvertes même si PRÊT est activé, et on ne peut pas les ouvrir au milieu du
tunnel à pleine vitesse » — en Défi, plus aucun verrou de porte : départ
sauvage sur PRÊT portes ouvertes, ouverture en pleine voie, avec piques."""
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


def _step(win, clock, s):
    for _ in range(int(s * 60)):
        clock[0] += DT
        win.game._tick()


def _key(win, k):
    win.game.keyPressEvent(QKeyEvent(QEvent.Type.KeyPress, k, Qt.KeyboardModifier.NoModifier))
    win.game.keyReleaseEvent(QKeyEvent(QEvent.Type.KeyRelease, k, Qt.KeyboardModifier.NoModifier))


def test_defi_depart_portes_ouvertes_puis_ouverture_en_ligne(fenetre):
    win, clock = fenetre
    g = win.game
    st = g.state
    if g.auto_ops.enabled:
        g.auto_ops.toggle()
    g.new_trip()
    st.mode = pn.MODE_RUN
    st.run_mode = "challenge"
    tr = st.train
    _step(win, clock, 1.0)
    if not tr.doors_cmd:
        _key(win, Qt.Key.Key_D)
        _step(win, clock, 12.0)
    assert tr.doors_open
    tr.speed_cmd = 11.0 / 15.0
    _key(win, Qt.Key.Key_V)            # PRÊT, portes ouvertes
    _step(win, clock, 40.0)
    assert st.trip_started, "PRÊT armé portes ouvertes : départ sauvage attendu"
    # porte fermée en route puis rouverte en pleine voie
    if tr.doors_cmd:
        _key(win, Qt.Key.Key_D)
        _step(win, clock, 12.0)
    _step(win, clock, 30.0)
    assert abs(tr.v) > 3.0 and pn.START_S + 50 < tr.s < pn.STOP_S - 50
    _key(win, Qt.Key.Key_D)
    _step(win, clock, 0.5)
    assert tr.doors_cmd, "ouverture en pleine voie refusée en Défi"
    # … et la rame CONTINUE, portes ouvertes (retour d'utilisateur, 11/10/2026 :
    # « quand j'ouvre les portes en roulant, ça marche mais le funi s'arrête »)
    v_avant = abs(tr.v)
    _step(win, clock, 10.0)
    assert abs(tr.v) > 0.6 * v_avant, f"la rame s'arrête portes ouvertes : {abs(tr.v):.1f} m/s"


def test_arrivee_normale_sans_pique_de_survitesse(fenetre):
    """Une arrivée normale (pilote auto) ne déclenche PAS la pique
    « arrivée trop rapide » ; une arrivée à 10 m/s à 40 m du repère, si."""
    win, clock = fenetre
    g = win.game
    st = g.state
    if g.auto_ops.enabled:
        g.auto_ops.toggle()
    st.run_mode = "normal"
    g.new_trip()
    st.mode = pn.MODE_RUN
    _step(win, clock, 1.0)
    textes = {fr for fr, _en in pn.SURVITESSE_ARRIVEE_QUIPS}
    vus = set()
    _key(win, Qt.Key.Key_A)                 # pilote automatique : un voyage complet
    for _ in range(600):
        _step(win, clock, 1.0)
        vus |= {e.message_fr for e in st.events if e.key == "doors_quip"}
        if st.finished:
            break
    assert st.finished, "le voyage du pilote auto n'est pas arrivé"
    assert not (vus & textes), f"pique d'arrivée à tort : {vus & textes}"


def test_defi_ouverture_en_croisiere_la_rame_continue(fenetre):
    win, clock = fenetre
    g = win.game
    st = g.state
    if g.auto_ops.enabled:
        g.auto_ops.toggle()
    g.new_trip()
    st.mode = pn.MODE_RUN
    st.run_mode = "challenge"
    tr = st.train
    _step(win, clock, 1.0)
    if tr.doors_cmd:
        _key(win, Qt.Key.Key_D)
        _step(win, clock, 15.0)
    tr.speed_cmd = 11.0 / 15.0          # en Défi la consigne va jusqu'à 15 m/s
    _key(win, Qt.Key.Key_V)
    _step(win, clock, 90.0)
    assert st.trip_started and abs(tr.v) > 8.0
    v0 = abs(tr.v)
    _key(win, Qt.Key.Key_D)
    _step(win, clock, 10.0)
    assert abs(tr.v) > 0.6 * v0, "la rame s'arrête quand on ouvre les portes en roulant"


def test_pret_remonte_la_consigne_hors_defi(fenetre):
    """Mode normal, consigne à 0 (après un Défi, une urgence) : PRÊT la remonte
    à 100 % et lance le départ ; en Défi, refus « la monter d'abord »
    (retour d'utilisateur, 12/10/2026 : « impossible d'appuyer sur PRÊT car
    consigne à 0 »)."""
    win, clock = fenetre
    g = win.game
    st = g.state
    if g.auto_ops.enabled:
        g.auto_ops.toggle()
    st.run_mode = "challenge"
    g.new_trip()
    st.mode = pn.MODE_RUN
    tr = st.train
    _step(win, clock, 1.0)
    tr.speed_cmd = 0.0
    _key(win, Qt.Key.Key_V)
    _step(win, clock, 1.0)
    assert tr.speed_cmd == 0.0 and not st.trip_started, "en Défi, la consigne reste au conducteur"
    st.run_mode = "normal"
    g.new_trip()
    st.mode = pn.MODE_RUN
    _step(win, clock, 1.0)
    if tr.doors_open or tr.doors_cmd:        # procédure : portes (D), puis PRÊT (V)
        _key(win, Qt.Key.Key_D)
        _step(win, clock, 15.0)
    tr.speed_cmd = 0.0
    _key(win, Qt.Key.Key_V)
    _step(win, clock, 8.0)
    assert tr.speed_cmd == 1.0, "PRÊT doit remonter la consigne à 100 % en mode normal"
    _step(win, clock, 40.0)
    assert st.trip_started, "le départ doit partir"
