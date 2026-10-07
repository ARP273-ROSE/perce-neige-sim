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

- L'AUTO attend que le skieur ait passé les portes du quai ; une fois monté,
  le départ vient vite.
- Hors de la voiture, plus de son de cabine : en gare, des bouffées d'air
  suivies de silences quand la rame roule ; dehors, du vent.
- Fosse de Val Claret à 1,95 m sous le quai (tête sous les rails), escalier
  au bout côté droit.
- Retour au skieur après le poste de pilotage : il retrouve sa place dans la
  voiture, au lieu de tomber dans le tunnel.
- En sens descente, il part de la terrasse du haut, à côté d'une assiette de
  frites.
- Klaxon = le vrai buzzer de la rame (vidéo de 2007, 1:56).
- Banc : 12 étapes.

### Étape 2 — le ski : à faire

- Neige sur les pistes : tracés OpenStreetMap (161 tronçons autour de Tignes,
  dont Glacier, Double M, Leisse, Rimaye, Génépy, Face), en hiver sur le relief.
- Ombrage du relief (normales) pour lire les pentes.
- Glisse : chausser / déchausser, virages, chasse-neige, vitesse ; le relief
  entier en collision sur la zone skiable.
- Descente jusqu'à Val Claret, retour à pied dans la gare : la boucle.
- **Fantôme** des descentes de Kevin : 5 descentes glacier → Val Claret sur ses
  traces GPS des 26, 27 et 28/04/2026, de 7 à 12 minutes chacune. Dans le jeu :
  positions et temps relatif seulement. Les traces brutes restent hors du
  dépôt (privées), dans `Workspace/Personnel/GPS/2026-04_Tignes/`.

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
