class_name FaultManager
extends Node
## Système de pannes Perce-Neige — port simplifié des 15 FAULT_KINDS
## du sim Python v1.9.1.
##
## Chaque panne a :
##   - severity : advisory / operational / stopping / catastrophic
##   - speed_cap : plafond de vitesse imposé (0.0 = aucun, ∞ = pas de limite)
##   - stops_train : true si le train doit s'arrêter d'urgence
##   - announcement : clé d'annonce vocale liée
##   - duration : durée auto-clear (0 = jamais auto-clear, intervention requise)
##
## Usage :
##   fault_manager.trigger("wet_rail")
##   fault_manager.clear_active()
##   fault_manager.is_active() / get_active_id() / get_active_label()

enum Severity { ADVISORY, OPERATIONAL, STOPPING, CATASTROPHIC }

# 15 types de pannes — port de FAULT_KINDS du sim Python
const FAULTS: Dictionary = {
	"tension": {
		"severity": Severity.ADVISORY,
		"speed_cap": 999.0,
		"stops_train": false,
		"label_fr": "Pic de tension câble",
		"label_en": "Cable tension spike",
		"announcement": "minor_incident",
		"duration": 30.0,
	},
	"door": {
		"severity": Severity.STOPPING,
		"speed_cap": 0.0,
		"stops_train": true,
		"label_fr": "Défaut porte",
		"label_en": "Door fault",
		"announcement": "tech_incident",
		"duration": 25.0,
	},
	"thermal": {
		"severity": Severity.OPERATIONAL,
		"speed_cap": 8.0,
		"stops_train": false,
		"label_fr": "Surchauffe moteur",
		"label_en": "Motor thermal limit",
		"announcement": "minor_incident",
		"duration": 90.0,
	},
	"fire": {
		"severity": Severity.CATASTROPHIC,
		"speed_cap": 0.0,
		"stops_train": true,
		"label_fr": "DÉTECTION FUMÉE — frein d'urgence",
		"label_en": "SMOKE DETECTED — emergency brake",
		"announcement": "evac",
		"duration": 0.0,
	},
	"wet_rail": {
		"severity": Severity.ADVISORY,
		"speed_cap": 6.0,
		"stops_train": false,
		"label_fr": "Rail humide — adhérence réduite",
		"label_en": "Wet rail — reduced adhesion",
		"announcement": "minor_incident",
		"duration": 60.0,
	},
	"motor_degraded": {
		"severity": Severity.OPERATIONAL,
		"speed_cap": 9.0,
		"stops_train": false,
		"label_fr": "Mode 2/3 moteurs — Von Roll",
		"label_en": "2/3 motor mode — Von Roll redundancy",
		"announcement": "tech_incident",
		"duration": 0.0,   # reste jusqu'à fin du voyage
	},
	"slack": {
		"severity": Severity.ADVISORY,
		"speed_cap": 999.0,
		"stops_train": false,
		"label_fr": "Mou de câble (-8 000 daN)",
		"label_en": "Cable slack (-8 000 daN)",
		"announcement": "minor_incident",
		"duration": 15.0,
	},
	"aux_power": {
		"severity": Severity.STOPPING,
		"speed_cap": 0.0,
		"stops_train": true,
		"label_fr": "Perte auxiliaires 400 V",
		"label_en": "Aux 400 V power loss",
		"announcement": "tech_incident",
		"duration": 45.0,
	},
	"parking_stuck": {
		"severity": Severity.STOPPING,
		"speed_cap": 0.0,
		"stops_train": true,
		"label_fr": "Frein parking bloqué",
		"label_en": "Parking brake stuck",
		"announcement": "long_repair",
		"duration": 60.0,
	},
	"cable_rupture": {
		"severity": Severity.CATASTROPHIC,
		"speed_cap": 0.0,
		"stops_train": true,
		"label_fr": "RUPTURE CÂBLE — frein urgence",
		"label_en": "CABLE RUPTURE — emergency brake",
		"announcement": "evac",
		"duration": 0.0,
	},
	"service_brake_fail": {
		"severity": Severity.CATASTROPHIC,
		"speed_cap": 0.0,
		"stops_train": true,
		"label_fr": "Frein service HS — frein parking",
		"label_en": "Service brake failed — parking brake",
		"announcement": "evac",
		"duration": 0.0,
	},
	"flood_tunnel": {
		"severity": Severity.STOPPING,
		"speed_cap": 0.0,
		"stops_train": true,
		"label_fr": "Inondation tunnel détectée",
		"label_en": "Tunnel flood detected",
		"announcement": "long_repair",
		"duration": 120.0,
	},
	"comms_loss": {
		"severity": Severity.ADVISORY,
		"speed_cap": 10.0,
		"stops_train": false,
		"label_fr": "Perte radio CAB ↔ poste",
		"label_en": "CAB ↔ control radio loss",
		"announcement": "minor_incident",
		"duration": 40.0,
	},
	"switch_abt_fault": {
		"severity": Severity.OPERATIONAL,
		"speed_cap": 4.0,
		"stops_train": false,
		"label_fr": "Anomalie aiguillage Abt",
		"label_en": "Abt switch anomaly",
		"announcement": "tech_incident",
		"duration": 0.0,
	},
	"fire_vent_fail": {
		"severity": Severity.CATASTROPHIC,
		"speed_cap": 0.0,
		"stops_train": true,
		"label_fr": "Ventilation incendie HS",
		"label_en": "Fire ventilation failed",
		"announcement": "evac",
		"duration": 0.0,
	},
}

const SEVERITY_LABEL: Dictionary = {
	Severity.ADVISORY:     {"fr": "INFO",      "en": "INFO"},
	Severity.OPERATIONAL:  {"fr": "DÉGRADÉ",   "en": "DEGRADED"},
	Severity.STOPPING:     {"fr": "ARRÊT",     "en": "STOP"},
	Severity.CATASTROPHIC: {"fr": "URGENCE",   "en": "EMERGENCY"},
}
const SEVERITY_COLOR: Dictionary = {
	Severity.ADVISORY:     Color(0.20, 0.55, 1.0),
	Severity.OPERATIONAL:  Color(1.0, 0.70, 0.10),
	Severity.STOPPING:     Color(1.0, 0.40, 0.10),
	Severity.CATASTROPHIC: Color(1.0, 0.10, 0.10),
}

var lang: String = "fr"
var physics: TrainPhysics = null
var announcements: Announcements = null

# Panne courante
var _active_id: String = ""
var _active_remaining: float = 0.0
var _active_total_duration: float = 0.0


func _ready() -> void:
	_detect_lang()
	set_process(true)


func _detect_lang() -> void:
	var loc: String = OS.get_locale().to_lower()
	lang = "fr" if loc.begins_with("fr") else "en"


func set_physics(p: TrainPhysics) -> void:
	physics = p


func set_announcements(a: Announcements) -> void:
	announcements = a


func is_active() -> bool:
	return _active_id != ""


func get_active_id() -> String:
	return _active_id


func get_active_label() -> String:
	if _active_id == "":
		return ""
	var key: String = "label_fr" if lang == "fr" else "label_en"
	return FAULTS[_active_id][key]


func get_active_severity() -> int:
	if _active_id == "":
		return -1
	return FAULTS[_active_id]["severity"]


func get_active_severity_label() -> String:
	if _active_id == "":
		return ""
	return SEVERITY_LABEL[FAULTS[_active_id]["severity"]][lang]


func get_active_severity_color() -> Color:
	if _active_id == "":
		return Color(1, 1, 1)
	return SEVERITY_COLOR[FAULTS[_active_id]["severity"]]


func get_active_remaining() -> float:
	return _active_remaining


# Plafond de vitesse imposé par la panne courante (m/s).
# Retourne PNConstants.V_MAX si pas de panne ou pas de cap.
func get_speed_cap() -> float:
	if _active_id == "":
		return PNConstants.V_MAX
	var cap: float = FAULTS[_active_id]["speed_cap"]
	return minf(cap, PNConstants.V_MAX)


# Déclenche une panne par son ID. Si une panne est déjà active, la remplace
# (la nouvelle panne prend la priorité).
func trigger(fault_id: String) -> void:
	if not FAULTS.has(fault_id):
		push_warning("[FaultManager] panne inconnue : %s" % fault_id)
		return
	_active_id = fault_id
	var dur: float = FAULTS[fault_id]["duration"]
	_active_total_duration = dur
	_active_remaining = dur if dur > 0.0 else INF

	# Effet immédiat : si la panne arrête le train, déclenche frein urgence
	if FAULTS[fault_id]["stops_train"] and physics != null:
		physics.emergency_brake = true

	# Annonce vocale liée
	var ann_key: String = FAULTS[fault_id]["announcement"]
	if announcements != null and ann_key != "":
		announcements.queue(ann_key)

	print("[Fault] %s déclenchée (%s)" % [fault_id, get_active_severity_label()])


# Force la fin d'une panne (recovery manuelle ou catastrophique → R)
func clear_active() -> void:
	if _active_id == "":
		return
	# Si stopping/catastrophic, libère le frein urgence
	if physics != null:
		physics.emergency_brake = false
	print("[Fault] %s clearée" % _active_id)
	_active_id = ""
	_active_remaining = 0.0
	_active_total_duration = 0.0


# Trigger random pour tests / mode auto-exploitation
func trigger_random(exclude_catastrophic: bool = true) -> void:
	var pool: Array = []
	for fid in FAULTS.keys():
		if exclude_catastrophic and FAULTS[fid]["severity"] == Severity.CATASTROPHIC:
			continue
		pool.append(fid)
	if pool.is_empty():
		return
	trigger(pool.pick_random())


func _process(delta: float) -> void:
	if _active_id == "":
		return
	# Catastrophique : ne s'auto-clear jamais (intervention requise via R)
	if FAULTS[_active_id]["severity"] == Severity.CATASTROPHIC:
		return
	# Decremente le timer ; auto-clear quand atteint 0
	if _active_total_duration > 0.0:
		_active_remaining -= delta
		if _active_remaining <= 0.0:
			clear_active()
