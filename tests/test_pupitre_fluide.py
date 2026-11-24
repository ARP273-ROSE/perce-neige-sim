"""Pupitre du PC fluide et interface à l'échelle de l'écran (retour d'utilisateur du 24/11/2026, plein écran 4K 32" :
« les boutons sont énormes », « le joystick n'est peut-être pas pertinent sur PC », deux postes en doublon, nom et
vitesse qui se chevauchent dans le pupitre replié, aiguilles saccadées).

Exécution : QT_QPA_PLATFORM=offscreen pytest tests/test_pupitre_fluide.py -v
"""
import os
import sys
from pathlib import Path

import pytest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pupitre_remontee as pr  # noqa: E402

ICI = Path(__file__).resolve().parent.parent
SCRIPTS = ICI / "godot_project" / "scripts"
PAQUET = {"id": "tsd6_x", "nom": "TSD6 Marmottes Express", "groupe": "tsd", "v": 2.0, "v_nom": 5.0, "kw": 100.0,
          "etat": "marche", "mode": "auto", "evts": [],
          "va_et_vient": {"pos": [0.2, 0.8], "portes": ["fermees", "fermees"]}}


# --- lissage des aiguilles (modèle, sans Qt) ---

def test_interpolation_entre_paquets():
    m = pr.ModeleRemontee()
    m.recevoir(dict(PAQUET), maintenant=10.0)
    assert m.recevoir_vite(["tsd6_x", 3.0, 200.0, [0.3, 0.7]], maintenant=10.1)
    # affiché avec RETARD_S de différé : à mi-chemin des deux relevés
    v, kw, pos = m.lisse(10.05 + m.RETARD_S)
    assert v == pytest.approx(2.5) and kw == pytest.approx(150.0)
    assert pos == pytest.approx((0.25, 0.75))
    # au-delà du dernier relevé : on le garde (pas d'extrapolation qui dépasserait l'arrêt)
    assert m.lisse(20.0)[0] == pytest.approx(3.0)


def test_paquet_leger_d_une_autre_ligne_ignore():
    m = pr.ModeleRemontee()
    assert not m.recevoir_vite(["tsd6_x", 1.0, 1.0, []])       # pas encore de ligne
    m.recevoir(dict(PAQUET), maintenant=0.0)
    assert not m.recevoir_vite(["autre", 9.0, 9.0, []], maintenant=0.1)
    assert not m.recevoir_vite("n'importe quoi", maintenant=0.1)
    assert m.lisse(5.0)[0] == pytest.approx(2.0)


def test_changement_de_ligne_repart_de_zero():
    m = pr.ModeleRemontee()
    m.recevoir(dict(PAQUET), maintenant=0.0)
    m.recevoir_vite(["tsd6_x", 4.0, 300.0, [0.5, 0.5]], maintenant=0.1)
    m.recevoir(dict(PAQUET, id="tcd_y", v=1.0, kw=50.0, va_et_vient=None), maintenant=0.2)
    v, kw, pos = m.lisse(0.2 + m.RETARD_S)
    assert (v, kw, pos) == (1.0, 50.0, ())


def test_d_affiche_et_signature():
    m = pr.ModeleRemontee()
    m.recevoir(dict(PAQUET), maintenant=0.0)
    m.recevoir_vite(["tsd6_x", 4.0, 300.0, [0.6, 0.4]], maintenant=0.1)
    d = m.d_affiche(1.0)
    assert d["v"] == pytest.approx(4.0) and d["va_et_vient"]["pos"] == pytest.approx([0.6, 0.4])
    assert m.d["v"] == 2.0                      # la télémesure elle-même n'est pas touchée
    assert m.signature_aiguilles(1.0) != m.signature_aiguilles(0.0 + m.RETARD_S)


# --- échelle de l'interface de la 3D ---

def test_facteur_ui():
    import perce_neige_sim as pn
    # 4K 32" : réduite au plus (boutons de ~3 cm sinon)
    assert pn.facteur_ui_3d(3840, 2160, 137.7) == pytest.approx(0.5)
    # portable 1080p 15,6" : presque rien
    assert 0.8 < pn.facteur_ui_3d(1920, 1080, 141.0) < 0.95
    # petite vue 3D (poste) ou densité inconnue : inchangée
    assert pn.facteur_ui_3d(1100, 600, 96.0) == 1.0
    assert pn.facteur_ui_3d(3840, 2160, 0.0) == 1.0


def test_vue_3d_applique_le_facteur():
    sr = (SCRIPTS / "state_receiver.gd").read_text(encoding="utf-8")
    assert '"echelle_ui"' in sr and "content_scale_factor" in sr


# --- un seul poste sur le PC, joystick au tactile seulement ---

def test_poste_et_joystick():
    cs = (SCRIPTS / "commandes_skieur.gd").read_text(encoding="utf-8")
    assert 'lg != null and not bool(main.get("client_mode"))' in cs
    assert "_joy.visible = DisplayServer.is_touchscreen_available()" in cs


def test_trajet_et_paquet_leger_envoyes():
    mg = (SCRIPTS / "main.gd").read_text(encoding="utf-8")
    assert '"remontee_v"' in mg and 'etat["trajet"]' in mg
    ex = (SCRIPTS / "exploitation_remontee.gd").read_text(encoding="utf-8")
    assert "func etat_rapide()" in ex


# --- dessin (Qt) ---

@pytest.fixture(scope="module")
def jeu(tmp_path_factory):
    from PyQt6.QtWidgets import QApplication
    import perce_neige_sim as pn
    app = QApplication.instance() or QApplication(sys.argv)
    data = tmp_path_factory.mktemp("pn_fluide")
    pn._persistent_data_dir = lambda: Path(data)
    pn._writable_dir = lambda: Path(data)
    try:
        win = pn.MainWindow()
    except Exception as e:
        pytest.skip(f"MainWindow impossible hors écran : {e}")
    win.game.sounds.enabled = False
    yield pn, win.game
    win.close()
    app.processEvents()


def test_bandeau_nom_long_raccourci(jeu):
    from PyQt6.QtCore import QRectF
    from PyQt6.QtGui import QImage, QPainter
    _pn, g = jeu
    g._recevoir_remontee(dict(PAQUET, nom="TSD6 Marmottes Express de la Grande Pare", trajet="Parcouru 10 m"))
    textes = []
    img = QImage(400, 50, QImage.Format.Format_ARGB32)
    p = QPainter(img)
    orig = p.drawText

    def note(*a):
        textes.append(a[-1])
        return orig(*a)
    p.drawText = note
    try:
        g._draw_bandeau_pupitre(p, QRectF(0, 0, 390, 46))
    finally:
        p.end()
    assert any(isinstance(t, str) and t.endswith("…") and t.startswith("TSD6") for t in textes)


def test_paquet_leger_recu_par_le_pc(jeu):
    _pn, g = jeu
    g._recevoir_remontee(dict(PAQUET))
    s0 = g._signature_pupitre()
    g._message_3d({"remontee_v": ["tsd6_x", 4.9, 400.0, [0.9, 0.1]]})
    import time
    time.sleep(g._remontee.RETARD_S + 0.02)
    assert g._signature_pupitre() != s0


# --- première installation du décor HD : fenêtre de progression, REDÉMARRER à la fin (24/11/2026) ---

def test_fenetre_pack_hd(jeu):
    import pack_hd
    pn, _g = jeu
    avant = dict(pack_hd.etat)
    try:
        pack_hd.etat.update(phase="telechargement", fait=100 << 20)
        dlg = pn.PackHdDialog(None)
        assert dlg._barre.value() == int(1000 * (100 << 20) / pack_hd.TAILLE)
        assert not dlg._b_redemarrer.isVisibleTo(dlg)
        pack_hd.etat.update(phase="pret", fait=pack_hd.TAILLE)
        dlg._maj()
        assert dlg._b_redemarrer.isVisibleTo(dlg) and pn.T("Restart", "Redémarrez") in dlg._texte.text()
        dlg.close()
    finally:
        pack_hd.etat.update(avant)


def test_colonne_de_boutons_sans_debordement():
    cs = (SCRIPTS / "commandes_skieur.gd").read_text(encoding="utf-8")
    assert "VFlowContainer.new()" in cs and "col.anchor_top = 0.0" in cs
