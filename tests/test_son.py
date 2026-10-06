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

# Sur la CI (runner Linux sans QtMultimedia), le simulateur tourne sans son :
# les tests qui lisent seulement les WAV passent, ceux du lecteur se sautent.
QSoundEffect = getattr(pn, "QSoundEffect", None)


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
    if QSoundEffect is None:
        pytest.skip("QtMultimedia indisponible")
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


# --- 2026-09-30 : les rapports du PC de Kevin ont tranché -----------------
# Boucles bien en lecture (Qt : Ready, isPlaying) mais à 0,136 : plancher de
# fluage 0,45 × atténuation sous le clip de freinage 0,55 × annonce 0,55,
# alors que le clip, à 14-16 s, est quasi muet (−29 dBFS).

FREIN = Path(__file__).resolve().parent.parent / "sons" / "ambients" / "real_brake_approach.wav"


def test_enveloppe_du_clip_de_freinage():
    env = pn._wav_envelope_db(str(FREIN))
    assert 78 <= len(env) <= 81                  # 20 s par pas de 250 ms
    debut = max(env[:8])                         # 2 premières secondes : fort
    fin = sum(env[60:66]) / 6                    # 15 à 16,5 s : faible
    assert debut > -21.0, debut
    assert fin < -26.0, fin


def test_attenuation_suit_le_niveau_du_clip():
    env = pn._wav_envelope_db(str(FREIN))
    assert pn._fx_duck_strength(env, 1000.0) == pytest.approx(1.0)
    # position relevée sur le PC de Kevin (15 975 ms) : plus d'atténuation
    assert pn._fx_duck_strength(env, 15975.0) < 0.25
    # enveloppe absente (fichier illisible) : comportement d'avant
    assert pn._fx_duck_strength([], 15975.0) == 1.0


def test_ambiance_non_etouffee_en_fin_de_clip_de_freinage(fenetre):
    """Rejoue le relevé du 30/09 : 0,74 m/s, clip de freinage à 16 s."""
    win, _ = fenetre
    snd = win.game.sounds
    spath = str(snd._ambient_wavs["brake_approach_real"])
    snd._fx_env_cache[spath] = pn._wav_envelope_db(spath)

    class FauxFx:
        def position(self):
            return 15975

        def duration(self):
            return 20000

        def playbackState(self):  # noqa: N802
            return pn.QMediaPlayer.PlaybackState.PlayingState

    vrai_fx, vrai_chemin = snd._fx_player, snd._fx_loaded_path
    vrais = (snd._amb_playing, snd._fx_oneshot_active, snd._fx_duck_level)
    try:
        snd._fx_player = FauxFx()
        snd._fx_loaded_path = spath
        snd._amb_playing = True
        snd._fx_oneshot_active = True
        snd._fx_duck_level = 1.0                 # on sortait d'une phase forte
        for _ in range(120):                     # 2 s à 0,74 m/s
            snd.update_ambient(0.74, 1.0 / 60.0)
        gain = pn._ambient_gain(0.74, True)
        assert snd._amb_vol_target > 0.85 * gain, (snd._amb_vol_target, gain)
    finally:
        snd._fx_player, snd._fx_loaded_path = vrai_fx, vrai_chemin
        snd._amb_playing, snd._fx_oneshot_active, snd._fx_duck_level = vrais


# --- 2026-09-30 : vue salle des machines + bogue Qt 6.11 du volume nul -----
# Sur un vrai serveur son : un QSoundEffect qui JOUE à volume exactement 0
# rend muets tous les autres (−140 dB). C'était le vrai « silence total
# entre 0,2 et 1 m/s en décélération » : sous 1 m/s, la boucle de croisière
# jouait à volume 0 jusqu'à son arrêt à 0,2 m/s.

def test_soundeffect_jamais_a_volume_nul():
    if QSoundEffect is None:
        pytest.skip("QtMultimedia indisponible")
    app = QApplication.instance() or QApplication(sys.argv)  # noqa: F841
    fx = pn._SoundEffect()
    fx.setVolume(0.0)
    # niveau effectif côté Qt (volume() rend le niveau demandé depuis
    # le volume général du 05/10/2026)
    assert 0.0 < QSoundEffect.volume(fx) <= 2e-4
    fx.setVolume(0.5)
    assert abs(QSoundEffect.volume(fx) - 0.5) < 1e-6
    assert fx.volume() == 0.5


def test_boucle_de_croisiere_jamais_nulle_en_deceleration(fenetre):
    win, _ = fenetre
    snd = win.game.sounds
    snd.set_machine_room_view(False)
    for v in [3.0] * 60 + [0.9] * 60 + [0.5] * 60:
        snd.update_ambient(v, 1.0 / 60.0)
        for pl in (snd._amb_player, snd._amb2_player):
            if pl.isPlaying():
                # niveau EFFECTIF côté Qt : depuis le volume général
                # (05/10/2026), volume() rend le niveau demandé, qui peut
                # valoir 0 — c'est le plancher envoyé à Qt qui compte
                eff = (QSoundEffect.volume(pl) if QSoundEffect is not None
                       and isinstance(pl, QSoundEffect) else pl.volume())
                assert eff > 0.0, "une boucle joue à volume nul : Qt coupe tout"


def test_niveaux_de_la_salle_des_machines():
    g12, r12 = pn._machine_room_levels(12.0)
    assert abs(g12 - pn.MR_GAIN_12) < 1e-9 and r12 == 1.0
    g6, r6 = pn._machine_room_levels(6.0)
    assert abs(r6 - 0.5) < 1e-9
    assert abs(g6 - pn.MR_GAIN_12 * 0.5 ** pn.MR_EXP) < 1e-9
    assert pn._machine_room_levels(1.0)[1] == pn.MR_RATE_MIN     # 3 m/s mini
    assert pn._machine_room_levels(0.0)[0] == 0.0
    assert 0.0 < pn._machine_room_levels(0.2)[0] < pn._machine_room_levels(0.3)[0]


def test_vue_salle_des_machines_remplace_le_son_cabine(fenetre):
    win, _ = fenetre
    snd = win.game.sounds
    snd.set_machine_room_view(True)
    for _ in range(240):                       # 4 s à 12 m/s
        snd.update_ambient(12.0, 1.0 / 60.0)
    assert snd._mr_mix == 1.0
    assert snd._mr_started
    assert snd._amb_vol_target < 1e-6 and snd._amb2_vol_target < 1e-6
    assert abs(snd._mr_run_audio.volume() - pn.MR_GAIN_12) < 0.01
    assert abs(snd._mr_rate - 1.0) < 0.02
    assert snd._mr_idle.volume() > 0.99
    d = snd.diagnostic(12.0)
    assert d["salle_machines"]["vue"] is True
    snd.set_machine_room_view(False)
    for _ in range(300):
        snd.update_ambient(12.0, 1.0 / 60.0)
    assert snd._mr_mix == 0.0 and not snd._mr_started


# --- 2026-10-01 : sons de la salle absents (mise à jour sans sons/) --------
# La cabine ne doit pas s'effacer devant une salle des machines muette.

def test_salle_des_machines_absente_garde_le_son_cabine(fenetre):
    win, _ = fenetre
    snd = win.game.sounds
    vrais = dict(snd._ambient_wavs), snd._mr_present
    try:
        snd._ambient_wavs["salle_machines_repos"] = Path("/nulle/part/repos.wav")
        snd._mr_present = None
        assert snd.machine_room_sounds_present() is False
        snd.set_machine_room_view(True)
        for _ in range(240):
            snd.update_ambient(12.0, 1.0 / 60.0)
        assert snd._mr_mix == 0.0 and not snd._mr_started
        assert snd._amb2_vol_target > 0.1, "la cabine s'est tue"
        assert snd.diagnostic(12.0)["salle_machines"]["fichiers_presents"] is False
    finally:
        snd._ambient_wavs.clear()
        snd._ambient_wavs.update(vrais[0])
        snd._mr_present = vrais[1]
        snd.set_machine_room_view(False)


# --- 2026-10-03 : « l'ambiance est dans les haut-parleurs, les annonces et
# le reste dans le casque ». Tous les lecteurs suivent la sortie par défaut.

def test_tous_les_lecteurs_sur_la_meme_sortie(fenetre):
    win, _ = fenetre
    snd = win.game.sounds
    sorties = snd._sorties_audio()
    # les boucles d'ambiance (QSoundEffect) ET les lecteurs (QAudioOutput)
    assert any(isinstance(o, pn.QSoundEffect) for o in sorties)
    assert any(isinstance(o, pn.QAudioOutput) for o in sorties)
    snd._sortie_id = None               # force le réalignement
    snd.suivre_sortie_par_defaut()
    from PyQt6.QtMultimedia import QMediaDevices
    if QMediaDevices.defaultAudioOutput().isNull():
        pytest.skip("aucune sortie audio dans cet environnement")
    assert len(snd.peripheriques_utilises()) == 1, snd.peripheriques_utilises()


# --- 2026-10-04 : qualité 3D (menu Affichage), transmise au viewer -------

def test_qualite_3d_menu_et_flux(fenetre, tmp_path):
    win, _ = fenetre
    assert win.game._qualite_3d in pn.QUALITES_3D
    pn._persistent_data_dir = lambda: tmp_path
    win._choisir_qualite_3d("low")
    assert win.game._qualite_3d == "low"
    assert pn._lire_prefs().get("qualite_3d") == "low"
    import godot_bridge as gb
    b = gb.GodotBridge()
    b.quality = "low"
    b.dev_project_dir = None
    # la commande de lancement porte le réglage
    cmd = b._resolve_command() or []
    assert not cmd or "--quality=low" in cmd
    win._choisir_qualite_3d("auto")


def test_volume_general_f7_f8_et_sorties(fenetre, tmp_path):
    """Volume général (05/10/2026) : F7/F8 ±10 %, gain niveau² appliqué
    PAR-DESSUS le niveau propre de chaque sortie, retenu dans les réglages."""
    from PyQt6.QtMultimedia import QAudioOutput, QSoundEffect
    from PyQt6.QtCore import Qt
    from PyQt6.QtTest import QTest
    win, _ = fenetre
    g = win.game
    snd = g.sounds
    pn._persistent_data_dir = lambda: tmp_path
    pn.regler_volume_general(1.0)
    out = snd._audio
    demande = out.volume()
    assert QAudioOutput.volume(out) == pytest.approx(demande, abs=1e-3)
    QTest.keyClick(g, Qt.Key.Key_F7)
    QTest.keyClick(g, Qt.Key.Key_F7)
    assert pn.niveau_volume_general() == pytest.approx(0.8)
    assert pn._lire_prefs().get("volume_son") == pytest.approx(0.8)
    # la sortie garde son niveau demandé ; le gain 0,8² s'applique dessus
    assert out.volume() == pytest.approx(demande, abs=1e-6)
    assert QAudioOutput.volume(out) == pytest.approx(demande * 0.64, abs=2e-3)
    amb = snd._amb_player
    amb.setVolume(0.5)
    assert QSoundEffect.volume(amb) == pytest.approx(0.5 * 0.64, abs=2e-3)
    # un fondu qui relit puis réécrit le volume ne cumule pas le gain
    for _ in range(5):
        amb.setVolume(amb.volume())
    assert QSoundEffect.volume(amb) == pytest.approx(0.32, abs=2e-3)
    # à zéro, les QSoundEffect restent au plancher (bogue Qt du volume nul)
    pn.regler_volume_general(0.0)
    assert QSoundEffect.volume(amb) >= pn._SoundEffect.VOLUME_MIN * 0.99
    QTest.keyClick(g, Qt.Key.Key_F8)
    assert pn.niveau_volume_general() == pytest.approx(0.1)
    pn.regler_volume_general(1.0)
    assert QSoundEffect.volume(amb) == pytest.approx(0.5, abs=2e-3)


def test_volume_jauge_cliquable(fenetre, tmp_path):
    from PyQt6.QtCore import Qt
    win, _ = fenetre
    g = win.game
    pn._persistent_data_dir = lambda: tmp_path
    pn.regler_volume_general(0.5)
    g._show_help = False
    if g.state.mode == pn.MODE_TITLE:
        g.new_trip()
    g.grab()
    zones = {int(qk): rect for rect, qk, _h in g._hit_zones}
    assert int(Qt.Key.Key_F7) in zones and int(Qt.Key.Key_F8) in zones
    appuis = []
    vrai = g._sim_press
    g._sim_press = lambda qk: (appuis.append(int(qk)), vrai(qk))
    try:
        from PyQt6.QtTest import QTest
        from PyQt6.QtCore import QPoint
        k = g._ui_k()
        c = zones[int(Qt.Key.Key_F8)].center()
        QTest.mouseClick(g, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier,
                         QPoint(round(c.x() * k), round(c.y() * k)))
    finally:
        g._sim_press = vrai
    assert appuis == [int(Qt.Key.Key_F8)]
    assert pn.niveau_volume_general() == pytest.approx(0.6)
    pn.regler_volume_general(1.0)
