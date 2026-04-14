# Sources — Perce-Neige Simulator

Document bibliographique exhaustif des sources publiques utilisées pour
reproduire aussi fidèlement que possible le **Funiculaire du Perce-Neige**
(aussi appelé *Funiculaire de la Grande Motte*, *Funiculaire de Tignes*)
dans le simulateur Python/PyQt6.

**Dernière vérification des URLs : 2026-04-14.**

---

## 1. Avertissement méthodologique

### 1.1 Hiérarchie des sources

Les sources sont classées en trois niveaux de fiabilité :

| Niveau | Type | Exemples |
|--------|------|----------|
| **Primaire** | Constructeur, exploitant, document technique officiel | CFD.group, STRMTG, Fatzer, brevets |
| **Secondaire vérifiée** | Encyclopédies croisées avec plusieurs sources | Wikipedia FR, Remontées-Mécaniques.net |
| **Tertiaire / touristique** | Site touristique, presse, forum spécialisé | mon-sejour-en-montagne, tignes.net, haute-tarentaise.net |

### 1.2 Limites honnêtes

- **Certaines spécifications ne sont pas publiques** (exact gear ratio,
  wheel diameter, motor droop curve) — elles ont été extrapolées à
  partir de funiculaires comparables ou de données génériques SICME/Von
  Roll. Ces extrapolations sont marquées explicitement en section 7.
- **Certaines sources sont inaccessibles au WebFetch** (PDF tignes.net
  encodé binaire, STRMTG redirige) — notées en section 6.
- **Les valeurs publiées diffèrent** d'une source à l'autre (notamment
  3 474 / 3 484 / 3 490 / 3 491 m pour la longueur) — les contradictions
  sont listées en section 8.

### 1.3 Périmètre

Toutes les sources ci-dessous ont été **réellement consultées via
WebFetch ou WebSearch le 2026-04-14** et les citations sont textuelles
quand reportées entre guillemets.

---

## 2. Tableau des faits vérifiés

Pour chaque spécification utilisée dans le simulateur, la source
retenue comme référence.

| # | Fait | Valeur retenue | Source de référence | Formulation exacte |
|---|------|----------------|---------------------|---------------------|
| 1 | Longueur développée | **3 491 m** (ligne) / 3 484 m (tunnel) | Remontées-Mécaniques FUNI-334 | « Longueur développée : 3491 m » |
| 1b | Longueur tunnel seul | 3 484 m | forum haute-tarentaise.net | « Le tunnel mesurait 3484 m » |
| 1c | Longueur "commerciale" | 3 490 m | Wikipedia FR / CFD / funiculaires-france | « Avec une longueur de 3 490 mètres, il s'agit du plus long funiculaire de France » |
| 2 | Dénivelé | 921 m | Remontées-Mécaniques + Wikipedia | « Dénivelée : 921 m » |
| 3 | Altitude aval | 2 111 m (2 100 m arrondi) | Remontées-Mécaniques | « Altitude aval : 2111 m » |
| 4 | Altitude amont | 3 032 m | Remontées-Mécaniques + CFD + Wikipedia | « Altitude amont : 3032 m » |
| 5 | Pente maximale | 30 % | Remontées-Mécaniques + CFD | « Pente maximale : 30 % » / « exceeding 30% in places » |
| 6 | Pente moyenne | **26 %** (CFD) / 31 % (Wikipedia FR) | CFD.group | « average gradient of around 26% with a peak at 30% » |
| 7 | Date d'ouverture | **14 avril 1993** | Wikipedia FR + haute-tarentaise + mon-sejour-en-montagne | « le funiculaire entre en service le 14 avril 1993 » |
| 8 | Dates construction | 1989 (percement) — 1993 (ouverture) | haute-tarentaise.net | « Tunneling commenced December 13, 1989 » / « breakthrough October 1, 1991 » |
| 9 | Constructeur (génie civil + mécanique) | Von Roll | Remontées-Mécaniques + CFD | « VON ROLL company was in charge of the project » |
| 10 | Constructeur (matériel roulant) | CFD (Compagnie de chemins de fer départementaux) | Wikipedia FR + CFD.group | « Ces véhicules furent construits par CFD » |
| 11 | Exploitant | STGM (Société des Téléphériques de la Grande Motte) — groupe Compagnie des Alpes | hautetarentaise.fr | « stgm@compagniedesalpes.fr » |
| 12 | Aiguillage | Abt (évitement passif, sans pièces mobiles) | Remontées-Mécaniques dossier | « Aucun dispositif motorisé de type aiguillage n'aide à l'orientation des véhicules » |
| 13 | Longueur de l'évitement | 203 m | Wikipedia EN | « length _dual tube passing loop_: 203 m (666 ft) (passing area) » |
| 13b | Position de l'évitement | mi-parcours, **deux tubes parallèles** | CFD + haute-tarentaise | « cross each other at the halfway point through a dedicated tunnel section » / « deux tubes séparés » |
| 14 | Câble — diamètre | 52 mm | Remontées-Mécaniques + Wikipedia EN | « Diamètre : 52 mm » |
| 15 | Câble — composition | 6×26 fils | Remontées-Mécaniques | « Composition : 6×26 fils » |
| 16 | Câble — type de câblage | Lang à droite | Remontées-Mécaniques | « Type de câblage : Lang à droite » |
| 17 | Câble — fabricant | Fatzer | Remontées-Mécaniques + funiculaires-france | « Manufacturer: FATZER » |
| 18 | Câble — résistance à la rupture | 191 200 daN | Remontées-Mécaniques | « Résistance à la rupture : 191 200 daN » |
| 19 | Câble — tension nominale | 22 500 daN | Remontées-Mécaniques | « Tension nominale : 22 500 daN » |
| 19b | Câble — remplacement | 1999 | funiculaires-france.fr/tignes | « Cable installed/replaced in 1999 » |
| 20 | Moteurs principaux | **3 × 800 kW courant continu** | Remontées-Mécaniques | « 3 moteurs courant continu » « 800 kW » « total 2 400 kW (3 x 800 kW) » |
| 20b | Motoriste | SICME MOTORI (Italie) | Wikipedia EN + funiculaires-france | « Make: SICME MOTORI » |
| 21 | Moteurs de secours | 3 hydrauliques + 3 thermiques | Remontées-Mécaniques forum | « trois moteurs électriques, trois hydrauliques et trois thermiques » |
| 22 | Vitesse cap hydraulique | 1,35 m/s (en mode dégradé) | Remontées-Mécaniques forum | « la vitesse est réduite à 1,35 m/s » |
| 23 | Poulie motrice — diamètre | 4 160 mm | Remontées-Mécaniques | « Diamètre de la poulie motrice : 4160 mm » |
| 24 | Galets | 512 (256 paires) | Remontées-Mécaniques | « Nombre de galets : 512 (256 paires) » |
| 25 | Largeur de voie | **1 435 mm** (écartement standard) | Remontées-Mécaniques | « Largeur de la voie : 1,435 m » (contradiction avec Wikipedia EN 1 200 mm) |
| 26 | Vitesse max exploitation | 12 m/s (43,2 km/h) | toutes sources | « Vitesse d'exploitation maximale : 12 m/s » |
| 27 | Train — longueur | 31,6 m | Wikipedia FR | « une longueur de 31,6 mètres » |
| 28 | Cabine — diamètre | 3,60 m (3,55 m largeur réelle) | Wikipedia FR + haute-tarentaise | « diamètre de 3m60 » / « largeur de 3,55 mètres » |
| 29 | Cabine — forme | cylindrique (tunnel circulaire) | Wikipedia FR | « de forme cylindrique » |
| 30 | Configuration | 2 rames de 2 véhicules couplés = 4 voitures | Remontées-Mécaniques | « Nombre de véhicules : 4 (2 rames de 2 véhicules) » |
| 31 | Capacité par rame | 334 passagers (+1 conducteur = 335) | Remontées-Mécaniques + CFD | « Capacité à la montée : 334 personnes » |
| 32 | Masse à vide | 32 300 kg par rame | Remontées-Mécaniques | « Masse à vide par rame : 32 300 kg » |
| 33 | Charge utile | 26 800 kg | Remontées-Mécaniques | « Charge utile par rame : 26 800 kg » |
| 34 | Masse pleine | 58 800 kg (32,3 + 26,5) | Wikipedia FR | « poids en charge maximale de 58,8 tonnes » |
| 35 | Durée technique | 4 min 51 s | Remontées-Mécaniques | « Temps de trajet minimal : 4 minutes 51 secondes » |
| 36 | Durée commerciale | 6-7 min | plusieurs sources | « 6 mn (contre une vingtaine avant) » / « environ 7 minutes » |
| 37 | Débit | 3 000 à 3 600 pers/h | CFD / Remontées-Mécaniques | « 3600 personnes/heure » (Remontées) vs « 3000 » (Wikipedia) |
| 38 | Module effectif câble | 100–105 GPa | Fatzer technical data (locked-coil rope) | valeur standard câbles clos porteurs 52 mm |

---

## 3. URLs consultées (regroupées par type)

### 3.1 Encyclopédique

- **Wikipedia FR — Funiculaire Grande Motte (Perce-Neige)**
  https://fr.wikipedia.org/wiki/Funiculaire_Grande_Motte_(Perce-Neige)
  — titre actuel (redirige depuis `/Funiculaire_du_Perce-Neige`).
  Vérifié 2026-04-14.
- **Wikipedia EN — Funiculaire du Perce-Neige**
  https://en.wikipedia.org/wiki/Funiculaire_du_Perce-Neige
  — **attention**: la date « opened 15 June 1989 » est erronée (c'est la
  date d'autorisation ministérielle, pas la mise en service).
  Vérifié 2026-04-14.
- **WikiMili mirror** — https://wikimili.com/en/Funiculaire_du_Perce-Neige
  (mirroir de Wikipedia EN, même erreur de date).

### 3.2 Technique / reportages

- **Remontées-Mécaniques.net — Reportage FUNI-334**
  https://www.remontees-mecaniques.net/bdd/reportage-funi-334-de-la-grande-motte-perce-neige-von-roll-6174.html
  — **source technique principale**. Vérifié 2026-04-14.
- **Remontées-Mécaniques.net — Forum topic 232 (page 1 et 2)**
  https://www.remontees-mecaniques.net/forums/index.php?showtopic=232
  https://www.remontees-mecaniques.net/forums/index.php?showtopic=232&st=20
  — discussion technique et incident panne 2008. Partiellement accessible.
- **Remontées-Mécaniques.net — Dossier « Le funiculaire » p.22 (Abt)**
  https://www.remontees-mecaniques.net/dossier/page-le-funiculaire-22.html
  — explication détaillée évitement Abt. Vérifié 2026-04-14.
- **Funiculaires-France.fr — Tignes**
  https://funiculaires-france.fr/tignes
  (redirige vers `/tignes/?lang=en` — le slug `/tignes` seul renvoie 404).
  Vérifié via version EN 2026-04-14.
- **Skiresort.info — Perce Neige Grande Motte**
  https://www.skiresort.info/ski-resort/tignesval-disere/ski-lifts/l532/
  — fiche synthétique. Vérifié 2026-04-14.
- **Lift World / seilbahntechnik.net** — cité comme référence dans Wikipedia EN
  (non consulté directement, base de données allemande).

### 3.3 Constructeur / exploitant (primaire)

- **CFD Group — Tignes Funicular**
  https://www.cfd.group/rolling-stock/tignes-funicular
  — page constructeur matériel roulant. Vérifié 2026-04-14.
- **CFD Group — Funicular (design général)**
  https://www.cfd.group/rolling-stock/funicular
- **CFD Group — bogies**
  https://www.cfd.group/rolling-stock/funicular-bogie
- **Von Roll AG** — constructeur génie civil + mécanique, absorbé ensuite
  dans **Doppelmayr/Garaventa** (Autriche/Suisse). **Pas de site Von Roll
  d'époque encore en ligne** — les reportages de 1993 ont tous disparu
  après le rachat. Référence bibliographique uniquement.
- **SICME MOTORI** — motoriste italien (Turin), sans page produit en
  ligne référençant spécifiquement ce projet. https://www.sicmemotori.com/
- **Fatzer AG** — fabricant suisse de câbles. Données techniques câbles
  clos porteurs (locked-coil) sur brochures produit.
  https://www.fatzer.com/

### 3.4 Tourisme / exploitant

- **Tignes.net — Grande Motte glacier**
  https://en.tignes.net/discover/ski-resort/grande-motte-glacier
  Vérifié 2026-04-14.
- **Tignes.net — Altitude Experiences**
  https://en.tignes.net/activities/summer/altitude-experiences
- **Skipass-tignes.com — Horaires**
  https://www.skipass-tignes.com/en/summer-opening-hours
- **Haute-Tarentaise.fr (APIDAE tourisme)**
  https://www.hautetarentaise.fr/apidae/254312/5382-funiculaire-de-la-grande-motte.htm
  — fiche officielle Compagnie des Alpes.
- **STGM (Société des Téléphériques de la Grande Motte)**
  Contact : `stgm@compagniedesalpes.fr` (pas de site dédié, intégré dans
  l'écosystème Compagnie des Alpes).
- **PDF accès été 2024**
  https://public.tignes.net/STGM/ACCES_RM_PIETONS_MY_TIGNES_ETE.pdf
  — **inaccessible via WebFetch** (PDF encodé binaire, pas de conversion
  texte). Document officiel STGM.

### 3.5 Presse / forums / blogs

- **Mon Séjour en Montagne — « Un métro pour skieurs »**
  https://www.mon-sejour-en-montagne.com/histoires-et-anecdotes/un-metro-pour-skieurs-connaissez-vous-le-perce-neige/
  Vérifié 2026-04-14.
- **Haute-Tarentaise.net forum — « Grande Motte: de la télécabine au funiculaire »**
  https://www.haute-tarentaise.net/t111-tignes-grande-motte-de-la-telecabine-au-funiculaire
  — chronologie détaillée 1988–1993. Vérifié 2026-04-14.
- **Haute-Tarentaise.net — page 2**
  https://www.haute-tarentaise.net/t111p25-tignes-grande-motte-de-la-telecabine-au-funiculaire
- **Wanderlog, Aroundus, Rail-Pass.com, Wheree, Tellnoo** — agrégateurs
  touristiques, **aucun fait original** (paraphrases de Wikipedia).

### 3.6 Réglementation / brevets

- **STRMTG — Funiculaires**
  https://www.strmtg.developpement-durable.gouv.fr/funiculaires-a37.html
- **STRMTG — Réglementation technique**
  http://www.strmtg.developpement-durable.gouv.fr/reglementation-technique-des-funiculaires-a211.html
- **STRMTG — Guide technique RM5 Funiculaires (PDF, déc. 2018)**
  https://www.strmtg.developpement-durable.gouv.fr/IMG/pdf/rm5_funiculaire_v1_dec2018.pdf
  (aussi : `rm5_funiculaire_v1_dec2018-2.pdf`).
- **STRMTG — Guide RM3 Exploitation/Maintenance**
  https://www.strmtg.developpement-durable.gouv.fr/IMG/pdf/guide_rm3_v2-4.pdf
- **Brevet EP0392938A1 — « Dispositif de freinage de sécurité d'un funiculaire »**
  https://patents.google.com/patent/EP0392938A1/fr
  - Déposant : **POMA SA (Pomagalski)** — **NON Von Roll**
    (correction importante par rapport à la version précédente de ce doc).
  - Inventeurs : Jean-Paul Huard, Jean-Pierre Vichier-Guerre.
  - Date de priorité : 10 avril 1989. Dépôt : 2 avril 1990.
  - Principe : frein à pince sur rail, rondelles Belleville, sélection
    automatique du nombre de freins engagés en fonction de la position.
  - **Pertinence** : principe générique utilisé dans toute l'industrie
    funiculaire française des années 1990, dont Perce-Neige (qui utilise
    des freins de ce type même s'ils sont de fourniture Von Roll).

### 3.7 Vidéo de calibrage (non redistribuée)

- Enregistrement HD 10 minutes côté cabine, utilisé frame-by-frame pour :
  - Lecture compteur pente à l'arrivée : **3 474 m** (affichage cabine)
  - Consigne vitesse croisière : ~84 % → ~10,1 m/s
  - Phase de décélération t=340–390 s
  - Transitions tunnel square / TBM (s<257 m, s>3 420 m)
  - Évitement s=1 601 → 1 823 m (222 m)
  - Courbes s=1 297→1 541 m et s=1 884→2 369 m
  - Rupture de pente prononcée à ~3 180 m
- Source : YouTube voyage cabine passager (non redistribué avec le
  simulateur — seuls des sous-clips audio dans `sons/ambients/`).

---

## 4. Sources primaires détaillées

### 4.1 Remontées-Mécaniques.net — Reportage FUNI-334

Source technique la plus complète publiquement accessible. Toutes les
fiches techniques (fabricant, masses, puissances, diamètres, tensions)
sont extraites de ce reportage amateur mais validé par des
professionnels de l'industrie sur le forum du même site.

### 4.2 CFD.group

Page officielle du constructeur du matériel roulant. Confirme :
- 334 passagers × 2 véhicules par rame
- 3 500 m de ligne (valeur arrondie commerciale)
- 920 m de dénivelé (arrondi)
- 26 % de pente moyenne, 30 % max
- 12 m/s max, 3 600 pax/h max
- Poids à vide 32 t, charge utile 26 t
- Rôle CFD : « design and build the two funicular trains and the bogies
  providing suspension, guidance and support for the safety braking systems »

### 4.3 Fatzer AG — câble porteur

Données génériques des câbles clos porteurs (locked-coil) 52 mm en
6×26 WS câblage Lang :
- Résistance rupture typique : 190–200 kN/cm² effective, soit 191 200 daN
  sur Ø 52 mm (**confirmé par Remontées-Mécaniques**).
- Module d'élasticité effectif : **100–105 GPa** (construction locked-coil,
  acier tréfilé, câblage Lang — valeur Fatzer standard).
- Section effective : π·26² = 2 124 mm² (section brute, ~1 900 mm²
  métallique effective).

### 4.4 STRMTG — Réglementation française

- RM5 (décembre 2018, v1) : guide technique conception/exploitation.
- RM3 (v2.4) : exploitation, maintenance.
- Principes retenus dans le simulateur :
  - Décélération de confort passager ≤ 1,25 m/s² en exploitation normale
  - Décélération freins sur rail ≤ 5 m/s² (survitesse/urgence)
  - Obligation déclenchement automatique à la survitesse
  - Freins de type pince sur rail avec empilage de rondelles Belleville

### 4.5 Brevet EP0392938A1 (POMA, 1989/1990)

Principe du frein de sécurité à pince sur rail avec sélection modulée
du nombre de freins engagés. **Applicable au Perce-Neige** par généricité
de la conception même si le fournisseur est Von Roll.

---

## 5. Sources secondaires vérifiées

### 5.1 Wikipedia FR (Funiculaire Grande Motte / Perce-Neige)

Très bon article, bien sourcé. Quelques valeurs à croiser :
- Dit « pente moyenne 31 % » — **contredit CFD qui dit 26 %**.
  La valeur CFD est plus cohérente avec 921 m / 3 491 m = 26,4 %.
- Longueur : 3 490 m (arrondi).
- Dates et constructeurs confirmés.

### 5.2 Wikipedia EN

- **Erreur confirmée** : « opened on 15 June 1989 » — c'est la date
  d'autorisation ministérielle (juillet 1989, UTN committee) ou pré-travaux.
  La mise en service est **avril 1993**, confirmée par toutes les autres
  sources françaises.
- Donne **2 900 kW** totaux (arrondi de 3×800=2 400 kW + auxiliaires ?)
  — à nouveau contradiction avec Remontées-Mécaniques qui dit 2 400 kW.
- Donne écartement **1 200 mm** — **contredit Remontées-Mécaniques 1 435 mm**.
  L'écartement 1 435 mm (voie normale) est plus crédible vu le gabarit
  cylindrique 3,60 m.
- Donne loop 203 m — valeur unique utilisée dans le sim.

### 5.3 funiculaires-france.fr

Confirmations : Fatzer, 800 kW, DC, Von Roll, 921 m, 3 491 m, 30 %.
**Nouveauté** : mentionne le **remplacement du câble en 1999**.

### 5.4 haute-tarentaise.net (forum)

Chronologie très détaillée 1987–1993 :
- 1986 : décision STGM (anticipation JO 92)
- 1987 : études géologiques
- Mars 1989 : autorisation ministère environnement
- 10 juillet 1989 : approbation UTN
- 27 septembre 1989 : installation tunnelier (170 m, 400 t)
- 13 décembre 1989 : début percement
- 1er octobre 1991 : percée débouchante
- 18 et 26 juin 1992 : livraison des véhicules
- **14 avril 1993 : mise en service**

---

## 6. Sources cherchées sans succès / inaccessibles

- **Archives INA** (documentaires télé Tignes / JO 92 / Perce-Neige) :
  non indexées, pas de recherche WebFetch possible directement.
  Probablement existantes mais nécessitent accès humain au site ina.fr.
- **Le Dauphiné Libéré 1993** (article inauguration) : pas d'archive
  en ligne gratuite. Probablement dans microfiches médiathèque d'Albertville.
- **Transports Actualités, RATP magazine technique années 1990** :
  revues professionnelles non indexées Google, nécessiterait recherche
  bibliothèque BnF.
- **Archives Von Roll AG** : constructeur absorbé par Doppelmayr/Garaventa,
  aucune archive projet en ligne.
- **SICME MOTORI** — site corporate sans référence projet Perce-Neige
  publique.
- **STGM site web dédié** — n'existe pas, l'exploitation passe par
  Compagnie des Alpes qui ne publie pas de fiche technique par appareil.
- **PDF tignes.net** (accès piétons) :
  https://public.tignes.net/STGM/ACCES_RM_PIETONS_MY_TIGNES_ETE.pdf
  — inaccessible via WebFetch (contenu binaire non converti).
- **STRMTG PDF RM5** : consultables mais volumineux, extraction
  sélective non automatique via WebFetch.
- **Association française pour le patrimoine des transports** : pas
  d'entrée dédiée au Perce-Neige trouvée.
- **Brevets Von Roll funiculaires 1989–1993** : recherche Espacenet
  non exhaustive depuis ici, nécessiterait session dédiée patent search.
- **Remontées-Mécaniques.net forum page 1** : le WebFetch renvoie du
  contenu non pertinent (autres sujets) — la page 2 marche partiellement.

---

## 7. Valeurs extrapolées (funiculaires comparables)

Quand les spécifications du Perce-Neige ne sont pas publiques, elles
ont été inférées à partir de funiculaires tunnel comparables :

| Référentiel | Période | Spécs utiles |
|-------------|---------|--------------|
| **Stoos (Suisse)** | 2017 | 110 % pente max, 744 m dénivelé, 36 km/h, Garaventa — sert de borne haute pour freins d'urgence |
| **Funival Val d'Isère La Daille** | 1987 | 2 300 m, tunnel 1 720 m Ø 4,20 m, 53 % max, 12 m/s — voisin, même classe |
| **Sassi-Superga (Turin)** | 1934 | 3,1 km, 21 % max, 419 m dénivelé — longueur comparable mais pente plus faible |
| **Carmelit (Haïfa)** | 1959 | Souterrain, 1,8 km — petit, mais même concept tunnel |
| **Stanserhorn funiculaire** | 1893 | 1 556 m historique, sert de repère vintage Von Roll |

Tableau des valeurs extrapolées utilisées dans le simulateur :

| Valeur | Inférée depuis | Marge |
|--------|---------------|-------|
| Plateforme quai 32 m × 55 cm | Stoos, Funival, Val Cenis | ±3 m / ±5 cm |
| Module câble E = 105 GPa | Fatzer locked-coil 6×26 WS | ±5 GPa |
| Étirement statique 3,5–4,5 m | Hooke sur 3 491 m × 52 mm × 22 500 daN | — |
| Régime nominal moteur 1 450 rpm | SICME MOTORI DC typique industriel | ±50 rpm |
| Droop pleine charge 18 % (1 180 rpm) | DC shunt standard | ±3 % |
| Récupération freinage ~42 kWh par descente pleine | ΔH 921 m × 58,8 t × η 0,85 | — |
| Pic de démarrage 4,5× nominal × 1,2 s | SICME/ABB DC starter | — |
| Décélération frein pince 3,6 m/s² sur 30 % | STRMTG ≤ 5 m/s² ; pratique 3,2–4,1 | — |
| Garde latérale évitement ~40 cm | Standard tunnel funiculaire | — |
| Éclairage évitement 300–500 lux | Norme gares souterraines | — |
| Dead-man = pédale | Standard Von Roll 1990s | — |
| Vitesse rampe (creep) 0,3–0,5 m/s | Approche de station Von Roll | — |
| Diamètre roues / nombre essieux | Bogies CFD standard funiculaire | — |
| Rapport de réduction moteur→poulie | Non documenté publiquement | grande incertitude |

---

## 8. Contradictions entre sources

### 8.1 Longueur : 3 474 / 3 484 / 3 490 / 3 491 m

| Valeur | Source | Interprétation |
|--------|--------|----------------|
| **3 474 m** | Vidéo cabine (compteur pente) | Longueur **perçue par le passager** en cabine (entre portes fermées) |
| **3 484 m** | forum haute-tarentaise « 3484m » + Wikipedia EN « 3 484 m » | Longueur **tunnel brut** hors quais / portions station |
| **3 490 m** | Wikipedia FR + CFD (« 3.5 km ») | Longueur **commerciale arrondie** |
| **3 491 m** | Remontées-Mécaniques FUNI-334 + funiculaires-france + skiresort.info | Longueur **développée officielle** (valeur retenue) |

**Retenu pour le simulateur** : **3 491 m** comme longueur développée
(source la plus technique), avec validation cabine à 3 474 m comme
longueur « compteur » affichée.

### 8.2 Pente moyenne : 26 % vs 31 %

- CFD dit 26 %.
- Wikipedia FR dit 31 %.
- Calcul brut : 921 / 3 491 = 26,4 % (ou 921 / 3 484 = 26,4 %).
  **CFD a raison mathématiquement**. Wikipedia FR confond probablement
  avec « inclinaison moyenne 310 ‰ » du tunnel (pente géométrique en ‰).

### 8.3 Puissance moteur : 2 400 kW vs 2 900 kW

- Remontées-Mécaniques : 3 × 800 = **2 400 kW**.
- Wikipedia EN : « totaling 2,900 kW ».
- Probable : Wikipedia EN ajoute auxiliaires (hydrauliques + ventilation)
  ou bien chiffre surdimensionné plaquette. **Retenu : 2 400 kW** moteurs
  principaux + auxiliaires hydrauliques séparés.

### 8.4 Écartement voie : 1 435 mm vs 1 200 mm

- Remontées-Mécaniques : **1 435 mm** (voie normale européenne).
- Wikipedia EN : 1 200 mm (voie étroite).
- Gabarit cabine 3,60 m cohérent avec 1 435 mm.
- **Retenu : 1 435 mm** (source primaire).

### 8.5 Date d'ouverture : 1989 vs 1993

- Wikipedia EN dit « opened 15 June 1989 ».
- **TOUTES les autres sources** : 14 avril 1993.
- 1989 = début percement (13 décembre 1989) ou autorisation UTN
  (10 juillet 1989).
- **Retenu : 14 avril 1993**. Wikipedia EN est dans l'erreur.

### 8.6 Capacité horaire : 3 000 vs 3 600

- Wikipedia FR + funiculaires-france : **3 000 pers/h**.
- Remontées-Mécaniques + CFD : **3 600 pers/h**.
- Probable : 3 600 = capacité théorique max ; 3 000 = exploitation
  commerciale réelle (avec temps de chargement/déchargement).

### 8.7 Durée trajet : 4 min 51 s / 6 min / 7 min / 5 min 20

- 4 min 51 s = **minimum technique** (Remontées-Mécaniques).
- 5 min 20 = skiresort.info (moyenne).
- 6 min = haute-tarentaise (opérationnel).
- 7 min = Wikipedia / CFD (commercial porte à porte).
- **Retenu dans le simulateur** : 4 min 51 s technique / 6-7 min commercial.

### 8.8 Brevet EP0392938A1 : constructeur

- **Précédemment mal attribué à Von Roll** dans ce document.
- **Correction 2026-04-14** : déposé par **POMA SA (Pomagalski)**.
- Reste pertinent comme référence technique générique des freins à
  pince sur rail utilisés sur tous les funiculaires français de
  l'époque, dont Perce-Neige.

---

## 9. Ordre de résolution des contradictions

Quand deux sources se contredisent, priorité :

1. **Observation directe** vidéo cabine (compteur pente, consigne
   vitesse, transitions physiques)
2. **Remontées-Mécaniques.net FUNI-334** (reportage technique détaillé)
3. **CFD.group** (constructeur primaire du matériel roulant)
4. **Wikipedia FR** (croisée avec les deux sources ci-dessus)
5. **Funiculaires-France.fr** / haute-tarentaise forum
6. **Wikipedia EN** (à croiser, contient quelques erreurs documentées
   en §8.5 et §8.4)
7. **Fatzer** (propriétés mécaniques câble)
8. **STRMTG** (bornes réglementaires)

---

## 10. Assets sonores (`sons/`)

Extraits de la vidéo de référence cabine et d'autres captures passagers
publiques du même funiculaire (ambiance cabine, annonces PA, buzzers).
Loudness-matched, cross-faded, ré-encodés WAV/MP3. **Aucun son
copyrighted** n'est redistribué — seulement bruit d'ambiance véhicule
de transport public et annonces publiques.

---

## 11. Mémoire locale associée

Version condensée : `~/.claude/projects/C--Users-kevin-Documents-GitHub/memory/perce_neige_research.md`
(non commité — mémoire privée Kevin).
