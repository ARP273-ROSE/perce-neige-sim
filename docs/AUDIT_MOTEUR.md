# Audit du moteur de rendu (vue 3D Godot)

Question posée : « le jeu paraît léger et les PC galèrent ; Godot est-il adapté, ou faut-il autre chose ? »

## Méthode

- **Exe Windows exporté en release** (Godot 4.6.1, noyau C++ compilé en release), pas l'éditeur. Synchronisation verticale coupée, aucun plafond d'images par seconde.
- **Machine de mesure** : PC de bureau haut de gamme, avec un processeur 12 cœurs / 24 fils et une carte graphique récente de 16 Go. Écran 4K. Les mesures en 4K sont prises à 150 % de rendu 3D dans une fenêtre 2560 × 1440, faute de fenêtre 4K sans passer en plein écran.
- **Sonde** : `godot_project/sonde_moteur.gd`. C'est un autoload ajouté seulement à l'export de mesure, car le modèle release ignore `-s`. Elle reste inerte sans `--sonde`. Elle ferme le menu de départ, place le joueur à chaque point, puis attend que le nombre de nœuds soit stable pendant 3 s.
- **Mesures** : 240 images par variante, après 40 images de mise en route.
  - « image ms » : intervalle mesuré d'une image à la suivante.
  - « scripts ms » : chronomètre posé autour du `_process` et du `_physics_process` de tous les nœuds. `TIME_PROCESS` donne le maximum de la dernière seconde : il est inutilisable image par image.
  - « rendu CPU ms » : `viewport_get_measured_render_time_cpu` + `get_frame_setup_time_cpu`, c'est-à-dire le tri, le culling et la soumission des appels.
  - « carte ms » : `viewport_get_measured_render_time_gpu`.
  - « appels », « primitives », « objets » : moniteurs `RENDER_TOTAL_*_IN_FRAME`.
- **Points** :
  - cabine du Perce-Neige à mi-tunnel ;
  - Val Claret : skieur au pied du Funival, regard vers l'amont ;
  - Tignes le Lac : pied du TSD de Palafour ;
  - sommets de la Tovière et de Solaise : à côté de la gare amont, regard vers la vallée.
- **Retrait d'un groupe** : `layers = 0` sur tous ses `VisualInstance3D` (masquer par `visible` ne tient pas, le jeu la remet), mesure appariée avec et sans.
- **Profil 6 Go** : `--simuler-vram=6`. Sur l'écran 4K de la machine, le régulateur part au cran 3 (sans brouillard). Sur un écran 1440p, il partirait au cran 1.
- **Coût des scripts par ablation** : `_process` et `_physics_process` coupés script par script, 60 images avec et 60 sans. La méthode est bruitée, à ±0,05 ms près, et la somme varie de 0,4 à 1,2 ms d'une passe à l'autre.
- **Limites** :
  - pas de bridage de fréquence du processeur : il aurait fallu changer un réglage système ;
  - l'essai à 2 cœurs garde 24 fils logiciels, que l'ordonnanceur répartit sur les 2 cœurs ;
  - au point Val Claret de la passe Mobile, la caméra est partie ailleurs (1798 m au lieu de 1802 m, regard sur un mur) : ce point n'y est pas comparable.

## Mesures

#### Forward+, 2560 × 1440, cran 0 (tout)

| Point | i/s | image ms (p95) | scripts ms | rendu CPU ms | carte ms | appels | primitives | objets | VRAM Mo | nœuds |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Cabine PN en ligne | 353 | 2.83 (3.61) | 0.40 | 0.90 | 2.29 | 797 | 0.48 M | 2038 | 1382 | 4797 |
| Val Claret (bas du Funival) | 337 | 2.97 (3.24) | 0.68 | 1.33 | 2.55 | 2064 | 4.48 M | 2427 | 1660 | 46898 |
| Tignes le Lac | 273 | 3.67 (4.25) | 1.14 | 1.46 | 2.38 | 1646 | 6.16 M | 2471 | 1747 | 70820 |
| Sommet Tovière | 206 | 4.86 (5.65) | 1.23 | 2.18 | 2.55 | 3041 | 8.72 M | 5271 | 1783 | 82944 |
| Solaise | 345 | 2.90 (3.29) | 0.69 | 1.18 | 2.28 | 1432 | 4.53 M | 1737 | 1683 | 42294 |

#### Forward+, 3840 × 2160 (rendu 3D à 150 % d'une fenêtre 2560 × 1440), cran 0 (tout)

| Point | i/s | image ms (p95) | scripts ms | rendu CPU ms | carte ms | appels | primitives | objets | VRAM Mo | nœuds |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Cabine PN en ligne | 220 | 4.55 (4.88) | 0.48 | 0.98 | 4.24 | 701 | 0.47 M | 1584 | 1916 | 4797 |
| Val Claret (bas du Funival) | 221 | 4.52 (5.26) | 0.76 | 1.27 | 3.92 | 2043 | 4.48 M | 2434 | 2192 | 46898 |
| Tignes le Lac | 243 | 4.11 (5.01) | 1.17 | 1.34 | 3.65 | 1657 | 6.18 M | 2484 | 2278 | 70820 |
| Sommet Tovière | 199 | 5.02 (5.88) | 1.32 | 2.09 | 3.61 | 2921 | 8.69 M | 5219 | 2313 | 82944 |
| Solaise | 239 | 4.18 (5.02) | 0.75 | 1.12 | 3.48 | 1431 | 4.53 M | 1737 | 2214 | 42294 |

#### Variantes (Forward+, carte ms à 1440p → 4K)

| Point | base | sans ombres | sans effets | sans MSAA | rendu 50 % |
|---|---:|---:|---:|---:|---:|
| Cabine PN en ligne | 2.29 → 4.24 | 2.28 → 4.21 | 1.12 → 2.23 | 1.98 → 3.61 | 1.11 → 1.61 |
| Val Claret (bas du Funival) | 2.55 → 3.92 | 2.33 → 3.65 | 1.42 → 2.21 | 2.15 → 3.16 | 1.68 → 2.07 |
| Tignes le Lac | 2.38 → 3.65 | 2.07 → 3.32 | 1.36 → 2.11 | 1.99 → 2.89 | 1.62 → 1.96 |
| Sommet Tovière | 2.55 → 3.61 | 2.11 → 3.11 | 1.49 → 2.10 | 2.22 → 2.99 | 1.88 → 2.15 |
| Solaise | 2.28 → 3.48 | 2.07 → 3.25 | 1.26 → 1.98 | 1.89 → 2.74 | 1.51 → 1.85 |

#### Moteurs de rendu au même point (2560 × 1440)

| Point | Forward+ cran 0 : i/s / carte ms / appels | Forward+ cran 3 (profil 6 Go) | Mobile | Compatibilité (cran 2) : i/s / rendu CPU ms / carte ms / appels |
|---|---|---|---|---|
| Cabine PN en ligne | 353 / 2.29 / 797 | 564 / 1.01 / 701 | 625 / 0.98 / 613 | 315 / 2.44 / 0.79 / 760 |
| Val Claret (bas du Funival) | 337 / 2.55 / 2064 | 417 / 1.14 / 1267 | 574 / 0.56 / 612 | 237 / 3.22 / 1.15 / 1289 |
| Tignes le Lac | 273 / 2.38 / 1646 | 414 / 0.85 / 676 | 404 / 0.74 / 591 | 292 / 2.14 / 1.04 / 746 |
| Sommet Tovière | 206 / 2.55 / 3041 | 328 / 0.91 / 909 | 332 / 0.93 / 910 | 232 / 2.76 / 1.01 / 1099 |
| Solaise | 345 / 2.28 / 1432 | 471 / 0.89 / 608 | 463 / 0.77 / 591 | 329 / 2.10 / 1.06 / 707 |

#### Deux cœurs (affinité), Forward+ 1440p cran 0

| Point | i/s 24 fils → 2 cœurs | rendu CPU ms | scripts ms | carte ms |
|---|---|---|---|---|
| Cabine PN en ligne | 353 → 349 | 0.90 → 0.78 | 0.40 → 0.42 | 2.29 → 2.29 |
| Val Claret (bas du Funival) | 337 → 292 | 1.33 → 1.80 | 0.68 → 0.66 | 2.55 → 2.54 |
| Tignes le Lac | 273 → 231 | 1.46 → 2.05 | 1.13 → 1.16 | 2.38 → 2.40 |
| Sommet Tovière | 206 → 178 | 2.18 → 2.82 | 1.22 → 1.29 | 2.55 → 2.62 |
| Solaise | 345 → 332 | 1.18 → 1.29 | 0.69 → 0.65 | 2.28 → 2.26 |

#### Part fixe et groupes, cran 4 (puce intégrée simulée, 1920 × 1080) et cran 0 (2560 × 1440)

Écart de temps de carte (et d'appels) quand on coupe un seul poste. Les points cabine, Val Claret, Tignes, Tovière et Solaise sont donnés dans cet ordre.

| Poste coupé | cran 4, carte ms | cran 0, carte ms | appels (cran 0) |
|---|---|---|---|
| base (temps total) | 0,54 / 0,57 / 0,36 / 0,50 / 0,40 | 2,29 / 2,55 / 2,40 / 2,56 / 2,28 | 701 / 2076 / 1719 / 2923 / 1401 |
| ciel uni au lieu du ciel nuancé | −0,02 / −0,01 / 0 / 0 / 0 | ≈ 0 | ≈ 0 |
| anticrénelage d'écran (SMAA / FXAA) | −0,05 / −0,07 / −0,04 / −0,04 / −0,05 | ≈ 0 (MSAA à ce cran) | ≈ 0 |
| tonemap linéaire | ≈ 0 | ≈ 0 | ≈ 0 |
| brouillard (simple + volumétrique) | ≈ 0 (coupé au cran 4) | −0,10 / −0,05 / −0,05 / −0,04 / −0,04 | ≈ 0 |
| SSAO | ≈ 0 | ≈ 0 | ≈ 0 |
| halo | ≈ 0 (coupé au cran 4) | −0,18 / −0,18 / −0,17 / −0,17 / −0,17 | ≈ 0 |
| 2D (HUD, boutons) | −0,01 à −0,02 (−0,03 à −0,11 ms CPU, 26 à 63 appels) | ≈ 0 | −26 à −63 |
| relief | 0 / −0,15 / −0,11 / −0,14 / −0,20 | 0 / −0,74 / −0,61 / −0,63 / −0,80 | −15 à −101 |
| remontées | 0 / −0,24 / −0,05 / −0,22 / −0,06 | 0 / −0,67 / −0,63 / −0,87 / −0,40 | **−1226 à −2786** |
| domaine (pistes, panneaux) | ≈ 0 | ≈ 0 | −43 à −50 |
| funiculaire (tunnel, voie, gares, halls, salle des machines, rames) | −0,44 / −0,01 / −0,02 / 0 / −0,02 | −1,38 / 0 / −0,03 / 0 / 0 | −675 / −31 / −86 / 0 / 0 |

Côté CPU, retirer les remontées fait gagner sur le rendu CPU **0,6 à 1,45 ms au cran 0**, et 0,15 à 0,64 ms au cran 4 : 85 à 95 % des appels de dessin viennent d'elles.

#### Ombres du soleil sur le relief (cran 0 seulement, Forward+ 1440p)

| Point | base : image / rendu CPU / appels | portée 300 m | 2 tranches | aucun porteur d'ombre (le relief ne porte pas d'ombre : `cast_shadow` coupé) |
|---|---|---|---|---|
| Val Claret | 2,43 ms / 0,84 / 1155 | −0,03 ms / −30 appels | −0,05 ms / −146 | −0,09 ms / −448 |
| Tignes le Lac | 3,43 / 1,31 / 1664 | −0,16 / −217 | −0,20 / −246 | **−0,56 / −950** |
| Sommet Tovière | 4,75 / 2,09 / 2981 | −0,11 / −400 | −0,47 / −965 | **−1,17 / −1959** (−6,2 M primitives) |
| Solaise | 2,67 / 1,03 / 1337 | −0,07 / −103 | 0 / −378 | −0,18 / −680 |

### Coût des scripts (ablation, sommet de la Tovière)

Le total des scripts va de 0,4 à 1,3 ms par image selon le point, soit 15 à 25 % du fil principal. Aucun script ne domine :

| Script | ms par image |
|---|---:|
| main.gd | 0,16 à 0,28 |
| remontees_domaine.gd | 0,10 à 0,18 |
| skieur_joueur.gd | 0,11 à 0,15 |
| ligne_remontee.gd (11 lignes construites) | 0,05 à 0,39 |
| hud.gd, cockpit_panel.gd | 0,01 à 0,11 chacun |
| sons_remontees.gd, audio.gd, sons_skieur.gd | 0,05 à 0,07 chacun |
| portes (porte_auto, porte_personnel) | 0,04 à 0,12 |

## Ce que disent les chiffres

1. **Sur un PC de bureau haut de gamme, rien ne force la machine** : 200 à 350 i/s en 1440p et 200 à 240 i/s en 4K, tout activé. Une image prend 3 à 5 ms.
2. **Au sommet de la Tovière, la limite est le processeur, pas la carte.** L'image de 4,9 ms se répartit ainsi :
   - 1,2 ms de scripts ;
   - 2,2 ms de préparation du rendu (tri, culling, soumission de 3 000 appels) ;
   - environ 1,5 ms de moteur hors scripts : physique, synchronisation.

   Pendant ce temps, la carte travaille 2,6 ms en parallèle. Le volume de géométrie (8,7 M primitives) ne coûte presque rien à la carte. Ce qui coûte, c'est le **nombre d'appels**, qui vient pour 85 à 95 % des remontées et, au cran 0, est doublé par les ombres.
3. **Ce qui s'effondre en premier sur une petite machine, c'est le rendu CPU.** Avec 2 cœurs, il passe de 2,2 à 2,8 ms à la Tovière (+30 %), et de 1,3 à 1,8 ms à Val Claret (+35 %). Les scripts et la carte ne bougent pas.
4. **Côté carte au cran 0**, les postes chers sont :
   - l'éclairage indirect et les effets : la variante « sans effets » fait gagner 1,1 ms en 1440p et 1,7 ms en 4K, dont environ 0,9 ms en 1440p pour l'éclairage indirect seul. Le halo pèse 0,17 ms, le brouillard 0,05 ms, le SSAO 0 ;
   - le nuanceur du relief : 0,6 à 0,8 ms, soit 25 à 30 % de la carte ;
   - le MSAA ×4 : 0,3 ms en 1440p, 0,6 ms en 4K.

   **Au cran 4, la part fixe est quasi nulle** sur cette carte (0,4 à 0,57 ms au total) : ciel, tonemap, brouillard et SSAO ne coûtent rien, et l'anticrénelage d'écran 0,05 ms. Le relief y fait 30 à 40 % de la carte. Les ~4 ms de part fixe mesurés sur puce intégrée ne viennent donc pas des effets d'écran. Ils viennent plutôt du coût de base de Forward+ (pré-passe de profondeur, éclairage par grappes, résolution) et du relief. Pour le savoir, il faut mesurer sur la puce elle-même une scène entièrement vidée (`masque=` sur tous les groupes).
5. **Mobile contre Forward+.**
   - Le rendu Mobile va 1,6 fois plus vite que Forward+ au cran 0 (0,6 à 1 ms de carte au lieu de 2,3 à 2,6 ms), mais seulement parce qu'il n'a ni ombres du soleil (réservées à Forward+), ni éclairage indirect, ni brouillard volumétrique.
   - **Forward+ au cran 3 coûte autant à la carte que Mobile** : 0,91 contre 0,93 ms à la Tovière, 0,85 contre 0,74 ms à Tignes, avec à peu près autant d'appels.
   - Visuellement, au même cadrage, Mobile est presque identique : même ciel et même neige, sans les ombres du relief.
   - Passer à Mobile n'apporterait donc rien que les crans ne donnent déjà. Le seul cas à essayer est celui de la puce intégrée, pour la pré-passe de profondeur que Mobile n'a pas, et il faut le mesurer sur place.
6. **Compatibilité (OpenGL) est le plus lent côté processeur** : 2,1 à 3,2 ms de rendu CPU pour 700 à 1 300 appels, contre 1,2 à 2,2 ms en Forward+ pour 2 fois plus d'appels. C'est le coût par appel du pilote OpenGL. À n'utiliser qu'en secours, comme aujourd'hui.

**Réponse à la question** : Godot n'est pas le goulot. Sur une machine puissante, il tient 200 à 350 i/s. Le coût se concentre sur quelques choix mesurables : le nombre d'appels des remontées, les ombres portées par le décor, le nuanceur du relief et l'éclairage indirect. Ces mêmes choix coûteraient autant dans un autre moteur, et un changement de moteur ne réglerait rien. Ce qui peut encore aider les petites machines, c'est de réduire les appels et d'alléger le relief.

## Les 5 corrections les plus rentables

| # | Correction | Gain mesuré ou borné | Qui en profite |
|---|---|---|---|
| 1 | **Moins d'appels pour les remontées** : pylônes, sièges, véhicules et gares lointaines regroupés par ligne (MultiMesh ou maillage fusionné par tronçon) | Les remontées font 85 à 95 % des appels. Les retirer fait gagner 0,6 à 1,45 ms de rendu CPU au cran 0 et 0,15 à 0,64 ms au cran 4 sur ce PC. Avec 2 cœurs, le rendu CPU monte de 30 à 35 %. Gain attendu en divisant les appels par 2 : 0,3 à 0,7 ms ici, environ le double sur un processeur modeste | Toutes les machines, surtout les processeurs modestes |
| 2 | **Ombre portée réservée au relief et au décor proche** : `cast_shadow` coupé pour les objets des remontées à plus de 150 à 200 m, ou ombres en 2 tranches | Aucun porteur d'ombre (le relief n'en porte pas) : −1,17 ms à la Tovière (4,75 → 3,58 ms, −1 959 appels, −6,2 M primitives), −0,56 ms à Tignes. En 2 tranches : −0,47 ms à la Tovière | Cran 0 (cartes de 8 Go et plus) |
| 3 | **Nuanceur du relief allégé aux crans ≥ 3** (chantier pc-relief-leger) | Le relief fait 25 à 30 % de la carte au cran 0, 30 à 40 % au cran 4 ici, et 2,5 à 4,4 ms sur puce intégrée. Gain attendu : 30 à 50 % du coût du relief | Puces intégrées, petites cartes |
| 4 | **Éclairage indirect seulement en 1440p et moins** : en 4K, partir au cran 1 sauf marge mesurée | En 4K, sans les effets, on passe de 3,9 à 2,2 ms de carte à Val Claret, dont environ 1,3 ms pour l’éclairage indirect (le reste : halo et brouillard). En 1440p, environ 0,9 ms | Écrans 4K avec une carte moyenne |
| 5 | **Scripts** : sortir de `_process` ce qui ne change pas à chaque image (main.gd, remontees_domaine.gd, skieur_joueur.gd), plutôt que de tout passer en C++ | 0,4 à 1,3 ms au total, sans pic ; gain réaliste 0,2 à 0,4 ms | Processeurs modestes |

**Fait : le funiculaire caché vu des pistes** (branche pc-perf-8). Dehors, à plus de 60 m des deux gares, les rames et le tube du tunnel ne sont plus dessinés.
- Un diagnostic par différence de pixels, tout autour des deux gares de 15 à 150 m, ne montre plus aucune trace de rame au-delà de 35 m.
- Devant la gare de Val Claret (point `gare_pn` de la sonde) :
  - 1 440p, cran 0 : 1 972 → 797 appels, image 4,17 → 2,94 ms (240 → 340 i/s) ;
  - 1 080p, cran 4 : 1 005 → 481 appels, image 3,13 → 2,35 ms.
- Les images avant et après sont identiques.

**Fait : moins d'appels pour les remontées** (branche pc-appels-remontees).
1. Plus d'ombre portée pour les pièces dont l'ombre ne se voit pas : pneus et fourches des lanceurs (sous le toit des gares), paires de galets, pince, mâchoires et vantaux des véhicules. Le soleil des ombres n'éclaire que la neige. À la Tovière au cran 0, les porteurs d'ombre passent de 2 711 à 983 surfaces : 3 037 → 2 435 appels, image 5,39 → 4,97 ms.
2. Les véhicules lointains sont fondus en un maillage par matériau, au lieu d'une MultiMesh par pièce : 8 → 2 MultiMesh pour une télécabine. À la Tovière : 2 515 → 2 232 appels au cran 0, 1 065 → 1 001 au cran 4 (image 3,09 → 2,89 ms).
3. En tout, à la Tovière au cran 0 : 3 037 → 2 232 appels (−27 %), image 5,39 → 4,36 ms (−19 %). Images inchangées.

## Rejouer les mesures

```
# export de mesure : project.godot reçoit l'autoload le temps de l'export, puis il est restauré
[autoload] SondeMoteur="*res://sonde_moteur.gd"
godot --headless --path godot_project --export-release "Windows x86_64"
perce_neige_3d.exe --resolution 2560x1440 -- --sonde --cran=0 --sortie=mesures.json \
    [--points=cabine,val_claret,tignes_lac,toviere,solaise] \
    [--variantes=base,sans_ombres,sans_effets,sans_msaa,echelle_50,ombres_2_tranches,ombres_relief_seul,ciel_uni,sans_aa_ecran,
                 tonemap_lineaire,sans_brouillard,sans_ssao,sans_halo,sans_2d,masque=relief,masque=remontees,…] \
    [--echelle-base=1.5] [--scripts | --ablation-a=toviere] [--simuler-integre] [--simuler-vram=6]
```
