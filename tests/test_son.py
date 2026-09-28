"""Son d'ambiance PC — retour d'essai du 2026-09-28 : « à la décélération,
sous 1 m/s, aucun son d'ambiance, c'est net sur le PC » (non reproduit sous
Linux, niveaux mesurés conformes).

Les boucles d'ambiance se fiaient à un drapeau « ça joue » jamais vérifié
auprès de Qt. Si Windows coupe une voix, la boucle de croisière est relancée
au prochain arrêt, mais la boucle LENTE ne l'est jamais. Un chien de garde
les relance, et un diagnostic part au point de collecte.

Exécution : QT_QPA_PLATFORM=offscreen pytest tests/test_son.py -v
"""
import json
import os
import sys
from pathlib import Path

import pytest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from PyQt6.QtWidgets import QApplication  # noqa: E402

import perce_neige_sim as pn  # noqa: E402

QSoundEffect = pn.QSoundEffect


class FauxLecteur:
    """QSoundEffect minimal : ce que Windows ferait d'une voix coupée."""

    def __init__(self, joue=False):
        self._joue = joue
        self._vol = 0.0
        self.lectures = 0

    def isPlaying(self):  # noqa: N802
        return self._joue

    def status(self):
        return QSoundEffect.Status.Ready

    def play(self):
        self._joue = True
        self.lectures += 1

    def stop(self):
        self._joue = False

    def volume(self):
        return self._vol

    def setVolume(self, v):  # noqa: N802
        self._vol = v

    def isMuted(self):  # noqa: N802
        return False

    def loopsRemaining(self):  # noqa: N802
        return -2

    def source(self):
        from PyQt6.QtCore import QUrl
        return QUrl.fromLocalFile("/x/real_cruise_loop_v2.wav")


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
    if not win.game.sounds.enabled:
        pytest.skip("système son indisponible")
    yield win, clock
    win.close()
    app.processEvents()


def test_chien_de_garde_relance_la_boucle_lente_coupee(fenetre):
    win, _ = fenetre
    snd = win.game.sounds
    vrai = snd._amb_player
    faux = FauxLecteur(joue=False)
    try:
        snd._amb_player = faux
        snd._amb_playing = True            # le code croit que ça joue…
        snd._wd_relances = {}
        for _ in range(40):                # … 0,67 s de décélération à 0,7 m/s
            snd.update_ambient(0.7, 1.0 / 60.0)
        assert faux.lectures == 1, "la boucle lente coupée n'a pas été relancée"
        assert snd._wd_relances.get("lente") == 1
        for _ in range(60):                # elle rejoue : plus de relance
            snd.update_ambient(0.7, 1.0 / 60.0)
        assert faux.lectures == 1
    finally:
        snd._amb_player = vrai


def test_diagnostic_son_serialisable(fenetre):
    win, _ = fenetre
    d = win.game.sounds.diagnostic(0.8)
    json.dumps(d)
    for cle in ("drapeaux", "cibles", "boucle_lente", "boucle_croisiere",
                "moteur", "relances", "fichier_lente", "gain_ambiance"):
        assert cle in d, cle
    assert d["fichier_lente"]["nom"] == "real_cruise_loop_v2.wav"


def test_diagnostic_envoye_a_la_deceleration_sous_1_ms(fenetre, monkeypatch):
    win, clock = fenetre
    g = win.game
    st = g.state
    envois = []
    import reporting
    monkeypatch.setattr(reporting, "envoyer",
                        lambda genre, **k: envois.append((genre, k)) or {})
    g._diag_son_envoye = set()
    g._diag_t = 0.0
    g.sounds._diag_boucle_relancee = False
    st.trip_started = True
    st.finished = False
    for v in [1.4, 1.2, 1.05, 0.98, 0.9] + [0.8] * 150:
        st.train.v = v
        g._diagnostic_son_tick(1.0 / 60.0)
    motifs = [k["motif"] for genre, k in envois if genre == "diagnostic_son"]
    assert motifs == ["deceleration_sous_1_ms"], motifs
    releves = envois[0][1]["releves"]
    assert len(releves) == 2 and releves[0]["v"] < 1.0
    # une seule fois par session
    for v in [1.5, 0.5] * 5:
        st.train.v = v
        g._diagnostic_son_tick(1.0 / 60.0)
    assert len(envois) == 1
