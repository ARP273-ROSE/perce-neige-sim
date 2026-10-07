# Perce-Neige Simulator 3D

Le projet Godot 4.6 du simulateur Perce-Neige. Il sert à deux choses :

- **la version Web** (PWA) : <https://funiculaire.giff.re>, tactile (iPad,
  Android) ou à la souris, installable comme une application, utilisable
  hors ligne ; c'est la 3D qui conduit, avec sa propre physique ;
- **la vue cabine 3D du simulateur PC** (F4) : le même projet, exporté et
  lancé en « mode client ». Le PC calcule la physique et envoie l'état à la
  3D, qui l'affiche ; la 3D renvoie au PC les appuis sur le pupitre et
  l'état du skieur.

Présentation générale, vraie machine et commandes : `../README.md`. Manuel :
`../manuel_perce_neige.pdf`. Journal des versions : `../CHANGELOG.md`.

---

## Ce qu'il y a dedans

- **Physique** portée du PC, même modèle (`train_physics.gd`) : régulateur
  Von Roll, freins, câble élastique, contrepoids ; la parité avec le PC est
  vérifiée par `../tests/parite_pwa.py`.
- **Ligne** : tunnel aux sections réelles, évitement Abt avec ses
  aiguillages, galets et supports numérotés, câble en chaînette, sortie de
  secours ; gare de Val Claret (`gare_aval.gd`) et gare de la Grande Motte
  avec sa terrasse et le téléphérique (`gare_amont.gd`), salle des machines.
- **Relief** du massif d'après l'IGN (`relief_builder.gd`, données
  produites par `../tools_relief3d.py`).
- **Rames** d'après photos, intérieur, passagers en skieurs, **pupitre de
  conduite** et son écran Pro-face (`pupitre_conduite.gd`,
  `ecran_proface.gd`), cliquable.
- **Exploitation** : modes Normal, Défi, Pannes ; annonces ; exploitation
  automatique (`auto_operator.gd`).
- **Skieur jouable** (`skieur_joueur.gd`, collisions dans
  `collisions_jeu.gd`, portes automatiques dans `porte_auto.gd`) : suivi du
  chantier dans `../SKIEUR.md`.
- **Réglage automatique** de la qualité selon la machine
  (`perf_manager.gd`).

## Commandes de la version Web

Boutons à l'écran : ± VITESSE, FREIN, URGENCE, PORTES, PRÊT / DÉPART,
INVERSER, AUTO, PHARES, CABINE, TUNNEL, VUE, SKIEUR, ANNONCES, MODE, PANNE.

Clavier : `↑`/`↓` consigne, `Espace` frein, `Maj` urgence, `Entrée`
départ, `D` portes, `I` inverser, `H` phares, `C` cabine, `J` tunnel,
`V` / `O` vue, `M` mode, `F` choix de panne, `R` nouveau voyage (après un
accident ou une panne grave), `F1` panne au hasard, `F2` effacer la panne,
`F3` exploitation automatique, `K` skieur. En skieur : `ZQSD` (ou flèches),
`Maj` pour courir, `V` 1re / 3e personne.

## Développer

- Ouvrir `project.godot` avec Godot 4.6 (rendu Forward+ sur PC ; la
  version Web passe en Compatibility).
- Mode client, comme dans le PC : `godot --path . -- --client
  [--port=7777]`. L'état arrive en UDP sur ce port (une ligne JSON par
  paquet, voir `state_receiver.gd`) ; les messages vers le PC partent sur
  le port suivant.
- **Bancs** (tous doivent finir sur `OK`) :

  ```
  godot --headless --path . -s bench_<nom>.gd -- --mode=normal
  ```

  `bench_skieur_3d.gd` se lance avec `--fixed-fps 60`. Les 15 bancs :
  aiguillage, auto, defi, galets, pannes, perf, portes, pupitre, relief,
  rupture, salle_machines, skieur, son_salle, train_mesh, voyages.
- **Captures** de contrôle : `shot_*.gd` (vues de la cabine, du pupitre,
  du skieur…).
- **Publier la version Web** : `bash ../deploy_web.sh` (export Web, puis
  copie sur le serveur).

## Licence

MIT. Auteur : ARP273-ROSE.
