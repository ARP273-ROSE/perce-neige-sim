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

### Étape 3 — finitions (v1.18.0) : fait

- **Sortie de secours du tunnel** (`sortie_secours.gd`) : la paroi percée à
  la chambre du galet 145 (`TunnelBuilder.ouvertures`), galerie circulaire
  jusqu'au portail sur la piste, à la position de Kevin (Google Earth
  45°26′04,26″ N 6°54′02,60″ E ; relief du jeu à 2 643,5 m, Google Earth
  2 655,89 m). Le sol suit le relief (`ReliefBuilder.amenageurs`, appelés
  avant les pièces fines) ; remblai et aire sur le relief ; collisions de la
  galerie et du relief au portail. On y va rame arrêtée à la chambre, portes
  ouvertes (Défi, panne) : porte → passerelle → galerie. Banc
  `bench_secours_3d.gd`, captures `shot_secours.gd`.
- **Skieur en AUTO** (`skieur_auto.gd`, bouton AUTO / touche X) : la boucle
  complète, étapes avec points de passage (ceux des bancs) ; la rame
  l'attend (`SkieurAuto.descend()` → `retenue`). Banc
  `bench_skieur_auto_3d.gd`.
- Redescendre en funiculaire : il suffit de monter à bord en haut.
- **Porte du personnel** (`porte_personnel.gd`) : en haut de chaque quai de
  Val Claret, la porte du garde-corps pivote quand on la pousse et sonne
  une fois (le klaxon) ; palier et escalier jusqu'au fond de la fosse
  (`stations_builder.gd`, `_build_pit`).
- **Issues de secours de la face** (bouton ÉVACUER, touche U — I est
  « inverser » ; PC : U relayée par `skieur_evacuer`) : les quatre D jaunes sont des maillages à
  part (`TrainBodyBuilder._build_cap`, clé « Av/Ar + G/D »), le fond de
  calotte des collisions est percé à leur place (`CollisionsJeu._calotte`,
  `set_issues`). Possible dans une rame arrêtée en tunnel
  (`main.evacuation_possible`) ; collisions du tunnel, de la voie et de
  l'escalier de service construites à la demande autour du marcheur
  (`CollisionsJeu.assurer_autour`, ± 80 m) ; rame retenue tant qu'il est à
  pied dans le tunnel (écoute 4) ; panneaux remis à quai portes ouvertes.
  Banc `bench_issues_3d.gd`.
- **Écoute selon l'endroit** (`main._gare_ecoute`, `_gain_machinerie`,
  `TrainAudio.gare_ecoute` / `gain_machinerie`) : 0 rame, 1 gare basse
  (souffle), 2 dehors (vent), 3 gare haute (machinerie à −6 dB par
  doublement de la distance au-delà de 4 m, plancher −24 dB —
  `audit_physique/son_gare_haute.sage`), 4 tunnel à pied (souffle). Les
  buzzers de quai sonnent dans leur gare à chaque départ, même du milieu
  du tunnel, jamais depuis une rame en tunnel. Banc `bench_ecoute_3d.gd`.
- Souffle plus aigu, sifflement de fil (`tools_sons_skieur.py`).
- **Retours du troisième essai PC** (07-08/10/2026) : couloir de la
  voiture — capsule inclinée avec la voiture qui porte
  (`SkieurJoueur._aligner_capsule`, `up_direction` = y de la voiture :
  verticale dans le monde, elle accrochait le haut des porte-skis qui
  penchent avec la caisse à 16,7°), glissement le long de tout mur
  (`wall_min_slide_angle` 0, pas de côté kinématique), bancs à l'assise
  (0,73-1,53), porte-skis 0,36 de large, bancs d'extrémité −0,45 m,
  pupitre/siège replacés (signe de `dz`) ; le passage est un slalom
  (couloir à droite aux paliers pairs, à gauche aux impairs, porte-skis
  dans la moitié arrière du palier) ; touche
  d'évacuation **U** ; bouton **EXPLOIT.** du HUD (exploitation auto, Web =
  `auto_operator`, PC = touche X relayée, état `exploitation` reçu) ;
  **musiques des gares** (`sons/musique/gare_basse.mp3` = ouverture
  d'orchestre, `gare_haute.mp3` = Toréador ; HORS dépôt public, posées par
  `deploy_web.sh` dans `musique/` de la PWA ; `TrainAudio._update_musique`
  par écoute 1 / 3 ; PC `SoundSystem.set_musique_gare`).
- **Retours du deuxième essai PC** (07/10/2026) : AUTO non forcé à
  l'activation quand une rame est à quai (elle attend qu'on monte ;
  `_entrer_skieur`, PC `basculer_skieur`) et enclenché à bord
  (`_maj_skieur`, PC `_appliquer_etat_skieur` → `skieur_embarque`) ;
  retenue plafonnée 45 s (`AutoOperator.RETENUE_MAX_S`, PC
  `AutoOps.RETENUE_MAX_S`) ; vues verrouillées en skieur sur le PC ;
  portes à la stabilisation de la rame seule (`rebound_envelope_propre`,
  PC `rebound_envelopes_m()[0]`) ; portes du quai dès les portes cabine
  ouvertes (`GareAval.mettre_a_jour`, `finished`) ; skis à +10 cm
  (`Y_SKI`), postures schuss / chasse-neige (`SkieurMesh.squelette_schuss`,
  `squelette_chasse`, `skis_aux_pieds(mat, 22°)`), chute
  (`SkieurJoueur._chuter`, `V_CHUTE_MUR` 6, `V_CHUTE_ROCHE` 8, `CHUTE_S`
  2,5) ; panneaux ronds nommés (`DomaineSkiable._construire_panneaux`,
  tous les 250 m, Label3D) ; néons et câbles du tunnel sur la paroi.

Reste : le poste de la rame d'en face (on ne conduit que la rame choisie au
départ), les remontées mécaniques, sauts et chutes.

## Sources

- Kevin, 07/10/2026 : la porte Génépy au bas du quai gauche (en regardant vers le
  haut), le terrain à remonter jusqu'à elle ; la sortie de secours (position).
- Kevin, 07/10/2026 : sur le quai on n'entend que des souffles d'air et des
  silences ; la fosse assez profonde pour avoir la tête sous les rails ; la
  terrasse et l'assiette de frites ; le buzzer à 1:56 comme klaxon.
- Kevin, 07/10/2026 : photo de l'issue de secours vue de l'intérieur (les D
  jaunes cerclés de noir de part et d'autre du pare-brise, la paroi du
  poste à gauche) ; l'escalier de service à droite en montant ; les règles
  de ce qu'on entend (souffle en bas, machinerie en haut, air dehors,
  buzzers dans leur gare) ; la porte du personnel qui sonne ; le souffle à
  rendre plus aigu, « comme un fil ».
- Vidéos YouTube :
  - « [FUNI284] Funiculaire Perce-Neige | Tignes (montée) », chaîne Transports
    câblés : portes de la salle du bas ;
  - « funiculaire de la grande motte », 2007 : parcours complet, sortie du haut,
    buzzer de la rame (1:55,65-1:56,65) devenu le klaxon.
- OpenStreetMap (ODbL) : pistes et remontées, requête Overpass du 07/10/2026.
