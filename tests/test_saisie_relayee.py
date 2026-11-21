"""Frappe relayée vers un champ de texte de la vue 3D (retour d'utilisateur du 21/11/2026 : le code du salon ne
s'écrivait pas sur le PC, les lettres faisaient les raccourcis du skieur)."""
import os
import types

import pytest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
QtCore = pytest.importorskip("PyQt6.QtCore")
QtGui = pytest.importorskip("PyQt6.QtGui")
QtWidgets = pytest.importorskip("PyQt6.QtWidgets")
Qt = QtCore.Qt


def _ev(key, text="", mods=Qt.KeyboardModifier.NoModifier):
    return QtGui.QKeyEvent(QtCore.QEvent.Type.KeyPress, key, mods, text)


def test_frappe_relayee():
    app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])
    import perce_neige_sim as pns
    w = types.SimpleNamespace(_saisie_file=[])
    relayer = pns.GameWidget._saisie_relayer
    assert relayer(w, _ev(Qt.Key.Key_Z, "z"))
    assert relayer(w, _ev(Qt.Key.Key_7, "7"))
    assert relayer(w, _ev(Qt.Key.Key_Backspace))
    assert relayer(w, _ev(Qt.Key.Key_Return, "\r"))
    assert not relayer(w, _ev(Qt.Key.Key_F11))
    app.clipboard().setText("ABC-123")
    assert relayer(w, _ev(Qt.Key.Key_V, "", Qt.KeyboardModifier.ControlModifier))
    assert w._saisie_file == [{"t": "z"}, {"t": "7"}, {"k": "BackSpace"}, {"k": "Enter"}, {"t": "ABC-123"}]
