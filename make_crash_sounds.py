#!/usr/bin/env python3
"""Génère les trois sons d'accident du mode Défi (version 3D / web).

Aucun échantillon externe n'est utilisé : tout est SYNTHÉTISÉ ici, en
Python standard (pas de dépendance), pour que les fichiers soient
reproductibles et sans question de licence. Sortie :

    godot_project/sounds/crash_impact.wav   collision au butoir (~2,6 s)
    godot_project/sounds/derail.wav         déraillement à l'évitement (~3,6 s)
    godot_project/sounds/game_over.wav      sting de fin de service (~4,2 s)

Format : WAV PCM 16 bits, 44 100 Hz, mono — identique aux autres sons du
projet Godot. Le tirage aléatoire est fixé (graine constante) : relancer
le script régénère des fichiers rigoureusement identiques.

Usage : python3 make_crash_sounds.py
"""

from __future__ import annotations

import math
import random
import struct
import os

RATE = 44100
SEED = 20260821


# ---------------------------------------------------------------------------
# Outillage : buffers, filtres, écriture WAV
# ---------------------------------------------------------------------------

def buf(seconds: float) -> list[float]:
    return [0.0] * int(seconds * RATE)


def add(dst: list[float], src: list[float], at: float, gain: float = 1.0) -> None:
    """Mixe src dans dst à partir de l'instant `at` (secondes)."""
    i0 = int(at * RATE)
    for i, v in enumerate(src):
        j = i0 + i
        if 0 <= j < len(dst):
            dst[j] += v * gain


def noise(n: int, rng: random.Random) -> list[float]:
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def lowpass(x: list[float], cutoff: float) -> list[float]:
    """Un pôle — suffisant pour dégrossir un bruit."""
    a = math.exp(-2.0 * math.pi * cutoff / RATE)
    y, prev = [], 0.0
    for v in x:
        prev = (1.0 - a) * v + a * prev
        y.append(prev)
    return y


def highpass(x: list[float], cutoff: float) -> list[float]:
    a = math.exp(-2.0 * math.pi * cutoff / RATE)
    y, prev_x, prev_y = [], 0.0, 0.0
    for v in x:
        prev_y = a * (prev_y + v - prev_x)
        prev_x = v
        y.append(prev_y)
    return y


def bandpass(x: list[float], f0: float, q: float) -> list[float]:
    """Biquad passe-bande (Audio EQ Cookbook) — sert aux crissements."""
    w0 = 2.0 * math.pi * f0 / RATE
    alpha = math.sin(w0) / (2.0 * q)
    b0, b1, b2 = alpha, 0.0, -alpha
    a0, a1, a2 = 1.0 + alpha, -2.0 * math.cos(w0), 1.0 - alpha
    b0, b1, b2 = b0 / a0, b1 / a0, b2 / a0
    a1, a2 = a1 / a0, a2 / a0
    y = []
    x1 = x2 = y1 = y2 = 0.0
    for v in x:
        out = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, v
        y2, y1 = y1, out
        y.append(out)
    return y


def env_exp(n: int, tau: float, attack: float = 0.002) -> list[float]:
    """Enveloppe percussive : attaque courte puis décroissance en e^(-t/tau)."""
    na = max(1, int(attack * RATE))
    out = []
    for i in range(n):
        a = i / na if i < na else 1.0
        out.append(a * math.exp(-(i / RATE) / tau))
    return out


def thump(rng: random.Random, f0: float, f1: float, tau: float,
          dur: float) -> list[float]:
    """Choc grave : sinus qui glisse de f0 à f1 + bruit d'attaque."""
    n = int(dur * RATE)
    env = env_exp(n, tau, 0.001)
    out = []
    phase = 0.0
    for i in range(n):
        k = i / max(n - 1, 1)
        f = f0 + (f1 - f0) * k
        phase += 2.0 * math.pi * f / RATE
        out.append(math.sin(phase) * env[i])
    # Attaque : bruit très bref filtré bas, pour l'impression de masse
    na = int(0.05 * RATE)
    hit = lowpass(noise(na, rng), 400.0)
    henv = env_exp(na, 0.012, 0.0005)
    for i in range(na):
        out[i] += hit[i] * henv[i] * 0.9
    return out


def metal_ring(f_list: list[float], tau: float, dur: float,
               detune: float = 0.0) -> list[float]:
    """Résonances INHARMONIQUES : c'est ce qui fait « tôle » et pas « note »."""
    n = int(dur * RATE)
    out = [0.0] * n
    for k, f in enumerate(f_list):
        env = env_exp(n, tau * (1.0 - 0.12 * k), 0.001)
        phase = 0.0
        vib = detune * (k + 1)
        for i in range(n):
            f_i = f * (1.0 + vib * math.sin(2.0 * math.pi * 3.1 * i / RATE))
            phase += 2.0 * math.pi * f_i / RATE
            out[i] += math.sin(phase) * env[i] / (k + 1.6)
    return out


def soft_clip(x: float) -> float:
    return math.tanh(x)


def write_wav(path: str, data: list[float], peak: float = 0.92) -> None:
    # Fondus de bord : sans eux, la coupure nette de la queue (partiels
    # métalliques encore audibles) fait un clic — très net au casque.
    fade_in, fade_out = int(0.002 * RATE), int(0.12 * RATE)
    n_tot = len(data)
    for i in range(min(fade_in, n_tot)):
        data[i] *= i / fade_in
    for i in range(min(fade_out, n_tot)):
        k = i / fade_out
        data[n_tot - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * k)
    m = max(1e-9, max(abs(v) for v in data))
    g = peak / m
    frames = bytearray()
    for v in data:
        s = int(max(-1.0, min(1.0, soft_clip(v * g))) * 32767.0)
        frames += struct.pack("<h", s)
    n = len(frames)
    hdr = b"RIFF" + struct.pack("<I", 36 + n) + b"WAVEfmt " \
        + struct.pack("<IHHIIHH", 16, 1, 1, RATE, RATE * 2, 2, 16) \
        + b"data" + struct.pack("<I", n)
    with open(path, "wb") as f:
        f.write(hdr + bytes(frames))
    print("  %-26s %5.2f s  %7d octets" % (os.path.basename(path),
                                           len(data) / RATE, len(hdr) + n))


# ---------------------------------------------------------------------------
# 1. Collision au butoir — 32 t lancées dans un mur de béton
# ---------------------------------------------------------------------------

def make_crash(rng: random.Random) -> list[float]:
    out = buf(2.7)

    # Fracas d'attaque : bruit large bande, très bref
    n = int(0.35 * RATE)
    crack = highpass(noise(n, rng), 250.0)
    cenv = env_exp(n, 0.055, 0.0006)
    add(out, [crack[i] * cenv[i] for i in range(n)], 0.0, 0.85)

    # Le choc lui-même : la masse qui s'écrase (glissando descendant)
    add(out, thump(rng, 78.0, 34.0, 0.42, 1.6), 0.0, 1.0)
    # Reculs / seconds contacts : le train est en deux voitures couplées
    add(out, thump(rng, 62.0, 30.0, 0.22, 0.9), 0.14, 0.55)
    add(out, thump(rng, 52.0, 27.0, 0.16, 0.7), 0.33, 0.35)

    # Tôles et structure : partiels inharmoniques qui sonnent longtemps
    add(out, metal_ring([287.0, 431.0, 719.0, 1103.0, 1571.0, 2287.0],
                        0.55, 1.8, 0.0015), 0.01, 0.34)

    # Débris : verre et gravats qui retombent
    for _ in range(70):
        t = rng.uniform(0.06, 1.9)
        nd = int(rng.uniform(0.01, 0.05) * RATE)
        d = bandpass(noise(nd, rng), rng.uniform(1800.0, 6500.0), 6.0)
        de = env_exp(nd, 0.012, 0.0004)
        amp = 0.30 * math.exp(-t / 0.8) * rng.uniform(0.3, 1.0)
        add(out, [d[i] * de[i] for i in range(nd)], t, amp)

    # Queue : poussière et grondement résiduel
    nt = int(1.6 * RATE)
    tail = lowpass(noise(nt, rng), 220.0)
    tenv = env_exp(nt, 0.55, 0.05)
    add(out, [tail[i] * tenv[i] for i in range(nt)], 0.25, 0.35)
    return out


# ---------------------------------------------------------------------------
# 2. Déraillement — les boudins sortent du rail à l'aiguillage Abt
# ---------------------------------------------------------------------------

def make_derail(rng: random.Random) -> list[float]:
    out = buf(3.6)

    # Crissement : bruit passe-bande modulé + glissando descendant (l'acier
    # qui frotte l'acier, hauteur qui tombe avec la vitesse)
    n = int(2.4 * RATE)
    raw = noise(n, rng)
    grind = bandpass(raw, 1500.0, 1.2)
    grind2 = bandpass(raw, 3200.0, 3.0)
    genv = []
    for i in range(n):
        t = i / RATE
        a = min(1.0, t / 0.06) * math.exp(-t / 1.25)
        # Broutement : la rame tape les traverses ~22 Hz en ralentissant
        f_mod = 22.0 * (1.0 - 0.55 * t / 2.4)
        a *= 0.55 + 0.45 * abs(math.sin(2.0 * math.pi * f_mod * t))
        genv.append(a)
    add(out, [(grind[i] * 0.75 + grind2[i] * 0.45) * genv[i]
              for i in range(n)], 0.0, 0.9)

    # Squeal : deux résonances de roue qui descendent
    ns = int(1.5 * RATE)
    sq = [0.0] * ns
    for f0, f1, amp in ((2450.0, 1650.0, 0.5), (3620.0, 2380.0, 0.28)):
        phase = 0.0
        for i in range(ns):
            k = i / (ns - 1)
            f = f0 + (f1 - f0) * k
            f *= 1.0 + 0.012 * math.sin(2.0 * math.pi * 7.3 * i / RATE)
            phase += 2.0 * math.pi * f / RATE
            e = min(1.0, i / (0.08 * RATE)) * math.exp(-(i / RATE) / 0.75)
            sq[i] += math.sin(phase) * e * amp
    add(out, sq, 0.05, 0.55)

    # Chocs sur les traverses : espacés de plus en plus (la rame ralentit)
    t, dt = 0.10, 0.115
    while t < 2.6:
        add(out, thump(rng, rng.uniform(70.0, 96.0), 38.0, 0.10, 0.45), t,
            0.55 * math.exp(-t / 1.5))
        dt *= 1.16
        t += dt

    # Impact final : la rame s'immobilise contre la paroi du tube
    add(out, thump(rng, 66.0, 31.0, 0.35, 1.3), 2.35, 0.9)
    add(out, metal_ring([196.0, 337.0, 611.0, 962.0], 0.8, 1.2, 0.002),
        2.36, 0.4)

    # Ballast projeté
    for _ in range(45):
        tt = rng.uniform(2.4, 3.3)
        nd = int(rng.uniform(0.008, 0.03) * RATE)
        d = bandpass(noise(nd, rng), rng.uniform(1200.0, 5200.0), 5.0)
        de = env_exp(nd, 0.010, 0.0004)
        add(out, [d[i] * de[i] for i in range(nd)], tt,
            0.25 * math.exp(-(tt - 2.4) / 0.5))
    return out


# ---------------------------------------------------------------------------
# 3. Game over — sting sobre de fin de service
# ---------------------------------------------------------------------------

def make_game_over(rng: random.Random) -> list[float]:
    out = buf(4.2)

    # Bourdon grave qui s'installe (l'installation qui se met à l'arrêt)
    n = int(4.0 * RATE)
    drone = [0.0] * n
    for f, amp in ((36.7, 0.55), (55.0, 0.35), (110.0, 0.14)):
        phase = 0.0
        for i in range(n):
            phase += 2.0 * math.pi * f / RATE
            t = i / RATE
            e = min(1.0, t / 0.35) * min(1.0, (4.0 - t) / 1.2)
            drone[i] += math.sin(phase) * amp * e
    add(out, drone, 0.0, 0.5)

    # Trois notes descendantes (ré mineur : A3 → F3 → D3), timbre d'orgue
    # de gare : fondamentale + quinte + octave, attaque douce.
    notes = ((220.00, 0.00), (174.61, 0.62), (146.83, 1.24))
    for f, t0 in notes:
        nn = int(1.5 * RATE)
        v = [0.0] * nn
        for mult, amp in ((1.0, 0.6), (1.5, 0.22), (2.0, 0.28), (3.0, 0.10)):
            phase = 0.0
            for i in range(nn):
                phase += 2.0 * math.pi * f * mult / RATE
                tt = i / RATE
                e = min(1.0, tt / 0.03) * math.exp(-tt / 0.62)
                v[i] += math.sin(phase) * amp * e
        add(out, v, t0, 0.42)

    # Accord final tenu, une octave plus bas
    nf = int(2.4 * RATE)
    fin = [0.0] * nf
    for f, amp in ((73.42, 0.55), (110.00, 0.30), (87.31, 0.30),
                   (146.83, 0.18)):
        phase = 0.0
        for i in range(nf):
            phase += 2.0 * math.pi * f / RATE
            tt = i / RATE
            e = min(1.0, tt / 0.12) * math.exp(-tt / 1.3)
            fin[i] += math.sin(phase) * amp * e
    add(out, fin, 1.75, 0.6)

    # Souffle de salle des machines qui retombe (bruit très filtré)
    nb = int(3.0 * RATE)
    br = lowpass(noise(nb, rng), 160.0)
    be = [min(1.0, (i / RATE) / 0.5) * math.exp(-(i / RATE) / 1.5)
          for i in range(nb)]
    add(out, [br[i] * be[i] for i in range(nb)], 0.4, 0.22)
    return out


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.join(here, "godot_project", "sounds")
    os.makedirs(out_dir, exist_ok=True)
    print("Synthese des sons d'accident (graine %d) :" % SEED)
    rng = random.Random(SEED)
    write_wav(os.path.join(out_dir, "crash_impact.wav"), make_crash(rng))
    rng = random.Random(SEED + 1)
    write_wav(os.path.join(out_dir, "derail.wav"), make_derail(rng))
    rng = random.Random(SEED + 2)
    write_wav(os.path.join(out_dir, "game_over.wav"), make_game_over(rng))


if __name__ == "__main__":
    main()
