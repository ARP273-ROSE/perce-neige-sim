"""Élasticité du câble en marche — retour d'essai du 2026-10-04.

Kevin : « la rame oscille déjà au ralenti quand elle rentre, pas juste
après l'arrêt, et quand elle part du bas elle oscille aussi à
l'accélération ». Le mouvement intégré (tr.s) est celui du câble à la
poulie ; chaque rame s'en écarte élastiquement (st.el_x1 / el_x2), avec une
raideur EA/L qui dépend du câble déroulé (audit_physique/elasticite_cable.sage).

Exécution : QT_QPA_PLATFORM=offscreen pytest tests/test_elasticite_cable.py -v
"""
import os
import sys
from pathlib import Path

import pytest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

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


def _lancer(win, s0, v0, sens, pax=334):
    g = win.game
    st = g.state
    g.new_trip()
    st.mode = pn.MODE_RUN
    st.run_mode = "normal"
    tr = st.train
    tr.pax_car1, tr.pax_car2, st.ghost_pax = pax // 2, pax - pax // 2, 0
    tr.direction = sens
    st.selected_direction = sens
    tr.s, tr.v = s0, v0
    tr.maint_brake = tr.doors_open = tr.doors_cmd = tr.doors_visual_open = False
    tr.trip_started = st.trip_started = True
    tr.speed_cmd, tr.speed_cmd_eff = 1.0, abs(v0)
    return g, st, tr


def test_depart_du_bas_la_rame_traine_et_oscille(fenetre):
    win, clock = fenetre
    g, st, tr = _lancer(win, pn.START_S, 0.0, +1)
    xs, tens = [], []
    for _ in range(int(30 / DT)):
        clock[0] += DT
        g._tick()
        xs.append(st.el_x1)
        tens.append(tr.tension_dan)
    # retard sur la poulie à l'accélération (≈ m·a/k : 58 cm à 0,30 m/s²)
    assert min(xs) < -0.40, f"retard maxi {min(xs)*100:.0f} cm"
    # et ça oscille autour : le retard n'est pas monotone
    creux = sum(1 for i in range(1, len(xs) - 1) if xs[i] < xs[i - 1] and xs[i] < xs[i + 1])
    assert creux >= 2, "pas d'oscillation pendant l'accélération"
    # la tension suit (dizaines de kN)
    assert max(tens) - min(tens) > 1500.0


def test_entree_en_gare_basse_au_ralenti_ca_oscille(fenetre):
    win, clock = fenetre
    g, st, tr = _lancer(win, pn.START_S + 300.0, -12.0, -1)
    amp_ralenti = 0.0
    for _ in range(int(70 / DT)):
        clock[0] += DT
        g._tick()
        if abs(abs(tr.v) - pn.CREEP_V) < 0.02 and not st.finished:
            amp_ralenti = max(amp_ralenti, abs(st.el_x1))
    assert amp_ralenti > 0.15, f"au ralenti : ±{amp_ralenti*100:.0f} cm seulement"


def test_en_haut_la_rame_ne_bouge_quasiment_pas(fenetre):
    win, clock = fenetre
    g, st, tr = _lancer(win, pn.STOP_S - 300.0, 12.0, +1)
    amp = 0.0
    for _ in range(int(60 / DT)):
        clock[0] += DT
        g._tick()
        if tr.s > pn.STOP_S - 40.0:
            amp = max(amp, abs(st.el_x1))
    assert amp < 0.03, f"±{amp*100:.1f} cm en gare haute"


def test_cable_rompu_plus_d_ecart_elastique():
    st = pn.GameState()
    ph = pn.Physics(st)
    st.el_x1, st.el_v1 = 0.4, 0.1
    st.train.cable_rupture = True
    ph._elastic_step(DT, 0.3)
    assert st.el_x1 == 0.0 and st.el_v1 == 0.0
