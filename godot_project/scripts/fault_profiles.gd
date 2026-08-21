class_name FaultProfiles
extends Object
## Profil de réalisme par panne — port de FAULT_PROFILES du sim PC.
## Décrit CE QUI SE PASSE, CE QU'IL FAUT FAIRE et CE QUI EST BLOQUÉ, en
## FR et EN. Utilisé par le panneau de panne du HUD (mode Pannes) et par
## le sélecteur manuel.
##
## Les touches citées sont celles de la version 3D / web :
##   PRÊT-DÉPART (Entrée), FREIN (Espace), URGENCE (Maj), PORTES (D),
##   INVERSER (I) — plus les boutons tactiles équivalents.

const PROFILES: Dictionary = {
	"tension": {
		"what_fr": "Pic de tension transitoire (+6 500 daN) sur le câble — le régulateur a déjà commencé à atténuer.",
		"what_en": "Transient cable tension surge (+6 500 daN) — the regulator is already damping it.",
		"do_fr": "Réduire un peu la consigne de vitesse jusqu'à ce que la jauge Câble revienne au vert.",
		"do_en": "Ease the speed setpoint down until the cable gauge is back in the green.",
		"blocked_fr": "Aucune restriction.",
		"blocked_en": "No restriction.",
	},
	"door": {
		"what_fr": "Capteur de porte défectueux : la sécurité interdit le redémarrage tant que la séquence n'a pas été cyclée.",
		"what_en": "Faulty door sensor : safety chain blocks restart until the door sequence is cycled.",
		"do_fr": "S'arrêter, attendre la levée du défaut, puis relancer avec PRÊT / DÉPART.",
		"do_en": "Stop, wait for the fault to clear, then restart with READY / DEPART.",
		"blocked_fr": "Départ tant que les portes ne sont pas cyclées.",
		"blocked_en": "Departure blocked until the doors are cycled.",
	},
	"thermal": {
		"what_fr": "Bobinages moteur à 105 °C — la protection thermique déclasse la puissance et plafonne à 8 m/s.",
		"what_en": "Motor windings at 105 °C — thermal protection derates power and caps speed at 8 m/s.",
		"do_fr": "Continuer en mode dégradé jusqu'au terminus : le système se refroidit en roulant.",
		"do_en": "Limp home to the terminus — the motors cool down while rolling.",
		"blocked_fr": "Vitesse > 8 m/s, accélérations brusques.",
		"blocked_en": "Speed > 8 m/s, sharp accelerations.",
	},
	"fire": {
		"what_fr": "DÉTECTION FUMÉE en cabine ou en tunnel. Frein d'urgence engagé automatiquement. Risque vital.",
		"what_en": "SMOKE / FIRE DETECTION in cabin or tunnel. Emergency brake engaged automatically. Life-threatening.",
		"do_fr": "1) Arrêt complet  2) Annonce evacuation (auto)  3) Évacuer les passagers  4) Service terminé : NOUVEAU VOYAGE.",
		"do_en": "1) Full stop  2) Evacuation announcement (auto)  3) Evacuate passengers  4) Service over : NEW TRIP.",
		"blocked_fr": "PRÊT, DÉPART, redémarrage du voyage. Service terminé.",
		"blocked_en": "READY, DEPART, trip restart. Service over.",
	},
	"wet_rail": {
		"what_fr": "Suintement / condensation sur les rails — adhérence réduite, plafond auto à 6 m/s.",
		"what_en": "Wall seepage / condensation on the rails — adhesion drops, speed auto-capped at 6 m/s.",
		"do_fr": "Continuer doucement, les patins essuient le rail au passage. La protection se relèvera seule.",
		"do_en": "Keep going gently, the brake shoes wipe the rails. Protection will reset on its own.",
		"blocked_fr": "Vitesse > 6 m/s.",
		"blocked_en": "Speed > 6 m/s.",
	},
	"motor_degraded": {
		"what_fr": "Un des trois groupes moteurs HS — service en mode 2/3 (redondance Von Roll). Plafond 9 m/s.",
		"what_en": "One of the three motor groups failed — 2/3 mode (Von Roll redundancy). Speed cap 9 m/s.",
		"do_fr": "Continuer jusqu'au terminus en mode dégradé. Aucun redémarrage requis.",
		"do_en": "Limp home in degraded mode. No restart required.",
		"blocked_fr": "Vitesse > 9 m/s, accélérations vives.",
		"blocked_en": "Speed > 9 m/s, sharp accelerations.",
	},
	"slack": {
		"what_fr": "Mou de câble détecté (-8 000 daN) — l'élasticité des 3,5 km Fatzer s'est relâchée brièvement.",
		"what_en": "Cable slack detected (-8 000 daN) — the 3.5 km Fatzer elasticity unloaded momentarily.",
		"do_fr": "Freiner doucement pour rétablir la précontrainte.",
		"do_en": "Brake smoothly to restore preload.",
		"blocked_fr": "Aucune restriction (éviter les accélérations brusques).",
		"blocked_en": "No restriction (avoid sharp accelerations).",
	},
	"aux_power": {
		"what_fr": "Perte des auxiliaires 400 V — contacteur traction ouvert, frein tambour serré. Le train s'arrête.",
		"what_en": "400 V auxiliaries lost — traction contactor opened, drum brake clamped. Train will halt.",
		"do_fr": "L'urgence s'engage seule (frein à manque de courant). Attendre la reprise du secours, puis PRÊT / DÉPART.",
		"do_en": "The emergency engages by itself (power-loss brake). Wait for the backup feeder, then READY / DEPART.",
		"blocked_fr": "Traction, PRÊT et DÉPART tant que le 400 V n'est pas restauré.",
		"blocked_en": "Traction, READY and DEPART blocked until 400 V is back.",
	},
	"parking_stuck": {
		"what_fr": "Frein parking (tambour) refuse de se relâcher — la rame ne peut pas démarrer.",
		"what_en": "Parking (drum) brake refuses to release — the cabin cannot move.",
		"do_fr": "Cycler l'arrêt d'urgence à l'arrêt complet, puis PRÊT / DÉPART.",
		"do_en": "Cycle the emergency stop at full stop, then READY / DEPART.",
		"blocked_fr": "Toute traction tant que le tambour ne se libère pas.",
		"blocked_en": "All traction blocked until the drum releases.",
	},
	"cable_rupture": {
		"what_fr": "RUPTURE DU CÂBLE TRACTEUR — événement type Glória (Lisbonne 2025, 16 morts). La tension s'est effondrée, le frein de service est noyé, seul le parachute Belleville retient la cabine.",
		"what_en": "TRACTION CABLE RUPTURE — Gloria-class event (Lisbon 2025, 16 deaths). Tension collapsed, service brake swamped, only the centrifugal Belleville parachute is holding the cabin.",
		"do_fr": "1) Maintenir la cabine à l'arrêt (URGENCE)  2) Annonces incident puis evacuation  3) Évacuer par le passage de service  4) Service terminé : NOUVEAU VOYAGE.",
		"do_en": "1) Hold the cabin stopped (EMERGENCY)  2) Incident then evacuation announcements  3) Evacuate via the service walkway  4) Service over : NEW TRIP.",
		"blocked_fr": "PRÊT, DÉPART, frein de service à 15 % seulement, redémarrage interdit.",
		"blocked_en": "READY, DEPART, service brake only 15 % effective, restart forbidden.",
	},
	"service_brake_fail": {
		"what_fr": "Frein de service hydraulique en perte d'efficacité — pattern de double-défaillance. Le parachute fonctionne encore mais la rame n'est plus apte au service.",
		"what_en": "Hydraulic service brake fade — double-failure pattern. The parachute still works but the cabin is no longer fit for service.",
		"do_fr": "1) La chaîne de sécurité déclenche l'arrêt d'urgence (~3 s)  2) Annonce incident technique  3) Évacuer  4) Service terminé.",
		"do_en": "1) The safety chain trips the emergency stop (~3 s)  2) Technical incident announcement  3) Evacuate  4) Service over.",
		"blocked_fr": "PRÊT, DÉPART, redémarrage du voyage.",
		"blocked_en": "READY, DEPART, trip restart.",
	},
	"flood_tunnel": {
		"what_fr": "Eau stagnante dans le tunnel (alimentation glaciaire) — adhérence critique, plafond auto à 4 m/s.",
		"what_en": "Standing water in the tunnel (glacier-fed) — critical adhesion, speed auto-capped at 4 m/s.",
		"do_fr": "Continuer doucement jusqu'au terminus, en marche au pas.",
		"do_en": "Crawl to the terminus carefully.",
		"blocked_fr": "Vitesse > 4 m/s.",
		"blocked_en": "Speed > 4 m/s.",
	},
	"comms_loss": {
		"what_fr": "PA + radio tunnel perdus — passagers et machinerie isolés (leçon Kaprun 2000 : information = sécurité).",
		"what_en": "Tunnel PA + radio lost — passengers and machinery isolated (Kaprun 2000 lesson : information = safety).",
		"do_fr": "Continuer normalement, surveiller les autres systèmes de plus près.",
		"do_en": "Continue normally, watch the other systems more closely.",
		"blocked_fr": "Annonces sonores tunnel.",
		"blocked_en": "Tunnel PA announcements.",
	},
	"switch_abt_fault": {
		"what_fr": "Aiguillage Abt à l'évitement central désaligné — l'interlock impose l'ARRÊT avant l'évitement jusqu'au verrouillage.",
		"what_en": "Abt crossing switch at the central siding misaligned — the interlock forces a HOLD before the siding until it clears.",
		"do_fr": "Laisser l'enveloppe arrêter la rame avant l'aiguillage, attendre la remise en place, puis reprendre.",
		"do_en": "Let the envelope stop the train before the switch, wait for realignment, then resume.",
		"blocked_fr": "Franchissement de l'évitement ; vitesse > 4 m/s.",
		"blocked_en": "Passing the siding ; speed > 4 m/s.",
	},
	"fire_vent_fail": {
		"what_fr": "FEU EN TUNNEL + DÉSENFUMAGE HORS SERVICE — défaut composé de classe Kaprun 2000 (155 morts). Les fumées ne peuvent pas être extraites.",
		"what_en": "TUNNEL FIRE + VENTILATION OFFLINE — Kaprun-class compound fault (155 deaths). Smoke cannot be extracted from the tunnel.",
		"do_fr": "1) Arrêt immédiat  2) Annonce evacuation (auto)  3) Évacuation IMMÉDIATE par le passage de service (vers le bas, hors des fumées)  4) Service terminé.",
		"do_en": "1) Immediate stop  2) Evacuation announcement (auto)  3) IMMEDIATE evacuation via the service walkway (downward, out of the smoke)  4) Service over.",
		"blocked_fr": "PRÊT, DÉPART, redémarrage du voyage. Service terminé.",
		"blocked_en": "READY, DEPART, trip restart. Service over.",
	},
}

# Pondération du tirage aléatoire (mode Pannes) — calibrée sur
# research_failures.md §2 : aux_power et thermal dominent les funiculaires
# réels, la rupture de câble est rarissime (classe Glória) mais doit être
# représentée pour que le scénario soit pédagogiquement complet.
const WEIGHTS: Dictionary = {
	"tension": 4, "door": 4, "thermal": 5, "fire": 3, "wet_rail": 4,
	"motor_degraded": 4, "slack": 4, "aux_power": 5, "parking_stuck": 4,
	"cable_rupture": 1, "service_brake_fail": 2, "flood_tunnel": 2,
	"comms_loss": 3, "switch_abt_fault": 2, "fire_vent_fail": 2,
}

# Ordre d'affichage dans le sélecteur manuel.
const ORDER: Array = [
	"tension", "door", "thermal", "fire", "wet_rail", "motor_degraded",
	"slack", "aux_power", "parking_stuck", "cable_rupture",
	"service_brake_fail", "flood_tunnel", "comms_loss",
	"switch_abt_fault", "fire_vent_fail",
]


static func get_field(kind: String, field: String, lang: String) -> String:
	if not PROFILES.has(kind):
		return ""
	var key: String = "%s_%s" % [field, "en" if lang == "en" else "fr"]
	var prof: Dictionary = PROFILES[kind]
	return prof.get(key, "")


## Tirage pondéré d'une panne (mode Pannes, planificateur automatique).
static func weighted_pick() -> String:
	var total: int = 0
	for k: String in ORDER:
		total += int(WEIGHTS.get(k, 1))
	var r: int = randi() % maxi(total, 1)
	for k: String in ORDER:
		r -= int(WEIGHTS.get(k, 1))
		if r < 0:
			return k
	return "thermal"
