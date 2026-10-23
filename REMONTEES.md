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
- **garde-corps** : `garde_corps(t)`. Automatique : relevé à la fin du freinage en gare, baissé au
  début du lanceur de départ (1.22.6).
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

Depuis la 1.22.13, la gare suit les photos des gares BMF du Marmottes Express
(`LigneRemontee._capot`) :
- carénage blanc en gélule (profil en superellipse), du nez de la gare jusqu'au-delà de la poulie ;
- bout arrondi en plan, garni d'une grande verrière sombre à montants blancs ;
- hublots et bandeau du nom de la ligne sur les flancs ;
- dessous plat percé de la fente où passent les suspentes ;
- deux colonnes rondes évasées en tête, l'une sous la poulie, l'autre au milieu du quai ;
- cabine du conducteur en pierre, toit à deux pans, à côté du quai d'embarquement ;
- plate-forme posée sur un talus de neige damée (`_talus`, collision comprise) au lieu d'un socle
  de béton.

Les portillons s'ouvrent vers l'avant, vers la ligne d'arrêt.

Au nez, la batterie de galets est posée côté ligne, centrée là où se croisent l'horizontale de la gare
et la pente de la ligne ; le câble y suit un raccord parabolique, qui est l'arc des galets
(`LigneRemontee._preparer_nez`, 1.22.6). Chaque gare est posée au plus haut du terrain sous son
emprise, sur un socle (`RemonteesDomaine._poser`).

### Hauteur des pylônes

Aucune source ouverte ne la donne. Elle est calculée pour que le câble chargé reste partout à au moins
6,5 m au-dessus du terrain, flèche parabolique comprise entre les têtes (`LigneRemontee.GARDE`).
Cette garde décroît dans les 40 m qui précèdent une gare, jusqu'à la hauteur du câble au quai : sans
cela, le dernier pylône du Marmottes Express montait à la butée de 32 m. Sur les télécabines, la
traverse est remontée au pivot du train support (0,62 m sous le câble au lieu de 0,95 m) pour laisser
passer le toit des cabines.

## Contrôle visuel

- `shot_vitrine_remontees.gd` : vitrine de tous les modèles (pylônes, véhicules, pinces ouvertes et
  fermées, garde-corps, bulle, portes, téléski, 3S, téléphérique).
- `shot_ligne_remontee.gd <clé>` : une ligne complète sur son profil réel.
- `shot_remontees_jeu.gd` : les lignes posées dans le jeu.
- `shot_cabines.gd` / `shot_sieges.gd` : studio des cabines (portes ouvertes, intérieur) et des sièges.

### Design des cabines et des sièges (1.22.7)

- **Cabine** (`VehiculeRemontee._maillage_cabine`, 1.22.8) : cotes relevées sur les plans CWA de
  l'Omega V (Wikimedia Commons, CC BY-SA, utilisateur Ryse93) et sur des photos de cabines
  (Méribel, Orelle) : 2,46 m en travers du câble (deux banquettes de 5 places de 46 cm, face à face),
  1,68 m dans le sens du câble, 2,25 m de haut. La face des portes est en œuf, les faces longues en
  trapèze arrondi (`_profil_cabine` : demi-largeur et demi-longueur par anneau). Grand vitrage teinté
  de 0,30 à 1,35 m sous le toit, petite vitre haute, cadre noir sur les arêtes, liseré de couleur
  sous le toit, tampons de caoutchouc aux angles, porte de 0,90 m en deux vantaux découpés dans la
  coque. Suspente cintrée terminée par une poutre posée sur le toit par deux pieds. Maillages
  partagés par famille ; matériaux de caisse double face (on voit l'intérieur à travers les vitres).
- **Siège BMF du Marmottes Express** (`VehiculeRemontee._siege_bmf`, 1.22.9), d'après les photos de la
  ligne (reportage remontees-mecaniques.net, 2011, consulté comme référence, aucune image reprise) :
  poutre de tête : une tôle verticale pleine au milieu (suspente, plaque du numéro) et aux bouts,
  ajourée de triangles entre les deux, sur un longeron en caisson (1.22.12) ; les cadres latéraux en
  tube rond sortent horizontalement sous ses bouts ; gros cadres tubulaires derrière le dossier, cintrés sous l'assise ; dossier bas et peu
  incliné (la particularité BMF citée par le reportage) ; six coussins noirs sur un carénage
  aluminium ; pince à un gros ressort rouge par bout. Garde-corps BMF (1.22.10, axe corrigé en 1.22.11) : axe juste au-dessus du dossier, en arrière,
  basculement vers le haut ; garde-corps
  compact (1.22.12), trois repose-pieds en T (un pour deux places), chacun tenu par une seule
  tige ; numéro du siège sur la poutre. Recoupé avec deux modèles
  d'impression 3D de sièges Doppelmayr D-Line (Printables), étudiés pour la structure (poutre de
  tête porteuse, cadres cintrés, un repose-pieds par place) et non repris dans le dépôt.
- **Siège** (autres familles) : coussins d'assise et de dossier rembourrés (`RemonteeKit.coussin`, boîte aux arêtes
  arrondies, maillage partagé, environ 300 triangles), sur un bac d'assise et une coque de dossier
  pleine largeur, avec des accoudoirs garnis et des attaches du dossier sous l'arceau. Garnitures
  satinées : le noir n'est plus un aplat.

## Dans le jeu (v1.21.0)

Deux lignes servent d'échantillon : le **TSD6 Marmottes Express** (Bartholet, 11 pylônes) et la
**TCD10 des Boisses** (CWA Omega IV, 11 pylônes). Ce sont deux appareils dont les positions OSM et le
tableau des balanciers concordent pylône par pylône. Elles se construisent au passage en vue skieur.

Les véhicules sont visibles jusqu'à 700 m, les pylônes et le câble jusqu'à 3 km. Une ligne dont le
milieu est à plus de 2,5 km de la caméra ne fait plus avancer ses véhicules.

Depuis la 1.22.0 :
- on monte à bord : à pied dans les cabines (assis d'office face à l'amont depuis la 1.22.6),
  et sur les sièges par les portillons et la ligne d'arrêt (`RemonteesDomaine._embarquement`) ;
- collisions des pylônes, des gares et des véhicules ;
- câble en chaînette (`LigneRemontee.chainette`) ;
- suspente toujours à l'extérieur de la boucle, avec des véhicules en miroir sur les lignes
  qui montent à gauche.

Depuis la 1.22.2 :
- galets mobiles qui suivent la courbe du câble et le passage des pinces ;
- gaines de pince effilées jusqu'à zéro ;
- lanceur à accélération continue (18 m) ;
- balancement pendulaire amorti selon la masse (`bench_remontee_dynamique_3d.gd`).

Reste à faire : poser toutes les lignes du domaine, des
gares plus détaillées, le téléski en ligne complète, le 3S et le téléphérique en ligne complète.
