"""Interface peinte à l'échelle de la fenêtre (retour d'essai 2026-10-04 :
« la fenêtre s'adapte mal aux différents formats d'écran »).

Le pupitre, le journal et les écrans sont placés en pixels fixes pour une
toile d'au moins 1280 × 1000 ; GameWidget la met à l'échelle d'un bloc.
On vérifie que tout tient dans la fenêtre à plusieurs formats, que les
clics tombent sur le bon bouton, et que la vue 3D embarquée suit.
"""
import os
import sys
from pathlib import Path

import pytest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from PyQt6.QtCore import QPoint, QPointF, Qt  # noqa: E402
from PyQt6.QtTest import QTest  # noqa: E402
from PyQt6.QtWidgets import QApplication, QWidget  # noqa: E402

import perce_neige_sim as pn  # noqa: E402

# (largeur, hauteur) de la zone de jeu : portable 1080p à 125 %, petit
# écran, 1080p à 100 %, 1440p, ultra-large 21:9, 16:10, 4K à 100 %
FORMATS = [(1536, 760), (1024, 700), (1920, 1010), (2560, 1370),
           (3440, 1390), (1440, 1050), (3840, 2100)]


@pytest.fixture(scope="module")
def jeu(tmp_path_factory):
    app = QApplication.instance() or QApplication(sys.argv)
    data = tmp_path_factory.mktemp("pn_ui")
    pn._persistent_data_dir = lambda: Path(data)
    pn._writable_dir = lambda: Path(data)
    try:
        win = pn.MainWindow()
    except Exception as e:
        pytest.skip(f"MainWindow impossible hors écran : {e}")
    g = win.game
    g._show_help = False
    g.new_trip()
    g.setMinimumSize(100, 100)
    yield app, win, g
    win.close()
    app.processEvents()


def _peindre(app, g, w, h):
    g.resize(w, h)
    app.processEvents()
    g.grab()               # repeint : zones cliquables recalculées


@pytest.mark.parametrize("w,h", FORMATS)
def test_tout_tient_dans_la_fenetre(jeu, w, h):
    app, _, g = jeu
    _peindre(app, g, w, h)
    k = g._ui_k()
    vw, vh = g._ui_taille(k)
    assert vh >= g.UI_H_REF - 1 and vw >= g.UI_W_MIN - 1
    assert g._hit_zones, "aucune zone cliquable peinte"
    for rect, _qk, _hold in g._hit_zones:
        assert rect.right() * k <= w + 1 and rect.bottom() * k <= h + 1, \
            (w, h, rect)
    # le pupitre (rect h − 260) contient ses lignes d'info et ses voyants :
    # 508 + 12 lignes × 14 (mode Défi) + voyants 38 px ≤ hauteur du pupitre
    assert 508 + 12 * 14 + 38 <= vh - 260


def test_hauteur_utile_trop_petite_avant(jeu):
    """Le cas du retour d'essai : 1536 × 760 utiles, l'ancienne interface
    exigeait 900 px de haut. L'échelle descend, la toile garde 1000."""
    app, _, g = jeu
    _peindre(app, g, 1536, 760)
    assert g._ui_k() == pytest.approx(0.76, abs=1e-3)
    assert g._ui_taille(g._ui_k())[1] == 1000


def test_clic_au_bon_endroit_malgre_l_echelle(jeu, monkeypatch):
    app, _, g = jeu
    _peindre(app, g, 1536, 760)
    k = g._ui_k()
    zones = {int(qk): rect for rect, qk, _h in g._hit_zones}
    assert int(Qt.Key.Key_H) in zones
    appuis = []
    monkeypatch.setattr(g, "_sim_press", lambda qk: appuis.append(int(qk)))
    c = zones[int(Qt.Key.Key_H)].center()
    QTest.mouseClick(g, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier,
                     QPoint(round(c.x() * k), round(c.y() * k)))
    assert appuis == [int(Qt.Key.Key_H)]


def test_vue_3d_embarquee_suit_l_echelle(jeu):
    app, _, g = jeu
    _peindre(app, g, 1536, 760)
    faux = QWidget(g)
    ancien = g._godot_embed_widget
    g._godot_embed_widget = faux
    try:
        g._reposition_godot_embed()
        k = g._ui_k()
        vw, vh = g._ui_taille(k)
        geo = faux.geometry()
        assert geo.x() == int(20 * k) and geo.y() == int(44 * k)
        # bas de la 3D = bas du rect de vue (h − 240 dans la toile)
        assert abs(geo.y() + geo.height() - (vh - 240) * k) <= 2
        assert abs(geo.x() + geo.width() - (vw - 420) * k) <= 2
    finally:
        g._godot_embed_widget = ancien
        faux.deleteLater()


def test_menu_taille_interface(jeu):
    app, win, g = jeu
    _peindre(app, g, 2560, 1370)
    k_normal = g._ui_k()
    win._choisir_taille_ui(0.85)
    assert pn._lire_prefs().get("taille_ui") == 0.85
    assert g._ui_k() == pytest.approx(k_normal * 0.85)
    # « plus grande » reste bornée par ce qui tient
    win._choisir_taille_ui(1.3)
    k_tient = min(2560 / g.UI_W_MIN, 1370 / g.UI_H_REF)
    assert g._ui_k() == pytest.approx(min(k_tient, k_normal * 1.3))
    win._choisir_taille_ui(1.0)
    assert g._ui_k() == pytest.approx(k_normal)


def test_petit_ecran_demarre_agrandi(jeu):
    pn._ecrire_prefs({"fenetre": ""})
    w2 = pn.MainWindow()
    try:
        dispo = QApplication.primaryScreen().availableGeometry()
        petit = dispo.height() - 60 < 900 or dispo.width() - 20 < 1280
        assert w2._demarrer_agrandie == petit
        assert w2.width() <= max(900, dispo.width())
    finally:
        w2.close()


def test_fenetre_memorisee(jeu):
    app, win, _ = jeu
    win.resize(1100, 720)
    win.move(40, 30)
    app.processEvents()
    win.close()
    app.processEvents()
    assert pn._lire_prefs().get("fenetre")
    w2 = pn.MainWindow()
    try:
        assert not w2._demarrer_agrandie
        # taille d'avant, ramenée par Qt à l'écran s'il est plus petit
        dispo = QApplication.primaryScreen().availableGeometry()
        assert w2.height() == 720
        assert w2.width() == min(1100, dispo.width() - 2) or w2.width() == 1100
    finally:
        w2.close()
    win.show()
    app.processEvents()


# ----- écran détecté (v1.15.55) -------------------------------------------
# Valeurs vérifiées par audit_physique/echelle_ecran.sage (.txt)
@pytest.mark.parametrize("ecran,attendu", [
    ((1920, 1080, 531, 299, 1.0), 1.053),     # 24" 1080p 100 % (référence)
    ((2560, 1440, 597, 336, 1.0), 1.361),     # 27" 1440p 100 %
    ((2560, 1440, 597, 336, 1.5), 1.361),     # 27" 4K 150 %
    ((3440, 1440, 800, 335, 1.0), 1.728),     # 34" 21:9
    ((1536, 864, 310, 174, 1.25), 1.007),     # portable 14" 1080p 125 %
    ((1440, 900, 286, 179, 2.0), 1.0),        # Mac 13" : jamais sous 1
    ((3840, 2160, 1210, 680, 1.0), 2.499),    # téléviseur 55"
])
def test_facteur_selon_l_ecran(ecran, attendu):
    e = pn._decrire_ecran(*ecran)
    assert e["facteur"] == pytest.approx(attendu, abs=2e-3)


@pytest.mark.parametrize("mm", [(0, 0), (2000, 1200), (5, 3)])
def test_taille_physique_absente_ou_fantaisiste(mm):
    assert pn._decrire_ecran(1920, 1080, mm[0], mm[1], 1.0)["facteur"] is None


def test_ecran_dans_le_journal_au_premier_trajet(jeu):
    app, _, g = jeu
    _peindre(app, g, 1536, 760)
    g._ecran_journal_fait = False
    g.new_trip()
    lignes = [e.message_fr for e in g.state.events if e.key == "screen"]
    assert lignes and lignes[0].startswith("Écran ") and "interface à" in lignes[0]
    # place insuffisante → la ligne propose le plein écran
    assert "F11" in lignes[0]


def test_changement_d_ecran_vu_en_direct(jeu):
    app, _, g = jeu
    _peindre(app, g, 1536, 760)
    n = sum(1 for e in g.state.events if e.key == "screen")
    g._ecran_sig = ("autre écran", 1, 1, 1, 1, 1.0)   # comme un glisser
    g._ui_k()
    app.processEvents()
    assert sum(1 for e in g.state.events if e.key == "screen") == n + 1


def test_plein_ecran_f11(jeu):
    app, win, g = jeu
    win.showMaximized()
    app.processEvents()
    QTest.keyClick(g, Qt.Key.Key_F11)
    app.processEvents()
    assert win.isFullScreen() and pn._lire_prefs().get("plein_ecran") is True
    QTest.keyClick(g, Qt.Key.Key_F11)
    app.processEvents()
    assert not win.isFullScreen() and pn._lire_prefs().get("plein_ecran") is False
