# Archive locale des sources — Perce-Neige Simulator

Snapshots HTML des pages web utilisées pour calibrer le simulateur.
Téléchargés le **2026-04-14** via `curl` depuis `C:\Users\kevin\Documents\GitHub\perce-neige-sim`.

Le but : avoir une copie locale stable même si les pages originales disparaissent ou sont modifiées. Chaque ligne donne l'URL d'origine, le fichier local, et ce qu'on tire de la source.

---

## 1. Filière constructeur — Von Roll → Doppelmayr/Garaventa

Von Roll Seilbahnen AG (CH) a été racheté par **Doppelmayr Holding** en **1996**, puis fusionné avec **Garaventa** (CH) en **2002** pour former le **Doppelmayr/Garaventa Group**. **Il n'existe plus de site Von Roll Seilbahnen.** Le support technique post-1996 du Perce-Neige relève de Doppelmayr/Garaventa.

| Fichier local | URL d'origine | Contenu utile |
|---|---|---|
| `wikipedia_von_roll_holding.html` | https://en.wikipedia.org/wiki/Von_Roll_Holding | Historique complet Von Roll, acquisitions, filières ferroviaire/funiculaire |
| `wikipedia_doppelmayr_garaventa.html` | https://en.wikipedia.org/wiki/Doppelmayr/Garaventa_Group | Absorption Von Roll 1996, fusion Garaventa 2002, portfolio actuel |
| `doppelmayr_home.html` | https://www.doppelmayr.com/en/ | Page d'accueil actuelle (constructeur actif post-2002) |
| `doppelmayr_products_funicular.html` | https://www.doppelmayr.com/en/products/funiculars/ | Gamme funiculaire actuelle (Stoosbahn 2017 référence technologique) |

## 2. CFD (Compagnie de chemins de fer départementaux) — matériel roulant

Constructeur des deux rames + bogies + systèmes de freinage de sécurité du Perce-Neige.

| Fichier local | URL d'origine | Contenu utile |
|---|---|---|
| `cfd_machines_tignes_funicular.html` | https://www.cfd.group/machines/tignes-funicular-perce-neige | Fiche projet Tignes : 334 pax × 2, 3 500 m, 920 m dénivelé, 26 %/30 %, 12 m/s, 3 600 pax/h |
| `cfd_rolling_tignes_funicular.html` | https://www.cfd.group/rolling-stock/tignes-funicular | Fiche véhicule Tignes : 32 t vide, 26 t utile |
| `cfd_rolling_funicular.html` | https://www.cfd.group/rolling-stock/funicular | Catégorie générique « funicular » CFD |
| `cfd_rolling_funicular_bogie.html` | https://www.cfd.group/rolling-stock/funicular-bogie | Bogies : suspension, guidage, parachute |
| `cfd_rolling_bourg_saint_maurice.html` | https://www.cfd.group/rolling-stock/bourg-saint-maurice-funicular | Arc-en-Ciel (1989) — même constructeur, comparaison directe |
| `wikipedia_cfd_fr.html` | https://fr.wikipedia.org/wiki/Compagnie_de_chemins_de_fer_d%C3%A9partementaux | Histoire CFD, filières ferroviaires et funiculaires |

## 3. Remontées-Mécaniques.net — reportage FUNI-334

Source technique amateur la plus complète publiquement accessible. Toutes les fiches techniques (masses, puissances, diamètres, tensions, Fatzer 52 mm) de ce document ont été validées sur le forum par des pros de l'industrie.

| Fichier local | URL d'origine | Contenu utile |
|---|---|---|
| `remontees_mecaniques_funi334.html` | https://www.remontees-mecaniques.net/bdd/reportage-funi-334-de-la-grande-motte-perce-neige-von-roll-6174.html | Tous les chiffres techniques Perce-Neige : Fatzer 52 mm, tension 22 500 daN, rupture 191 200 daN, 3 × 800 kW DC, 58,8 t max, 3 491 m, 921 m, 30 % max |

## 4. Câble — Fatzer AG (Suisse)

Fournisseur câble locked-coil 52 mm du Perce-Neige. Fatzer est filiale du **Brugg Group** depuis 2006.

| Fichier local | URL d'origine | Contenu utile |
|---|---|---|
| `fatzer_home.html` | https://www.fatzer.com/ | Page accueil Fatzer AG |
| `fatzer_wire_ropes.html` | https://www.fatzer.com/en/products/wire-ropes/ | Gamme câbles acier, locked-coil et câblage Lang |
| `wikipedia_fatzer_de.html` | https://de.wikipedia.org/wiki/Fatzer_AG | Histoire Fatzer, production 1836→, rachat Brugg |
| `brugg_lifting_home.html` | https://www.brugglifting.com/en | Brugg Lifting (groupe mère actuel) |

## 5. STRMTG — Réglementation française

Service Technique des Remontées Mécaniques et des Transports Guidés. Régulateur qui édicte les guides RM (Remontées Mécaniques) et contrôle les appareils en France.

| Fichier local | URL d'origine | Contenu utile |
|---|---|---|
| `strmtg_home.html` | https://www.strmtg.developpement-durable.gouv.fr/ | Portail STRMTG |
| `strmtg_guides_techniques.html` | https://www.strmtg.developpement-durable.gouv.fr/guides-techniques-r44.html | Index guides techniques (RM1…RM7), permet de retrouver RM5 « Règles techniques de sécurité des téléphériques et funiculaires » |

## 6. Wikipedia — Perce-Neige

| Fichier local | URL d'origine | Contenu utile |
|---|---|---|
| `wikipedia_perce_neige_fr.html` | https://fr.wikipedia.org/wiki/Funiculaire_de_Tignes | Article FR : inauguration 14 avril 1993, 334 pax, 3 491 m, 921 m, tunnel 100 %, 12 m/s, 334 pax |
| `wikipedia_perce_neige_en.html` | https://en.wikipedia.org/wiki/Perce-Neige_funicular | Article EN : données partiellement contradictoires (1989 / 2 900 kW) — 1993 / 2 400 kW est la version recoupée |

---

## Utilisation

Ces fichiers sont là pour :
1. **Traçabilité** : chaque valeur du sim peut être retrouvée à la source, même si la page est modifiée ou supprimée en ligne.
2. **Guide LaTeX théorique** : les références `\href{}` du guide pointent vers les URL d'origine, ces fichiers servent d'archive de secours.
3. **Audits futurs** : re-vérifier une valeur ne nécessite pas de refaire la recherche web.

Taille totale : ~1.8 Mo (19 fichiers HTML).

Téléchargés avec :
```bash
curl -sS -L -A "Mozilla/5.0" -o "<fichier>.html" "<URL>"
```
