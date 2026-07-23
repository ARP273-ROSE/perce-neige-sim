![Perce-Neige Simulator](logo.png)

# Perce-Neige Simulator

![Python](https://img.shields.io/badge/python-3.9+-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey.svg)

**Drive the longest funicular in France — 3 474 m of underground tunnel from Val Claret (2 111 m) to the Grande Motte glacier (3 032 m) in Tignes, France.**

An accurate PyQt6 simulation of the *Perce-Neige* underground funicular (built 1989–1991, opened 14 April 1993 by Von Roll / CFD). Distant descendant of the author's 2006 TI-84 `FUNIC` program — same spirit, real physics, proper graphics.

---

## Quoi de neuf — v1.12.x (audit + retours d'essai terrain, juillet 2026)

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

## Features

### Real-world fidelity
- **Slope length** 3 474 m (cockpit counter reference), **vertical drop** 921 m, altitudes 2 111 m → 3 032 m
- **Gradient profile** from 8 % (gentle square-section start) to 30 % (steepest sustained middle), eases to 6 % at the upper square-section platform — calibrated directly against the real cockpit video
- **Square cut-and-cover** at both ends (s < 257 m and s > 3 420 m), **round TBM bore** through the middle — exact transition distances read from the on-board counter
- **Passing loop** s=1 601 → 1 823 m, curves at s=1 297 → 1 541 m and s=1 884 → 2 369 m
- **Speed** capped at 12 m/s (43.2 km/h) — the Von Roll regulator limit. In the reference cockpit video the driver cruises at ~10.1 m/s (speed_cmd ≈ 84 %), giving the real 7 min 54 s Val Claret → Grande Motte trip time ; you can push to full 12 m/s in the sim.
- **Train** : two coupled cylindrical cars, ∅ 3.60 m, 32 t empty, up to 334 passengers (58.8 t max)
- **Motors** 3 × 800 kW DC at the upper drive station, below the *Panoramic* restaurant
- **Cable** 52 mm Fatzer, nominal 22 500 daN, breaking 191 200 daN

### Physics
- Variable-gradient integration with position-dependent slope
- Mass-aware gravity, rolling resistance, motor force with `P = F·v` envelope
- Normal brake (2.5 m/s²) and emergency brake (5 m/s²)
- Live **cable tension** estimate with nominal / warning / breaking bands
- **Comfort score** via jerk integration
- **Energy score** in kWh
- **Honest real-time integration** : every physics step advances by the
  actual wall-clock delta measured via `time.monotonic()` (clamped to
  [1 ms, 100 ms]). Earlier builds used a hardcoded 16 ms assumption —
  under Windows timer granularity and typical render load the real
  frame cost reaches 20–30 ms, so the sim used to drift down to ~48 %
  of real time. Now 12 m/s on the speedometer moves the train 12 m per
  real second

### Interface
- Faux-3D side view with yellow cylindrical cabins, coupled cars, windowed body, highlight strip, rounded end caps
- Animated **drive station cutaway** at the upper platform — three DC motors feeding a rotating drive pulley, cable visibly wrapping
- **Mini-map** across the top showing both trains' positions and the passing loop
- **Analog speedometer** in m/s (with km/h sub-label) + **tension gauge** in daN, both with green/yellow/red bands
- **Bar gauges** for speed command (% of V_MAX), brake, and motor power
- **Realistic cockpit button panel** — illuminated push-buttons for electric stop, emergency stop (red mushroom), dead-man vigilance, headlights, cabin lights, horn, doors, autopilot and sound
- Warning lights: doors, brake, cable, fault, speed limit
- **Scrolling snow** across the view, cosmic gradient sky
- **Event log** with FR/EN messages
- Fully **bilingual FR / EN**, auto-detected from system locale (toggle with `L`)
- **Bilingual hover tooltips** on every cockpit button and clickable HUD zone — describe the action, the keyboard shortcut and the physical semantics (e.g. 2.5 m/s² service brake vs. 5 m/s² rail brakes). Text flips instantly when you toggle the language

### Realistic driving regulator
- The driver sets a **speed command** (percentage of V_MAX = 12 m/s) with `↑` / `↓` — the regulator smoothly tracks it with a realistic accel/decel envelope, exactly like the real Von Roll speed programmer
- **Programmed station approach** : the envelope automatically clamps the setpoint so the train always has enough distance to reach the creep zone before the platform
- **Creep zone** : when the front is 20 m before the platform, the train crawls at 1 m/s through the 20 m approach and the 35 m platform, stopping flush at the platform end
- **Counterweight wagon** : the descending train *is* the counterweight — mechanically linked by the cable. In real operation the down-going wagon is almost always empty because skiers go *up* by funicular and come *back down on skis*; only the summer glacier season sees a handful of passengers coming down. The ascending train therefore has to lift close to a full load of net imbalance
- **Cable elasticity rebound** : after the main train stops at the upper station, the counterweight wagon at Val Claret creeps up ~1.2 m over 2 seconds because the long cable relaxes (motor is at the top)
- **Dead-man vigilance** : the driver must touch a control at least once every 20 s, otherwise the system triggers an automatic electric stop (press `G` to acknowledge)

### Cabin first-person view (F4)
> **NEW in v1.11.x** — F4 now **cycles 3 states** : OFF (side view) →
> built-in procedural cabin view (Python pinhole) → **Godot 3D viewer
> embedded** in the F4 area. The bundled standalone Godot binary is
> shipped inside the .exe / AppImage, nothing to install. The Python
> sim drives the physics over UDP at 60 Hz and the 3D viewer renders
> the real cockpit perspective with full Phase 4-10 features : tunnel
> TBM with chamber, Abt switch passing loop, machine room, animated
> cable, animated passengers, voice announcements. On Windows the
> Godot window is reparented as a true Win32 child (SetParent) ; on
> Linux X11 via xdotool + QWindow.fromWinId() + createWindowContainer.
> On Wayland / macOS, the Godot window opens separately.

#### Faut-il installer Godot ? / Do I need Godot installed?
**Non / No.**
- **Release .exe (recommandé)** : le viewer 3D est **embarqué dans
  l'exécutable** — rien à installer.
- **Depuis les sources (`git clone` + `launch.bat`)** : le binaire
  `bundled_godot/perce_neige_3d.exe` est **gitignoré** (~125 Mo) donc
  absent après un clone. Au premier F4, l'appli **propose de le
  télécharger automatiquement** depuis la dernière release GitHub
  (intégrité vérifiée SHA-256). Alternatives : le télécharger à la main
  depuis la page Releases dans `bundled_godot/`, installer Godot 4.6
  (fallback dev), ou le builder via `./build_godot_viewer.sh`.
- Si aucun viewer n'est trouvable, F4 retombe proprement sur la vue
  cabine procédurale Python documentée ci-dessous.

Préréglages de rendu du viewer (arg projet) : `--quality=low|medium|high`
(low : SDFGI + fog volumétrique + SSR coupés — pour iGPU).

#### Built-in procedural cabin view (fallback)
- **Real pinhole-camera perspective** — `screen_r = focal · R_tunnel / d`
  with a 72° horizontal FOV, matching the wide driver windshield and the
  tight 3.1 m TBM bore
- TBM segment pitch 1.5 m : at 12 m/s, 8 rings stream past every second,
  with the correct 1/d size falloff that makes near walls fill the view
- **Wall fluorescents** : long horizontal tubes (~1.6 m, spaced 12 m)
  on the left wall while climbing / right wall while descending —
  layered halo + mid-glow + bright core, exactly like the HD footage
- **Headlights gate visibility** : off → you barely see a few metres of
  concrete and only the wall neons as beacons ; on → the beam reaches
  ~260 m with Beer-Lambert exponential falloff, far enough to actually
  *see* the tunnel curving up or down through the gradient breaks
- Sleepers drawn one per ring with a central cable-guide bolt, rails +
  cable guide connect smoothly between consecutive rings
- Correct handling of curves (lateral offset `½·focal·κ·d`) and passing
  loop double-bore on the opposite wall
- **Exact 3D vertical curvature** — every tunnel ring, wall panel,
  platform edge and ghost-wagon vertex is projected through a true
  pinhole camera frame (forward + altitude difference rotated by the
  local slope pitch), so a gradient break ahead is rendered with the
  same geometric fidelity as a horizontal turn
- **Continuous floor / ceiling / arch envelope polylines** drawn across
  successive rings give vertical curvature the same visual clarity that
  rail continuity gives to horizontal turns

### Side-profile view (default)
- **Researched gradient profile** — 15 % at Val Claret ramp-up, 30 %
  sustained in the mid-tunnel main climb, 12 % easing out onto the
  Grande Motte glacier platform, pronounced break at ~3 180 m
- **Mouse-wheel zoom** (or `+` / `-` / `0` to reset) with an aspect-ratio
  lock : the visual slope angle is exactly the real slope angle at any
  zoom level — zooming reveals more detail without distorting steepness
- **Distance + elevation readout** : `travel / total m` and `Δalt / total m`
  are trip-relative (0 at departure platform, full span at arrival),
  direction-aware for descending trips

### Game modes
- **Normal** — just drive a trip
- **Challenge** — optimise time + comfort + energy
- **Faults** — 15 incident types, sourced from real documented funicular
  failures (STRMTG RM5, BEA-TT Glória Lisboa 2025, Kaprun 2000, Carmelit,
  Perce-Neige 2008 outage, Montmartre 2006, Sassi-Superga, M2 Lausanne).
  Random weighted scheduler by default; press **F** to open the manual
  picker dialog (choose a specific fault or toggle auto/manual scheduler)

### Fault catalogue (press F in Faults mode)
Common operational faults : `tension`, `door`, `thermal`, `fire`,
`wet_rail`, `motor_degraded` (M1/M2/M3 named, Sassi-Superga precedent),
`slack`, `aux_power` (Perce-Neige 2008 pattern), `parking_stuck`.
Severe / catastrophic : `cable_rupture` (Glória Lisboa 2025 class),
`service_brake_fail` (Glória double-failure), `flood_tunnel`,
`comms_loss` (Kaprun lesson), `switch_abt_fault` (Abt crossing interlock),
`fire_vent_fail` (fire + désenfumage down, Kaprun class).

Physics realism : overspeed cascade in three stages per EP0392938A1
POMA + STRMTG RM5 — +10 % service brake, +12 % secondary emergency,
+20 % mechanical Belleville parachute centrifugal trip. Cable cumulative
fatigue counter (Palmgren-Miner, ISO 4309 / DIN EN 12927-6) tracks
round-trip cycles and `cable_wear_pct` for each trip.

### Fault realism — recovery state machine (v1.9.0 / v1.9.1)
Faults are now classified by **severity** and have realistic recovery paths :

- **Advisory** (`tension`, `wet_rail`, `slack`, `comms_loss`) — dashboard
  warning only, no operational impact, auto-clears
- **Operational** (`door`, `thermal`, `motor_degraded`, `flood_tunnel`) —
  degraded mode (speed cap, power derate), trip continues, auto-clears on
  timer
- **Stopping** (`aux_power`, `parking_stuck`, `switch_abt_fault`) — train
  must stop, then **READY (V) + DEPART (Z)** required to resume — releasing
  the brake alone never auto-restarts the trip
- **Catastrophic** (`cable_rupture`, `fire`, `fire_vent_fail`,
  `service_brake_fail`) — trip is **TERMINATED**. The phase machine runs :
  `active` → `intervention_called` (tech_incident PA) → `evacuating`
  (dim_light + evac PA, cabin lights dimmed, passengers evacuated) →
  `out_of_service`. READY/DEPART are blocked permanently — **press R for a
  new trip** from the menu sequence (the only way out of a Glória / Kaprun
  class event)

A persistent **on-screen panel** (top-left of the world view) tells the
driver in real time : what's happening, what to do, what's blocked, and —
for catastrophic faults — a 5-stage phase indicator and the explicit
"Press R for new trip" hint once evacuation has begun.

**v1.9.1 patch** — announcement queue hardening : every PA in the
catastrophic chain (`tech_incident` → `dim_light` → `evac`) now waits
for the previous one to fully finish before the next one fires, so no
message is ever cut off. The emergency brake squeal (`brake_noise`)
no longer loops forever once the cabin is parked out of service.

### Documentation download (F6)
Press **F6** to open the docs dialog : downloads the latest
`manuel_perce_neige.pdf` (user manual) and `guide_theorique.pdf`
(theory guide with full formula derivations, regulatory sources, audio
calibration validation) from the GitHub repo into your Downloads folder
and opens them in the default PDF viewer — handy when running the
standalone EXE which doesn't bundle the PDFs.

### Auto-update (GitHub)
- Background check on startup (3 s after launch) — silent unless an
  update is available
- Manual check via **Help → Check for updates**
- Downloads the release zipball from GitHub, validates size, rejects
  path-traversal and symlinks, copies a whitelist of files and restarts
- User data (venv, CLAUDE.md, `.git`, `crash_reports/`) is never touched

### Bug reports (anonymous)
- `sys.excepthook` writes an anonymized JSON crash report into
  `crash_reports/` if the app ever crashes
- Next launch offers to open a **pre-filled GitHub issue** — paths and
  user names are stripped before anything leaves your machine
- Manual report via **Help → Report a bug** : form with description +
  steps ; opens the same pre-filled issue URL in your browser
- **No telemetry** : nothing is sent automatically, nothing contacts a
  server without your explicit click

### Real cabin ambient sound
- Two long loops extracted from the real 10-minute HD cabin recording :
  a 25 s slow/approach segment and a 60 s steady-cruise segment,
  loudness-matched and crossfaded live based on the train's current
  speed — stops sound like stops, cruise sounds like cruise, no more
  11-second clip heard on repeat
- Volume ceiling lifted to ~95 % so the tunnel rumble actually feels
  like being inside the car

### Auto-exploitation mode (ambient)
- Press `X` to hand the line over to the simulator : boarding,
  doors-close chime, trip, passing-loop crossing, arrival,
  turnaround — round after round, from the published opening time
  (08:45) to the last scheduled descent (16:45)
- **Activate from any state** : at a terminus auto-ops begins a new
  boarding cycle, mid-tunnel it takes over the current trip, and
  after an incident halt it pre-arms READY and fires the buzzer
  automatically — no need to be at a station to hand over
- **`Shift+X` : 24/7 override** — ignore the published opening hours
  and let the line run continuously (useful for ambient background
  play outside the ski season window)
- **Live side panel** (bottom-right, next to the event log) :
  wall-clock, schedule, current phase with countdown, peak/off-peak
  band, day counters (trips, pax, distance). Green border inside
  hours, orange outside, purple pill when 24/7 is armed. Phase
  labels localise fully — in French the panel reads *EMBARQUEMENT*,
  *FERMETURE*, *ATTENTE PRÊT*, *DÉPART*, *EN VOIE*, *ARRIVÉE*,
  *OUVERTURE PORTES*, *INACTIF* instead of the raw English state
  names
- **`F5` : trip log viewer** — opens a dialog with the last 100
  round-trips and the last 60 daily-stat rows straight from
  `exploitation.db`
- **Peak vs off-peak cruise** : 12 m/s during the morning-rush and
  late-afternoon return windows, 10.3 m/s off-peak — the regulator
  picks the setpoint from the real clock
- **Passenger load varies with time of day** : morning ascents are
  heavy (skiers going up), late-afternoon descents are heavy
  (skiers returning) — the load samples feed the mass-aware physics
  so the cable tension reflects a realistic day
- **Input lockout while auto is running** : cockpit buttons and most
  keys are masked (only `X`, `P`, `N`, `L`, `F1`–`F5`, `Backspace`,
  `Esc` pass through) so you can't accidentally fight the state
  machine
- **Exploitation log** in `exploitation.db` (SQLite, WAL) : every
  round-trip records departure/arrival timestamps, direction,
  passenger count, cruise speed, distance, duration and incident
  count. A `daily_stats` table keeps the running km/pax/trips for
  the current day
- Meant to be left running in the background : you hear the cabin
  ambient, the buzzers, the announcements, the crossing whoosh
  exactly like a real day on the line

### Abnormal-stop sequence (Von Roll safety-chain fidelity)
- Any latched stop engaged **while rolling in the tunnel** — manual
  electric stop (`3`), emergency stop (`4`), overspeed auto-trip,
  dead-man vigilance loss, or a service-stopping fault (door,
  thermal, motor degraded, aux power, parking drum stuck, fire)
  — now triggers the full real-world abnormal-stop protocol :
  1. READY / ghost-ready / departure buzzer cleared immediately
  2. Cabin decelerates to a stop under its own physics
  3. Once `|v| < 0.1 m/s` the **incident announcement** plays
     (`tech_incident`, or `dim_light + evac` for fire), not at the
     moment the button is pressed
  4. `trip_started` flips back to `False` (trip formally suspended)
  5. **Parking drum engages** — raising the speed setpoint no longer
     moves the cabin on its own
  6. Driver releases the latched stop, presses READY (triggers the
     "Remise en route" announcement), then DEPART (buzzer, drum
     releases, trip resumes)
- At the termini the sequence short-circuits : messages play
  instantly and the drum doesn't need engaging since the doors-open
  parking state already holds the cabin still
- Silent-advisory faults (cable tension, wet rail, slack cable) are
  unchanged — dashboard only, no PA, no forced stop

### Real on-board announcements
- Authentic recordings from the actual Perce-Neige cabins, bundled under
  `sons/Funiculaire perce neige/`
- Played automatically at the right moment : doors closing, welcome,
  minor/technical incident, 10 min stop, restart, evacuation, upstream
  passenger exit, dimmed lighting, brake noise, etc.
- 5 languages per message (FR / EN / IT / DE / ES) — the game picks the
  current UI language (FR or EN) and queues FR then EN like the real train.
- Press `N` at any time to mute / unmute.
- Press `F2` to open the manual announcement console : a 15-entry panel
  with hotkeys to trigger any message (doors closing, welcome, incident,
  evacuation, brake noise, …) on demand.

---

## Installation

**For everyone (recommended, no Python required)** — go to the [latest release](https://github.com/ARP273-ROSE/perce-neige-sim/releases/latest), download **`PerceNeigeSimulator-windows.exe`** and double-click it. Done. The app updates itself automatically when a new version is published on GitHub.

### From source (developers)

Windows :
```cmd
launch.bat
```

Linux / macOS :
```bash
./launch.sh
```

Both launchers create a local venv outside the project folder, install PyQt6 + Pillow, and launch the game.

Manual install :
```bash
pip install -r requirements.txt
python perce_neige_sim.py
```

### Building the standalone executable yourself

```bash
pip install pyinstaller pillow
python make_logo.py
pyinstaller perce_neige.spec
# → dist/PerceNeigeSimulator(.exe)
```

A GitHub Actions workflow (`.github/workflows/build.yml`) builds the Windows `.exe` automatically and attaches it to every tagged release.

---

## Controls

**Driving**

| Key              | Action                                            |
|------------------|---------------------------------------------------|
| `↑` / `W`        | Speed command + (raise setpoint %)                |
| `↓` / `S`        | Speed command − (lower setpoint %)                |
| `Space` / `B`    | Service brake (hold)                              |
| `Shift`          | Emergency brake (hold)                            |
| `3`              | **Electric stop** — latched service stop          |
| `4`              | **Emergency stop** — latched rail brakes          |
| `G`              | Dead-man vigilance acknowledge                    |

**Cockpit**

| Key              | Action                                            |
|------------------|---------------------------------------------------|
| `H`              | Headlights on / off                               |
| `C`              | Cabin lights on / off (dims the ride)             |
| `K`              | Horn (hold)                                       |
| `D`              | Doors open / close (only at a stop)               |
| `A`              | Autopilot toggle (programmed run)                 |
| `X`              | Auto-exploitation on / off (full-service ambient) |
| `Shift+X`        | 24/7 override — ignore published opening hours    |
| `N`              | Mute / unmute on-board announcements              |
| `Backspace`      | Abort the running announcement                    |

**System**

| Key              | Action                                            |
|------------------|---------------------------------------------------|
| `P`              | Pause / resume                                    |
| `M`              | Cycle mode : Normal → Challenge → Faults          |
| `L`              | Language FR / EN                                  |
| `F1`             | Help overlay on / off                             |
| `F2`             | On-board announcement console (manual trigger)    |
| `F3`             | Real machine info overlay (specs + source links)  |
| `F5`             | Auto-exploitation trip log viewer                 |
| `R`              | New trip (after arrival)                          |
| `Enter`          | Start (from title screen)                         |
| `Esc`            | Pause / menu / quit                               |

---

## Specs used

Sourced from Wikipedia (FR + EN), `remontees-mecaniques.net`, and CFD's official page on the rolling stock :

| Property                  | Value             |
|---------------------------|-------------------|
| Length (along slope)      | 3 474 m           |
| Vertical drop             | 921 m             |
| Lower station             | Val Claret 2 111 m |
| Upper station             | Glacier 3 032 m   |
| Max gradient              | 30 %              |
| Max speed                 | 12 m/s (cruise ≈ 10.1 m/s) |
| Trains                    | 2 × 2 coupled cars |
| Capacity                  | 334 pax + 1 conductor |
| Empty / loaded mass       | 32.3 t / 58.8 t   |
| Motor power (total)       | 3 × 800 kW DC = 2 400 kW |
| Cable diameter            | 52 mm             |
| Cable nominal / breaking  | 22 500 / 191 200 daN |
| Tunnel diameter (min)     | 3.9 m             |
| Track gauge               | 1 200 mm          |
| Passing loop length       | ~200 m            |
| Built by                  | Von Roll / CFD    |
| Opened                    | 14 April 1993     |

---

## License

MIT. Author : ARP273-ROSE — 2006 TI-Basic original, 2026 PyQt6 port.
