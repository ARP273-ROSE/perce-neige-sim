# Audit physique — pannes & types d'arrêts (2026-07-23)

Déclencheur : retours d'essai terrain — « dans la panne de frein de
service, le funi continue le trajet à fond avec 0 kW et le frein à moitié
serré » ; « une panne qui impose 6 m/s : le funi réduit sa vitesse quasi
instantanément, c'est pas possible ».

Banc : `tests/bench_pannes.py` (chaque panne déclenchée à 10 m/s en croisière,
montée chargée et descente ; chaque type d'arrêt depuis 12 et 6 m/s, deux
sens). Exécution : `QT_QPA_PLATFORM=offscreen python tests/bench_pannes.py`.

## Constats AVANT (v1.12.20)

| Panne | Constat | Verdict |
|---|---|---|
| thermal / wet_rail / motor_degraded / flood / switch_abt | Moteur coupé en UNE frame au déclenchement du cap (fondu `v_limit` + bleed 1,5 m/s²) → décél 1,82 m/s², jerk 120, cap atteint en 0,8–4,6 s | irréaliste (le « quasi instantané ») |
| service_brake_fail | Aucune réaction : la rame finit le trajet à 12 m/s, 0 kW, frein affiché inopérant — pourtant classée CATASTROPHIQUE | incohérent (le retour terrain) |
| aux_power | « traction coupée, frein serré » annoncé… mais seul le moteur était coupé : la rame ACCÉLÉRAIT en roue libre jusqu'à 13,2 m/s | incohérent |
| parking_stuck | « tambour serré » : la rame continuait à 12 m/s pendant 90 s | incohérent |
| switch_abt_fault | « hold before the siding » annoncé, mais seul un cap 2 m/s était appliqué — jamais d'arrêt avant l'aiguillage | incohérent |
| slack / tension | Annonces menaçantes (« interrupteur de mou », « réduire la puissance ») sans AUCUNE conséquence si on ignore | narratif seulement |
| Arrêt électrique | Doctrine Von Roll ≈ 0,4 m/s² ; mesuré : moy 0,99 en montée (moteur coupé net → la gravité impose sa loi), 0,11–0,36 selon les cas — et consigne qui REMONTAIT vers 12 si le bouton était à 100 % | hors doctrine |
| cable_rupture ↑ | Décél 6,4 m/s² — parachute 3,6 + gravité 2,75 sur la pente | CORRECT (physique) |
| fire / urgence commandée | 1,06–1,87 m/s² (frein poulie 1,25 ± gravité) | CORRECT |
| Parachute | 3,97–4,22 m/s² (3,6 + déséquilibre) | CORRECT |

## Corrections (v1.12.21)

1. **Plafond de panne = affaire du régulateur.** Le fondu moteur et le
   bleed-off se réfèrent au V_MAX MACHINE ; le cap de panne passe par une
   rampe de consigne dédiée **0,60 m/s²** (vs 0,25 confort) avec
   **feed-forward de la pente de consigne** (sans lui le P accumulait
   1,7 m/s d'erreur). Résultat : glissement 10→cap à 0,6–0,75 m/s², plus
   de chute libre.
2. **Chaînes de sécurité automatiques** (la surveillance réelle ne laisse
   jamais rouler un défaut grave) :
   - frein de service dégradé en marche → pressostat → **urgence auto en
     ~3 s** (s'arrête en 126 m depuis 10 m/s) ;
   - dépassement persistant du plafond de panne (> cap + 1 m/s pendant
     12 s SANS décélération franche) → urgence auto ;
   - interrupteur de **mou de câble** : décél > 1,5 m/s² pendant le
     défaut de mou → urgence ;
   - surveillance **tension** : > 35 000 daN (seuil rouge) pendant le
     défaut → urgence.
3. **aux_power** : le frein à manque de courant s'applique (urgence
   engagée au déclenchement) — « traction coupée, frein serré » est
   maintenant vrai (arrêt en 48 m).
4. **parking_stuck en marche** : le tambour serré freine réellement
   (urgence si v > 0,5 m/s).
5. **switch_abt_fault** : enveloppe d'arrêt **avant l'aiguillage**
   (0,6 m/s² vers un point 15 m en amont), cap 2 m/s si déjà engagé.
6. **Arrêt électrique** : consigne plafonnée à la vitesse courante puis
   rampe **0,45 m/s²**, suivie par le contrôleur unifié (le drive garde
   la main : régen contrôlée, décél ≈ 0,4 dans les DEUX sens).

## Mesures APRÈS

| Cas | Avant | Après |
|---|---|---|
| wet_rail 6 m/s | cap en 2,5 s, décél 1,82 | cap en ~7 s, décél ≤ 0,75 |
| flood 4 m/s | cap en 3,5 s, décél 1,82 | glisse à 4, décél ≤ 0,75 |
| service_brake_fail | roule à 12 m/s indéfiniment | urgence auto à 3 s, arrêt 126 m |
| aux_power | accélère à 13,2 m/s | arrêt 48 m (frein ressort) |
| parking_stuck | roule à 12 m/s | arrêt 48 m |
| switch_abt | 2 m/s sans arrêt | freine et s'arrête avant l'aiguillage |
| Arrêt électrique 12 m/s | moy 0,99 (montée) | moy 0,40 les deux sens, 181 m |
| Arrêt électrique 6 m/s | 141–167 m (consigne remontait) | 50 m, moy 0,36 |

Types d'arrêts (inchangés, validés) : urgence commandée 1,85 m/s² moyen
(1,25 frein poulie + déséquilibre gravitaire — 39 m depuis 12 m/s),
parachute 4,1 m/s² (3,6 + gravité — 18 m), rupture de câble en montée
6,4 m/s² (parachute + pente : physique, pas un bug).

Tests : 16/16 inchangés ; le banc `tests/bench_pannes.py` reste dans le repo
pour re-vérifier après toute retouche de la physique.
