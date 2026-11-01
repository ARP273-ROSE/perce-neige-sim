# Rapport PC sur ba4b49e (1.53.2)

Godot 4.6.1, Windows, Ryzen 9 5900X, RTX 5070 Ti, DLL de la Release v1.52.0. Rien n'est publié.

## 1. Bancs Windows (`--fixed-fps 60`, 4 en parallèle)

Échecs : 2 sur 35, les mêmes que sous Linux.

- `bench_skieur` : escalier de la fosse, pieds à -2,64 pour un fond à -3,55.
- `bench_ski` : écart au sol max 0,068 m pour 0,05 toléré, seuil inchangé. Descente n° 4, t = 405,37-405,40 s,
  position (85,2 ; 2658,65 ; 2020,5), 12,3 m/s, 3 images, skieur au-dessus du sol. Second pic de 0,034 m à t = 407,6 s.

Autres résultats :

- Verdict OK et sortie en code 139 : `poste_remontee`, `tunnel_piste`, `toutes_lignes` (plantage déjà connu à la fermeture).
- Sans verdict, code 0 : `auto`, `voyages` (relevés seuls, valeurs non vérifiées).
- `salle_machines` et `train_mesh` : écrivent par défaut dans `/tmp`, absent sous Windows, et tournent alors sans fin.
  OK avec un chemin en argument. `aiguillage` : même erreur à l'export, verdict OK.
- Les 25 autres, plus `defi` : OK, code 0.

## 2. Essai à l'écran (sources, fenêtre 1622×956)

Démarrage, entrée en skieur et fermeture (code 0, 1,5 s au plus) OK au mode auto et au cran 7.
Cran 7 : 30 i/s confirmés (image médiane 33,33 ms).

Non essayé : conduite, glisse, son, exe exporté, PC à carte intégrée. Touche envoyée directement à la fenêtre.
Non identifié : une capture de la boucle du skieur, dans la rame à 2118 m, presque entièrement brune.

## 3. Performance, cran 0

Fil principal sans vsync, tournée de 6 remontées (9006 images) ; GPU en moyenne sur la tournée, 4K.

| Variante | arrêt moy (ms) | tournée moy | p95 | > 16,7 ms | GPU |
|---|---|---|---|---|---|
| base | 7,74 | 7,57 | 13,73 | 163 | 3,90 |
| véhicules 1400 m | 10,02 | 9,49 | 15,88 | 339 | 4,05 |
| construction 4000/6000 m | 9,52 | 10,45 | 18,59 | 844 | 5,13 |
| tout ×2 | 10,76 | 11,28 | 19,47 | 1047 | 4,75 |

- Relevé F10 en 4K : GPU médiane 6,70 ms, p95 7,66. Scène peu représentative (dans la rame).
- Le fil principal limite : tsd6_fresse p95 16,71 ms, cabine_3s p95 16,20 ms.
- Proposition : effets purement graphiques possibles ; ne pas doubler la construction ; véhicules à 1400 m seulement
  après un gain sur le fil principal. Relief fin en anneaux non mesuré (prototype nécessaire). Rien n'est implémenté.
- Anomalie : en mode auto, le régulateur passe à « détail 2/2 (saccades, fil principal) » à l'entrée en skieur.
  Le F10 donne « principal » 17,4 ms pour une image de 16,67 ms. Hypothèse non prouvée : ce temps inclut l'attente du vsync.

## 4. Lot C : correspondance temps → pylône

n° = rang dans `pylones` (k = n° − 1). Hauteurs brutes en m, biais −10 à −20 % non corrigé.

- **tsd6_leissieres** : P2 8-11 (incertain) · P3 9-13 · P4 10-14 · P5 11-13,5 · P6 11-14 · P7 ≥ 15 · P8 5-8 ·
  P11 10-13 (incertain, nouvelle estimation) · P12 ≥ 10 (incertain, nouvelle estimation) · P13 12-15 · P14 7,5-10.
  Non mesurés : P1, P9, P10. Mesure 577 écartée (P13, pied caché). 5-8 ne vaut que pour P8.
  512 et 520 sont le seul P12. P2 serait plutôt à d ≈ 30 m qu'à 65 m (déduit, non prouvé).
- **tsf4_grand_huit** (certains) : P2 10-12 · P4 10-12 · P5 8-10 · P6 11-13,5 · P7 8,5-10 · P9 7,5-9 · P11 9-12 · P12 14-17.
  P1 : JSON d = 62,4 (`reconstitue`), mais le fût vu passe à 66 s, soit d ≈ 17 m.
- **tcd10_toviere** (certains ; P1-P5 attribués par ordre et nombre seulement) : P1 5-7 · P2 9-13 · P3 18-21 · P4 18-23 ·
  P5 12-16 · P10 15-17,5 · P11 21-24 · P13 21-25 · P14 16-19 · P15 15-17,5 · P16 17,5-20,5.

## 5. Vérifications en vidéo

Portées sous la garde : observations qualitatives, sauf mention. Le manteau neigeux réduit la garde visible.

- **Borsat, 1094-1865 m** (t ≈ 292-482 s) : aucun passage bas vu sur les images regardées. Estimation grossière
  au droit de deux pylônes : assise à ~6 m de la neige (échelle : voie 5,2 m).
- **Lanches, barre rocheuse P19-P20** (t ≈ 498-540 s) : la barre paraît à droite de l'axe du câble, avec de la neige sous la ligne.
  Si le profil la met dans l'axe, la garde calculée serait trop faible (à recouper). Passage flou à 508 s.
- **Vanoise, P6-P7** (t ≈ 140-200 s) : non concluant. Caméra vers le ciel, contre-jour, sol sous la ligne non visible,
  et P6 tombe dans un plan détourné (136-144 s).

Positions de pylônes :

- **Rogoney** (revu) : passages à d ≈ 43, 104, 200, 303, ~395, 473, ~524. Les `reconstitue` à 167,1 et 239,8 m ne sont pas vus ;
  399,9 m est cohérent ; ~524 m n'est pas au JSON. 7 vus sur 8.
- **Termignon, ligne 1** (relevé du 28/10, non revu) : 6 sur 7, attribution de la ligne moyenne. Pylône à ~476 m pour 491,5 au JSON.
  91,6 m non filmé, coupe à 140-144 s.
- **Inexploitables** (constat du 28/10, non revu) : Fontaine Froide (coupes à ~44 et ~167 s, 684-937 m sautés) ;
  Savonnette (s'arrête en pleine ligne, 1 passage) ; Solaise (clip promo, aucun trajet continu) ;
  Vallon (probablement l'ancienne télécabine, 24 pylônes pour 17 ; pas de preuve directe de la date).
