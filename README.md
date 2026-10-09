![Perce-Neige Simulator](logo.png)

# Perce-Neige Simulator

![Python](https://img.shields.io/badge/python-3.9+-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS%20%7C%20Web-lightgrey.svg)

**Conduisez le plus long funiculaire de France** : 3 474 m de tunnel entre
Val Claret (2 111 m) et le glacier de la Grande Motte (3 032 m), à Tignes.

Simulation physique du funiculaire souterrain *Perce-Neige* (Von Roll / CFD,
construit de 1989 à 1991, ouvert le 14 avril 1993), avec les vrais sons et
les vraies annonces de la cabine. Descendant lointain d'un programme TI-84
de 2006.

*English : the user manual `manuel_perce_neige.pdf` is bilingual (FR/EN) and
the interface switches to English with the `L` key.*

---

## Deux façons de jouer

|                 | PC (Windows, Linux, macOS)                                                                     | Web, tablette, téléphone                                               |
|-----------------|------------------------------------------------------------------------------------------------|------------------------------------------------------------------------|
| **Où**          | [Télécharger l'installeur](https://github.com/ARP273-ROSE/perce-neige-sim/releases/latest/download/PerceNeigeSimulator-Setup.exe) (lien permanent) | <https://funiculaire.giff.re>                                          |
| **Quoi**        | Application PyQt6 : pupitre complet, vue en coupe du terrain, vue cabine 3D intégrée (pupitre cliquable, skieur), exploitation automatique, journal d'exploitation | Version 3D Godot 4, tactile (iPad, Android, PC), installable comme application, fonctionne hors ligne ; skieur jouable |
| **Mise à jour** | Automatique au démarrage                                                                       | Automatique                                                            |

L'installeur s'installe dans le profil utilisateur, sans mot de passe
administrateur. Au premier lancement, Windows peut afficher « Windows a
protégé votre ordinateur » (installeur non signé) : *Informations
complémentaires* puis *Exécuter quand même*. Les mises à jour suivantes ne
le déclenchent plus.

**Linux et macOS** — sur la [page de la dernière version](https://github.com/ARP273-ROSE/perce-neige-sim/releases/latest) :

- Linux : `PerceNeigeSimulator-…-linux.AppImage`, à rendre exécutable puis
  lancer. Fonctionne sur les distributions encore suivies (glibc ≥ 2.34 :
  Ubuntu ≥ 22.04, Debian ≥ 12, Fedora, RHEL ≥ 9, Mint ≥ 21, Arch,
  openSUSE…) ; essayée à chaque version sur six d'entre elles. L'archive
  `…-linux-x86_64.tar.gz` contient le même programme sans AppImage.
- macOS : `…-macos-apple-silicon.dmg` (M1 et suivants) ou
  `…-macos-intel.dmg`, à glisser dans Applications. L'application n'est
  pas signée par un développeur Apple : au premier lancement, clic droit →
  *Ouvrir* (ou Réglages Système → Confidentialité et sécurité → *Ouvrir
  quand même*).

La vue cabine 3D est incluse partout. Sous Linux et macOS, l'application
signale les nouvelles versions au démarrage ; on remplace alors l'AppImage
ou l'app.

---

## Les modes automatiques, en clair

Trois automatismes, trois noms (depuis la 1.18.5 — « les modes autos,
c'est un bazar intergalactique ») :

| Mode | Où | Commande | Ce qu'il fait |
|------|----|----------|---------------|
| **Pilote auto** | PC | `A` / bouton PILOTE | **Un voyage** tout seul : portes, PRÊT, 100 %, arrivée, portes, passagers ; puis rend la main. |
| **Exploitation auto** | PC et Web | PC : `X` ; Web : `F3` / bouton EXPLOIT. (tableau de bord et skieur) | **Tout le service** : embarquement, horaires, départs enchaînés, pannes du mode Pannes. Le skieur ne la change pas en apparaissant ; CONDUIRE l'arrête. |
| **Boucle du skieur** | Web (et vue 3D du PC) | `X` / bouton BOUCLE | **Le skieur** fait la boucle seul (gare, rame, terrasse, ski, retour) ; il enclenche l'exploitation auto pour son trajet. |

Conduire à la main = aucun des trois. En Défi et en Pannes, l'exploitation
auto est sans objet (on conduit).

## La vraie machine

Sources : Wikipédia (FR + EN), remontees-mecaniques.net, page CFD du
matériel roulant. Détail dans `SOURCES.md`.

| Caractéristique              | Valeur                          |
|------------------------------|---------------------------------|
| Longueur (le long de la pente) | 3 474 m                       |
| Dénivelé                     | 921 m                           |
| Gare basse                   | Val Claret, 2 111 m             |
| Gare haute                   | Glacier de la Grande Motte, 3 032 m |
| Pente maximale               | 30 %                            |
| Vitesse maximale             | 12 m/s (croisière réelle ≈ 10,1 m/s) |
| Rames                        | 2 × 2 voitures couplées         |
| Capacité                     | 334 passagers + 1 conducteur    |
| Masse à vide / en charge     | 32,3 t / 58,8 t                 |
| Motorisation                 | 3 × 800 kW à courant continu, en gare haute |
| Câble                        | Fatzer 52 mm, 22 500 daN nominal, 191 200 daN à la rupture, pas de câble lest |
| Diamètre du tunnel (mini)    | 3,9 m                           |
| Écartement                   | 1 200 mm                        |
| Évitement                    | ≈ 200 m, aiguillages Abt        |
| Constructeur                 | Von Roll / CFD                  |
| Ouverture                    | 14 avril 1993                   |

---

## Ce que simule le programme

- **Physique** : pente variable (8 % en bas, 30 % au milieu, 6 % en haut,
  calée sur la vidéo de cabine), masse selon la charge, résistance au
  roulement et traînée, moteurs à enveloppe P = F·v avec régénération,
  frein de service (2,5 m/s²), arrêt d'urgence (1,25 m/s²) et parachute
  sur rail (3,6 m/s², sur survitesse ou rupture du câble), tension du câble
  et fatigue cumulée, **câble élastique** en marche et à l'arrêt (rebond,
  recul de plus d'un mètre de la rame pleine en gare basse), poids propre
  du câble, contrepoids = l'autre rame. Chaque trajet fait 3 474 m au
  compteur ; arrêts à 1,5 m du butoir en haut, 4 à 5 m en bas.
  Modèle audité et chiffré avec SageMath : `AUDIT_PHYSIQUE_VOYAGES.md`.
- **Régulateur Von Roll** : consigne en % de 12 m/s, enveloppe d'approche
  programmée, rampement à 1 m/s, arrêt au repère, vigilance homme-mort.
- **Tunnel et gares d'après vidéos et photos** : tranchées couvertes carrées
  aux extrémités, alésage tunnelier au milieu, évitement Abt de 1 601 à
  1 823 m avec ses aiguillages dessinés (langues, lacunes où le câble
  opposé file entre deux bouts de rail pliés, cœur en X, galets de
  déviation), courbes où le
  câble file en ligne droite d'un galet au suivant, gares aux parois bleu
  nuit et caillebotis, salle des machines enterrée aux deux roues
  d'entraînement jaunes (la roue aval affleure entre les butoirs, sommets
  des deux roues alignés sur la pente de la voie, câble en huit). Galets de
  ligne fidèles qui tournent, supports numérotés, câble en chaînette entre
  les galets, sortie de secours dessinée d'après la vidéo de montée.
- **Gares d'après le réel** : Val Claret dans son état de 2018 (place,
  escalier, salle d'attente, portes coulissantes d'un seul vantail vers
  les quais, fosse sous la voie) ; Grande Motte ouverte sur le glacier
  (quais en escalier, mur de tête vitré, terrasse sur pilotis avec son
  escalier, restaurant, téléphérique, porte de la piste Génépy).
- **Relief réel** : tout le domaine Tignes – Val d'Isère en 3D sur
  21 × 17 km, des Brévières au glacier du Pissaillas en passant par le
  Fornet (IGN RGE ALTI et orthophotographie), avec ses 420 pistes nommées
  (OpenStreetMap). Vue extérieure en
  « rayons X » : le sol devient translucide autour du tunnel. Sur PC, la
  vue de profil est une vraie coupe du terrain.
- **Vue cabine 3D** (F4) : viewer Godot embarqué, rien à installer. Rames
  d'après photos (roues Abt à double boudin, phares halogènes, plaque,
  intérieur avec paliers, bancs et porte-skis, passagers en skieurs),
  **pupitre de conduite** reproduit d'après photos, avec son écran Pro-face
  vivant, et dont les boutons se cliquent (portes, éclairage, klaxon,
  ± VITE, MONTÉE, URGENCE, ÉLECTRIQUE) ; vue extérieure et vue libre de la
  salle des machines (O). La 3D se règle sur la machine (menu Affichage →
  Qualité 3D) : elle coupe d'abord les effets, puis verrouille 30 i/s, et
  ne réduit le rendu qu'en dernier recours, à 85 % au plus bas — les
  textes du pupitre restent lisibles.
- **Skieur jouable** (F9 sur PC, SKIEUR / K dans la version Web) : il
  marche dans les gares, monte les escaliers, prend la rame, va au poste,
  sort en haut sur la terrasse ou par la porte de la piste Génépy. Le
  funiculaire tourne tout seul, l'attend et ferme les portes quand il est à
  bord.
- **Ski** : dehors, il chausse (E) et descend jusqu'à Val Claret sur un
  domaine en hiver : neige, relief ombré, pistes d'OpenStreetMap damées et
  balisées de leur couleur. Glisse physique (pente, carres, neige, air,
  chasse-neige, schuss), vitesse et nom de la piste à l'écran, et le fantôme
  des vraies descentes de Kevin à battre. En bas, on remonte en funiculaire.
  Suivi dans `SKIEUR.md`.
- **Trois modes** : Normal ; Défi (trajet noté sur 100, butoir,
  déraillement, collision) ; Pannes (15 pannes issues d'incidents
  documentés : STRMTG RM5, Glória Lisbonne 2025, Kaprun 2000, Carmelit,
  Perce-Neige 2008…, chacune avec sa procédure de reprise).
  `AUDIT_PHYSIQUE_PANNES.md` détaille le modèle.
- **Exploitation automatique** (X) : journée complète de 08:45 à 16:45,
  embarquement, fermeture, trajet, croisement, stabilisation du câble à
  l'arrivée, demi-tour ; journal SQLite consultable (F5). Maj+X = 24/7.
  La touche A confie un seul voyage au pilote automatique.
- **Sons** : ambiance réelle de la cabine, buzzers, annonces authentiques en
  cinq langues (console F2), klaxon = le vrai buzzer de la rame, sons
  d'accident synthétisés ; en vue salle des machines, le son réel de la gare
  haute, dont la hauteur suit la vitesse du câble ; hors de la rame, sur le
  quai, des bouffées d'air puis le silence, et le vent dehors.
- **Autour** : mise à jour automatique, rapports d'incident anonymes (avec
  votre accord), téléchargement des PDF (F6), interface FR/EN à l'échelle
  de l'écran, plein écran (F11), volume général (F7 / F8).

---

## Commandes (PC)

L'écran d'accueil (F1) reprend ces touches.

**Conduite**

| Touche            | Action                                          |
|-------------------|-------------------------------------------------|
| `↑` / `↓`         | Consigne de vitesse ± (% de 12 m/s)             |
| `Espace` / `B`    | Frein de service (maintenir)                    |
| `Maj`             | Arrêt d'urgence, frein poulie 1,25 m/s² (maintenir) |
| `3`               | Arrêt électrique (verrouillé)                   |
| `4`               | Arrêt d'urgence verrouillé (même frein poulie que `Maj`) |
| `V`               | PRÊT                                            |
| `Z`               | DÉPART forcé (Défi) — en service, PRÊT suffit : le départ suit tout seul |
| Molette (vue 3D)  | LOUPE sur le pupitre et l'écran Pro-face (vue cabine) |
| `I`               | Inverser le sens (à l'arrêt)                    |
| `W`               | Vigilance marche / arrêt                        |
| `G`               | Acquitter la vigilance                          |

**Cabine**

| Touche            | Action                                          |
|-------------------|-------------------------------------------------|
| `D`               | Portes (à l'arrêt)                              |
| `H`               | Phares                                          |
| `C`               | Éclairage cabine                                |
| `K`               | Klaxon (maintenir)                              |
| `A`               | Pilote automatique du voyage                    |
| `X`               | Exploitation automatique                        |
| `Maj+X`           | 24/7, ignorer les horaires                      |
| `N`               | Silence annonces                                |
| `Retour arrière`  | Couper l'annonce en cours                       |
| `F2`              | Console des annonces                            |
| `J`               | Éclairage du tunnel                             |
| `F4`              | Vue cabine : profil → dessinée → 3D             |
| `O`               | Vue 3D : cabine → extérieure → salle des machines (glisser, molette, clic droit) |
| `F9`              | Skieur dans la vue 3D (voir plus bas)           |
| Clic sur le pupitre 3D | Portes, éclairage, klaxon, ± VITE, MONTÉE, URGENCE, ÉLECTRIQUE : comme les touches |

**Système**

| Touche            | Action                                          |
|-------------------|-------------------------------------------------|
| `P` / `Échap`     | Pause                                           |
| `M`               | Mode : normal / défi / pannes                   |
| `F`               | Sélecteur de pannes (mode pannes)               |
| `R` / `Entrée`    | Nouveau voyage / démarrer depuis l'écran-titre  |
| `Début`           | Retour à l'écran-titre                          |
| `F1`              | Aide                                            |
| `F3`              | La vraie machine, liens                         |
| `F5`              | Journal d'exploitation                          |
| `F6`              | Télécharger manuel et guide théorique (PDF)     |
| `F7` / `F8`       | Volume général − / +                            |
| `F11`             | Plein écran / fenêtre                           |
| `+` / `−` / `0`   | Zoom de la vue de profil (ou molette)           |
| `L`               | Langue FR / EN                                  |
| Menu Aide         | Raccourcis (F1), PDF (F6), la vraie machine (F3), skieur (F9), nouveautés, mise à jour, signaler un problème, à propos |
| Menu Affichage    | Qualité 3D, taille de l'interface, plein écran  |

**Skieur** (F9 ou bouton SKIEUR, en vue 3D)

| Touche                       | Action                                   |
|------------------------------|------------------------------------------|
| `Z` `Q` `S` `D` / flèches    | Marcher (W A S D aussi)                  |
| `Maj`                        | Courir                                   |
| `V`                          | 1re / 3e personne                        |
| `E`                          | Chausser / déchausser (dehors, sur la neige) |
| À ski : `Q` / `D`, `Z`, `S`, `Maj` | Tourner, pousser, chasse-neige, schuss |
| Glisser dans la 3D, molette  | Regarder, rapprocher la caméra           |
| CONDUIRE (près du poste)     | S'asseoir au poste : fin du skieur et de l'exploitation automatique |
| AUTO (touche X)              | Le skieur fait la boucle tout seul : gare, rame, Génépy, trace n° 4 à ski, retour |
| EXPLOIT.                     | Exploitation automatique du funiculaire, marche / arrêt, même en skieur (Web : F3 ; PC : aussi le bouton AUTO du tableau de bord) |
| ÉVACUER (touche U)           | Rame arrêtée en tunnel : enlever les issues de secours de la face, descendre sur la voie, l'escalier de service ramène en gare ou à la galerie de secours |
| `F9` ou QUITTER              | Revenir à la conduite (l'exploitation automatique continue) |

Pendant ce temps, la rame est en exploitation automatique, 24 h/24 : elle
attend le skieur resté en gare et ferme les portes dès qu'il est dans la
voiture.

## Commandes (version Web)

Sur tablette, tout passe par les boutons à l'écran : ± VITESSE, FREIN,
URGENCE, PORTES, PRÊT / DÉPART, INVERSER, AUTO, PHARES, CABINE, TUNNEL,
VUE, SKIEUR, ANNONCES, MODE, PANNE. En vue cabine, les boutons du pupitre
3D se touchent du doigt. Le skieur se dirige au joystick (en bas à
gauche) ; un doigt glissé ailleurs tourne la vue ; CHAUSSER met les skis,
puis le joystick tourne (gauche / droite), pousse (haut) ou freine en
chasse-neige (bas), et SCHUSS accélère.

Au clavier : `↑`/`↓` consigne, `Espace` frein, `Maj` urgence, `Entrée`
départ, `D` portes, `I` inverser, `H` phares, `C` cabine, `J` tunnel,
`V` ou `O` vue, `M` mode, `F` choix de panne, `R` nouveau voyage (après
un accident ou une panne grave), `F3` exploitation automatique, `K`
skieur (puis ZQSD, `Maj`, `V`, `E` pour chausser).

---

## Documentation

- `manuel_perce_neige.pdf` : manuel utilisateur, FR/EN, 56 pages.
- `guide_theorique.pdf` : formules, sources réglementaires, calibration audio.
- `AUDIT_PHYSIQUE_VOYAGES.md`, `AUDIT_PHYSIQUE_PANNES.md` : audits du
  modèle physique, scripts SageMath et sorties dans `audit_physique/`.
- `SOURCES.md`, `research_*.md` : sources techniques et historiques.
- `CHANGELOG.md` : journal des versions.

---

## Depuis les sources

```cmd
launch.bat        (Windows)
./launch.sh       (Linux / macOS)
```

Les lanceurs créent un environnement virtuel hors du dossier, installent
PyQt6 et Pillow, puis lancent le jeu. À la main :

```bash
pip install -r requirements.txt
python perce_neige_sim.py
```

- **Viewer 3D** : le binaire `bundled_godot/` (~125 Mo) n'est pas dans le
  dépôt. Au premier F4, l'application propose de le télécharger depuis la
  dernière release (contrôle SHA-256). Sinon : Godot 4.6 installé, ou
  `./build_godot_viewer.sh`. Sans viewer, F4 retombe sur la vue cabine
  dessinée.
- **Tests** : `QT_QPA_PLATFORM=offscreen pytest tests` ; bancs Godot :
  `godot --headless --path godot_project -s bench_<nom>.gd`.
- **Version Web** : `bash deploy_web.sh` (export Web Godot, puis copie sur
  le serveur).
- **Release PC** : un tag `v*` déclenche GitHub Actions
  (`.github/workflows/build.yml`), qui construit l'installeur et le publie.

---

## Licence

MIT. Auteur : ARP273-ROSE, original TI-Basic 2006, portage PyQt6 2026.

Police des textes 3D : Liberation Sans (© Red Hat, Google — SIL Open Font
License 1.1), dans `godot_project/fonts/` avec sa licence.
