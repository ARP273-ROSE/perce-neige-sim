"""Sons des remontées du domaine (25/10/2026), synthétisés — régénérables :
    python3 tools_sons_remontees.py
      → godot_project/sounds/remontees/*.wav

Retour d'utilisateur, 25/10/2026 : « le bruit du trajet sur un télésiège, à l'intérieur
d'une TC, du TPH, du 3S ; le bruit autour des gares et quand on le prend ;
l'accélération et la décélération du lanceur ; le passage sur un pylône en
fonction de la vitesse et du nombre de galets, porteur ou compression, pas le
même son en télésiège et en TC ; l'arrêt ; le son de la gare qui monte quand
on s'approche et diminue quand on s'éloigne ».

Calage sur des vidéos de lignes du domaine (analyse du signal, pas de copie) :
en gare de télésiège débrayable, une raie forte vers 290 Hz (réducteur) et
une autre vers 78 Hz (moteur), du grondement 250–500 Hz (pneus des
lanceurs) ; en ligne, un souffle 250–1 000 Hz ; au pylône, une salve de
chocs secs. Les prises réelles remplaceront ces sons quand des extraits
propres seront choisis.

Boucles (raccordées) :
  gare_debrayable   moteur + réducteur + pneus des lanceurs, claquements de pinces
  gare_fixe         poulie et moteur seuls (télésièges et téléskis à pinces fixes)
  lanceur           ronflement de pneus (hauteur = vitesse du véhicule)
  ligne_siege       vent et câble, assis à l'air libre
  ligne_cabine      intérieur de cabine : grondement sourd, sifflement de joints
  ligne_3s          intérieur de grande cabine (3S, téléphérique) : roulement
                    du chariot sur les porteurs, plus grave
  teleski           corde et câble d'un téléski, crissement des skis
Coups :
  galet_support     choc grave d'une pince sur un galet porteur (dessous)
  galet_compression choc plus sec, métallique (galets au-dessus)
  arret_urgence     claquement du frein de poulie, câble qui vibre
  file_huees        la file d'attente qui hue le resquilleur
"""
import os
import wave

import numpy as np

SR = 22050
rng = np.random.default_rng(20261025)
SORTIE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "godot_project", "sounds", "remontees")


def bande(x, f0, f1, rampe=0.15):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    g = np.clip((f - f0 * (1 - rampe)) / (2 * rampe * f0), 0, 1) \
        * np.clip((f1 * (1 + rampe) - f) / (2 * rampe * f1), 0, 1)
    return np.fft.irfft(X * g, len(x))


def rose(m):
    Xr = np.fft.rfft(rng.standard_normal(m))
    fr = np.fft.rfftfreq(m, 1.0 / SR)
    Xr[1:] /= np.sqrt(fr[1:])
    return np.fft.irfft(Xr, m)


def boucle(x, fondu=0.25):
    """Raccorde la fin sur le début (fondu enchaîné de `fondu` s)."""
    k = int(fondu * SR)
    w = np.linspace(0, 1, k)
    x = x.copy()
    x[:k] = x[:k] * w + x[-k:] * (1 - w)
    return x[:-k]


def ecrire(nom, x, crete_db=-3.0):
    os.makedirs(SORTIE, exist_ok=True)
    x = x / (np.max(np.abs(x)) + 1e-9) * 10 ** (crete_db / 20.0)
    chemin = os.path.join(SORTIE, nom + ".wav")
    with wave.open(chemin, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    print(chemin, "%.1f s" % (len(x) / SR))


def raie(t, f, a, gigue=0.004):
    """Raie tonale qui flotte un peu (moteur sous charge)."""
    ph = 2 * np.pi * np.cumsum(f * (1 + gigue * np.sin(2 * np.pi * 0.31 * t))) / SR
    return a * np.sin(ph)


def choc(m, f0, decroit, bruit=0.5):
    """Un choc : sinus amorti + bruit filtré amorti."""
    t = np.arange(m) / SR
    env = np.exp(-t / decroit)
    s = np.sin(2 * np.pi * f0 * t) * env
    n = bande(rng.standard_normal(m), f0 * 0.7, f0 * 4.0) * env * bruit
    return s + n


# --- gare de débrayable ------------------------------------------------------------
n = int(8.25 * SR)
t = np.arange(n) / SR
x = raie(t, 291.0, 0.35) + raie(t, 582.0, 0.08) + raie(t, 78.0, 0.45) + raie(t, 156.0, 0.12)
x += bande(rose(n), 250, 500) * 3.0                     # pneus des lanceurs
x += bande(rose(n), 60, 200) * 2.0
# claquements de pinces sur le rail, irréguliers
for k in range(6):
    p = int(rng.uniform(0.2, 7.8) * SR)
    c = choc(int(0.12 * SR), rng.uniform(900, 1400), 0.02, 0.8) * 0.5
    x[p:p + len(c)] += c[: len(x) - p]
ecrire("gare_debrayable", boucle(x))

# --- gare à pinces fixes -----------------------------------------------------------
x = raie(t, 78.0, 0.5) + raie(t, 210.0, 0.18) + raie(t, 420.0, 0.05)
x += bande(rose(n), 80, 300) * 2.0
x += bande(rose(n), 300, 900) * 0.6                      # câble sur la poulie
ecrire("gare_fixe", boucle(x))

# --- lanceur (pneus) : joué avec pitch_scale ∝ vitesse ----------------------------
n2 = int(2.25 * SR)
t2 = np.arange(n2) / SR
x = bande(rose(n2), 120, 900) * 2.5
# battement des pneus successifs (pas 0,7 m à 5 m/s ≈ 7 Hz)
x *= 1.0 + 0.45 * np.sin(2 * np.pi * 7.0 * t2)
x += raie(t2, 180.0, 0.15, 0.01)
ecrire("lanceur", boucle(x, 0.1))

# --- en ligne, assis ---------------------------------------------------------------
n3 = int(12.25 * SR)
t3 = np.arange(n3) / SR
lent = 0.7 + 0.3 * np.sin(2 * np.pi * 0.07 * t3) * np.sin(2 * np.pi * 0.023 * t3 + 1.0)
x = bande(rose(n3), 250, 1000) * 2.0 * lent                  # vent
x += bande(rose(n3), 40, 160) * 0.8                           # câble
x += bande(rng.standard_normal(n3), 1400, 1800) * 0.05 * lent  # fil qui siffle
ecrire("ligne_siege", boucle(x))

# --- intérieur de cabine -----------------------------------------------------------
x = bande(rose(n3), 50, 300) * 2.5
x += bande(rose(n3), 300, 900) * 0.5 * lent
x += bande(rng.standard_normal(n3), 2500, 3200) * 0.03 * lent   # joints de porte
ecrire("ligne_cabine", boucle(x))

# --- intérieur de grande cabine (3S, téléphérique) ---------------------------------
x = bande(rose(n3), 35, 220) * 3.0
x += bande(rose(n3), 220, 600) * 0.6
x *= 1.0 + 0.12 * np.sin(2 * np.pi * 2.3 * t3)                 # galets du chariot
ecrire("ligne_3s", boucle(x))

# --- téléski ------------------------------------------------------------------------
x = bande(rose(n3), 600, 3000) * 0.8 * (1.0 + 0.3 * np.sin(2 * np.pi * 0.9 * t3))   # skis
x += bande(rose(n3), 80, 300) * 0.6                                                  # câble
ecrire("teleski", boucle(x))

# --- galets -------------------------------------------------------------------------
ecrire("galet_support", choc(int(0.18 * SR), 140.0, 0.035, 0.6) + 0.4 * choc(int(0.18 * SR), 420.0, 0.012, 0.3), -6.0)
ecrire("galet_compression", choc(int(0.15 * SR), 380.0, 0.02, 0.9) + 0.5 * choc(int(0.15 * SR), 1300.0, 0.006, 0.5), -6.0)

# --- arrêt d'urgence ------------------------------------------------------------------
n4 = int(3.0 * SR)
t4 = np.arange(n4) / SR
x = choc(n4, 95.0, 0.25, 1.0)
x += choc(n4, 700.0, 0.05, 1.0) * 0.6
x += np.sin(2 * np.pi * 2.1 * t4) * bande(rose(n4), 60, 250) * np.exp(-t4 / 1.2) * 1.5   # câble qui balance
ecrire("arret_urgence", x)


# --- huées de la file d'attente ---------------------------------------------------------
# « whouuu » de la file qu'on vient de griller au portique (retour d'utilisateur,
# 25/10/2026) : 26 voix sur la voyelle [u], qui montent puis retombent, deux
# sifflets, la rumeur de la foule. Tirage à part : les sons ci-dessus ne bougent pas.
from scipy.signal import lfilter

rng_h = np.random.default_rng(20261025)


def resonateur(x, f, bw):
    r = np.exp(-np.pi * bw / SR)
    a = [1.0, -2 * r * np.cos(2 * np.pi * f / SR), r * r]
    return lfilter([1.0 - r], a, x)


def voix(duree, f0, monte, femme):
    """Un « whouuu » : souffle à l'attaque, voyelle [u] qui monte puis tombe."""
    m = int(duree * SR)
    t = np.arange(m) / SR
    u = t / duree
    # contour : attaque montante, longue descente (hou-ou-ou)
    cont = np.where(u < 0.15, 1.0 + monte * u / 0.15, 1.0 + monte - (monte + 0.25) * (u - 0.15) / 0.85)
    vib = 1.0 + 0.012 * np.sin(2 * np.pi * rng_h.uniform(4.5, 6.5) * t + rng_h.uniform(0, 6))
    f = f0 * cont * vib
    ph = 2 * np.pi * np.cumsum(f) / SR
    # source glottale : dents de scie adoucies
    src = sum(np.sin(k * ph) / k ** 1.3 for k in range(1, 28) if k * f0 * 1.6 < SR / 2)
    src += 0.25 * rng_h.standard_normal(m)                    # souffle dans la voix
    k = 1.15 if femme else 1.0
    y = resonateur(src, 320 * k, 80) + 0.5 * resonateur(src, 800 * k, 100) + 0.08 * resonateur(src, 2300 * k, 160)
    # « wh » : souffle seul les 120 premières ms
    souffle = bande(rng_h.standard_normal(m), 300, 1500) * np.exp(-t / 0.08)
    env = np.minimum(1, t / 0.18) * np.minimum(1, (duree - t) / 0.5) ** 1.5
    return (y / (np.max(np.abs(y)) + 1e-9) + 0.4 * souffle / (np.max(np.abs(souffle)) + 1e-9)) * env


def huees():
    D = 3.6
    m = int(D * SR)
    x = np.zeros(m)
    for _ in range(26):
        femme = rng_h.random() < 0.4
        f0 = rng_h.uniform(170, 260) if femme else rng_h.uniform(95, 150)
        d = rng_h.uniform(1.6, 2.7)
        t0 = rng_h.uniform(0.0, 0.55) + rng_h.exponential(0.12)
        v = voix(d, f0, rng_h.uniform(0.15, 0.45), femme) * rng_h.uniform(0.4, 1.0)
        i0 = int(t0 * SR)
        n = min(len(v), m - i0)
        x[i0:i0 + n] += v[:n]
    # un sifflet ou deux, une rumeur de foule
    for _ in range(2):
        t0 = rng_h.uniform(0.3, 1.0)
        d = rng_h.uniform(0.7, 1.1)
        n = int(d * SR)
        tt = np.arange(n) / SR
        fs = rng_h.uniform(1900, 2600) * (1 + 0.15 * np.sin(np.pi * tt / d)) - 400 * tt
        sif = np.sin(2 * np.pi * np.cumsum(fs) / SR) * np.minimum(1, tt / 0.05) * np.minimum(1, (d - tt) / 0.15)
        i0 = int(t0 * SR)
        x[i0:i0 + n] += 0.12 * sif
    t = np.arange(m) / SR
    x += 0.18 * bande(rose(m), 150, 2500) * np.minimum(1, t / 0.3) * np.minimum(1, (D - t) / 1.0)
    # léger espace : deux échos courts (la gare, la neige)
    y = x.copy()
    for dl, g in [(0.045, 0.25), (0.11, 0.15)]:
        k = int(dl * SR)
        y[k:] += g * x[:-k]
    return bande(y, 80, 6000)


ecrire("file_huees", huees(), -4.0)
