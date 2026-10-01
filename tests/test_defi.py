"""Mode Défi — retours d'essai du 2026-09-28.

1. Boutons + et − : « les variations de vitesse sont brusques et
   violentes ». Le régulateur calculait sa commande pour le moteur nominal
   alors que le Défi le surrégime (×1,8) : au-dessus de ~8 m/s la rame
   dépassait la consigne de 0,9 m/s et freinait à 1,1 m/s² au lieu de 0,7.
2. Rupture du câble en montée : « la voiture ralentit et s'arrête alors
   qu'on n'a serré aucun frein, elle devrait repartir dans l'autre sens ».
   La séquence d'incident prenait le passage par v = 0 au sommet de la
   course pour un arrêt et serrait le tambour, qui agit par le câble rompu.

Exécution : QT_QPA_PLATFORM=offscreen pytest tests/test_defi.py -v
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


def _physique(s0, v0, pax=334, cmd=None):
    st = pn.GameState()
    st.mode = pn.MODE_RUN
    st.run_mode = "challenge"
    tr = st.train
    tr.pax_car1 = pax // 2
    tr.pax_car2 = pax - pax // 2
    st.ghost_pax = 0
    tr.direction = 1
    tr.s = s0
    tr.v = v0
    tr.maint_brake = False
    tr.doors_open = False
    tr.trip_started = True
    st.trip_started = True
    tr.speed_cmd = v0 / 15.0 if cmd is None else cmd
    tr.speed_cmd_eff = v0
    return st, pn.Physics(st)


@pytest.mark.parametrize("pas", [+0.35, -0.35])
def test_boutons_plus_moins_suivent_la_consigne(pas):
    st, ph = _physique(1000.0, 10.0)
    tr = st.train
    for _ in range(int(15 / DT)):
        ph.step(DT)
    v_prev, a_pk, v_hi, v_lo = tr.v, 0.0, tr.v, tr.v
    for i in range(int(25 / DT)):
        if i < int(0.4 / DT):                      # bouton tenu 0,4 s
            tr.speed_cmd = max(0.0, min(1.0, tr.speed_cmd + pas * DT))
        ph.step(DT)
        a_pk = max(a_pk, abs(tr.v - v_prev) / DT)
        v_prev = tr.v
        v_hi, v_lo = max(v_hi, tr.v), min(v_lo, tr.v)
    cible = tr.speed_cmd * 15.0
    depasse = (v_hi - cible) if pas > 0 else (cible - v_lo)
    assert depasse < 0.15, f"dépassement de {depasse:.2f} m/s"
    assert abs(tr.v - cible) < 0.1, f"reste à {tr.v:.2f} pour {cible:.2f}"
    assert a_pk < (0.45 if pas > 0 else 0.85), f"|a| pic {a_pk:.2f} m/s²"


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


def _rupture_en_montee(win, clock, maj_apres=None, duree=40.0):
    """Rame pleine lancée à 14,3 m/s en montée : la survitesse +20 % casse
    le câble. `maj_apres` = secondes après la rupture où l'on appuie Maj."""
    g = win.game
    st = g.state
    g.new_trip()
    st.mode = pn.MODE_RUN
    st.run_mode = "challenge"
    tr = st.train
    tr.pax_car1, tr.pax_car2, st.ghost_pax = 167, 167, 0
    tr.direction = 1
    st.selected_direction = 1
    tr.s, tr.v = 1500.0, 14.3
    tr.maint_brake = tr.doors_open = tr.doors_cmd = tr.doors_visual_open = False
    tr.trip_started = st.trip_started = True
    tr.speed_cmd, tr.speed_cmd_eff = 1.0, 15.0
    t, t_r, v_min, s_max = 0.0, None, 0.0, 0.0
    while t < duree and not st.crashed:
        clock[0] += DT
        t += DT
        g._tick()
        if tr.cable_rupture and t_r is None:
            t_r = t
        if t_r is None:
            continue
        if maj_apres is not None and t - t_r > maj_apres and not tr.emergency:
            g.keyPressEvent(QKeyEvent(QEvent.Type.KeyPress, Qt.Key.Key_Shift,
                                      Qt.KeyboardModifier.ShiftModifier))
        v_min = min(v_min, tr.v)
        s_max = max(s_max, tr.s)
    return st, t_r, v_min, s_max


def test_rupture_en_montee_sans_frein_la_rame_redescend(fenetre):
    win, clock = fenetre
    st, t_r, v_min, s_max = _rupture_en_montee(win, clock, duree=25.0)
    assert t_r is not None, "pas de rupture"
    assert v_min < -10.0, f"la rame n'est pas repartie (v mini {v_min:.2f})"
    assert st.train.s < s_max - 50.0, "position figée au sommet de la course"


def test_rupture_puis_urgence_parachute_tient_la_rame(fenetre):
    win, clock = fenetre
    st, t_r, v_min, _ = _rupture_en_montee(win, clock, maj_apres=8.0, duree=45.0)
    tr = st.train
    assert tr.parachute_engaged
    assert abs(tr.v) < 0.01, f"v = {tr.v:.3f}"
    s_tenu = tr.s
    g = win.game
    for _ in range(int(20 / DT)):
        clock[0] += DT
        g._tick()
    assert abs(tr.s - s_tenu) < 0.05, f"glisse de {tr.s - s_tenu:+.2f} m sous parachute"
    assert st.fault_phase != "active", "la séquence d'incident n'a pas démarré"


# --- 2026-10-01 : « quand le câble casse […] la machinerie doit s'arrêter,
# là elle s'emballe ». Les poulies suivaient la rame qui dévale.

def test_rupture_la_machinerie_s_arrete(fenetre):
    win, clock = fenetre
    g = win.game
    st = g.state
    tr = st.train
    g.new_trip()
    st.mode = pn.MODE_RUN
    st.run_mode = "challenge"
    tr.pax_car1, tr.pax_car2, st.ghost_pax = 167, 167, 0
    tr.direction = 1
    st.selected_direction = 1
    tr.s, tr.v = 1500.0, 14.3
    tr.maint_brake = tr.doors_open = tr.doors_cmd = tr.doors_visual_open = False
    tr.trip_started = st.trip_started = True
    tr.speed_cmd, tr.speed_cmd_eff = 1.0, 15.0
    t, t_r, mv_r, mv_max, t_arret = 0.0, None, 0.0, 0.0, None
    while t < 20.0 and not st.crashed:
        clock[0] += DT
        t += DT
        g._tick()
        if tr.cable_rupture and t_r is None:
            t_r, mv_r = t, abs(g._machine_v)
            etat = pn.physics_to_state_dict(tr, st)
            assert etat["cable_rupture"] is True and "ghost_s" in etat
        if t_r is None:
            continue
        mv_max = max(mv_max, abs(g._machine_v))
        if t_arret is None and abs(g._machine_v) < 1e-9:
            t_arret = t - t_r
    assert t_r is not None, "pas de rupture"
    assert mv_max <= mv_r + 1e-9, f"la machinerie accélère ({mv_max:.2f} > {mv_r:.2f} m/s)"
    assert t_arret is not None and abs(t_arret - mv_r / pn.A_DRIVE_TRIP) < 0.1, t_arret
    assert tr.v < -5.0, "la rame décrochée doit dévaler"
    assert g.sounds._machine_speed == 0.0
