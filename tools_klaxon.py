"""Klaxon du pupitre, pris sur le vrai buzzer de la rame — régénérable :
    python3 tools_klaxon.py chemin/vers/v2.wav
      → godot_project/sounds/klaxon.wav     (PWA, boucle tant qu'on tient)
      → sons/ambients/klaxon_buzzer.wav      (PC, même fichier)

Retour d'utilisateur, 07/10/2026 : « le buzzer à 1:56 [de la vidéo] qui dure 3 secondes
environ, tu le récupères à un moment où il n'y a pas d'autre bruit de fond
et tu t'en sers comme son de klaxon ».

Source : vidéo YouTube JMyPmj8EebU (« funiculaire de la grande motte »,
2007), piste son extraite en WAV mono 44,1 kHz (ffmpeg -ac 1 -ar 44100).
La vidéo elle-même reste hors du dépôt.

Mesures sur cette piste :
  - le buzzer sonne de 1:55,4 à 1:58,3 ;
  - fondamental 385,59 Hz, stable à 0,02 Hz près ;
  - harmoniques 5 et 7 les plus fortes ; 97 % de l'énergie sur les
    harmoniques entre 1:55,65 et 1:56,65 (le moins de bruit autour).

Traitement :
  1. découpe de 386 périodes exactes du fondamental dans cette fenêtre
     (1,0011 s) ;
  2. FFT circulaire du morceau ; on ne garde que les raies à ±12 Hz des
     harmoniques 1 à 15 : le reste (voix, roulement) disparaît, et le
     son boucle sans raccord puisque le filtre est circulaire ;
  3. rotation au passage par zéro le plus calme (pas de clic au départ) ;
  4. crête normalisée à −3 dBFS.
"""
import sys
import wave

import numpy as np

SR = 44100
F0 = 385.59                 # Hz, mesuré sur 1:55,65–1:58,20
T0 = 115.65                 # s, début de la fenêtre propre
PERIODES = 386
LARGEUR = 12.0              # Hz gardés de part et d'autre de chaque raie
HARMONIQUES = 15

source = sys.argv[1] if len(sys.argv) > 1 else "v2.wav"
with wave.open(source) as w:
    assert w.getframerate() == SR and w.getnchannels() == 1, source
    x = np.frombuffer(w.readframes(w.getnframes()), np.int16) / 32768.0

n = int(round(PERIODES * SR / F0))
seg = x[int(T0 * SR):int(T0 * SR) + n].astype(float)
X = np.fft.rfft(seg)
f = np.fft.rfftfreq(n, 1.0 / SR)
garde = np.zeros_like(f, bool)
for k in range(1, HARMONIQUES + 1):
    garde |= np.abs(f - k * F0) <= LARGEUR
part = float(np.sum(np.abs(X[garde]) ** 2) / np.sum(np.abs(X[f > 0]) ** 2))
y = np.fft.irfft(X * garde, n)

# départ sur un passage par zéro montant, là où l'enveloppe est la plus basse
zc = np.where((y[:-1] < 0) & (y[1:] >= 0))[0]
env = np.convolve(np.abs(y), np.ones(64) / 64, mode="same")
y = np.roll(y, -int(zc[np.argmin(env[zc])] + 1))
y = y / np.max(np.abs(y)) * 10 ** (-3.0 / 20.0)

for chemin in ("godot_project/sounds/klaxon.wav", "sons/ambients/klaxon_buzzer.wav"):
    with wave.open(chemin, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((y * 32767).astype(np.int16).tobytes())
    print(chemin, "%d échantillons (%.4f s)" % (n, n / SR))
print("énergie gardée : %.1f %%, RMS %.1f dBFS, raccord de boucle %.4f"
      % (100 * part, 20 * np.log10(np.sqrt(np.mean(y ** 2))), abs(y[0] - y[-1])))
