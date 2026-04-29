# Sources techniques — Perce-Neige Simulator 3D

Toutes les données géométriques, mécaniques et opérationnelles utilisées
dans le port Godot 4 proviennent des sources référencées ci-dessous.
Ce fichier est mis à jour à chaque recherche ou vérification technique.

---

## Sources principales

### remontees-mecaniques.net (référence du secteur)
- [Funiculaire 334 places (FUNI 334) de la Grande Motte (Perce-Neige) — Von Roll](https://www.remontees-mecaniques.net/bdd/reportage-funi-334-de-la-grande-motte-perce-neige-von-roll-6174.html)
- [Forum : FUNI de la Grande Motte (Perce-Neige) — Tignes](https://www.remontees-mecaniques.net/forums/index.php?showtopic=232)

Données extraites :
- **1 câble tracteur unique** en boucle continue (pas 2, pas de bouclage en bas)
- **Câble Fatzer 52 mm** "6×26 fils Thermocompacte"
- Longueur totale : plus de 3.5 km
- Résistance à la rupture : **191 200 daN**
- Charge nominale : 22 500 daN
- **Poulie motrice** en gare amont (Grande Motte), **diamètre 4160 mm**
- Attaches culot reliant chaque rame au câble
- **256 paires de galets** (= **512 galets au total**) répartis sur toute la ligne
- Pas de tension dynamique : les 2 rames équilibrent le câble (32.3 t à vide chacune)
- 3 moteurs DC **3 × 800 kW = 2 400 kW** en gare amont (sous le restaurant Panoramic)

### Wikipedia
- [Funiculaire du Perce-Neige (en)](https://en.wikipedia.org/wiki/Funiculaire_du_Perce-Neige)
- [Wikidata Q2437281](https://www.wikidata.org/wiki/Q2437281)

### CFD Group (constructeur rames et bogies)
- [Tignes Funicular — La Grande Motte](https://www.cfd.group/rolling-stock/tignes-funicular)

Le matériel roulant (2 × 2 cars couplés, bogies, cabines) a été conçu et
construit par CFD. Von Roll a été maître d'œuvre de l'ensemble.

### Skiresort / Tignes
- [Perce Neige (Grande Motte) — skiresort.info](https://www.skiresort.info/ski-resort/tignesval-disere/ski-lifts/l532/)
- [Summer pedestrian passes — Tignes](https://www.skipass-tignes.com/en/altitude-experiences)
- [Tignes Destination Glacier — Funiculaire Perce-Neige (YouTube)](https://www.youtube.com/watch?v=vYDgtZ6o1Z0)

### Autres
- [Funiculaires de France — Tignes](https://funiculaires-france.fr/tignes/?lang=en)
- ["Un métro pour skieurs" : Le Perce-Neige — Mon séjour en montagne](https://www.mon-sejour-en-montagne.com/histoires-et-anecdotes/un-metro-pour-skieurs-connaissez-vous-le-perce-neige/)
- [Tignes Grande Motte : de la télécabine au funiculaire — Haute Tarentaise](https://www.haute-tarentaise.net/t111-tignes-grande-motte-de-la-telecabine-au-funiculaire)

---

## Dimensions et calibrations clés

### Géométrie du tracé
| Donnée | Valeur | Source |
|---|---|---|
| Longueur le long de la pente | **3 474 m** | remontees-mecaniques / cockpit counter |
| Altitude Val Claret | 2 111 m | Wikipedia, CFD |
| Altitude Glacier Grande Motte | 3 032 m | Wikipedia, CFD |
| Dénivelé | 921 m | Calcul |
| Tunnel carré (cut-and-cover) | s ∈ [0, 257] et [3420, 3474] | Observation vidéo cockpit HD |
| Tunnel rond (TBM) | s ∈ [257, 3420] | idem |
| Boucle de croisement | s ∈ [1611, 1813] | vidéo cockpit + Wikipedia |
| Gradient max soutenu | 30 % (sur s ∈ [914, 2400]) | vidéo calibrée via 10.1 m/s |
| Diamètre tunnel min (TBM) | 3.9 m | Wikipedia |
| Écartement rails (gauge) | 1 200 mm | Wikipedia |

### Vitesse
| Donnée | Valeur | Source |
|---|---|---|
| V max régulateur Von Roll | **12 m/s** (43.2 km/h) | Wikipedia, CFD |
| V cruise réelle | ~10.1 m/s (speed_cmd ≈ 84 %) | vidéo cockpit HD |
| Durée trip Val Claret → Glacier | 7 min 54 s | vidéo cockpit |
| Vitesse moyenne | 7.33 m/s | calcul (3474 / 474 s) |

### Rames
| Donnée | Valeur | Source |
|---|---|---|
| Nombre de rames | 2 (va-et-vient) | toutes sources |
| Composition par rame | 2 cars couplés | CFD |
| Capacité | 334 passagers + 1 conducteur | CFD, Wikipedia |
| Masse à vide | **32.3 t** | CFD |
| Charge utile max | **26.8 t** (58.8 t PM) | CFD |
| Masse 1 passager (calcul) | 75 kg | convention sim |
| Diamètre cabine cylindrique | 3.60 m | CFD |

### Câble et traction
| Donnée | Valeur | Source |
|---|---|---|
| Câble Fatzer ∅ | **52 mm** | remontees-mecaniques |
| Configuration torons | 6×26 fils Thermocompacte | remontees-mecaniques |
| T nominal | 22 500 daN | Wikipedia |
| T warning | ~28 000 daN | calibration sim |
| T rupture | 191 200 daN | remontees-mecaniques |
| **Poulie motrice ∅** | **4160 mm** | remontees-mecaniques |
| Position poulie motrice | gare amont (s=LENGTH) | remontees-mecaniques |
| Système | **câble unique en boucle** (pas 2 câbles, pas de bouclage bas) | remontees-mecaniques |
| **Paires de galets** | **256** (512 galets) sur 3474 m | remontees-mecaniques |
| **Entraxe réel paires galets** | **13.57 m** (3474 / 256) | calcul |
| Pitch hélice torons 6×26 | ~0.40 à 0.50 m (≈ 8× ∅ câble) | convention câble Fatzer |

### Motorisation
| Donnée | Valeur | Source |
|---|---|---|
| Moteurs | 3 × DC 800 kW | Wikipedia, CFD |
| Puissance totale | 2 400 kW | Wikipedia |
| Emplacement | gare amont, sous restaurant Panoramic | Wikipedia |
| Inrush DC au démarrage | ~4.5× nominal pendant 1.2 s | convention moteur DC |

### Construction
| Donnée | Valeur | Source |
|---|---|---|
| Maître d'œuvre | **Von Roll** (Suisse) | toutes sources |
| Rames et bogies | **CFD** (Compagnie Française de Diligences) | CFD, Wikipedia |
| Début construction | 1989 | skiresort.info |
| Ouverture au public | **14 avril 1993** | Wikipedia, mon-sejour-en-montagne |
| Câble fabricant | Fatzer AG (Suisse), 1999 (dernier relevé) | remontees-mecaniques |

---

## Défilements visuels calibrés (v = 10 m/s cruise réel)

Pour que la simulation donne un ressenti fidèle à la vidéo cockpit HD :

| Élément | Entraxe | Passages/s | 1 tous les... |
|---|---|---|---|
| Paires de galets | 13.57 m | 0.74 | **1.35 s** (rythme funiculaire) |
| Traverses béton | 0.60 m | 16.7 | 60 ms (classique voie ferrée) |
| Néons muraux | 12 m | 0.83 | 1.2 s |
| Torons câble brin gauche (te tire) | — | **0** (fixe) | — |
| Torons câble brin droite défilant | pitch 0.45 m | 44 tours/s | 23 ms (2×v relative) |

---

## Aiguillage Abt — passing loop

### Principe (sources Wikipedia + remontees-mecaniques)
- **Pas de pièces mobiles** sur la voie : le switch est entièrement passif
- Inventé par Carl Roman Abt, première application Funiculaire Giessbach (Suisse, 1879)
- **Roues asymétriques** : sur chaque cabine, les roues côté extérieur ont
  *deux flasques* (sandwich autour du rail extérieur), les roues côté intérieur
  sont *plates et plus larges* pour passer par-dessus les coupures
- **Chaque rame va toujours du même côté** au croisement (rame 1 toujours à gauche,
  rame 2 toujours à droite)

### Géométrie du passing loop
- **Rail extérieur continu** : le rail extérieur de chaque voie est une ligne
  continue qui passe à travers tout le passing loop sans interruption
  (sandwich entre les 2 flasques des roues outboard)
- **Rails intérieurs avec coupures** : les rails intérieurs ont des coupures
  aux endroits où le câble et les flasques des roues extérieures de la rame
  opposée doivent passer ; les roues larges sans flasque les enjambent
- À l'entrée du loop, les 2 rails de la voie unique se courbent vers
  l'extérieur pour devenir les 2 rails extérieurs des 2 voies du loop ;
  les 2 rails intérieurs apparaissent avec des bouts francs

### Sources
- [Wikipedia — Funicular (Abt switch section)](https://en.wikipedia.org/wiki/Funicular)
- [Wikipedia — Carl Roman Abt](https://en.wikipedia.org/wiki/Carl_Roman_Abt)
- [Wikidata Q334561 — Abt's switch](https://www.wikidata.org/wiki/Q334561)
- [ASME Landmark — Funicular Giessbach](https://www.asme.org/about-asme/engineering-history/landmarks/259-funicular-giessbach)

### Implémentation Perce-Neige (sim 3D)
- Boucle de croisement : s ∈ [1611, 1813] m (202 m de long)
- Décalage latéral max par voie : ±2.20 m (entraxe 4.40 m entre les 2 axes)
- Longueur transition smoothstep : 15 m de chaque côté
- Tube tunnel : se divise en 2 tubes parallèles dans le passing loop (mesh 4 sections)
- Dalle béton : se divise en 2 dalles parallèles dans le passing loop
- Rails : 2 rails extérieurs continus de s=0 à s=LENGTH, 2 rails intérieurs
  uniquement dans la section plate [PASSING_START, PASSING_END]
- Traverses : 1 set centré hors loop, 2 sets (un par voie) dans le loop plat
- Guides câble : 1 set hors loop, 2 sets dans le loop plat
- Câble : 2 brins, suivent l'axe de chaque voie dans le loop (smoothstep)

---

## Notes d'implémentation 3D

- **Smoothing dans les virages** : Curve3D avec tangentes Catmull-Rom explicites
  (`tangent = 0.33 × (p_next − p_prev)`, handles `in/out = ∓tangent`) —
  sinon la spline dégénère en segments rectilignes avec cassures de tangente
  à chaque point de contrôle.
- **2 brins côte à côte** : 1 câble unique en boucle visible comme 2 tubes
  parallèles (écart 24 cm entre les 2 poulies). Brin gauche (aller) tire
  rame 1, brin droite (retour) tire rame 2.
- **Masquage dynamique** : chaque brin découpé en segments de 15 m,
  visibilité calculée chaque frame : brin gauche visible de `s_rame1` à
  `LENGTH`, brin droite visible de `LENGTH − s_rame1` à `LENGTH`.
- **Shader hélicoïdal** : 6 torons, pitch 45 cm, uniform `cable_phase` animé
  à `+s_rame1` pour le brin gauche (apparaît fixe en référentiel cabine)
  et `−s_rame1` pour le brin droite (défile à 2×v relative).
