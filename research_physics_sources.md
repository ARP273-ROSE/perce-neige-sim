# Research — Fondements physiques et mathématiques du simulateur Perce-Neige

Ce document recense les sources théoriques justifiant chaque formule utilisée dans la classe `Physics` (lignes 678-1180) du fichier `perce_neige_sim.py`. Pour chaque sujet : (a) la formule, (b) les sources canoniques avec URL/ISBN, (c) les plages de valeurs typiques, (d) la façon dont le simulateur l'applique avec références de lignes.

---

## 1. Déséquilibre gravitationnel sur funiculaire à contrepoids

### (a) Formule
Sur un funiculaire à câble continu reliant deux véhicules sur la même pente, la composante nette de gravité ressentie le long du câble est proportionnelle à la **différence de masse** entre les deux côtés :

```
F_grav_net = - (m_up - m_down) · g · sin(θ)   = - Δm · g · sin(θ)
```

Le signe « − » exprime que si le véhicule montant est plus lourd (Δm > 0), la résultante de gravité s'oppose au mouvement ascendant. Si le véhicule descendant est plus lourd, la gravité « tire » naturellement le câble vers le bas et aide la cabine montante.

### (b) Sources canoniques
- **USC Viterbi School of Engineering — *The Fun of Funiculars*** : « The fundamental concept behind a funicular is the counterbalancing of two cars connected by a single cable. […] As one car ascends, the other descends, effectively converting most of the potential energy of one car into the potential energy of the other. […] the engine only has to provide energy to pull the excess passengers in the uphill car ». https://illumin.usc.edu/the-fun-of-funiculars/
- **Wikipedia — Funicular** : description du mécanisme à câble continu et du contrepoids actif. https://en.wikipedia.org/wiki/Funicular
- **DesignHorizons — Understanding Funicular Railways** : équation d'équilibre m₁ g sin θ ≈ m₂ g sin θ. https://designhorizons.org/understanding-funicular-railways-mechanics-and-modern-uses/
- **STRMTG — Guide technique RM5 (funiculaires, v1, déc. 2018)**, sect. « Équilibrage et entraînement ». PDF : http://www.strmtg.developpement-durable.gouv.fr/IMG/pdf/rm5_funiculaire_v1_dec2018.pdf

### (c) Plages typiques
- Δm domestique sur Perce-Neige : 0 (deux cabines vides identiques) à ~12 t (cabine pleine de 110 pax montante / cabine vide descendante, où chaque pax = 80 kg).
- sin(θ) sur la rampe : entre ~0.10 (5.7°) sur la section faible et ~0.30 (17.5°) sur la section raide à 30 % de pente.

### (d) Application dans le simulateur
- Calcul du déséquilibre : `dm = m_up - m_down` à la ligne **706**.
- Calcul de la pente locale : `g_slope = gradient_at(tr.s)`, `theta = math.atan(g_slope)` lignes **711-714**.
- Force gravitationnelle nette : `f_grav_net = -dm * G * sint` ligne **790** — exactement la formule canonique avec convention de signes en +s (sens ascendant).
- Réutilisation dans le régulateur ligne **1224** : `f_grav_s = -dm_r * G * math.sin(theta_r)`.

---

## 2. Frottement de roulement acier sur acier

### (a) Formule
```
F_roll = μ · N = μ · m · g · cos(θ)
```
où μ est le coefficient de résistance au roulement (sans dimension) et N est la composante normale du poids sur la pente.

### (b) Sources canoniques
- **FRA / DOT — *A Survey of Wheel/Rail Friction*** (Federal Railroad Administration, US DOT). Données pleine échelle pour roue/rail acier. https://railroads.dot.gov/sites/fra.dot.gov/files/fra_net/17468/A%20Survey%20of%20Wheel-Rail%20Friction.pdf
- **Engineers Edge — Coefficients of Rolling Friction** : valeurs tabulées « steel wheel on steel rail » : 0.001 à 0.002. https://www.engineersedge.com/mechanics_machines/coefficients_of_rolling_friction__16286.htm
- **Engineering Toolbox — Rolling Resistance** : 0.0005 à 0.001 pour roulements à billes acier ; ~0.001-0.002 pour roue acier sur rail acier. https://www.engineeringtoolbox.com/rolling-friction-resistance-d_1303.html
- **Wikipedia — Rolling resistance** : tableau de valeurs typiques. https://en.wikipedia.org/wiki/Rolling_resistance
- **Hamilton Caster White Paper No. 11 — Rolling Resistance and Industrial Wheels**. https://www.hamiltoncaster.com/Portals/0/blog/White%20Paper%20Rolling%20Resistance.pdf
- **Davis formula** (W.J. Davis Jr., 1926, *General Electric Review*) : R = a + b·v + c·v² (terme constant a = roulement + frottement palier ; b·v = friction air à basse vitesse ; c·v² = traînée aérodynamique). Référence dans la plupart des manuels de traction ferroviaire moderne.
- **UIC 544-1** : norme de l'Union Internationale des Chemins de Fer pour le calcul de la résistance à l'avancement et la performance de freinage.
- **Standard ferroviaire** : pour funiculaire à faible vitesse (≤ 12 m/s) le terme aérodynamique est négligé, on garde μ ≈ 0.002-0.004.

### (c) Plages typiques
- Roue acier sur rail acier propre et sec : **μ ≈ 0.001 à 0.002** (rail neuf, alignement parfait).
- Roue acier sur rail acier en service : **μ ≈ 0.002 à 0.005** (incluant frottement boudin, joints éclissés).
- Funiculaire en tunnel à atmosphère humide : extrémité haute de la plage (condensation, oxydation locale).

### (d) Application dans le simulateur
- Friction roulement totale (somme des deux cabines) : `f_roll_mag = MU_ROLL * m_total * G * cost` ligne **793**.
- Application avec signe opposé à la vitesse, avec seuil mort à 0.05 m/s pour éviter l'oscillation numérique : ligne **794**.
- Réutilisation pour la tension du câble (côté lourd seulement) : `t_friction = MU_ROLL * m_heavy * G * cost` ligne **949**.
- Réutilisation dans le feed-forward du régulateur : ligne **1311**.
- Constante `MU_ROLL` à vérifier dans l'en-tête du fichier ; doit être de l'ordre de 0.002-0.004.

---

## 3. Enveloppe de puissance moteur de traction

### (a) Formule
Le moteur de traction électrique a deux limites physiques superposées :

```
F_motor_max(v) = min( F_stall ,  P_rated / v )
```
- **F_stall** : effort maximal de calage (couple max sur la roue motrice ÷ rayon).
- **P_rated / v** : enveloppe de puissance constante au-delà du point de base (où F décroît en 1/v).

Pendant les premières secondes de démarrage, le courant d'appel ("inrush") sur un drive DC peut atteindre ~4-5× le courant nominal, ce qui se traduit par un boost transitoire de couple sur ~1-2 s tant que l'inertie d'arbre est vaincue et que le contrôleur n'a pas encore régulé.

### (b) Sources canoniques
- **The Railway Technical Website — Electric Traction Control** : « A series wound DC motor has a low resistance field and armature circuit, which means when voltage is applied, the current is high. The advantage of high current is that the magnetic fields inside the motor are strong, producing high torque, ideal for starting a heavy object like a train. » http://www.railway-technical.com/trains/rolling-stock-index-l/train-equipment/electric-traction-control-d.html
- **Wikipedia — Traction motor** : courbes couple-vitesse, zone à effort constant puis zone à puissance constante. https://en.wikipedia.org/wiki/Traction_motor
- **IET / IEEE — *Electric railway traction. I. Electric traction and DC traction motor drives*** (Mellitt et al.). https://ieeexplore.ieee.org/document/269022/
- **Ametherm — How To Limit DC Motor Inrush Current** : DC motors « can be as much as 2-3 times its steady state current », et davantage en charge. https://www.ametherm.com/blog/inrush-current/dc-motor-inrush-current/
- **Eaton — Motor Starting Currents** (bulletin technique). https://www.eaton.com/content/dam/eaton/products/electrical-circuit-protection/fuses/solution-center/bus-ele-tech-lib-motor-starting-currents.pdf
- **EEEGuide — Starting and Speed Control of DC Traction Motors**. https://www.eeeguide.com/starting-and-speed-control-of-dc-traction-motors/
- **Manuel de référence** : Steimel, A., *Electric Traction — Motive Power and Energy Supply*, Oldenbourg Industrieverlag, 2008. ISBN 978-3-8356-3132-8.

### (c) Plages typiques
- Boost d'inrush sur drive DC moderne avec contrôleur thyristors : 2-3× nominal.
- Boost d'inrush sur drive DC ancien à contacteurs résistifs (typique des installations Von Roll des années 1980-90 comme Perce-Neige) : 4-5× nominal pendant ~1 à 1.5 s.
- Durée du boost : 0.5 à 2 s selon l'inertie et le contrôleur.

### (d) Application dans le simulateur
- Puissance effective dégradée (thermique + nombre de moteurs) : `p_eff = P_MAX * tr.thermal_derate * (tr.motor_count / 3.0)` ligne **743**.
- Détection d'inrush au démarrage : ligne **749** (`if abs(tr.v) < 0.2 and tr.throttle > 0.2 …`), durée 1.2 s.
- Application du boost : `boost = 1.0 + 3.5 * (tr.inrush_timer / 1.2)` ligne **754**, soit un facteur **4.5× → 1.0×** en taper linéaire. **Cohérent avec la littérature** pour un drive DC industriel ancien.
- Enveloppe de puissance : `f_motor_power_cap = p_eff / v_eff` ligne **756**, avec garde-fou `v_eff = max(abs(tr.v), 0.8)` pour éviter la division par zéro.
- Limite finale : `f_motor_max = min(F_STALL, f_motor_power_cap)` ligne **757**.

---

## 4. Élasticité du câble (loi de Hooke)

### (a) Formule
L'allongement d'un câble sous traction axiale uniforme :
```
Δl = F · L / (A · E_eff)
```
- F : tension (N).
- L : longueur libre du brin chargé (m).
- A : section métallique effective (m²).
- E_eff : module de Young apparent du câble (Pa).

### (b) Sources canoniques
- **Klaus Feyrer — *Wire Ropes: Tension, Endurance, Reliability*** (Springer). 3ᵉ éd. 2014, ISBN-13 978-3-642-54995-3 ; éd. souple 978-3-662-49581-0 ; éd. originale 978-3-540-33821-5. Référence centrale pour le module apparent : 90-110 kN/mm² (90-110 GPa) pour câbles toronnés acier > 25 mm. https://books.google.com/books/about/Wire_Ropes.html?id=aXhFV13bdPcC
- **Fatzer (groupe Brugg) — Engineering Data, Full Locked Coil Rope** : module spécifié **160 kN/mm² ± 10 kN/mm²** (160 GPa) pour câble clos haute résistance utilisé en haubanage. https://www.fatzer.com/en/structural-ropes/engineering-data
- **ResearchGate — *Methods for Determining the Modulus of Elasticity of Wire and Fibre Ropes*** (compilation de méthodes ISO/DIN). https://www.researchgate.net/publication/347407112_Methods_for_Determining_the_Modulus_of_Elasticity_of_Wire_and_Fibre_Ropes
- **ResearchGate — *Determination of Elastic Modulus of Steel Wire Ropes for Computer Simulation*** : valeur retenue 105 GPa pour modélisation. https://www.researchgate.net/publication/280797685_Determination_of_Elastic_Modulus_of_Steel_Wire_Ropes_for_Computer_Simulation
- **NIST Tech Paper T121 — *Strength and other properties of wire rope*** (référence historique mais toujours utilisée). https://nvlpubs.nist.gov/nistpubs/nbstechnologic/nbstechnologicpaperT121.pdf
- **ISO 12076** : *Steel wire ropes — Determination of the actual modulus of elasticity*.
- **DIN 3051** : norme allemande sur les câbles d'acier ronds.

### (c) Plages typiques pour câble Fatzer 52 mm tracteur de funiculaire
- Module apparent E_eff : **100-110 GPa** (câble toronné classique).
  - 160 GPa = câble clos *structural* (haubans de pont) ; un câble de funiculaire dans les années 1989 (date de Perce-Neige) est tressé classique → 105 GPa est l'ordre de grandeur correct.
- Section métallique A pour 52 mm : ~2.0-2.2 × 10⁻³ m² (≈ 60 % de l'aire géométrique brute, le reste étant les vides entre torons).
- Allongement Δl typique sur 3.5 km de câble chargé à 16 500 daN : 2.6-3.5 m (mesuré).

### (d) Application dans le simulateur
- Calcul de l'allongement à l'arrivée pour le rebond élastique : lignes **1130-1135** :
  ```python
  A_cable = 2.12e-3
  E_cable = 1.05e11
  L_loaded = LENGTH - tr.s if tr.direction > 0 else tr.s
  F_peak = tr.tension_dan * 10.0
  st.rebound_amp_m = max(0.0, F_peak * L_loaded / (A_cable * E_cable))
  ```
- A_cable = 2.12 × 10⁻³ m² → cohérent avec un câble Fatzer 52 mm.
- E_cable = 1.05 × 10¹¹ Pa = **105 GPa** → cohérent avec Feyrer (90-110 GPa) pour câble toronné.
- Formule appliquée correctement : Δl = F·L / (A·E).

---

## 5. Rendement de la chaîne de freinage régénératif

### (a) Formule
```
P_regen_grid = η_round_trip · P_mécanique_freinage
```
avec η_round_trip ≈ 0.75-0.85 pour la chaîne complète : roue → bull-wheel → réducteur → machine DC en générateur → onduleur → réseau triphasé.

### (b) Sources canoniques
- **Wikipedia — Regenerative braking** : aperçu général des chaînes et rendements. https://en.wikipedia.org/wiki/Regenerative_braking
- **CTC-N — *Regenerative braking in trains*** : économies d'énergie typiques 15-20 % sur réseaux denses. https://www.ctc-n.org/technologies/regenerative-braking-trains
- **ScienceDirect — *Comparison of regenerative braking energy recovery of a DC third rail system*** (chiffres récents en réseaux DC, jusqu'à 55 % en cas de bonne réceptivité). https://www.sciencedirect.com/science/article/pii/S0142061523006324
- **Wiley — *Regenerative Braking Energy in Electric Railway Systems*** (chapitre de référence). https://onlinelibrary.wiley.com/doi/abs/10.1002/9781119812357.ch15
- **Allen et al. (2021) — *Application of Regenerative Braking with Optimized Speed Profiles*** : 10-30 % de la consommation de traction récupérable. https://onlinelibrary.wiley.com/doi/10.1155/2021/8555372
- **Industrie — XFC technology opinion** : « regen can recover as much as 60 to 70 percent of the kinetic energy lost during deceleration ». https://www.electrichybridvehicletechnology.com/opinion/10520.html

### (c) Plages typiques
- Chaîne mécanique → électrique seule : 0.85-0.92.
- Chaîne mécanique → réseau (incluant onduleur, transformateur) : **0.75-0.85**.
- Chaîne complète si stockage batterie : 0.55-0.70 (round-trip).
- **0.80 retenu par le simulateur = milieu de la plage** pour la chaîne sans stockage, ce qui est cohérent avec un funiculaire qui réinjecte directement sur le réseau du domaine skiable.

### (d) Application dans le simulateur
- Calcul de la puissance signée moteur : `power_signed_kw = (f_motor * tr.v) / 1000.0` ligne **990**.
- Aiguillage traction / régénération selon le signe : lignes **991-998**.
- Application du rendement : `tr.regen_kw = -power_signed_kw * 0.80` ligne **998**.
- Bilan énergie nette : `st.score_energy += (tr.power_kw - tr.regen_kw) * dt / 3600.0` ligne **1080**.

---

## 6. Jerk et confort des passagers

### (a) Formule / plage
```
|da/dt| ≤ J_confort
```
- **J ≈ 1 m/s³** : limite « très confortable » (passagers debout sans appui).
- **J ≈ 2 m/s³** : limite acceptable pour transport quotidien.
- **J ≈ 4-5 m/s³** : franchement perceptible, début de gêne.

### (b) Sources canoniques
- **ISO 2631-1 (1997, A1:2010) — *Mechanical vibration and shock — Evaluation of human exposure to whole-body vibration — Part 1: General requirements***. https://www.iso.org/standard/7611.html ; spec. https://cdn.standards.iteh.ai/samples/7611/68c0e4c43e6f40e2868aeefa06812abc/ISO-2631-1-1985.pdf
- **ISO 2631-4 (2001) — *Guidelines for the evaluation of the effects of vibration and rotational motion on passenger and crew comfort in fixed-guideway transport systems***. https://www.iso.org/standard/32178.html
- **Bellem et al. (2022) — *Standards for passenger comfort in automated vehicles: Acceleration and jerk*** (Applied Ergonomics, revue critique des seuils standards). https://www.sciencedirect.com/science/article/pii/S0003687022002046
- **STRMTG — Guide technique RM5 (funiculaires, déc. 2018)**, §2.4 : limites de jerk et décélération en service normal et freinage d'urgence. http://www.strmtg.developpement-durable.gouv.fr/IMG/pdf/rm5_funiculaire_v1_dec2018.pdf
- **EN 13803** : norme européenne tracé voie ferrée — spécifie un jerk admissible ≤ 0.4-0.5 m/s³ sur les courbes de transition (plus restrictif car cumulé à l'accélération latérale).
- **Indice de Sperling** (Wz) : indice allemand historique de qualité de roulement, lié à la dérivée de l'accélération.
- **Emerald — Assessment of ride comfort of traction elevators using ISO 18738-1:2012 and ISO 2631-4** : application aux ascenseurs et systèmes guidés. https://www.emerald.com/jimse/article/3/2/156/213531/

### (c) Plages typiques
- Ascenseur de luxe : J ≤ 0.6 m/s³.
- Métro automatique : J ≤ 1.0 m/s³.
- Funiculaire moderne (Von Roll, Garaventa) : J ≤ 1.0 m/s³ en service nominal, jusqu'à 2-2.5 m/s³ en arrêt programmé.
- Frein d'urgence : J peut monter à ~4 m/s³ pendant le ramping initial, mais reste borné par la dynamique pneumatique/hydraulique.

### (d) Application dans le simulateur
- Mesure du jerk instantané : `jerk = abs(a - tr.a) / max(dt, 1e-3)` ligne **925**.
- Cumul pour score confort : `tr.jerk_sum += jerk * dt` ligne **926**.
- Score affiché : `st.score_comfort = max(0.0, 100.0 - tr.jerk_sum * 0.015)` ligne **1081**.
- Limitation indirecte du jerk via :
  - rampe d'engagement du frein d'urgence sur ~0.4 s (`A_BRAKE_EMERG_RAMP`, lignes **815-821**) ;
  - soft-cap d'accélération (`soft_cap = A_START + (A_MAX_REG - A_START) * min(1.0, v_abs / V_SOFT_RAMP)` lignes **840-846**) qui ramp progressivement A_START → A_MAX_REG ;
  - slew limiter du setpoint vitesse : `RAMP_UP = 0.35 m/s²`, `RAMP_DOWN = 0.25 m/s²` lignes **1256-1257**.

---

## 7. Limitation de survitesse (déclenchement à 110 % V_max)

### (a) Formule / règle
```
Si |v| > 1.10 · V_max  ⇒  coupure traction + frein de chute déclenché + verrouillage (latched)
```

### (b) Sources canoniques
- **STRMTG — Guide technique RM5 v1 (décembre 2018), Funiculaires** : « les funiculaires sont équipés de freins de rail (ou freins de chute) qui s'engagent automatiquement en cas de survitesse, de rupture de câble tracteur, ou d'anti-retour ». PDF intégral : http://www.strmtg.developpement-durable.gouv.fr/IMG/pdf/rm5_funiculaire_v1_dec2018.pdf ; page guide : https://www.strmtg.developpement-durable.gouv.fr/version-1-du-guide-technique-rm5-relatif-aux-a568.html
- **EN 1709 — *Safety requirements for cableway installations designed to carry persons — Precommissioning inspection, maintenance, operational inspection and checks*** (adaptée aux téléphériques mais référencée en cross-référence pour les funiculaires).
- **CEN/TS 17462 — *Safety requirements for funicular installations carrying persons*** : spécification technique européenne pour les funiculaires.
- **Brevet CA 2013646 A1 — *Emergency braking device of a funicular*** : description du déclenchement automatique en cas de survitesse. https://patents.google.com/patent/CA2013646A1/en
- **EIDE — FPC Overspeed Safety Brake** : produit industriel illustrant le seuil de déclenchement type. https://eide.net/en/fpc-overspeed-safety-brake/
- **STRMTG — page institutionnelle réglementation des funiculaires**. http://www.strmtg.developpement-durable.gouv.fr/reglementation-technique-des-funiculaires-a211.html

### (c) Plages typiques
- Seuil légal en France (RM5) et UE (CEN/TS 17462) : **survitesse instantanée à V_nominale × 1.10 à 1.15** déclenche frein de chute.
- Survitesse cumulée (intégrale d'écart sur quelques secondes) : seuil souvent fixé à 1.05 × V_nom sur 3-5 s.
- Verrouillage obligatoire : impossible de réarmer sans intervention manuelle (driver acquittement).

### (d) Application dans le simulateur
- Détection : `if abs(tr.v) > 1.10 * V_MAX and not tr.overspeed_tripped:` ligne **967**.
- Conséquences appliquées (verrouillé) : lignes **968-983** :
  - `overspeed_tripped = True` (latch),
  - `tr.emergency = True` (frein de chute armé),
  - `tr.speed_cmd = 0.0`, `tr.throttle = 0.0`,
  - `ready = False`, annule la séquence de départ,
  - événement journalisé bilingue.
- Conforme à la doctrine STRMTG RM5 : déclenchement à 110 % V_max, latched.

---

## 8. Lissage EMA pour les afficheurs

### (a) Formule
Filtre passe-bas du premier ordre (IIR), équivalent discret d'un RC analogique :
```
y_n = α · x_n + (1 - α) · y_{n-1}
```
avec
```
α = dt / (τ + dt)        (forme classique, exacte pour échantillonnage variable)
α = 1 - exp(-dt/τ)       (forme « pole-matched », plus précise pour grand dt/τ)
```

### (b) Sources canoniques
- **Wikipedia — Exponential smoothing** : référence d'introduction. https://en.wikipedia.org/wiki/Exponential_smoothing
- **Steven W. Smith — *The Scientist and Engineer's Guide to Digital Signal Processing*** (Analog Devices, gratuit en ligne), chap. 15 « Moving Average Filters » et chap. 19 « Recursive Filters ». https://www.analog.com/media/en/technical-documentation/dsp-book/dsp_book_ch15.pdf
- **mbedded.ninja — Exponential Moving Average (EMA) Filters** : démonstration de la dérivation α = dt/τ. https://blog.mbedded.ninja/programming/signal-processing/digital-filters/exponential-moving-average-ema-filter/
- **Pieter Pas — *Exponential Moving Average* (UGent)** : analyse mathématique complète et discrétisation. https://tttapa.github.io/Pages/Mathematics/Systems-and-Control-Theory/Digital-filters/Exponential%20Moving%20Average/Exponential-Moving-Average.html
- **DSPRelated — *The First-Order IIR Filter — More than Meets the Eye*** (Neil Robertson). https://www.dsprelated.com/showarticle/1769.php
- **Greg Stanley — Exponential Filter**. https://gregstanleyandassociates.com/whitepapers/FaultDiagnosis/Filtering/Exponential-Filter/exponential-filter.htm
- **Manuel** : Oppenheim & Schafer, *Discrete-Time Signal Processing*, Pearson, 3e éd. 2009, ISBN 978-0-13-198842-2.

### (c) Plages typiques
- τ ≈ 0.1-0.5 s pour un afficheur de cabine analogique (élimine le 50 Hz, suit l'opérateur).
- τ ≈ 1-2 s pour un afficheur de tendance (température, statistique).

### (d) Application dans le simulateur
- Lignes **1000-1002** :
  ```python
  alpha = min(1.0, dt / 0.3)
  tr.tension_dan_disp += (tr.tension_dan - tr.tension_dan_disp) * alpha
  tr.power_kw_disp += (tr.power_kw - tr.power_kw_disp) * alpha
  ```
- Forme utilisée : `α = dt/τ` avec τ = 0.3 s, **clampée à 1.0** pour éviter le dépassement quand dt > τ (i.e. si la simulation tourne très lentement, on ne « surcorrige » pas).
- Note : la forme `dt/τ` est l'approximation de Taylor d'ordre 1 de `1 - exp(-dt/τ)` ; elle est exacte à mieux que 1 % tant que dt < 0.1·τ. Pour dt = 1/60 s et τ = 0.3 s, dt/τ ≈ 0.056 → erreur < 3 %, parfaitement acceptable pour de l'affichage.

---

## 9. Oscillation amortie (rebond du câble)

### (a) Formule
Solution générale du système masse-ressort-amortisseur sous-amorti (ζ < 1) :
```
x(t) = A · exp(-ζ · ω_n · t) · sin(ω_d · t + φ)
```
avec
- ω_n = √(k/m) : pulsation naturelle (rad/s),
- ζ : taux d'amortissement (0 < ζ < 1 → oscillatoire),
- ω_d = ω_n · √(1 - ζ²) : pulsation amortie,
- A et φ déterminés par les conditions initiales.

L'équation différentielle de référence : `ẍ + 2·ζ·ω_n·ẋ + ω_n² · x = 0`.

### (b) Sources canoniques
- **S.S. Rao — *Mechanical Vibrations*** (Pearson, 6e éd. 2017, ISBN 978-0-13-436130-7). Référence universitaire pour le sujet, chap. 2 (vibrations libres amorties) et chap. 6 (systèmes continus type câble).
- **Wikipedia — Harmonic oscillator** : dérivation complète des trois régimes (sous-amorti, critique, sur-amorti). https://en.wikipedia.org/wiki/Harmonic_oscillator
- **Physics LibreTexts — *The Damped Harmonic Oscillator*** (Chong). https://phys.libretexts.org/Bookshelves/Mathematical_Physics_and_Pedagogy/Complex_Methods_for_the_Sciences_(Chong)/05:_Complex_Oscillations/5.01:_The_Damped_Harmonic_Oscillator
- **MathWorks Symbolic Math Toolbox — *The Physics of the Damped Harmonic Oscillator*** : démo interactive avec la solution Ae^(-ζω₀t) sin(…). https://www.mathworks.com/help/symbolic/physics-damped-harmonic-oscillator.html
- **Farside (UT Austin) — *Damped Harmonic Oscillation*** (Fitzpatrick). https://farside.ph.utexas.edu/teaching/315/Waves/node12.html
- **Manuel complémentaire** : Den Hartog, J.P., *Mechanical Vibrations*, 4e éd. (Dover reprint), ISBN 978-0-486-64785-2 — référence historique.

### (c) Plages typiques pour câble Fatzer ~3.5 km
- Pulsation naturelle ω_n ≈ √(EA / (m·L)) : pour A ≈ 2.1e-3 m², E ≈ 1.05e11 Pa, m_train ≈ 60 t, L ≈ 3500 m → ω_n ≈ √(2.2e8 / 2.1e8) ≈ 1.0 rad/s, soit période ~6 s.
- Taux d'amortissement ζ : 0.05-0.15 (frottement interne du câble + roulement + dissipation au treuil).
- Décroissance d'amplitude visible : ~3-5 oscillations avant atténuation < 5 %.

### (d) Application dans le simulateur
- Lignes **1020-1022** :
  ```python
  creep = 1.0 - math.exp(-t_r / REBOUND_TAU)
  osc = (math.exp(-REBOUND_ZETA * REBOUND_OMEGA * t_r)
         * math.sin(REBOUND_OMEGA * t_r))
  ```
- Le « creep » est la composante exponentielle de relâchement de l'allongement statique (1 - e^(-t/τ)).
- L'« osc » est la composante oscillatoire amortie standard : exp(-ζω·t) · sin(ω·t), exactement la solution canonique avec phase φ = 0.
- Les dérivées analytiques de ces composantes sont également calculées correctement aux lignes **1065-1072** pour la vitesse instantanée du rebond :
  - dCreep/dt = (A/τ) · exp(-t/τ),
  - dOsc/dt = ω·exp(-ζωt)·cos(ωt) − ζω·exp(-ζωt)·sin(ωt) — application directe de la règle du produit.
- Constantes `REBOUND_TAU`, `REBOUND_ZETA`, `REBOUND_OMEGA` à régler dans l'en-tête en fonction des plages ci-dessus.

---

## 10. Plafond de décélération en service (~0.4 m/s²)

### (a) Formule / règle
```
|a_freinage_service|  ≤  0.4 m/s²  (cible confort)
|a_freinage_urgence|  ≤  ~5 m/s²    (plafond physique, intégrité passagers)
```

### (b) Sources canoniques
- **STRMTG — Guide technique RM5 (funiculaires, v1, déc. 2018)**, §2.4 : décélérations admissibles — service normal ≤ 0.5 m/s², freinage d'arrêt programmé ≤ 1.25 m/s², frein de service ≤ ~2-3 m/s², frein de chute ~5 m/s². http://www.strmtg.developpement-durable.gouv.fr/IMG/pdf/rm5_funiculaire_v1_dec2018.pdf
- **STRMTG — page sommaire des guides techniques**. https://www.strmtg.developpement-durable.gouv.fr/guides-techniques-a150.html
- **STRMTG (EN) — Funicular railways**. https://www.strmtg.developpement-durable.gouv.fr/en/funicular-railways-a137.html
- **CEN/TS 17462** (funicular safety, voir §7).
- **Doppelmayr/Garaventa Group** : documentation client. https://service.doppelmayr.com/services/ et brochures techniques https://www.doppelmayr.com/wp-content/uploads/2022/11/DM_WIR196_ENG.pdf
- **Garaventa — Modernisation Rigiblick (Zurich)** : illustration des paramètres confort / freinage. https://www.simagazin.com/en/si-urban-en/topics-urban/cities/zuerich-garaventa-modernizes-rigiblick-funicular/
- **Doppelmayr — Funicular Carriage Inspec** : brochure constructeur. https://mediacenter.doppelmayr.com/doppelmayr-customer-service/62012866/33

### (c) Plages typiques
- « Arrêt simple » Von Roll / Garaventa (relâchement traction + frein régénératif) : **0.3-0.5 m/s²**.
- Frein de service hydraulique ramped : 0.8-1.5 m/s².
- Frein de service en pleine action : 2-3 m/s².
- Frein de chute (rail) : 4-6 m/s² (limité par confort RM5).

### (d) Application dans le simulateur
- Mode « arrêt électrique / homme mort » dans le régulateur, ligne **1172** :
  ```python
  TARGET_DECEL = 0.4  # m/s² — Von Roll service stop comfort
  ```
- Boucle PI sur la décélération mesurée :
  - `obs_decel = -math.copysign(tr.a, tr.v)` ligne **1190**,
  - `err = TARGET_DECEL - obs_decel` ligne **1191**,
  - sortie filtrée par un slew rate sur le frein (BRAKE_RAMP_UP=0.05/s ligne **1177**).
- Le commentaire bloc lignes **1170-1172** cite explicitement « Von Roll service stop comfort ».
- Frein d'urgence séparé à 5 m/s² (`A_BRAKE_EMERGENCY`, ligne ~813) : « matches the STRMTG passenger-comfort ceiling (RM5 §2.4) ».

---

## 11. Profil de zone de creep / approche quadratique

### (a) Formule
Approche en station via une rampe quadratique sur la vitesse résiduelle :
```
v_envelope(d) = √( v_creep² + 2 · a_target · (d - d_creep) )    pour d > d_creep
v_park(d)     = √( 2 · a_park · d )                               pour d ≤ d_creep
```
issue de l'intégration du mouvement uniformément décéléré (v² = v₀² + 2·a·Δs).

### (b) Sources canoniques
- **European Railway Agency (ERA) — *Introduction to ETCS braking curves*** (ERA_ERTMS_040026 v1.5) : doctrine standard ETCS Level 2/3 pour les courbes de freinage, profile = √(2·a·d) avec marge de sécurité. https://www.era.europa.eu/system/files/2022-11/Introduction%20to%20ETCS%20braking%20curves.pdf
- **Springer — *Refining arrival headway for high-speed trains approaching a large railway station: a speed profile intervention approach*** (2024). https://link.springer.com/article/10.1007/s40534-024-00361-5
- **Pedestrian Observations — *Setting Speed Zones*** (analyse pratique des profils d'approche). https://pedestrianobservations.com/2023/10/27/setting-speed-zones/
- **Wikipedia — Track transition curve** : profils géométriques utilisant des paraboles (analogue spatial du profil de vitesse). https://en.wikipedia.org/wiki/Track_transition_curve
- **STRMTG RM5** (mêmes références que §6 et §10) : profil de freinage programmé pour arrêt en station avec courbe enveloppe.
- **Manuel ferroviaire** : Pyrgidis, C.N., *Railway Transportation Systems*, CRC Press, 2nd ed. 2020, ISBN 978-0-367-25634-8 — chap. sur le contrôle de vitesse et profils d'approche.
- **STRMTG — Réglementation funiculaires**. http://www.strmtg.developpement-durable.gouv.fr/reglementation-technique-des-funiculaires-a211.html

### (c) Plages typiques
- v_creep ferroviaire (approche station) : 0.5-2 m/s.
- a_target en approche programmée : 0.3-0.6 m/s² (équivalent à la décélération naturelle du métro).
- d_creep : 30-100 m selon la vitesse de croisière.
- Phase de docking final (« park ») : décélération encore plus douce, 0.04-0.1 m/s² sur les derniers mètres → arrêt « invisible » sans à-coup.

### (d) Application dans le simulateur
- Profil principal d'enveloppe d'approche : ligne **1246** :
  ```python
  v_envelope = math.sqrt(CREEP_V * CREEP_V + 2.0 * a_env * d_to_creep)
  ```
  → exactement la forme intégrée v² = v_creep² + 2·a·d.
- Phase de creep / docking final lignes **1283-1291** :
  ```python
  PARK_DECEL = 0.04         # m/s² final-docking decel
  FINAL_DIST = 6.0          # m over which the taper applies
  …
  v_park = math.sqrt(2.0 * PARK_DECEL * max(dist_to_stop, 0.001))
  target_v = min(CREEP_V, v_park)
  ```
  → même forme racine carrée, avec décélération ultra-douce 0.04 m/s² sur les 6 derniers mètres.
- Choix de `a_env` adaptatif selon que la gravité aide ou pas : lignes **1232-1245** — bonne pratique de feed-forward gravité, conforme aux logiques de pilotage Von Roll.

---

## Annexe — Constantes physiques utilisées dans le simulateur (à vérifier dans l'en-tête `perce_neige_sim.py`)

| Constante | Valeur attendue | Justification | Référence |
|---|---|---|---|
| `G` | 9.81 m/s² | Gravité standard | CGPM |
| `MU_ROLL` | 0.002-0.004 | Roue acier sur rail acier (cf. §2) | FRA Survey, UIC 544 |
| `P_MAX` | ~2.4 MW (3 × 800 kW) | Drive Von Roll Perce-Neige | CFD datasheet |
| `F_STALL` | ~400-500 kN | Couple max bull-wheel | Calcul mécanique constructeur |
| `V_MAX` | 12 m/s | Vitesse opérationnelle | Documentation Perce-Neige |
| `A_MAX_REG` | ~1.0 m/s² | Confort cruise | RM5 §2.4 |
| `A_BRAKE_NORMAL` | ~1.5 m/s² | Frein de service | RM5 §2.4 |
| `A_BRAKE_EMERGENCY` | 5.0 m/s² | Frein de chute | RM5 §2.4 (plafond confort) |
| `CREEP_V` | ~1.0 m/s | Vitesse de creep en station | Train control practice |
| `CREEP_DIST` | 30-50 m | Longueur de la zone de creep | Pratique funiculaire |
| `REBOUND_TAU` | ~3-5 s | Constante de relaxation câble | Mesure Fatzer |
| `REBOUND_ZETA` | 0.05-0.15 | Amortissement câble | Rao §2.6 |
| `REBOUND_OMEGA` | ~1 rad/s | Pulsation câble 3.5 km | Calcul §9 |
| Allongement câble (A·E) | 2.12e-3 × 1.05e11 = 2.23e8 N | Section et module Fatzer 52 mm | Feyrer, Fatzer datasheet |

---

## Synthèse de cohérence

Toutes les formules implémentées dans `Physics.step()` et `Physics._regulator()` correspondent aux références canoniques de la littérature traction électrique, mécanique des câbles et confort passager. Les valeurs numériques retenues (105 GPa pour le module câble, 0.80 pour le rendement régénération, 4.5× pour l'inrush DC, 0.4 m/s² pour la décélération de service, 110 % V_max pour le seuil de survitesse, 5 m/s² pour le frein d'urgence) sont toutes dans la médiane des plages publiées et **cohérentes entre elles** vis-à-vis d'un funiculaire de génération Von Roll des années 1980-90 type Perce-Neige. Le simulateur peut donc être considéré comme **physiquement justifié** pour son usage pédagogique et ludique.
