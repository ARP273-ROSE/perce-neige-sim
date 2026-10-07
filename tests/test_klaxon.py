"""Klaxon = vrai buzzer de la rame (tools_klaxon.py), même fichier PC et PWA."""
import wave
from pathlib import Path

import numpy as np

RACINE = Path(__file__).resolve().parent.parent
PC = RACINE / "sons" / "ambients" / "klaxon_buzzer.wav"
PWA = RACINE / "godot_project" / "sounds" / "klaxon.wav"


def _lire(p):
    with wave.open(str(p)) as w:
        assert (w.getnchannels(), w.getframerate()) == (1, 44100)
        return np.frombuffer(w.readframes(w.getnframes()), np.int16) / 32768.0


def test_klaxon_buzzer_385_hz_en_boucle():
    x = _lire(PC)
    assert 0.95 < len(x) / 44100 < 1.05
    X = np.abs(np.fft.rfft(x))
    f = np.fft.rfftfreq(len(x), 1 / 44100)
    # raie du fondamental à 385,6 Hz, et la plus forte = 7e harmonique
    assert abs(f[np.argmax(X * (np.abs(f - 385.6) < 20))] - 385.6) < 1.5
    assert abs(f[np.argmax(X)] - 7 * 385.6) < 5
    # raccord de boucle : pas de saut plus grand qu'un pas ordinaire
    sauts = np.abs(np.diff(x))
    assert abs(x[0] - x[-1]) <= sauts.max()


def test_klaxon_pc_egal_pwa():
    if PWA.exists():
        assert PWA.read_bytes() == PC.read_bytes()
