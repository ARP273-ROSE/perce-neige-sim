class_name AutoOperator
extends Node
## Mode auto-exploitation : pilote la cabine sans input utilisateur.
## Boucle aller-retour Val Claret ↔ Grande Motte avec arrêts en gare,
## ouverture/fermeture portes, départ automatique. Optionnellement
## injection de pannes aléatoires.
##
## Toggle via F3. Quand actif, override physics.speed_cmd.
## Une fois désactivé, rend la main au driver humain.

enum State {
	IDLE,                # désactivé
	WAITING_AT_STATION,  # portes ouvertes, en gare, dwell timer
	CLOSING_DOORS,       # animation fermeture portes (3s)
	READY_TO_DEPART,     # portes fermées, attend départ
	DEPARTING,           # accel jusqu'à V_CRUISE
	CRUISING,            # vitesse de croisière
	APPROACHING,         # début du ralentissement avant gare
	STOPPING,            # creep + arrêt
	OPENING_DOORS,       # animation ouverture portes (2s)
}

const STATION_DWELL_S: float = 30.0    # temps en gare avant départ auto
const RANDOM_FAULT_CHANCE_PER_TRIP: float = 0.20   # 20% chance d'une panne par voyage

var physics: TrainPhysics = null
var fault_manager: FaultManager = null

var enabled: bool = false
var state: State = State.IDLE
var _state_timer: float = 0.0
var _trip_count: int = 0
var _fault_injected_this_trip: bool = false


func set_physics(p: TrainPhysics) -> void:
	physics = p


func set_fault_manager(fm: FaultManager) -> void:
	fault_manager = fm


func toggle() -> void:
	enabled = not enabled
	if enabled:
		print("[AutoOp] Mode auto-exploitation ACTIVÉ")
		_enter_initial_state()
	else:
		print("[AutoOp] Mode auto-exploitation désactivé — driver manuel reprend la main")
		state = State.IDLE
		# Ne touche plus aux contrôles, le driver reprend
		if physics != null:
			physics.speed_cmd = 0.0


func _enter_initial_state() -> void:
	if physics == null:
		return
	if physics.doors_open:
		state = State.WAITING_AT_STATION
	elif not physics.trip_started:
		state = State.READY_TO_DEPART
	elif absf(physics.v) > 0.5:
		state = State.CRUISING
	else:
		state = State.WAITING_AT_STATION
	_state_timer = 0.0


func _process(delta: float) -> void:
	if not enabled or physics == null:
		return
	# Pas d'auto-exploit en cas de panne catastrophique : le mode s'arrête
	if fault_manager != null and fault_manager.get_active_severity() == FaultManager.Severity.CATASTROPHIC:
		return

	_state_timer += delta

	match state:
		State.WAITING_AT_STATION:
			# Portes ouvertes, on attend STATION_DWELL_S puis on ferme
			physics.speed_cmd = 0.0
			if _state_timer > STATION_DWELL_S:
				_request_close_doors()
				state = State.CLOSING_DOORS
				_state_timer = 0.0
				_fault_injected_this_trip = false

		State.CLOSING_DOORS:
			# Attendre que doors_open passe à false (animation ~3s)
			if not physics.doors_open:
				state = State.READY_TO_DEPART
				_state_timer = 0.0

		State.READY_TO_DEPART:
			# Démarrer le trip et accélérer
			if not physics.trip_started:
				physics.start_trip()
			physics.speed_cmd = 1.0   # plein gaz
			state = State.DEPARTING
			_state_timer = 0.0

		State.DEPARTING:
			# Maintien plein gaz jusqu'à V_CRUISE_PEAK
			physics.speed_cmd = 1.0
			if absf(physics.v) > PNConstants.V_CRUISE_OFFPEAK * 0.95:
				state = State.CRUISING
				_state_timer = 0.0
				_maybe_inject_fault()

		State.CRUISING:
			# Cruise normal
			physics.speed_cmd = 1.0
			# Détecte approche gare : distance restante < 200m
			var dist_remaining: float = _distance_to_stop()
			if dist_remaining < 200.0:
				state = State.APPROACHING
				_state_timer = 0.0

		State.APPROACHING:
			# Réduire la consigne progressivement
			var dist: float = _distance_to_stop()
			# Linéaire de 200m → 1.0 jusqu'à 50m → 0.3 puis creep
			if dist > 50.0:
				physics.speed_cmd = lerpf(0.3, 1.0, (dist - 50.0) / 150.0)
			else:
				physics.speed_cmd = 0.15   # creep
			if dist < 5.0 or physics.finished:
				state = State.STOPPING
				_state_timer = 0.0

		State.STOPPING:
			# Frein doux jusqu'à arrêt complet
			physics.speed_cmd = 0.0
			if absf(physics.v) < 0.05:
				_request_open_doors()
				state = State.OPENING_DOORS
				_state_timer = 0.0
				_trip_count += 1
				print("[AutoOp] Trip %d terminé, arrivée en gare" % _trip_count)

		State.OPENING_DOORS:
			# Attendre que doors_open passe à true
			if physics.doors_open:
				state = State.WAITING_AT_STATION
				_state_timer = 0.0

		_:
			pass


func _distance_to_stop() -> float:
	if physics.direction > 0:
		return maxf(0.0, PNConstants.STOP_S - physics.s)
	else:
		return maxf(0.0, physics.s - PNConstants.START_S)


func _request_close_doors() -> void:
	if physics == null:
		return
	# Trigger fermeture portes — ici on met juste doors_open=false
	# (le sim Python a une animation 3s, on simplifie)
	physics.doors_open = false


func _request_open_doors() -> void:
	if physics == null:
		return
	# À l'arrivée, inverser direction et attendre nouveau départ
	physics.doors_open = true
	physics.trip_started = false
	physics.finished = false
	physics.direction = -physics.direction


func _maybe_inject_fault() -> void:
	if fault_manager == null or _fault_injected_this_trip:
		return
	if randf() < RANDOM_FAULT_CHANCE_PER_TRIP:
		fault_manager.trigger_random(true)   # exclude catastrophic en mode auto
		_fault_injected_this_trip = true
