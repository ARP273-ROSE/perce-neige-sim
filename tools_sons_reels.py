"""Sons RÉELS des remontées (25/10/2026), tirés de vidéos enregistrées depuis
l'intérieur d'une cabine — extraits choisis par un utilisateur, avec l'accord de
l'auteur des vidéos. Régénérables à partir de la piste audio de chaque vidéo :
    python3 tools_sons_reels.py 3s  piste_3s.wav    → godot_project/sounds/remontees/3s_*.wav
    python3 tools_sons_reels.py tcd piste_tcd.wav   → godot_project/sounds/remontees/tcd_*.wav
    python3 tools_sons_reels.py tkd piste_tkd.wav   → godot_project/sounds/remontees/tkd_*.wav
    python3 tools_sons_reels.py tsf piste_tsf.wav   → godot_project/sounds/remontees/tsf_*.wav
    python3 tools_sons_reels.py tsd piste_tsd.wav   → godot_project/sounds/remontees/tsd_*.wav
    python3 tools_sons_reels.py boisses piste.wav   → godot_project/sounds/remontees/boisses_*.wav

3s — un 3S Doppelmayr de la même génération que l'Olympique (téléphérique des
Prodains, Avoriaz) :
  3s_gare          0:09–0:15   cabine en gare, portes ouvertes          (boucle)
  3s_lanceur_acc   0:28–0:42   accélération dans le lanceur au départ
  3s_ligne         1:00–1:07   en ligne                                 (boucle)
  3s_pylone        2:55–2:59   passage d'un pylône (chocs vers 1,5–2,9 s)
  3s_lanceur_dec   6:35–6:42   freinage dans le lanceur à l'arrivée
  3s_motrice       6:44–6:50   gare motrice, portes fermées             (boucle)
tcd — une télécabine débrayable de 8 places (Saulire Express 2, Méribel) :
  tcd_gare         0:00–0:03   cabine en gare                           (boucle)
  tcd_lanceur_acc  0:09–0:16   accélération au départ
  tcd_pyl_cc       0:17–0:21   deux pylônes de compression rapprochés (choc vers 2,9 s)
  tcd_pyl_s        0:31–0:33   pylône porteur, 6 galets (choc vers 1,1 s)
  tcd_ligne        3:09–3:11   en ligne                                 (boucle)
  tcd_pyl_sc       4:27,5–4:30 pylône porteur et compression, 2 × 4 galets (choc vers 0,6 s)
  tcd_pyl_c        5:00–5:10   approche et passage d'une compression : la cabine
                               vibre de plus en plus avant le pylône (choc vers 6,8 s)
  tcd_lanceur_dec  6:21–6:24   freinage à l'entrée en gare
tkd — un téléski DÉBRAYABLE (Tête de Torraz, La Giettaz), pour les TKD seulement
(les téléskis à enrouleur sont différents) :
  tkd_gare          0:00–0:06   au départ                                (boucle)
  tkd_depart        0:15–0:19,5 prise de la perche, départ
  tkd_ligne         0:25–0:30   tracté en ligne                          (boucle)
  tkd_pyl_s         0:40–0:41   pylône (choc vers 0,5 s)
  tkd_pyl_c         2:08–2:09   pylône de compression (choc vers 0,3 s)
  tkd_lacher        3:28–3:35   lâcher de la perche et son retour (avec du vent)
tsf — un télésiège à pinces fixes (les Souffles, Hirmentaz), pour les TSF :
  tsf_motrice      0:40–0:45   gare motrice (aval)                      (boucle)
  tsf_arret        0:55–1:04   arrêt normal, la motrice ralentit et se tait
  tsf_redemarrage  1:11–1:20   redémarrage, avec le klaxon
  tsf_embarquement 1:53–2:00   le siège prend le skieur au départ
  tsf_pyl_c        2:26–2:31   pylône de compression
  tsf_ligne        3:05–3:14   en ligne : presque rien                  (boucle)
  tsf_pyl_s        3:59–4:04   pylône porteur
  tsf_arrivee      6:10–6:17   gare d'arrivée, sans moteur              (boucle)
  tsf_ruisseau     2:35–2:42   un ruisseau sous la ligne, au début du trajet : le
                               passage le plus régulier dans les aigus ; graves
                               retirés (câble, vent)                    (boucle)
tsd — un télésiège débrayable de 8 places (l'Altiport, Méribel), pour les TSD :
  tsd_forfait      0:12–0:15   validation du forfait sous le portique (toutes les remontées)
  tsd_gare         0:26–0:32   gare de départ                           (boucle)
  tsd_portillons   0:38–0:50   passage des portillons et tapis roulant
  tsd_embarquement 0:55–1:04   embarquement et accélération dans le lanceur
  tsd_pyl_cc       1:05–1:11   deux premiers pylônes de compression (avec du vent)
  tsd_pyl_s        2:05–2:08   pylône porteur (moins de vent qu'à 3:49 ; choc vers 1,6 s)
  tsd_ligne        2:10–2:15   en ligne, sans vent                      (boucle)
  tsd_arret        5:17–5:20   décélération jusqu'à l'arrêt en ligne
  tsd_arrete       5:24–5:36   arrêté en ligne                          (boucle)
  tsd_redemarrage  6:00–7:05   redémarrage : près d'une minute pour reprendre la
                               pleine vitesse, un pylône passé au ralenti
  tsd_arrivee      8:26–8:34   entrée en gare, décélération
  tsd_debarquement 8:34–8:40   débarquement
  tsd_gare_haut    8:46–8:54   gare d'arrivée                           (boucle)
boisses — la télécabine des Boisses elle-même (passages repérés à l'image) :
  boisses_gare        0:00–0:03   cabine en gare                        (boucle)
  boisses_lanceur_acc 0:03–0:12   départ, lanceur
  boisses_ligne       0:38–0:48   en ligne                              (boucle)
  boisses_pyl_s       2:52,5–2:56 pylône (choc vers 1,9 s)
  boisses_lanceur_dec 4:28–4:40   arrivée, lanceur
Les niveaux relatifs d'un même profil sont conservés (un seul gain par profil).
"""
import os
import sys
import wave

import numpy as np

SR = 22050
PROFILS = {
    "3s": [
        ("3s_gare", 9.0, 15.0, True),
        ("3s_lanceur_acc", 28.0, 42.0, False),
        ("3s_ligne", 60.0, 67.0, True),
        ("3s_pylone", 175.0, 179.0, False),
        ("3s_lanceur_dec", 395.0, 402.0, False),
        ("3s_motrice", 404.0, 410.0, True),
    ],
    "tcd": [
        ("tcd_gare", 0.0, 3.0, True),
        ("tcd_lanceur_acc", 9.0, 16.0, False),
        ("tcd_pyl_cc", 17.0, 21.0, False),
        ("tcd_pyl_s", 31.0, 33.0, False),
        ("tcd_ligne", 189.0, 191.0, True),
        ("tcd_pyl_sc", 267.5, 270.0, False),
        ("tcd_pyl_c", 300.0, 310.0, False),
        ("tcd_lanceur_dec", 381.0, 384.0, False),
    ],
    "tkd": [
        ("tkd_gare", 0.0, 6.0, True),
        ("tkd_depart", 15.0, 19.5, False),
        ("tkd_ligne", 25.0, 30.0, True),
        ("tkd_pyl_s", 40.0, 41.0, False),
        ("tkd_pyl_c", 128.0, 129.0, False),
        ("tkd_lacher", 208.0, 215.0, False),
    ],
    "tsf": [
        ("tsf_motrice", 40.0, 45.0, True),
        ("tsf_arret", 55.0, 64.0, False),
        ("tsf_redemarrage", 71.0, 80.0, False),
        ("tsf_embarquement", 113.0, 120.0, False),
        ("tsf_pyl_c", 146.0, 151.0, False),
        ("tsf_ligne", 185.0, 194.0, True),
        ("tsf_pyl_s", 239.0, 244.0, False),
        ("tsf_arrivee", 370.0, 377.0, True),
        ("tsf_ruisseau", 155.0, 162.0, True, 700.0),
    ],
    "tsd": [
        ("tsd_forfait", 12.0, 15.0, False),
        ("tsd_gare", 26.0, 32.0, True),
        ("tsd_portillons", 38.0, 50.0, False),
        ("tsd_embarquement", 55.0, 64.0, False),
        ("tsd_pyl_cc", 65.0, 71.0, False),
        ("tsd_pyl_s", 125.0, 128.0, False),
        ("tsd_ligne", 130.0, 135.0, True),
        ("tsd_arret", 317.0, 320.0, False),
        ("tsd_arrete", 324.0, 336.0, True),
        ("tsd_redemarrage", 360.0, 425.0, False),
        ("tsd_arrivee", 506.0, 514.0, False),
        ("tsd_debarquement", 514.0, 520.0, False),
        ("tsd_gare_haut", 526.0, 534.0, True),
    ],
    "boisses": [
        ("boisses_gare", 0.0, 3.0, True),
        ("boisses_lanceur_acc", 3.0, 12.0, False),
        ("boisses_ligne", 38.0, 48.0, True),
        ("boisses_pyl_s", 172.5, 176.0, False),
        ("boisses_lanceur_dec", 268.0, 280.0, False),
    ],
}
SORTIE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "godot_project", "sounds", "remontees")


def lire(chemin):
    with wave.open(chemin, "rb") as w:
        n = w.getnframes()
        sr = w.getframerate()
        ch = w.getnchannels()
        x = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float32) / 32768.0
    if ch > 1:
        x = x.reshape(-1, ch).mean(axis=1)
    if sr != SR:
        t = np.arange(int(len(x) * SR / sr)) / SR
        x = np.interp(t, np.arange(len(x)) / sr, x)
    return x


def boucle(x, fondu=0.5):
    fondu = min(fondu, len(x) / SR * 0.25)
    k = int(fondu * SR)
    w = np.linspace(0, 1, k)
    y = x.copy()
    y[:k] = x[:k] * w + x[-k:] * (1 - w)
    return y[:-k]


def bords(x, d=0.05):
    k = int(d * SR)
    y = x.copy()
    y[:k] *= np.linspace(0, 1, k)
    y[-k:] *= np.linspace(1, 0, k)
    return y


def main():
    x = lire(sys.argv[2])
    sons = {}
    for e in PROFILS[sys.argv[1]]:
        nom, a, b, en_boucle = e[:4]
        s = x[int(a * SR):int(b * SR)]
        s = s - s.mean()
        if len(e) > 4:
            # passe-haut (FFT, rampe d'une demi-octave)
            X = np.fft.rfft(s)
            f = np.fft.rfftfreq(len(s), 1.0 / SR)
            X *= np.clip((f - e[4] * 0.7) / (e[4] * 0.3), 0.0, 1.0)
            s = np.fft.irfft(X, len(s))
        sons[nom] = boucle(s) if en_boucle else bords(s)
    filtres = {e[0] for e in PROFILS[sys.argv[1]] if len(e) > 4}
    crete = max(np.max(np.abs(s)) for n, s in sons.items() if n not in filtres)
    gain = 10 ** (-3.0 / 20.0) / crete
    # (les prises filtrées, isolées de leur contexte, sont mises à −9 dB crête)
    for n in filtres:
        sons[n] = sons[n] * (10 ** (-9.0 / 20.0) / np.max(np.abs(sons[n]))) / gain
    os.makedirs(SORTIE, exist_ok=True)
    for nom, s in sons.items():
        with wave.open(os.path.join(SORTIE, nom + ".wav"), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes((np.clip(s * gain, -1, 1) * 32767).astype(np.int16).tobytes())
        print(nom, "%.1f s" % (len(s) / SR))


if __name__ == "__main__":
    main()
