"""Sons du skieur jouable (07/10/2026), synthétisés — régénérables :
    python3 tools_sons_skieur.py
      → godot_project/sounds/souffle_tunnel.wav  (une bouffée d'air, ~6 s)
      → godot_project/sounds/vent_dehors.wav     (vent léger, boucle de 12 s)

Kevin, 07/10/2026 : « sur le bord du quai, alors que le truc est parti,
j'entends le son comme si j'étais dedans, alors qu'en vrai en bas on
n'entend rien, à part des souffles d'air réguliers / vent sifflements suivis
de silences dus aux surpressions dans le tunnel ».

Bouffée : bruit rose filtré 300-3 000 Hz (plus de grave : Kevin, 07/10/2026,
« le souffle du vent est trop grave, faut monter un peu pour que ça siffle
un peu comme un fil ») qui monte en 1,5 s, tient, et retombe en 3 s, avec
un sifflement de fil — deux bandes étroites, 1 500→1 900 Hz et son octave
affaiblie — qui s'installe après le gros du souffle.
Vent : bruit rose 180-2 500 Hz, modulé lentement, raccordé en boucle, avec
un fil qui siffle faiblement.
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
def rose(m):
    """Bruit rose (−3 dB/octave) de m échantillons."""
    Xr = np.fft.rfft(rng.standard_normal(m))
    fr = np.fft.rfftfreq(m, 1.0 / SR)
    Xr[1:] /= np.sqrt(fr[1:])
    return np.fft.irfft(Xr, m)


def fil(m, f0, f1, t_glisse=3.0, largeur=0.06):
    """Sifflement de fil (son éolien) : bande étroite (±6 %) de bruit blanc
    autour d'une fréquence qui glisse de f0 à f1, plus son octave à −10 dB."""
    tt = np.arange(m) / SR
    f_c = f0 + (f1 - f0) * np.clip(tt / t_glisse, 0, 1)
    blanc = rng.standard_normal(m)
    # le glissement se fait par morceaux de 100 ms (filtre FFT par tranche)
    out = np.zeros(m)
    pas = int(0.1 * SR)
    for i in range(0, m, pas):
        j = min(i + pas, m)
        fc = float(f_c[(i + j) // 2])
        tranche = blanc[max(0, i - pas):min(m, j + pas)]
        y = bande(tranche, fc * (1 - largeur), fc * (1 + largeur), 0.5) \
            + 0.32 * bande(tranche, 2 * fc * (1 - largeur), 2 * fc * (1 + largeur), 0.5)
        out[i:j] = y[i - max(0, i - pas):i - max(0, i - pas) + (j - i)]
    return out / np.max(np.abs(out))


souffle = bande(rose(n), 300.0, 3000.0)
souffle /= np.max(np.abs(souffle))
# sifflement de fil : il s'installe après le gros du souffle et glisse vers l'aigu
siffle = fil(n, 1500.0, 1900.0)
env = np.where(t < 1.5, (t / 1.5) ** 2,
               np.where(t < 3.0, 1.0, np.clip(1.0 - (t - 3.0) / 3.0, 0, 1) ** 1.5))
env_s = np.where(t < 2.0, (t / 2.0) ** 3, np.clip(1.0 - (t - 2.0) / 3.5, 0, 1))
ecrire("godot_project/sounds/souffle_tunnel.wav", (souffle + 0.45 * siffle * env_s) * env)

# --- vent dehors, en boucle ------------------------------------------------------
n2 = int(12.0 * SR)
t2 = np.arange(n2) / SR
vent = bande(rose(n2), 180.0, 2500.0)
vent /= np.max(np.abs(vent))
# un fil qui siffle faiblement, au gré des rafales
vent += 0.18 * fil(n2, 1400.0, 1700.0, 12.0) * (0.5 + 0.5 * np.sin(2 * np.pi * t2 / 12.0 + 0.7))
vent *= 0.65 + 0.35 * np.sin(2 * np.pi * t2 / 4.0) * np.sin(2 * np.pi * t2 / 12.0 + 0.7)
# raccord de boucle : fondu enchaîné de 1 s entre la fin et le début
k = SR
fondu = np.linspace(0, 1, k)
vent[:k] = vent[:k] * fondu + vent[-k:] * (1 - fondu)
ecrire("godot_project/sounds/vent_dehors.wav", vent[:-k], -6.0)

# --- pas en chaussures de ski sur sol dur (09/10/2026) -----------------------------
# Kevin : « quand je marche sur les escaliers le long du quai sans les skis,
# rajoute un claquement sec à chaque pas, à cause des chaussures de ski ».
# Coque plastique rigide qui frappe du béton / du métal : un clic très bref
# (talon), une résonance de coque vers 1,1 et 3,2 kHz qui s'éteint en ~25 ms,
# un petit choc sourd vers 160 Hz. Trois variantes, tirées au hasard.
for k3 in range(3):
    n3 = int(0.12 * SR)
    t3 = np.arange(n3) / SR
    clic = rng.standard_normal(n3) * np.exp(-t3 / 0.0025)
    f1 = 1100.0 * (1.0 + 0.06 * (k3 - 1))
    f2 = 3200.0 * (1.0 + 0.05 * (1 - k3))
    coque = (np.sin(2 * np.pi * f1 * t3) * 0.6 + np.sin(2 * np.pi * f2 * t3 + 0.7) * 0.4) \
        * np.exp(-t3 / 0.022)
    choc = np.sin(2 * np.pi * 160.0 * t3) * np.exp(-t3 / 0.030) * 0.5
    x3 = bande(clic, 800.0, 7000.0) * 1.2 + coque * 0.5 + choc
    x3[: int(0.0005 * SR)] *= np.linspace(0, 1, int(0.0005 * SR))
    ecrire("godot_project/sounds/pas_chaussure_%d.wav" % (k3 + 1), x3, -4.0)
