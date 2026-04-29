# Perce-Neige Simulator 3D

**Port 3D du simulateur Perce-Neige vers Godot 4.** Rendu moderne avec éclairage global temps réel (SDFGI), brouillard volumétrique, shaders PBR. Conserve la physique exacte du funiculaire réel de Tignes (3 474 m, Von Roll / CFD 1993) portée depuis le projet Python PyQt6.

![Version](https://img.shields.io/badge/version-0.1.0-orange.svg)
![Godot](https://img.shields.io/badge/Godot-4.6+-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey.svg)

---

## État actuel — MVP Phase 1 + 2 + 3

- ✅ Projet Godot 4.6.2 structuré et compilable
- ✅ Physique Von Roll complète portée en GDScript (régulateur, freins, tension câble, contrepoids)
- ✅ Tunnel procédural 3D — spline suivant le vrai profil de pente (8 % → 30 % → 6 %) et les courbes horizontales réelles
- ✅ Cabine MVP (cylindres jaunes 2 voitures couplées) suivant la spline
- ✅ Éclairage tunnel — néons muraux tous les 12 m, zones sombres respectées
- ✅ Brouillard volumétrique + SDFGI (éclairage global temps réel)
- ✅ Phares cabine + feux arrière + éclairage intérieur
- ✅ HUD cockpit bilingue FR/EN (vitesse, consigne, tension, puissance, distance)
- ✅ Audio cabine — ambient cruise + slow avec crossfade basé sur la vitesse

## À faire dans les prochaines phases

- ⏳ Extrémités horseshoe (tunnel carré) aux stations
- ⏳ Modélisation Blender de la cabine Von Roll détaillée (avec cockpit intérieur)
- ⏳ Rails + traverses + sabots guide-câble
- ⏳ Sections squares/cut-and-cover aux extrémités (Val Claret / Grande Motte portails)
- ⏳ Boucle de croisement double-bore
- ⏳ Station upper avec salle des machines Panoramic
- ⏳ Skybox extérieure (glacier Grande Motte, vallée Val Claret)
- ⏳ Système de pannes porté depuis Python (15 types)
- ⏳ Annonces multilingues (FR/EN/IT/DE/ES) depuis le projet Python
- ⏳ Auto-exploitation mode
- ⏳ Build standalone Windows/Linux/macOS
- ⏳ Auto-update GitHub

---

## Lancement

### 1. Ouvrir le projet

Godot 4.6.2 est installé dans `C:\Users\kevin\Documents\Godot\`. Pour lancer :

1. **Double-cliquer** sur `C:\Users\kevin\Documents\Godot\Godot_v4.6.2-stable_win64.exe`
2. Dans le **Project Manager** : cliquer **Import**
3. Naviguer vers `C:\Users\kevin\Documents\GitHub\perce-neige-sim-3d\` et sélectionner `project.godot`
4. Cliquer **Import & Edit**

Godot ouvre l'éditeur avec le projet chargé.

### 2. Lancer le jeu

- Presser **F5** (ou cliquer le bouton ▶ en haut à droite)
- Première fois : Godot demande la scène principale — elle est déjà configurée (`scenes/main.tscn`)

Le tunnel met ~2-3 secondes à se générer (1158 rings × 20 segments = ~46k triangles).

### 3. Conduite

| Touche | Action |
|--------|--------|
| **↑** / **W** | Augmenter la consigne de vitesse |
| **↓** / **S** | Diminuer la consigne de vitesse |
| **Entrée** | Prêt / Départ (démarre le voyage) |
| **Espace** / **B** | Frein service |
| **Shift** | Frein d'urgence |
| **H** | Allumer / éteindre les phares |
| **P** | Pause |
| **V** | Changer de vue (à implémenter) |

Au démarrage, le train est à Val Claret (s=26 m), portes ouvertes, prêt. Appuyer sur **Entrée** pour démarrer le trip, puis **↑** pour augmenter la consigne de vitesse. Le régulateur Von Roll prend en charge l'accélération et le freinage automatique en approche de Grande Motte.

---

## Architecture

```
perce-neige-sim-3d/
├── project.godot          # Config Godot
├── icon.svg               # Icône projet
├── scenes/
│   └── main.tscn         # Scène principale (minimal wrapper)
└── scripts/
    ├── constants.gd      # PNConstants — specs funiculaire
    ├── slope_profile.gd  # Profil gradient + courbes + sections
    ├── train_physics.gd  # Physique Von Roll portée du Python
    ├── tunnel_builder.gd # Génération mesh procédural du tunnel
    ├── tunnel_lights.gd  # Néons muraux
    ├── cabin.gd          # Cabine + phares + caméra FPV
    ├── hud.gd            # HUD cockpit bilingue
    ├── audio.gd          # Ambient loops avec crossfade
    └── main.gd           # Orchestrateur
```

La physique tourne à **60 Hz fixe** (pas de couplage framerate). Le rendu tourne au framerate de l'écran. Jusqu'à 4 steps de rattrapage par frame en cas de hiccup.

---

## Tests effectués

- ✅ Compilation GDScript sans erreur sur Godot 4.6.2 stable Windows
- ✅ Génération du tunnel réussit (spline de 3474 m, ~1160 rings)
- ✅ Scène principale construite sans exception (`[PerceNeige3D] Ready.` en stdout)
- ⏳ **Test visuel à faire par l'utilisateur** : ouvrir Godot, F5, vérifier le rendu

---

## Pourquoi Godot 4 et pas UE5 ?

- **Conserve 100 % de la logique du projet Python** (GDScript proche de Python)
- Pas de royalties, pas de licence commerciale
- Build exécutable ~50 Mo (vs ~500 Mo UE5)
- Hot-reload instantané, itération rapide
- SDFGI + brouillard volumétrique = rendu tunnel très convaincant sans les tracasseries Lumen/Nanite

---

## License

MIT. Auteur : ARP273-ROSE, 2026. Port 3D du Perce-Neige Simulator Python/PyQt6 (v1.9.1).
