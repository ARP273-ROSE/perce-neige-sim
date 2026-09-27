"""Portes : temporisations calées sur le clip de fermeture (2026-09-27).

La fermeture est une séquence en série (annonce → buzzer → clip) dont on ne
connaît pas la durée d'avance : les vantaux et l'interlock ne comptent qu'à
partir du DÉBUT DU CLIP, signalé par le lecteur (on_step("motion")).

Exécution : QT_QPA_PLATFORM=offscreen pytest tests/test_portes.py -v
"""
import os
import sys
import types

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import perce_neige_sim as pn  # noqa: E402

DT = 1.0 / 60.0


class _Sons:
    """Lecteur factice : garde le rappel on_step pour le déclencher quand le
    « clip » démarre, comme le vrai lecteur au début de door_motion.wav."""

    def __init__(self) -> None:
        self.on_step = None
        self.motion_played = 0

    def play_doors_close_sequence(self, lang="fr", on_complete=None,
                                  on_step=None) -> None:
        self.on_step = on_step

    def play_door_motion(self) -> None:
        self.motion_played += 1


def _widget():
    w = types.SimpleNamespace(sounds=_Sons())
    w.begin_doors_open = types.MethodType(pn.GameWidget.begin_doors_open, w)
    w.begin_doors_close = types.MethodType(pn.GameWidget.begin_doors_close, w)
    return w


def _run(tr, seconds: float) -> None:
    t = 0.0
    while t < seconds - 1e-9:
        pn.advance_door_timers(tr, DT)
        t += DT


def test_fermeture_suit_le_clip():
    w = _widget()
    tr = pn.Train()
    tr.doors_open = tr.doors_cmd = tr.doors_visual_open = True
    w.begin_doors_close(tr, "fr")
    # annonce + buzzer : 14,4 s sans que rien ne bouge
    _run(tr, 14.4)
    assert tr.doors_open and tr.doors_visual_open
    # début du clip
    w.sounds.on_step("motion")
    _run(tr, pn.DOOR_MOTION_LEAD - 0.1)
    assert tr.doors_visual_open           # vantaux pas encore partis
    _run(tr, 0.2)
    assert not tr.doors_visual_open       # vantaux partis à 1,3 s
    assert tr.doors_open                  # interlock encore ouvert
    _run(tr, pn.DOOR_CLOSE_TIME - pn.DOOR_MOTION_LEAD)
    assert not tr.doors_open              # butée à 5,3 s


def test_filet_sans_lecteur():
    w = _widget()
    tr = pn.Train()
    tr.doors_open = tr.doors_cmd = tr.doors_visual_open = True
    w.begin_doors_close(tr, "fr")         # le lecteur ne rappelle jamais
    _run(tr, pn.DOOR_CLOSE_PENDING + 0.1)
    assert not tr.doors_open and not tr.doors_visual_open


def test_reouverture_pendant_la_sequence():
    """Le conducteur rouvre avant le clip : le rappel tardif ne ferme rien."""
    w = _widget()
    tr = pn.Train()
    tr.doors_open = tr.doors_cmd = tr.doors_visual_open = True
    w.begin_doors_close(tr, "fr")
    on_step = w.sounds.on_step
    _run(tr, 3.0)
    w.begin_doors_open(tr)
    on_step("motion")
    _run(tr, 10.0)
    assert tr.doors_open and tr.doors_visual_open


def test_ouverture():
    w = _widget()
    tr = pn.Train()
    tr.doors_open = tr.doors_cmd = tr.doors_visual_open = False
    w.begin_doors_open(tr)
    assert w.sounds.motion_played == 1
    _run(tr, pn.DOOR_MOTION_LEAD + 0.05)
    assert tr.doors_visual_open and not tr.doors_open
    _run(tr, pn.DOOR_OPEN_TIME)
    assert tr.doors_open


def test_lecteur_muet_rappelle_tout_de_suite():
    """SoundSystem désactivé : on_step("motion") part immédiatement, sinon
    les portes ne se fermeraient jamais sans son."""
    ss = pn.SoundSystem.__new__(pn.SoundSystem)
    ss.enabled = False
    ss._close_seq_active = False
    seen = []
    ss.play_doors_close_sequence(lang="fr", on_step=seen.append)
    assert seen == ["motion"]
