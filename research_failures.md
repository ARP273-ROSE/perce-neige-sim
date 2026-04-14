# Research — Modes de défaillance des funiculaires

> **Périmètre** : recherche documentaire sur les pannes et incidents
> susceptibles d'affecter un funiculaire à câble unique en tunnel
> comparable au **Perce-Neige de Tignes** (Von Roll 1993, 3 491 m,
> Fatzer 52 mm 6×26 Lang, 3 × 800 kW DC SICME, 334 pax, v_max 12 m/s).
>
> **Objectif** : alimenter et calibrer le mode `panne` du simulateur
> PyQt6 avec des seuils, des déclencheurs et des comportements
> physiquement crédibles, sourcés sur des incidents réels et la
> réglementation française (STRMTG).
>
> **Date** : 2026-04-14.

---

## 1. Méthodologie

### 1.1 Sources consultées (résumé)

| Catégorie | Sources clés | Fiabilité |
|---|---|---|
| Réglementation | STRMTG (RM5 Funiculaires v1 déc. 2018), brevets | Primaire |
| Incidents documentés | Wikipédia FR (liste accidents RM), presse (CNN, France 24, Le Temps, RTS, Le Moniteur, Globes, Funimag) | Secondaire vérifiée |
| Technique câble | OITAF, ISO 4309, DIN EN 12927-6, NDT.net, Quadco | Primaire |
| Forums spécialisés | remontees-mecaniques.net, haute-tarentaise.net, funimag | Secondaire (croisé) |
| Patents | EP0392938A1 POMA (frein de sécurité funiculaire) | Primaire |

### 1.2 Limites honnêtes

- **Aucun rapport BEA-TT ne traite spécifiquement du Perce-Neige** —
  l'incident d'évacuation 2008 (forum) n'a pas généré d'enquête
  publique car pas de blessé et cause externe (réseau électrique).
- **Les rapports STRMTG annuels** mentionnent agrégats statistiques
  mais rarement par appareil nominal — pas d'historique panne par
  panne du Perce-Neige publié.
- **Données constructeur** (Von Roll → Doppelmayr) post-1993 inaccessibles.
- Les seuils chiffrés du simulateur (températures moteur, surtension
  câble en daN, durées) sont **calibrés ingénieriquement** à partir
  des classes d'isolation moteur, du facteur de sécurité câble et des
  recommandations OITAF/ISO, **pas mesurés** sur l'appareil réel.

---

## 2. Tableau des incidents — Simulateur ↔ Réalité

Mapping des 9 pannes existantes du simulateur (`perce_neige_sim.py`,
fonction `maybe_random_event`, ligne ~1426) avec les références réelles.

| # | Panne simulateur | Effet sim | Comparable réel | Source |
|---|---|---|---|---|
| 1 | `tension` | +6 500 daN sur jauge câble, 22 s | Surtensions Glória Lisbonne (cable splice failure) ; Montmartre rupture culot 2006 | CNN 2025-10-21, Funimag 2006 |
| 2 | `door` | Capteur porte HS — arrêt station, 35 s | Standard d'industrie post-Kaprun (portes bloquées en feu) | Wikipedia Kaprun, RM5 §3.4 |
| 3 | `thermal` | Bobinages 85→105 °C, derate 55 %, v≤8 m/s, 80 s | Classe F isolation 155 °C ; Class B rise 80 K | IEC 60349-2, Cat/EC&M |
| 4 | `fire` | Détection fumée → arrêt urgence, 60 s | **Kaprun 11/11/2000 — 155 morts** ; Carmelit Haïfa fév. 2017 | Wikipedia Kaprun, Globes Carmelit |
| 5 | `wet_rail` | Adhérence dégradée, v≤6 m/s, 35 s | Suintement voûte tunnel rocheux (universel) | OITAF, RM5 §2 |
| 6 | `motor_degraded` | 1 des 3 × 800 kW HS, mode 2/3, v≤9 m/s, 90 s | Sassi-Superga D2+D3 panne simultanée (réduit à D1) | Wikipedia Sassi-Superga |
| 7 | `slack` | −8 000 daN, mou câble détecté, 12 s | Détecteur slack obligatoire (RM5) ; Glória cause secondaire | RM5, GPIAAF Lisbonne |
| 8 | `aux_power` | Perte 400 V → traction coupée, frein serré, 25 s | **Perce-Neige 19/08/2008** (panne courant générale Val Claret, évacuation à pied) | Forum haute-tarentaise.net |
| 9 | `parking_stuck` | Frein parking ne se lève pas, 18 s | Standard EIDE / EP0392938A1 | Patent POMA 1989 |

### 2.1 Pannes manquantes au simulateur (suggestions)

| Panne | Justification réelle |
|---|---|
| **Rupture du câble tracteur** | Glória Lisbonne 2025 (16 morts, câble non certifié), Montmartre 2006, Carmelit 2015 |
| **Frein de service inopérant** | Glória 2025 (frein pneumatique perdu après rupture câble + frein manuel insuffisant) |
| **Survitesse non triggered** | Cas hypothétique critique : trip à 110 % V_max obligatoire (RM5) |
| **Désalignement aiguillage Abt** | Spécifique Perce-Neige (sabot d'enclenchement) |
| **Ventilation tunnel HS** | Conséquence amplificatrice du `fire` (désenfumage) |
| **Eau crue / inondation tunnel** | Funiculaires souterrains (zone glacier, fonte) |
| **Communication PA / GSM tunnel HS** | Leçon Kaprun (passagers sans contact attendant) |

---

## 3. Incidents documentés par funiculaire comparable

### 3.1 Perce-Neige (Tignes) — 19 août 2008

**Source** : forum haute-tarentaise.net + remontees-mecaniques.net topic 232.

**Faits** :
- ~16h15, panne générale du réseau électrique Val Claret (extérieure
  à STGM).
- Au rétablissement, le funiculaire **ne redémarre pas**.
- **Deux cabines bloquées dans le tunnel** — évacuation à pied des
  passagers.
- Personnes à mobilité réduite : assistance pompiers + secouristes
  station.
- Restaurant panoramique Grande Motte : descente en 4×4.

**Pertinence sim** : illustre exactement la panne `aux_power` actuelle.
La séquence réelle (perte alim → traction coupée → évacuation tunnel
plat) confirme le scénario implémenté. Suggère d'ajouter un branchement
narratif "évacuation pédestre" si la panne dure > 5 min.

### 3.2 Kaprun (Autriche) — 11 novembre 2000 — 155 morts

**Source** : Wikipedia EN/FR, Medium (Schroeder), grokipedia.

**Faits techniques** :
- Funiculaire **tunnel** Gletscherbahn Kaprun 2 (3,3 km).
- Train s'arrête 600 m dans le tunnel à 9h10.
- **Origine** : friteuse électrique non homologuée dans cabine
  conducteur arrière, fuite huile sur radiateur électrique.
- Aggravation : **portes verrouillées par sécurité standard**, pas
  d'extincteur accessible passagers, **pas de détecteur fumée**, pas
  de réseau radio dans tunnel, effet cheminée.

**Leçons réglementaires (post-2000) appliquées au Perce-Neige (1993)
en rétrofit** :
- Détecteurs fumée obligatoires
- Extincteurs accessibles aux passagers
- Communication intercom / interphone tunnel
- Marteaux brise-vitre
- Matériaux ignifuges
- Possibilité d'ouverture manuelle des portes
- Désenfumage tunnel + éclairage de secours

**Pertinence sim** : confirme la **gravité** maximale de la panne
`fire`. Justifie l'arrêt d'urgence immédiat et un timer minimum de 60 s
(temps désenfumage). Suggère un mode **évacuation tunnel** dédié.

### 3.3 Glória (Lisbonne) — 3 septembre 2025 — 16 morts

**Source** : CNN 2025-10-21, France 24 2025-10-20, NBC News, Wikipedia
"Ascensor da Glória derailment".

**Faits techniques** (rapport intérimaire GPIAAF) :
- Cabine haute s'emballe en descente, **déraille en bas**, percute un
  immeuble.
- **Câble entre cabines rompu à son point d'attache supérieur**.
- Câble **non certifié** pour transport de personnes.
- Câble **non conforme aux spécifications** CCFL — pas de tests ni
  inspection avant installation.
- **Tâches de maintenance marquées comme faites sans l'avoir été**.
- Après rupture câble : **frein pneumatique perdu** (coupure power),
  frein manuel **insuffisant** pour arrêter la cabine.

**Pertinence sim** : justifie une panne **rupture câble** explicite
avec **double défaillance** (câble + frein parachute lent à se serrer).
Met en lumière l'importance des **tests freins charge réelle**
hebdomadaires (fait au Perce-Neige, voir RM5).

### 3.4 Montmartre (Paris) — 7 décembre 2006

**Source** : Funimag photoblog 2006-12-19, Le Moniteur, forum
remontees-mecaniques topic 2014.

**Faits** :
- Test annuel STRMTG des freins de cabine sous charge.
- **Culot du câble tracteur cède** lors de la 2ème série de tests.
- Cabine **chute au bas du plan incliné**.
- **Aucun blessé** (test, sans passagers).
- Service réduit à 1 cabine du 30 juin 2007 au 2 août 2008.

**Pertinence sim** : illustre la **fragilité de l'attache câble**
(souvent culot conique avec alliage zinc) sollicitée en surcharge lors
des tests. Démontre la valeur du test annuel — qui *trouve* les
défauts *avant* l'accident voyageurs.

### 3.5 Carmelit (Haïfa, Israël) — souterrain similaire

**Source** : Wikipedia "Carmelit", Globes 2018.

Trois incidents notables :
- **1986–1992** : fermeture pour rénovation lourde après 27 ans.
- **Mars 2015** : panne **câble défectueux** — fermeture jusqu'en
  juillet 2015.
- **4 février 2017** : **incendie en gare Paris** hors heures
  d'ouverture. 1 rame fortement endommagée + parties tunnel. Réouverture
  octobre 2018 avec rames neuves Doppelmayr.
- **Août–septembre 2025** : 3 semaines fermées pour réfection dalle
  béton tunnel.

**Pertinence sim** : Carmelit est l'**analogue le plus proche** du
Perce-Neige (souterrain, longueur comparable, contexte service
intensif). Trois pannes en 30 ans = **base statistique** pour fixer le
taux d'événement aléatoire dans le sim (ordre de grandeur 1 panne
significative tous les 5–10 ans en exploitation normale).

### 3.6 Sassi–Superga (Turin) — incidents matériel roulant

**Source** : Wikipedia IT, GTT.

- Conversion 1934 funiculaire → tramway à crémaillère central.
- Quand **D2 et D3 en panne simultanément**, service réduit à D1
  (40 pax) + bus de remplacement.

**Pertinence sim** : appuie le scénario `motor_degraded` (perte
redondance partielle).

### 3.7 M2 Lausanne (mixte funiculaire/métro)

**Source** : Le Temps, RTS, 24 heures.

Pannes récurrentes :
- Décembre 2022 : panne générale 6h–10h.
- 12 avril 2023 : défaut alimentation électrique.
- 29 janvier 2016 : pannes consécutives section unique + circuit
  puissance.

**Pertinence sim** : confirme que les **pannes alimentation électrique**
sont le mode de défaillance le plus fréquent en exploitation
(corrélé `aux_power`).

### 3.8 Stoos (Suisse) — recherche infructueuse

Aucun incident significatif documenté depuis l'ouverture
2017 — l'appareil est récent (Garaventa) et plutôt cité comme
référence de fiabilité 110 % pente.

### 3.9 Funival Val d'Isère — recherche infructueuse

Aucun rapport public d'incident sur Funival (1987, voisin direct).
Forum haute-tarentaise.net mentionne accidents génériques Val d'Isère
mais pas Funival spécifiquement.

### 3.10 Capelinhos Açores 2019 — non vérifié

**Aucune trace** d'un funiculaire à Capelinhos (Faïal, Açores) : c'est
un site volcanique avec phare et centre d'interprétation souterrain,
**pas de funiculaire**. Probablement confusion par l'utilisateur. À
écarter de la liste.

---

## 4. Physique des défaillances

### 4.1 Fatigue câble (Palmgren-Miner)

**Loi cumulative** : `D = Σ (n_i / N_i)` où `n_i` = cycles à amplitude
`σ_i`, `N_i` = cycles à rupture pour cette amplitude. Rupture
attendue à `D = 1` (en pratique, codes prennent `D ≤ 0,5` pour acier
soudé pour marge — cf. Quadco, ScienceDirect).

**Application Perce-Neige** :
- Coefficient sécurité statique : 191 200 / 22 500 = **8,5** (très
  élevé, conforme funiculaire vs grues 5–6).
- Cycles aller-retour ≈ 30/jour × 200 jours/an = 6 000 cycles/an.
- Câbles funiculaire : durée vie usuelle 12–18 ans. **Remplacement
  Perce-Neige documenté en 1999** (6 ans après mise en service —
  cycle court probablement intervenu sur défaut détecté MFL).

**Critères de mise au rebut (DIN EN 12927-6, ISO 4309)** :
- Perte section métallique LMA > **25 %** sur réf. 500d, > **6 %** sur
  réf. 6d → rebut immédiat.
- Nombre fils rompus visibles > seuil par type câblage (Lang : seuil
  plus strict que ordinaire car interaction visuelle des fils).

**Comportement sim suggéré** : compteur de cycles avec dégradation
progressive de la résistance utile, déclenchant un avertissement à
80 % du seuil de rebut puis échec catastrophique à 100 %.

### 4.2 Survitesse — réglementation

**Source** : EP0392938A1 (POMA), forums remontees-mecaniques,
clearsy.com.

**Seuils typiques** :
- **+10 % V_max** → **trip frein de service** (commande électrique).
- **+12 %** → frein de secours automatique.
- **+20 %** → frein d'ultime secours mécanique (parachute pince/rail
  par déclencheur centrifuge).

**Application Perce-Neige** :
- V_max = 12 m/s.
- Seuil 1 : 13,2 m/s.
- Seuil 2 : 13,44 m/s.
- Seuil 3 : 14,4 m/s → frein parachute Belleville garanti.

**Décélération admissible** (RM5 + brevet POMA) :
- Confort exploitation : ≤ **1,25 m/s²** (1,5 max ponctuel).
- Service : ≤ **2,5 m/s²**.
- Urgence : ≤ **5 m/s²** absolu.
- Pratique freins pince Belleville sur rail : 3,2–4,1 m/s² mesurés
  (compatible 30 % pente Perce-Neige : 3,6 m/s² extrapolé).

### 4.3 Thermique moteur DC

**Source** : IEC 60349-2, Cat / Caterpillar white paper, EC&M.

**Classes d'isolation pertinentes** :
- Classe F : 155 °C absolu, élévation 105 K (rise sur 40 °C ambiant).
- Classe H (traction usage) : **180 °C absolu**, élévation 125 K, max
  220 °C.

**Loi d'Arrhenius simplifiée** : durée de vie isolation **divisée par
2 tous les +10 °C** au-dessus du nominal.

**Application Perce-Neige (3 × 800 kW DC SICME)** :
- Service intensif été (skieurs glacier) = 30 cycles/h × 5 min × 80 %
  charge = service S5 intermittent.
- Ventilation forcée externe + cale rotor obligatoire.
- Seuil derate sim (`thermal` : 105 °C) **cohérent** avec class F
  rise 80 K + ambient 25 °C = 105 °C alarme.

### 4.4 Adhérence rail (« wet_rail »)

Tunnel rocheux sous glacier : **suintement année-round** (eau de
fonte glaciaire + condensation murs froids). Pas de gel possible
(profondeur > 100 m sous surface, T° stable 0–4 °C).

**Coefficient adhérence acier-acier** :
- Sec : μ ≈ 0,15–0,20.
- Humide : μ ≈ 0,08–0,12.
- Polluant + eau : μ ≈ 0,05.

Funiculaire à câble = **traction non dépendante de l'adhérence rail**
(le câble tire). Mais **freinage d'urgence pince/rail dépend de
l'adhérence** : si rail mouillé, distance de freinage allongée.

**Pratique sim** : limiter v à 6 m/s permet de garantir distance
freinage ≤ 30 m même avec μ = 0,05 (`v² / 2·μ·g = 36 / (0,98) ≈ 37 m`).

### 4.5 Perte alimentation et freinage dynamique

**Architecture standard funiculaire électrique** :
- Alimentation principale : MV 20 kV → transfo → redresseur DC 750 V
  bus traction.
- Auxiliaires 400 V (ventilation, freins, signalisation, éclairage).
- **Backup** : batterie tampon DC + groupe diesel auxiliaire (3 ×
  thermiques au Perce-Neige selon forum RM).

**Modes de panne** :
- Perte MV → bascule onduleur batterie + groupe diesel (~30 s
  démarrage).
- Perte 400 V aux → traction coupée, **freins parking serrés
  automatiquement par défaut** (fail-safe).
- Pendant la perte, freinage **rhéostatique** dissipe l'énergie cinétique
  dans résistances de frein.

**Cohérent avec `aux_power` simulateur**.

### 4.6 Incendie tunnel — évacuation

**Source** : RM5 §4 (STRMTG), CETU (Centre Études Tunnels), retour
expérience Kaprun.

**Exigences réglementaires post-Kaprun** :
- Détection fumée multi-points.
- Désenfumage longitudinal ou semi-transversal selon longueur tunnel.
- Éclairage secours autonomie ≥ 1h.
- Marquage cheminement réfléchissant.
- Issues secours espacées ≤ 250 m (ITI 98-300 du 8 juillet 1998 pour
  tunnels ferroviaires, transposable).
- **Évacuation verticale** : technique consistant à ramener cabines
  par cabine à l'aide d'un dispositif roulant sur câble (cf. STRMTG
  exercice 7 Laux).

**Perce-Neige** :
- Tunnel 3 484 m, dénivelé 921 m → si évacuation pédestre : 30–60 min.
- Pas d'issue secours intermédiaire connue (tunnel mono-tube avec
  évitement central uniquement).
- En cas de feu, désenfumage par buse amont (gravité naturelle :
  l'air chaud monte vers gare amont 3 032 m).

### 4.7 Détecteur slack (mou câble)

**Principe** : capteur de tension différentielle sur poulie de renvoi.
Si tension < seuil bas (typiquement 60 % du nominal), interrupteur
bascule → arrêt d'urgence.

**Cause physique** :
- Train en descente qui décélère brutalement → cabine plus rapide que
  câble → mou côté contrepoids/cabine montante.
- Contrepoids bloqué (rare dans configuration Perce-Neige
  car contrepoids = autre rame).

**Cohérent avec `slack` simulateur (-8 000 daN momentané)**.

### 4.8 Frein parking bloqué (parking_stuck)

Frein parking funiculaire = frein à tambour sur poulie motrice
(différent du frein parachute pince/rail des cabines). Maintenu serré
ressort, libéré par circuit hydraulique.

**Modes de panne** :
- Fuite circuit hydraulique → ne libère pas.
- Garniture collée après long arrêt → libération mais résiduel.
- Capteur de levée HS → automate refuse traction.

Cycle d'arrêt d'urgence + reprise = procédure standard pour purger
hydraulique et tester capteurs.

---

## 5. Tableau récapitulatif — Pannes physiquement justifiées

| Nom (FR) | Nom (EN) | Cause physique | Seuil sim suggéré | Comportement sim | Réel comparable |
|---|---|---|---|---|---|
| Pic tension câble | Cable tension surge | Choc mécanique, démarrage brusque charge max | +30 % du nominal soit 22 500 + 6 750 daN | Avertisseur visuel, dérate puissance demande | Glória (cumul charges) |
| Mou câble | Cable slack | Décél brutale, élasticité câble 105 GPa × 3,5 km | -35 % nominal soit -7 875 daN | Trip arrêt si > 3 s | RM5 obligatoire |
| Rupture câble (à ajouter) | Cable rupture | Fatigue Miner D≥1, défaut culot, corrosion | LMA > 25 % cumulée | Frein parachute immédiat | **Glória 2025**, Montmartre 2006 |
| Surchauffe moteur | Motor overheat | Service S5 dépassé, ventilation HS | T° bobinage > 130 °C (class F) | Derate à 55 %, v≤8 m/s | Standard industriel |
| Groupe moteur HS | Motor group fault | Défaut redresseur, balais, capteur | 1 sur 3 | Mode 2/3, v≤9 m/s | Sassi-Superga |
| Survitesse | Overspeed | Dérive régulateur, pente + charge max | V > 1,10 × V_max = 13,2 m/s | Frein service ; >1,20 V_max → parachute | RM5 § obligatoire |
| Adhérence rail | Wet/slick rail | Suintement, condensation, humidité 95 % | μ < 0,10 mesuré sabots tests | v cap à 6 m/s | Tunnel souterrain universel |
| Perte alim. aux. | Aux power loss | Disjoncteur 400 V, défaut câblage | Tension bus < 320 V | Traction cut, freins serrés | **Perce-Neige 19/08/2008** |
| Frein parking bloqué | Parking brake stuck | Hyd leak, capteur levée HS | Pression < 80 % seuil | Refus traction, cycle E-stop | EIDE / EP0392938A1 |
| Capteur porte HS | Door sensor fault | Capteur fin de course HS, IR salissure | Discordance > 2 s | Stop next station, mode dégradé | Post-Kaprun |
| Détection fumée | Smoke / fire | Détecteur ionique/optique tunnel | Densité opt > 0,15 dB/m | E-stop, désenfumage, évacuation | **Kaprun 2000**, Carmelit 2017 |
| Aiguillage Abt mal engagé (à ajouter) | Abt switch misalignment | Sabot d'aiguille usé, ressort fatigué | Capteur position absent | Approche évitement à creep 0,3 m/s + alarme | Spécifique conception Abt |
| Inondation tunnel (à ajouter) | Tunnel flooding | Rupture conduite eau / fonte rapide | Capteur niveau bassin pied | Service suspendu | Funiculaires souterrains |
| Communication HS (à ajouter) | Comms loss | PA tunnel, GSM, intercom | Perte test cyclique 30 s | Évacuation manuelle obligatoire si autres pannes | Leçon Kaprun |
| Frein de service inopérant (à ajouter) | Service brake failure | Pression hyd, garnitures usées | Test charge échoue | Mode maintenance forcé | **Glória 2025** |

---

## 6. Réglementation française synthèse (STRMTG / RM5 v1 déc. 2018)

### 6.1 Architecture freinage exigée

Tout funiculaire doit disposer de **deux freins indépendants** —
chacun capable d'**arrêter et d'immobiliser** l'installation dans
le **cas de charge le plus défavorable** (cabine pleine descendante,
30 % pente Perce-Neige).

**Familles** :
1. **Frein de service** (machinerie, sur poulie motrice ou arbre lent)
   — pour exploitation normale.
2. **Frein de sécurité de la machinerie** — disjoncte automatiquement
   sur survitesse, perte tension, bouton AU.
3. **Frein de voie embarqué** (parachute) — sur cabine, pince le rail
   en cas de rupture câble ou survitesse forte.

### 6.2 Détecteurs obligatoires

- Rupture câble (slack switch).
- Survitesse (centrifuge mécanique + redondant capteur électrique).
- Anti-retour (le train ne doit pas reculer en sens opposé).
- Position dans la course (codeurs absolus).
- Tension câble (jauge de contrainte poulie de renvoi).
- Température bobinage moteur.
- Position aiguillage (Abt = pas mécanique mais détection passive).
- Détection fumée tunnel (post-Kaprun).

### 6.3 Veille automatique conducteur

VACMA (Veille Automatique par Contrôle du Maintien d'Appui — SNCF
norme transposable) :
- Pédale ou poignée maintenue appuyée.
- **Beep audible toutes ~58 s** si pas d'autre action.
- Conducteur doit **relâcher puis ré-appuyer en ≤ 3 s**.
- Sinon : freinage automatique.

Dans certains funiculaires (Stoos automatisé), pas de conducteur
embarqué : la veille concerne l'opérateur télécommande en gare.

### 6.4 Tests réguliers

- **Vérification freins de voie** : obligatoire **annuelle**
  (minimum), test charge réelle simulant rupture câble. **C'est lors
  de ce test que le Montmartre a perdu son culot en 2006**.
- Inspection visuelle câble : quotidienne.
- **Inspection magnétique non destructive (MFL)** : annuelle ou
  semestrielle selon usage.
- Test isolement moteurs : annuel.
- Test détection fumée : trimestriel.

---

## 7. Ce qui n'a PAS été trouvé (honnêteté)

- **Aucun rapport BEA-TT spécifique au Perce-Neige** (l'incident 2008
  n'a pas justifié d'enquête publique).
- **Aucune publication STRMTG nominative** sur appareils individuels
  Compagnie des Alpes (rapports STRMTG annuels = agrégats).
- **Pas d'historique de remplacement câble** post-1999 trouvé
  publiquement (probablement remplacement vers 2010–2014 selon cycle
  habituel 12–15 ans, mais non documenté en ligne).
- **Aucun incident Funival** documenté publiquement.
- **Aucun funiculaire à Capelinhos (Açores)** n'existe — confusion
  utilisateur à corriger.
- **Spécification exacte du frein parachute Von Roll Perce-Neige**
  (génériquement EP0392938A1 POMA — type Belleville pince/rail — mais
  fournisseur Von Roll pour ce projet, brochure non en ligne).
- **Bulletin annuel STRMTG funiculaires** (non récupéré en PDF
  exploitable via WebFetch).
- **Articles techniques OITAF en français** avec données câbles 6×26
  WS Lang spécifiques (PDF lourds non parsés).
- **Le Dauphiné Libéré archives 1993–2025** — incidents locaux
  potentiels non indexés Google.
- **PHP DEP Engineering frein chariot** (lien trouvé mais
  non consulté en profondeur — référence supplémentaire possible).

---

## 8. URLs consultées (synthèse)

### 8.1 Réglementation et institutions

- https://www.strmtg.developpement-durable.gouv.fr/funiculaires-a37.html
- https://www.strmtg.developpement-durable.gouv.fr/IMG/pdf/rm5_funiculaire_v1_dec2018.pdf
- https://www.strmtg.developpement-durable.gouv.fr/version-1-du-guide-technique-rm5-relatif-aux-a568.html
- https://www.strmtg.developpement-durable.gouv.fr/exercice-grandeur-nature-immersion-dans-une-a886.html
- https://www.bea-tt.developpement-durable.gouv.fr/
- https://www.bea-tt.developpement-durable.gouv.fr/liste-des-enquetes-selon-la-date-de-l-accident-r377.html
- https://www.cetu.developpement-durable.gouv.fr/
- https://www.securite-ferroviaire.fr/sites/default/files/reglementations/pdf/2023-03/iti-98-300-8-juillet-1998-securite-dans-les-tunnels-ferroviaires.pdf
- https://patents.google.com/patent/EP0392938A1/fr

### 8.2 Incidents documentés

- https://fr.wikipedia.org/wiki/Liste_des_principaux_accidents_de_remont%C3%A9es_m%C3%A9caniques
- https://en.wikipedia.org/wiki/Kaprun_disaster
- https://en.wikipedia.org/wiki/Ascensor_da_Gl%C3%B3ria_derailment
- https://edition.cnn.com/2025/10/21/europe/lisbon-funicular-crash-faulty-cable-intl
- https://www.france24.com/en/europe/20251020-crashed-lisbon-funicular-had-faulty-cable-official-inquiry-finds
- https://en.wikipedia.org/wiki/Carmelit
- https://en.globes.co.il/en/article-haifas-carmelit-subway-reopens-after-18-month-upgrade-1001255073
- https://www.funimag.com/photoblog/index.php/20061219/incident-technique-au-funiculaire-de-montmartre/
- https://www.lemoniteur.fr/article/funiculaire-de-montmartre-remise-en-service-d-une-deuxieme-cabine.1047279
- https://www.remontees-mecaniques.net/forums/index.php?showtopic=232 (Perce-Neige + incident 2008)
- https://www.remontees-mecaniques.net/forums/index.php?showtopic=2014 (Montmartre)
- https://www.haute-tarentaise.net/t111-tignes-grande-motte-de-la-telecabine-au-funiculaire
- https://www.haute-tarentaise.net/t190-val-d-isere-les-accidents-passes
- https://www.letemps.ch/suisse/lausanne-metro-tombe-panne-pendant-quatre-heures
- https://www.rts.ch/info/regions/vaud/2025/article/panne-du-metro-lausannois-trafic-interrompu-entre-ouchy-et-bessieres-28879030.html
- https://it.wikipedia.org/wiki/Tranvia_Sassi-Superga
- https://en.wikipedia.org/wiki/Stoosbahn
- https://en.wikipedia.org/wiki/Funival
- https://www.ville-rail-transports.com/ferroviaire/quels-controles-apres-laccident-du-funiculaire-de-lisbonne/

### 8.3 Technique câble et fatigue

- https://oitaf.org/wp-content/uploads/2023/12/525530_Book-3-1.pdf (Magnetic Rope Testing)
- https://oitaf.org/dokumente/technical-recommendations-in-effect/
- https://www.ndt.net/article/v04n08/zawada/zawada.htm
- https://www.ndt.net/article/v11n06/basak/basak.htm
- https://www.aemmeci.com/en/blog/media-article/9-rope-inspection-safety-and-the-iso4309-regulation.html
- https://www.quadco.engineering/en/know-how/an-overview-of-the-palmgren-miner-rule.htm
- https://www.sciencedirect.com/topics/engineering/palmgren-miner-rule
- https://www.sciencedirect.com/science/article/abs/pii/S1350630719307824 (fatigue grey theory)

### 8.4 Moteurs DC et thermique

- https://www.cat.com/en_US/by-industry/electric-power/Articles/White-papers/temperature-rise-and-insulation-class-relationship.html
- https://www.ecmweb.com/content/article/20899136/the-hot-issue-of-motor-temperature-ratings
- https://library.e.abb.com/public/58df388d653856c0c125795f00432d0c/DAHandbook_Section_08p11_Motor-Protection_757291_ENa.pdf
- https://www.drivesandautomation.co.uk/useful-information/nema-insulation-classes/
- https://voltage-disturbance.com/power-engineering/motor-over-temperature-protection/

### 8.5 Veille automatique / dead-man

- https://fr.wikipedia.org/wiki/Veille_automatique
- https://www.techno-science.net/definition/14796.html
- https://www.cairn.info/revue-terrains-et-travaux-2006-2-page-16.htm

### 8.6 Freinage funiculaire

- https://www.remontees-mecaniques.net/dossier/page-les-systemes-de-freinage-10.html
- https://www.remontees-mecaniques.net/forums/index.php?showtopic=6906
- https://www.axesindustries.com/details.php/id/9836/freins-de-securite-industriels-eide.html
- https://www.dep-engineering.fr/st_frein_chariot_parachute.htm
- https://www.funimag.com/photoblog/index.php/20100208/le-nouveau-funiculaire-de-bienne-evilard/142-0188/
- https://www.clearsy.com/thematiques/freinage-et-arret-automatique-de-train/

---

## 9. Recommandations pour le simulateur

### 9.1 Pannes à ajouter (priorité haute)

1. **`cable_rupture`** — frein parachute immédiat, distance d'arrêt
   < 30 m, obligatoire pour cohérence post-Glória 2025.
2. **`overspeed_runaway`** — V > 13,2 m/s déclenche frein service ;
   > 14,4 m/s → parachute. Lié à la dérive du régulateur ou pente +
   charge anormale.
3. **`fire_evac_long`** — variante longue de `fire` qui force
   évacuation tunnel pédestre (60 min sim accéléré ?).
4. **`abt_switch_alarm`** — approche évitement à 0,3 m/s avec alarme
   visuelle (Perce-Neige spécifique).

### 9.2 Calibrations à raffiner

- `tension` : nominal = 22 500 daN ; surge réaliste = +25 à +35 %
  (5 600–7 900 daN) plutôt que les 6 500 actuels (correct mais
  documenter dans le code en commentaire).
- `thermal` : seuil 105 °C correspond à classe F rise +80K ; documenter
  référence IEC 60349-2 dans le code.
- `wet_rail` : v cap 6 m/s justifié par d_freinage = v²/2μg avec
  μ=0,05 → ~37 m. Documenter formule.
- `slack` : -8 000 daN ≈ -35 % nominal, cohérent avec seuil typique
  détecteur 60 % (déclenche entre 9 000 et 13 500 daN absolus).

### 9.3 Métrologie à exposer dans le HUD

- Compteur cycles câble (Palmgren-Miner pseudo-D).
- Température bobinage des 3 moteurs (séparés).
- Pression circuit hydraulique freins.
- Niveau eau bassin pied (si on ajoute `flooding`).
- État détecteurs fumée (nominal / alarme niveau 1 / alarme niveau 2).

---

## 10. Annexe — Citations clés

> « Les funiculaires sont équipés de détecteurs d'incident (rupture
> de câble, survitesse et anti-retour) pour déclencher le freinage
> de secours du véhicule, avec une pluralité de freins permettant une
> modulation du freinage en cas d'incident. »
> — Brevet EP0392938A1, POMA SA, 1989.

> « The cable involved in the derailment did not comply with the
> specifications in force at the CCFL to be used for the Gloria tram
> and no testing or oversight by Carris was done on the cable prior
> to its installation. »
> — GPIAAF interim report, oct. 2025 (cité par CNN).

> « After the cable broke, safety systems cut power to the funicular,
> meaning that the pneumatic brake no longer worked and the manual
> brake wasn't strong enough to stop the car hurtling down the hill. »
> — NBC News, 2025 sur Glória.

> « Une panne générale a privé d'électricité la partie haute de la
> station de Tignes Val Claret, et particulièrement le secteur du
> funiculaire vers 16h15 le 19 août 2008. Lors du rétablissement, le
> funiculaire d'accès au glacier de la Grande Motte n'a pas redémarré
> et les passagers, bloqués dans les deux cabines à l'intérieur du
> tunnel, ont dû être évacués à pied. »
> — Forum haute-tarentaise.net (résumé presse 2008).

> « In addition to the machinery brakes, funicular vehicles have
> their own braking system that acts on the rails when needed, for
> example following rupture of the traction cable (these are called
> onboard brakes or track brakes). »
> — STRMTG, Guide technique RM5 v1 déc. 2018.

> « The structural flaws of the funicular trains included a lack of
> safety mechanisms, fire extinguishers in sealed attendants'
> compartments out of passengers' reach, no smoke detectors, and no
> cellphone reception within the tunnels. »
> — Wikipedia, Kaprun disaster.

---

*Fin du document — research_failures.md*
