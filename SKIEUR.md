# Le skieur jouable — suivi du chantier

Demande de Kevin du 07/10/2026 : « un skieur capable de monter les escaliers
des gares et de marcher à l'intérieur sans passer au travers du plancher, des
murs, des portes ou du wagon, qui peut marcher dans le wagon, voyager dans le
funiculaire et aller au poste de pilotage. Arrivé en haut, il est capable de
skier sur le décor pour redescendre, en suivant les pistes ; il peut boucler la
boucle et remonter, ou redescendre avec le funiculaire. Mets de la neige sur la
piste. »

## Où on en est

### Étape 1 — le piéton (v1.16.0) : fait

- **Bouton SKIEUR** (touche K) dans la barre du haut ; QUITTER pour revenir à la
  conduite. Le funiculaire passe en AUTO pendant qu'on marche.
- **Sur le simulateur PC** (v1.16.3) : touche F9 ou bouton SKIEUR, en vue 3D
  (F4). Le PC garde la rame (exploitation AUTO 24 h/24) ; la 3D lui renvoie
  l'état du skieur (dans la voiture, sur le quai, dehors) par UDP (port 7778).
- **Commandes** :
  - joystick à l'écran (bas gauche) ;
  - doigt glissé ailleurs pour tourner la vue ;
  - COURIR, 1re/3e personne (touche V), CONDUIRE près du poste ;
  - au clavier : ZQSD / flèches, Maj, souris, molette.
- **Collisions** (`scripts/collisions_jeu.gd`), construites au premier passage
  en vue skieur :
  - **gares** : les vrais maillages, dont les marches des quais ;
  - **rames** : collisions simplifiées (paliers, parois, bancs, porte-skis,
    pupitre, seuils de porte) ;
  - **portes** : vantaux mobiles ;
  - **relief** : triangles du bloc, pièces fines de 2 m autour des gares, trous
    des bâtiments.
- **Le skieur** (`scripts/skieur_joueur.gd`) :
  - il monte les marches de 40 cm au plus ;
  - il est emporté par la voiture où il se tient, y compris au retournement de
    la rame en gare ;
  - s'il tombe, il revient au dernier sol sûr.
- **Portes automatiques** (`scripts/porte_auto.gd`) : entrée de la gare du bas,
  baies du mur de tête en haut, porte Génépy.
- **Chemins validés** par le banc `bench_skieur_3d.gd` :
  - en bas : place → escalier → porte d'entrée → salle → porte de la cloison
    (pendant l'embarquement) → palier → quai en escalier → voiture ;
  - le trajet, emporté par la rame ;
  - en haut : voiture → quai → palier → baie automatique → terrasse ;
  - en haut toujours : voiture → bas du quai gauche → **porte Génépy** →
    couloir → neige remontée au niveau du seuil.

### Retours du premier essai (v1.16.1) : faits

- L'AUTO attend que le skieur ait passé les portes du quai ; une fois qu'il
  est dans la voiture (passé la ligne des portes), il ferme les portes et
  part (v1.16.2).
- Hors de la voiture, plus de son de cabine : en gare, des bouffées d'air
  suivies de silences quand la rame roule ; dehors, du vent.
- Fosse de Val Claret à 1,95 m sous le quai (tête sous les rails), escalier
  au bout côté droit.
- Retour au skieur après le poste de pilotage : il retrouve sa place dans la
  voiture, au lieu de tomber dans le tunnel.
- En sens descente, il part de la terrasse du haut, à côté d'une assiette de
  frites.
- Klaxon = le vrai buzzer de la rame (vidéo de 2007, 1:56).
- Escalier au bout de la terrasse du haut, jusqu'à la neige (v1.16.4).
- Banc : 14 étapes.

### Étape 2 — le ski (v1.17.0) : fait

- **Hiver** en mode skieur : neige sur le relief (roche au-dessus de ~37°,
  rien sous 1 800 m), relief ombré, pistes damées, horizon clair
  (`relief_builder.gd`, `en_hiver()` des shaders ; `set_hiver()`).
- **Pistes** d'OpenStreetMap (`tools_pistes.py` → `textures/pistes_masque.png`
  et `scripts/pistes_donnees.gd`) : 248 tracés, 45 surfaces ; jalons de la
  couleur de la piste tous les 40 m (`domaine_skiable.gd`) ; vitesse et piste
  sous les skis en haut de l'écran.
- **Glisse** (`skieur_joueur.gd`, `_glisser`) : chausser / déchausser (E,
  bouton CHAUSSER) dehors sur la neige ; posé sur le sol affiché
  (`ReliefBuilder.hauteur_sol`) ; pesanteur, carres, neige, air, virages
  limités à 6,5 m/s², chasse-neige, pas de patineur ; arrêt par les murs des
  gares. Pilote à ski (`chemin`, `vitesse_pilote`) pour les bancs et le futur
  mode AUTO.
- **Fantôme** (`tools_fantomes.py` → `scripts/fantomes_donnees.gd`,
  `fantome_ski.gd`) : 5 descentes réelles de Kevin (26-28/04/2026), de 4 min 45
  à 10 min 15 ; il part quand on s'élance de son départ ; chrono à l'arrivée
  (200 m de la gare de Val Claret). Dans le dépôt : positions lissées et temps
  relatif seulement ; les traces brutes restent hors du dépôt (privées), dans
  `Workspace/Personnel/GPS/2026-04_Tignes/`.
- **La boucle** : en bas on déchausse, on marche jusqu'à la gare, on remonte en
  funiculaire.
- Banc `bench_ski_3d.gd` ; captures `shot_ski.gd`.

Reste à voir : les remontées mécaniques (pas de télésiège : on remonte par le
funiculaire), les sauts (il reste collé au sol), les chutes.

### Étape 3 — finitions : à faire

- **Sortie de secours du tunnel** (Kevin, 07/10/2026) :
  - percer la galerie depuis le tunnel jusqu'à la piste ;
  - débouché **circulaire comme le tunnel**, sur la piste, à 45°26′04,26″ N
    6°54′02,60″ E, altitude 2 655,89 m (Google Earth) ;
  - à cet endroit passent les pistes Double M et Face.
- Mode AUTO du skieur : la boucle complète tout seul.
- Redescendre en funiculaire, aller au poste de la rame d'en face.

## Sources

- Kevin, 07/10/2026 : la porte Génépy au bas du quai gauche (en regardant vers le
  haut), le terrain à remonter jusqu'à elle ; la sortie de secours (position).
- Kevin, 07/10/2026 : sur le quai on n'entend que des souffles d'air et des
  silences ; la fosse assez profonde pour avoir la tête sous les rails ; la
  terrasse et l'assiette de frites ; le buzzer à 1:56 comme klaxon.
- Vidéos YouTube :
  - « [FUNI284] Funiculaire Perce-Neige | Tignes (montée) », chaîne Transports
    câblés : portes de la salle du bas ;
  - « funiculaire de la grande motte », 2007 : parcours complet, sortie du haut,
    buzzer de la rame (1:55,65-1:56,65) devenu le klaxon.
- OpenStreetMap (ODbL) : pistes et remontées, requête Overpass du 07/10/2026.
