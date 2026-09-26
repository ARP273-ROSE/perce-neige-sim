# Audit physique — voyages complets, montée et descente (2026-09-26)

Déclencheur : « si je descends ou monte j'ai des valeurs différentes de
puissance, de tension et de régén » ; « la cabine aval recule au fur et à
mesure de l'embarquement dans la PWA mais pas sur le PC ». Demande : simuler
des voyages sur les deux rames dans les deux sens, comparer puissances,
régénération et tension du câble, et vérifier la cohérence avec le profil de
ligne, la pente, la masse, le remplissage, les frottements et l'air (tube
unique / évitement). Corrections portées sur le **programme PC**
(`perce_neige_sim.py`) **et la PWA** (`godot_project/scripts/train_physics.gd`).

Tout chiffre ci-dessous sort de `audit_physique/audit_voyages.sage`
(SageMath 10.9, sortie brute `audit_physique/resultats.txt`, figures
`audit_physique/fig/`) ou des bancs `tests/bench_voyages.py` (PC),
`godot_project/bench_voyages_3d.gd` (PWA) et `tests/parite_pwa.py`.
Rapport PDF : `audit_physique/audit_voyages.pdf`.

## 1. Bancs

- **Voyages complets** : 5 chargements (rame pilotée / contrepoids : vide/vide,
  pleine/vide, vide/pleine, pleine/pleine, demi/demi) × 2 sens, consigne
  pleine, jusqu'à l'arrivée. Séries CSV à 0,5 s : position des deux rames,
  pente locale de chacune, altitude, masses, vitesse, accélération,
  throttle, régén, frein, puissance, régén, tension.
- **Test miroir** : monter la rame PLEINE avec un contrepoids VIDE est la même
  situation physique que descendre la rame VIDE avec un contrepoids PLEIN
  (même câble, mêmes deux rames). À position égale de la rame pleine,
  puissance, régén et tension doivent coïncider.
- **Recalcul indépendant** (Sage) : bilan des forces refait à la main à partir
  du profil, des masses et des constantes, confronté aux séries du banc.
- **Parité PC ↔ PWA** : mêmes cas dans Godot headless, séries interpolées à
  position égale.

## 2. Ce qui était juste

| Contrôle | Résultat |
|---|---|
| Profil : dénivelé intégré | 921,00 m (facteur d'échelle 1,035 sur le gradient interpolé), pente moyenne 26,5 % |
| Miroir PC (montée pleine/vide vs descente vide/pleine) | écart max **0,00 kW / 0,00 daN / 0,00 kW** — symétrie exacte |
| Miroir PWA | idem (banc Godot) |
| Cohérence interne : puissance affichée vs F·v recalculé à 12 m/s | ≤ 34 kW (transitoires du régulateur), tension recalculée à l'identique |
| Durée d'un trajet | 397–401 s (6 min 40) — commercial « 6–7 min » ✓ ; le « 4 min 51 » technique n'est atteignable qu'à 12 m/s sans creep d'entrée en gare |
| Tension pleine/vide | pic 23 850 daN à s ≈ 900 (zone 30 % avec 2,3 km de câble au-dessus) — nominal constructeur 22 500, coefficient de sécurité 8,0 |
| Régén pleine/vide en descente | 866 kW = 0,80 × la puissance miroir (1 100 kW) − les frottements comptés deux fois |
| Régulateur, freins, arrêts | inchangés depuis l'audit des pannes de juillet (banc `bench_pannes.py` rejoué) |

**La réponse à « des valeurs différentes en montée et en descente »** : dans
les deux codes, à situation physique égale, les valeurs sont identiques. Ce
qui diffère, c'est *monter la rame pleine* (traction ~1,1 MW) et *descendre
la rame pleine* (régénération ~0,9 MW) : ce sont deux situations différentes
— dans la seconde, c'est le contrepoids vide qui monte. Après correction, la
descente pleine commence même en **traction** (voir § 3.1).

## 3. Ce qui manquait

### 3.1 Le poids propre du câble ne pesait pas sur le moteur — 🔴 majeur

Le câble tracteur (Fatzer 52 mm, 11 kg/m, **38 t sur la ligne**) passe sur
la poulie motrice en gare haute. Le brin de la rame pilotée pèse
ρ·g·(z_poulie − z_rame) le long de la pente, celui du contrepoids
ρ·g·(z_poulie − z_contrepoids). À la poulie, le moteur voit la **différence
des deux brins** :

    F_câble = ρ·g·(z_rame − z_contrepoids)   →  −98,9 kN au départ bas,
                                                 0 à mi-ligne, +98,9 kN en haut

soit **10,1 tonnes-force**, PLUS que le déséquilibre pleine/vide des deux
rames (69,5 kN sur la zone à 29,5 %). Le simulateur l'avait dans la **jauge
de tension** (terme ρ·g·Δh de chaque brin) mais pas dans le **bilan des
forces** — la jauge et la dynamique se contredisaient : à s = 26 m
pleine/vide, la différence des brins vaut 124 kN, le moteur n'en fournissait
que 26.

Preuves qu'il n'y a pas de câble de queue qui l'équilibrerait :
- aucune source (FUNI-334, Wikipédia FR/EN, CFD, haute-tarentaise) n'en
  mentionne ; les « 512 galets (256 paires) » sont les deux brins d'un seul
  câble ;
- sans le poids du câble, la tension maximale pleine/vide serait 16 054 daN :
  le **nominal constructeur de 22 500 daN** ne serait jamais atteint ; avec,
  le pic vaut 23 850 daN — cohérent ;
- sans lui, la force résistante maximale à 12 m/s est 107 kN, soit 54 % de
  ce que 2 400 kW peuvent fournir (200 kN) : le drive serait 2,8×
  surdimensionné. Avec (et la traînée, § 3.2) : 185 kN, 92 %. Les
  **3 × 800 kW installés ne s'expliquent qu'avec le poids du câble.**

Conséquences visibles au pupitre après correction (banc PC) :

| Trajet (rame pilotée/contrepoids) | P max avant | P max après | Régén max avant | après | E traction avant | après |
|---|---|---|---|---|---|---|
| montée vide/vide | 286 kW | **1 527 kW** | 248 kW | 507 kW | 3,9 kWh | 47,7 kWh |
| montée pleine/vide | 1 100 kW | **2 238 kW** | 0 | 148 kW | 62,5 kWh | 106,3 kWh |
| descente pleine/vide | 23 kW | **825 kW** | 866 kW | 1 000 kW | 0,1 kWh | 13,7 kWh |
| montée pleine/pleine | 507 kW | 1 366 kW | 441 kW | 441 kW | 6,9 kWh | 46,4 kWh |

- Un **départ vide/vide en bas demande 1,5 MW** : il faut hisser 3,4 km de
  câble ; l'arrivée en haut se fait en régénération (le contrepoids vide, en
  bas, porte alors le câble).
- Une **descente chargée commence en traction** (825 kW) : le contrepoids
  vide est en bas avec tout le câble, c'est lui qu'il faut hisser ; la
  régénération n'arrive qu'après mi-ligne.
- Le pic pleine/vide (2 238 kW électriques) tient dans les 2 400 kW.
- Le câble (38 t) entre aussi dans la masse en mouvement (129 t au lieu de
  91 pour deux rames chargées à moitié) et dans le feed-forward du
  régulateur.

### 3.2 Traînée d'air en tunnel — 🔴 majeur, incertain en amplitude

Le simulateur n'avait **aucune** traînée (« négligeable en dessous de
12 m/s » — vrai à l'air libre, faux dans un tube). Faits :
- cabines cylindriques Ø 3,60 m dans un tube Ø 3,90 m (min) ; section
  d'air libre ≈ 11,05 m² (radier compris) ;
- forum haute-tarentaise : « *Les portes permettent d'éviter les courants
  d'air dus aux différences de pression entre le haut et le bas* », portes
  de gare « *hermétiques* », fonctionnant « *comme un sas* », et « *on sent
  un souffle de face lorsque l'on marche sur le quai* » ;
- avant le croisement, la colonne d'air **entre les deux rames** est
  comprimée par les deux ; elle ne peut s'échapper que par les espaces
  annulaires (les portes-sas ferment les extrémités). Après le croisement,
  la colonne entre elles s'étire : même débit, même traînée, en aspiration.

Modèle 1D quasi-stationnaire (Vardy 1996, Sockel) : débit annulaire
v·A_T (repère tunnel), vitesse relative dans l'annulaire v·(2−β)/(1−β),
pertes = contraction au nez (0,4) + frottement λ·L/D_h (λ = 0,025, L = 32 m)
+ élargissement de Borda-Carnot (β²) ; F = ΔP·A_rame + ½ frottement de peau.
Dans l'**évitement**, le second tube (203 m, section A_T) court-circuite
l'annulaire : partage du débit à perte de charge égale.

| β = A_rame/A_air | traînée tube unique, par rame, 12 m/s | puissance | dans l'évitement |
|---|---|---|---|
| 0,55 | 8,0 kN | 96 kW | 0,9 kN |
| 0,60 | 11,1 kN | 133 kW | 1,1 kN |
| **0,65** | **16,1 kN** | **193 kW** | **1,2 kN** |
| 0,70 | 24,4 kN | 292 kW | 1,4 kN |
| 0,75 | 39,6 kN | 475 kW | 1,6 kN |
| 0,85 | 153 kN | 1 841 kW | 2,5 kN |

La sensibilité à β est violente (×20 entre 0,55 et 0,85). Le β géométrique
brut (disque Ø 3,60 dans 11,05 m²) vaut 0,92 — impossible : le pic
pleine/vide dépasserait 5 MW. La partie basse de la cabine n'est pas un
disque plein (châssis, bogies, jupes), et le tube foré est probablement plus
large que le minimum de 3,90 m. **β = 0,65 est la valeur la plus haute
compatible avec les 2 400 kW installés** (pic pleine/vide 2 238 kW ;
β = 0,70 donnerait ≈ 2 460 kW). Elle est à recaler sur mesure — voir § 6.

Effet retenu : **32 kN pour les deux rames en tube unique** (385 kW à
12 m/s), **2,5 kN quand une rame est dans l'évitement**. La puissance
creuse donc à la traversée de l'évitement : pleine/pleine, 697 kW → 165 kW →
399 kW. Chaque rame est dans son tube pendant 203 m ≈ 17 s ; par symétrie
la rame pilotée y entre 50 m avant le contrepoids.

Prédiction vérifiable sur place : à β = 0,65 la surpression devant la rame
vaut ≈ 1,9 kPa (19 hPa) et **tombe en ~3 s à l'entrée de l'évitement** — ça
doit se sentir aux oreilles, indépendamment des 100 hPa de l'altitude gagnés
en 7 min.

### 3.3 Résistance du câble sur ses galets — mineur

38 t de câble sur 512 galets : ≈ 1,5 % de la charge normale (ordre de
grandeur usuel des galets à roulement — estimation, pas de source
constructeur) → **5,4 kN constants**, 2,6× le roulement des deux rames
(2,1 kN à μ = 0,0025).

### 3.4 Rendement électrique — mineur

La puissance affichée en traction était la puissance **mécanique** à la
jante ; la régénération, elle, avait déjà son rendement (0,80). Traction :
P_élec = F·v / 0,90 (moteur DC ≈ 0,94 × réducteur ≈ 0,97 × convertisseur
≈ 0,98 — estimation d'ingénieur).

### 3.5 Tension : frottement et traînée signés — mineur

Le frottement de roulement était toujours ajouté à la tension du brin,
quel que soit le sens. Il charge le brin d'une rame qui monte VERS la
poulie et décharge celui d'une rame qui s'en éloigne (et n'existe pas à
l'arrêt). Idem pour la traînée et la moitié des galets. Pic pleine/vide :
25 781 daN (coefficient de sécurité 7,4).

### 3.6 Affaissement d'embarquement — port PWA → PC

À quai, tambour serré en gare haute, la rame pend à son brin : chaque
passager l'allonge de Δm·g·sinθ·L/(EA). En gare **basse** (L = 3 448 m,
pente 8,9 %, k = EA/L = 36 kN/m) : **1,79 mm par passager, 59,8 cm pour
334**, période propre 7,9 s. En gare **haute** (L = 26 m) : 0,012 mm par
passager, 4 mm pour 334 — invisible. La PWA l'avait (visuel) ; le PC
l'a désormais **physiquement** : la rame recule à ≤ 3 cm/s pendant
l'embarquement, l'allongement persiste jusqu'au départ, le contrepoids ne
bouge pas, le repère d'arrêt lui laisse la place.

### 3.7 Hold Abt — bug latent

`if d_hold > 0` : dès que la rame, en rampant, dépassait le point d'arrêt
avant l'aiguillage d'un millimètre, la cible disparaissait et elle
repartait au plafond de panne. Le banc 3D (`bench_pannes_3d.gd`) l'a
révélé quand la nouvelle dynamique a déplacé l'arrêt de quelques cm.
Corrigé dans les deux codes : en amont de l'aiguillage, la cible reste le
point de hold.

### 3.8 Divers

- `inrush` (×4,5 pendant 1,2 s au démarrage) est du **code mort** : la
  force est plafonnée par F_STALL = 260 kN en dessous de 9,2 m/s, et le
  boost ne s'applique qu'à la limite de puissance. Laissé tel quel.
- « ~42 kWh par descente chargée (datasheet CFD) » : **sans source**. La
  fiche CFD ne contient aucun chiffre d'énergie ; `SOURCES.md` § 7 le
  classe déjà en « extrapolé », avec une formule fausse (921 m × 58,8 t ×
  0,85 donne 125 kWh, pas 42, et c'est la différence de masse qui compte).
  Le modèle donne 31 kWh régénérés + 14 kWh consommés pour une descente
  pleine/vide.
- `research_physics_sources.md` § 2 : « le terme aérodynamique est
  négligé » — à lire avec le § 3.2 ci-dessus.

## 4. Bilan des forces retenu (rame pilotée en s, contrepoids en L − s)

    F = F_moteur − F_génératrice
        − g·(m_A·sinθ_A − m_B·sinθ_B)          déséquilibre des rames, pentes locales
        + ρ·g·(z_A − z_B)                     poids propre du câble
        − sgn(v)·[μ·g·(m_A·cosθ_A + m_B·cosθ_B) + F_galets]
        − sgn(v)·[F_aéro(s_A, v) + F_aéro(s_B, v)]   chacune dans son régime
        − F_freins
    (m_A + m_B + ρ·L)·a = F

Figure `audit_physique/fig/puissance_forces.png` : composantes le long de
la montée pleine/vide et puissance résultante pour trois chargements ;
`avant_apres.png` : séries du banc avant/après.

## 5. Vérifications après correction

- 21 tests `pytest` (16 anciens + miroir, poids du câble, enveloppe
  installée, creux de l'évitement, affaissement) ; bancs Godot
  `bench_pannes_3d.gd` et `bench_defi_3d.gd` verts.
- Parité PC ↔ PWA (`tests/parite_pwa.py`, 5 trajets, 450–480 points par
  trajet à 12 m/s) : écarts p95 **≤ 0,4 kW** et **≤ 2 daN** ; durées à
  ±1,5 s (repères d'arrêt différents : 26/3 448 m sur PC, 20/3 457 m sur
  PWA).
- `bench_pannes.py` rejoué : arrêt électrique 0,39/0,32 m/s² inchangé ;
  urgence commandée 2,10 m/s² (1,85 avant : la traînée et le câble
  s'ajoutent au frein poulie) ; parachute 4,34 (4,09). Les deux alertes
  restantes du banc (« switch_abt ne s'arrête pas » en 90 s — il rampe à
  2 m/s puis 0,75 sur 400 m, la fenêtre est trop courte ; à-coups au coup de
  frein) **préexistaient** (banc rejoué sur le code d'origine).

## 6. Ce qu'il reste incertain — à mesurer sur place

1. **β (traînée)** : une lecture de la puissance au pupitre en croisière
   à 12 m/s, rames vides, à mi-ligne (câble équilibré, pentes égales) donne
   directement la traînée : P ≈ (32 kN·β/0,65 + 7,5 kN) × 12 / 0,90. À
   β = 0,65 : ≈ 530 kW ; si le pupitre dit 300, β ≈ 0,5 ; s'il dit 900,
   β ≈ 0,75. Et le **creux à l'évitement** est la signature la plus nette.
2. **Rendements** (0,90 / 0,80) et **galets** (1,5 %) : estimations.
3. **Câble de queue** : si l'exploitant en confirme un, le terme § 3.1
   disparaît (et les 2 400 kW redeviennent inexplicables).

## 7. Fichiers

- `perce_neige_sim.py` : constantes `CABLE_ROLLER_C`, `DRIVE_EFF`,
  `REGEN_EFF`, `AERO_*` ; fonctions `air_density_at`, `_aero_coefficients`,
  `aero_drag_side_n`, `aero_drag_n`, `rope_weight_force_n`,
  `ROPE_ROLLERS_N`, `ROPE_MASS_KG` ; `Physics.step` (forces, affaissement,
  tension signée, puissance), `_regulator` (masse, gravité, feed-forward,
  hold Abt) ; `GameState.sag_*`.
- `godot_project/scripts/constants.gd`, `train_physics.gd` : même port.
- `tests/test_physics.py` (+5), `tests/bench_voyages.py`,
  `tests/parite_pwa.py`, `godot_project/bench_voyages_3d.gd`.
- `audit_physique/` : `audit_voyages.sage`, `resultats.txt`, `fig/`,
  `audit_voyages.tex` + `.pdf`.
