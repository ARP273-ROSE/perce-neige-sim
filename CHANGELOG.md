# Journal des versions — Perce-Neige Simulator

Historique détaillé, version par version, du plus récent au plus ancien.
Chaque entrée dit ce qui a changé, pourquoi (souvent un retour d'essai),
et comment ça a été vérifié. Le README ne garde que la présentation du
projet ; les versions antérieures à la 1.12 sont résumées dans le manuel.

## v1.13 → v1.15 (septembre 2026)

**v1.18.3** — retours du quatrième essai sur PC.
- « En mode exploitation auto tu repasses tout seul en mode normal, sinon
  ça fait n'importe quoi » → activer l'exploitation automatique (X, bouton
  AUTO, EXPLOIT. du skieur, montée du skieur) ramène au mode NORMAL (le
  Défi n'a plus de sécurités, le mode Pannes tire des pannes). PC et Web.
- « La première fois qu'on active le skieur sur le PC ça prend plus de
  10 s, on ne sait pas si ça marche, il n'y a pas de message » → le temps
  de préparer le décor (collisions des gares, par tranches sans gel), le
  bouton SKIEUR du PC affiche « décor 45 % (6 s) », le journal note le
  début et « décor 3D prêt en N s » ; dans la vue 3D le message reste
  affiché avec l'avancement. La vue 3D du PC construit deux fois plus par
  image (14 ms au lieu de 7 : le PC dessine à part).

**v1.18.2** — retours du troisième essai sur PC.
- « En haut et en bas de la rame je suis bloqué par les derniers
  porte-skis, je ne peux pas accéder à l'avant ni évacuer » → trois
  causes. (1) La caisse penche avec la pente (16,7° à mi-tunnel) et les
  porte-skis, fixés au plancher, penchent avec elle ; le skieur, lui,
  était vertical dans le monde : son haut, décalé de 50 cm, accrochait le
  haut des porte-skis — sa capsule prend maintenant l'inclinaison de la
  voiture qui le porte. (2) Abordé presque de face, un mur arrêtait net
  (Godot ne glisse pas sous 15° de la normale) : on glisse maintenant le
  long de tout mur. (3) Collisions plus justes : bancs à leur assise (plus
  la lèvre), porte-skis 7 cm plus étroits, bancs d'extrémité raccourcis,
  pupitre et siège enfin à leur place (ils étaient posés 16 m derrière la
  voiture). Le passage reste un slalom : le couloir libre est à droite aux
  paliers pairs, à gauche aux impairs, comme dans la vraie rame.
- « Ton menu d'aide dit que c'est la touche I mais elle est déjà
  attribuée à Inverser le sens » → l'évacuation est sur **U** (issUe de
  secours), partout (aide F1, manuel, README).
- « Rajoute la possibilité d'activer / désactiver le mode auto même en
  mode skieur » → bouton **EXPLOIT.** dans le HUD du skieur (Web :
  l'automate local, aussi F3 ; PC : relayé au PC, comme son bouton AUTO),
  état affiché dans les deux sens.
- Musiques d'ambiance des gares (les fichiers de Kevin) : l'ouverture
  d'orchestre en attente gare du bas, la chanson du Toréador en gare du
  haut, en boucle à bas niveau quand le skieur y est (Web et PC).
  Enregistrements hors du dépôt public : `sons/musique/` (ignoré) sur le
  PC et le NAS, servis à côté de la PWA (`musique/`), chargés à la demande.

**v1.18.1** — correctif de construction : les paquets Linux et macOS de la
1.18.0 ne se construisaient pas (`wave` utilisé sans import dans l'écriture
atomique des WAV — l'application plantait à la synthèse des sons au
premier lancement ; les tests ne synthétisent pas de son). Import ajouté,
synthèse vérifiée.

**v1.18.0** — audit complet (plantages, gels, fluidité, PC multiplateforme,
cohérence), sortie de secours du tunnel jusqu'à la piste, skieur en AUTO.
- Kevin : « fais un audit complet physique, anti crash, freeze,
  adaptabilité, perfo, fonction PC multiplateforme, parallélisme,
  fluidité, fonctionnalité, réalisme… et finis ce qui reste à faire :
  sortie de secours, piste, skieur ».
- **Audit** : trois passes de lecture du code (version Web/3D, application
  PC, cohérence PC ↔ Web et réalisme), par zones. Aucun plantage franc
  trouvé ; les défauts réels, tous corrigés :
  - **Gels et à-coups (3D)** : la physique ne rattrape plus son retard en
    rafale après des images longues (rame à 4×, buzzers décalés) ;
    l'orthophoto du relief est préparée hors du fil principal ; les
    collisions du skieur se construisent par tranches de 7 ms sur
    quelques images au lieu d'une seule (gel d'une à plusieurs secondes
    sur iPad, son coupé), avec « Préparation du décor… » ; les réglettes
    de l'évitement ont deux matériaux prêts (un changement de matériau
    compilait un nuanceur à chaud).
  - **Coût par image (3D)** : l'écran Pro-face de la rame d'en face
    (invisible) n'est plus recomposé 30 fois par seconde ; le tronçon
    libre du câble au culot n'est refait que si la rame a bougé (à quai :
    plus rien) ; le panneau de panne ne se remet en forme que si la panne
    change ; les passagers ne sont repositionnés que si l'inclinaison a
    changé ; plus de chaînes formatées ni de recherches de nœuds à chaque
    image (pupitre, trait du tunnel, skieur).
  - **Commandes** : entrer en skieur en tenant FREIN ou +VITESSE ne les
    laisse plus « tenus » ; dans la vue 3D du PC, J et C passent au PC
    (une bascule locale était écrasée au paquet suivant).
  - **PC, pertes de données** : le programme installé par le Setup
    gardait ses données (journal d'exploitation, réglages, meilleurs
    scores) dans un dossier que le Setup efface à chaque passage ; elles
    vivent maintenant dans le profil (reprise automatique des anciennes).
    La trace d'un crash natif était vidée avant d'être lue : relevée
    d'abord. Les WAV synthétisés sont écrits en entier puis posés (un
    fichier tronqué n'« existait » plus à moitié).
  - **PC, gels** : téléchargement des PDF (F6) hors du fil de
    l'interface ; arrêt du viewer 3D sans attendre jusqu'à 2,5 s ;
    recherche de la fenêtre X11 (Linux) dans le fil de lancement ; plus
    d'appels disque à chaque image pour vérifier que les sons existent.
  - **PC, robustesse** : un mp3 indécodable ne bloque plus PRÊT pour
    toujours ; le journal SQLite n'est plus une exception à chaque tick si
    la base est pleine ou verrouillée ; une exception qui revient à
    chaque image n'est signalée qu'une fois par minute (60 rapports par
    seconde avant) ; la file des rapports est purgée même sans accord
    d'envoi ; un seul viewer 3D lancé à la fois ; les lecteurs audio sont
    arrêtés avant la pose d'une mise à jour ; journaux bornés à 1 Mo.
  - **PC, multiplateforme** : polices de repli sur Linux et macOS (Segoe
    UI → Noto Sans, DejaVu Sans, Helvetica ; Consolas → DejaVu Sans Mono,
    Menlo) ; le spec Windows embarque VERSION et kit.json (sinon mise à
    jour proposée à chaque lancement).
  - **Cohérence** : buzzer de départ en haut à 6,0 s des deux côtés (= le
    clip ; le PC disait 6,5) ; horaires d'exploitation rétablis à toute
    sortie du mode skieur ; constantes mortes de la version Web mises au
    vrai (fermeture des portes 5,3 s, amortissement 0,15).
- **Sortie de secours** (`scripts/sortie_secours.gd`) : « tu peux percer la
  sortie de secours dans le tunnel, et sortir sur la piste ; sur la piste
  la sortie est circulaire comme le tunnel, je t'ai mis sa position ».
  - Le débouché est posé sur le relief du jeu à la position donnée
    (45°26′04,26″ N 6°54′02,60″ E, `audit_physique/sortie_secours.sage`).
    Google Earth y donne 2 655,89 m, le relief IGN du jeu 2 643,5 m : la
    galerie descend donc de la chambre (sol à 2 661 m).
  - La paroi est vraiment percée à la chambre du galet 145 (plus un fond
    sombre). Galerie circulaire de 3 m, sol plat, 8 m perpendiculaires
    puis tout droit vers le portail (114 m), le sol 4,3 m sous le relief
    en rampe de 36 % au plus ; là où le relief ne couvre plus le tube, un
    remblai ; lampes tous les 12 m ; mur de tête en béton percé d'un
    cercle, aire plane devant.
  - Pour y aller : rame arrêtée à la chambre, portes ouvertes (mode Défi
    ou panne) ; de la porte on descend sur la passerelle (les paliers de
    quai des portes ne sont actifs qu'en gare), puis l'ouverture. Dehors,
    la trace n° 1 de Kevin passe à 88 m : on chausse et l'on descend.
- **Skieur en AUTO** (bouton AUTO, touche X ; `scripts/skieur_auto.gd`) :
  « il peut boucler la boucle et remonter ». La boucle entière toute
  seule : place → salle → rame (il attend la rame à quai), trajet, sortie
  par la porte Génépy, à pied jusqu'au départ de la trace n° 4 (au pied
  de la gare), chausser, descente sur la trace, déchausser à Val Claret,
  retour à la gare, et on recommence. La rame l'attend aussi quand il
  descend à l'arrivée. Bloqué trop longtemps : reposé à l'étape suivante.
  En haut, il descend par la porte où il est monté (les porte-skis barrent
  l'allée : on ne traverse pas la voiture).
- **Porte du personnel et escalier de la fosse** (gare basse,
  `scripts/porte_personnel.gd`) : « faut un escalier pour descendre dans
  la fosse dans la gare aval au niveau des portes en haut du quai réservé
  personnel ; au moment où on pousse la porte ça sonne avec le son du
  klaxon puis ça s'arrête ». En haut de chaque quai, la porte du
  garde-corps pivote quand on la pousse et sonne une fois (le klaxon) ;
  derrière, un palier et un escalier descendent au fond de la fosse.
- **Issues de secours de la face** (bouton ÉVACUER, touche U — relayée par
  le PC) : « de part et d'autre de la vitre frontale, les parties jaunes
  cerclées de noir sont des issues de secours et ça s'en va en cas
  d'évacuation. Donc en cas d'arrêt dans le tunnel, rajoute la
  possibilité d'enlever ces parties, de marcher sur l'escalier en partie
  droite du tunnel quand on regarde vers le haut et ensuite de retourner
  en gare à pied ou de sortir par la sortie de secours au milieu ».
  - Les quatre D jaunes (deux par calotte) sont des panneaux à part,
    découpés dans la calotte et dans sa doublure, liseré noir conservé.
  - Dans une rame **arrêtée en tunnel** seulement : les panneaux
    s'effacent (maillages et collisions), on passe par le trou, on descend
    sur la voie, l'escalier de service (à droite en montant) ramène en
    gare ou à la galerie de secours. Les collisions du tunnel, de la voie
    et de l'escalier se construisent au fur et à mesure autour du marcheur
    (zones de ± 80 m) : rien n'est payé tant qu'on ne descend pas.
  - Tant que quelqu'un est à pied dans le tunnel, la rame est retenue ;
    les panneaux sont remis à l'arrêt suivant à quai, portes ouvertes.
- **Ce qu'on entend, selon l'endroit** : « le bruit du souffle dans le
  tunnel ne s'entend qu'en gare du bas sur les quais et dans la salle
  d'attente ; quand on attend en gare du haut on entend strictement le
  même son que celui de la vue machinerie, que tu modules en fonction de
  la distance à la machinerie ; et si on est dehors on entend l'air. Vue
  machinerie ou en gare du haut sur les quais, même si on pilote la rame
  du bas on entend le buzzer du haut ; les buzzers sonnent leurs sons
  respectifs dans les gares du bas et du haut et on les entend si on y
  est, même si ça redémarre au milieu du tunnel ; par contre si on est
  dans la rame, en vue extérieure ou à l'intérieur, on n'entend pas les
  buzzers des gares ».
  - Gare basse : les bouffées d'air et les silences. Gare haute : la
    salle des machines, à −6 dB par doublement de la distance à la
    machinerie au-delà de 4 m, plancher −24 dB
    (`audit_physique/son_gare_haute.sage`). Dehors : le vent. À pied
    dans le tunnel : les bouffées. Dans une rame : la cabine.
  - Buzzers : celui de chaque gare sonne dans sa gare à chaque départ —
    on l'entend des quais, de la salle d'attente, de la vue salle des
    machines, d'une rame à quai — y compris quand la rame repart du
    milieu du tunnel ; jamais d'une rame en tunnel ni dehors. Mêmes
    règles sur le PC (le 4ᵉ champ de `skieur_etat` porte le gain de la
    machinerie).
- **Souffle plus aigu** (`tools_sons_skieur.py`) : « le souffle du vent
  est trop grave, faut monter un peu pour que ça siffle un peu comme un
  fil, plus de grave ». Bruit rose 300-3 000 Hz (au lieu de brun
  150-1 500) et un sifflement de fil, deux bandes étroites qui glissent
  de 1 500 à 1 900 Hz ; le vent de dehors monte aussi (180-2 500 Hz) avec
  un fil qui siffle faiblement.
- **Retours du deuxième essai sur PC** (v1.17.0) :
  - « En vue skieur le mode auto est forcé et se déclenche alors que je
    suis encore dehors, pas le temps d'embarquer » → une rame à quai,
    prête à l'embarquement, n'est plus mise en exploitation automatique à
    l'activation du skieur : elle attend qu'on monte (portes ouvertes au
    besoin) ; l'exploitation s'enclenche quand on est dedans et part 1,5 s
    plus tard. Si la rame est en ligne, l'exploitation tourne pour qu'elle
    vienne. PC et Web.
  - « La séquence reste bloquée à embarquement 6 s… elle devrait se
    poursuivre toute seule » → la rame n'attend pas un skieur resté sur
    le quai plus de 45 s : passé ce délai elle ferme et part. PC et Web.
  - « Un micmac de vues : en skieur je peux changer de vue cockpit,
    externe, machinerie, le son n'est plus cohérent » → sur le PC, O et
    le bouton VUE sont refusés en skieur (message), et le son de la salle
    des machines ne suit plus cette vue fantôme.
  - « En haut les portes de la rame peuvent s'ouvrir après l'arrêt car il
    n'y a pas d'oscillation, en bas il faut attendre » → l'ouverture des
    portes attend la stabilisation de LA rame concernée, plus de
    l'installation entière : en haut (brin court, millimètres) elles
    s'ouvrent 3 s après l'arrêt ; en bas, à la fin du rebond. PC et Web.
  - « Une fois les portes cabine ouvertes, les portes d'accès au quai
    doivent s'ouvrir » → les portes coulissantes de la salle d'attente
    s'ouvrent dès les portes de la rame ouvertes à quai (sur le PC, le
    voyage restait « commencé » jusqu'au demi-tour de l'automate, bien
    après).
  - « Les skis sont cachés sous la neige ; le skieur devrait se mettre en
    schuss ou en chasse-neige ; dans les décors trop vite on devrait
    déchausser et s'exploser, plus qu'à rechausser » → skis posés 10 cm
    au-dessus du sol calculé (les tuiles du relief, maillées autrement,
    les cachaient) ; **postures** : recroquevillé en schuss (bâtons sous
    les bras), jambes écartées et skis en V (22°) en chasse-neige ;
    **chute** contre un mur à plus de 6 m/s ou sur la roche (pente > 37°)
    à plus de 8 m/s : skis déchaussés, 2,5 s à terre, « Chute ! CHAUSSER
    (E) pour rechausser ».
  - « Rajoute les panneaux ronds des bords de piste de la couleur
    adéquate avec Tignes et le nom de la piste, sinon je suis perdu » →
    500 panneaux : un disque de la couleur de la piste sur un poteau, à
    droite en descendant, au départ et tous les 250 m, « TIGNES » et le
    nom en lettres blanches, face au skieur qui descend.
  - « Les néons, les câbles et ce qui est accroché dans le tunnel défilent
    à l'intérieur de la cabine côté gauche en montant » → ils étaient dans
    le gabarit de la caisse (néons à 1,40 m de l'axe, câbles à 1,55 ;
    la caisse fait 1,72 de rayon) : posés sur la paroi (1,68 et 1,84 m).
- **Audit fonctionnel PC ↔ Web** (deuxième passe : pannes, départs,
  exploitation automatique, manuel). Appliqué :
  - **Pannes (Web)** : l'annonce d'une panne stoppante attend l'arrêt
    (plus d'« évacuation » pendant le freinage) ; une panne
    catastrophique enchaîne incident technique à l'arrêt → lumières
    baissées → évacuation → cabine vidée (R rallume). « Défaut porte » et
    « Inondation tunnel » ne stoppent plus la rame (plafond 4 m/s pour
    l'inondation, comme le PC) ; le défaut porte verrouille le départ
    tant que les portes n'ont pas été cyclées. Perte 400 V et tambour
    bloqué coupent vraiment la traction (tambour tenu, la rame ne recule
    pas). Surchauffe et moteur HS déclassent la puissance (0,55 et 2/3,
    valeurs du PC) ; pic de tension (+6 500 daN) et mou (8 000 daN) se
    voient sur la jauge, le mou déclenche l'urgence sous un coup de
    frein, le seuil rouge 35 000 daN aussi (hors Défi). Aiguillage Abt :
    50 s ; les pannes « jusqu'à la fin du voyage » sont levées à
    l'arrivée. Une catastrophe ne se lève plus d'un tap (PANNE, F2,
    LEVER, MODE) : seul NOUVEAU VOYAGE. Pas d'empilement de pannes.
    « PA + radio perdus » bloque les annonces en ligne (PC et Web), pas
    celles de quai.
  - **Départs (Web)** : la consigne n'est plus effacée pendant la
    séquence de départ (la rame part à la consigne affichée dès la fin
    du buzzer) ; PRÊT/DÉPART refuse consigne à 0, urgence engagée ou
    panne catastrophique, avec le message du PC ; confirmation simulée de
    l'autre rame 2–4 s entre la fin de la fermeture et le buzzer, voyant
    PRÊT VÉHICULE allumé au buzzer seulement. FREIN tenu abaisse la
    consigne (0,8/s). Défi : PRÊT/DÉPART portes ouvertes part au buzzer
    seul, portes ouvertes (départ « sauvage » enfin possible).
  - **Survitesse et collisions (Web)** : cascade +10 % urgence, +12 %,
    +20 % parachute 3,6 m/s² dans tous les modes ; collision butoir et
    collision entre rames dans tous les modes (hors Défi : HUD
    « COLLISION — nouveau voyage (R) » et bouton NOUVEAU VOYAGE) ; le
    déraillement reste au Défi.
  - **Exploitation automatique (Web)** : pointe 9–12 h / 14–16 h à
    12 m/s, 10,3 m/s en creuse ; charge de passagers selon l'heure et la
    saison, formule exacte du PC, contrepoids en sens inverse ; l'arrivée
    est laissée à l'enveloppe du régulateur ; sur catastrophe l'AUTO se
    désactive ; journal avec passagers, croisière, pointe.
  - **PC** : touche 4 = « frein de sécurité poulie, verrouillé
    (1,25 m/s²) » (plus de « 5 m/s² ») ; au demi-tour, confort et
    drapeaux du Défi repartent de zéro ; après « Perte 400 V », « Tambour
    bloqué » ou « Aiguillage Abt », le chrono ne court qu'à l'arrêt et
    vaut « reprise du secours » : PRÊT lève la panne, DÉPART repart à
    3 m/s jusqu'à la gare ; le planificateur ne tire plus de panne à
    quai.
  - **Manuel** (FR et EN) : consigne continue à la flèche haut (plus de
    W ni de paliers) ; séquence PC D → PRÊT → 2–4 s → DÉPART, premier
    PRÊT après l'arrivée = demi-tour ; portes sous 0,2 m/s, consigne
    toujours réglable, 15 m/s en Défi, rampe 0,32 m/s² ; charges d'hiver
    et d'été ; l'autre rame s'immobilise là où elle était à la rupture ;
    encadré « Différences avec le PC » (ouverture et inversion
    automatiques à l'arrivée, veille PC seulement) ; 4 = le même frein
    que Maj, verrouillé.
  - Laissé tel quel, à dessein : l'arrêt d'urgence commandé modélisé en
    frein de voie (choix de la v1.15.52), la rame d'en face figée à la
    rupture, l'arrêt anormal en tunnel de la version Web.
- Vérifié :
  - nouveaux bancs `bench_secours_3d.gd` (de la voiture à la piste par la
    galerie, puis à ski jusqu'à Val Claret), `bench_skieur_auto_3d.gd`
    (la boucle bouclée, 22 min), `bench_issues_3d.gd` (ÉVACUER : par le
    trou, sur la voie, 26 m d'escalier ; refusé à quai, issues remises)
    et `bench_ecoute_3d.gd` (12 points : écoute et buzzers selon
    l'endroit) ; `bench_skieur_3d.gd` passe par la porte du personnel et
    l'escalier de la fosse ;
  - `bench_ski_3d.gd` : panneaux nommés, chute contre la façade de Val
    Claret à 9 m/s puis E pour rechausser ; tests PC du skieur adaptés
    (rame à quai qui attend, retenue plafonnée, portes du haut sans
    attendre le contrepoids) ;
  - `bench_pannes_3d.gd` : 13 cas de plus (effets des pannes) ;
    `bench_portes_3d.gd` et `bench_pupitre_3d.gd` suivent la nouvelle
    séquence de départ ;
  - 20 bancs Godot, 104 tests PC ; rendus de la galerie, du portail, des
    issues de secours et de la porte du personnel.

**v1.17.0** — le ski : chausser en haut, descendre les pistes balisées
jusqu'à Val Claret, contre le fantôme des descentes de Kevin (suivi :
SKIEUR.md).
- Kevin : « arrivé en haut, il est capable de skier sur le décor pour
  redescendre ; tu as les trajectoires de pistes sur les plans des pistes ;
  tu me mets de la neige sur la piste » ; « tu as balisé les pistes ? » ;
  « je t'ai mis mes trajectoires GPX, si jamais ça peut t'aider ».
- **L'hiver** (en mode skieur) : la photographie aérienne de l'IGN est
  d'été. Le relief passe sous la neige, sauf la roche des pentes de plus de
  37° environ et les fonds sous 1 800 m.
  - Relief ombré par le soleil des gares, pour lire les pentes.
  - Pistes damées d'un blanc net, hors-piste gris bleuté, grain de neige
    près de l'œil.
  - Horizon clair, skieur éclairé par le soleil (il était à contre-jour).
- **Pistes d'OpenStreetMap** (`tools_pistes.py`) : 248 tracés et 45
  surfaces de piste sur toute l'emprise du relief ; les itinéraires
  hors-piste ne sont ni damés ni balisés.
  - Neige damée sur 30 m de large autour de l'axe des pistes.
  - **5 667 jalons**, un de chaque côté tous les 40 m, de la couleur de la
    piste (verte, bleue, rouge, noire).
  - En haut de l'écran : vitesse et piste sous les skis (« 54 km/h ·
    Double M (rouge) »).
- **Chausser** : bouton CHAUSSER, touche E (aussi sur le PC), dehors sur la
  neige. Refusé dans une gare ou une rame.
- **La glisse**, posée exactement sur le relief affiché :
  - la pesanteur le long de la pente ; les carres absorbent ce qui part en
    travers des skis ;
  - frottement de la neige damée (μ = 0,05), traînée de l'air (moindre en
    schuss) ;
  - virages d'autant plus larges que l'on va vite (6,5 m/s² au plus) ;
  - chasse-neige, pas de patineur (3 m/s sur le plat), montée en canard ;
  - arrêt par les murs des gares.
  - Commandes : Q / D (ou joystick) pour tourner, Z pour pousser, S pour
    le chasse-neige, Maj ou SCHUSS pour le schuss. La caméra se place
    derrière les skis.
- **Le fantôme de Kevin** (`tools_fantomes.py`) : ses 5 descentes réelles
  du 26 au 28/04/2026, de la gare du glacier à Val Claret, de 4 min 45 à
  10 min 15.
  - Le dépôt n'en garde que les positions lissées, une par seconde, et le
    temps relatif : ni date, ni heure, ni altitude GPS.
  - Les traces qui montent d'abord au glacier partent du point le plus
    proche de la gare après le haut.
  - Le fantôme, un skieur bleu translucide, part quand on s'élance de son
    point de départ. À l'arrivée, à 200 m de la gare de Val Claret :
    « Arrivée : 9 min 04 s — fantôme 7 min 39 s (+85 s) ».
- **La boucle** : en bas, on déchausse, on marche jusqu'à la gare, et
  l'on remonte en funiculaire.
- Vérifié :
  - nouveau banc `bench_ski_3d.gd` : refus dans la rame ; hiver et
    jalons ; descente complète sur la trace n° 4, toujours au sol, 54 km/h
    au plus ; course contre le fantôme ; déchaussé, il marche ;
  - 16 bancs Godot, 104 tests PC ;
  - rendus `shot_ski.gd`.

**v1.16.5** — documentation à jour de tout ce qui est arrivé depuis
septembre : manuel, aide F1, menu Aide, README.
- Kevin : « je pense que tu peux compléter manuel, menu aide, menu F1,
  readme… avec tous les nouveaux ajouts qu'on a faits depuis ».
- **Manuel** (`manuel_perce_neige.pdf`, FR et EN, 54 pages au lieu de
  45) ; il s'arrêtait à la v1.15.34 :
  - nouveautés d'octobre (v1.15.35 à v1.16.5) ;
  - installation Windows (Setup), Linux, macOS et version Web ;
  - tables des touches corrigées et complétées : ↑ / ↓ seuls (W est la
    veille, S ne fait rien), PRÊT, DÉPART, inverser, veille, éclairage du
    tunnel, Retour arrière, Début, F7 / F8, F9, F11, menus Aide et
    Affichage ;
  - nouvelles sections : les vues 3D et le pupitre (chaque bouton, son
    rôle, sa touche), la version Web (boutons à l'écran), le skieur ;
  - FAQ : passer en skieur, pupitre 3D sur PC, taille de la fenêtre, 3D
    qui saccade ; mise à jour et rapports d'incident décrits comme ils
    marchent aujourd'hui ;
  - longueur : 3 474 m, comme le README et le compteur.
- **Aide F1** : F9 (skieur) ; conseils sur le pupitre 3D cliquable et le
  skieur.
- **Correction** : l'aide F1 et le README annonçaient un arrêt d'urgence à
  5 m/s². Le simulateur freine à 1,25 m/s² (arrêt d'urgence commandé) et
  à 3,6 m/s² (parachute, sur survitesse ou rupture du câble) ; 5 m/s²
  n'est que le plafond réglementaire. Le manuel le disait déjà.
- **Menu Aide** : raccourcis (F1), manuel et guide PDF (F6), la vraie
  machine (F3), skieur (F9), nouveautés (journal des versions en ligne),
  puis mise à jour, signalement, à propos (avec le lien de la version
  Web).
- **README** : gares, relief, pupitre, skieur, sons ; commandes du skieur
  et de la version Web. Le README de la version Web (`godot_project/`),
  resté à la v0.1.0, est réécrit.
- **Version Web** : K (skieur) dans la barre d'aide du clavier.
- PC : clé EN MARCHE du pupitre 3D sur arrêt, la MONTÉE est refusée,
  comme dans la PWA.
- Vérifié : 104 tests PC, banc du pupitre, manuel compilé sans erreur.

**v1.16.4** — pupitre : cadres et boîte ARRÊTS comme sur la photo ;
escalier au bout de la terrasse du haut.
- **Pupitre**, d'après la photo envoyée par Kevin :
  - « le trait du cerclage s'interrompt pour le titre du box » : le trait
    du haut des cadres PORTES 1 à 6, PORTES 7 à 12 et ÉCLAIRAGE est coupé
    à la largeur du titre ;
  - à gauche, cadre **ARRÊTS** : le gros coup-de-poing au milieu,
    **URGENCE** ; le petit à droite, **ÉLECTRIQUE** ; à gauche d'URGENCE,
    l'emplacement d'un bouton qui n'est pas monté (obturateur gris, qui ne
    s'appuie plus).
  - Les deux libellés sont placés au haut du cadre : vus du siège, les
    champignons les cachaient.
- **Escalier de la terrasse** : « au bout de la terrasse au sud en haut,
  faut un escalier pour rejoindre le sol ».
  - Sur le petit côté de la pointe sud-ouest, là où la neige est la plus
    proche du plancher : 2,85 m dessous, contre 4 à 11 m le long du grand
    côté sud.
  - 16 contremarches de 17,8 cm, giron de 29 cm, 1,4 m de large ; marches
    en caillebotis, limons galvanisés, mains courantes noires ; le
    garde-corps s'ouvre en haut ; la neige est mise à niveau au pied.
- Vérifié :
  - banc du skieur, 14 étapes : il descend l'escalier jusqu'à la neige ;
  - 15 bancs Godot ; rendus du pupitre et de l'escalier.

**v1.16.3** — PC : les boutons du pupitre 3D agissent, et le mode skieur
arrive sur le simulateur PC.
- Kevin : « sur le PC, les boutons marchent mais il ne se passe rien
  ensuite, le bouton éclairage cabine ne marche pas, alors que dans la PWA
  ça fonctionne ; là je fais fermer les portes et rien ne se passe » ;
  « comment je passe en mode skieur sur le PC ? ».
- Cause : sur PC, la rame est pilotée par le simulateur et la vue 3D ne
  fait que l'afficher. La liaison n'allait que du PC vers la 3D : un clic
  sur le pupitre 3D montrait le geste, et le PC n'en savait rien.
- **Retour de la 3D vers le PC** (UDP, port 7778) :
  - chaque bouton du pupitre 3D appuie la touche du PC qui fait la même
    chose, avec les mêmes verrous :
    - PORTES 1 à 6 / 7 à 12 (ouverture, fermeture) → D ;
    - ÉCLAIRAGE CABINE et COMPARTIMENT → C ;
    - KLAXON → K (tenu) ;
    - − VITE / + VITE → flèches (tenues) ;
    - MONTÉE → PRÊT (V), puis DÉPART (Z) ;
    - URGENCE → 4 ; ARRÊT ÉLEC → 3 ;
  - en exploitation AUTO, la rame reste à l'automate, comme au clavier.
- **Mode skieur sur PC** : touche **F9** ou bouton **SKIEUR**, en vue 3D
  (F4).
  - ZQSD / WASD ou flèches pour marcher, Maj pour courir, V pour la 1re /
    3e personne, glisser dans la 3D pour regarder.
  - Le funiculaire passe en exploitation AUTO, 24 h/24, avec la même
    règle que la PWA : il attend le skieur resté en gare et ferme les
    portes dès qu'il est dans la voiture.
  - Hors de la rame, le son de la cabine s'efface ; la 3D joue les
    bouffées d'air du quai et le vent dehors.
  - CONDUIRE (près du poste) : fin du mode skieur et de l'AUTO. F9 ou
    QUITTER : retour à la conduite, l'AUTO continue.
- Vérifié :
  - tests PC : 104, dont le pupitre 3D (éclairage, portes, klaxon,
    vitesse) et le skieur (attente sur le quai, fermeture à bord,
    CONDUIRE) ;
  - vue 3D lancée en mode PC, pilotée par UDP : elle renvoie l'état du
    skieur ;
  - 15 bancs Godot.

**v1.16.2** — en AUTO, les portes se ferment dès que le skieur est dans la
voiture.
- Kevin : « je veux qu'il ferme les portes de la rame une fois qu'il a
  détecté que j'étais à l'intérieur du funi ».
- Monté pendant l'arrêt et passé la ligne des portes, le skieur déclenche
  la séquence de départ 1,5 s plus tard : annonce, fermeture des portes,
  buzzer, départ (environ 30 s en tout).
- Debout dans l'embrasure d'une porte, il compte encore comme « sur le
  quai » : les portes restent ouvertes.
- Déjà à bord à l'arrivée : arrêt habituel de 30 s, le temps de
  descendre.
- Vérifié : banc du skieur, 13 étapes (dont l'embrasure).

**v1.16.1** — le skieur, retours du premier essai : départ manqué, son du
quai, fosse, chute au retour, frites, klaxon.
- **Départ manqué** : « la fermeture auto et le départ ont été déclenchés
  quand j'ai passé les portes du quai, donc j'ai loupé le départ ».
  - Tant que le skieur est entre la salle et la voiture, l'AUTO attend
    (au moins 6 s de plus).
  - Une fois monté, le départ vient 8 s plus tard au plus.
- **Son sur le quai** : « j'entends le son comme si j'étais dedans, alors
  qu'en vrai en bas on n'entend rien, à part des souffles d'air réguliers /
  vent sifflements suivis de silences dus aux surpressions dans le
  tunnel ».
  - Hors de la voiture, le son de la cabine est coupé.
  - En gare, rame en marche : une bouffée d'air toutes les 9 à 18 s, plus
    forte quand la rame va vite, puis le silence.
  - Dehors : un vent léger.
  - Sons synthétisés (`tools_sons_skieur.py`) : aucune prise de son du
    quai.
- **Fosse de Val Claret** : « plus profonde pour que la tête soit sous les
  rails, et un escalier pour remonter au bout ».
  - 1,95 m sous le quai.
  - Escalier de 15 marches côté droit, au bout de la fosse vers la
    cloison, hors de l'axe des butoirs.
  - Poteaux sous les longrines tous les 2,5 m.
- **Chute au retour du poste** : « j'étais au milieu de tout le monde, j'ai
  changé de vue pour aller au poste de pilotage, je suis revenu au skieur
  et je suis tombé sous le tunnel ».
  - Le skieur retrouve sa place dans la voiture, même si elle a roulé
    entre-temps.
  - Les paliers de collision de la voiture ne débordent plus sous la
    caisse.
- **Départ d'en haut** : « en sens descente, le skieur devrait être en haut
  sur la terrasse avec une assiette de frites ». Il y est, à côté d'une
  table, face à son assiette.
- **Klaxon** : « le buzzer à 1:56, tu le récupères à un moment où il n'y a
  pas de bruit de fond et tu t'en sers comme klaxon ».
  - Une seconde du vrai buzzer de la rame (385,6 Hz), prise là où il sonne
    seul, filtrée sur ses harmoniques et bouclée sans raccord
    (`tools_klaxon.py`).
  - Même son sur PC et PWA, au niveau de l'ancien.
- Vérifié :
  - banc du skieur, 12 étapes : AUTO retenu, chute au retour, fosse,
    départ d'en haut ;
  - 15 bancs Godot, 101 tests PC.

**v1.16.0** — le skieur jouable, étape 1 : marcher dans les gares, prendre
le funiculaire, sortir en haut (suivi : SKIEUR.md).
- Kevin : « un skieur capable de monter les escaliers des gares et de
  marcher à l'intérieur sans passer au travers du plancher, des murs, des
  portes ou du wagon, qui peut marcher dans le wagon, voyager dans le
  funiculaire et aller au poste de pilotage ».
- **Bouton SKIEUR** (touche K) : on incarne un skieur, skis à la main.
  - Vue de dos, ou à la 1re personne.
  - Joystick à l'écran ; un doigt glissé ailleurs tourne la vue. Au
    clavier : ZQSD / flèches, Maj pour courir, souris.
  - CONDUIRE près du poste de la rame pilotée ; QUITTER pour revenir à la
    conduite.
  - Le funiculaire tourne en AUTO pendant qu'on marche.
- **Collisions**, construites au premier passage (~170 000 triangles,
  ~0,2 s) :
  - gares : leurs vrais maillages, dont les marches des quais ;
  - rames : collisions simplifiées (parois, paliers, bancs, porte-skis,
    pupitre, seuils de porte), plus un panneau par porte qui suit son
    vantail ;
  - relief : les triangles du bloc, et la pièce fine de 2 m autour des
    gares, sans les bâtiments.
- **Le skieur** monte les marches (40 cm au plus) et glisse le long des
  murs. Dans une voiture, il est emporté avec elle, y compris au
  retournement de la rame en gare. S'il tombe dans un trou, il revient au
  dernier sol sûr.
- **Portes automatiques**, qui s'ouvrent quand on approche :
  - entrée de la gare de Val Claret (les deux baies du milieu) ;
  - baies du mur de tête en haut, vers la terrasse ;
  - **porte de la piste Génépy** : « au bout en bas du quai gauche en
    regardant vers le haut ; tu me montes le terrain jusque-là ». Le mur de
    la salle du quai et le mur sud-est sont percés, un couloir les relie,
    et la neige est remontée au niveau du seuil.
- **Corrections trouvées en marchant** :
  - une paroi de lames de bois courait derrière la façade vitrée de la
    salle d'attente : de l'intérieur, on voyait du bois au lieu des
    vitres ;
  - palier ajouté entre la porte de la cloison et la première marche du
    quai (3 m de vide) ;
  - barre noire en travers des deux ouvertures de la façade de tête,
    retirée.
- Outils :
  - `shot_skieur.gd` : vues du skieur aux endroits clés ;
  - `bench_skieur_3d.gd` : banc à six étapes, de la place de Val Claret à la
    neige de la Génépy.
- À venir (SKIEUR.md) :
  - la neige sur les pistes (OpenStreetMap) et la glisse jusqu'à Val
    Claret ;
  - le fantôme des descentes GPS de Kevin ;
  - la sortie de secours du tunnel.
- Vérifié : 15 bancs Godot, dont le nouveau.

**v1.15.91** — portes de la salle d'attente : le vantail libère tout le
passage.
- Kevin : « c'est un seul vantail qui glisse complètement à gauche pour
  laisser tout le passage, pas que la moitié ; vérifie la vidéo ».
- La v1.15.90 gardait un panneau fixe côté milieu et ne faisait glisser
  que la vitre extérieure. Or, sur la vidéo, les deux vitres sont dans un
  même cadre et partent ensemble.
- Chaque porte est maintenant un seul vantail de toute la baie (2,1 m).
  Il glisse de 2,15 m vers le milieu de la salle, en retrait côté quai,
  derrière le montant et la vitrine.
- Banc du pupitre : passage entièrement libre (course > 2 m), vers le
  milieu, fermé avant le départ.

**v1.15.90** — portes de la salle d'attente de Val Claret : un seul
vantail, qui coulisse vers le milieu.
- Kevin : « les portes de la salle du bas, c'est un seul battant qui
  coulisse vers le milieu de la salle : la porte de droite en regardant
  vers le haut coulisse à gauche, celle du quai gauche à droite », avec la
  vidéo « [FUNI284] Funiculaire Perce-Neige | Tignes (montée) » (chaîne
  Transports câblés, 0:55-0:58).
- Chaque baie garde ses deux panneaux vitrés :
  - le panneau côté milieu est fixe, au nu de la salle ;
  - le vantail côté extérieur, en retrait côté quai, glisse derrière lui
    en ≈ 2 s (1,5 s avant), comme sur la vidéo.
- Avant : deux vantaux par porte qui s'écartaient (supposé).
- L'affichette « PORTES AUTOMATIQUES / AUTOMATIC DOORS » est collée sur le
  vantail mobile de la porte ouest (photo 093500, vidéo) et part avec lui.
- Banc du pupitre : un vantail par porte, chacun vers le milieu, fermé
  avant le départ (`GareAval.course_vantail`). SOURCES.md, ligne 24g.

**v1.15.89** — plus de micro-coupures du son sur iPad ; bancs et paliers
de niveau à quai.
- **« En marche, sur la PWA de l'iPad, le son a des micro-coupures tout le
  temps maintenant »**.
  - Cause : sur l'iPad (Safari), le son est mixé sur le fil principal,
    entre deux images, dans un tampon de 43 ms. Une image plus longue
    vide le tampon et fait un trou.
  - Les versions récentes avaient alourdi chaque image. Mesuré sur la
    PWA réelle (Chromium sur le GPU du NAS, définition iPad, conduite
    d'essai) : 6,46 ms par image en moyenne, contre 5,39 ms en v1.15.78.
  - Deux postes :
    - l'**écran Pro-face** du pupitre, redessiné en entier 30 fois par
      seconde : ~170 appels de dessin à chaque fois ;
    - les **66 pièces du pupitre**, jamais fusionnées : 66 appels par
      image.
  - Correctifs :
    - l'écran est en deux couches. Le fond (cadres, libellés, voyants)
      n'est redessiné que s'il change. Les valeurs (date, heure à la
      seconde, vitesse, distance) se posent par-dessus, jusqu'à 30 fois
      par seconde, en une dizaine d'appels ;
    - les pièces fixes du pupitre sont fusionnées par matériau. Seules
      les commandes (enfoncées, tournées, allumées) et l'écran restent à
      part.
  - En marche : 739 → 579 appels de dessin par image ; 5,28 ms par image
    (p99 8,7 ms au lieu de 10,7).
  - Tampon du son de la PWA porté de 50 à 100 ms
    (`audio/driver/output_latency.web`). Une image lente jusqu'à ~85 ms
    ne coupe plus le son ; le retard ajouté, ~45 ms, est imperceptible.
- **« Tu as incliné les sièges dans le mauvais sens » ; « les bancs sont
  horizontaux lorsque la pente du wagon est celle des gares »** (Kevin).
  - Les paliers étaient construits pour la pente moyenne de la ligne
    (26,5 %). À quai, ils penchaient donc de 10°, l'arrière en l'air.
  - Paliers, bancs et porte-skis sont maintenant de niveau quand la
    voiture est à la pente des gares : 8,57 %, moyenne des 4 voitures
    rame arrêtée (`audit_physique/pente_paliers.sage`, écart à quai
    ≤ 0,73°).
  - En pleine ligne (30 %), l'avant est 11,8° plus haut. Les
    contremarches font 12 cm.
- Outils :
  - `shot_bancs.gd` : vues des bancs depuis un palier, caméra de niveau ;
  - `sonde_couts.gd` : appels de dessin, objets et triangles de chaque
    branche de la scène, masquée à tour de rôle.
- Vérifié : 14 bancs Godot ; performance mesurée sur la PWA exportée.

**v1.15.88** — intérieur des voitures d'après les photos : paliers en
caoutchouc, bancs bleus, porte-skis orange.
- Kevin : « un palier au travers de chaque vitre, recouvert d'un matelas
  noir en caoutchouc ; sur chaque palier deux porte-skis orange, décalés
  d'un palier sur deux ; le long des parois courbes sous les fenêtres, un
  banc bleu clair sauf à la porte », puis « affine la forme des
  porte-skis ». Photos FUNI-334 : « L'intérieur », « Les sièges »,
  « Détail d'un couloir ».
  - **Paliers** : tapis de caoutchouc noir alvéolé, trous ronds en
    quinconce au pas de 4 cm.
  - **Bancs** moulés bleu clair contre la paroi, sous chaque hublot :
    assise à 0,45 m, lèvre avant arrondie, jupe en retrait, dossier
    jusqu'au bas du hublot. Aucun au droit des portes : deux bancs pour
    trois cerceaux de chaque côté, en escalier comme les paliers.
  - **Porte-skis** en tube orange cintré (un maillage balayé par
    porte-skis) :
    - deux arceaux en ∩ à coins arrondis, reliés en haut ;
    - pieds à décrochement en baïonnette vers mi-hauteur, embouts gris ;
    - deux par palier, en quinconce d'un palier sur deux.
  - Les rouges « sièges » génériques et les poteaux du milieu du couloir,
    absents des photos, sont retirés. Les passagers assis sont sur les
    bancs ; au droit des portes, ils sont debout ; personne n'est debout
    dans les porte-skis.
- Plan des cerceaux exposé (`TrainBodyBuilder.KINDS`). SOURCES.md, ligne
  24i.
- Vérifié : 14 bancs Godot (dont la rame), 99 tests PC, parité PWA.

**v1.15.87** — relief 3D juste ; bouche du tunnel en gare amont d'après
les photos.
- **« Normalement il est souterrain tout le temps, donc c'est une
  imprécision de carte ? »** — Non : la carte IGN est juste, c'était
  notre relief 3D (audit_physique/tunnel_amont_relief.sage).
  - Selon l'altitude IGN ponctuelle (RGE ALTI), notre tunnel est
    souterrain partout avant la gare amont : 21 m de roche à s = 3 210 m,
    environ 1 m à s = 3 426 m. Le LiDAR 0,5 m concorde à 2-4 m près.
  - Notre grille de 25 m était en moyenne 10,7 m trop basse le long de
    la fin de ligne, jusqu'à 36 m dans les barres rocheuses. La cause :
    demandé directement à 25 m, le service IGN renvoie un relief GROSSIER
    (17 m d'écart quadratique, 51 m au pire). À 5 m l'écart tombe à
    3,5 m, à 2 m à 0,8 m.
  - `tools_relief3d.py` télécharge maintenant à 4 m, par tuiles, et lit
    la valeur à chaque nœud. Écart le long de la fin de ligne : 1,6 m
    (contre 14,4 m). Au pied de la voie : 2 108,3 m au lieu de 2 114,3 m,
    ce qui colle au LiDAR de la gare aval.
- **Bouche du tunnel en gare amont** (« le mur aval de la gare ferme
  l'entrée du tunnel ») :
  - la salle des quais commence maintenant AU PIGNON aval du bâtiment, par
    un mur droit (`station_high_start` 3 478,82, fondu de 0,5 m en haut
    au lieu de 6 m). Le pignon est percé de la bouche ; la queue de la
    rame arrêtée y arrive, comme sur la photo 095520 ;
  - côté quai, d'après les photos du forum (« un petit zoom sur la sortie
    du tunnel ») :
    - mur bleu nuit, ouverture rectangulaire bordée de cornières
      galvanisées, linteau à l'axe + 1,55 m ;
    - gros caisson en saillie jusqu'au plafond, avec **deux miroirs
      convexes** tournés chacun vers un quai (Kevin : « ce sont des
      miroirs pour surveiller les deux quais ») ;
    - pilier à gauche, portillons blancs au pied des quais, sens
      interdit à droite.
- **« Enlève le tas de neige côté est du bâtiment »** : le relèvement du
  terrain ne couvre plus que le tunnel, avant le pignon, avec un raccord
  de 4 m. La façade sud-est est dégagée.
- **Gare aval** : la dalle de la place, qui dépassait du terrain corrigé,
  est retirée : la place est le terrain aplani. Les portes coulissantes de
  la salle d'attente se ferment avant le départ et s'ouvrent après
  l'arrivée : banc sur une vraie séquence (fermées 21 s avant la
  traction).
- Vérifié : 14 bancs Godot, 99 tests PC, parité PWA.

**v1.15.86** — le relief ne traverse plus les gares ; gare amont (Grande
Motte) refaite d'après le réel.
- **« Le relief rentre dans le bâtiment et les quais »** : le relief IGN
  maillé à 25 m traversait le hall de Val Claret et la salle des quais.
  Celle-ci n'avait que 0,3 à 0,9 m de terre au-dessus d'elle, et
  dépassait même de 3,4 m plus haut.
  - Autour de chaque gare, une pièce de terrain plus fine (maille de 2 m)
    remplace le bloc. Elle s'y raccorde sans marche sur les mêmes
    triangles, et :
    - retire le terrain dans les bâtiments (masque à 25 cm) ;
    - aplanit la place, l'escalier et l'auvent en bas ;
    - rase le terrain sous la terrasse en haut ;
    - recouvre les quais souterrains d'au moins 1,2 m.
  - Les marches de l'escalier aval sont pleines jusqu'à la place.
- **Gare amont** (« maintenant tu fais pareil pour le haut ») : nouveau
  `GareAmont` (scripts/gare_amont.gd) pour l'extérieur, d'après l'IGN
  (BD TOPO, LiDAR HD, orthophoto), les photos de Kevin, le reportage du
  forum (2017) et Wikimedia Commons (2023) :
  - **hall des quais** de 14 × 44,5 m dans l'axe de la voie, toit
    monopente blanc :
    - côté sud-est : socle béton, tôle nervurée blanche, bande de baies
      bleues ;
    - pignon aval à deux fenêtres bleues ;
  - **façade de tête** (état 2017, seul photographié) :
    - bardage bois en deux registres ;
    - enseignes « TIGNES », « ALT 3032 M », « FUNICULAIRE / Glacier de la
      Grande Motte » ;
    - porte « DESCENTE », mur en pierre, sortie entre deux sens
      interdits, fenêtre bleue d'angle ;
  - **terrasse** sur pilotis au niveau du palier : caillebotis, garde-corps
    noir, tables, transats, porte-skis, parasols ;
  - **restaurant Le Panoramic** (chalet de bois brun, toits gris) et
    annexes bleu nuit ;
  - **gare aval du téléphérique de la Grande Motte**, à 107 m : bardage
    gris, étage vitré, socle en pierre, « TELEPHERIQUE DE LA GRANDE
    MOTTE », « GRANDE MOTTE » ;
  - éclairage « plein jour » propre à ces matériaux (le jeu n'a pas de
    soleil). Un maillage par matériau.
- **Mur de tête du hall**, d'après les photos du 26/04/2026 :
  - lames de bois ;
  - **deux baies vitrées symétriques** sur la terrasse ;
  - **kiosque à écran** (FUNICULAIRE · TP DE GRANDE MOTTE · TSD DE LA
    VANOISE · TSD DES LANCHES) ;
  - bandeau rouge « ALTITUDE EXPERIENCES ... » ;
  - lettres rétroéclairées « DESTINATION / GLACIER » ;
  - plafond sombre à spots, 5 m au-dessus du palier. Il remplace la
    verrière et le mur entièrement vitré du 06/10, que les photos ne
    montrent pas. Le tablier de neige est remplacé par la terrasse.
- Relevé : SOURCES.md, ligne 24h. Signalé, non corrigé : entre s =
  3 260 et 3 440 m, le relief IGN passe jusqu'à 19 m sous le tunnel du jeu.
- Vérifié :
  - `bench_relief_3d` : quais recouverts en bas et en haut, couverture
    minimale 1,16 m ; terrain retiré dans les deux halls ;
  - 14 bancs Godot, 99 tests PC, parité PWA ;
  - rendus Vulkan et Compatibility.

**v1.15.85** — gare aval (Val Claret) refaite d'après le réel.
- « Refais complètement le design extérieur de la gare aval, à l'aide des
  vidéos, des photos, du forum, de Google Earth… et modélise la salle
  d'attente et les portes coulissantes vers le quai » :
  - nouveau `GareAval` (scripts/gare_aval.gd), qui remplace le hall en béton
    générique et sa cage d'escalier vers la surface ;
  - état d'après le réaménagement de 2018 (ICM Architectures), relevé sur
    l'IGN (BD TOPO, LiDAR HD, orthophoto 2024), les photos de Kevin du
    26/04/2026 et celles de l'architecte.
- **Extérieur** :
  - bâtiment semi-enterré à toit en herbe, emprise et hauteur IGN ;
  - façade en lames de bois « DESTINATION GLACIER », avec le bandeau rouge
    « ECOLES DE SKI / ALTITUDE EXPERIENCES... / SORTIE » ;
  - auvent sur deux poteaux, escalier métallique depuis la place, avec
    garde-corps galvanisés en 5 files ;
  - **arches** (Kevin : « rondes, pas ovales, un grand diamètre devant et
    un plus petit derrière, alignées côté droit en regardant dans le sens
    de la montée ») :
    - la rouge et 3 en lamellé-collé, en **cercles** de rayon 7,76 m
      (LiDAR : sommet à 2119,75 m, 12,8 m entre les pieds) ;
    - 3 plus petites derrière (rayon 6,2 m) ;
    - toutes tangentes à la même ligne côté droit, reliées par des pannes
      noires.
- **Salle d'attente** : plafond « origami » à facettes et LED, colonnes en
  bois avec anneau lumineux, suspensions en étoile, murs en lames de bois,
  sol bleu nuit, bancs, porte-skis, 3 écrans, comptoir, quelques skieurs.
- **Cloison vers le quai** (photos 093457 à 093500) :
  - menuiseries bleu marine ;
  - **2 portes coulissantes automatiques à 2 vantaux**, au pied de chaque
    quai. Elles s'ouvrent pendant l'embarquement en gare aval et se
    referment au départ ;
  - vitrine centrale face à la fosse, enrouleur incendie rouge, bandeau
    « ALTITUDE EXPERIENCES... » et vitrage haut ;
  - **panneau des départs vivant** : date et heure locales, FR / EN en
    alternance, prochain départ ;
  - balustrade courbe en lames de bois, affichette « PORTES
    AUTOMATIQUES… », « 2 » sur le montant droit.
- Fusionnée par matériau : 548 objets → 53 appels de dessin ; éclairée sur
  la PWA comme les autres gares.
- Vérifié :
  - `bench_pupitre_3d` : 4 vantaux, ouverts à l'embarquement puis fermés
    au départ ; panneau renseigné ;
  - 14 bancs Godot, 99 tests PC, parité PWA ;
  - rendus Vulkan et Compatibility.

**v1.15.84** — l'écran du pupitre et l'horloge de la cabine à l'heure
locale de l'appareil.
- « Affiche la vraie date et heure que tu récupères du PC, de l'iPad ou
  du téléphone, au lieu d'un truc figé » : dans le navigateur, l'heure
  « système » de Godot est en UTC, d'où 2 h de retard en été.
  - `PNConstants.heure_locale()` lit le décalage du fuseau dans le
    navigateur, relu chaque minute pour suivre le passage à l'heure
    d'hiver ; sur PC, c'est l'heure locale du système.
  - L'écran Pro-face affiche la date et l'heure à la seconde ; la
    tablette-horloge du montant gauche suit aussi.

**v1.15.83** — plus aucune silhouette jaune sur les rames.
- « Enlève complètement cette silhouette jaune partout, ça laisse des
  traces » : la silhouette des rames est supprimée en vue extérieure. Le
  tunnel reste visible à travers le relief grâce à son trait ambre.
- Vérifié : `bench_relief_3d` (aucun recouvrement sur les rames), 14 bancs
  Godot, 99 tests PC, parité PWA.

**v1.15.82** — rames vues à travers le relief seulement là où il les
cache ; écran du pupitre agrandi et fluide.
- **« En vue externe, la rame est devenue toute jaune »** : la silhouette
  jaune était dessinée par-dessus toute la coque, même à découvert.
  - Elle compare maintenant sa profondeur à celle de la scène, en Vulkan
    comme en Compatibility.
  - Elle n'apparaît que sur les parties cachées par le relief ; à
    découvert, la rame garde ses couleurs.
- **Écran Pro-face** (« agrandis-le pour qu'il prenne quasi tout l'espace
  noir, et augmente la fréquence de rafraîchissement ») :
  - dalle de 0,272 × 0,161 m au lieu de 0,17 × 0,10, au rapport de
    l'écran ;
  - rendu à deux fois sa résolution, pour rester net ;
  - rafraîchi 30 fois par seconde au lieu de 4.
- Vérifié : 14 bancs Godot, 99 tests PC, parité PWA ; rendus Vulkan et
  Compatibility.

**v1.15.81** — inversion en gare silencieuse ; vue extérieure sans zone
marron ; gares éclairées sur la PWA ; titres du pupitre dans la plaque.
- **Inversion du sens** (« quand j'inverse en gare après un trajet normal,
  j'ai l'annonce anormale ») : l'annonce « retour en gare » ne part plus
  qu'en plein tunnel. Comme sur le PC, le demi-tour à quai est silencieux
  et coupe l'annonce en cours.
- **Vue extérieure** (« la zone marron qui entoure le trajet, c'est moche ;
  on ne voit pas les sommets à côté et au-dessus ») :
  - le relief redevient **opaque** partout : les sommets se voient ;
  - c'est le tunnel qui se dessine à travers la montagne. Le trait ambre
    a deux passes : plein à découvert, 45 % à travers le relief. Il est
    interrompu à la place des rames et fin, même de près ;
  - **les deux rames se voient à travers le relief**, en silhouette
    jaune translucide ;
  - caméra toujours libre sous la voie ; sous la montagne, le vide est
    gris roche.
- **« Il fait toujours nuit dans la gare du haut »** (PWA) :
  - le ciel du rendu Compatibility sortait NOIR, à travers la verrière et
    les baies. Un ciel procédural le remplace partout sur la PWA ;
    l'ambiante reste à son niveau d'avant, donc le tunnel ne change pas ;
  - les néons des gares sont 2,5 fois plus forts sur le web.
    L'intérieur de la cabine passe sur sa propre couche de rendu, que ces
    néons n'éclairent pas : le pupitre n'est plus surexposé ;
  - mesures sans phares : hall du haut 36 → 67, gare du bas 75 ;
    pupitre 118.
- **Pupitre** : titres PORTES 1 à 6, PORTES 7 à 12 et ÉCLAIRAGE
  redescendus dans la plaque (« ils sont dehors »). Les rangées sont
  resserrées et la plaque gagne 5 mm.
- **PWA** : le numéro de version s'affiche dans le titre en haut à gauche,
  pour savoir quelle version tourne.
- Vérifié :
  - `bench_pupitre_3d` : inversion à quai silencieuse, annoncée en
    tunnel ;
  - `bench_relief_3d` : trait « rayons X », silhouettes des deux rames ;
  - 14 bancs Godot, 99 tests PC, parité PWA ;
  - rendus Vulkan et Compatibility.

**v1.15.80** — vue extérieure en « rayons X » ; pupitre couché et
complet ; instruments dans la colonne de droite ; gares éclairées sur la
PWA.
- **Vue extérieure** (« au lieu d'un éclaté, diminue l'opacité du sol
  autour du tunnel pour le voir au travers de la montagne et en entier ;
  et je n'arrive plus à passer sous la voie ») :
  - l'écorché est remplacé par un **couloir translucide**. Le sol est à
    25 % d'opacité jusqu'à 120 m de l'axe du tunnel, en plan, et
    redevient opaque à 450 m ;
  - deux passes : opaque hors du couloir, translucide et sans profondeur
    dedans. Le tunnel, les rames et les gares se voient à travers ;
  - le **tunnel entier** est tracé d'un trait ambre, d'un bout à l'autre.
    Sa largeur est constante à l'écran ; il s'efface près de la caméra,
    où l'on voit le vrai tube ;
  - **la caméra passe sous la voie** (site jusqu'à −1,2 rad) et sous la
    montagne :
    - le dessous du relief s'affiche assombri ;
    - sous l'horizon, le « ciel » prend la couleur de la roche ;
    - les flancs du bloc de relief ne se voient plus de l'intérieur ;
  - PWA : le ciel physique sortait noir en rendu Compatibility. En vue
    extérieure, un ciel procédural (dégradé bleu, roche sous l'horizon)
    le remplace.
- **Pupitre** :
  - « trop étiré en hauteur, abaisse la limite haute » : face couchée à
    28° (au lieu de perpendiculaire au regard), plus basse, recentrée.
    Proportions proches du vrai, voie dégagée ;
  - **PORTES 1 à 6 = côté gauche en regardant vers le haut, 7 à 12 =
    côté droit** :
    - chaque groupe n'ouvre et ne ferme que son côté, dans les deux sens
      de marche ;
    - le dernier côté fermé lance la vraie séquence (annonce, buzzer,
      clip) ;
    - l'arrivée en gare et le bouton PORTES ouvrent les deux ;
  - **coups-de-poing** : le gros à gauche = URGENCE, le petit à droite =
    ARRÊT ÉLEC. Ils restent enfoncés tant que l'arrêt dure, et un nouvel
    appui les relâche ;
  - **arrêt électrique** dans la PWA (port de `electric_stop` du PC) :
    consigne ramenée à 0 sur la rampe régénérative de 0,45 m/s² (de
    12 m/s : arrêt doux en 27 s, sans frein de voie), départ refusé tant
    qu'il est engagé.
- **Interface PWA** (« la planche de commande est masquée par le bandeau
  du bas ; déplace-le à droite, vire ÉTATS ») :
  - les instruments passent dans la colonne de droite, sous la salle des
    machines : vitesse + E-STOP + puissance, tension câble, consigne,
    profil de ligne ;
  - le panneau ÉTATS est supprimé ;
  - le profil ne dépasse plus 0,65 × sa largeur (« trop vertical, trop
    déformé » sur iPad) ;
  - sur un écran de 900 de haut, tout est réduit d'un même facteur ;
  - PORTES et PRÊT/DÉPART descendent dans la colonne de gauche : au
    centre, ils masquaient l'écran du pupitre.
- **Gares dans le noir sur la PWA** (iPad, phares éteints) : le rendu
  Compatibility n'a ni éclairage indirect ni plus de 8 lampes par objet.
  - Les matériaux des gares reçoivent une luminosité propre (0,4 × leur
    couleur), qui n'éclaire pas la cabine.
  - Les néons des quais et du hall sont doublés.
  - Une lumière ambiante plus forte s'applique quand la caméra cabine est
    en gare.
  - Hall du haut : luminosité moyenne 36 → 56 ; gare du bas : 68.
- Vérifié :
  - `bench_pupitre_3d` : portes par côté, rame montante et descendante ;
    coups-de-poing ; arrêt électrique en ligne ; départ refusé ;
  - `bench_relief_3d` : sol translucide à l'aplomb du tunnel de bout en
    bout, opaque à 2 km ; trait du tunnel complet ; caméra sous la voie ;
  - 14 bancs Godot, 99 tests PC, parité PWA ;
  - rendus Vulkan et Compatibility, en 4:3 et 16:9.

**v1.15.79** — vue extérieure refondue en écorché de la montagne ; pupitre
redressé face au regard, commandes actionnables.
- **Vue extérieure** (« 3 m après le départ du bas, ça passe à la vue
  panoramique du haut, statique, en lévitation totale ; faut tout
  refondre ») :
  - la cause : le relief n'était affiché que si la caméra était
    au-dessus de la surface. En orbite rapprochée, elle est presque
    toujours sous la montagne ; il ne restait alors que la photo
    panoramique de la gare du haut, posée à 10 km ;
  - le relief est maintenant **toujours** affiché, et **jusqu'à
    l'horizon** :
    - bloc IGN détaillé (25 m) ;
    - anneau lointain de 44 × 44 km à 200 m (Terrain Tiles, orthophoto
      IGN, rotondité de la Terre), avec une brume de distance ;
    - plus aucune photo panoramique en vue extérieure ; le ciel reste
      bleu et allumé, même tunnel éteint ;
  - **écorché** : du côté de la caméra, la montagne est ouverte dans un
    demi-disque centré sur la rame, jusqu'au niveau du tunnel :
    - le fond suit le profil de la voie, juste sous le tube ;
    - les parois montrent la roche à strates, l'épaisseur de montagne
      au-dessus du tunnel jusqu'au liseré clair de la surface, et l'entrée
      du tunnel dans la roche, un trou bordé de béton ;
    - l'entaille a juste la taille qu'il faut pour que la visée
      caméra → rame ne traverse jamais la montagne : elle grandit tout de
      suite et rapetisse en douceur ;
    - la caméra ne descend jamais sous son fond ; en très grand recul,
      elle reste au-dessus du relief ;
  - le tracé orange en surface est posé sur les triangles du relief
    (il flottait 8 m au-dessus).
- **Pupitre** :
  - « incline ce panneau perpendiculaire à la ligne du regard » : la face
    est tournée vers l'œil du conducteur (≈ 62°) ;
  - « descends-le sur le truc blanc, ça masque la vue de la voie » : elle
    est posée devant le tube, plus bas. La voie reste dégagée ;
  - « faudrait pouvoir appuyer sur ces boutons » : au clic ou au doigt,
    en vue cabine. Les boutons de l'écran passent avant :
    - OUVERTURE et FERMETURE commandent les portes ;
    - **MONTÉE** (le bouton noir, réponse de Kevin) lance le départ ; le
      voyant **PRÊT** s'allume alors, et ce n'est plus un bouton ;
    - **−VITE / +VITE** : sélecteur à rappel, vertical au repos ; tenu à
      gauche ou à droite, il baisse ou monte la consigne de vitesse ;
    - **EN MARCHE** : commutateur général à clé. Sur arrêt, le pupitre
      s'éteint et le départ est refusé ; il est impossible de le couper
      rame en marche ;
    - KLAXON sonne tant qu'on le tient (même son que le PC) ;
    - CABINE et COMPARTIMENT allument ou éteignent la cabine ;
    - un appui sur l'écran change de page ;
  - **coups-de-poing rouges** à gauche de l'écran, d'après la photo
    095119 : plaque grise, un poussoir clair et deux coups-de-poing dans
    un cadre, une clé à étiquette rouge. Les anciens, sur le tube, sont
    supprimés. Leur fonction n'est pas encore connue : ils s'enfoncent
    seulement ;
  - embarqué dans le PC, le pupitre ne fait que le geste, car le PC
    pilote la rame.
- Vérifié :
  - nouveaux bancs `bench_pupitre_3d` (face à 0,0° du regard ; 16
    commandes et l'écran trouvés au clic là où on les voit ; actions) et
    `bench_relief_3d` (6 positions × 5 cadrages : visée toujours dégagée,
    relief affiché, fond sous le tube) ;
  - 14 bancs Godot, 99 tests PC, parité PWA ;
  - rendus Vulkan et Compatibility (web).

**v1.15.78** — pupitre de conduite reproduit d'après les photos, écran
Pro-face vivant.
- **« Le poste de conduite avec les commandes, les boutons et l'écran
  fidèles »** : le pupitre de la cabine 3D (PWA et vue 3D du PC) est
  refait d'après les photos de Kevin du 26/04/2026 (094300, 094305,
  094308, 094402) et la vidéo de descente de 2013.
  - Caisson gris sur le tube transversal. À gauche, l'écran tactile
    Pro-face sur son cadre noir ; à droite, la plaque à boutons disposée
    comme sur la photo :
    - PORTES 1 à 6 et PORTES 7 à 12, chacune avec OUVERTURE et FERMETURE ;
    - PRÊT, un bouton noir, un sélecteur, un commutateur à clé ;
    - KLAXON, et le groupe ÉCLAIRAGE : sélecteur CABINE 0/1, COMPARTIMENT,
      SECOURS.
  - Les libellés du bouton noir, du sélecteur et du commutateur à clé de
    la deuxième rangée sont illisibles sur les photos. Ils sont laissés
    sans texte plutôt qu'inventés.
  - Voyants et commandes suivent l'état réel de la rame :
    - FERMETURE vert, portes fermées ; OUVERTURE blanc, portes ouvertes ;
    - PRÊT vert, rame prête ;
    - COMPARTIMENT allumé avec l'éclairage de la cabine, et le sélecteur
      CABINE sur 0 ou 1 ;
    - SECOURS toujours allumé ;
    - KLAXON enfoncé pendant le klaxon (PC).
  - **L'écran est vivant**, rafraîchi 4 fois par seconde, dessiné seulement
    en vue cabine :
    - en-tête : date et heure réelles, voyants ARRÊT FREIN DE SERVICE,
      ARRÊT ÉLEC. et Alarmes ;
    - en marche, la page « CONDUITE VÉHICULE n » : PRÊT MOTRICE, PRÊT
      VÉHICULE n, TEST EN COURS, MARCHE, AUTORISATION OUVERTURE PORTES,
      PUPITRE AVANT ; FREIN DE VOIE LEVÉ, RALENTISSEUR LEVÉ, PORTES
      FERMÉES, PORTES SECOURS FERMÉES, VITESSE RÉDUITE ;
    - à l'arrêt en gare, la page « VOITURE AVAL », avec les six portes de
      la voiture (vert fermées, rouge ouvertes) ;
    - en bas : VITESSE VÉHICULE au centième, DISTANCE, et DÉFAUTS (rouge
      en cas de panne).
  - Le PC transmet maintenant à la 3D le klaxon, l'arrêt électrique, l'état
    « prêt » des deux rames et les freins, pour l'écran et les voyants.
- Vérifié : 99 tests PC, 12 bancs PWA, parité PC/PWA OK, rendus Vulkan et
  web.

**v1.15.77** — relief 3D réel du massif en vue extérieure, graphismes plus
économes.
- **« Prolonger le paysage 3D jusqu'au tunnel et jusqu'en bas, jusqu'au lac
  de Tignes, et dans le rayon autour »** (vue extérieure de la PWA) :
  - le massif réel est modélisé en 3D, sur 8,6 × 10,2 km, du sommet de la
    Grande Motte au lac du Chevril. Le relief vient de l'IGN (RGE ALTI),
    la texture de l'orthophotographie IGN (`tools_relief3d.py`) ;
  - lacs, villages et sommets portent leur nom (OpenStreetMap) ;
  - le tracé du tunnel est dessiné en surface (ruban orange) ;
  - autour de la rame, la montagne s'ouvre comme une maquette découpée. Le
    puits grandit avec le recul de la caméra : on y voit la rame dans son
    tube, et le tunnel à sa vraie profondeur ;
  - la caméra extérieure recule jusqu'à 6 km, et le brouillard du tunnel
    s'efface avec le recul. Au-delà de 10 km, le panorama des montagnes
    lointaines prend le relais ;
  - en orbite rapprochée, la caméra est sous la montagne : la vue
    habituelle du tunnel est inchangée.
- **Optimisation selon la machine** (« un beau truc qui ne consomme pas
  énormément de ressources ») :
  - 3D : le relief est construit en tâche de fond. Sur PC, il est préparé
    dans un fil parallèle ; dans la PWA (sans fils), par tranches de 3 ms
    par image. Il ne coûte plus que 8 ms au démarrage, contre 216.
  - Sa finesse suit la machine détectée : maille de 25 m et orthophoto de
    2 048 px pour une bonne carte graphique ; maille de 50 m (quatre fois
    moins de triangles) et 1 024 px sur iPad, carte intégrée modeste ou
    rendu logiciel. Le panorama de la gare amont passe aussi à
    demi-résolution sur ces machines (25 → 6 Mo de mémoire graphique).
  - Version autonome : quand la fenêtre est réduite, la 3D tombe à
    5 images/s ; en arrière-plan, à 20. Le réglage automatique de qualité
    suspend alors ses mesures, pour ne pas baisser la qualité à tort.
  - PC, vue en coupe : le décor (crêtes, massif, neige, glacier, tunnel,
    gare aval, bornes) est rendu une fois dans une image en cache, avec
    30 % de marge autour de la vue. Il n'est refait que quand la caméra en
    sort, environ toutes les 20 s à 12 m/s. Le ciel a aussi son image en
    cache. Temps de dessin par image : 12,4 → 6,2 ms au zoom normal,
    13,5 → 7,1 ms au zoom large. L'image est identique.
- Corrigé : la fenêtre « Signaler un problème » du PC plantait à
  l'ouverture (`QCheckBox` non importé).
- Vérifié : 99 tests PC, 12 bancs PWA, parité PC/PWA OK, rendus Vulkan et
  web aux deux finesses.

**v1.15.76** — roues de la machinerie lisibles à toute vitesse, pylône du
téléphérique mesuré sur photo.
- **« Les roues ne tournent pas à la bonne vitesse en fonction de la
  vitesse, et pas dans le bon sens »** (vue en coupe du PC) : c'était un
  effet stroboscopique. À 12 m/s, une roue de 4,16 m tourne de 11 à 17°
  entre deux images de la vue. Ses 12 ouvertures sont espacées de 30° :
  dès que le pas dépasse 15°, l'œil les voit tourner lentement à
  l'envers. Corrections :
  - chaque roue porte un repère rouge unique ;
  - quand elle tourne de plus de 6° entre deux images, les ouvertures se
    fondent en un voile et le repère laisse une traînée ;
  - les deux brins de la voie sont dessinés et défilent en sens
    contraires. Le brin de la rame 1 entre au sommet de la roue aval ;
    celui de la rame 2 passe au-dessus d'elle sur ses galets et rejoint la
    roue amont. Le brin de la rame qui monte entre toujours dans la gare.
- **Pylône du téléphérique** : le reportage remontees-mecaniques
  confirme que le survol de 152 m est « sur la partie située en aval du
  pylône », sans donner la hauteur du pylône.
  - Mesuré sur une de ses photos, où une cabine passe juste à côté
    (caisse ≈ 3 m), le pylône fait environ 30 m, et non 61.
  - Avec le survol de 152 m, la tension des porteurs est d'environ 52 t
    (porteur de 13 kg/m, estimé). La pente du câble à vide atteint 45 %.
  - Cabine pleine au ras du pylône, la pente monte à 57-62 % : c'est le
    « 55 % » de la fiche (`audit_physique/telepherique.sage`).
  - La tête du pylône est dessinée en longue poutre inclinée, comme sur la
    photo.
- Vérifié : 99 tests PC.

**v1.15.75** — téléphérique de la Grande Motte, axes lisibles, roues
animées ; salle des machines : phares et tunnel qui s'allument à
l'approche.
- **Vue salle des machines (PWA) : « je ne vois plus rien »**. Sa caméra
  par défaut se retrouvait enfermée dans les marches et le palier ajoutés
  au hall en 1.15.67. Ils comptent maintenant comme des obstacles.
- **« De la machinerie, j'attendais la rame qui arrive, quelle qu'elle
  soit, et je voyais le faisceau des phares éclairer progressivement les
  parois du tunnel »** : la rame d'en face a désormais ses phares. Ils
  suivent le même interrupteur (touche H) et éclairent le tunnel en
  approchant.
- **« Le tunnel vu de la machinerie, s'il est allumé, ne s'allume que
  progressivement à l'approche de la rame »** : les néons ne s'allument
  que dans une zone de 300 m autour des rames, tube après tube, à mesure
  qu'elles avancent. Avant, tous les tubes restaient allumés de bout en
  bout. En web, en vue salle des machines, l'éclairage suit la rame qui
  approche de la gare, pilotée ou non.
- **« On n'arrive pas à comprendre la légende et les axes entre la
  distance parcourue et l'altitude »** (vue en coupe du PC) :
  - les altitudes passent dans une bande d'axe à gauche (« ALTITUDE ») ;
  - la distance parcourue est donnée par des bornes kilométriques jaunes
    posées sur la voie, au compteur du pupitre : « km 0 » au départ de
    Val Claret, « km 3,474 » à l'arrivée ;
  - une légende rappelle les deux.
- **« Animer de manière réaliste les roues en haut de la machinerie, en
  transposant le schéma fonctionnel »** : sous la gare amont, la salle des
  machines montre les deux roues alignées le long de la voie, jante rouge
  et voile jaune à douze ouvertures. Elles tournent à la vitesse de la
  poulie en sens contraires, avec le câble en huit et des repères qui
  défilent sur le brin.
- **« Le haut de la gare supérieure est à l'extérieur »** : la correction
  de +10 m du relief et la couverture forcée autour de la gare amont sont
  retirées. Le terrain IGN y est à 3 028 m pour un rail à 3 032 m, et le
  hall et la verrière sortent du glacier.
- **Téléphérique de la Grande Motte, « qui part dans la foulée du funi »**
  (bicâble à va-et-vient Von Roll 1975, 115 + 1 places, fiche
  remontees-mecaniques.net) :
  - la coupe suit maintenant sa ligne (OpenStreetMap), puis le sommet ;
  - gare aval à 3 034 m contre la sortie du funiculaire, gare amont à
    3 456 m sur l'arête, un pylône en treillis ;
  - porteurs en chaînette (cosh) et deux cabines qui se croisent (5 min de
    trajet, 1 min en gare) ;
  - la hauteur du pylône et la tension ne sont pas publiées. Elles sont
    déduites des deux chiffres de la fiche (survol maximal 152 m, pente
    maximale 55 %) sur le relief IGN : pylône d'environ 61 m, tension
    d'environ 37 t pour un porteur de 50 mm. La longueur développée
    calculée est de 1 721 m pour 1 696 m annoncés
    (`audit_physique/telepherique.sage`).
- Vérifié : 99 tests PC, 12 bancs PWA, parité PC/PWA OK, rendus Vulkan et
  web.

**v1.15.74** — rames de la vue en coupe affinées, relief IGN, vitesse au
centième.
- **« Deux chiffres après la virgule dans l'affichage digital de la
  vitesse »** : le cadran du pupitre affiche 10,37 m/s au lieu de 10,4,
  sur PC et dans la PWA.
- **« Tu peux vraiment affiner le design des rames dans la vue en
  coupe »** : rames redessinées d'après le modèle 3D. Caisse gris argent
  avec reflet de toit et joints entre les baies, bande de bas de caisse,
  nez jaunes à pare-brise ovale, hublots ovales à cadre sombre, trois
  portes vitrées par voiture, soufflet d'intercirculation, culot d'attache
  du câble, bogies cachés derrière le tube comme en vrai. On voit les
  passagers (habits, visages, bonnets) derrière les vitres selon la
  charge. La rame fait au moins 160 px de long à l'écran.
- **« C'est bizarre que dans la partie supérieure le relief au-dessus du
  tunnel soit si plat et si près »** : c'est bien réel. Vérifié sur le
  relief au mètre de l'IGN (RGE ALTI), il y a 150 à 190 m de roche
  au-dessus de la voie entre 870 et 1 750 m, mais seulement 17 à 70 m sur
  le dernier tiers. Le haut de la ligne passe sous la pente régulière du
  glacier, presque parallèle à la voie, et la gare amont débouche à son
  niveau (3 028 m). Vers 2 105 m il ne reste qu'une vingtaine de mètres :
  c'est là qu'est la sortie de secours.
- La coupe utilise maintenant le relief IGN RGE ALTI (service
  d'altimétrie de la Géoplateforme). Les tuiles SRTM/EU-DEM étaient
  lissées de ~10 m en moyenne, jusqu'à 59 m par endroits. L'épaisseur de
  roche au-dessus de la rame s'affiche en haut à droite de la vue.
- Vérifié : 99 tests PC.

**v1.15.73** — calage sur la vidéo de descente, tunnel débouché sous la gare
amont.
- **« Entre les galets 213 et 214 tu as mis un truc qui ferme le tunnel »**
  : c'était le dôme du panorama, une sphère de 400 m de rayon autour de la
  gare amont. Le tunnel qui descend la traverse justement là, et elle
  formait un disque en travers du tube. Le dôme est maintenant ouvert au
  passage du tunnel. En vue cabine, il n'est affiché qu'à moins de 450 m
  de la gare.
- **Calage sur la descente en cabine** (vidéo « Transports câblés » de
  2013, 12 m/s), demandé par Kevin
  (`tools_calage_descente.py`, `audit_physique/calage_descente.sage`) :
  - **néons** : en croisière, un néon allumé passe toutes les 1,630 s, à
    0,026 s près sur 56 intervalles. Ils sont donc allumés tous les 20 m :
    un tube tous les 10 m, un sur deux allumé, au lieu de 12 m (PWA, vue
    cabine et vue en coupe du PC) ;
  - **accélération au départ** : 0,296 m/s², mesurée sur le resserrement
    des néons de 6 à 11,7 m/s. Le simulateur utilise 0,30 : confirmé ;
  - **section carrée sous la gare amont** : avec ce départ, la cabine entre
    dans le tube rond 34 à 42 m sous son point de départ. Le tube rond
    s'arrête donc vers 3 443 m, et un caisson carré d'une trentaine de
    mètres le relie à la salle de gare (avant, le tube allait jusqu'à la
    salle) ;
  - **approche du bas**, lue sur l'écran du pupitre : environ 0,64 m/s de
    moyenne, la vitesse véhicule oscillant de 0,05 à 1,56 m/s avec une
    période d'environ 7 s (élasticité de 3,45 km de câble). Gardé pour
    plus tard.
- L'écran du pupitre est identifié (terminal Pro-face « CONDUITE VÉHICULE
  1 ») : il servira à la reproduction du pupitre.
- Vérifié : 99 tests PC, 12 bancs PWA, parité PC/PWA OK.

**v1.15.72** — correctif : la 1.15.71 ne démarrait plus sur PC.
- **« La version 71 après mise à jour sur PC, ça ne démarre plus, rien ne
  se passe »** : la nouvelle vue en coupe lit le relief dans un nouveau
  module, `profil_coupe.py`. Il manquait dans la liste des fichiers du
  paquet Windows (`kit.json`, « modules »). L'import échouait dès le
  lancement, sans aucun message, puisque l'application n'a pas de console.
- Le module est ajouté au paquet. L'import est désormais facultatif :
  sans les données, la vue profil dessine un relief simplifié au lieu
  d'empêcher le démarrage.
- **Garde-fous** : la CI importe maintenant le programme principal dans le
  paquet construit (`verification_import`, qui était vide). Un nouveau test,
  `tests/test_paquet.py`, vérifie que tout module local importé figure bien
  dans le kit.
- Une 1.15.71 installée ne démarre pas, donc ne peut pas se mettre à jour
  seule : il faut réinstaller une fois à la main.
- Vérifié : 99 tests PC (+2).

**v1.15.71** — vue profil du PC refaite : une vraie coupe du terrain.
- **« Dans cette vue-là on peut redesigner complètement les rames et le
  reste »**. Avant, les montagnes étaient des sinusoïdes, le dessus du
  relief une ligne à 160 m au-dessus de la voie, il y avait des sapins
  (Val Claret est au-dessus de la limite des arbres) et les rames étaient
  deux tonneaux jaunes grossis.
- **Relief réel** : le terrain au-dessus de la ligne est tiré du modèle
  numérique de terrain le long du tracé IGN. Il se prolonge vers le lac en
  aval, et en amont par le glacier jusqu'au sommet de la Grande Motte.
  L'outil `tools_profil_coupe.py` génère `profil_coupe.py`. Le modèle lisse
  le glacier d'environ 20 m : il est recalé sur l'altitude de la gare
  amont.
- **Crêtes de fond réelles**, voilées par l'atmosphère et blanchies avec
  l'altitude : la vue regarde vers l'est, l'amont étant à droite. Pour
  chaque point, c'est l'altitude maximale sur une bande de 0,8 à 4 km,
  puis de 4 à 18 km.
- **Coupe du massif** : roche à strates, manteau neigeux, glace bleutée du
  glacier avec ses crevasses. L'échelle est isotrope : la pente apparente
  est la vraie.
- **Tunnel** à ses cotes (Ø 3,9 m, rail à 1,24 m sous l'axe), avec la
  chambre de l'évitement, les néons (un sur deux) et la voie.
- **Sortie de secours** au galet 145 : la galerie monte jusqu'à la surface
  et débouche au bord de la piste rouge (fait de Kevin). C'est là que le
  tube passe le plus près de la surface.
- **Gares** : Val Claret (hall béton, bandeau « ALTITUDE EXPERIENCE »,
  quai) et Grande Motte (hall bleu nuit, verrière qui sort sur le glacier,
  les deux roues jaunes de la salle des machines, butoirs bleus).
- **Rames aux vraies proportions** : deux voitures de 15,8 m, caisse
  Ø 3,6 m qui remplit le tube. Carrosserie argent, nez jaunes avec
  pare-brise, grandes baies où l'on voit les passagers selon la charge,
  trois portes par voiture (noires et voyant vert ouvertes, ambre en
  mouvement), bogies, phares avec leur faisceau. Quand le zoom les rendrait
  illisibles, rames, tube et gares sont grossis sans déformation. Les
  câbles partent du milieu de la voiture amont et montent jusqu'à la
  poulie.
- Le dessin de la vue prend environ 9 ms par image sur le NAS (6 ms avant).
- Vérifié : 97 tests PC.

**v1.15.70** — annonce d'arrivée entière, pente continue, paysage dans
toutes les vues.
- **« L'annonce d'arrivée en haut se déclenche trop tard et est coupée par
  l'arrêt »** : elle dure 54,24 s. Elle partait au début du rampement à
  0,75 m/s, qui ne commence plus qu'au galet 238, soit 49,2 s avant
  l'arrêt. Elle part maintenant à 51 m de l'arrêt, quelle que soit la
  vitesse, et finit 3 s avant (`audit_physique/annonce_arrivee.sage`, PC
  et PWA ; test sur une rame pleine et une rame vide).
- **« La variation de la pente en haut avant l'entrée en gare n'est pas
  continue alors qu'elle l'est dans la réalité »** : la pente suit
  désormais une courbe cubique monotone (Fritsch-Carlson) passant par les
  points du profil. La pente et sa variation sont continues, sans jamais
  dépasser les valeurs relevées. Avant, la variation changeait d'un coup à
  chaque point du profil : ×22 à 3 368,52 m. La physique, la voie
  dessinée et le PC suivent la même courbe
  (`audit_physique/pente_continue.sage`, identique à scipy à 2·10⁻¹⁶
  près). La pente reste de 10 % au galet 238.
- **« En vue extérieure et en vue salle des machines on ne voit pas le
  paysage »** : le panorama couvre maintenant le tour complet (6 144 ×
  1 024, de −25° à +35°). Il s'affiche en vue cabine, et dans les autres
  vues dès que la caméra est à moins de 150 m de la gare amont.
- Vérifié : 97 tests PC (+1), 12 bancs PWA, parité PC/PWA OK.

**v1.15.69** — la sortie de secours dessinée d'après la vidéo.
- **« Regarde comment c'est foutu la sortie de secours à 0:54 »** (vidéo
  de montée 20260426_094649.mp4, 0:54-0:55, au galet 145) :
  - le tube s'élargit sur quelques mètres et l'on voit tout autour le
    rebord circulaire de la chambre (deux anneaux sombres) ;
  - à droite, l'ouverture est sombre et haute, depuis la passerelle, avec
    un bord de béton clair, un petit panneau vert « SORTIE » et une
    étiquette blanche juste après ;
  - en face, sur la paroi gauche, juste avant l'anneau et sous les câbles :
    un boîtier orange, un coffret blanc et sa gaine jusqu'au sol.
- La porte plaquée et le grand panneau « SORTIE DE SECOURS » de la 1.15.68
  sont retirés. **Pas de gyrophare** (retour de Kevin) : l'objet orange est
  un boîtier, pas un feu.

**v1.15.68** — courbes, galets et sortie de secours aux positions lues au
compteur de la cabine.
- **Relevés de Kevin dans la vidéo de montée** (compteur 0 au départ, nez
  de la rame montante à s = compteur + 38,56 m) :
  - premier et dernier galet incliné de chaque courbe : n° 81 à 1 274 m et
    n° 98 à 1 510 m, puis n° 126 à 1 857 m et n° 163 à 2 351 m ;
  - dernier galet de l'évitement, le n° 121, à 1 790 m ;
  - sortie de secours au n° 145, à 2 112 m.
- **Courbes** : leurs positions chronométrées sur la vidéo étaient
  décalées de 15 à 30 m (la seconde commençait 29 m trop tard). Elles vont
  maintenant exactement du premier au dernier galet incliné. Les angles,
  recalés sur l'IGN avec ces positions, font 15,9° et 28,5° ; l'écart
  moyen à la ligne IGN est de 2,5 m (10 m au pire, la précision de l'IGN).
- **Les galets ne sont plus au pas constant** : ils sont serrés dans les
  courbes (13,3 à 13,9 m) et plus espacés en ligne droite (14,5 à 15,9 m).
  Les n° 81, 98, 126, 145 et 163 sont à moins de 0,7 m des relevés.
  L'ancienne grille plaçait le n° 81 à 79 m trop bas. Le n° 121, posé par
  la géométrie des aiguillages, tombe à 0,2 m du relevé : cela confirme la
  correspondance entre compteur et position. Les galets inclinés sont
  exactement les n° 81 à 98 et 126 à 163.
- **Courbes en arcs de cercle dans la PWA**, comme sur PC. Le cap était
  lissé par demi-courbe, ce qui annulait la courbure au début, au milieu
  et à la fin : le premier galet incliné restait presque droit.
- **Sortie de secours** : une porte métallique dans la paroi droite en
  montant, au galet 145, avec cadre, barre anti-panique et panneau vert
  « SORTIE DE SECOURS » éclairé au-dessus. Rien ne dépasse de la paroi, le
  gabarit de la rame ne laisse que 15 cm.
- Panorama de la gare amont recentré sur le nouveau cap d'arrivée
  (214,2°).
- Vérifié : 96 tests PC, 12 bancs PWA, parité PC/PWA OK.

**v1.15.67** — gare amont ouverte sur le glacier, tracé vérifié sur l'IGN,
approche au galet 238.
- **Gare amont refaite (retours de Kevin) : « la sortie est vers le
  haut »**. Les marches des quais se prolongent dans le hall de la salle
  des machines jusqu'à un palier plat, de chaque côté de la fosse des
  roues. Le mur du fond devient une façade vitrée sur toute la largeur,
  avec une porte coulissante à deux vantaux en face de chaque palier
  (« SORTIE EXIT »). Le plafond monte à 6 m sur les 7,6 derniers mètres
  (verrière) : le sommet de la Grande Motte, à 14° au-dessus de
  l'horizon et à 2,3 km, se voit dès la cabine, rame à quai. L'enseigne
  « DESTINATION GLACIER » passe sur un panneau bois au-dessus des portes.
  L'ancien hall de 14 × 28 m, qui aurait bouché la vue, est supprimé.
- **La vue est le vrai paysage** : panorama calculé sur le relief réel
  (Terrain Tiles : SRTM, EU-DEM) depuis la gare amont de l'IGN, centré sur
  le cap réel de la voie (214,5°) — la Grande Motte à 2,3 km, la Grande
  Casse à droite. Habillage d'hiver (neige sous 37°, roche au-delà), ombres
  du soleil, voile atmosphérique, courbure terrestre. `tools_panorama.py`
  le régénère. Il n'est affiché qu'en vue cabine. En rendu web (iPad), une
  correction de gamma garde un ciel de plein jour : le rendu Compatibility
  assombrissait le ciel jusqu'au bleu nuit.
- **Garde-corps en tube rond bleu, angles cintrés, dans les deux gares**
  (« la structure des barrières est bleue, pas grise, c'est un tube rond et
  les angles sont arrondis »). En haut, la barrière ne ferme plus le
  quai. Elle part 1 m sous le nez de la rame arrêtée (« pas d'espace vide
  entre le haut du funi et le début des barrières ») et longe le palier
  jusqu'au mur du fond, pour qu'on ne tombe pas dans la fosse. En bas, le
  tracé ne change pas (retour en travers et porte « réservé au personnel »).
- **Tracé en plan vérifié de bas en haut sur l'IGN et OpenStreetMap**
  (`audit_physique/trace_ign.sage`). Les positions des courbes (vidéo
  cabine) étaient justes, pas leurs angles : 20° + 28° deviennent 16,5° +
  28,3°. L'écart à la ligne IGN (précision 10 m) passe de 18 m en moyenne
  et 38 m au pire à 2 m en moyenne et 11 m au pire. Les caps sont
  maintenant géographiques : 169,7° au départ, 214,5° à l'arrivée. Les
  coordonnées GPS notées dans le code étaient fausses (le point « gare
  amont » tombait sur l'évitement) : remplacées par celles de l'IGN.
- **« La vitesse de 0,7 m/s est atteinte quand on arrive au galet 238 et
  pas avant »** : la vitesse d'approche (0,75 m/s) est atteinte quand le
  nez de la rame montante passe le galet n° 238, à l'entrée du quai haut,
  et non plus 20 m plus tôt (`CREEP_DIST` de 55 à 35,03 m, PC et PWA). Un
  test le vérifie dans les deux sens de conduite.
- **Le boîtier blanc en lévitation en gare basse** était un boîtier
  électrique du tunnel posé dans la salle de la gare, loin de tout mur, et
  les deux câbles muraux du tunnel traversaient les salles des gares dans
  le vide. Les deux s'arrêtent maintenant à l'entrée du tube, dans les
  deux gares.
- Vérifié : 96 tests PC (+1), 12 bancs PWA, parité PC/PWA OK, rendus
  Vulkan et Compatibility.

**v1.15.66** — la rame pleine recule de plus d'un mètre en gare basse.
- **« Je suis sûr du mètre » : la rame pleine recule d'au moins 1 m pendant
  l'embarquement en gare basse**. Avec un câble de 1 250 mm² d'acier à
  100 GPa (EA = 1,25·10⁸ N, une estimation et non une donnée constructeur,
  Fatzer ne publiant pas le module de ses câbles à torons), le recul
  n'était que de 0,60 m. EA est maintenant la raideur effective de toute
  la chaîne (câble, tassement, poulies, machinerie), calée sur cette
  observation : 7,0·10⁷ N, soit 1,07 m de recul pour 334 passagers
  (`audit_physique/recul_embarquement.sage`). Même valeur sur PC et dans
  la PWA.
- Conséquences, chiffrées par Sage :
  - l'oscillation à l'arrêt en bas est plus lente et plus ample :
    11,7 s par aller-retour pour une rame pleine au bout de 3 450 m de
    câble, au lieu de 8,7 s ;
  - la stabilisation sous 2 cm prend 35 s pour une rame pleine en bas, au
    lieu de 26 s. Le garde-fou d'ouverture des portes passe de 30 à 45 s
    (exploitation automatique, pilote auto, demi-tour de la PWA), sinon
    les portes s'ouvraient en pleine oscillation ;
  - la marge de 4,5 m au butoir bas garde au moins 3 m dans le pire cas
    (recul de 1,07 m plus oscillation).
- **« La barrière doit descendre jusqu'au point bas de l'allongement du
  câble, cabine pleine en bas »** : en gare basse, le garde-corps part de
  la position du nez quand la rame pleine a reculé au maximum
  (`TrainPhysics.recul_embarquement_max`, 1,07 m sous le nez à l'arrêt).
  En gare haute, l'allongement n'est que de 5 mm.
- Tests : les valeurs attendues ont été mises à jour depuis Sage (période
  11,68 s, recul de 1,0 à 1,2 m, rebond en bas jusqu'à 80 cm). 95 tests
  PC, 12 bancs PWA, parité PC/PWA OK.

**v1.15.65** — chaque trajet fait vraiment 3 474 m : voie rallongée de
40,52 m.
- **« La distance parcourue réelle de chaque trajet, c'est 3 474 m »** :
  la voie faisait 3 474 m d'un butoir à l'autre, si bien qu'entre les
  deux points d'arrêt la rame ne parcourait que 3 433,48 m. La v1.15.64
  ramenait seulement le compteur à 3 474.
- **« Tu rallonges des sections neutres de part et d'autre de
  l'évitement, où il n'y a ni changement de pente ni virage, et tu
  ajustes la répartition des galets pour garder le même nombre »** :
  - deux tronçons de 20,26 m sont insérés à 1 571 m (entre la fin de la
    courbe 1 et l'entrée de l'évitement) et à 1 853,5 m (entre la sortie
    de l'évitement et la courbe 2), à pente constante (29,5 %) et en ligne
    droite. Tout ce qui est au-delà recule d'autant : tables de pente, de
    cap, de zones sombres et de sections du tunnel, évitement (1 631,26 à
    1 833,26 m, même longueur), salle de la gare haute, arrêts, quais,
    butoirs. Le changement est fait sur PC et dans la PWA ;
  - la voie fait 3 514,52 m (`LENGTH`), et le trajet d'arrêt à arrêt
    3 474 m (`PARCOURS` = `STOP_S` − `START_S`). En haut, l'arrêt est à
    3 496,56 m ; l'autre rame est au miroir 3 519,12 − s. Les rames se
    croisent à 27 m en aval du centre de l'évitement, contre 25 m avant ;
  - les galets restent 238, au pas de 14,71 m au lieu de 14,54. Le n° 238
    est à 3 477,53 m, à l'entrée du quai haut, où la pente de la gare
    (10 %) est atteinte. Les galets non numérotés de la gare haute sont
    comptés depuis le bout de la voie : le dernier, qui raccorde la salle
    des machines, est à −6,79 m au lieu de −7,04 ;
  - le compteur du pupitre affiche la distance réellement parcourue, sans
    mise à l'échelle.
- Audit : `audit_physique/arrets_gares.sage` (voie, arrêts, galet 238,
  et recul de la rame pleine à l'embarquement : 0,57 m avec 334 × 75 kg,
  0,65 m avec 85 kg ; 1 m demanderait un câble de module 57 GPa).
- Tests :
  - deux bancs avaient en dur l'ancienne position de l'évitement et un
    tirage de panne. Le planificateur pouvait tirer une rupture de câble,
    qui ne se « lève » pas en ligne et se comptait alors à chaque image ;
    il y a maintenant une remise en service complète entre deux pannes ;
  - 12 bancs PWA, 95 tests PC ;
  - parité PC/PWA OK (0,1 kW au 95e percentile).

**v1.15.64** — garde-corps de haut de quai, compteur et indicateur de
vitesse du pupitre, roues qui suivent la rame.
- **« En haut des deux rames, en gare aval comme amont, des barrières le
  long du quai avec bordure bleue, qui commencent où la tête de rame
  s'arrête, et vont à angle droit pour fermer le quai en haut avec une
  porte réservée au personnel »**, d'après la vidéo d'arrivée en gare
  haute et les photos 095443 / 095511 :
  - un garde-corps galvanisé (montants verticaux, main courante et deux
    lisses parallèles à la pente, plinthe bleue qui suit les marches) longe
    la voie sur chaque quai, du nez de la rame arrêtée au haut du quai ;
  - au haut du quai, un garde-corps en travers le ferme du bord de voie au
    mur, avec un portillon bleu « RÉSERVÉ AU PERSONNEL ».
- **« Quand on part, le compteur indique 0 m, quand on arrive 3 474 m,
  quel que soit le sens ou la rame »** : la PWA affichait l'abscisse brute
  (23 m au départ, 3 456 m à l'arrivée en haut), et le petit écran du
  pupitre du PC aussi. Les deux affichent maintenant la distance du trajet
  (`distance_compteur`, même calcul sur PC et PWA).
- **« L'indicateur de vitesse prend la vitesse des roues du train, pas
  celle de la machinerie »** : les cadrans du PC et de la PWA lisent la
  vitesse de la poulie plus l'oscillation élastique de la rame
  (`vitesse_roues`). C'est la même en régime établi ; elle s'en écarte
  dans les transitoires et pendant le rebond à l'arrêt. Le panneau de la
  salle des machines garde la vitesse du câble.
- **« Quand la rame du bas recule pendant l'embarquement, les roues n'ont
  pas l'air de tourner »** : elles tournaient à la vitesse de la poulie,
  nulle à quai. Elles tournent maintenant selon le déplacement réel de la
  rame dessinée : 1,035 rad pour 31 cm de recul, soit d/R.
- Vérifié : 2 tests PC (compteur, vitesse des roues), contrôle du compteur
  à 3 474 m à l'arrivée dans le banc des portes, 12 bancs PWA, 95 tests
  PC, vues des garde-corps aux deux gares.

**v1.15.63** — quais à la bonne longueur, rame d'en face complète, boutons
dans le navigateur du PC.
- **« Les quais sont trop longs : en bas le quai se prolonge de 4 m après
  le haut de la rame, en haut de 3 m après le bas de la rame ; le galet
  238 doit arriver en entrée de quai, et la pente de la gare du haut doit
  y être atteinte comme maintenant »** :
  - les quais s'étendent maintenant de 3 à 42,56 m en bas, et de 3 437,04
    à 3 473 m en haut. Avant, c'était 3 à 51 m et 3 425 à 3 473 m
    (`PNConstants.QUAI_*`) ;
  - le galet n° 1 est à 43,79 m, à 1,23 m de la fin du quai bas ; le
    n° 238 est à 3 436,76 m, à 0,28 m de l'entrée du quai haut. Ils
    restent entre deux traverses, et la grille garde ses 238 supports ;
  - la pente de la gare haute (10 %) est atteinte au n° 238, sur PC comme
    dans la PWA. La vidéo la plaçait à 3 420 m, où le tunnel redevient
    carré, et le tunnel ne change pas. Parité PC/PWA vérifiée.
- **« Vue salle des machines : l'autre rame à quai en haut ne contient pas
  de passagers et la vitre du cockpit est opaque »** : la rame d'en face
  était dessinée simplifiée (sans intérieur, disque sombre derrière des
  vitres teintées). Elle a maintenant le même pare-brise clair, le même
  intérieur et ses passagers, à moins de 150 m seulement (comme ses roues),
  et sans lampe de poste pour ne pas entamer le quota de lumières de la
  PWA. En descente, elle porte 0 à 16 passagers : les skieurs redescendent
  à ski.
- **Navigateur du PC** : les boutons à l'écran (PORTES, PRÊT/DÉPART…)
  n'apparaissaient que sur écran tactile. Ils sont maintenant là dans tout
  navigateur et se cliquent à la souris. La ligne des raccourcis clavier
  ajoute « D Portes » et passe sous le bouton MODE.
- Vérifié :
  - banc des galets avec un nouveau contrôle, la pente atteinte au n° 238 ;
  - pas de saut du câble jusqu'à 10 mm. Sur un galet incliné de −8° en
    courbe, le câble soulevé de 1,6 mm glisse de 13 mm dans la gorge,
    selon la loi physique du jeu en √h ;
  - 12 bancs de la PWA, 93 tests du PC, parité PC/PWA ;
  - vues des bouts de quai et du pare-brise de l'autre rame
    (`shot_orbite.gd quai` / `fantome`).

**v1.15.62** — arrêts calés sur les butoirs, bouton PORTES, débarquement à
l'arrivée.
- **« En haut on s'arrête à 1,5 m du butoir, en bas à 4 ou 5 m, pour la
  marge d'oscillation et d'allongement »** (fait de Kevin) :
  - **avant**, le PC s'arrêtait à 9,5 m du butoir en haut et à 7,9 m en
    bas, la PWA à 0,6 m et à 1,9 m. Surtout, dans la PWA, la rame d'en
    face était placée en miroir à 3 474 − s, alors que ses points
    d'arrêt n'étaient pas symétriques. Quand on arrivait en haut, l'autre
    rame finissait donc 1 m **dans** le butoir bas, et l'arrêt dépendait
    de la rame et du sens ;
  - **maintenant**, les points d'arrêt sont comptés depuis la face des
    têtes en bois des butoirs : 1,5 m en haut (`STOP_S` = 3 456,04), 4,5 m
    en bas (`START_S` = 22,56), et les mêmes sur PC et dans la PWA. La
    rame d'en face est au miroir de ces deux arrêts : `MIROIR_S` = 3 478,6.
    Le câble entre les deux rames fait donc 4,6 m de moins que la voie.
    `audit_physique/arrets_gares.sage` donne l'allongement du brin de la
    rame en bas : 2,2 m vide, 2,8 m pleine ;
  - **mesuré** dans la PWA, l'arrêt se fait à 1,53 m en haut quelle que
    soit la charge, et entre 4,1 et 4,7 m en bas selon l'oscillation et
    l'affaissement d'embarquement. En Défi, la collision a lieu nez
    contre la tête du butoir ; avant, elle était 3,5 m dans le mur en
    haut.
- **« Un bouton pour les portes dans la PWA »** : un bouton tactile
  PORTES à gauche de PRÊT/DÉPART, vert quand les portes sont ouvertes (et
  la touche D au clavier). Il reprend les mêmes verrous que la touche D
  du PC : rame immobile, ouverture à quai seulement, aucun verrou en Défi.
  - La fermeture joue la vraie séquence (annonce, buzzer, clip) sans
    partir.
  - PRÊT/DÉPART, portes déjà fermées, ne lance que le buzzer de quai.
    Pendant une fermeture au bouton, il enchaîne directement sur le
    départ.
  - Un refus s'affiche dans le bandeau d'état.
- **« En mode auto sur le PC, à l'arrivée, aller jusqu'à l'ouverture des
  portes et le débarquement des passagers »** :
  - le pilote auto (A) attend la fin des oscillations du câble (comme
    l'exploitation automatique), ouvre les portes, laisse descendre tout
    le monde, puis rend la main. Au départ, il ne ferme les portes
    qu'une fois l'embarquement fini ;
  - à l'ouverture des portes à l'arrivée, sur PC (touche D, X, A) comme
    dans la PWA, les passagers des deux rames **descendent** d'abord,
    environ 12 s pour 150 personnes par voiture. La nouvelle charge
    monte ensuite, au demi-tour. Avant, les effectifs glissaient
    directement de l'ancienne charge à la nouvelle ; l'exploitation
    automatique attend maintenant que tout le monde soit descendu.
- Tests :
  - deux tests du PC avaient en dur l'ancien miroir et l'ancien pilote ;
  - celui de la boucle de croisière échouait depuis le volume général de
    la v1.15.56, car il lisait le niveau demandé et non celui envoyé à
    Qt.
  - Bancs de la PWA : 12 au vert, dont 10 nouveaux contrôles des portes.
  - Parité PC/PWA : 0,1 kW au 95e percentile.

**v1.15.61** — câble continu au galet de contact, décollage sans angle.
- **« Au point de contact avec le galet, le câble semble s'interrompre »**.
  Deux causes :
  - **un vrai trou en marche.** Le câble posé est fait de segments de
    15 m, et leur affichage n'était recalculé que quand la rame changeait
    de tranche de 15 m. Or depuis la v1.15.59, le câble commence au
    premier galet touché, devant la rame, et ce point avance par sauts :
    il recule d'une rame à l'autre. Le segment juste après le galet
    restait donc masqué, jusqu'à 15 m de câble manquant. Cela arrivait
    dans 25 % des positions, en montée comme en descente, puisque l'une
    des deux rames descend toujours. L'affichage suit maintenant la
    position de cette coupe elle-même ;
  - **une couture.** Les anneaux du tronçon libre comptaient leur angle
    depuis la gauche de la voie, ceux du câble posé depuis la droite.
    L'hélice des torons s'inversait donc au raccord. Ils ont maintenant
    le même repère.
- **« Le décollement est toujours brusque avec un angle »** :
  - **coude vers le haut.** Dans 15 % des positions, le câble pliait
    vers le haut sur le premier galet, jusqu'à 0,8° : un « V » qu'aucun
    galet ne peut faire, puisqu'un galet porte et ne retient pas. Le
    critère D·(D + L) ≥ 2ah supposait une voie droite. Surtout, le
    tronçon libre prenait la tension de la jauge, et les portées celle du
    câble à l'altitude, jusqu'à 239 kN en haut. Les deux ont maintenant
    la même tension, puisque la tension est continue le long du câble.
    Le premier galet est désormais celui sous lequel passerait la
    chaînette qui irait plus loin, ce qui équivaut à un coude vers le
    bas (`audit_physique/decollage_galet.sage` : hauteur / coude =
    D·L/(D + L) > 0). Quand la rame avance, le câble quitte chaque galet
    à 0 mm et tangentiellement. Il reste au plus +0,000° au premier
    galet. Le coude normal, vers le bas, vaut 0,4 à 0,7°, comme sur
    n'importe quel galet de la ligne (L/a) ;
  - **sauts sur le côté.** En courbe et dans l'évitement, le tronçon
    libre sautait jusqu'à 3,3 cm de côté. Au-dessus d'un galet, le
    câble était ramené au centre de la gorge en dessous de 7 cm, et
    laissé libre au-dessus. Il a maintenant le vrai jeu de la gorge,
    mesuré dans le repère du galet incliné : 0 au fond, puis 3,2 cm·√(h/6
    mm) dans le creux, puis 3,3 cm + 0,78·h le long des joues. Le tronçon
    suit la ligne tendue (la plus courte) à travers ce jeu, qui varie
    sans saut. Les poulies de déviation de l'aiguillage le retiennent du
    côté intérieur du coude jusqu'à ce qu'il passe au-dessus de leur
    jante, sur un chanfrein de pente 0,5. Avec une arête vive, il
    sautait de 3,6 cm, et une pente doit rester sous cotan 30° = 1,73
    pour que sa position soit unique. Il reste des pas de 4,5 mm au
    plus, au changement de galet près des gares.
- Plus léger : le tube du tronçon libre se reconstruit en 0,04 ms au
  lieu de 1,1 ms, et celui de la rame lointaine (à plus de 250 m) n'est
  plus refait. Le câble coûte 0,29 ms par image au lieu de 1,37 ms.
- Vérifié :
  - banc des galets à 26 contrôles, avec six nouveaux sur toute la ligne
    dans les deux sens : coude au premier galet, câble continu en marche,
    sens des torons, joues et poulies jamais traversées, pas de saut d'un
    pas de 0,5 m au suivant ;
  - le test de rupture, instable une fois sur trois (le bout suit la
    position affichée de la rame, en retard d'un pas), a maintenant une
    tolérance d'un pas ;
  - bancs aiguillage, salle des machines, rame, portes, son et
    performance ;
  - vues au contact du galet (`shot_orbite.gd plongee descente=20`).

**v1.15.60** — câble sous la rame : virages, évitement et arrivée en gare
amont.
- **« Vérifie la pose du câble à la descente, dans les virages et
  l'évitement »** : le câble part toujours du culot vers l'amont, en
  montée comme en descente. Mais dans la v1.15.59, son tronçon libre
  suivait la corde droite du culot au premier galet touché. Balayage de
  toute la ligne, dans les deux sens :
  - en courbe (1 300 à 2 300 m), cette corde s'écartait jusqu'à 18 cm de
    la gorge des galets qu'elle survolait, et passait dans leurs joues ;
  - dans l'aiguillage, elle sautait 75 fois un galet de déviation ;
  - en arrivant en gare amont, elle traversait de 2,5 cm le dernier
    galet du tunnel ;
  - sur une bosse du profil en long, la corde pouvait passer sous le
    sommet d'un galet intermédiaire.
- Le tronçon libre est maintenant découplé :
  - **en hauteur**, c'est la chaînette jusqu'au premier galet sur lequel
    elle appuie, à 10-26 m, et la courbe reste douce. La hauteur est
    comptée au-dessus du sommet de chaque galet, profil en long compris.
    Un galet qui dépasse de la chaînette devient l'appui, y compris en
    arrivant en gare amont ;
  - **sur le côté**, là où le câble passe bas au-dessus d'un galet (moins
    de 7 cm, joues et rayon du câble), il est dans la gorge : le galet,
    incliné en courbe, le guide par sa joue et le câble suit l'axe de la
    gorge. Galets de déviation compris. Plus haut, il passe au-dessus
    sans le toucher.
  Résultat : 2 mm d'écart au plus avec l'axe des gorges survolées, aucun
  galet traversé, galets de déviation suivis.
- Tracés réels du jeu (courbe, évitement, courbe haute) :
  `audit_physique/plan_chainette.png`.
- Vérifié : 3 contrôles ajoutés au banc des galets, qui balaie toute la
  ligne dans les deux sens. Bancs aiguillage, rupture, 3D, salle des
  machines et Défi.

**v1.15.59** — le câble pend en chaînette, sous la rame et entre les galets.
- **« Sous la rame, le câble semble collé au sommet des galets et s'en
  décolle au dernier moment ; il vaudrait mieux respecter la courbure
  en cosh, qu'il se décolle du galet un peu avant l'attache et sans
  angle »** :
  - avant, le câble restait posé jusqu'au premier galet en amont du
    culot, puis montait tout droit vers lui, avec un coude ;
  - maintenant, du culot (12 cm au-dessus de la ligne des galets), il
    décrit une chaînette (forme exacte en cosh) jusqu'au premier galet
    qu'il touche vraiment, R1. La pente au culot est dans l'axe du culot.
    Les galets d'avant sont survolés : ils sont libérés et ralentissent ;
  - R1 est le premier galet, à la distance D, sur lequel la chaînette
    appuie : D·(D + L) ≥ 2·a·h, avec a = T/(w cos α) entre 1 200 et
    2 700 m selon la tension, et L la portée suivante. Il est à 17-30 m
    du culot (`audit_physique/chainette_attache.sage` : 17 à 25 m pour un
    appui continu). Sur R1, le galet dévie le câble d'environ 0,5°, autour
    de 25 cm de rayon : invisible.
- **« Le cosh dans chaque section de câble entre ses points d'appui »** :
  chaque portée pend en chaînette entre deux galets, a(cosh(L/2a) −
  cosh((x − L/2)/a)). La tension croît vers le haut avec le poids du
  câble, d'environ 140 kN en bas à 240 kN en haut. La flèche fait 1,2 à
  2 cm sur 14,5 m. Après une rupture, le câble retombe toujours jusqu'à
  la longrine.
- Profil réel du jeu (échelle verticale amplifiée) :
  `audit_physique/profil_chainette.png`.
- Salle des machines : le raccord du brin visait encore l'ancien dernier
  galet du tunnel (−6,865 m). Depuis le recalage entre les traverses
  (v1.15.56), ce galet est à −7,04 m ; le câble faisait un petit coude de
  17 cm. C'est corrigé.
- Vérifié : banc des galets (20 contrôles, dont R1, la chaînette, le
  coude sur R1, la flèche et les galets survolés), bancs de la salle des
  machines, rupture, aiguillage, 3D, Défi et portes ; vue dans l'axe du
  câble sous la rame (`shot_galets.gd vue=chainette`).

**v1.15.58** — passagers redessinés : de vrais skieurs.
- **« Redesign complètement les passagers pour qu'ils soient bien
  réalistes, mes skieurs »** : les silhouettes en capsules sont
  remplacées par des skieurs modélisés (`scripts/skieur_mesh.gd`), aux
  proportions d'un adulte de 1,75 m :
  - **corps** : veste et pantalon de ski bouffants. La veste a une
    fermeture éclair, des poches et un col montant, parfois un
    empiècement d'épaules d'une autre couleur. Le pantalon recouvre des
    chaussures de ski rigides (coque, tige inclinée, boucles, strap).
    Gants à manchette, visage ;
  - **tête** : casque à oreillettes avec masque (écran miroir, monture,
    sangle), ou bonnet à revers et pompon avec cheveux et lunettes de
    soleil. Tour de cou porté sur le menton chez certains ;
  - **sac à dos** pour un quart d'entre eux, bretelles posées sur la
    veste ;
  - **attitudes** : debout qui tient ses skis, mains libres, sur son
    téléphone (tête penchée), enfant, et assis sur les perchoirs ;
  - **matériel** : skis cintrés à spatules relevées, avec fixations,
    freins, semelle noire et carres ; bâtons avec poignée, dragonne et
    rondelle ; snowboard avec fixations à spoiler ;
  - **couleurs** : chacun s'habille dans des palettes de vêtements de ski
    actuels (`scripts/skieur.gdshader`). Veste unie ou bicolore, pantalon
    souvent sombre, casque mat ou brillant, écran miroir orange, bleu,
    argent… Peau, cheveux, gants et chaussures varient aussi. Les tailles
    varient de ±6 %.
- Les skieurs qui attendent dans les halls des gares (une boîte et une
  sphère jusqu'ici) sont les mêmes : assis sur les bancs, ou debout
  avec leurs skis ou leur surf.
- Performance : deux niveaux de détail dans le même maillage. Les
  passagers de la rame pilotée ne sont plus dessinés en vue cabine, où
  ils sont derrière la caméra. PWA mesurée sur GPU : 3,0 à 3,7 ms par
  image en vue cabine (au lieu de 3,4 à 4,2), 60 images/s en vue
  extérieure. La première bascule en vue extérieure fige l'image environ
  0,9 s, comme avant (compilation des shaders) ; les skieurs y ajoutent
  environ 0,2 s.
- Outils : `shot_skieurs.gd` (studio des attitudes), `shot_pax.gd` (vues
  dans la rame et en orbite), arguments `--vue=1` et `--sans-pax` pour
  les mesures. Bancs 3D, portes, rame et galets passent.

**v1.15.57** — tunnel de nouveau éclairé dans la PWA.
- **« Dans la PWA l'éclairage du tunnel n'est plus comme avant, c'est
  tout sombre »**, au moins dans la seconde moitié de la montée, en
  coupant puis en rallumant le tunnel (capture iPad du 05/10, 2 830 m) :
  - cause : le rendu web (Compatibility) ne dessine qu'un nombre limité
    de lampes par image (32 par défaut) et laisse tomber les autres dans
    un ordre arbitraire. Autour des deux rames, il y avait déjà 32 néons,
    plus les lampes des gares, de la salle des machines et de la cabine.
    En seconde moitié de montée, les néons de l'autre rame, plus bas,
    prenaient la place de ceux de la cabine ;
  - mesure dans la PWA (Chromium sur GPU), phares coupés et tunnel
    allumé : 15/255 de luminance à 2 730 m, contre 50 à 80 maintenant.
    Les phares masquaient le défaut dans les essais précédents ;
  - le web garde maintenant les néons autour de la rame pilotée
    seulement (l'autre rame est à plus d'un kilomètre). Le quota passe à
    128 lampes (`limits/opengl/max_renderable_lights`), ce qui sert aussi
    aux PC en rendu OpenGL. Image un peu plus légère : 3,4 à 4,2 ms en
    médiane, au lieu de 4,0 à 4,8 ms ;
  - interrupteur J : les lampes restent en place à énergie nulle et les
    tubes prennent le matériau des tubes éteints. On ne cache plus les
    lampes et on ne change plus le mode d'ombrage, ce qui obligeait le
    rendu web à recompiler des shaders à chaud. Le ciel s'éteint par son
    énergie, au lieu de désactiver la source des reflets. Le noir total
    est conservé : 2,2/255 sur PC avec tout éteint, 45 tunnel allumé.
- Vérifié : coupé puis rallumé à 1 300 et 2 700 m dans Chromium et WebKit
  (moteur de Safari), bancs 3D, galets, Défi, rupture, aiguillage, perf.

**v1.15.56** — galets de ligne fidèles et qui tournent, supports redessinés
entre les traverses, câble accroché au milieu de la voiture amont par un
culot, volume général.
- **« Dessine bien les galets comme en vrai : leurs bords qui remontent,
  le bon diamètre, la bande de roulement en caoutchouc, leur structure »**.
  Mesures prises sur la photo d'un galet posé à plat (reportage
  remontees-mecaniques.net, O. Lakatos 2015), avec le câble de 52 mm et
  le culot posés à côté comme étalon :
  - deux joues évasées en alliage Ø 640 qui forment une gorge en V ;
  - une bande de roulement en caoutchouc noir Ø 500 au fond de la gorge,
    où repose le câble ;
  - un moyeu à cinq bras, visible par l'ouverture des joues.
  Avant, c'était un cylindre blanc de 300 mm. Vus de la cabine, on
  retrouve les deux joues claires et la gorge sombre de la vidéo du 26/04.
  En courbe et dans l'évitement, les galets inclinés montrent leur face.
- **« Leur bonne vitesse de rotation selon la vitesse du câble, et leur
  ralentissement progressif une fois que le câble est parti »** :
  - un galet sous le câble tourne à v/R, soit 458 tr/min à 12 m/s ;
  - quand le culot de sa rame le dépasse, il est libéré et ralentit seul :
    environ 111 s pour s'arrêter, freiné surtout par les joints de ses
    roulements (`audit_physique/galets_ligne.sage`) ;
  - il n'y a pas de câble lest (fiche du reportage) : les galets en aval
    d'une rame sont immobiles ou en train de ralentir ;
  - seuls les galets proches de la caméra sont animés. Au-delà de 70 m,
    un modèle allégé prend le relais sans que rien disparaisse.
- **« Redessine les supports des galets pour qu'ils soient fidèles »,
  « mets-les entre deux traverses, tu auras plus de place en largeur »** :
  - chaque galet tourne dans une fourche galvanisée : deux flasques, une
    semelle, deux paliers boulonnés et l'axe. La fourche s'incline avec
    le galet en courbe ;
  - la fourche repose par un pied sur une traverse en U, large de 1,40 m,
    qui enjambe la fosse sur deux cornières ;
  - chaque support est calé au milieu de l'intervalle entre deux rangées
    de plots, avec au moins 22 cm entre une joue et un plot. Le n° 1 reste
    juste après le quai aval, le n° 238 juste avant le quai amont ;
  - la plaque de numéro est décalée (36 cm de l'axe, 15 cm en avant du
    support) pour dégager les paliers.
- **« Le câble s'accroche au milieu de la voiture amont de chaque rame,
  avec le dispositif qu'il y a en photo »** : un culot (cône coulé sur le
  bout du câble, « attaches culot » de la fiche technique) est tenu par
  une chape sous la voiture amont, plus haut que les joues des galets. Le
  câble redescend de lui jusqu'au premier galet en amont, puis repart de
  galet en galet. Auparavant, il s'arrêtait au centre de la rame.
- **Galets inclinés autour du câble** : en courbe, le galet s'incline pour
  recevoir le câble sur sa ligne. Avec les galets Ø 500, pivoter autour
  de leur centre aurait déporté le câble de 15 cm, jusqu'à toucher les
  rails de l'aiguillage Abt.
- **« Un bouton à côté du son pour régler le volume général »** : entre
  SON et AIDE, une jauge − / + (pas de 10 %), aussi sur F7 / F8 et à la
  molette au-dessus de la jauge. Le réglage est retenu d'une session à
  l'autre et s'applique aussi au son de la vue 3D. Chaque son garde son
  niveau propre (fondus, ambiances) ; le volume général s'y ajoute.
- PWA mesurée sur le GPU du NAS : toujours 60 images/s stables, 4,8 ms de
  calcul par image en médiane, au lieu de 3,7 ms.
- Vérifié :
  - banc `bench_galets_3d.gd` (16 contrôles) : v/R, sens opposé sur le
    brin de la rame descendante, pas de câble sous la rame, libération au
    passage du culot, ralentissement conforme à l'audit, arrêt en moins
    de 2 min, culot entre les joues et la caisse, supports entre les
    traverses, numéros 1 et 238 ;
  - aiguillage Abt sans conflit, bancs 3D, rupture, salle des machines,
    Défi et voyages ;
  - captures Forward+ de la voie droite, d'une courbe, de l'évitement et
    du culot ;
  - deux tests du volume ; les 94 tests PC passent.

**v1.15.55** — l'interface se règle sur l'écran détecté ; plein écran F11.
- **« Tu peux t'adapter auto à l'affichage détecté ? »** : l'échelle ne
  dépendait que de la taille de la fenêtre. Elle lit maintenant l'écran
  où se trouve la fenêtre : diagonale réelle, définition et mise à
  l'échelle du système (Windows 125 %…).
  - De la diagonale, elle déduit la distance de lecture probable :
    portable ≈ 50 cm, 24" ≈ 73 cm, 27" ≈ 80 cm, téléviseur ≈ 2 m. Elle
    agrandit alors le pupitre pour que le texte garde la même taille
    apparente qu'un 24" 1080p à 100 %. Exemples : 27" 1440p ×1,36,
    34" 21:9 ×1,73, téléviseur 55" ×2,5.
  - Elle ne descend jamais sous la mise à l'échelle choisie dans le
    système. Si la taille physique est absente ou fantaisiste (machine
    virtuelle, projecteur), l'ancienne règle s'applique.
  - Changer d'écran en glissant la fenêtre, de définition ou de mise à
    l'échelle est pris en compte tout de suite, vue 3D comprise.
  - Le journal de bord affiche au premier départ l'écran détecté et
    l'échelle retenue, par exemple « Écran 14″, 1920 × 1080, mise à
    l'échelle 125 % → interface à 76 % (limitée par la place — F11 :
    plein écran) ». Le rapport de problème contient aussi cette ligne.
  - Menu Affichage → Taille de l'interface : « Automatique (selon l'écran
    et la fenêtre) » ; plus petite ou plus grande restent possibles.
- **F11 : plein écran** (aussi dans le menu Affichage), retenu d'une
  session à l'autre. Sur un portable, la barre des tâches et la barre de
  titre reviennent au pupitre et à la vue : environ 14 % de hauteur en
  plus.
- Vérifié : facteurs calculés par `audit_physique/echelle_ecran.sage`
  (.txt) pour neuf écrans de référence, et repris dans
  `tests/test_echelle_interface.py`. On y contrôle aussi la taille
  physique absente, la ligne du journal, le changement d'écran en direct
  et F11. Les 92 tests PC passent.

**v1.15.54** — la fenêtre s'adapte à tous les formats d'écran.
- **« La fenêtre s'adapte mal aux différents formats d'écran »** : le
  pupitre, le journal et les écrans d'aide sont dessinés en pixels fixes,
  et l'interface exigeait au moins 1280 × 900. Un portable 1080p réglé à
  125 % n'offre que 1536 × 760 : la fenêtre sortait de l'écran (journal
  coupé), et le bas du pupitre (Temps, Confort) passait sous les voyants.
  - toute l'interface est maintenant dessinée à l'échelle de la fenêtre,
    d'un seul bloc. Elle rétrécit quand la place manque et grandit sur
    les très grands écrans. La vue (3D ou profil) prend la largeur en
    plus : 16:10, 16:9, 21:9 ultra-large ;
  - les clics, les infobulles et la fenêtre 3D embarquée suivent la même
    échelle ;
  - la fenêtre démarre à une taille qui tient sur l'écran, ou agrandie si
    l'écran est petit. Elle retrouve ensuite sa taille et sa place d'une
    session à l'autre ;
  - nouveau menu **Affichage → Taille de l'interface** : plus petite (plus
    de place pour la vue), normale, plus grande, très grande ;
  - pupitre : les libellés Consigne, Frein et Puissance ne sont plus
    rognés par leurs barres. L'allongement du câble passe dans le cadran,
    sous « daN », au lieu de déborder du cercle.
- Vérifié : `tests/test_echelle_interface.py` (13 tests) contrôle que tout
  tient à sept formats, du 1024 × 700 au 4K, ainsi que les clics, la
  place de la 3D, le menu et la mémoire de la fenêtre. Captures relues
  aux formats portable, petit écran et 21:9. Les 79 tests PC passent.

**v1.15.53** — la 3D se règle sur la machine et s'ajuste en direct
contre les saccades.
- **« Détecter la config du PC, CPU, cœurs, GPU, RAM… et adapter les
  réglages pour que ça reste fluide »** : au lancement, la vue 3D lit le
  processeur et son nombre de cœurs, la mémoire, la carte graphique et
  son pilote, la définition et la fréquence de l'écran, sous Windows,
  macOS et Linux. Elle en déduit un profil de départ :
  - carte dédiée (NVIDIA, Radeon RX) : tout activé ;
  - Mac Apple Silicon : sans l'éclairage indirect (SDFGI) ;
  - puce intégrée : un ou deux crans plus bas selon la mémoire et le
    nombre de cœurs ;
  - rendu logiciel (llvmpipe) : très bas ;
  - écran de plus de 2560 × 1600 : rendu 3D réduit d'office.
- **« Détecter les saccades en direct pour t'adapter en live »** :
  - toutes les 2 s, la durée de chaque image est mesurée : images par
    seconde, part d'à-coups (images au moins deux fois trop longues),
    1 % des pires images, et temps GPU quand le pilote le donne ;
  - la 3D descend d'un cran sous 83 % de la fréquence de l'écran, au-delà
    de 3 % d'à-coups, ou si les pires images dépassent trois fois le
    budget. Ordre des crans : éclairage indirect, puis brouillard
    volumétrique et reflets, puis anticrénelage et rendu à 85 %, puis
    70 %, puis 60 % sans halo, et enfin 30 images/s régulières plutôt
    que 45 saccadées ;
  - elle remonte quand c'est fluide : après 20 s si le GPU a de la marge,
    après 40 s sinon. Un cran qui saccade de nouveau dans les 20 s
    suivant une remontée est écarté pendant 3 min : pas de va-et-vient.
- **Menu Affichage → Qualité 3D** : Automatique, Haute, Moyenne, Basse.
  Le choix est retenu d'une session à l'autre et s'applique sans
  relancer la 3D. Les modes fixes ne s'adaptent pas.
- **Rapport de problème** : il contient la machine détectée et les
  derniers changements de cran avec leur raison.
- La PWA garde son réglage mesuré sur iPad : 60 images/s stables sur le
  banc GPU, rendu identique.
- Le rendu sur un fil séparé (`--render-thread separate`) n'est pas
  activé : Godot 4.6 le donne encore pour expérimental.
- Vérifié : banc `bench_perf_3d.gd` (19 contrôles : profils, écran 4K,
  descente sur à-coups et sur lenteur, remontée, interdiction de 3 min,
  modes fixes, plafond à 30 images/s), essai en fenêtre réelle, mesure
  de la PWA, test du menu, et tous les bancs 3D et tests PC.

**v1.15.52** — urgence sans oscillation, fluidité sur PC modeste, câble
rompu non réparable en ligne.
- **« Quand la rame monte et que je serre le frein d'urgence, elle oscille
  comme une dingue, avec le câble non cassé »** : jusqu'ici, l'urgence
  freinait toute l'installation par la poulie, et la coupure du moteur
  faisait osciller une rame pleine de 2,7 m au bout de 3 km de câble. Or
  l'urgence et le parachute sont des **freins de voie** : chaque rame
  serre ses pinces sur les rails et y est tenue. Tant qu'ils sont serrés,
  le câble ne fait plus osciller les rames, et un écart en cours s'éteint
  sans rebond. Mesuré à 500, 1 700 et 3 000 m : moins de 3 cm, contre
  273 cm. L'oscillation normale reprend au desserrage. Test
  `test_urgence_en_montee_pas_d_oscillation`.
- **« Sur un PC moins puissant ça saccade »** :
  - **vue 3D, mouvement lissé** : avec le PC, la rame avançait par sauts
    quand le PC, chargé, envoyait ses positions à rythme irrégulier. Elle
    avance maintenant entre deux paquets avec la vitesse reçue, puis se
    recale en douceur sur la position envoyée ;
  - **qualité adaptative** : la 3D du PC partait toujours en qualité
    haute. Sous 45 images/s, elle retire un effet toutes les 3 s, du plus
    coûteux au moins visible : éclairage indirect (SDFGI), puis
    brouillard volumétrique, reflets (SSR) et anticrénelage, puis rendu à
    75 % puis 60 % de la résolution, puis le halo (glow). Le journal
    indique « [Perf] … qualité réduite (cran n/5) » ;
  - **côté PC** : quand la 3D intégrée recouvre la vue, la fenêtre ne
    dessine plus la vue 2D en dessous, et le reste (pupitre, jauges,
    journal) se redessine à 30 Hz au lieu de 60.
- **Câble rompu** : dans la PWA, le bouton LEVER, F2 ou un changement de
  mode « réparaient » le câble en pleine ligne, et le contrepoids, figé
  dans le tunnel, sautait en miroir de la rame (en gare haute si elle
  avait glissé en bas). Comme au PC, seul un nouveau voyage (bouton
  NOUVEAU VOYAGE ou R) remet maintenant l'installation en service.
- Vérifié : 65 tests PC, parité PC ↔ PWA, bancs défi (dont la levée
  refusée en ligne), pannes, portes, aiguillage, salle des machines,
  rupture.

**v1.15.51** — élasticité du câble en marche.
- **Ta question** : « est-ce que tu es capable de reproduire la physique de
  l'élasticité du câble en fonction de la longueur déroulée, de la masse
  de la rame et des variations de vitesse ? » ; et ton observation : « la
  rame oscille déjà au ralenti quand elle rentre, pas juste après
  l'arrêt, et quand elle part du bas elle oscille aussi à
  l'accélération ».
- **Modèle** (PC et PWA, identiques) :
  - le mouvement calculé jusqu'ici devient celui du câble **à la poulie
    motrice**, celui que mesure le codeur et que pilote le régulateur ;
  - chaque rame pend au bout de son brin, comme à un ressort dont la
    raideur dépend du câble déroulé jusqu'à la poulie : k = EA/L ;
  - elle s'en écarte quand la poulie accélère :
    m·x″ = −k·x − c·x′ − m·a_poulie, avec m = rame + 1/3 de la masse du
    brin, et un amortissement de 0,15.
  - Le contrepoids a son propre ressort.
  - Chiffres (`audit_physique/elasticite_cable.sage`) :
    - 3 450 m de câble en bas : période de 7,0 s (rame vide) à 8,7 s
      (rame pleine) ;
    - 25 m en haut : moins d'une seconde, quelques millimètres ;
    - à 0,30 m/s², la rame pleine en bas traîne de 58 cm derrière la
      poulie.
- **Ce qu'on voit maintenant** :
  - **départ du bas** : la rame traîne d'une soixantaine de centimètres
    et oscille de ±10 cm pendant l'accélération, puis rattrape la poulie
    en fin d'accélération ;
  - **entrée en gare basse** : quand le freinage cesse et que la rame
    passe au ralenti, elle oscille de ±35 cm environ, avant même
    l'arrêt ;
  - **en haut** : pratiquement rien.
  - Le rebond après l'arrêt n'est plus une formule posée : c'est la même
    oscillation, quand le tambour bloque la poulie. Le mode auto attend
    toujours que les deux rames soient stabilisées (< 2 cm) avant
    d'ouvrir les portes.
  - La jauge de tension inclut l'effort élastique (la rame en retard
    tire plus).
  - La vue 3D (PC et PWA) et la vue cabine 2D montrent la position
    réelle de la rame ; la machinerie tourne avec la poulie, régulière.
  - À la rupture du câble, la rame libérée part de sa position et de sa
    vitesse réelles.
- **Corrigé au passage** : tambour serré, la poulie glissait de
  ~1 mm/s sous la pente (sa position était intégrée avant le tambour). Le
  rebond, qui réécrivait la position, masquait ce glissement.
- Vérifié : 64 tests PC, dont 5 nouveaux (`tests/test_elasticite_cable.py`
  et la période d'oscillation conforme au calcul SageMath) ; parité PC ↔
  PWA (5 voyages types, tension à quelques dizaines de daN près) ; bancs
  pannes, portes, défi, auto, aiguillage, salle des machines. Le banc de
  rupture échoue de temps en temps sur la position du bout de câble à
  0,1-0,3 m près, comme avant ce changement.

**v1.15.50** — numéros des supports dégagés du câble et des plots.
- **« Le câble masque les chiffres maintenant quand il est présent »** :
  à 19 cm de l'axe (v1.15.49), la plaque était juste derrière le second
  brin, qui passe à 12 cm. Elle revient au bout droit de la traverse,
  à 29 cm de l'axe (« juste avant le bord »), à droite du brin et de son
  galet. Pour que les plots ne la masquent plus (v1.15.48), elle est
  **surélevée sur un potelet** : son bas 2 cm au-dessus du dessus des
  plots, son haut sous le champignon du rail. Vue du poste, ni les plots
  ni le câble ne passent plus devant. Même règle pour les deux voies de
  l'évitement, et toujours à gauche dans les virages à droite.
- Seule la face tournée vers le lecteur est bleue et réfléchissante ; le
  dos est en métal nu (le dos des plaques de l'autre sens ressemblait à
  un numéro sans chiffres). Chiffres de 10 cm sur une plaque de
  25 × 14 cm.
- Vérifié sur captures depuis le poste (avec et sans le second brin, en
  ligne droite et en virage à droite) et en vue plongeante ; aucun trou ;
  bancs aiguillage, salle des machines, portes, rupture.

**v1.15.49** — numéros des supports plus gros, visibles et réfléchissants.
- **Plus gros et rentrés vers l'intérieur** (« faudrait les faire plus
  gros, et un peu décalés vers l'intérieur car ils sont masqués par les
  traverses ») : chiffres de 11 cm (7 avant) sur une plaque de
  30 × 15 cm, à 19 cm de l'axe (29 avant). La plaque est maintenant dans
  le couloir libre entre les deux rangées de plots, sous les galets, son
  haut au ras de la traverse.
- **Vraiment rétroréfléchissants** (« pas franchement réfléchissants
  quand éclairés par les phares ») : reflet beaucoup plus fort et qui
  porte plus loin (×1 à 80 m, ×20 de près). Le fond bleu est plafonné
  pour rester bleu, sinon la plaque devenait blanche et les chiffres
  illisibles. Les plaques restent visibles jusqu'à 300 m : on voit au
  fond du tunnel une file de points bleus qui brillent dans les phares.
- Vérifié sur captures depuis le poste (phares seuls, tunnel éteint) et
  en vue plongeante ; bancs aiguillage, salle des machines, portes,
  rupture.

**v1.15.48** — la voie comme sur la vidéo : fosse centrale, hauts plots,
supports numérotés réfléchissants.
- **« Le plancher entre les traverses au milieu de la voie, faudrait le
  baisser de 70 cm »**, d'après ta vidéo 4K de la montée du 26/04 (vue
  plongeante depuis le nez) : les rails reposent sur de hauts plots en
  béton. Le fond, entre les deux rangées de plots et entre les plots
  eux-mêmes, est maintenant 70 cm sous l'ancienne dalle, et la longrine
  est au fond. La fosse suit chaque voie dans l'évitement, et remonte au
  niveau de la dalle juste avant la roue aval de la gare haute. Le bas du
  tube du tunnel et les joints annulaires s'arrêtent à la dalle (ils
  traversaient la fosse comme un faux plancher).
- **Plots tous les 1,51 m** (0,95 m estimés avant) : mesuré sur la
  vidéo, ils défilent à 5,25 Hz à 7,95 m/s.
- **Supports de galets** : cadres en acier galvanisé blanc qui enjambent
  la fosse (traverse sous les galets, pieds jusqu'au fond).
  - Positions (faits de Kevin) : aucun support en gare aval ; le n° 1
    est au bout du quai aval, le n° 238 (dernier numéroté) au début du
    quai amont, soit 238 supports au pas de 14,54 m, plus ceux de
    l'aiguillage. La gare amont garde trois supports non numérotés.
  - Numéros blancs sur plaque bleue, **rétroréfléchissants** : invisibles
    dans le noir, ils s'allument dans les phares (vue cabine).
  - En montant : numéros pairs (2 → 238), sur la face tournée vers la
    rame montante, à droite juste avant le bout de la traverse, à gauche
    dans les virages à droite.
  - En descendant : numéros impairs (237 → 1), même règle vue de la rame
    descendante.
- **Le pas est vérifié sur la vidéo** (question de Kevin : « la vitesse
  de croisière de 10,1 m/s corrobore-t-elle cet écartement ? ») :
  - l'écran du pupitre indique 1 910 m à 30 s et 2 387 m à 90 s, soit
    7,95 m/s (il affiche 7,9 m/s) : ce jour-là, la croisière était de
    8 m/s ;
  - les supports défilent à 0,55–0,57 Hz (analyse de fréquence sur 60 s,
    harmonique à 1,13 Hz, coupe temporelle), soit 14,0 à 14,5 m ;
  - la plaque n° 174 passe à ~2 516 m, et 51,5 + 173 × 14,2 ≈ 2 508 m.
  À 10,1 m/s, le même rythme donnerait 18 m et seulement ~190 supports.
- Coût de rendu : chiffres plats à contours simplifiés (59 triangles par
  chiffre au lieu de 1 864 : 44 000 triangles par image sinon), effacés
  au-delà de 120 m.
- Outils : `shot_voie.gd` (vue plongeante sur la voie depuis le nez,
  fond magenta pour révéler les trous).
- Vérifié : bancs aiguillage, salle des machines, rupture, son salle,
  portes, pannes, rame ; aucun trou (fond magenta) en gare aval, en
  pleine ligne, dans l'évitement et en gare amont ; 60 tests PC.

**v1.15.47** — évitement : plus de lueur fantôme, même habillage que le
reste du tunnel ; arrêt électrique actif jusqu'au quai.
- **« Une deuxième rangée de néons qui font une lumière fantomatique dans
  le noir »** : les réglettes de l'évitement (tous les 8 m de chaque
  côté, à 1,15 m) avaient leur propre matériau lumineux, que la touche J
  ne coupait pas. Elles s'éteignent désormais avec l'éclairage du
  tunnel. Vérifié : tout éteint à l'entrée de l'évitement, le 99e
  centile de luminance passe de 93 à 0.
- **« La section de l'évitement, l'habillage du tunnel est différent »** :
  les joints annulaires et la canalisation de voûte s'arrêtaient 60 m
  avant l'évitement et ne reprenaient que 60 m après, soit 320 m de
  paroi nue. Ils continuent maintenant partout :
  - les joints suivent chaque tube, y compris là où les deux tubes se
    rejoignent (seul l'arc qui borde le vide est dessiné) ;
  - la canalisation suit la voûte droite du tube droit.
- **« En mode normal, au ralenti en entrant en gare, l'arrêt électrique
  est inopérant »** : sur les 55 derniers mètres, le régulateur imposait
  la vitesse de rampement (0,75 m/s) sans regarder la consigne. L'arrêt
  électrique ramenait bien la consigne à 0, mais la rame rampait jusqu'au
  quai. L'arrêt électrique (et la veille) prime maintenant : arrêt en
  ~1 m, puis tambour serré comme ailleurs en ligne. Tests
  `tests/test_arret_electrique.py` : échouent sur la v1.15.46 (la rame
  roule encore à 0,75 m/s dix secondes après), passent maintenant ; le
  quai est toujours atteint à 0,5 m près sans arrêt électrique.
- Vérifié : 60 tests PC, bancs aiguillage, son salle, portes, pannes,
  rame, salle des machines et rupture ; captures de l'évitement.

**v1.15.46** — noir total pour de vrai, phares de « pleins phares »,
pupitre éteint avec la cabine.
- **« Noir, ça veut dire qu'on ne voit rien du tout, même à 1 m »** :
  quatre sources de lumière restaient, trouvées sur captures en rendu
  PWA (Chromium sur le GPU du NAS) et en rendu PC (Forward+) :
  1. un **soleil** (lumière directionnelle sans ombres) éclairait parois,
     voie et pupitre dans tout le tunnel (« y a pas de soleil, c'est un
     tunnel ») → supprimé. Il ne reste qu'une lumière propre à la vue
     extérieure, qui n'éclaire que les rames et la voie ;
  2. 🔴 **le pare-brise de la voiture de tête n'était pas sur la bonne
     surface** depuis le 27/09 : il avait été posé sur la cloison du
     soufflet. Le conducteur regardait donc à travers la vitre des
     fenêtres, teintée et lumineuse, ce qui faisait un voile brun sur
     toute la vue en rendu PC. Le pare-brise est maintenant à sa place,
     avec la même teinte, mais sans lumière propre ;
  3. la petite lampe du pupitre restait allumée en permanence ;
  4. la lumière de la cabine éclairait aussi le tunnel autour de la
     rame. Désormais, les lumières de la cabine n'éclairent que la rame
     (couche de rendu dédiée), et les reflets du ciel sont coupés avec
     l'éclairage du tunnel.
  Tout éteint, l'image fait 1/255 de luminance moyenne dans la PWA,
  contre 101 avec tout allumé.
- **Pupitre et éclairage cabine** (« le pupitre est éclairé par la
  cabine sauf si l'éclairage cabine est off, alors on ne voit que les
  écrans et les boutons allumés ») :
  - en 3D, un plafonnier du poste et la lampe du pupitre suivent la
    touche C, ainsi que la lueur des fenêtres vue de l'extérieur ;
  - dans la vue cabine 2D du PC, l'habillage s'assombrit et ne laisse
    que les écrans et les voyants.
- **Phares** (« plus de puissance, mais pas de halo central plus
  brillant que le reste, comme des pleins phares de voiture ») : le
  cône de 32° dessinait un rond lumineux net au bout du tunnel. Le
  faisceau fait maintenant 75° (plus large que la vue par le
  pare-brise), il est homogène, porte loin et éclaire presque à
  l'horizontale ; énergie 12. Il éclaire peu le brouillard de la vue PC.
- **Vue 2D du PC** : avec l'éclairage du tunnel coupé, le fond est noir
  et les parois ne sont plus dessinées ; si les phares sont aussi
  éteints, plus rien n'est tracé (sauf en gare). La fenêtre latérale
  devient noire.
- Outils : `shot_noir.gd` (captures et liste des lumières et vitres
  devant la caméra) ; la PWA d'essai accepte `--s=<m>` avec
  `--drivetest`.
- Vérifié : 57 tests PC, bancs son salle, portes, pannes, rame, salle
  des machines et rupture ; captures PWA, PC Forward+ et vue 2D.

**v1.15.45** — tout le son sur la même sortie, tunnel dans le noir total.
- **Son partagé entre haut-parleurs et casque** (« l'ambiance est dans les
  haut-parleurs, les annonces et le reste dans le casque ») : sous Qt, les
  boucles d'ambiance et de machinerie (QSoundEffect) restent sur la sortie
  audio trouvée au lancement, alors que les annonces (QMediaPlayer)
  suivent la sortie par défaut du système. Brancher ou choisir le casque
  après le lancement coupait donc le son en deux, et le bruit de la
  machinerie qui accélère partait dans les haut-parleurs. Désormais, tous
  les lecteurs suivent la sortie par défaut : réalignement immédiat sur
  changement de périphérique, et contrôle toutes les 2 s. Le diagnostic
  liste les sorties utilisées (`sorties_lecteurs`). Test :
  `test_tous_les_lecteurs_sur_la_meme_sortie`.
- **Éclairage coupé = noir total** (« le tunnel doit être dans le noir
  total, là on le voit ») : lumière ambiante et teinte du brouillard à 0
  (au lieu de 0,03 et 0,05). Le ciel ne se reflète plus sur les parois.
  En qualité haute (vue 3D du PC), l'illumination globale SDFGI et le
  brouillard volumétrique sont éteints aussi. Il ne reste que les phares,
  l'éclairage cabine (C) et les gares. Vue cabine dessinée du PC : sans
  néons ni phares, plus rien n'est tracé au-delà de 2,5 m.
- Vérifié : 57 tests PC, bancs 3D son salle, portes, pannes et rupture ;
  PWA dans Chromium sur GPU.

**v1.15.44** — couper l'éclairage du tunnel, boutons rangés par thème,
séquence auto corrigée.
- **Couper l'éclairage du tunnel** (touche **J**, bouton ÉCL. TUNNEL au
  pupitre PC, bouton TUNNEL sur la PWA) : « rajoute l'option de couper
  tous les éclairages du tunnel ». En 3D, les néons s'éteignent (sources
  et tubes). La lumière ambiante descend de 0,40 à 0,03 et la teinte du
  brouillard de 1 à 0,05, sans quoi le fond du tunnel restait gris. Il ne
  reste que les phares, l'éclairage des gares, de la salle des machines et
  de la cabine. Vérifié dans la PWA (Chromium sur GPU) : le tunnel est
  noir, seul le faisceau des phares éclaire la voie. Sur le PC, la vue
  cabine dessinée n'a plus ses tubes, et l'état est transmis à la vue 3D
  (`tunnel_lights`).
- **Boutons rangés par thème** (« mets tout ce qui se rapporte aux
  lumières ensemble, fais un tri des boutons pour que tout soit
  cohérent ») :
  - pupitre PC en cinq rangées : sécurité (arrêt électrique, urgence,
    veille), éclairage (phares, cabine, tunnel), exploitation (portes,
    pilote auto, klaxon), vues (vue 3D, cycle des vues), système (son,
    aide) ;
  - « CABINE [C] » (lumière) et « CABINE [O] » (vue) se confondaient :
    ils deviennent « ÉCL. CABINE » et « VUE CABINE » ;
  - PWA : rangée du haut en trois blocs, conduite (INVERSER, AUTO),
    lumières (PHARES, CABINE, TUNNEL) et affichage (VUE, ANNONCES). Le
    bouton CABINE est nouveau, avec la touche C. Les trois boutons de
    lumière s'allument en vert quand la lumière est allumée. La rangée est
    ancrée par son bord droit, et ANNONCES ne déborde plus de l'écran.
  - Aides clavier (PC F1, bandeau PWA) : H, C et J regroupés.
- **Séquence auto** (« bug dans la séquence auto — c'est quand on passe
  du mode manuel à auto après un trajet ; au deuxième cycle ça marche ») :
  au passage en auto, la rame était encore tournée vers la gare où elle
  venait d'arriver. L'automate l'y « renvoyait » : fermeture des portes,
  buzzer, « Départ », arrivée instantanée, puis seulement le demi-tour. Il
  la retourne maintenant avant tout embarquement
  (`AutoOps._begin_boarding`). Un test reproduit le cas : il échoue sur
  l'ancien code (départ dans le sens +1 depuis le haut) et passe
  désormais. La PWA n'était pas touchée, car sa physique fait elle-même
  le demi-tour à chaque arrivée.

**v1.15.43** — plus de feux rouges, « TIGNES » lisible en entier.
- « Enlève-moi le feu rouge à l'arrière des rames et le reflet/halo rouge
  qui va avec. » Trois sources ont été retirées :
  - le projecteur rouge de la rame pilotée (énergie 3, portée 80 m), qui
    teintait cerceaux et rails derrière elle ;
  - la lumière rouge placée au centre de la rame d'en face (portée 12 m) ;
  - les feux arrière rouges émissifs, à l'origine du halo par effet de
    lueur. Les feux arrière sont désormais des lentilles éteintes, comme
    sur la rame pilotée.
- « Écris bien TIGNES, le haut des lettres du milieu est un peu mangé. »
  Le mot était un seul panneau vertical posé devant le nez. Sous le
  centre de la calotte bombée, la tôle avance au-dessus du lettrage, et le
  haut du « G » et du « N » passait derrière. Chaque lettre est maintenant
  posée tangente à la calotte, à sa place, 1,2 cm devant
  (`_build_lettering`, `cap_surface_normal`). La calotte étant convexe,
  aucune lettre ne passe dessous, et le mot suit la courbure comme des
  lettres peintes. Captures avant/après : `shot_nez.gd` (avant et
  arrière).

**v1.15.42** — le simulateur PC pour Linux et macOS.
- Demande de Kevin : « sur GitHub, tu peux me builder les exécutables pour
  Linux toutes distributions et Mac ? » Chaque release publie désormais,
  à côté de l'installeur Windows :
  - `PerceNeigeSimulator-X-linux.AppImage`, avec en secours la même
    application en `…-linux-x86_64.tar.gz` ;
  - `…-macos-apple-silicon.dmg` et `…-macos-intel.dmg` ;
  - `SHA256SUMS`.
- **Linux** : PyInstaller en dossier autonome, construit dans `almalinux:9`
  (glibc 2.34). C'est le plancher des roues PyQt6 ≥ 6.10, et Linux garde
  ainsi la même version de Qt (6.11) que Windows. Les distributions
  couvertes sont toutes celles encore suivies : Ubuntu ≥ 22.04,
  Debian ≥ 12, Fedora, RHEL ≥ 9, Mint ≥ 21, Arch, openSUSE. Les
  bibliothèques que Qt réclame sans qu'elles soient toujours installées
  (libxcb-cursor, absente d'une Ubuntu de base) sont embarquées. L'AppImage
  utilise le runtime statique, qui fonctionne sans libfuse2. À chaque
  version, le job `essai-linux` la lance sur Ubuntu 22.04 et 24.04,
  Debian 12, Fedora 41, Arch et openSUSE Tumbleweed : le démarrage est
  vérifié sous un serveur X virtuel, sans plugin Qt manquant, et les
  bibliothèques du viewer 3D aussi. La vue 3D a été vérifiée à l'image
  sous Ubuntu 24.04.
- **macOS** : application `.app` (PyInstaller) dans un `.dmg`, construite
  sur les runners `macos-15` (Apple Silicon) et `macos-15-intel`. Le viewer
  3D est le nouvel export Godot « macOS » : binaire universel, signature ad
  hoc, recopié avec ditto. Tout le paquet est signé ad hoc, ce qui est
  obligatoire sur Apple Silicon. Essais sur le runner : le simulateur
  démarre, le viewer s'exécute (`--headless --quit`), et une capture de la
  vraie fenêtre Cocoa est publiée en artefact. Non signé par un développeur
  Apple : au premier lancement, clic droit → Ouvrir.
- **Viewer 3D depuis l'AppImage** : il plantait au démarrage (signal 11).
  Le lanceur de PyInstaller place ses propres bibliothèques dans
  `LD_LIBRARY_PATH`, et le viewer en héritait, ce qui le faisait charger
  la libstdc++ et la libX11 d'AlmaLinux au lieu de celles qui vont avec le
  Mesa du système. `godot_bridge` lui rend l'environnement d'origine
  (`*_ORIG`).
- AppImage et `.app` sont en lecture seule : sous Linux et macOS, les
  fichiers temporaires vont dans `~/.cache` ou `~/Library/Caches`. Le
  message « nouvelle version » indique le fichier à télécharger pour la
  plateforme.
- Godot : le projet importe aussi les textures ETC2/ASTC, une condition de
  l'export macOS universel. Le projet n'a que 5 textures, et l'export Web
  n'est pas concerné.
- Scripts réutilisables en local : `packaging/build_linux.sh`,
  `build_macos.sh`, `essai_distributions.sh`, `perce_neige_unix.spec`.

**v1.15.41** — rupture : le câble se détend aussi dans la salle des
machines, et le tronçon de la rame la suit.
- Retour de Kevin sur la 1.15.40 : « il reste tendu dans la salle des
  machines, et le bout cassé attaché à la rame emballée devrait avancer
  avec elle, alors que là tout reste à l'arrêt ».
- **Salle des machines** : le câble autour des roues avait sa propre
  géométrie, restée tendue. Il se détend désormais avec celui du tunnel.
  Il ne reste porté que là où quelque chose le tient : la moitié haute des
  jantes (il repose dans la gorge), les galets du brin de sortie et la fin
  de voie. Les brins croisés entre les deux roues retombent, ainsi que les
  tours sous les roues. Chaque point descend jusqu'à 1,2 m, au plus
  jusqu'au sol de la fosse ou jusqu'au haut d'une roue (il ne traverse
  rien). Les portées droites sont redécoupées tous les 40 cm pour pouvoir
  retomber.
- **Le tronçon accroché à la rame la suit dans les deux sens.** La 1.15.40
  ne le faisait que lorsque la rame tirait dessus en reculant. Si la rame
  file encore sur son élan, elle pousse le tronçon, qui bute à 60 cm du
  bout haut ; les deux bouts à vif restent visibles, et la brèche se
  rouvre dès qu'elle repart en arrière. (En réalité, un câble poussé
  s'entasse devant la rame : sans cette butée, le tronçon rattrapait le
  bout haut en 0,3 s et la cassure disparaissait.)
- Les ondulations du câble lâche appartiennent au câble : elles avancent
  avec le tronçon que la rame entraîne au lieu de rester fixes sur la voie,
  qui donnaient l'impression que « tout reste à l'arrêt ».
- Banc `bench_rupture_3d.gd` : salle des machines détendue puis rétablie ;
  tronçon poussé, sans jamais passer le bout haut ; tronçon tiré qui suit
  la rame. `shot_rupture.gd` capture aussi la salle vue de côté.

**v1.15.40** — rupture du câble : il casse, se détend, la machinerie
s'arrête.
- Retour de Kevin : « quand le câble casse, il doit se détendre, casser
  quelque part et la machinerie doit s'arrêter, là elle s'emballe ». Les
  roues de la salle des machines, le panneau du HUD et le son de la
  machinerie suivaient la vitesse de la rame pilotée, câble rompu ou non.
  La rame décrochée dévale en accélérant, donc la machinerie
  « s'emballait » avec elle. Le câble, lui, restait entier et tendu.
- **Machinerie** : nouvelle grandeur `machine_v`, la vitesse du câble à
  la poulie motrice. Câble intact, elle suit la rame. Câble rompu, la
  chaîne de sécurité coupe l'entraînement et les freins des roues
  l'arrêtent à 2 m/s² (`A_DRIVE_TRIP`) : 6 s depuis 12 m/s, 7,2 s depuis
  14,4 m/s, la survitesse du mode Défi. La règle vaut pour la 3D, le
  panneau du HUD, le son de la machinerie, et sur le PC pour les poulies
  2D, le régime affiché et le son. Les panneaux affichent « CÂBLE ROMPU —
  freinage des roues », puis « … machinerie à l'arrêt ».
- **Le câble casse quelque part** : sur le brin de la rame pilotée,
  25 à 80 m devant elle quand elle monte (en vue du conducteur), 20 à
  50 m derrière quand elle descend. Les deux bouts se rétractent de leur
  allongement élastique ε·L, à la vitesse ε·c de l'onde de détente
  (c = √(EA/ρ) ≈ 3 400 m/s). En haut, c'est quelques mètres, sur 2 km de
  câble. Les fils d'acier sont à vif (clairs et brillants) sur 25 cm à
  chaque bout. Le bout bas suit sa rame quand elle tire dessus en
  reculant ; un câble ne se pousse pas, donc si la rame continue de
  monter sur son élan, le bout reste où il est.
- **Le câble se détend** : toute la longueur retombe des galets sur la
  longrine en 0,18 s (chute libre de 16,4 cm). Elle s'y pose en
  serpentant doucement, avec des boucles plus larges près des bouts
  fouettés. Le tube du câble a maintenant un anneau tous les 2 m (avant,
  il était droit d'un galet à l'autre) ; descente et ondulation sont
  calculées dans le shader.
- **L'autre rame reste clouée** par son parachute, et son brin ne défile
  plus. Côté PC, la rupture n'était même pas transmise à la vue 3D : la
  rame d'en face continuait en miroir, le câble restait intact. Le PC
  envoie maintenant `cable_rupture` et la position figée de l'autre rame
  (`ghost_s`).
- Chiffres vérifiés dans `audit_physique/rupture_cable.sage` (onde de
  détente, chute, rétraction, arrêt de la machinerie). Nouveau banc
  `bench_rupture_3d.gd`, avec deux cas : panne avec parachute (rame
  retenue), et Défi sans urgence (la rame redescend et traîne son bout de
  câble, la machinerie reste arrêtée). Le banc son vérifie que la
  machinerie se tait. Côté PC, un test vérifie l'arrêt de la machinerie
  dans le temps prévu et l'envoi à la 3D. Captures : `shot_rupture.gd`.

**v1.15.39** — le son de la salle des machines arrive enfin sur le PC.
- « Sur la PWA il y a le son d'ambiance de la salle des machines, mais pas
  sur l'app PC : on entend les annonces, pas l'ambiance. » La cause : la
  mise à jour automatique du PC télécharge une archive allégée, et le kit
  en retirait le dossier `sons/` (`exclus_de_la_maj`), parce qu'il était
  censé ne jamais changer. Les deux boucles de la salle des machines,
  ajoutées en 1.15.34, ne sont donc jamais arrivées sur un PC mis à jour
  par l'application. En vue salle des machines, le son de cabine s'effaçait
  quand même, devant des lecteurs qui ne pouvaient pas démarrer : il ne
  restait que les annonces.
- L'archive de mise à jour contient de nouveau tout le dossier `sons/`
  (46 Mo de plus). Le programme de mise à jour remplace ce dossier en
  entier, annonces comprises, si bien que tout fichier ajouté depuis
  l'installation arrive cette fois.
- Garde-fou : si les sons de la salle manquent, la vue salle des machines
  garde le son de cabine au lieu de tout couper. Le diagnostic son signale
  `fichiers_presents`. Un test vérifie que la cabine reste audible quand
  un fichier manque.

**v1.15.38** — la rame ne tremble plus, phares sans éblouissement, roues
régulières au ralenti.
- « Tremblements excessifs de la rame quand elle roule. » Pour comprendre,
  la caméra de cabine a été relevée image par image, à 12 m/s, sur toute la
  ligne. La trajectoire elle-même ondulait : `Curve3D.sample_baked`
  interpole entre des points précuits tous les 0,5 m, et leur espacement
  est retouché à chaque segment de la courbe. Il en restait une ondulation
  de quelques millimètres. Elle donnait une accélération apparente de
  18 m/s² en médiane, alors que la vraie, dans les courbes, vaut environ
  0,1 m/s², avec des secousses de tangage entre 14 et 30 Hz. La caméra
  était accrochée au centre de la rame, à 15 m de là, et ce bras de levier
  amplifiait chaque écart d'orientation.
- `transform_at` lit maintenant une B-spline cubique uniforme. Elle est
  construite sur des points pris tous les 1 m, chacun moyenné sur 0,4 m
  pour gommer l'ondulation des points précuits. La courbe obtenue est
  continue jusqu'à l'accélération. Résultat : accélération apparente de la
  trajectoire 18 → 1,2 m/s² (le reste est l'arrondi des flottants
  32 bits à 3 km de l'origine), tangage parasite 0,36 → 0,04 °/s. Tous
  les bancs 3D passent.
- La caméra, les phares et le poste de conduite sont maintenant portés par
  la voiture de tête, comme la coque. La caméra se déplaçait jusqu'à 39 cm
  en travers et 9 cm en hauteur par rapport à la caisse dans les courbes.
  Elle est désormais fixe au millimètre.
- « Le halo central des phares fait un reflet aveuglant. » Le phare avait
  une énergie de 14, un cône de 38° concentré sur l'axe et une atténuation
  de 0,4, soit presque aucune perte avec la distance. Il surexposait le fond
  du tunnel pile au point de fuite. Captures à l'appui (`shot_phares.gd`,
  qui accepte des réglages en argument), le nouveau réglage est : énergie 5,
  faisceau plus homogène, atténuation 0,8, cône de 32°, phare braqué 6°
  vers la voie. La luminance au centre de l'image baisse de 65 % et la voie
  reste éclairée.
- « Au ralenti à l'arrivée, la rotation n'est pas complètement fluide. »
  La vitesse physique est parfaitement régulière : 0,75 m/s constants, sans
  à-coup. La cause est ailleurs. L'angle des roues et la phase du câble
  s'accumulaient sans fin, environ 1 700 rad et 3,5 km par trajet, et
  passaient au processeur graphique en flottants 32 bits. À 3 000 rad, le
  pas de ces flottants vaut 15 % du pas d'une image à 0,2 m/s. Ils sont
  désormais ramenés dans leur période, 2π pour les roues et 0,45 m (le pas
  du toronnage) pour le câble, ce qui ne change rien à l'image. Le banc
  vérifie qu'ils restent bornés après 4 km.
- La caméra de la salle des machines refaisait à chaque image son lancer de
  rayon (jusqu'à 500 pas) et l'écorché, même immobile. Ils ne sont refaits
  que si la vue bouge. Dans Chromium, la vue salle des machines passe de
  4,7 à 3,2 ms par image.

**v1.15.37** — la PWA coûte deux fois moins par image, roues dans le bon
sens, cabine dézoomée.
- « Ça saccade toujours le défilement du tunnel. » Pour mesurer au lieu de
  deviner, la PWA tourne maintenant dans Chromium sur le vrai processeur
  graphique du NAS (Radeon 740M), à la définition de l'iPad (2752 × 2064)
  et avec son agent utilisateur : conduite d'essai, durée de chaque image,
  profil du processeur. Une image coûtait 6,6 ms sur le fil principal
  (9,6 ms au 99ᵉ centile). Sur l'iPad, Safari est plus lent : on frôlait
  les 16,7 ms, d'où une image en retard de temps en temps.
- Cause n° 1, 13 % du temps : le moteur Web de Godot dessine dans un
  tampon hors écran puis le recopie dans la page à chaque image. La copie
  commence par deux lectures d'état qui attendent le processeur graphique,
  et elle oblige le navigateur à conserver l'image (`preserveDrawingBuffer`).
  `web_patch.py` retouche l'export pour dessiner directement dans la page.
  Le rendu est identique : cabine, vue extérieure et salle des machines
  ont été vérifiées sur captures.
- Cause n° 2 : les deux grands panneaux du HUD (console du bas et salle des
  machines) représentaient environ 220 appels de dessin et 1 500 éléments
  2D à chaque image, pour un contenu qui ne change que 15 fois par seconde.
  Ils sont maintenant rendus dans une image intermédiaire, à la définition
  réelle de l'écran pour que le texte reste net. Celle-ci n'est redessinée
  qu'à leur cadence, avec un décalage entre les deux panneaux.
- Cause n° 3 : la rame comptait 403 objets 3D (456 surfaces). Les pièces
  fixes de chaque voiture sont fusionnées par matériau (`MeshMerge`) ; les
  roues, les vantaux et les feux restent animés. On passe à 169 surfaces
  pour la rame pilotée et de 286 à 137 pour la rame d'en face. Les vitres
  ne sont pas fusionnées, pour que le tri de la transparence reste juste.
- Résultat dans Chromium : 3,2 ms par image au lieu de 6,6 (5,2 ms au
  99ᵉ centile au lieu de 9,6). Reste à surveiller : un à-coup unique de
  50 à 100 ms quand un matériau apparaît pour la première fois (compilation
  de son shader par le navigateur).
- Roues de la salle des machines : elles tournaient avec v × sens de
  marche, une valeur toujours positive en marche. Elles tournaient donc
  toujours dans le même sens, qu'on monte ou qu'on descende, avec la
  rame 1 ou avec la rame 2. Le sens suit maintenant la rame 1 : son brin
  entre par le haut de la roue aval quand elle monte (`v_rame1`). La règle
  s'applique à la 3D, au panneau du HUD et aux poulies du PC. Le banc
  vérifie les quatre cas (rame 1 ou 2, montée ou descente).
- Vue cabine : champ de vision porté de 70 à 78° (« on dirait que t'as
  zoomé »).
- Outils : `tests/web_perf_export.sh` (export instrumenté, option
  `--masquer=hud,cabin,…` pour mesurer un groupe), `tests/web_perf.py` et
  `web_perf_stats.py`, `tests/web_profile*.py`, et `shot_cabine.gd`
  (captures avec ou sans fusion, `--sans-fusion`). `perf_groupes.gd`
  compte maintenant aussi les appels de dessin, les objets et le HUD.

**v1.15.36** — le son revient dans la PWA sur Android.
- Retour de Kevin : « 0 son sur la PWA sur Android ». Reproduit dans
  Chromium, avec l'agent utilisateur d'Android et la sortie son enregistrée
  sur un serveur audio virtuel. La 1.15.35 donnait un silence numérique
  total, la 1.15.33 jouait normalement (ambiance −44 dB, buzzer −23 dB).
  La cause : le bus audio « Cabine », créé à l'exécution par la 1.15.34
  pour effacer le son de cabine en vue salle des machines. Sur Chrome, la
  PWA joue ses sons en échantillons Web Audio, et ce bus ajouté en cours
  de route rendait toute la sortie muette. Le Safari de l'iPad, qui mixe
  lui-même, n'était pas touché.
- Plus aucun bus n'est créé. Le fondu cabine ↔ salle des machines passe
  par une atténuation ajoutée au volume de chaque son de cabine (boucles,
  ventilation, croisement). Après correction, dans Chromium : ambiance
  −44 dB, buzzer −27 dB, salle des machines −24 dB en vue O. Le banc
  vérifie qu'aucun bus n'est créé.
- Au passage, le script de rapports d'erreur de la PWA ne s'exécutait plus.
  Sa parenthèse « abort\( » perdait son antislash à l'export, ce qui
  rendait l'expression régulière invalide. Elle est remplacée par
  « abort[(] », et les rapports d'erreur de la PWA fonctionnent de nouveau.
- Outil : `tests/pwa_son_chromium.py` ouvre la PWA dans Chromium, clique,
  appuie sur des touches et laisse enregistrer la sortie son.

**v1.15.35** — fluidité de la 3D, roue aval dégagée, frein à bande.
- « Le défilement du tunnel saccade » dans la PWA, ainsi que la rotation en
  vue salle des machines. La vidéo d'écran de l'iPad (120 Hz) montre qu'une
  image sur neuf arrive en retard : 25, 33 ou 42 ms au lieu de 16,7 ms. Le
  script n'est pas en cause : sans rendu, la scène tourne à plus de 4 000
  images par seconde. Le dessin, lui, l'était : 1,72 million de triangles
  par image en vue cabine.
- La cause : les éléments répétés le long de la ligne (joints annulaires du
  tunnel, escalier de service, blochets, galets) formaient chacun UN bloc
  couvrant 3,5 km. Godot ne peut pas écarter un tel bloc, donc la carte
  graphique traitait à chaque image toute la ligne, derrière la caméra
  comprise. Les seuls joints pesaient 936 000 triangles.
- La correction : ces éléments sont découpés en tronçons de 100 m, que
  Godot écarte hors champ. Les petits détails s'effacent au-delà de 150 à
  500 m. Les joints passent de 480 à 192 triangles, et les roues de la rame
  d'en face ne sont plus dessinées au-delà de 150 m. Au même endroit (vers
  1 450 m, à 12 m/s), l'image passe de 1,72 million à 357 000 triangles,
  soit 79 % de moins.
- « Dans la roue aval, une sorte de mur en béton ». Trois éléments
  traversaient la roue : la fin du caisson de la gare haute, la dalle de
  voie et la longrine du câble. Le caisson de la gare, dont le sol est à
  −2,65 m, s'étendait jusqu'au bout de la voie, au-dessus des 2,6 premiers
  mètres de la salle des machines. Désormais, ses derniers anneaux
  s'arrêtent sous la dalle ; la dalle de voie et la longrine s'arrêtent au
  bord de la fosse ; la dalle du hall et le plafond de la salle sont
  découpés autour de la roue. Le banc vérifie maintenant, sur toute la
  surface des triangles, que rien ne traverse la roue. Il détecte bien
  l'ancien défaut.
- Frein de roue : les étriers entraient dans la jante. Une première
  correction avait ajouté un disque déporté, mais Kevin a précisé que c'est
  « une bande métallique sur laquelle les freins appuient, pas une
  excroissance ». La photo DSCN3579 le confirme. La joue extérieure de
  chaque roue est donc une bande d'acier affleurante. Deux étriers à vérin
  appuient dessus sous la roue, depuis l'extérieur, sur leur bâti vert, et
  le carter rouge s'interrompt à leur droit.
- Vérifié : tous les bancs passent, 53 tests aussi. Le rendu réel des freins
  et de la roue aval a été contrôlé.

**v1.15.34** — son de la salle des machines, fin du silence d'ambiance PC.
- Demande de Kevin : le son de la vue salle des machines doit venir de la
  vidéo « [FUNI284] Funiculaire du Perce-Neige, Tignes (marche complète à
  12 m/s) ». Elle a été filmée en août 2013, caméra fixe en gare haute sur
  la roue aval, et publiée par la chaîne « Transports câblés ». Sa machinerie
  donne une raie très nette, proportionnelle à la vitesse : 196 Hz à 12 m/s,
  soit 9,8 fois la rotation du moteur. Deux boucles sans couture en sont
  extraites : la salle au repos (22 s) et la machinerie à 12 m/s (16 s).
- La machinerie est jouée à la hauteur v/12, avec la loi de niveau mesurée
  sur l'enregistrement (`son_salle_machines.sage`) : amplitude ∝ (v/12)^0,42,
  +4,7 dB sur la salle au repos à 12 m/s. La hauteur est bornée à 3 m/s,
  parce que le lecteur de Qt décroche sous un débit de 0,22. En dessous, la
  machinerie passe 6 dB sous la salle au repos, donc l'écart ne s'entend
  pas. En vue salle des machines, le son de la cabine s'efface en 0,35 s.
  Le bus « Cabine » de la PWA sert à ce fondu.
- **Vraie cause du « silence total entre 0,2 et 1 m/s en décélération »**
  sur PC, enfin trouvée. C'est un bogue de Qt 6.11, reproduit sur un vrai
  serveur son : dès qu'un QSoundEffect joue à volume EXACTEMENT nul, tous
  les autres deviennent muets (−140 dB). Sous 1 m/s, la boucle de croisière
  jouait à volume 0 jusqu'à son arrêt à 0,2 m/s. Les rapports de diagnostic
  du PC de Kevin l'affichaient déjà : « croisière : joue, volume 0 » à
  0,74 m/s. Tous les QSoundEffect passent par une sous-classe qui garde un
  plancher de 0,0001, soit −80 dB, inaudible. La correction de la 1.15.30
  reste valable : elle atténue selon le niveau réel du clip de freinage.
- Au passage, on lit sur l'enregistrement réel une accélération de
  0,24 m/s² entre 6 et 11 m/s et un freinage de 0,43 m/s² entre 11 et
  3 m/s. Le simulateur utilise 0,30 m/s² en accélération. Rien n'est
  modifié, c'est noté pour information.
- Vérifié :
  - PC, sur une vraie sortie son : la raie enregistrée suit la vitesse à
    1,5 % près (médiane), la salle au repos reste audible, aucun trou ;
    +4,3 dB à 12 m/s (réel : +4,7).
  - PWA : banc `bench_son_salle_3d.gd`.
  - 53 tests, dont la non-régression du volume nul.

**v1.15.33** — parcours du câble dans la salle des machines, câble animé.
- Parcours décrit par Kevin, appliqué tel quel. Les deux roues sont
  ALIGNÉES latéralement, chacune avec une gorge gauche et une gorge droite,
  aux mêmes x que les deux brins de la voie. Vu vers l'amont :
  1. Le câble de la rame 1 entre sur le haut de la roue aval, gorge gauche.
  2. Il descend en bas de la roue amont, s'y enroule côté gauche et sort
     par le haut.
  3. Il descend en bas de la roue aval, s'enroule côté droit et sort par le
     haut.
  4. Il redescend en bas de la roue amont, s'enroule côté droit et sort en
     haut.
  5. Il passe sur deux galets au-dessus du sommet de la roue aval, entre les
     butoirs bleus, et file vers la rame 2.
- Mesures, calculées dans `salle_machines_cable.sage` :
  - l'enroulement total vaut 773° ;
  - aucun brin ne se décale latéralement, sauf le passage de la gorge
    gauche amont à la gorge droite aval (2,7°) ;
  - au croisement, 68 mm séparent les câbles ;
  - le brin de sortie passe 34 mm au-dessus des joues de la roue aval ;
  - ses galets gardent 23 mm de jeu avec la roue ;
  - il redescend ensuite à 1° jusqu'au dernier galet du tunnel.
  Dans le tunnel, le brin de la rame 2 remonte donc de 12 cm à la fin de
  voie pour rejoindre ces galets.
- « Les câbles ont l'air figés dans la salle des machines alors que ça
  tourne ». Le câble de la salle reçoit le même shader à torons que celui
  du tunnel, et il défile au pas de la jante. Le sens de rotation des roues
  était inversé quand on conduisait la rame 2 ; il suit désormais toujours
  la rame 1.
- Vérifié par le banc `bench_salle_machines_3d.gd`. Il contrôle les roues
  alignées, le jeu du brin au-dessus de la roue aval et celui des galets. Il
  contrôle aussi la position du dernier galet du tunnel, le raccord du brin
  de la rame 2 et le défilement du câble. Tous les bancs passent, 49 tests
  aussi.

**v1.15.32** — lacunes de l'aiguillage d'après les photos, roue amont
remontée.
- Retour d'essai sur le rendu de la 1.15.31 : les deux lacunes entourées
  étaient « à améliorer au vu des photos ». Les gros plans d'Hakone et de
  la photo de Kevin montrent que les deux bouts de rail sont PLIÉS pour
  courir côte à côte, parallèlement au câble, qui file droit dans le couloir
  entre eux. Dans la 1.15.31, les bouts suivaient la ligne de la roue et le
  câble les coupait en biais. Désormais, chaque bout arrive par un coude
  franc (3,6°) depuis la ligne de la roue, puis longe le câble à 8 cm sur
  1 m de chevauchement. Les bouts sont coupés francs avec un chanfrein,
  posés sur des plaques d'appui boulonnées, et une tôle de glissement sombre
  court sous le câble d'un coude à l'autre, 12 mm sous lui.
- Salle des machines, demande de Kevin : « remonter la roue motrice amont
  pour que la pente entre le sommet de la roue amont et celui de la roue
  aval soit celle de la voie en gare amont ». La roue amont est remontée
  d'1 m : les deux sommets sont alignés sur la pente de la voie. Le brin de
  sortie quitte désormais la roue amont par son sommet, au niveau de la
  voie, et file droit jusqu'à la voie. La batterie de galets en courbe
  disparaît, remplacée par deux galets porteurs. La roue amont dépasse de
  30 cm du sol du hall derrière les butoirs, dans la fosse prolongée, et un
  garde-corps jaune l'entoure. La salle perd 1 m de hauteur, et
  l'enroulement total passe de 780° à 774° (`salle_machines_cable.sage`).
- Vérifié. Le banc `bench_aiguillage_3d.gd` contrôle les bouts parallèles
  au câble (écart nul), la roue portée partout et le câble dégagé. Le banc
  `bench_salle_machines_3d.gd` contrôle la pente A→B, nulle dans le repère
  de la voie, le brin de sortie au niveau de la voie, et la roue amont dans
  la fosse. Tous les bancs passent, 49 tests aussi.

**v1.15.31** — aiguillage Abt : les bouts de rail qui manquaient.
- Retour d'essai : « il manque des bouts de rail dans l'Abt, renseigne-toi
  et regarde bien les photos ». Sources : Wikipédia DE « Abtsche Weiche »
  (rails extérieurs sans lacune ; rails intérieurs à langues fixes, avec des
  lacunes pour les boudins, pour le câble et pour la pince du frein de voie)
  et photos Wikimedia d'Hakone, de la Polybahn de Zurich et d'Oberweißbach.
- Chaque rail intérieur commence désormais par une **langue** qui naît dans
  la voie unique, 4 m avant la fourche, contre le rail extérieur opposé (le
  boudin de l'autre rame passe entre les deux), puis s'écarte avec la voie.
  Là où le câble de la rame opposée traverse, le rail est **coupé** : la
  langue finit en lame d'un côté du câble, un second bout décalé repart de
  l'autre côté, et les deux se chevauchent sur 1,1 m ; la roue plate (24 cm)
  porte sur l'un puis sur l'autre. Ce second bout revient sur la ligne de
  la roue, croise l'autre rail intérieur sur le cœur en X à 27,5 m, et court
  tout l'évitement. La v1.15.29 ne dessinait qu'un rail continu troué sous
  la tête, qui n'existe pas.
- Blochets et socles suivent les nouveaux bouts ; les galets de déviation
  à 4,5 m, qui gênaient les langues, sont retirés. La lacune pour la pince
  du frein de voie n'est pas dessinée : sa position sur le Perce-Neige est
  inconnue.
- Vérifié par le banc `bench_aiguillage_3d.gd`. La roue plate est portée
  partout, l'ornière du boudin reste libre, le câble ne touche aucun bout de
  rail, et aucun galet n'est posé sur un rail. Tous les bancs passent,
  49 tests aussi.

**v1.15.30** — ambiance PC : fin du « silence » sous 1 m/s en décélération.
- Les deux rapports de diagnostic arrivés du PC de Kevin le 30/09 (Windows 10,
  Qt 6.11) ont tranché : les boucles d'ambiance jouaient bien (Qt : en
  lecture, aucune relance du chien de garde), mais à 0,136 de volume, soit
  plancher de fluage 0,45 × atténuation sous le clip de freinage réel 0,55
  × atténuation sous l'annonce 0,55. Or ce clip de freinage (20 s) est fort
  pendant 4 s puis quasi muet (−29 dBFS, contre −12 pour l'ambiance) : on
  étouffait l'ambiance sous un clip qu'on n'entendait plus.
- L'atténuation sous un clip réel suit désormais le niveau RÉEL du clip,
  mesuré par tranches de 250 ms au lancement : pleine à −20 dBFS et
  au-dessus (le clip porte le bruit moteur, on ne l'entend pas en double),
  nulle à −30 dBFS et en dessous. Au point relevé sur le PC (0,74 m/s,
  clip à 16 s), l'ambiance repasse de 0,136 à 0,25 sous l'annonce, 0,45
  sans annonce. Le rapport de diagnostic donne aussi le niveau du clip.
- Tests : `tests/test_son.py` plantait sur la CI depuis la 1.15.25
  (QtMultimedia absent du runner) ; les tests du lecteur s'y sautent, ceux
  qui lisent les WAV y tournent. Trois tests rejouent le relevé du 30/09.
  49 tests.

**v1.15.29** — aiguillage Abt dessiné, câble tendu entre les galets, vue
salle des machines.
- Demande de Kevin, photo d'un aiguillage Abt de funiculaire à l'appui (« ce
  n'est pas celui du funiculaire mais le principe est le même ») :
  l'intérieur des deux aiguillages de l'évitement est dessiné. Rails
  extérieurs continus ; chaque rail intérieur naît 9 m après la fourche,
  contre le rail extérieur opposé, là où la lacune laisse passer le boudin
  de l'autre rame (nez en rampe, pointe écartée) ; les deux rails intérieurs
  se croisent en X à 27,5 m sur un cœur coulé (semelle sombre, déplacée :
  elle était 8 m trop tôt et à mi-hauteur des rails) ; à 17 m, le câble de
  la rame opposée traverse le rail intérieur par une fenêtre (âme et patin
  découpés sur 1,6 et 3,7 m, tête renforcée au-dessus du câble, 3 cm de jeu).
  Galets de l'aiguillage placés à l'écart des fenêtres ; galets de déviation
  inclinés à moyeu rouge du côté intérieur du coude du câble. Les blochets
  des deux voies ne se superposent plus : socles étroits sous les rails
  intérieurs dans l'aiguillage.
- « Normalement en courbe, le câble va en ligne droite entre les galets » :
  le câble n'épouse plus la courbe de la voie. Il est tendu d'un galet au
  suivant et ne change de direction qu'aux galets ; dans la grande courbe
  (R ≈ 460 m), la corde passe 4,9 cm à l'intérieur de l'arc à mi-portée.
  Le câble repose exactement dans la gorge de chaque galet, et l'inclinaison
  des galets en courbe découle de l'effort (tension contre poids : 73 à 78°
  requis, plafonnée à 32° pour que les deux galets d'une paire ne se
  touchent pas).
- Nouvelle vue 3D, demande de Kevin : la **salle des machines**, caméra fixe
  par rapport à la gare amont (elle ne suit pas le train), qui tourne dans
  tous les sens autour des deux roues, zoome, et se déplace (clic droit, ou
  deux doigts). Elle reste dans la salle et le hall, recule si elle finirait
  dans une machine, et efface la dalle quand on passe au-dessus. La touche
  `O` et le bouton VUE font le tour cabine → extérieure → salle des machines.
- Les 16 photos de visite de Kevin n'ont pas donné l'écart entre les deux
  roues, car aucune ne les montre ensemble. La plaque du réducteur confirme
  la vitesse maxi : 55 tr/min × π × 4,16 m = 11,98 m/s. Le secours
  hydraulique entraîne le câble à 2,0 ou 1,3 m/s. Le pupitre donne les
  contrôles d'entrée en gare, 8 m/s puis 1,4 m/s, et le simulateur les
  respecte. Tout est consigné dans `SOURCES.md`, lignes 23f à 23i.
- Vérifié : banc `bench_aiguillage_3d.gd` (aucun contact câble-rail hors
  des 4 fenêtres, aucun galet sur un rail, 16 galets de déviation), captures
  en vrai rendu Godot sans GPU (`shot_aiguillage.gd`,
  `shot_salle_machines.gd` sous Xvfb + Mesa), tous les autres bancs, 46 tests.

**v1.15.28** — carter rouge fixe autour des roues, ouvertures plus arrondies.
- Précision de Kevin : « le truc rouge autour de la poulie ne tourne pas, il
  protège le câble ; le câble doit être dedans, et il faut l'interrompre pour
  laisser sortir le câble ». Le rouge est désormais un **carter fixe** (tôle
  extérieure et deux flasques, sur deux pieds) qui coiffe la jante ; la roue,
  jante et joues comprises, est jaune et tourne seule. Le carter est ouvert
  là où le câble entre et sort, calculé depuis les points de tangence (le
  brin quitte le rayon du carter à environ 22° du point de contact) : tout
  le dessus de la roue aval entre les butoirs, son retour depuis la roue
  amont, et côté roue amont les arrivées, le départ vers la roue aval et la
  sortie vers la batterie.
- Ouvertures du voile aux coins nettement plus arrondis (bout extérieur en
  arche, bout intérieur en ogive), comme sur la vidéo de 2011.
- Écart entre les deux roues **non mesuré** : aucune photo trouvée ne les
  montre ensemble (visite de 2011, reportage de 2015, vidéo) ; la position
  reste celle du tracé calculé (entraxe 6,7 m, roue amont 1 m plus bas).

**v1.15.27** — roues d'entraînement redessinées d'après les photos de flanc.
- Retour d'essai : « tu n'as pas trouvé des photos des roues vues de flanc,
  pour avoir le bon design des ouvertures ? ». Trouvées : la visite de la
  salle des machines du 20 juin 2011 sur le forum remontees-mecaniques.net
  (récupérée par la Wayback Machine, le forum bloque les accès
  automatiques), et la vidéo YouTube de la poulie motrice qui l'accompagne.
- Les roues ont une **jante rouge épaisse** (joues comprises) et un **voile
  jaune évidé de douze ouvertures en pétales** : arrondies côté jante,
  pointues côté moyeu, séparées par des bras larges. Les quatre trous ronds
  de la v1.15.26 étaient une invention. Piste de frein en acier juste sous
  la jante, comme sur la photo des freins.
- Voile construit par secteurs (moitiés sans trou triangulées par
  `Geometry2D`), parois des ouvertures extrudées.

**v1.15.26** — salle des machines de la gare amont refaite (3D, PC et PWA).
- **Deux roues d'entraînement** ∅ 4 160 mm, jaunes, voile plein, gorges
  garnies de rouge, piste de frein et étriers rouge et turquoise sur bâti vert,
  comme sur les photos du reportage remontees-mecaniques.net.
- **La roue aval affleure au niveau de la voie entre les deux bras bleus des
  butoirs** (précision de Kevin). Son sommet est à −1,30 m, sous la table de
  roulement, et elle sort de la dalle de s = −0,14 à 2,04 m, les bras allant
  de −0,25 à 2,15 m. La roue amont est sous la dalle.
- **Passage du câble** : le brin gauche de la voie se pose sur le sommet de la
  roue aval, fait un huit entre les deux roues (qui tournent en sens
  inverses, deux passes par roue, 780° d'enroulement, désaxements ≤ 2,6°),
  remonte à 8,5° dans la fosse et retrouve la voie droite par une batterie de
  quatre galets entre les butoirs. Tracé déduit du principe classique (roue à
  deux gorges et seconde roue) et vérifié par SageMath :
  `audit_physique/salle_machines_cable.sage`.
- **Salle sous la dalle** : murs carrelés blancs, trois moteurs à courant
  continu bleus avec leur ventilateur, arbres sous carter grillagé jaune,
  réducteurs jaunes, paliers, centrale hydraulique des freins, armoires
  électriques, néons. Caillebotis sur la fosse derrière la roue. En vue
  extérieure, la salle devient transparente comme le tunnel.
- Banc `godot_project/bench_salle_machines_3d.gd` (cotes : affleurement,
  position entre les bras, pente du brin) et rendu hors Godot
  `tests/rendu_salle_machines.py`.

**v1.15.25** — son d'ambiance PC : chien de garde et diagnostic.
- Retour d'essai : « à la décélération, sous 1 m/s, aucun son d'ambiance,
  c'est net sur le PC ». Non reproduit sous Linux : joué sur un vrai serveur
  son et enregistré, le simulateur garde −12 à −28 dBFS pendant toute
  l'arrivée. Qt 6.11 mélange pourtant les sons de la même façon sous Windows.
- Fragilité trouvée : les deux boucles d'ambiance se fiaient à un drapeau
  « ça joue » jamais vérifié auprès de Qt. Si Windows coupe une voix
  (changement ou réveil du périphérique audio, session réinitialisée), la
  boucle de croisière est relancée au prochain arrêt, mais la boucle lente,
  seule à jouer sous 1 m/s, ne l'était jamais. Un chien de garde vérifie
  toutes les 0,5 s et relance une boucle coupée (le sifflement moteur le
  faisait déjà).
- Diagnostic : au premier passage sous 1 m/s en décélération, deux relevés
  de l'état réel de chaque lecteur (lecture, statut, volume, ducks, version
  de Qt, sortie audio) partent au point de collecte du NAS, une fois par
  session, et aussitôt si une boucle a dû être relancée. Genre
  `diagnostic_son` ajouté au collecteur.
- Tests : `tests/test_son.py` (3).

**v1.15.24** — mode Défi et son d'ambiance (PC + PWA), retours d'essai du 28/09 :
- **Consigne 0 en fin de montée** : « je mets la consigne à 0 et il accélère
  pour se jeter dans le butoir ». La consigne effective touchait 0 alors que
  la rame roulait encore à ~2 m/s, et le variateur lâchait tout (ancienne
  « roue libre à 0 » de juillet). Or depuis l'audit du 26/09, le poids du
  câble est dans la dynamique : sans câble lest, les 3,4 km de câble du
  contrepoids tirent ≈ 99 kN vers la gare haute. La rame réaccélérait donc
  jusqu'au butoir. Désormais la consigne 0 est une consigne comme une autre :
  le variateur arrête la rame et la tient, sans ramper (l'anticipation ne
  compte plus roulement et traînée à l'arrêt). Couper trop tard finit
  toujours au butoir : c'est le piège du Défi.
- **Boutons + et −** « brusques et violents » : en Défi le moteur est
  surrégimé ×1,8 mais le régulateur calculait sa commande pour le moteur
  nominal. Au-dessus de ~8 m/s la rame dépassait la consigne de 0,9 m/s (et y
  restait) et freinait à 1,1 m/s² au lieu de 0,7. Le régulateur voit
  maintenant la vraie force disponible ; côté PC, le plafond de décélération
  de confort est levé en Défi comme dans la PWA (son relâchement donnait un
  à-coup de 48 m/s³). Mesuré : 0,31 m/s² au +, 0,73 m/s² au −, à-coups
  ≈ 3 m/s³, plus aucun dépassement.
- **Rupture du câble en montée** : « la voiture ralentit et s'arrête alors
  qu'on n'a serré aucun frein ». Sur PC, la séquence d'incident prenait le
  passage par v = 0 au sommet de la course pour un arrêt et serrait le
  tambour de la gare haute, qui agit par le câble rompu. Désormais le tambour
  et l'affaissement du câble sont inopérants câble rompu, la séquence attend
  une rame vraiment tenue, et la rame redescend. Maj (parachute) l'arrête et
  la tient ; relâcher l'urgence la laisse repartir (parité PWA).
- **Son d'ambiance à basse vitesse (PWA)** : entre 0,1 et 0,4 m/s la PWA
  retirait encore 22 à 35 dB à l'ambiance, alors qu'elle devait suivre la loi
  du PC. Elle garde maintenant un plancher à −10 dB tant que le voyage est en
  cours. Sur PC, la mesure ne montre pas de coupure (boucle lente entre 0,25
  et 0,45, 8 à 13 dB sous la croisière, comme les enregistrements réels).
- Tests : `tests/test_defi.py` (4), 2 tests Défi dans `tests/test_physics.py`,
  banc `bench_defi_3d.gd` étendu (tenue à 0, fin de montée, rupture avec et
  sans urgence, boutons + et −). Manuel 1.15.24.


**v1.15.23** — les vantaux s'ouvrent toujours vers le BAS de la pente et se
ferment vers le HAUT (3D, PC + PWA). Retour d'essai : « le sens d'ouverture
n'est pas cohérent entre l'arrivée et le départ ». Les vantaux glissaient
« vers l'arrière de la caisse », or la caisse est retournée quand elle
descend (le nez mène toujours) : à la montée ils s'ouvraient vers le bas,
à la descente vers le haut, et au demi-tour ils changeaient de côté. Le
signe du glissement suit maintenant la même règle que le retournement
(`Cabin.door_slide_sign`). Le banc `bench_portes_3d.gd` vérifie les quatre
cas (rame 1/2 × montée/descente) : déplacement −1,20 m le long de la montée.

**v1.15.22** — la vue extérieure (O) reste accessible en exploitation
automatique : « je ne peux pas changer de vue avec O, c'est bloqué, mais F4
marche ». Le verrou de l'automate (qui ignore les touches de conduite) avait
deux listes blanches dupliquées, clavier et boutons du pupitre, et O manquait
aux deux. Une seule liste `AUTO_OPS_META_KEYS` (X, Échap, P, L, N, Retour,
F1–F6, O, +/−) sert désormais aux deux chemins. Test ajouté.

**v1.15.21** — exploitation automatique : les portes attendent la fin des
oscillations, le demi-tour attend la descente (PC + PWA) :
- retour d'essai : « il inverse le sens du voyage trop vite, en bas on n'a pas
  le temps de voir l'oscillation ; il faut attendre la fin des oscillations
  avant d'ouvrir les portes ». Nouvelle phase **STABILISATION** de l'automate
  PC : les portes ne s'ouvrent que lorsque l'enveloppe du rebond du câble
  A·e^(−ζωt) passe sous **2 cm** — pour la rame pilotée ET le contrepoids
  (quand on arrive en haut, c'est lui qui oscille en bas). Bornes 3 s / 30 s.
  Chiffré par SageMath (`audit_physique/stabilisation_rebond.sage`) : 17 s
  rame vide en bas, 26 s pleine, 0 s en haut. Puis **12 s** portes ouvertes
  (descente des passagers) avant le demi-tour, au lieu de 5 s. Le panneau
  d'exploitation affiche l'amplitude résiduelle (« STABILISATION ±12 cm »,
  « CP » quand c'est le contrepoids).
- PWA : le délai fixe de 15 s avant portes + demi-tour devient le même
  critère physique (< 2 cm, 3 s mini, 30 s maxi) — en bas 17 s avec une
  oscillation de 25 cm visible, en haut 3 s.
- Tests : `tests/test_exploitation_auto.py` (3), `tests/conftest.py` (charge
  `ssl` avant Qt : deux tests de mise à jour dépendaient de l'ordre des
  fichiers dans python-lab), banc `godot_project/bench_auto_3d.gd` dans les
  deux sens.

**v1.15.20** — icône partout et dry run de l'exploitation automatique :
- la nouvelle icône devient aussi l'icône du projet Godot (`icon.png`) et le
  favicon / icône Apple de la PWA (export de l'icône réactivé).
- **Dry runs** (PC avec lecteur d'annonces simulé aux vraies durées, PWA en
  headless) : arrivée puis départ en exploitation automatique, dans les deux
  sens — la séquence est cohérente (ouverture à l'arrivée, annonce, buzzer,
  vantaux 1,3 s après le début du clip, interlock à la butée, buzzer de quai,
  traction). Une incohérence corrigée au passage : sur PC l'exploitation
  automatique ouvrait les portes d'un coup à l'arrivée, sans clip ni délai,
  avant l'arrêt complet ; elle passe par la commande normale (clip, vantaux
  à 1,3 s, interlock à 2 s). Bancs : `godot_project/bench_auto_3d.gd`,
  `tests/dryrun_auto_pc.py`.

**v1.15.19** — en vue extérieure, les deux gares redeviennent
translucides : l'habillage de la v1.15.14 (parois, plafonds, poutres, fond
de la gare haute) suit maintenant la paroi du tunnel (alpha 0,22, faces
avant coupées) au lieu de cacher la rame à quai.

**v1.15.18** — le bouton « ORBITE [O] » s'appelle **VUE EXT. [O]**, comme la
vue qu'il commande (aide et README alignés).

**v1.15.17** — rapports d'incident automatiques, comme MusicOthèque :
- **PC** : au premier lancement, le programme demande l'accord pour signaler
  tout seul ses problèmes ; ensuite plantage Python, crash natif Qt, gel de
  l'interface (vigie) et preuve de vie quotidienne partent au point de
  collecte du NAS. Aide → **Signaler un problème…** envoie un signalement
  écrit avec les derniers événements du journal de bord (copie .zip sur le
  Bureau) ; Aide → case à cocher pour l'envoi automatique. Plus de ticket
  GitHub proposé au lancement.
- **PWA** : les erreurs JavaScript et les erreurs de script Godot (au plus
  trois par session) partent au même point de collecte sous le nom
  `funiculaire-pwa/<version>`.
- **Pupitre** : troisième rangée de boutons **VUE 3D [F4]**, **VUE EXT. [O]**,
  **AIDE [F1]** (rangées resserrées de 36 à 32 px pour la loger).
- **Écran d'aide en cours de voyage** : deux boutons, **REPRENDRE** (ferme
  l'aide) et **RAME / SENS…** (abandonne le voyage et revient à l'écran
  titre) — on pouvait ne plus retrouver la sélection après avoir démarré.
- **Icône refaite** d'après le vrai design : la face avant de la rame
  (calotte jaune, grand pare-brise, portes en D, TIGNES, deux phares ronds,
  tampons) dans le rond du tunnel ; `make_logo.py` produit logo.png/.ico,
  logo_64.png et les icônes PWA.

**v1.15.16** — lien de téléchargement permanent : chaque release publie
aussi l'installeur sous le nom stable `PerceNeigeSimulator-Setup.exe`, si
bien que
<https://github.com/ARP273-ROSE/perce-neige-sim/releases/latest/download/PerceNeigeSimulator-Setup.exe>
pointe toujours vers la dernière version (page : <https://github.com/ARP273-ROSE/perce-neige-sim/releases/latest>).

**v1.15.15** — écran d'accueil : bouton **COMMENCER ▶** cliquable en bas à
droite (équivaut à F1) ; tant que l'écran d'accueil est affiché, un clic
ailleurs n'atteint plus les zones de l'écran titre cachées dessous.

**v1.15.14** — gares refaites d'après les photos (les deux se ressemblent) :
parois **bleu nuit**, plafond **clair** porté par des **poutres acier
sombres** en travers tous les 2,8 m et deux pannes en long, **poteaux**
sombres le long des murs, **appliques bleues** ; quais en **caillebotis
noir** à nez de marche en tôle damier alu, avec la **bande rouge** de la gare
haute ; néons entre les poutres. Même traitement pour le fond de la gare
haute (mur « DESTINATION GLACIER ») ; hall de Val Claret en bardage bois.

**v1.15.13** — la vue 3D lancée au démarrage passait par-dessus l'écran
titre (« Godot passe au premier plan, on ne voit plus rien »). La fenêtre
native est masquée sous chaque overlay Qt par un mécanisme qui n'agit que
sur les changements d'état : quand la 3D finissait de s'embarquer pendant
l'écran titre, elle était montrée sans que le masquage soit réappliqué. Il
l'est maintenant dès la fin de l'embarquement ; la 3D apparaît au DÉMARRER.

**v1.15.12** — deux manques signalés :
- **PWA : NOUVEAU VOYAGE après une catastrophe.** Sans clavier, rien ne
  permettait de relancer un voyage après une panne catastrophique (la touche
  R existait, pas de bouton). Un bouton rouge « NOUVEAU VOYAGE » apparaît au
  centre dès que la rame est immobilisée par la panne ; il repart de la gare
  vers laquelle on allait, dans l'autre sens (comme R). Après une collision
  en Défi, l'écran de fin gardait déjà le sien.
- **PC : la vue 3D d'entrée de jeu.** Le viewer Godot démarre en arrière-plan
  au lancement quand il est disponible ; en refermant l'écran d'accueil (F1)
  on tombe directement sur la vue cabine 3D. F4 garde son cycle.

**v1.15.11** — le bouton AUTO [A] du PC fait enfin quelque chose. Il ne
faisait que basculer un drapeau que rien ne lisait. C'est maintenant le
**pilote automatique du voyage** promis par le manuel : engagé par le
conducteur, il ferme les portes après un court arrêt, arme PRÊT, donne le
DÉPART, tient 100 % de consigne et laisse l'enveloppe d'arrêt poser la rame,
puis se désengage à l'arrivée. Il appuie les touches comme le conducteur
(tous les verrous et annonces s'appliquent) et rend la main dès qu'on touche
la consigne ou un frein, sur panne, ou si l'exploitation automatique (X)
prend la ligne ; engagé après une arrivée, il inverse le sens et repart.
Plus engagé par défaut au nouveau voyage. Test `tests/test_pilote_auto.py`.

**Note physique (27/09)** — « RÉGEN » à l'arrivée en haut avec une rame
pleine : c'est le poids du câble (38 t, pas de câble lest sur le Perce-Neige)
qui, en haut, tire le contrepoids de 99 kN et l'emporte sur les 16–45 kN de
la rame pleine ; à 12 m/s constant 126–410 kW de régénération, et jusqu'à
1 MW pendant la décélération des 128 t en mouvement. Calcul Sage dans
`audit_physique/regen_arrivee_haut.sage`, détail dans
`AUDIT_PHYSIQUE_VOYAGES.md`.

**v1.15.10** — PWA : salle des machines refondue comme celle du PC. Vue en
coupe de la machinerie de la gare amont : 3 moteurs DC teintés par la
charge, réducteur, arbre, **deux poulies jaunes Von Roll** (motrice et
déviation) qui tournent à ω = v / r et s'inversent à la descente, câble en
huit qui les enlace avec un repère qui défile, LED de puissance, lectures
∅ / tr/min / vitesse câble ; en dessous les trois groupes moteurs et leurs
barres de puissance.

**v1.15.9** — historique corrigé (F3) : le funiculaire n'a pas remplacé un
téléphérique mais les **deux télécabines 4 places Grande Motte A (1968) et
B (1969)**, Transtélé / PHB ; le téléphérique de la Grande Motte (sommet
3 456 m) existe toujours au-dessus (source remontees-mecaniques.net).

**v1.15.8** — R après un arrêt en tunnel repart bien d'une gare (PC) :
- « Quand tout est cassé au milieu, R repart parfois de l'endroit où il
  est. » Cause : l'affaissement d'embarquement (v1.13) s'ancre dès que la
  rame est immobilisée hors voyage — donc aussi après l'arrêt sur panne
  catastrophique en tunnel — et `new_trip()` ne le désarmait pas : le
  premier pas de physique ramenait la rame à l'ancrage. Désarmé au nouveau
  voyage ; test de régression `tests/test_nouveau_voyage.py`.
- R relance un voyage neuf dès que la rame est **immobilisée** par une panne
  catastrophique (plus besoin d'attendre la fin des annonces d'évacuation).

**v1.15.7** — écran d'accueil refondu, passagers modélisés, phares ronds :
- **Écran d'accueil / aide (F1)** : les conseils de conduite recouvraient
  la fin de la colonne des raccourcis. Refonte : trois colonnes (Conduite,
  Cabine, Système) à une ligne par touche, description repliée si besoin,
  et les conseils dans la place qui reste — mesurée, jamais par-dessus.
  Toutes les touches y sont (PRÊT `V`, DÉPART `Z`, inversion `I`, `Début`).
- **Passagers et matériel modélisés** : silhouettes articulées (bottes,
  jambes, veste, bras, gants, sac, casque, lunettes), assises sur les
  perchoirs ou debout ; skis à spatules et fixations, bâtons à poignées et
  rondelles, surfs aux bouts arrondis. Un shader à masques colore chaque
  pièce différemment par instance, toujours en MultiMesh.
- **Phares halogènes ronds** (pas rectangulaires) dans la bande sombre
  sous « TIGNES », avec leur cerclage.
- **Roues du système Abt** : d'un côté des roues à **double boudin** qui
  enserrent le rail extérieur et guident la rame (côté gauche pour la rame 1
  en regardant vers le haut, côté droit pour la rame 2), de l'autre des
  **cylindres larges sans boudin** qui passent sur tout l'appareil de
  l'aiguillage. Le côté suit la rame et le sens de marche.
- **Roues sur le rail dans les changements de pente** : chaque voiture repose
  sur ses deux bogies (corde entre les appuis) au lieu d'être posée sur la
  tangente en son milieu — les roues décollaient sur les crêtes convexes.
- Manuel PDF et README mis à jour (nouveautés 1.15, touches).

**v1.15.6** — cabine et faces d'après les photos (retours du 27/09) :
- **Pare-brise** ramené à 1,52 × 1,78 m (mesuré sur la photo 094104).
- **Plancher en marches** : le bord bas de chaque palier affleure le
  plancher de la caisse, la contremarche de 37 cm est entière (avant, la
  moitié de chaque palier passait sous le plancher : on ne voyait que des
  biseaux). Sièges et passagers suivent.
- **Passagers selon le remplissage** : 2 assis (perchoirs) + 12 debout par
  cerceau, 126 places par voiture, le nombre affiché suit le remplissage
  déclaré (PWA et PC — le PC envoie maintenant ses effectifs au viewer,
  rame d'en face comprise). Casques, manteaux variés, **skis et bâtons
  (55 %), surfs (20 %)** tenus debout à côté. Tout en MultiMesh.
- **Phares** : la bande sombre sous « TIGNES » est en fait les deux phares
  halogènes — deux lentilles rectangulaires par face, allumage qui chauffe
  (≈ 0,3 s, passe par l'orange) et extinction qui refroidit (≈ 0,6 s) ;
  les disques des coins bas sont des tampons. Seule la face de tête est
  allumée.
- **Plaque** du bas du pare-brise : « FUNICULAIRE / PERCE NEIGE 1 » ou
  « 2 » selon la rame pilotée (l'autre rame porte l'autre numéro).

**v1.15.5** — câble et galets descendus, galets inclinés dans l'évitement :
- le câble était à −0,99 m (table de roulement −1,24, fond de caisse −1,16) :
  câble et galets entraient dans le dessous des rames. Le câble est
  maintenant au niveau des blochets (4 cm au-dessus de leur dessus), les
  galets s'enfoncent dans la longrine, les équerres ne dépassent que de
  quelques centimètres ; la roue aval de la gare haute suit.
- dans l'évitement, chaque voie s'écarte de l'axe : sa courbure propre
  incline maintenant les galets, dans le même sens qu'en ligne — vers
  l'extérieur à l'entrée, contre-courbe au milieu, retour à la réunion.

**v1.15.4** — retours d'essai du 27/09 :
- **Paroi du tunnel** : ce n'étaient pas des dalles de béton. Revêtement
  lisse, clair, légèrement brillant comme sur la vidéo cabine ; les joints
  en quinconce disparaissent, il ne reste que de fines lignes circulaires.
- **Gare haute** : la machinerie est sous terre. De la gare on ne voit plus
  que le sommet de la grande roue aval qui émerge d'une fente du sol au bout
  de la voie (les deux brins passent dessus et plongent) ; la salle des
  machines (poulie motrice, moteurs) est construite sous la dalle, et la
  salle de gare se termine par le mur en bardage bois « DESTINATION
  GLACIER » de la photo 095119.
- **Vue cockpit** : plus de tache blanche de reflet sur le pare-brise (la
  vitre n'est plus éclairée, c'est une teinte).
- **Évitement Abt** : les deux ronds orange aux fourchements sont retirés.

**v1.15.3** — mise à jour automatique, portes, poste :
- **Mise à jour automatique (PC)** : elle ne marchait « pas du tout ». Le
  paquet installé par le Setup passait encore par l'ancien mécanisme (échange
  d'un .exe PyInstaller vérifié par SHA256SUMS), dont les releases ne
  publient plus les fichiers ; en repli il recopiait quelques .py depuis le
  dépôt sans le fichier VERSION ni le viewer 3D. Le programme se met
  maintenant à jour comme MusicOthèque : archive ZIP téléchargée et extraite
  par lui-même (pas de SmartScreen), **viewer 3D compris** (~30 Mo par
  version, les sons restent en place), redémarrage proposé. Verrou
  `PerceNeigeSimulatorEnCours` lu par l'installeur. **Une installation du
  Setup 1.15.3 est nécessaire une fois** ; ensuite tout est automatique.
- **Portes calées sur le son (PC + PWA)** : séquence en série annonce →
  buzzer (7 s) → clip de fermeture (7 s), et les vantaux partent 1,3 s après
  le début du clip pour buter à 5,3 s (le « clac » de fin de course, lu dans
  l'enveloppe du son). Sur PC, l'interlock basculait 3 s après la commande,
  en pleine annonce, et le viewer fermait 11 s avant le bruit ; dans la PWA,
  buzzer et clip jouaient ensemble. Le PC envoie au viewer l'état des
  vantaux, pas l'interlock.
- **Porte ouverte** : un joint de hublot flottait dans la baie (la doublure
  y est ouverte, le vantail est une pièce à part).
- **Poste** : le pare-brise est sur la calotte, presque au nez — la caméra
  restait à 2,1 m de la vitre. Elle passe à ~1 m, pupitre contre la doublure,
  champ 70° ; pare-brise élargi à 1,64 m (≈ 47 % de la face sur la photo
  094104) et rehaussé. Plancher, plafond, siège, moniteur et équipements du
  montant gauche suivent sans sortir de la calotte.

**v1.15.2** — champ de vision du cockpit : la caméra était à 2,3 m
derrière un pare-brise de 1,4 m (22° de champ, « la vitre est trop
petite ») ; elle passe à ~1,8 m de la vitre avec le pupitre contre son bas
comme sur la photo 095119 (moniteur, siège, plancher, plafond, mains
courantes suivent), champ vertical 78°. **Joints noirs intérieurs** sur la
doublure autour du pare-brise et des hublots : ils recouvrent le crénelage
des découpes, vu de près (« c'est pixelisé le bord »).

**v1.15.1** — pas de fosse en haut, seulement en bas (retour d'essai) : la
dalle, les blochets et l'escalier vont jusqu'au bout à Grande Motte,
butoirs bleus seuls.

**v1.15.0** — le tunnel d'après les vidéos cabine (2026-04-26 et HD) :
- **Anneaux de voussoirs** de la section au tunnelier (257 → 3 420 m) :
  joints circulaires tous les 1,4 m et joints longitudinaux en quinconce,
  comme les bagues visibles sur toute la vidéo.
- **Galets blancs** : les galets du câble sont en polymère clair, la chose
  la plus visible du tunnel — ils étaient en fonte sombre.
- **Canalisation grise en voûte, côté droit**, et **joints horizontaux des
  banches** dans la galerie carrée de Val Claret.
- **Évitement Abt** : grandes **poulies horizontales orange** de renvoi du
  câble aux deux fourchements (hd_278), plaques de cœur de croisement (les
  roues extérieures à double boudin guident, les intérieures sont plates
  et franchissent le cœur ; le câble du véhicule opposé passe dans un trou
  de la voie intérieure — dossier remontees-mecaniques.net), réglettes
  lumineuses supplémentaires dans la chambre. Tout en MultiMesh.

**v1.14.4** — galets plus inclinés, gares détaillées :
- **Galets** : inclinaison dans les virages doublée (× 8 au lieu de × 4,
  plafond 32° au lieu de 15°).
- **Gares** (photos 093522 / 094104 en bas, 095509 / 095443 en haut) : une
  **fosse sous la voie** aux deux bouts (fond en caillebotis, parois béton,
  cornières de rive, les rails passent sur des longrines, la dalle et les
  blochets s'arrêtent) ; en haut, **deux grandes poulies de renvoi** du
  câble vers la machinerie (Ø 1,6 m, une par brin) et une petite, ruban
  « 1000 VOLTS » ; en bas, une chaîne de sécurité. Le butoir rouge générique
  est remplacé aux deux gares par les **butoirs bleus** à tête bois de la
  photo (deux poutres-caissons au niveau du châssis).

**v1.14.3** — le cockpit enfin *dans* la rame :
- En vue cabine, la coque n'était pas dessinée : on voyait le tunnel de
  tous côtés, sans montants, sans encadrement de pare-brise, sans hublots.
  Elle reste maintenant **visible**, avec une **doublure intérieure crème**
  (tube et calotte, 5 cm en retrait) percée aux hublots, au pare-brise et
  aux baies de portes — les vantaux fermés se voient de l'intérieur, les
  hublots donnent sur le tunnel. **Pare-brise quasi clair** pour la cabine
  pilotée (α 0,16 au lieu de 0,62).
- **Plancher en gradins** (vidéo cabine) : un palier horizontal par
  cerceau sur la pente moyenne de 26,5 %, contremarches alu de 35 cm ;
  sièges, passagers, potelets et siège conducteur posés sur leur palier.

**v1.14.2** — galets du câble dans les virages : ce n'est plus l'axe de
la paire qui penche (un galet finissait plus haut que l'autre) — le
**support reste horizontal** et **chaque galet est incliné dans son
support**, les deux à la même hauteur, comme en vrai.

**v1.14.1** — retours d'essai : l'escalier du tunnel n'a **pas de rambarde**
(potelets et câble retirés, `walkway_handrail` pour les remettre) ; les
**portes s'ouvrent des deux côtés** en gare.

**v1.14.0** — portes qui coulissent, escalier du tunnel, poste enrichi :
- **Portes coulissantes animées** : chaque vantail est une pièce séparée
  (cerceau sous 54° depuis le sommet, hublot compris) qui se **déboîte
  de 8 cm puis glisse de 1,20 m** vers l'arrière en 2,5 s, côté quai
  seulement (les quais sont à −X du repère voie), à l'ouverture comme à la
  fermeture. Portes placées hors des échancrures de bogie (W W D W W D W D
  W W, bogies à 2 m des extrémités).
- **Premier cerceau jaune avec son hublot**, comme sur la photo 095438.
- **Tunnel** (vidéo cabine `20260426_094202.mp4`) : **escalier métallique
  de service à droite en montant** — marches horizontales tous les 0,45 m
  (13 cm de dénivelé à 30 %), deux limons, potelets tous les 3 m et câble
  main-courante — et boîtiers gris sur le mur gauche, côté des gros câbles.
  Tout en MultiMesh (≈ 25 000 instances, 5 appels de dessin).
  `walkway_side` permet de le passer à gauche.
- **Poste** (photos 095119 / 094402 / 094413) : deux coups-de-poing rouges
  à gauche de l'écran, combiné à l'extrémité gauche, étiquettes « PORTES
  1 à 6 / 7 à 12 / ÉCLAIRAGE / CABINE », pastille rouge à droite du tube,
  **tablette-horloge vivante** sur le montant gauche (heure réelle), panneau
  latéral beige à quatre boutons, levier et boîtier rouge, grille de
  ventilation à lamelles.

**v1.13.7** — flancs refaits d'après les photos 095433/095438/094135 :
- La caisse est une suite de **cerceaux de 1,30 m** séparés par un joint
  sombre **en creux** (plus de nervure saillante), dix par voiture, chacun
  percé d'**un hublot haut et étroit** : 0,75 m de large, ~1,5 m d'arc, du
  dessus des assises (0,6 m du plancher) à la courbe du plafond (2,05 m),
  extrémités très arrondies (r = 0,28). Trois portes par face (source CFD),
  vantail unique de la largeur d'un cerceau avec un hublot plus étroit
  (0,60 m), disposées W D W W D W W D W W.

**v1.13.6** — face avant et hublots corrigés d'après les photos :
- **Face avant** : seul le pare-brise est vitré. Les panneaux en D de part
  et d'autre sont les **portes d'évacuation, jaunes pleines**, avec liseré
  sombre, poignée et serrure (erreur de lecture de la v1.13.3 corrigée).
- **Hublots des flancs** : rectangles à **grands arrondis** (r = 0,25 m,
  ~1,0 × 1,1 m, au-dessus de la ceinture) au lieu de rectangles chanfreinés
  d'une cellule ; même technique que le pare-brise (découpe de la tôle,
  joint caoutchouc noir, vitre lissée à fleur de tôle), grille du tube
  affinée (2,5°, 10 cm) sous les panneaux vitrés.
- L'articulation verticale aux changements de pente est incluse depuis la
  v1.13.5 (chaque voiture prend la tangente 3D de la spline à sa propre
  abscisse, donc son propre tangage).

**v1.13.5** — les deux voitures s'articulent, les roues tournent sur les
rails :
- **Articulation** : la rame n'est plus un bloc rigide de 32 m. Chaque
  voiture est un nœud posé **sur la spline à sa propre abscisse** (s ∓ 8 m)
  avec sa propre orientation, replacé chaque frame ; l'intérieur (plancher,
  plafond, bandeau LED, sièges, passagers, mains courantes) est scindé par
  voiture et suit. Pupitre, siège conducteur, caméra et phares restent
  rigides avec la cabine (c'est le repère de la vue). Le soufflet suit la
  voiture de tête.
- **Roues** : quatre roues par bogie sur pivots, tournées à v/R (roulement
  sans glissement), avec moyeu clair et barres radiales sur la face externe
  — une roue lisse qui tourne ne se voit pas. Essieux, boîtes d'essieu et
  longerons de bogie ; la jupe est **échancrée** au droit des bogies
  (2,8 m) pour qu'on les voie sur les rails depuis la vue extérieure.

**v1.13.4** — la voie descend dans le tube, la coque redevient opaque, la
vue orbitale tourne en ligne, la puissance de redémarrage :
- **Voie descendue de 0,50 m** (`floor_y_local` −1,85) : la table de
  roulement est à 1,23 m sous l'axe au lieu de 0,73 — en réalité les rails
  sont au fond de l'alésage. Quais recalés au plancher cabine (−1,10),
  brins en salle des machines, carrosserie : fond plat à −1,16, plancher
  intérieur 2,4 m sous le plafond, **face avant de 2,93 m** (réel 3,1 m,
  contre 2,43 avant), hublots descendus à 0,85 m du plancher, bogies
  visibles sous la jupe. Caméra cabine inchangée : les rails passent
  simplement plus bas sous les yeux, comme sur les photos.
- **« Les parois sont transparentes »** en vue extérieure (PWA) : Godot
  tient pour face avant l'enroulement horaire, la coque était construite
  dans l'autre sens et le culling l'effaçait vue de dehors. Triangles
  retournés + matériaux double face.
- **Vue orbitale figée en ligne** : un doigt posé en vue extérieure et
  relâché en vue cabine (le bouton VUE bascule sur l'appui) restait
  mémorisé, et tout drag suivant passait pour un pincement à deux doigts.
  Le suivi des doigts se fait maintenant dans tous les modes.
- **Puissance au redémarrage en pleine pente** (calcul Sage
  `audit_physique/redemarrage_pente.sage`) : P = F·v, donc l'effort et la
  tension sont là tout de suite mais la puissance ne peut croître qu'avec la
  vitesse — c'est physique. Deux choses étaient discutables : le démarrage
  doux de quai (0,12 m/s² à v = 0, calibré sur la sortie de gare filmée)
  s'appliquait aussi en pleine voie → il ne vaut plus qu'à moins de 55 m
  d'un terminus, ailleurs la rampe programmée de 0,30 m/s² est prise dès le
  décollage (12 m/s en 41 s au lieu de 46) ; et l'afficheur partait de
  0 kW alors qu'un moteur DC qui pousse à l'arrêt dissipe déjà ses pertes
  cuivre (4 % du nominal au courant nominal, ∝ F²) et son excitation
  (15 kW) → il part maintenant de ~60 kW au décollage. Et surtout le
  régulateur n'avait **pas de feed-forward positif** de la rampe de
  consigne : seul le terme proportionnel accélérait (constante de temps
  ≈ 3 s, 0,40 m/s à 3 s au lieu de 0,8). Ajouté, avec une **pré-tension**
  (couple statique posé avant que le tambour ne lâche — la rame reculait
  de 2 cm au décollage en pente). PC et PWA.

**v1.13.3** — la face avant, emblématique, refaite aux cotes de la photo
(`sons/photos/20260426_095511.jpg`, 220 px/m) :
- **Pare-brise de 1,40 m de large** presque carré, du haut de la calotte
  jusqu'à l'axe, avec la plaque « FUNICULAIRE PERCE NEIGE 1 » dedans en bas ;
  **deux baies de portes de secours hautes et étroites contre la lisière**
  (bord extérieur en D suivant la calotte) ; liserés des portes ;
  « TIGNES » sous le pare-brise, grille et feux ronds tout en bas.
- Les vitres ne sont plus des cellules de la grille polaire (bords en
  escalier) : contours échantillonnés finement (rectangles arrondis /
  D), tôle **découpée** aux vitres, **joints caoutchouc noirs** qui
  recouvrent la découpe, vitres lissées posées à fleur de tôle. La rame 2,
  sans intérieur, a un fond sombre derrière ses vitres.
- La face réelle mesure 3,1 m de haut (apex → fond plat) ; celle du jeu
  n'en a que 2,43 (voie plus haute dans le tube) : les cotes verticales sont
  comprimées de 0,78 depuis l'apex, les largeurs conservées.

**v1.13.2** — des rames réalistes en 3D (PWA et vue F4 du PC), d'après les
photos du 26 avril 2026 (`sons/photos`) :
- L'ancienne cabine était un **cylindre jaune Ø 3,40 m centré 15 cm sous
  l'axe** : il descendait à −1,85 m, sous la dalle et les rails. La nouvelle
  carrosserie (`train_body_builder.gd`) est un **tube Ø 3,44 m concentrique
  à l'alésage, coupé à plat 7 cm au-dessus de la table de roulement**, avec
  le plancher intérieur au niveau des quais-escaliers (les sièges sont
  posés dessus ; caméra et pupitre inchangés).
- **Flancs gris** en tôle alu nervurée : anneaux circonférentiels tous les
  1,85 m, hublots hauts à coins arrondis alternés avec **trois portes par
  face** (vantaux plus clairs, joint central), tôle pleine aux extrémités.
- **Extrémités jaunes** en calotte bombée (1 m) débordant sur le premier
  tronçon : pare-brise rectangulaire centré en haut, deux baies étroites de
  portes de secours, lettrage « TIGNES » (Label3D), plaque, grille noire,
  **deux feux ronds** en bas qui s'allument avec les phares (blanc devant,
  rouge derrière ; la rame 2 vient en face, feux blancs allumés).
- Bogies apparents (4 roues chacun, sur l'écartement de 1,20 m), soufflet
  d'intercirculation sombre entre les deux voitures. Longueur visuelle
  32,0 m exactement (repères d'arrêt et collisions inchangés).
- Contrôles : `bench_train_mesh_3d.gd` (rien sous les rails, rien dans la
  voûte ni les parois, 32 m) + `tests/rendu_rame.py` (rendu orthographique
  face / flanc / dessus / trois-quarts sans GPU, à partir du maillage exporté).

**v1.13.1** — l'ambiance cabine ne « se coupe » plus à la décélération :
- Retour d'essai : « le son ambiant se coupe à la décélération vers 1 m/s ».
  Sur le PC, le volume des boucles suivait v/10 jusqu'à un plancher de 0,14
  (−17 dB sous la croisière) atteint dès 1,5 m/s, tenu pendant les 70 s
  d'entrée en gare à 0,75 m/s, et encore ducké ×0,55 par le clip d'approche.
  Sur la PWA, le gate −30 dB → 0 dB montait de 0 à 1 m/s : −7,5 dB au
  fluage, coude pile sur la décélération.
- Les enregistrements réels placent la croisière à −11 dBFS, l'approche
  à −23 et le quai à −19 : le fluage doit rester vers −19, pas −29.
  Nouvelle loi commune (`_ambient_gain`) : plancher de **fluage 0,45** dès
  0,5 m/s, fondu vers le plancher d'arrêt 0,14 entre 0,5 et 0,1 m/s ; PWA :
  le gate ne mord qu'entre 0,5 et 0,1 m/s. Test `pytest` dédié.

**v1.13.0** — le moteur physique retrouve trois forces qui lui manquaient, sur
le programme PC **et** la PWA (`train_physics.gd`), à parité vérifiée au banc
(p95 < 1 kW et < 2 daN entre les deux). Détail, sources et chiffres :
`AUDIT_PHYSIQUE_VOYAGES.md` (+ rapport PDF et script Sage dans
`audit_physique/`).
- **Le poids propre du câble pèse sur le moteur.** Il était dans la jauge de
  tension (ρ·g·Δh par brin) mais absent du bilan des forces. La différence
  des deux brins à la poulie vaut ρ·g·(z_rame − z_contrepoids) = **±99 kN**
  (10 t-force) aux terminus — plus que le déséquilibre pleine/vide des rames
  (69,5 kN). Conséquences visibles : un départ **vide/vide** demande 1,5 MW
  (au lieu de 0,3), l'arrivée en haut se fait en régénération, et une
  **descente chargée commence en traction** (825 kW : le contrepoids vide,
  en bas, porte 3,4 km de câble). Le pic pleine/vide passe à 2 240 kW —
  enfin cohérent avec les 3 × 800 kW installés, qui étaient jusque-là
  2,8× surdimensionnés. Le câble (38 t) entre aussi dans l'inertie.
- **Traînée d'air en tunnel.** Cabines Ø 3,60 m dans un tube Ø 3,90 m, portes
  de gare « hermétiques pour éviter les courants d'air dus aux différences de
  pression » : la colonne d'air entre les deux rames ne peut s'échapper que
  par l'espace annulaire. Modèle 1D quasi-stationnaire (débit annulaire
  v·A_T, contraction + frottement + élargissement). **Tube unique : ~16 kN par
  rame à 12 m/s ; dans l'évitement, le second tube court-circuite
  l'annulaire : ~1 kN.** La puissance CREUSE donc de ~500 kW à la traversée
  de l'évitement, chaque rame dans son tube. Taux de blocage β = 0,65, la
  plus haute valeur compatible avec la puissance installée (à recaler sur
  mesure ; le β géométrique brut vaut 0,7–0,9).
- **Résistance du câble sur ses 512 galets** (~5,4 kN, 1,5 % de sa charge
  normale) et **rendement électrique** (0,90) sur la puissance affichée en
  traction — la régénération avait déjà le sien (0,80).
- **Tension signée** : frottement et traînée chargent le brin d'une rame qui
  monte vers la poulie et déchargent celui d'une rame qui s'en éloigne.
- **Affaissement d'embarquement porté sur le PC** (la PWA l'avait) : à quai
  en bas, chaque passager allonge les 3,45 km de brin de 1,8 mm — la rame
  recule de ~60 cm pour 334 passagers, physiquement (le contrepoids ne
  bouge pas). Invisible en haut (26 m de brin : 4 mm).
- **Hold Abt** : le point d'arrêt avant l'aiguillage disparaissait dès que la
  rame le dépassait d'un millimètre en rampant, et elle repartait au
  plafond de panne (bug latent, révélé par le banc 3D).
- **Test miroir** : monter la rame pleine avec contrepoids vide ≡ descendre la
  rame vide avec contrepoids plein (même câble) — puissance, régén et
  tension coïncident à 0,00 près, PC et PWA. 21 tests, 3 bancs
  (`tests/bench_voyages.py`, `godot_project/bench_voyages_3d.gd`,
  `tests/parite_pwa.py`).
- Le « ~42 kWh par descente chargée (datasheet CFD) » cité dans le code
  n'a pas de source : la fiche CFD ne donne aucun chiffre d'énergie. Le
  modèle donne 31 kWh régénérés (et 14 kWh consommés au départ) pour une
  descente pleine/vide.

## v1.12 (juillet – août 2026)

**v1.12.43** — vue 3D enfin intégrée sous Linux (session Wayland) :
- **La 3D s'ouvrait dans une fenêtre séparée sous Linux**, au lieu d'être
  encastrée dans la vue cabine comme sous Windows. Cause : sous Wayland il
  n'existe aucun équivalent de XEmbed — `QWindow.fromWinId()` ne peut pas
  adopter la surface d'un autre processus, et une fenêtre Godot native
  Wayland n'a même pas de XID que `xdotool` puisse trouver. L'embarquement
  échouait donc **en silence**.
- **Correctif** : en session Wayland, le simulateur bascule sur XWayland
  (`QT_QPA_PLATFORM=xcb`) avant de créer sa `QApplication`, et lance Godot
  avec `--display-driver x11`. Les deux processus partagent alors le même
  serveur X, seule configuration où le reparentage fonctionne réellement
  (vérifié sur KDE/Wayland : `xcb`+`x11` reparente, toutes les autres
  combinaisons non).
- **Opt-out** : `PERCE_NEIGE_KEEP_WAYLAND=1` conserve le backend Wayland
  natif, au prix d'une vue 3D en fenêtre détachée.
- Sans effet sur Windows (reparentage Win32 `SetParent`) ni sur les
  sessions Linux déjà en X11.

**v1.12.42** — rames 1/2 inversées en 3D + intégration de la fenêtre 3D sous Windows :
- **Rame 1 / rame 2 inversées dans la vue 3D** (corrigé) : le numéro de la
  rame pilotée n'était **jamais transmis** au viewer Godot, qui restait
  figé sur son défaut « rame 1 = voie gauche ». En choisissant *Rame 2*,
  la 2D vous plaçait bien sur la voie de droite et étiquetait l'autre
  cabine « RAME 1 », mais la 3D vous faisait croiser **du mauvais côté**
  dans l'évitement Abt, avec le mauvais brin de câble attaché à la
  cabine. Le champ `rame2` est désormais dans le flux d'état UDP et
  pilote la voie des deux cabines, le brin de câble et les étiquettes
  R1/R2.
- **Fenêtre 3D qui passe en arrière-plan** (Windows) : quand le
  reparentage Win32 (`SetParent`) échoue, la fenêtre Godot est maintenant
  rattachée comme **fenêtre possédée** du simulateur — elle reste au
  premier plan au lieu de plonger derrière au premier clic sur un bouton.
  Les styles d'origine sont restaurés en cas d'échec (plus de fenêtre
  fantôme sans cadre).
- **Délai d'intégration porté à 20 s** : sur une machine lente (disque
  dur, antivirus qui scanne les 128 Mo du viewer au premier lancement,
  tentative Vulkan qui échoue puis relance OpenGL), la fenêtre
  apparaissait **après** l'échéance de 9 s et le simulateur renonçait
  définitivement à l'embarquer.
- **Diagnostic d'intégration réel** : l'échec était muet (le sim distribué
  tourne sans console) et le code d'erreur affiché était toujours faux
  (`ctypes.windll` ne remonte pas `GetLastError`). Les étapes
  d'embarquement — dont l'**awareness DPI des deux fenêtres**, cause
  documentée d'échec de `SetParent` — sont journalisées dans
  `%TEMP%\perce_neige_3d.log`.

**v1.12.41** — chaos jouable + pannes en exploitation auto :
- **Emballement enfin atteignable consigne à fond** : le moteur peut
  SURRÉGIMER en Défi (le fondu à 12,25 m/s est levé + surcharge ×1,8) —
  la rame dépasse 12 m/s **même en montée chargée** et grimpe jusqu'à la
  cascade (+20 % ≈ 14,4 m/s → moteur détruit → câble rompu).
- **Frein parachute opérant après rupture** : câble rompu, le frein
  poulie n'a plus de chemin de force → l'urgence engage directement le
  parachute rail (3,6 m/s²) qui **freine réellement** ; plus d'urgence
  « activée d'office mais inopérante » (le pressostat auto est levé en
  Défi : c'est vous qui freinez).
- **Couper la puissance quand on freine** (TOUS les modes) : le moteur ne
  tire plus contre un frein serré (urgence, parachute, frein manuel,
  frein de service) → décélération franche.
- **Rouler portes ouvertes en Défi** : plus d'auto-fermeture au départ,
  ouverture/fermeture (D) possible à tout moment ; réduire la consigne
  freine désormais aussi portes ouvertes (« part à fond » corrigé).
- **Consigne 0 = dérive** vers la rame la plus lourde (freins lâchés,
  sans traction) — nulle à l'évitement (équilibre), forte aux terminus.
- **Pannes en exploitation AUTO** : le conducteur IA laisse les pannes se
  produire ET les gère seul — **R automatique après une évacuation**
  (catastrophe), et **retour à la gare la plus proche** à vitesse réduite
  (avec changement de sens si elle est derrière) pour les pannes qui
  arrêtent la rame (400 V, frein parking, aiguillage).
- **Avis passagers** : plus étoffés (nombreuses nationalités), affichés
  au bandeau **et dans le journal de bord** (persistant) ; un avis déjà
  en français n'est plus écrit deux fois ; piques demi-tour & portes
  ouvertes.
- **Correctifs** : R après un crash repart de la gare du crash ; le
  déraillement à l'aiguillage n'est plus confondu avec une collision de
  l'autre rame (qui, elle, s'est arrêtée ailleurs) ; le journal ne dit
  plus « Départ de Val Claret » lors d'une reprise en pleine voie ;
  tension câble à 0 à la rupture.

**v1.12.40** — mode chaos : finitions physiques + retours d'essai :
- **Câble rompu → tension à 0** : quand le câble tracteur se sectionne
  (emballement), la jauge de tension **tombe à zéro** (le brin de la rame
  pilotée n'est plus tendu) — plus d'à-coup fantôme au crash si le câble
  était déjà rompu.
- **R après un crash = le RETOUR** : après une collision à l'arrivée,
  appuyer sur **R** relance le voyage **depuis la gare où l'on s'est
  écrasé** (le retour), et non plus systématiquement depuis la gare de
  départ d'origine.
- **Piques sarcastiques demi-tour & portes ouvertes** : faire demi-tour
  inutilement ou **rouler portes ouvertes** en Défi déclenche des
  commentaires dédiés (bilingues).
- **Avis passagers en VO + traduction** au bandeau de résultat *et* à
  l'écran de game-over (l'avis « bon / correct » n'était pas affiché à la
  fin d'un trajet réussi — corrigé).
- **Manuel (43 p), README, menu d'aide (F1)** mis à jour, tout le
  programme bilingue FR/EN.

**v1.12.39** — mode Défi « chaos » : conséquences physiques + avis
passagers :
- **Survitesse / emballement** : en Défi, laisser la consigne à fond sur
  une descente chargée lève le plafond de vitesse — la gravité emballe la
  rame au-delà de 12 m/s (à vous de freiner : Espace / Maj).
- **Moteur détruit → câble rompu** : à +20 % de survitesse, message
  clair (« moteur détruit, CÂBLE ROMPU — freinez ! »). La rame découplée
  **suit alors la physique** (dévale, plus de contrepoids).
- **Fin dramatique au choix de vos bêtises** : collision au **vrai
  butoir** (la rame roule jusqu'au mur avant l'impact), **déraillement**
  à l'aiguillage en survitesse (> 13,5 m/s, au-dessus de la tolérance de
  certif), ou **collision frontale avec l'autre rame** (qui, elle, a
  freiné) à l'évitement.
- **Avis passagers** stylés par nationalité (interjection en VO +
  français, références locales), adaptés à la circonstance : voyage
  nickel (5★) → arrivée brusque (3★) → catastrophe (1★). Affichés au
  bandeau de résultat et à l'écran de game-over.

**v1.12.38** — doc du mode Défi : manuel (42 p) et menu d'aide (F1) mis
à jour avec le mode Défi complet — notation confort/précision/
régularité, absence d'auto-dock, alarme « TROP VITE », collision au
butoir et déraillement à l'aiguillage.

**v1.12.37** — MAJ auto débloquée, puissance, et Défi (décél, alarme,
déraillement) :
- **Auto-update qui restait bloqué** (« une console s'ouvre avec
  find <PID> et ça reste figé, l'exe n'est pas remplacé ») : la sortie
  « propre » via `QApplication.quit()` (tentée pour l'erreur `_MEI`)
  pouvait ne jamais rendre la main → le process restait vivant, le batch
  de swap attendait indéfiniment. Retour à `os._exit(0)` (sortie
  immédiate fiable) + le batch tourne désormais **sans fenêtre console**
  (`CREATE_NO_WINDOW`). Le swap installe le nom versionné et supprime
  l'ancien comme prévu.
- **Puissance ridicule en descente** (« je descends et il affiche 54 kW,
  600 en montée ») : si tu inversais et repartais avant la fin de
  l'embarquement, la rame descendait encore chargée (gravité qui assiste
  → quasi pas de puissance). Effectifs et contrepoids sont maintenant
  alignés sur la charge de la direction **au moment du départ**.
- **Décélération réaliste en Défi** : réduire la vitesse freine à
  1,2 m/s² (au lieu de 2,4 qui « jetait tout le monde en avant ») —
  ~60 m pour s'arrêter depuis 12 m/s, il faut anticiper.
- **Alarme « TROP VITE » anticipée** : dès qu'on dépasse le profil que
  l'automate tiendrait à cette position (plus « trop tard »).
- **Déraillement à l'aiguillage** : en Défi, franchir l'évitement Abt à
  plus de 11 m/s (40 km/h) fait dérailler — game-over + message
  sarcastique dédié.
- **Annonce d'accueil même à pleine vitesse** en Défi ; liste de
  messages sarcastiques étoffée (collision + déraillement).

**v1.12.36** — annonce d'accueil en gare haute réactivée : le message
« zone Grande Motte » (fichier 11) se déclenche à nouveau
automatiquement en approche finale de la Grande Motte. Il avait été
désactivé à tort — le charabia anglais signalé venait en fait de
l'ambiance de quai contaminée (corrigée), pas de cette annonce.

**v1.12.35** — alarme survitesse, à-coup de câble, ambiance, altitude :
- **Alarme rouge « TROP VITE »** au pupitre (clignotante) dès que la
  vitesse ne permet plus de s'arrêter au repère au frein de service —
  purement **indicative**, le sim n'intervient pas (à toi de freiner).
- **À-coup de câble à la collision** : l'impact fait bondir la jauge de
  tension (∝ vitesse d'impact), en plus de la secousse d'écran.
- **Ambiance de gare à l'approche** : jouée dès ~45 m du quai (par
  position, plus par la vitesse) — fini le silence pendant le fluage
  d'entrée en gare, l'ambiance ne « reprend » plus seulement après
  l'arrêt.
- **Altitude déplacée** dans le tableau latéral, juste sous le
  **Dénivelé** (au lieu de l'en-tête du pupitre).

**v1.12.34** — collision en bout de voie (mode Défi) :
- En **mode Défi**, le filet d'auto-docking Von Roll est **levé** : c'est
  au conducteur de freiner (la consigne devient réactive, 2,4 m/s²). Si
  tu ralentis **trop tard ou pas du tout**, la rame **percute le butoir**
  → écran de **COLLISION** avec secousse d'écran, flash rouge, vitesse
  d'impact et un **message sarcastique** tiré au hasard. R pour repartir.
  (En Normal/Auto, le régulateur dock toujours proprement — pas de
  crash possible par erreur de conduite.)
- L'arrivée en Défi est validée dès l'arrêt dans la zone de quai (±6 m),
  la précision d'arrêt notant l'écart exact au repère.

**v1.12.33** — exe versionné + erreur temp `_MEI` à la MAJ :
- **Nom d'exe versionné** : l'asset et l'exe installé s'appellent
  désormais `PerceNeigeSimulator_v1.12.33.exe` (clair, plus de
  `(1).new.new.exe`). L'auto-update installe le nouveau à côté, relance,
  puis supprime l'ancien.
- **Erreur « Failed to remove temporary directory …\_MEIxxxxx »** après
  la mise à jour : `os._exit(0)` sautait le nettoyage du dossier
  temporaire de PyInstaller. Sortie propre via `QApplication.quit()`
  (le bootloader efface son `_MEI`), avec exit dur de secours après 5 s,
  et le batch de swap nettoie en plus les `_MEI*` périmés.
  ⚠️ Comme l'asset change de nom, cette mise à jour est à télécharger
  une fois à la main ; les suivantes seront automatiques.

**v1.12.32** — confort réactif + vrai mode Défi (PC) :
- **Score de confort enfin réaliste** : il restait au max même après un
  arrêt d'urgence « tout le monde par terre ». Nouveau modèle ISO 2631 :
  pénalité quadratique sur l'excès d'accélération (au-delà de ~0,9 m/s²
  debout) + jerk + forte pénalité pendant un arrêt d'urgence. Un arrêt
  d'urgence fait chuter le confort (~50 pour le frein poulie, ~0 au
  parachute) ; la conduite douce reste à ~100.
- **Mode Défi opérationnel** (touche M) : conduite manuelle NOTÉE à
  l'arrivée sur trois critères — **confort** (40 %), **précision
  d'arrêt** au repère de quai (35 %), **régularité** sans urgence ni
  panne (25 %). Bandeau de résultat avec note /100 et étoiles, repère
  d'arrêt live au pupitre, et **record persistant** (survit aux
  fermetures).

**v1.12.31** — pannes bien plus rares + altitude au pupitre :
- **Pannes nettement moins fréquentes** (« encore beaucoup trop
  souvent ») : le hasard de déclenchement passe de 1/45 s à 1/240 s
  d'exposition, cooldown 20 → 90 s → environ un incident toutes les
  5-6 minutes (≈ un par trajet) au lieu de ~1/min. Déclenchement manuel
  toujours possible via le dialogue F.
- **Altitude instantanée** affichée dans l'en-tête du pupitre de
  conduite (PC), interpolée sur le profil réel (2111 m → 3032 m).

**v1.12.30** — bouton DÉMARRER qui débordait : le libellé était trop
gros (19 pt sur 320 px) et sortait des deux côtés. Bouton élargi
(460 px), police réduite (15 pt), texte tronqué proprement en dernier
recours — il tient désormais dans le bouton.

**v1.12.29** — écran d'accueil vide corrigé + noms de MAJ propres :
- **L'écran d'accueil était vide** (régression v1.12.27) : la fonction
  de dessin de l'écran-titre référençait `st` sans le définir →
  exception silencieuse dans le paint → rien à l'écran. Corrigé (test
  de rendu ajouté).
- **Noms d'exe de mise à jour qui s'accumulaient**
  (`...(1).new.new.exe`) : le fichier de staging dérivait du nom courant
  (`stem + ".new.exe"`) et se composait quand l'exe finissait déjà par
  « .new ». Passé à des noms fixes canoniques (`_pn_update_staged.exe`,
  `_pn_update_backup.exe`) — plus d'accumulation.

**v1.12.28** — auto-update : swap sûr (plus jamais d'exe perdu) :
- Le remplacement de l'exe à la fin du téléchargement pouvait
  **supprimer l'ancien exe sans installer le nouveau** (le batch faisait
  `del` avant `move` ; si l'antivirus verrouillait le fichier
  fraîchement téléchargé, le `move` échouait → appli disparue). Nouvelle
  séquence : renommer l'ancien en `.old`, installer le nouveau, et
  **restaurer l'ancien si l'installation échoue** — l'utilisateur n'est
  jamais laissé sans exe. (Bénéfice pour les mises à jour à partir de
  cette version.)

**v1.12.27** — lot de retours d'essai (écran-titre, auto, gares, base) :
- **Écran-titre PC refait** : rame et sens sont maintenant deux
  sélections séparées (bascules mises en évidence) + un bouton
  **DÉMARRER** — fini le départ au premier clic qui empêchait de régler
  la 2ᵉ option.
- **Allongement du câble corrigé** : la poulie motrice est en gare
  haute, donc la longueur pendante = LENGTH − s **quel que soit le
  sens**. Avant, à l'arrivée en bas il affichait 0,03 m (la valeur du
  haut) et ne se corrigeait qu'en inversant le trajet.
- **Annonce d'accueil (fichier 11) désactivée en automatique** : c'est
  un message de 54 s multilingue dont la partie anglaise (« please do
  not leave… ») tombait juste avant l'arrivée — reste diffusable via le
  menu ANNONCES.
- **Ambiance de gare à l'arrivée** : jouée dès que la rame est à l'arrêt
  en gare (avant : seulement portes ouvertes → silence total à
  l'arrivée). **Gare basse** dotée d'une ambiance distincte (elle était
  devenue identique à la haute).
- **Mode auto** : la rame annoncée correspond à celle choisie (plus de
  « rame 2 » aléatoire) ; le remplissage met à jour le **contrepoids**
  (déséquilibre de masse cohérent) ; le demi-tour attend l'arrêt +
  ouverture des portes + un temps de descente **avant** d'inverser le
  sens.
- **Base d'exploitation persistante** : rangée dans le dossier de
  données utilisateur (%APPDATA% / ~/.local/share), elle **survit
  désormais aux mises à jour** de l'exe (avant, à côté de l'exécutable,
  elle était effacée à chaque auto-update) — migration automatique de
  la base existante.

**v1.12.26** — pannes moins fréquentes + retenue = régénération (PWA + PC) :
- **Les pannes ne fusent plus** (« une toutes les 3 secondes ») : le
  scheduler tirait une probabilité PAR IMAGE (`random() > 0.0025`) —
  calibrée pour 60 Hz, mais sur un écran 144/240 Hz les pannes
  arrivaient 2,4 à 4× plus vite. Remplacé par un hasard exponentiel
  indépendant du framerate (λ = 1/45 s + cooldown 20 s → un incident
  toutes les ~60 s en moyenne, le temps de gérer chacun).
- **La retenue en descente est enfin de la RÉGÉNÉRATION, pas du frein**
  (« sur le PC il n'y a pas marqué régénération mais un pourcentage de
  frein ») : physiquement, un funiculaire retient une descente chargée
  par l'entraînement en génératrice (~42 kWh récupérés par descente,
  datasheet CFD), pas par le frein de service à friction — qui ne sert
  qu'à l'arrêt final et à l'urgence. Le modèle applique désormais une
  vraie force de freinage de l'entraînement (`regen_level`) : en
  descente chargée le frein de service reste à **0 %** et la jauge
  affiche la puissance **récupérée** (cyan « RÉGÉN »), avec bascule à
  hystérésis. Refonte appliquée aux deux moteurs physiques (PC + 3D) ;
  décélérations et distances d'arrêt inchangées (mêmes forces, seule
  l'attribution frein↔drive change).

**v1.12.25** — vue extérieure orbitale (PWA + PC) :
- **La vue « ensemble » n'est plus figée** : en vue extérieure (bouton
  VUE sur la PWA, touche **O** sur le PC avec la 3D embarquée F4),
  l'angle se règle dans tous les sens au glisser — un doigt sur
  tactile, clic gauche maintenu à la souris — et le zoom au pincement
  à deux doigts ou à la molette (distance 8–120 m, tangage borné).
  La caméra reste centrée sur la rame pilotée et la suit ; la position
  par défaut reproduit l'ancienne vue fixe.
- Côté PC, la touche O bascule FPV ↔ orbitale via le pont UDP
  (`ext_view`, appliqué sur changement) ; la souris agit directement
  dans la fenêtre 3D embarquée. Entrée ajoutée au menu d'aide (F1) et
  au manuel (42 p, couverture 1.12.25).
- (Release : la v1.12.24 n'a jamais été construite — incident de
  livraison d'événement GitHub Actions ; son contenu est inclus ici.)

**v1.12.24** — creux de vitesse à l'arrivée corrigé (PWA + PC) :
- « En gare du haut, la vitesse a diminué jusqu'à 0,1 m/s avant de
  réaccélérer à 0,75 m/s » : le feed-forward de pente de consigne
  (introduit par l'audit v1.12.21/23) se **cumulait** avec l'enveloppe
  d'approche quand la consigne descendait pendant l'arrivée (mode auto,
  ou molette baissée) → sur-freinage sous le profil, creux, puis
  remontée au creep. Le feed-forward est maintenant **exclusif** : la
  dérivée de la cible ACTIVE (consigne quand elle gouverne, enveloppe
  en approche/creep). Cas de non-régression « arrivée profil auto »
  ajouté aux deux bancs : v ne descend plus jamais sous 0,75 dans la
  zone de creep, arrivée propre.

**v1.12.23** — l'audit physique porté à la PWA/3D (banc `godot_project/bench_pannes_3d.gd`) :
- **Plafonds de panne progressifs côté 3D** : mêmes causes racines que
  le PC (fondu moteur + bleed-off référés au cap de panne) → référés au
  V_MAX machine, rampe de consigne 0,60 m/s² + feed-forward de pente.
  Mesuré : 10→6 m/s à ≤ 0,75 m/s².
- **Surveillance du plafond** portée (urgence auto si v > cap + 1 m/s
  12 s sans décélération franche — validée au banc par sabotage de
  consigne : déclenche à 15 s).
- **Pressostat frein de service** : l'urgence tombe ~3 s après le
  déclenchement de `service_brake_fail` (plus d'arrêt dans la frame).
- **Aiguillage Abt : arrêt AVANT l'évitement** — le point d'interlock
  (15 m en amont) devient la cible d'arrêt du régulateur : enveloppe,
  feed-forward, creep et docking s'y appliquent naturellement (le
  simple min() sur l'enveloppe dépassait l'aiguillage de ~175 m —
  banc : arrêt à s=1596 pour un aiguillage à 1611). Correctif appliqué
  aux DEUX versions (le PC v1.12.21 avait le même dépassement).
- Bouton tactile PANNE : déjà l'équivalent de l'acquittement (un appui
  panne active = clear) — inchangé.

**v1.12.22** — acquittement maintenance, rupture en descente vérifiée :
- **R à quai = acquittement maintenance** : une panne non catastrophique
  bloquait le départ jusqu'à la fin de son chrono (35–90 s). Rame à
  quai et à l'arrêt, R lève la panne (urgence relâchée, survitesse
  réarmée) et le départ est immédiatement possible — rappel affiché
  dans le panneau de panne. En ligne, le chrono reste la seule issue ;
  les catastrophiques gardent R = nouveau voyage.
- **Rupture de câble en descente — pente défavorable vérifiée au banc** :
  la rame découplée est tirée par tout son poids dans son sens de
  marche → décél nette 0,82 m/s² en zone 30 % (3,6 parachute −
  g·sinθ 2,78), 87 m d'arrêt depuis 12 m/s contre 18 m câble intact,
  indépendant de la charge. Cas ajoutés au banc `tests/bench_pannes.py`.
- **Documentation à jour** : manuel du conducteur (`manuel_perce_neige.pdf`,
  41 p, FR+EN) et guide théorique (`guide_theorique.pdf`, 14 p, FR+EN)
  recompilés — chaînes de sécurité automatiques, acquittement R,
  arrêt électrique régénératif 0,45 m/s², rupture en descente chiffrée,
  panneau de panne en bandeau bas.

**v1.12.21** — audit physique complet des pannes et des arrêts
(détail : `AUDIT_PHYSIQUE_PANNES.md`, banc reproductible
`tests/bench_pannes.py`) :
- **Les plafonds de panne ne « piquent » plus** (« le funi réduit sa
  vitesse quasi instantanément ») : le moteur n'est plus coupé en une
  frame au déclenchement — le cap passe par une rampe de consigne
  dédiée 0,60 m/s² avec feed-forward de pente. Rails humides 10→6 m/s
  en ~7 s à ≤ 0,75 m/s² au lieu de 2,5 s à 1,82.
- **Chaînes de sécurité automatiques** : frein de service dégradé →
  urgence auto en ~3 s (fini « le funi continue à fond avec 0 kW et le
  frein à moitié serré ») ; dépassement persistant d'un plafond de
  panne → urgence ; interrupteur de mou de câble et seuil rouge de
  tension actifs pendant leurs défauts.
- **aux_power** : le frein à manque de courant s'applique vraiment
  (la rame accélérait en roue libre à 13,2 m/s) ; **parking_stuck** en
  marche freine réellement ; **aiguillage Abt** : arrêt AVANT
  l'évitement, pas un simple 2 m/s.
- **Arrêt électrique conforme doctrine** : ≈ 0,4 m/s² dans les deux
  sens via régen contrôlée (mesuré avant : jusqu'à 1,0 en montée, et
  141 m pour s'arrêter depuis 6 m/s à cause d'une consigne qui
  remontait) .
- Validés tels quels (physique correcte) : urgence commandée
  1,25 m/s² ± gravité, parachute 3,6 + gravité, rupture de câble en
  montée à 6,4 m/s² (Belleville + pente, pas un bug).

**v1.12.20** — F4 instantané, panneau de panne dans le bandeau bas :
- **Recycler F4 vers la vue 3D est instantané** : en quittant la vue 3D,
  le viewer Godot reste vivant et embarqué, simplement masqué (il
  continue de recevoir l'état à 60 Hz) — au retour, il réapparaît là où
  il en est au lieu de repayer 1-3 s de lancement + chargement de scène.
  Il n'est tué que s'il n'a jamais fini de s'embarquer, si son process
  meurt (watchdog, étendu au viewer masqué) ou à la fermeture du sim.
- **La description des pannes vit maintenant dans le bandeau du bas**,
  entre le journal de bord et le panneau d'auto-exploitation (slot
  480×210, mise en page compactée, sévérité inline). Conséquence : la
  vue 3D n'a plus besoin d'être cachée pendant une panne — on garde la
  3D ET le descriptif lisible en même temps.

**v1.12.19** — la 3D embarquée ne masque plus l'interface, vrai mute :
- **Les panneaux F1/F2/F3, la description des pannes et la pause sont
  enfin lisibles avec la vue 3D active** : la fenêtre Godot embarquée
  est une fenêtre native enfant — elle passe TOUJOURS au-dessus de ce
  que Qt peint dans son rect (bataille d'airspace), donc l'aide, la
  console d'annonces et le panneau de panne étaient masqués. Tant qu'un
  de ces overlays est ouvert, la 3D est automatiquement cachée (le
  process continue de tourner) et la vue cabine procédurale reprend le
  rect — on garde une vue du tunnel ; à la fermeture du panneau, la 3D
  réapparaît là où elle en est.
- **La pendule n'est plus coupée en deux** : le rect de la 3D démarre
  sous le pill horloge (y=44) au lieu de passer dessous.
- **N = un vrai bouton de volume** : couper le son ne stoppe plus les
  players ni ne vide la file — toutes les sorties audio sont mutées,
  les annonces/séquences/boucles continuent leur cours en silence, et
  au dé-mute on réentend tout exactement là où ça en est (la v1.12.18
  interrompait la séquence de fermeture ; l'interruption reste pour
  Échap / nouveau trajet / annonce manuelle). Le mute est aussi relayé
  au viewer 3D embarqué (bus Master Godot), qui restait sonore.

**v1.12.18** — ambiances de quai nettoyées, mute pendant la fermeture :
- **Le buzzer de portes ne joue plus en boucle au lancement** : les
  ambiances de quai (`real_station_lower/upper.wav`, jouées en boucle à
  l'arrêt portes ouvertes) étaient des extraits bruts des vidéos de
  référence contenant… le buzzer de fermeture (gare basse, pics
  1685/2106/2527 Hz identifiés au spectre) et des annonces PA captées
  sur le quai réel — d'où le buzzer permanent à l'allumage et les
  « annonces parasites en anglais sorties de nulle part ». Les deux
  boucles sont reconstruites à partir de la seule fenêtre propre du
  clip gare haute (t=2,1–7,3 s : brouhaha de hall sans voix ni buzzer),
  refermées par fondu circulaire equal-power de 0,8 s.
- **Couper le son (N) pendant la séquence de fermeture ne bloque plus le
  départ** : le mute arrêtait le player au milieu de l'enchaînement
  annonce → buzzer → portes, donc l'EndOfMedia final n'arrivait jamais
  et `_close_seq_active` restait vrai à jamais — PRÊT refusé
  (« séquence sonore de fermeture en cours ») et train cloué à quai.
  Toutes les voies d'interruption (mute, stop, reset, annonce manuelle)
  résolvent maintenant la séquence et son callback, comme le fait déjà
  le chemin « déjà muet » ; le verrouillage physique des portes
  (doors_timer) reste inchangé.

**v1.12.17** — le check de mise à jour affiche enfin son résultat :
- « Vérifier les mises à jour » ne faisait **rien** (ni dialogue « à
  jour », ni proposition d'installation), et le check silencieux du
  démarrage ne proposait jamais les nouvelles versions : le résultat du
  thread réseau était renvoyé au GUI par un `QTimer.singleShot` créé
  **depuis le thread de fond** — sans boucle d'événements Qt dans un
  `threading.Thread`, ce timer ne se déclenche jamais (vérifié au banc :
  le callback n'est PAS appelé, alors qu'un signal Qt inter-threads est
  bien délivré). Remplacé par un signal `pyqtSignal(object, bool)` en
  livraison en file d'attente. ⚠️ Les exécutables ≤ 1.12.16 ne peuvent
  donc pas se mettre à jour seuls : télécharger cette version une fois
  à la main depuis la page Releases.

**v1.12.16** — charge symétrique, embarquement progressif dès le départ :
- **La puissance ne dépend plus de la cabine choisie** (« quand je prends
  la rame qui descend, la puissance affichée est inférieure ») : la rame
  montante était tirée 2 × (90..167) passagers (moyenne ~257) quand on la
  pilotait, mais 90..314 en un seul jet (moyenne ~202) quand elle était
  le contrepoids — soit ~4,4 t de déséquilibre en moins en pilotant la
  descente. Les deux rames tirent désormais leur charge dans la même loi
  (montée 2 voitures de 90..167, descente 2 voitures de 0..8) :
  l'installation est statistiquement identique quel que soit le côté
  piloté. Corrigé aux trois points de tirage (départ + demi-tour PC,
  `roll_pax` 3D).
- **Embarquement progressif dès le trajet initial sur le programme PC**
  (il n'existait qu'au demi-tour — la PWA/3D l'avait déjà au lancement) :
  les rames partent vides à quai, les effectifs glissent vers les cibles
  à ~12 pax/s portes ouvertes, masse et tension suivent en direct.

**v1.12.15** — accostage progressif, finitions réalisme :
- **Arrêt en gare enfin progressif** (« l'arrêt en gare supérieure est
  instantané ») : détection d'arrivée SERRÉE portée du PC (serrage
  uniquement à |v| < 0,08 m/s et à 8 cm du repère — le docking finit
  naturellement), feed-forward d'enveloppe dans le régulateur (vraie
  dérivée de la cible −a·(v/v_cible) : il SUIT le profil au lieu de le
  poursuivre avec 0,4 m/s de retard et de finir sur le butoir), et
  serrage du tambour rampé à 1,2 m/s². Pic de décélération finale :
  ~15 → 1,33 m/s², approche 0,44 → 0,20 → 0,08 m/s sur les 3 dernières
  secondes. 2D + 3D, deux gares.
- **L'affaissement d'embarquement persiste jusqu'au départ** (il
  « remontait » à tort au PRÊT/DÉPART) : l'allongement élastique reste
  tant que la charge est là — la rame part de sa position affaissée et
  l'écart se fond dans le trajet.
- **Boucles d'ambiance indétectables** : fondu circulaire de 4 s entre
  les segments les plus corrélés du fichier (recherche par corrélation
  normalisée), gain compensé exactement (RMS constant à 0,2 dB), import
  PCM (plus d'artefact codec au bouclage).
- **Néons dans le tube d'évitement droit** (voie rame 2) — il était noir.
- Manuel mis à jour (tensiomètre 2 brins + zones réalistes, jauge RÉGEN,
  creep 0,75 m/s + rampe de docking, rebond analytique ±25-45 cm,
  affaissement d'embarquement), FR + EN.

**v1.12.14** — départ à gravité excédentaire réparé, sons lissés,
affaissement d'embarquement :
- **« Elle n'a jamais voulu repartir »** (inversion en descente pour
  remonter) : le creep-kill (« frein > 0 et quasi-arrêt → v = 0 »)
  gelait définitivement les départs où la gravité fait le travail
  (contrepoids chargé qui tire la rame vide vers le haut : le régulateur
  en force module au FREIN dès le départ → v recollée à 0 chaque frame).
  Le kill ne s'applique plus que si l'arrêt est VOULU (régulateur en
  maintien, urgence, gros frein manuel). 2D + 3D. La grille de
  validation vérifie désormais que chaque scénario DÉMARRE (18/18).
- **Boucles d'ambiance sans couture** : fondu circulaire hors-ligne à
  puissance constante (la fin du fichier est fondue dans son début sur
  1,5 s) — le raccord de boucle est continu par construction, sans
  variation d'amplitude. Fichiers 30 → 28,5 s.
- **Son d'évitement fondu** : entrée et sortie du clip de croisement en
  fondu de 0,7 s calées sur la géométrie — plus de coupure sèche aux
  aiguillages ; le corps du clip joue à volume constant.
- **Affaissement d'embarquement (3D)** : à quai, chaque passager qui
  monte allonge élastiquement le brin (δ = Δm·g·sinθ·L/EA) — en gare
  basse la rame descend doucement jusqu'à ~40 cm pendant le remplissage,
  puis l'entraînement la remonte au repère pendant le buzzer
  (pré-tension) ; millimétrique en gare haute, l'asymétrie sort de la
  longueur du câble. Visible aussi sur le wagon opposé.

**v1.12.13** — tension à DEUX brins, régulateur en force, embarquement
progressif (2D **et** 3D) :
- **Tension câble : max des deux brins à la poulie.** L'ancien modèle
  « brin de la rame lourde » ignorait l'autre brin : à l'arrivée en haut à
  pleine charge il affichait ~3 000 daN alors que le brin de la rame vide
  EN BAS portait ~12 700 (3,4 km de câble pendu ≈ 9 900 daN + son poids),
  puis sautait à ~14 000 à l'échange de passagers. Désormais chaque brin
  est calculé avec SA rame, SA pente, SON câble et SON inertie
  (rame + brin) — la jauge suit le brin le plus chargé, continûment.
- **Embarquement progressif** (~12 pax/s par voiture, portes ouvertes) :
  fini l'échange de masse instantané au demi-tour — la tension glisse de
  12 767 à 13 994 daN pendant que les passagers tournent. Si on part
  avant la fin, on part avec ceux qui sont montés.
- **Régulateur unifié en FORCE** : accélération désirée bornée
  [−frein service ; +rampe programmée], force requise = m·a_dés + charge
  statique (gravité 2 pentes + frottements) → traction si positive,
  retenue sinon. Continu dans les 4 quadrants. Corrige la puissance qui
  tombait à 0 en pleine accélération au départ gare basse : le contrepoids
  attaque sa section à 27-29 % pendant que la rame chargée est sur les
  8-16 % du bas → gravité nette brièvement MOTRICE (s ≈ 120-330 m) — le
  moteur fournit maintenant le complément exact (creux à ~40 kW, sans
  jamais claquer à 0).
- L'amortisseur numérique du butoir (±2 m/s²) est exclu de l'inertie de
  tension (il ajoutait ~18 000 daN fantômes au contact du point d'arrêt).
- Validation : parité statique PWA↔PC au 0,1 daN (5 points, nouveau
  modèle), demi-tour continu (saut max 1 222 daN/frame = relâchement
  d'inertie au serrage, lissé à l'affichage), grille 60 scénarios sans
  échec, 16/16 tests desktop (assertion d'arrivée mise à jour au modèle
  2 brins).

**v1.12.12** — à-coups de puissance éliminés (2D **et** 3D), audit balayage :
- Toutes les **marches d'escalier** du modèle remplacées par des fondus
  continus : coupure moteur au plafond de vitesse (elle hachait la force à
  60 Hz — 910 sauts > 100 kW/frame mesurés au banc sous plafond de panne,
  0 après), verrou de gravité excédentaire (autorité de traction en fondu
  sur 6 000 N au lieu du tout-ou-rien), bascule RÉGEN/traction (seuil
  2 000 N + hystérésis d'affichage 15/30 kW).
- Plafond de panne : la CIBLE du régulateur est bornée aussi côté 3D
  (porté du PC) — le régulateur ne pousse plus contre la limite.
- **Audit balayage 60 scénarios** (5 positions × 3 charges × 2 sens ×
  2 vitesses × 40 s) : zéro NaN, tension dans [0 ; 45 000 daN], accél
  bornée, jamais traction et régen simultanées, zéro survitesse, zéro
  à-coup hors pics d'inrush (voulus). Parité statique PWA↔PC intacte,
  16/16 tests desktop.

**v1.12.11** — traction/retenue en descente lourde + jauges (2D **et** 3D) :
- **Plus de traction fantôme en descente lourde** (constaté après une
  inversion en tunnel) : quand la gravité pousse déjà dans le sens de
  marche, le moteur reste coupé — la gravité accélère (bridée par la rampe
  de confort = retenue de l'entraînement) et le frein module.
- **Retenue régénératrice affichée** : la jauge puissance bascule en RÉGEN
  (cyan, valeur négative) — ~560 kW en descente chargée à 12 m/s, soit
  ~47 kWh par descente (datasheet CFD : ~42 kWh). Jamais affiché avant.
- **Tension câble : inertie signée par la rame lourde le long de SA pente**
  (T = m·g·sinθ + m·a) : une rame lourde qui dévale DÉCHARGE le brin —
  l'ancien code ajoutait l'inertie dans les deux cas.
- **Feed-forward du régulateur à deux pentes** : l'ancien raccourci
  mono-pente se trompait de signe quand l'asymétrie du profil l'emportait
  sur l'écart de masse (rame chargée en bas à 22 % vs contrepoids vide à
  29 %) — la rame dérivait vers l'équilibre au lieu de suivre la consigne.
- **Jauge de tension à l'échelle de service** (0–42 000 daN, plus 0–rupture :
  le vert faisait 12 % de la barre) : vert jusqu'à l'alerte 28 000 — le
  nominal 22 500 est une valeur de service, marquée d'un repère, pas un
  seuil d'alarme — orange 28–35 000, rouge au-delà, rupture hors échelle.
- Cadran vitesse : lecture km/h sortie du cadran (elle chevauchait les
  graduations basses).
- 16/16 tests physique desktop verts (les 2 nouveaux cas de descente
  asymétrique compris).

**v1.12.10** — audit de parité physique PWA/3D ↔ programme PC (le port 3D
datait de la v1.9.1 et avait raté plusieurs corrections) :
- **Passagers enfin embarqués dans la 3D** : trafic skieur asymétrique comme
  sur PC (montée chargée 180–334 pax, descente quasi vide, contrepoids
  inversé), re-tirage à chaque demi-tour — avant, les deux rames restaient à
  0 pax → déséquilibre nul, gravité nette nulle, compteur pax figé à 0.
- **Pente locale de CHAQUE rame** dans la gravité nette et le frottement
  (profil asymétrique 8 % → 29,5 % → 6 % ; l'ancien port appliquait la pente
  de la rame pilotée aux deux).
- **Tension câble complète** : poids propre du câble (11 kg/m, jusqu'à
  ~9 900 daN quand la rame lourde est en bas) + pente locale de la rame
  LOURDE — la jauge évolue maintenant le long du trajet comme sur PC.
- **Interpolation physique linéaire** (comme le PC) : gravité/tension/altitude
  **identiques au dixième près** sur tout le profil (banc de parité 5 points) ;
  le smoothstep reste réservé à la géométrie 3D.
- **Arrêt d'urgence = frein poulie 1,25 m/s²** (norme passagers debout, comme
  le PC depuis l'audit décélérations) : arrêt depuis 12 m/s en montée chargée
  en 37 m — la table PC donne 38 m.
- **Docking final v1.12.3 porté** (0,15 m/s² sur 2,5 m — fini l'entrée en gare
  interminable), auto-park après arrêt d'urgence, bleed survitesse bidirectionnel.
- Banc validé : montée pleine charge 7,1 min, vmax 12,0 m/s, tension max
  24 100 daN (pic inrush), P max 1 240 kW.

**v1.12.9** — retours d'essai iPad/PWA :
- **Câble & profil de ligne suivent la rame pilotée** : en scénario « rame 2 »,
  c'est le bon brin (voie droite) qui reste accroché à la cabine — visibilité,
  animation des torons et coupe fragment échangées ; le mini-profil étiquette
  la rame pilotée « R2 » et l'opposée « R1 ».
- **Plus d'annonce intempestive après le demi-tour** : l'annonce de sortie
  (« Sortie des passagers » amont/aval) ne se déclenche plus automatiquement à
  l'ouverture des portes du terminus — elle était perçue comme une annonce de
  panne. Elle reste diffusable à la demande (bouton ANNONCES).
- **Parois du tunnel translucides en vue extérieure** (alpha 0,22, faces avant
  coupées) : on voit la rame à l'intérieur du tube ; opaques en vue cockpit.
- **Bouton PRÊT/DÉPART actif en mode auto** : il force le départ sans attendre
  les 30 s de stationnement (l'automate embraie sur la séquence lancée).
- **Arrêt d'urgence adouci** : décélération 5,0 → 3,0 m/s² et rampe 8 → 4/s
  (jerk divisé par ~3), reste plus ferme que le frein de service (2,5).
- **Menu des annonces audio** : nouveau bouton ANNONCES → 14 messages
  (sortie, incidents, évacuation, remise en route…) diffusables à la demande,
  avec STOP et FERMER.

**v1.12.8** — vue 3D : rebond élastique du câble à l'arrêt en gare basse
(±31 cm, T ≈ 6 s, amorti — millimétrique en gare haute : l'asymétrie sort
de la longueur du câble), arrivée temporisée 15 s frein tambour serré
avant l'ouverture des portes, sélecteur de scénario au démarrage (gare de
départ + rame 1/2), boutons de conduite grisés en mode auto, bouton PANNE
protégé (double-tap), habillage tactile nettoyé.

**v1.12.7** — retours d'essai iPad/web généralisés au desktop :
- **Annonces vocales réparées dans les builds exportés** (le viewer 3D
  autonome n'en jouait aucune depuis toujours : le scan des MP3 ne voyait
  pas les noms remappés `.import` des exports).
- **Séquence de départ en 3 phases aux durées réelles des enregistrements** :
  annonce « fermeture des portes » (7,5 s) → fermeture des portes (7,0 s) →
  buzzer 8 s (gare basse) / 6 s (gare haute) → traction.
- Annonce « zone Grande Motte » en approche finale de la gare haute
  uniquement (plus d'annonce fantôme à quai), défilement 3D interpolé
  (fini les saccades à haute fréquence d'affichage), arrêt de panne par
  frein d'urgence rampé (2,5 m/s², plus d'arrêt sec), pannes aléatoires du
  mode auto désactivées, néons en allumage progressif.
- **Version Web/PWA jouable sur tablette** (Safari/Chrome, contrôles
  tactiles, audio anti-mode-silencieux iPad).

**Fidélité au réel** (calibrée sur photos/vidéos embarquées + témoignage
d'un utilisateur régulier de la ligne) :
- **Évitement en deux tubes séparés** (conforme au chantier de 1991 : « tube
  d'évitement » distinct, contrairement à Val d'Isère) avec zones de fusion
  binoculaires calculées aux extrémités ; les deux voies divergent
  symétriquement, l'évitement est décalé 25 m vers l'aval (la rame montante
  est à l'abri dans son tube avant l'arrivée de la descendante).
- **Voie fidèle** : blochets indépendants sous chaque rail, longrine centrale
  continue portant les 256 paires de galets du câble. **Gares** : quais en
  escalier de 3 m des deux côtés (marches-paliers calées sur la pente, nez
  alu en bas / rouges en haut), sans garde-corps.
- **Tunnel éclairé uniformément** tout du long, un néon sur deux allumé.
- **Physique vérifiée au banc** : tension du câble avec son poids propre
  (~22 000 daN en bas → ~4 000 en haut), rebond élastique à l'arrêt en gare
  basse (k = EA/L : ±27 cm, période ~7 s — millimétrique en gare haute),
  freins réels (arrêt d'urgence poulie 1,25 m/s² ≠ parachute Belleville
  3,6 m/s²), cascade de survitesse +10/+12/+20 %, **entrée en gare à
  0,75 m/s**, verrou du contacteur de traction (aucun départ possible sans
  séquence PRÊT + buzzer).
- **Son asservi** : boucles d'ambiance réelles sans couture, hauteur moteur
  calibrée 172→202 Hz selon la vitesse, croisement synchronisé à la
  géométrie de l'évitement (position ET vitesse de lecture), freinage
  d'approche et ambiances de quai réels, ducking sous les annonces.

**Sécurité & robustesse** :
- Auto-update vérifié **SHA-256** (`SHA256SUMS` publié par le CI), sortie et
  swap fiabilisés, journal dans `%TEMP%\perce_neige_update.log`.
- Vue 3D sans Godot installé : viewer publié en asset de release,
  **téléchargement automatique** proposé au premier F4 (mode source).
- Intégration 3D blindée : watchdog, heartbeat UDP, auto-fermeture du
  viewer orphelin, validation des paquets.
- **16 tests physiques anti-régression** exécutés par le CI à chaque push.

**Performance 3D** : géométrie en tronçons de 120 m + échantillonnage
adaptatif (1,64 M → 0,73 M vertices, frustum culling efficace), lumières
activées à moins de 450 m des rames, préréglages
`--quality=low|medium|high`, diagnostic `--mesh-stats`.

---
