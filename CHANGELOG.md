# Journal des versions — Perce-Neige Simulator

Historique détaillé, version par version, du plus récent au plus ancien.
Chaque entrée dit ce qui a changé, pourquoi (souvent un retour d'essai),
et comment ça a été vérifié. Le README ne garde que la présentation du
projet ; les versions antérieures à la 1.12 sont résumées dans le manuel.

## v1.13 → v1.15 (septembre 2026)

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
