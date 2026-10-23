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
- côté portillons (télésièges), une rampe de neige damée à 10 % part du bout du quai et rejoint la
  piste (1.22.14) ; sa longueur (40 m au plus) est mesurée sur le relief par
  `RemonteesDomaine._poser`, sur toute la largeur de la rampe.

Les portillons s'ouvrent vers l'avant, vers la ligne d'arrêt.

Depuis la 1.27.0 — tout le domaine :
- 48 lignes posées (tous les télésièges, télécabines, le 3S, les téléphériques de la Grande Motte et
  du Fornet ; les téléskis attendent leur embarquement) ; banc `bench_toutes_lignes_3d.gd` ;
- niveaux de détail : une ligne à plus de 750 m est figée, une image sur deux de 150 à 300 m, une sur
  quatre au-delà ; par véhicule : pas déplacé au-delà de 700 m, une image sur quatre de 250 à 700 m ;
  corps de collision à jour seulement à moins de 60 m (et sur les lignes à moins de 120 m) ; pneus
  des lanceurs à moins de 250 m ; animations (pince, garde-corps, portes) recalculées seulement si
  elles changent ; flèche calculée portée par portée ;
- numéros en `TextMesh` fusionnés, véhicules fusionnés en une instance multi-surfaces (`MeshMerge`
  `une_instance`) : 11 instances par siège Doppelmayr au lieu de 29 ;
- accès des télésièges : bornes de contrôle grises avec lecteur et écran, vantaux en tube inox,
  portique d'entrée en bois au nom de la ligne ;
- exporteur : un espacement de moins de 4 s est rejeté (on repart du débit).

Depuis la 1.26.0 :
- pylône du téléphérique (`PyloneTreillis.va_et_vient`) : fût carré élancé, évasement en tête jusqu'à
  la voie, poutre de tête en caissons, un sabot par voie, portique de levage, plate-forme, échelle ;
- sièges débrayables et fixes des autres constructeurs (`VehiculeRemontee._ossature_moderne`),
  d'après les photos des lignes du domaine (Palafour, Marais, Laisinant, Almes) : poutre de tête
  en caisson numérotée, cadres latéraux en boucle arrondie avec accoudoir, assise rembourrée sur
  bac, lèvre avant en carénage alu (Doppelmayr, Garaventa), dossiers en coques ajourées
  (Doppelmayr) ou pleins (blancs sur les fixes).

Depuis la 1.25.0 — le téléphérique de la Grande Motte (`Telepherique`, classe fille de
`LigneRemontee`) :
- va-et-vient : deux cabines, une par voie, reliées par le tracteur ; quai 45 s portes ouvertes,
  départ à 0,6 m/s², 10 m/s, freinage anticipé pour passer le pylône à 5,2 m/s (fiche technique),
  arrivée en douceur ; le poste de commande s'y applique ;
- un porteur lisse par voie (H = 0,9 MN), qui fléchit sous la cabine ; tracteur à torons 0,45 m
  dessous ; 8 cavaliers par voie ;
- gares : quai de béton sur remblai, portique en A au-dessus des baies ; aval : bâtiment à bardage
  gris, escalier ; amont : tambours d'ancrage inclinés, poste de vigie ;
- on y monte à pied et l'on voyage debout ; banc `bench_tph_3d.gd`.

Depuis la 1.24.0 — le 3S de l'Olympique (`LigneRemontee.tricable()`), d'après le reportage
remontees-mecaniques.net (fiche technique, 184 photos consultées comme référence) :
- cabine CWA Zeta 30 places (`VehiculeRemontee._cabine_zeta`) : 2,76 × 2,66 × 2,55 m, angles très
  arrondis, grand vitrage, bandeau noir, jupe de tôle perforée, portes coulissantes, 2 × 6 places
  rouge et gris face à face, barres de maintien ; suspente en caisson coudée ; chariot de 2×4
  galets sur balanciers bleus (fixe, nœud « Pince »), pince du tracteur au milieu ;
- deux porteurs lisses de 57 mm par voie (ancrages fixes, H = 1,5 MN), qui fléchissent sous chaque
  cabine (2 950 kg à vide, 5 350 kg pleine) ; tracteur à torons de 52,5 mm, 0,42 m sous eux ;
  10 cavaliers par voie, serrés sur les porteurs, portant le tracteur sur un galet ;
- pylônes en treillis (`PyloneTreillis`) : fût à quatre membrures, tête en caisson treillis, à
  chaque voie un long sabot en porte-à-faux incliné sur la pente et cintré selon la déviation
  (plus long au P3 : 40 galets), passerelles et garde-corps, galets du tracteur ;
- gares : bâtiment de pierre et verre, toit sombre, bandeau noir au nom de la ligne, charpente
  rouge qui porte rails et lanceurs (`_gare_3s`, `_charpente_3s`) ;
- banc `bench_3s_3d.gd`.

Depuis la 1.23.0 — poste de commande (`PosteRemontee`, `LigneRemontee.etat`) :
- états `marche`, `arret_normal` (frein de service, 0,4 m/s²), `arret`, `urgence` (frein de poulie,
  1,5 m/s², à réarmer une fois arrêtée) ; démarrage à 0,25 m/s² ;
- référence de vitesse : petite 40 %, moyenne 70 %, grande 100 % (par défaut) ;
- tout le mouvement suit `vitesse_reelle` (`regime()`) : véhicules, pneus, poulies, torons du
  câble, portillons ; le balancier réagit aux freinages ;
- puissance au câble : surpoids du brin montée × dénivelé × vitesse, plus 10 % de pertes ;
- le pupitre suit la remontée où l'on est, sinon la plus proche (400 m) ;
- banc `bench_poste_remontee_3d.gd`.

Depuis la 1.22.23 :
- poids ponctuel des véhicules : en ligne, chaque véhicule abaisse le câble de la flèche d'un câble
  tendu (tension H) sous une charge ponctuelle, entre ses deux appuis, moins la charge moyenne déjà
  dans la chaînette ; calculée dans le shader du câble (`fleche_points`, appuis et charges passés à
  chaque image) et par `LigneRemontee._fleche` pour les véhicules ;
- déviation en gare : le câble arrive droit, s'enroule sur les galets de déviation côté intérieur
  (convexe), file en ligne droite tangente à la poulie (`_tangente_deviation`) ;
- en remontée, la caméra de dos traverse les parois du véhicule.

Depuis la 1.22.22 :
- terrassement des gares (`LigneRemontee._terrassement`) : dessus du quai et de la rampe d'accès,
  et un talus le long de chaque bord qui descend jusqu'au terrain réel (`sol_local`, relief
  affiché, échantillonné tous les 50 cm) ; même surface pour le maillage et la collision
  (polygone concave) ; la descente de débarquement est douce sur 4 m, puis talus normal ;
- télécabine à pied : chaussé, on déchausse en entrant et les skis vont au porte-skis du vantail
  (`VehiculeRemontee.porte_skis`) ; en haut, on se lève à l'ouverture des portes et l'on sort en
  marchant, porté par la cabine tant qu'on y est ;
- télésiège chaussé : on chausse au portillon ; en remontée, chausser et déchausser sont refusés.

Depuis la 1.22.16 :
- câble tracteur : le shader à torons du câble du funiculaire, pas mis à l'échelle du diamètre de
  la ligne, torons qui défilent à la vitesse du câble (`RemonteeKit.materiau_cable_tracteur`) ; les
  câbles porteurs (3S, téléphérique) restent lisses et immobiles ;
- rail d'ouverture des pinces (`_rail_ouverture`) : il descend sur le galet du levier sur les
  2,5 premiers mètres de la gare (`ouverture_pince`), comprime les ressorts et ouvre la mâchoire,
  puis remonte à la sortie ;
- gaines de la pince en demi-cônes ouverts par-dessous, grand diamètre contre la pince et pointe
  vers l'extérieur (1.22.17) ;
- télésiège : côté arrivée, le quai s'arrête 1,6 m après le couloir et descend à 1 pour 6
  (`_bords_quai`) ; le skieur chaussé se lève à sa place et glisse dessus ;
- à ski, le sol est le relief ou, plus haut, une plate-forme de gare (`SkieurJoueur._sol_ski`).

La poulie tourne à la vitesse du câble en ligne, à son rayon de gorge, dans le sens de la boucle
(1.22.15) : la roue est un nœud à part, l'arbre et le bâti restent fixes. Les numéros (pince et
plaque du siège) sont des étiquettes d'un seul côté, une par face, contre-inversées sur les
véhicules en miroir (`VehiculeRemontee._numero`) : lisibles à l'endroit de partout.

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
