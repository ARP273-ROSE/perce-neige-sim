class_name AutoOperator
extends Node
## Mode auto-exploitation : pilote la cabine sans input utilisateur.
## Boucle aller-retour Val Claret ↔ Grande Motte avec arrêts en gare,
## ouverture/fermeture portes, départ automatique. Optionnellement
## injection de pannes aléatoires.
##
## Toggle via F3. Quand actif, override physics.speed_cmd.
## Une fois désactivé, rend la main au driver humain.
##
## Audit fonctionnel du 07/10/2026 (parité avec l'exploitation auto du PC,
## AutoOps) :
##   - consigne de croisière selon l'HEURE LOCALE : 12 m/s en pointe
##     (9 h-12 h et 14 h-16 h), 10,3 m/s sinon — avant, 12 m/s toute la
##     journée ;
##   - charge de passagers selon l'heure et la saison (loi du PC
##     _sample_pax_load) — avant, tirage aléatoire quelle que soit l'heure ;
##   - plus de phase d'approche pilotée à la main : l'enveloppe d'arrêt du
##     régulateur fait le travail (elle doublonnait le freinage) ;
##   - une panne catastrophique fait SORTIR l'automate (service terminé :
##     NOUVEAU VOYAGE) au lieu de le figer ;
##   - l'automate relâche une urgence parasite avant de demander le
##     départ, et ne demande jamais le départ sur une panne catastrophique.

enum State {
	IDLE,                # désactivé
	WAITING_AT_STATION,  # portes ouvertes, en gare, dwell timer
	CLOSING_DOORS,       # (conservé : la séquence de départ ferme les portes)
	READY_TO_DEPART,     # séquence de départ en cours
	DEPARTING,           # accel jusqu'à la croisière
	CRUISING,            # croisière, puis arrêt par l'enveloppe du régulateur
	APPROACHING,         # (conservé, plus utilisé : l'enveloppe fait l'approche)
	STOPPING,            # (conservé, plus utilisé)
	OPENING_DOORS,       # attente de l'ouverture des portes (stabilisation)
}

const STATION_DWELL_S: float = 30.0    # temps en gare avant départ auto
# Pannes aléatoires en mode auto : DÉSACTIVÉES (retour d'essai iPad
# 2026-07 : « j'ai pas demandé des pannes »). Les pannes se déclenchent
# uniquement à la demande (bouton PANNE / F1).
const RANDOM_FAULT_CHANCE_PER_TRIP: float = 0.0

# Fenêtres de pointe du PC (AutoOps.peak_windows, perce_neige_sim.py
# :5819-5822) : [heure début, minute, heure fin, minute].
const POINTE: Array = [[9, 0, 12, 0], [14, 0, 16, 0]]

var physics: TrainPhysics = null
var fault_manager: FaultManager = null

var enabled: bool = false
## Skieur jouable (07/10/2026, « la fermeture auto et le départ ont été
## déclenchés quand j'ai passé les portes du quai, j'ai loupé le départ ») :
## posé par main.gd. `retenue` : un skieur est en gare sans être monté, on
## ne part pas ; `a_bord` : il est dans la voiture, passé la ligne des
## portes. Monté pendant l'arrêt, la séquence de départ (annonce →
## fermeture des portes → buzzer) part dès qu'on l'a vu dedans (Kevin :
## « qu'il ferme les portes une fois qu'il a détecté que j'étais à
## l'intérieur du funi »). Déjà à bord à l'arrivée : arrêt habituel, il a
## le temps de descendre.
var retenue: bool = false
var a_bord: bool = false
var bloque: bool = false     # à pied sur la voie : on ne part pas, sans limite (08/10/2026)
const A_BORD_DELAI_S: float = 1.5     # dedans depuis 1,5 s : on y va
## Retenue plafonnée (Kevin, 07/10/2026 : « la séquence reste bloquée à
## embarquement 6 s et rien ne se passe, que je reste sur le quai… elle
## devrait se poursuivre toute seule ») : passé RETENUE_MAX_S d'attente à
## cet arrêt, la rame part, skieur sur le quai ou pas.
const RETENUE_MAX_S: float = 45.0
var _retenue_t: float = 0.0
var _vu_en_gare: bool = false         # vu sur le quai pendant cet arrêt
var _a_bord_t: float = 0.0
var state: State = State.IDLE
var _state_timer: float = 0.0
var _trip_count: int = 0
var _fault_injected_this_trip: bool = false


func set_physics(p: TrainPhysics) -> void:
	physics = p


func set_fault_manager(fm: FaultManager) -> void:
	fault_manager = fm


# --- Horaire : pointe / creuse, charge selon l'heure (port du PC) ---------

## Heure locale de l'appareil (dans le navigateur, l'heure système de Godot
## est en UTC — PNConstants.heure_locale).
static func heure_locale() -> Dictionary:
	return PNConstants.heure_locale()


## Heure de pointe : 9 h-12 h et 14 h-16 h (PC AutoOps._is_peak, :6370).
static func heure_de_pointe(hl: Dictionary = {}) -> bool:
	if hl.is_empty():
		hl = heure_locale()
	var m: int = int(hl.get("hour", 0)) * 60 + int(hl.get("minute", 0))
	for w in POINTE:
		if m >= int(w[0]) * 60 + int(w[1]) and m < int(w[2]) * 60 + int(w[3]):
			return true
	return false


## Consigne de croisière (0..1) : 12 m/s en pointe, 10,3 m/s sinon
## (PC peak_cmd = 1,00, offpeak_cmd = 10,3 / V_MAX, :5824-5825).
static func consigne_croisiere(hl: Dictionary = {}) -> float:
	var v: float = PNConstants.V_CRUISE_PEAK if heure_de_pointe(hl) \
		else PNConstants.V_CRUISE_OFFPEAK
	return v / PNConstants.V_MAX


## Ski d'été sur le glacier de la Grande Motte : 15 juin → 31 juillet
## (PC _is_summer_ski_season, :6377-6390).
static func saison_ete(hl: Dictionary) -> bool:
	var m: int = int(hl.get("month", 1))
	var d: int = int(hl.get("day", 1))
	return (m == 6 and d >= 15) or m == 7


## Charge d'une rame selon l'heure et le sens — loi EXACTE du PC
## (_sample_pax_load, :6392-6428) : les skieurs MONTENT en funiculaire et
## redescendent à ski, donc la montée est chargée (pic 10 h 15 en hiver,
## 8 h 30 l'été) et la descente quasi vide (0-10 %), sauf en ski d'été où le
## glacier ferme vers midi (descentes chargées 11 h 30-12 h 30).
static func charge_pax(direction: int, hl: Dictionary = {}) -> int:
	if hl.is_empty():
		hl = heure_locale()
	var hr: float = float(int(hl.get("hour", 0))) + float(int(hl.get("minute", 0))) / 60.0
	var ete: bool = saison_ete(hl)
	var base: float
	if direction > 0:
		var frac: float
		if ete:
			frac = maxf(0.0, 1.0 - absf(hr - 8.5) / 2.5)
		else:
			frac = maxf(0.0, 1.0 - absf(hr - 10.25) / 3.0)
		base = 0.15 + 0.80 * frac
		base *= randf_range(0.80, 1.15)
		base = clampf(base, 0.0, 0.95)
	elif ete:
		var frac_d: float = maxf(0.0, 1.0 - absf(hr - 12.0) / 2.0)
		base = 0.10 + 0.75 * frac_d
		base *= randf_range(0.80, 1.15)
		base = clampf(base, 0.0, 0.90)
	else:
		base = randf_range(0.0, 0.10)
	return int(float(PNConstants.PAX_MAX) * base)


## Loi de charge branchée sur TrainPhysics.roll_pax : [voiture 1, voiture
## 2, contrepoids] — le contrepoids fait le trajet inverse (PC :6350-6353).
func _charge_horaire(direction: int) -> Array:
	var hl: Dictionary = heure_locale()
	var leg: int = charge_pax(direction, hl)
	return [leg / 2, leg - leg / 2, charge_pax(-direction, hl)]


func toggle() -> void:
	# Kevin, 08/10/2026 : « en mode exploitation auto tu repasses tout seul
	# en mode normal, sinon ça fait n'importe quoi » — l'automate ne conduit
	# qu'en mode normal (en Défi plus de sécurités, en Pannes le tirage)
	if not enabled and get_parent() != null and get_parent().get("run_mode") != null \
			and get_parent().get("run_mode") != "normal" and get_parent().has_method("set_run_mode"):
		get_parent().set_run_mode("normal")
		print("[AutoOp] retour au mode normal")
	enabled = not enabled
	var journal: Node = get_parent().get_node_or_null("ExploitationLog") \
		if get_parent() != null else null
	if enabled:
		print("[AutoOp] Mode auto-exploitation ACTIVÉ (%s)"
			% ("heure de pointe, 12 m/s" if heure_de_pointe() else "heure creuse, 10,3 m/s"))
		if physics != null:
			physics.loi_charge = Callable(self, "_charge_horaire")
			# à quai, portes ouvertes : la charge du trajet suit l'heure dès
			# maintenant (les effectifs glissent vers la nouvelle cible)
			if physics.doors_open and not physics.trip_started:
				physics.roll_pax()
		if journal != null:
			journal.set("auto_exploitation", true)
		_enter_initial_state()
	else:
		print("[AutoOp] Mode auto-exploitation désactivé — driver manuel reprend la main")
		state = State.IDLE
		# Ne touche plus aux contrôles, le driver reprend
		if physics != null:
			physics.speed_cmd = 0.0
			physics.loi_charge = Callable()
		if journal != null:
			journal.set("auto_exploitation", false)


func _enter_initial_state() -> void:
	if physics == null:
		return
	if physics.doors_open:
		state = State.WAITING_AT_STATION
		_vu_en_gare = false
		_retenue_t = 0.0
	elif not physics.trip_started:
		state = State.READY_TO_DEPART
	elif absf(physics.v) > 0.5:
		state = State.CRUISING
	else:
		state = State.WAITING_AT_STATION
		_vu_en_gare = false
		_retenue_t = 0.0
	_state_timer = 0.0


## Demande de départ de l'automate (PC AutoOps :6054-6058) : une urgence ou
## un arrêt électrique parasites (touche, rebond) sont relâchés d'abord —
## JAMAIS quand une panne les a engagés. Pose la consigne de croisière de
## l'heure avant la demande (request_depart refuse une consigne à 0).
func _demander_depart() -> void:
	var panne: bool = fault_manager != null and fault_manager.is_active()
	if not panne and (physics.emergency or physics.emergency_ramp > 0.0):
		physics.release_emergency()
		print("[AutoOp] urgence parasite relâchée")
	if not panne and physics.arret_elec:
		physics.arret_elec = false
	physics.speed_cmd = consigne_croisiere()
	var refus: String = physics.request_depart()
	if refus != "":
		print("[AutoOp] départ refusé — %s" % refus)


func _process(delta: float) -> void:
	if not enabled or physics == null:
		return
	# Panne catastrophique : service terminé, l'automate rend la main (le
	# conducteur relance par NOUVEAU VOYAGE). Avant, il restait figé.
	if fault_manager != null and fault_manager.is_active_catastrophic():
		print("[AutoOp] panne catastrophique — exploitation automatique arrêtée (NOUVEAU VOYAGE pour relancer)")
		toggle()
		return

	_state_timer += delta

	var seq_running: bool = physics.announce_phase_remaining > 0.0 \
		or physics.door_phase_remaining > 0.0 \
		or physics.confirmation_autre_remaining > 0.0 \
		or physics.departure_buzzer_remaining > 0.0 \
		or physics.trip_started

	match state:
		State.WAITING_AT_STATION:
			# Portes ouvertes, on attend STATION_DWELL_S puis on lance la
			# séquence de départ COMPLÈTE (annonce → portes → confirmation
			# de l'autre rame → buzzer) — ne plus fermer les portes
			# nous-mêmes : la séquence le fait au bon moment. La consigne
			# est déjà celle de l'heure, comme le PC (consigne à 100 % par
			# défaut à quai) : un PRÊT/DÉPART du conducteur pendant
			# l'attente n'est pas refusé « consigne à 0 » (le tambour tient
			# la rame, la consigne n'a pas d'effet hors voyage).
			physics.speed_cmd = consigne_croisiere()
			# Départ FORCÉ par le conducteur (bouton PRÊT/DÉPART) : la
			# séquence tourne déjà → on embraye tout de suite sans attendre
			# les 30 s. Sinon, on part au terme du dwell automatique.
			if retenue:
				_vu_en_gare = true
				_retenue_t += delta
			_a_bord_t = _a_bord_t + delta if a_bord else 0.0
			if (bloque or (retenue and _retenue_t < RETENUE_MAX_S)) and not seq_running:
				_state_timer = minf(_state_timer, STATION_DWELL_S - 6.0)
			elif a_bord and _vu_en_gare and _a_bord_t > A_BORD_DELAI_S \
					and not seq_running:
				_state_timer = STATION_DWELL_S + 0.01
			if _state_timer > STATION_DWELL_S or seq_running:
				if not seq_running:
					_demander_depart()
				state = State.READY_TO_DEPART
				_state_timer = 0.0
				_fault_injected_this_trip = false

		State.CLOSING_DOORS:
			# (état conservé pour compat — plus utilisé, la séquence de
			# départ gère la fermeture)
			state = State.READY_TO_DEPART
			_state_timer = 0.0

		State.READY_TO_DEPART:
			# Séquence de départ réelle en cours (annonce → portes →
			# confirmation → buzzer → traction). request_depart() est sans
			# effet si la séquence tourne déjà (garde interne).
			if physics.trip_started:
				physics.speed_cmd = consigne_croisiere()
				state = State.DEPARTING
				_state_timer = 0.0
			elif not seq_running and not bloque:
				_demander_depart()

		State.DEPARTING, State.CRUISING:
			# Consigne de l'heure du départ à l'arrivée ; l'enveloppe
			# d'arrêt du régulateur (approche, rampement, accostage) fait
			# l'arrivée toute seule — comme le TRANSIT du PC. L'ancienne
			# APPROACHING (consigne 1 → 0,3 → 0,15 à la main) doublonnait
			# l'enveloppe (cf. commentaire de TrainPhysics._regulator,
			# 2026-07-24). L'arrivée est guettée dès DEPARTING : sous un
			# plafond de panne, la croisière n'est jamais atteinte.
			physics.speed_cmd = consigne_croisiere()
			if physics.finished:
				state = State.OPENING_DOORS
				_state_timer = 0.0
				_trip_count += 1
				print("[AutoOp] Trip %d terminé, arrivée en gare" % _trip_count)
			elif state == State.DEPARTING \
					and absf(physics.v) > physics.speed_cmd * PNConstants.V_MAX * 0.95:
				state = State.CRUISING
				_state_timer = 0.0
				_maybe_inject_fault()

		State.APPROACHING, State.STOPPING:
			# (états conservés pour compat — plus utilisés)
			state = State.CRUISING
			_state_timer = 0.0

		State.OPENING_DOORS:
			# Les portes s'ouvrent TOUTES SEULES après la temporisation
			# d'arrivée de la physique (rebond de câble visible pendant
			# ~15 s) — ne rien forcer ici, juste attendre. (Surtout pas
			# `finished = false` : ça réarmait le serrage d'arrivée à
			# chaque frame → tempo jamais écoulée, portes jamais
			# ouvertes. start_trip() remet finished à zéro au départ.)
			if physics.doors_open:
				state = State.WAITING_AT_STATION
				_vu_en_gare = false
				_retenue_t = 0.0
				_state_timer = 0.0

		_:
			pass


func _distance_to_stop() -> float:
	if physics.direction > 0:
		return maxf(0.0, PNConstants.STOP_S - physics.s)
	else:
		return maxf(0.0, physics.s - PNConstants.START_S)


func _maybe_inject_fault() -> void:
	if fault_manager == null or _fault_injected_this_trip:
		return
	if randf() < RANDOM_FAULT_CHANCE_PER_TRIP:
		fault_manager.trigger_random(true)   # exclude catastrophic en mode auto
		_fault_injected_this_trip = true
