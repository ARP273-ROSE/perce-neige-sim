# Mesures de pylônes (vidéo et photo)

Valeurs numériques seulement. Hauteurs pied → câble en mètres, brutes : échelle par la largeur de la traverse de tête,
biais de −10 à −20 % non corrigé.

- **rang** : place dans `pylones` du JSON de 379d064, en partant de l'aval (k = rang − 1).
- **n°** : numéro réel, lu sur la plaque ou donné par le reportage ; il peut différer du rang.
- **source** : `plaque` (lue sur la vidéo), `vidéo`, `photo` (copie locale du site, lecture seule), `déduit`.
- **statut** : `certain` ou `incertain`. « non vu » plutôt qu'une estimation.

## tsf4_grand_huit

Plaques 2 à 11 lues sur la vidéo. 14 pylônes réels. **Le JSON est décalé d'au moins un rang** : il lui manque P1 et il
contient deux `reconstitue` (483,9 et 607,1 m) à des places où aucun pylône n'a été vu.

| n° réel | d proposé (m) | source du n° | h_min | h_max | source h | statut |
|---|---|---|---|---|---|---|
| P1 | non vu (contre la gare, avant 17 m) | photo | 9 | 11 | photo, de loin | incertain |
| P2 | ~17 | plaque | 7,5 | 9,5 | photo | certain (n°), incertain (h) |
| P3 | 113,5 | plaque | 10 | 12 | vidéo + photo | certain |
| P4 | 158,5 | plaque | 12 | 14,5 | photo | certain |
| P5 | 265,1 | plaque | 10 | 12 | vidéo | certain |
| P6 | 314,7 | plaque | 8 | 10 | vidéo | certain |
| P7 | 418,0 | plaque | 11 | 15 | vidéo + photo | certain |
| P8 | 471,9 | plaque | 8 | 10 | vidéo + photo | certain |
| P9 | 499,6 | plaque | 7,5 | 9,5 | vidéo + photo | certain |
| P10 | 662,5 | plaque | 12 | 15 | vidéo, pylône entier à 362 s (remplace 9-12) | incertain |
| P11 | 703,7 | plaque | 14 | 17 | vidéo | certain |
| P12 | ~792 | déduit (ordre) | 5,5 | 7 | photo | incertain |
| P13 | ~800 | déduit (ordre) | 6 | 7,5 | photo | incertain |
| P14 | ~808 | plaque sur photo | 5 | 6,5 | photo | incertain (h) |

Passages vidéo (s) : P2 66 · P3 113 · P4 135 · P5 187 · P6 210 · P7 263 · P8 291 · P9 305 · P10 383 · P11 406 · P12 ~459 · P13 ~463 · P14 ~467.
Support-compression d'après le reportage : P5 et P6, soit 265 et 315 m (le JSON les met à 314,7 et 418).

## tcd10_toviere

Pas de plaque lisible depuis la cabine. N° par comparaison avec les photos numérotées et par recompte à 1 image/s.
16 pylônes réels, 16 passages. À retirer du JSON : 305 et 906 m.

| n° réel | passage (s) | d (m) | h_min | h_max | source h | statut |
|---|---|---|---|---|---|---|
| P1 | 60,6 | ~19 | 5 | 7 | vidéo | incertain (au contact de la gare) |
| P2 | 66 | ~41 | 9 | 13 | vidéo | incertain |
| P3 | 81 | ~102 | 18 | 21 | vidéo | certain |
| P4 | 111 | ~225 | 18 | 23 | vidéo | certain |
| P5 | 130,5 | ~340 | 12 | 16 | vidéo | certain |
| P6 | 158,5 | ~450 | 13 | 17 | photo | certain |
| P7 | 177,5 | ~548 | 17 | 22 | photo | certain |
| P8 | 195,5 | 640-683 | 11 | 14 | photo | incertain (position) |
| P9 | 217 | 754 | 15 | 20 | vidéo + photo | certain |
| P10 | 232,5 | 832 | 19 | 24 | vidéo + photo | certain |
| P11 | 261 | 1004 | 21 | 25 | vidéo + photo | certain |
| P12 | 289 | 1164 | 16 | 19 | vidéo + photo | certain |
| P13 | 317 | 1321 | 15 | 19 | vidéo + photo | certain |
| P14 | 367 | 1591 | 17,5 | 20,5 | vidéo + photo | certain |
| P15 | ~372-376 | non établi | non vu | non vu | | incertain |
| P16 | ~376 | non établi | non vu | non vu | | incertain |

## tsd6_leissieres

Les plaques ne se lisent pas sur cette vidéo. Le reportage numérote depuis l'amont du JSON : **n° réel = 15 − rang**.
L'ordre des rangs du tableau précédent reste valable. Le reportage confirme : 2 pylônes contre la gare (rangs 1, 2),
un pylône de compression (rang 6) et l'enchaînement de l'arête (rangs 7 à 11).

## tsf4_rogoney

8 pylônes réels (reportage), tous photographiés et numérotés. **Le `reconstitue` à 239,8 m n'est pas vu, et il manque un
pylône vers 524 m.** Le 8e cherché est celui de ~165 m. d à ~1,9 m/s, recalé sur les d OSM.

| n° réel | passage (s) | d (m) | h_min | h_max | source h | statut |
|---|---|---|---|---|---|---|
| P1 | 66 | 42,6 | 10 | 12 | photo | certain (position), incertain (h) |
| P2 | 98 | 103,9 | 13,5 | 15,5 | photo | certain (position), incertain (h) |
| P3 | ~128 | ~165 | 12,5 | 15 | photo | incertain (caméra détournée au passage) |
| P4 | 148 | 199,6 | 13 | 15 | photo | certain (position), incertain (h) |
| P5 | 202,5 | 302,8 | 10 | 12 | photo | certain (position), incertain (h) |
| P6 | ~257 | ~395 | 11 | non vu | photo, pied hors cadre | incertain |
| P7 | 302 | 473,2 | 6 | 7,5 | photo, sur une bosse | certain (position), incertain (h) |
| P8 | 329,5 | ~524 | non mesuré | non mesuré | | incertain (position) |

Galets d'après le reportage : P4 est le seul support-compression (4S-C) ; à comparer au JSON.
