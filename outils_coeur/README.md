# Relevé du cœur (réécriture du cœur, étape 1)

Même mesure sur toutes les machines. Le jeu suit la boucle AUTO du skieur (salle des machines, cabine,
terrasse, ski, gare) et chronomètre chaque image. La sonde est `godot_project/sonde_coeur.gd`.

## Mesure de référence : export release, sans vsync

1. Exporter le pack (`--export-pack`) avec `sonde_coeur.gd` dans le projet, comme d'habitude.
2. Écrire à côté de l'exécutable un `override.cfg` :

```
[application]
run/flush_stdout_on_print=true

[autoload]
SondeCoeur="*res://sonde_coeur.gd"

[display]
window/vsync/vsync_mode=0
```

Machine « bridée » : ajouter `[threading]` puis `worker_pool/max_threads=4`. Sous Windows, lancer avec
`start /affinity 55` (4 cœurs physiques sur un processeur à 2 fils par cœur) ; sous Linux, avec
`taskset -c 0,2,4,6`. Une machine bridée garde sa carte graphique et ses fréquences : ce n'est pas la
machine visée.

3. Lancer, avec la sonde de fils à côté :

```
python outils_coeur/sonde_fils.py SORTIE/x_sonde.csv NOM_DU_PROCESSUS &
EXECUTABLE --resolution 3840x2160 -- --mode=normal --sortie=SORTIE --etiq=x --duree=1500
python outils_coeur/analyse_coeur.py SORTIE x
```

`NOM_DU_PROCESSUS` : celui qui dessine (sous Windows, pas l'enveloppe `.console.exe`).

## Sans export

```
godot --path godot_project --resolution 3840x2160 -s bench_coeur_3d.gd -- --mode=normal --sortie=SORTIE --etiq=x --duree=1500
```

Le binaire de l'éditeur ajoute son propre coût : ces chiffres ne se comparent qu'entre eux.

## Colonnes de `x_images.csv`

- `image_ms` : d'une fin de dessin à la suivante.
- `principal_ms` : du début de l'image (physique comprise) au début du dessin, donc scripts et moteur.
- `physique_ms` : physique.
- `dessin_ms` : de `frame_pre_draw` à `frame_post_draw`.
- `rendu_cpu_ms` / `gpu_ms` : temps mesurés par le moteur pour la vue principale.

Le projet ne règle pas `rendering/driver/threads/thread_model`. Si le défaut de Godot 4.6 dessine bien sur
le fil principal (à confirmer avec la sonde de fils), `dessin_ms` compte dans le fil principal.
`x_prof.txt` donne le temps par système, en µs cumulées par phase (enveloppe `Prof`).
