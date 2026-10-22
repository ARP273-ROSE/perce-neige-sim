# Remontées mécaniques du domaine

Chantier ouvert le 22/10/2026 (retour d'utilisateur : « continuer à développer les remontées du
domaine… un modèle de pylône très réaliste à adapter partout, un modèle de siège et de cabine par
constructeur avec pince débrayable réaliste et fonctionnelle, garde-corps et bulle pour les sièges,
portes de cabines qui marchent ; un échantillon de chaque, qu'on peut ensuite mettre partout »).

## Données

Pour chaque appareil du domaine, un dossier de travail hors dépôt rassemble :
- les fiches techniques (remontees-mecaniques.net, faits seulement) ;
- les positions OpenStreetMap / OpenSkiMap ;
- le terrain IGN ;
- les balanciers pylône par pylône.

Seules des **valeurs numériques** en sortent, vers le jeu :

- `godot_project/data/remontees/<clé>.json` : profil du terrain, pylônes (distance depuis l'aval,
  balanciers côté montée et côté descente, en groupes `[galets, "S"|"C"|"SC"]`), vitesse, espacement
  des véhicules, voie, sens de montée, famille de véhicule ;
- `scripts/remontees_donnees.gd` : les mêmes lignes en constante GDScript, générée, car les
  `.json` bruts ne partent pas dans les paquets exportés.

Balanciers : S = support (le câble passe sur les galets), C = compression (dessous), SC = les deux.
Quand aucune source ne les publie, ils sont estimés par une règle tirée des 36 lignes du domaine dont
le tableau est connu : P1 en compression à 12 galets, les autres pylônes en support à 8. Le profil du
terrain ne prédit pas mieux que cette règle.

## Modèles (`scripts/`)

| Fichier | Rôle |
|---|---|
| `remontee_kit.gd` | matériaux partagés et primitives : boîte, cylindre, tube cintré, galet, ressort |
| `pylone_remontee.gd` | pylône de TSD / TCD paramétrable : massif, fût conique en tronçons, échelle à crinoline, traverse caisson, passerelles, têtes de ligne au nombre réel de galets (S sous le câble, C dessus, SC les deux), portique de levage, ramasse-câble, plaque du numéro ; style `teleski` (fût fin et potence) |
| `pylone_treillis.gd` | pylône en treillis du 3S et du téléphérique : sabots des porteurs, poulies du tracteur |
| `vehicule_remontee.gd` | véhicules par famille (voir ci-dessous), avec la pince et les pièces animées |
| `ligne_remontee.gd` | ligne complète : gares (poulie, rail, pneus, came), pylônes, câble en boucle avec sa flèche, véhicules qui circulent |
| `remontees_domaine.gd` | pose les lignes à leur place réelle sur le relief du jeu, avec les distances de visibilité |

Familles de véhicules :
- **sièges** : Doppelmayr E98 6 et 4 places (dont la version à bulle des Lanches), Poma OCR 6,
  Poma Arceau 4, Garaventa SK6, Bartholet 6, Leitner 4, sièges fixes 3 et 4 places ;
- **cabines** : CWA Omega IV, Sigma Diamond EVO (porte-skis extérieurs), Sigma Symphony,
  cabine 3S (Zeta, 30 places, chariot sur deux porteurs), cabine de téléphérique ;
- **perches** : à enrouleur, en T biplace, à assiette débrayable.

Pièces animées, pilotées par `ligne_remontee.gd` selon la place du véhicule sur la boucle :

- **pince débrayable** : `ouvrir_pince(t)`. La mâchoire mobile s'écarte, le levier bascule sur la came
  et les ressorts se compriment. Couleur des ressorts : jaunes chez Bartholet, bleus chez Garaventa.
- **garde-corps** : `garde_corps(t)`. Il est relevé en gare, puis baissé une dizaine de secondes après
  la sortie, et relevé avant l'arrivée.
- **bulle** : `bulle(t)`. Elle se ferme en ligne et se relève en gare.
- **portes des cabines** : `portes(t)`. Elles glissent sur les panneaux fixes et ne s'ouvrent qu'à
  vitesse d'embarquement.
- **perche à enrouleur** : `deroule(t)`.

### Gare

Le véhicule débraye au nez de la gare : la came ouvre la pince et il roule sur le rail. Les pneus le
freinent ensuite à décélération constante jusqu'à 1 m/s. Il contourne la poulie, puis les pneus le
relancent et la pince se referme. La vitesse ne dépend que de la position sur la boucle : les
véhicules se resserrent en gare, comme sur une vraie ligne, et l'intervalle en temps reste constant.

Le câble en gare est placé pour que l'assise arrive à 0,48 m du quai, et le plancher des cabines au
niveau du quai.

### Hauteur des pylônes

Aucune source ouverte ne la donne. Elle est calculée pour que le câble chargé reste partout à au moins
6,5 m au-dessus du terrain, flèche parabolique comprise entre les têtes (`LigneRemontee.GARDE`).

## Contrôle visuel

- `shot_vitrine_remontees.gd` : vitrine de tous les modèles (pylônes, véhicules, pinces ouvertes et
  fermées, garde-corps, bulle, portes, téléski, 3S, téléphérique).
- `shot_ligne_remontee.gd <clé>` : une ligne complète sur son profil réel.
- `shot_remontees_jeu.gd` : les lignes posées dans le jeu.

## Dans le jeu (v1.21.0)

Deux lignes servent d'échantillon : le **TSD6 Marmottes Express** (Bartholet, 11 pylônes) et la
**TCD10 des Boisses** (CWA Omega IV, 11 pylônes). Ce sont deux appareils dont les positions OSM et le
tableau des balanciers concordent pylône par pylône. Elles se construisent au passage en vue skieur.

Les véhicules sont visibles jusqu'à 700 m, les pylônes et le câble jusqu'à 3 km. Une ligne dont le
milieu est à plus de 2,5 km de la caméra ne fait plus avancer ses véhicules.

Reste à faire : poser toutes les lignes du domaine, les collisions du skieur, monter à bord, des
gares plus détaillées, le téléski en ligne complète, le 3S et le téléphérique en ligne complète.
