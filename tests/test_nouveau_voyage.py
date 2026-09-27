"""R après un arrêt en tunnel : le nouveau voyage repart d'une GARE.

Retour d'essai 2026-09-27 : « quand j'appuie sur R pour faire un nouveau
voyage quand tout est cassé au milieu, des fois il repart de l'endroit où il
est ». Cause : l'affaissement d'embarquement s'ancre dès que la rame est
immobilisée hors voyage (tambour serré après une panne catastrophique), et
new_trip() ne le désarmait pas — le premier pas de physique ramenait la rame
à l'ancrage.

Exécution : QT_QPA_PLATFORM=offscreen pytest tests/test_nouveau_voyage.py -v
"""
import os
import sys
import types

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import perce_neige_sim as pn  # noqa: E402

DT = 1.0 / 60.0


class _Muet:
    """Système sonore factice : toute méthode est un no-op."""

    def __getattr__(self, name):
        return lambda *a, **k: None


def _fake_widget(st):
    w = types.SimpleNamespace(
        state=st, sounds=_Muet(), _welcome_played=False,
        _was_stopped_mid_tunnel=False, _mid_tunnel_stop_timer=0.0,
        _last_panne_kind="", _doors_quip_played=False, _brake_snd_played=False,
        _arrival_played=False, _load_challenge_best=lambda: 0.0)
    return w


def _arret_en_tunnel(s0: float):
    st = pn.GameState()
    st.mode = pn.MODE_RUN
    tr = st.train
    tr.direction = 1
    tr.s = s0
    tr.v = 0.0
    tr.maint_brake = True          # tambour serré par la séquence de panne
    tr.doors_open = False
    st.trip_started = False        # voyage suspendu
    tr.trip_started = False
    ph = pn.Physics(st)
    for _ in range(120):
        ph.step(DT)
    return st, ph


def test_affaissement_ancre_en_tunnel():
    st, _ = _arret_en_tunnel(1518.8)
    assert abs(st.sag_anchor_s - 1518.8) < 0.5


def test_r_repart_de_la_gare():
    st, ph = _arret_en_tunnel(1518.8)
    tr = st.train
    pn.GameWidget.new_trip(_fake_widget(st))
    assert abs(tr.s - pn.START_S) < 0.01
    for _ in range(120):
        ph.step(DT)
    assert abs(tr.s - pn.START_S) < 1.0, tr.s
    assert abs(st.sag_anchor_s - pn.START_S) < 1.0


def test_r_en_descente_repart_du_haut():
    st, ph = _arret_en_tunnel(2200.0)
    st.selected_direction = -1
    tr = st.train
    pn.GameWidget.new_trip(_fake_widget(st))
    for _ in range(120):
        ph.step(DT)
    assert abs(tr.s - pn.STOP_S) < 1.0, tr.s
