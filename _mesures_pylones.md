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

## tsd6_aiguille_percee

10 pylônes réels, numérotés de l'aval (photos numérotées) : même nombre et même ordre que le JSON ; P1 contre la gare aval,
P5-P6 et P8-P9 groupés, P10 contre la gare amont. Hauteur : rapport hauteur / traverse (≈ 7,5 m) sur une photo, en contre-plongée.

| n° réel | d JSON (m) | source du n° | h_min | h_max | source h | statut |
|---|---|---|---|---|---|---|
| P1 | 45 | photo | 6,5 | 9 | photo | certain (n°), incertain (h) |
| P2 | 217 | photo | 15 | 20 | photo | certain (n°), incertain (h) |
| P3 | 357 | photo | 12 | 16 | photo | certain (n°), incertain (h) |
| P4 | 534 | photo | 18 | 24 | photo | certain (n°), incertain (h) |
| P5 | 661 | photo | 15 | 19 | photo | certain (n°), incertain (h) |
| P6 | 680 | photo | 15 | 19 | photo | certain (n°), incertain (h) |
| P7 | 792 | photo | 14 | 18 | photo | certain (n°), incertain (h) |
| P8 | 870 | photo | 16 | 21 | photo | certain (n°), incertain (h) |
| P9 | 889 | photo | 20 | 26 | photo | certain (n°), incertain (h) |
| P10 | 965 | photo | 10 | 14 | photo | certain (n°), incertain (h) |

## tke_legettaz

**5 pylônes réels, numérotés sur les plaques (photos) ; le JSON en a 4.** Les d du JSON sont équidistants (64,3 / 128,6 / 193,0 /
257,3) : positions de remplissage, sans mesure, non marquées `reconstitue`. P3 et P4 sont côte à côte, décalés ; la pente atteint 60 % vers P5
(reportage). d réels et hauteurs : non vus (pas de vidéo, pas d'échelle).

## tke_lavachet

3 pylônes, P1 et P3 photographiés, 2S/2S d'après le reportage (JSON : [4, S] par pylône, sans brin distinct, à comparer). d équidistants
dans le JSON (65,2 / 130,3 / 195,5) : remplissage. d et hauteurs : non vus.

## tke_savonnette_1, tke_savonnette_2

2 pylônes chacun (reportage). **Longueurs 237 et 198 m au reportage ; 208 m pour les deux au JSON.** d équidistants dans le JSON
(69,4 / 138,8) : remplissage. Galets au reportage, I | II : P1 1S-1C | 1S-1C ; P2 1S-1C/1S | 1S/1S (JSON : [4, S] partout). d et hauteurs : non vus.

## tke_termignon_1, tke_termignon_2

7 pylônes, numérotés du reportage, photos de P2, P3, P5, P6, P7. **Formes différentes de deux lignes indépendantes : P2 = deux fûts séparés ; P3, P6, P7 =
portiques communs aux deux lignes ; P5 = fût unique et double potence en T.** P2, P3, P6, P7 sur glace (reportage). d du JSON : 3 `reconstitue` (91,6 ; 491,5 ; 489,2), voir
le rapport précédent (un pylône vu à ~476 m). Hauteurs : non mesurées (pas d'échelle fiable).

## tsf3_mont_blanc

14 ouvrages P0 à P13 (reportage), même nombre que le JSON. Montée/descente : P0 8C/8C · P1 8C/8C · P2 4SC/8S · P3 8S/rien · P4 8S/4S · P5 8S/4S · P6 8S/4S ·
P7 8S/8S · P8 8S/4S · P9 8S/2S · P10 8S/4S · P11 8S/4S · P12 8S/4S · P13 8S/8S. **P3 ne porte que le brin montant.** Numérotation à partir de P0 : rang = n° + 1.

## tkd_col_du_palet

14 passages en vidéo montante pour 14 pylônes au reportage et au JSON. Vitesse déduite entre passages et d du JSON : 3,1 à 3,6 m/s, sans anomalie : **les d du JSON tiennent.**
N° par ordre (plaques illisibles sur la vidéo) : ESTIMÉ, sauf P3, nommé au reportage. P3 est une compression au reportage ; le JSON met S partout. P9 a deux fûts côte à côte en vidéo. Hauteurs : non mesurées (pas d'échelle).

| n° | passage (s) | d JSON (m) | statut |
|---|---|---|---|
| P1 | 56 | 76 | ESTIMÉ (ordre) |
| P2 | 82,5 | 167 | ESTIMÉ (ordre) |
| P3 | 110 | 264 | photo + ordre |
| P4 | 136 | 354 | ESTIMÉ (ordre) |
| P5 | 158 | 431 | ESTIMÉ (ordre) |
| P6 | 186 | 528 | ESTIMÉ (ordre) |
| P7 | 216 | 636 | ESTIMÉ (ordre) |
| P8 | 237 | 702 | ESTIMÉ (ordre) |
| P9 | 264 | 799 | ESTIMÉ (ordre), deux fûts |
| P10 | 298 | 917 | ESTIMÉ (ordre) |
| P11 | 332 | 1036 | ESTIMÉ (ordre) |
| P12 | 366 | 1154 | ESTIMÉ (ordre) |
| P13 | 394 | 1251 | ESTIMÉ (ordre) |
| P14 | 430 | 1370 | ESTIMÉ (ordre) |

## tkd_chardonnet

Reportage : brin montant 12 pylônes, brin descendant 4, le plus haut commun, soit 15 ouvrages sur un tracé en quadrilatère. **Le JSON ne porte que les 12 du brin montant.** Un pylône du brin descendant se voit à droite vers 34-40 s.
Passages du brin montant : ~16, 25, 58, 92, 117, 136, 170, 202, 224, 252, 278, 292 s, contre les d 18, 41, 142, 243, 320, 379, 480, 569, 640, 717, 794, 841 du JSON : ~3 m/s, sans anomalie, **les d tiennent**, les deux premiers moins sûrs (contre la gare).
N° : P1 à P10, P12, P13 photographiés (numérotation du reportage, à recouper avec les rangs : le brin descendant y porte 13 à 15). Reste ESTIMÉ par ordre. Hauteurs : non mesurées.

## tkd_combe_folle

12 pylônes photographiés et numérotés (reportage), comme le JSON. P1, P2, P3 enchaînés. Le n° 8 est une compression (reportage), le JSON met S partout. P6 ouvre une série qui ne porte que le brin descendant ou montant, à préciser (légende). d et hauteurs : pas de nouveau relevé.

## tkd_signal_1, tkd_signal_2

Plusieurs reportages portent ce nom dans d'autres stations : le bon appareil **n'est pas établi** dans mes lectures ; aucune valeur reprise. Vidéo déjà relevée, voir le rapport précédent.

## Lignes à `reconstitue` : ce qui est établi

Les photos numérotées prouvent l'existence et l'ordre, pas la position. Vues depuis la cabine, trop plongeantes pour une hauteur fiable : hauteurs non mesurées.

| ligne | n réel (reportage) | n JSON | `reconstitue` | établi |
|---|---|---|---|---|
| tcd10_solaise | 16, P1 à P16 photographiés | 16 | 28,8 | P1 « en sortie de gare » : compatible ; d non mesuré |
| tcd10_vallon_iseran | 17, P3 à P16 photographiés | 17 | 1452,3 | nombre confirmé ; d non mesuré, vidéo de l'ancien appareil |
| tsd6_bollin | 10, P2 à P10 photographiés | 10 | 413,2 ; 533,0 | P10 « avant l'entrée en gare » : compatible |
| tsd6_fresse | 19, P2 à P19 photographiés, P9, P15, P16 compressions | 19 | 934,0 ; 1848,8 | compressions conformes au JSON (rangs 9, 15, 16) ; d non mesuré |
| tsd6_marais | 23, dont 7 compressions, P12 et P15 support-compression | 23 | 8 valeurs | 7 C et 2 SC conformes au JSON ; d non mesurés, vidéo de l'ancien appareil |
| tsd6_fontaine_froide | non recompté | 10 | 23,7 | vidéo plus complète à exploiter ; non fait |

Voie d'après le reportage : Bollin 7,35 m, Fresse 6,00 m.
