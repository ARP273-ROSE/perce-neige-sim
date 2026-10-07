"""Sons du skieur jouable (07/10/2026), synthétisés — régénérables :
    python3 tools_sons_skieur.py
      → godot_project/sounds/souffle_tunnel.wav  (une bouffée d'air, ~6 s)
      → godot_project/sounds/vent_dehors.wav     (vent léger, boucle de 12 s)

Kevin, 07/10/2026 : « sur le bord du quai, alors que le truc est parti,
j'entends le son comme si j'étais dedans, alors qu'en vrai en bas on
n'entend rien, à part des souffles d'air réguliers / vent sifflements suivis
de silences dus aux surpressions dans le tunnel ».

Bouffée : bruit brun filtré 150-1500 Hz qui monte en 1,5 s, tient, et
retombe en 3 s, avec un sifflement étroit qui glisse de 1 000 à 1 250 Hz.
Vent : bruit rose 100-2 000 Hz, modulé lentement, raccordé en boucle.
Pas d'enregistrement : aucune prise de son du quai n'existe dans le projet.
"""
import wave

import numpy as np

SR = 22050
rng = np.random.default_rng(20261007)


def bande(x, f0, f1, rampe=0.15):
    """Filtre passe-bande par FFT (bords en rampe de ±15 %)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    g = np.clip((f - f0 * (1 - rampe)) / (2 * rampe * f0), 0, 1) \
        * np.clip((f1 * (1 + rampe) - f) / (2 * rampe * f1), 0, 1)
    return np.fft.irfft(X * g, len(x))


def ecrire(chemin, x, crete_db=-3.0):
    x = x / np.max(np.abs(x)) * 10 ** (crete_db / 20.0)
    with wave.open(chemin, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    print(chemin, "%.1f s" % (len(x) / SR))


# --- bouffée d'air dans le tunnel ---------------------------------------------
n = int(6.0 * SR)
t = np.arange(n) / SR
brun = np.cumsum(rng.standard_normal(n))
brun -= np.convolve(brun, np.ones(2205) / 2205, mode="same")   # sans dérive
souffle = bande(brun, 150.0, 1500.0)
souffle /= np.max(np.abs(souffle))
# sifflement : bande étroite autour d'une fréquence qui glisse
blanc = rng.standard_normal(n)
f_c = 1000.0 + 250.0 * np.clip((t - 1.0) / 3.0, 0, 1)
phase = 2 * np.pi * np.cumsum(f_c) / SR
siffle = bande(blanc, 900.0, 1350.0) * (0.6 + 0.4 * np.sin(phase * 0.002))
siffle /= np.max(np.abs(siffle))
env = np.where(t < 1.5, (t / 1.5) ** 2,
               np.where(t < 3.0, 1.0, np.clip(1.0 - (t - 3.0) / 3.0, 0, 1) ** 1.5))
env_s = np.where(t < 2.0, (t / 2.0) ** 3, np.clip(1.0 - (t - 2.0) / 3.5, 0, 1))
ecrire("godot_project/sounds/souffle_tunnel.wav", (souffle + 0.22 * siffle * env_s) * env)

# --- vent dehors, en boucle ------------------------------------------------------
n2 = int(12.0 * SR)
t2 = np.arange(n2) / SR
X = np.fft.rfft(rng.standard_normal(n2))
f2 = np.fft.rfftfreq(n2, 1.0 / SR)
X[1:] /= np.sqrt(f2[1:])                         # bruit rose
rose = np.fft.irfft(X, n2)
vent = bande(rose, 100.0, 2000.0)
vent *= 0.65 + 0.35 * np.sin(2 * np.pi * t2 / 4.0) * np.sin(2 * np.pi * t2 / 12.0 + 0.7)
# raccord de boucle : fondu enchaîné de 1 s entre la fin et le début
k = SR
fondu = np.linspace(0, 1, k)
vent[:k] = vent[:k] * fondu + vent[-k:] * (1 - fondu)
ecrire("godot_project/sounds/vent_dehors.wav", vent[:-k], -6.0)
