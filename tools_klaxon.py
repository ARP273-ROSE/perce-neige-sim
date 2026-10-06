"""Klaxon du pupitre de la PWA (godot_project/sounds/klaxon.wav) — même
synthèse que le PC (horn_v3.wav de perce_neige_sim.py) : deux tons de
220 et 277 Hz en dents de scie (harmoniques 1 à 8), sous-harmonique,
souffle d'air, trémolo de 5 Hz ; boucle d'une seconde sans enveloppe.
    python3 tools_klaxon.py
"""
import math
import random
import struct
import wave

TAUX = 44100
f1, f2 = 220.0, 277.0
rnd = random.Random(277)
prev_n = 0.0
data = bytearray()
for i in range(TAUX):
    t = i / TAUX
    s = 0.0
    for k in range(1, 9):
        amp = 1.0 / k
        s += math.sin(2 * math.pi * f1 * k * t) * amp * 0.55
        s += math.sin(2 * math.pi * f2 * k * t) * amp * 0.50
    s += math.sin(2 * math.pi * (f1 * 0.5) * t) * 0.25
    prev_n = prev_n * 0.75 + rnd.uniform(-1.0, 1.0) * 0.25
    s += prev_n * 0.18
    s *= 0.82 + 0.08 * math.sin(2 * math.pi * 5.0 * t)
    s = math.tanh(s * 0.55) * 0.80
    data += struct.pack("<h", int(s * 32767))
with wave.open("godot_project/sounds/klaxon.wav", "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(TAUX)
    w.writeframes(bytes(data))
print("klaxon.wav : %d échantillons" % TAUX)
