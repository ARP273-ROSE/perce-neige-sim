class_name Challenge
extends Node
## Mode DÉFI — notation du trajet + game-over de conduite.
## Port de la logique challenge_* du sim PC (perce_neige_sim.py) :
##
##   score = 0,40 · confort + 0,35 · précision d'arrêt + 0,25 · régularité
##
##   - confort    : 100 − intégrale de la pénalité ISO 2631 (accélération
##                  au-delà de 0,9 m/s², jerk, urgence à vitesse notable) ;
##   - précision  : écart au repère de quai — 100 à ≤ 0,10 m, 0 à ≥ 2,00 m ;
##   - régularité : 100, moins 60 (urgence engagée), 40 (panne subie),
##                  50 (départ dangereux : portes ouvertes).
##
## Le meilleur score est persisté dans user:// (IndexedDB côté navigateur,
## donc conservé entre deux visites de la PWA).

signal result_ready(data: Dictionary)     # trajet noté
signal crashed(data: Dictionary)          # collision / déraillement

const BEST_FILE: String = "user://challenge_best.json"
const RESULT_BANNER_S: float = 12.0

var physics: TrainPhysics = null
var fault_manager: FaultManager = null
var lang: String = "fr"
var enabled: bool = false

# Fautes du trajet en cours
var emergency_used: bool = false
var fault_hit: bool = false
var unsafe: bool = false

# Dernier résultat
var last_score: float = -1.0
var best: float = 0.0
var docking_err: float = 0.0
var result_t: float = 0.0
var result_lines: Array = []
var review: Dictionary = {}

# Crash
var crash_active: bool = false
var crash_kind: String = ""
var crash_speed: float = 0.0
var crash_msg: String = ""
var crash_review: Dictionary = {}

var _prev_finished: bool = false
var _prev_trip_started: bool = false
var _doors_quip_t: float = -100.0


func _ready() -> void:
	var loc: String = OS.get_locale().to_lower()
	lang = "fr" if loc.begins_with("fr") else "en"
	best = _load_best()
	set_process(true)


func setup(p: TrainPhysics, fm: FaultManager) -> void:
	physics = p
	fault_manager = fm
	if physics != null and not physics.crash_occurred.is_connected(_on_crash):
		physics.crash_occurred.connect(_on_crash)


func _t(fr: String, en: String) -> String:
	return en if lang == "en" else fr


# --- Cycle de vie du trajet ----------------------------------------------

func reset_trip() -> void:
	emergency_used = false
	fault_hit = false
	unsafe = false
	if physics != null:
		physics.jerk_sum = 0.0


func clear_crash() -> void:
	crash_active = false
	crash_kind = ""
	crash_msg = ""
	crash_review = {}


func _process(delta: float) -> void:
	if not enabled or physics == null:
		return
	if result_t > 0.0:
		result_t = maxf(0.0, result_t - delta)

	# Fautes du trajet (mémorisées pour le sous-score de régularité)
	if physics.trip_started and not crash_active:
		if physics.emergency:
			emergency_used = true
		if fault_manager != null and fault_manager.is_active():
			fault_hit = true
		# Départ / marche PORTES OUVERTES : faute lourde + pique
		if physics.doors_open and absf(physics.v) > 0.5:
			unsafe = true
			var now: float = float(Time.get_ticks_msec()) / 1000.0
			if now - _doors_quip_t > 20.0:
				_doors_quip_t = now
				result_lines = [PNQuips.pick_quip(PNQuips.DOORS_OPEN, lang)]
				result_t = 6.0
				last_score = -1.0
				review = {}
				result_ready.emit({"quip_only": true})

	# Nouveau trajet → remise à zéro des fautes (le record persiste)
	if physics.trip_started and not _prev_trip_started:
		reset_trip()
		if physics.doors_open:
			unsafe = true
	_prev_trip_started = physics.trip_started

	# Arrivée → notation
	if physics.finished and not _prev_finished and not crash_active:
		_evaluate()
	_prev_finished = physics.finished


# --- Notation -------------------------------------------------------------

func _evaluate() -> void:
	var ideal: float = PNConstants.STOP_S if physics.direction > 0 \
		else PNConstants.START_S
	var err: float = absf(physics.s - ideal)
	docking_err = err
	var precision: float = clampf(100.0 * (1.0 - (err - 0.10) / 1.90), 0.0, 100.0)

	var reg: float = 100.0
	if emergency_used:
		reg -= 60.0
	if fault_hit:
		reg -= 40.0
	if unsafe:
		reg -= 50.0
	reg = maxf(0.0, reg)

	var comfort: float = maxf(0.0, 100.0 - physics.jerk_sum)
	var score: float = 0.40 * comfort + 0.35 * precision + 0.25 * reg
	last_score = score
	result_t = RESULT_BANNER_S

	review = PNQuips.pick_review("great" if score >= 80.0 else "rough", lang)

	result_lines = [
		_t("Confort %.0f   Precision %.0f   Regularite %.0f",
			"Comfort %.0f   Precision %.0f   Discipline %.0f")
			% [comfort, precision, reg],
		_t("Arret a %.2f m du repere", "Stopped %.2f m from the mark") % err,
	]
	if score > best:
		best = score
		_save_best(best)
		result_lines.append(_t("NOUVEAU RECORD", "NEW RECORD"))

	result_ready.emit({
		"score": score, "comfort": comfort, "precision": precision,
		"reg": reg, "err": err, "review": review,
	})
	print("[Challenge] %.0f/100 (confort %.0f, precision %.0f, regularite %.0f) — arret %.2f m"
		% [score, comfort, precision, reg, err])


# --- Collision ------------------------------------------------------------

func _on_crash(kind: String, speed: float) -> void:
	if crash_active:
		return
	crash_active = true
	crash_kind = kind
	crash_speed = speed
	var pool: Array = PNQuips.CRASH
	if kind == "derail":
		pool = PNQuips.DERAIL
	elif kind == "cabin":
		pool = PNQuips.CABIN
	crash_msg = PNQuips.pick_quip(pool, lang)
	crash_review = PNQuips.pick_review("disaster", lang)
	last_score = -1.0
	result_t = 0.0
	crashed.emit({"kind": kind, "speed": speed, "msg": crash_msg,
		"review": crash_review})
	print("[Challenge] CRASH %s a %.1f km/h" % [kind, speed * 3.6])


func crash_title() -> String:
	match crash_kind:
		"derail":
			return _t("DERAILLEMENT A L'AIGUILLAGE", "DERAILMENT AT THE SWITCH")
		"cabin":
			return _t("COLLISION AVEC L'AUTRE RAME", "HEAD-ON WITH THE OTHER CAR")
		_:
			return _t("COLLISION AVEC LE BUTOIR", "COLLISION WITH THE BUFFER STOP")


# --- Record persistant ----------------------------------------------------

func _load_best() -> float:
	if not FileAccess.file_exists(BEST_FILE):
		return 0.0
	var f: FileAccess = FileAccess.open(BEST_FILE, FileAccess.READ)
	if f == null:
		return 0.0
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary and (parsed as Dictionary).has("best"):
		return float((parsed as Dictionary)["best"])
	return 0.0


func _save_best(value: float) -> void:
	var f: FileAccess = FileAccess.open(BEST_FILE, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"best": snappedf(value, 0.1)}))
	f.close()
