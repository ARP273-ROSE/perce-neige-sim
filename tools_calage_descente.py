"""Mesures sur la vidéo de DESCENTE en cabine, pour caler le simulateur —
demande d'un utilisateur (06/10/2026) : « la descente est effectuée à 12 m/s donc tu
peux calibrer des trucs […] accélérations, espacement […] en fonction de la
position ».

Vidéo : « [FUNI284] Funiculaire du Perce-Neige | Tignes (descente) »,
chaîne « Transports câblés » (YouTube -T429ismOSE), filmée le 02/09/2013
(date affichée par l'écran du pupitre), téléchargée pour analyse locale
dans sons/videos/funiculaire_descente_1080p.mp4 (non versionnée).

    python3 tools_calage_descente.py   →  instants de passage des néons

Méthode : la caméra est tenue à la main (aucune fenêtre fixe ne suit la
voie), mais chaque néon qui passe au-dessus de la cabine éclaire toute la
moitié haute de l'image : on détecte ces pics de luminosité (maximum local
sur ±0,6 s d'un signal passe-haut). En croisière ils tombent toutes les
1,633 s (néons allumés régulièrement espacés) ; au départ l'intervalle se
resserre et donne la vitesse, donc l'accélération. Les relevés de l'écran
du pupitre (vitesse, distance) ont été lus à l'œil sur les images nettes.
Les calculs sont dans audit_physique/calage_descente.sage.
"""
import subprocess

import numpy as np

VIDEO = "sons/videos/funiculaire_descente_1080p.mp4"
FPS = 30.0
L, H = 96, 54

brut = subprocess.run(["ffmpeg", "-v", "error", "-i", VIDEO, "-vf", f"scale={L}:{H},format=gray",
                       "-f", "rawvideo", "-pix_fmt", "gray", "-"], capture_output=True, check=True).stdout
img = np.frombuffer(brut, np.uint8)
n = img.size // (L * H)
img = img[:n * L * H].reshape(n, H, L).astype(np.float32)
lum = img[:, : H * 4 // 9, :].mean(axis=(1, 2))
hp = lum - np.convolve(lum, np.ones(91) / 91, mode="same")
sm = np.convolve(hp, np.ones(5) / 5, mode="same")
pics = [i / FPS for i in range(18, n - 18) if sm[i] == sm[i - 18:i + 19].max() and sm[i] > 2.0]
print("instants de passage des néons (s) :")
print(", ".join("%.2f" % t for t in pics))
