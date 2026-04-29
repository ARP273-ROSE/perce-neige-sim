extends Node3D
## Orchestrateur principal — construit la scène 3D, gère les inputs,
## fait tourner la physique à 60 Hz fixe.

const PHYSICS_HZ: float = 60.0
const PHYSICS_DT: float = 1.0 / PHYSICS_HZ

var physics: TrainPhysics = null
var tunnel: TunnelBuilder = null
var track: TrackBuilder = null
var stations: StationsBuilder = null
var station_halls: StationHalls = null
var machine_room: MachineRoomBuilder = null
var lights: TunnelLights = null
var cabin: Cabin = null
var cabin_ghost: Cabin = null
var hud: HUD = null
var audio: TrainAudio = null
var announcements: Announcements = null
var fault_manager: FaultManager = null
var auto_operator: AutoOperator = null
var exploitation_log: ExploitationLog = null
var state_receiver: StateReceiver = null

# Mode CLIENT : démarré avec --client en arg projet, le sim Python pilote
# l'état via UDP. La physique locale + l'auto-op + les annonces auto sont
# désactivés. Le HUD est masqué (Python a son propre HUD).
var client_mode: bool = false

# État précédent pour détection de transition (annonces)
var _prev_doors_open: bool = true
var _prev_trip_started: bool = false
var _prev_direction: int = 1
var _last_welcome_time: float = -999.0
var _exit_announced_for_stop: bool = false
var _prev_fault_id: String = ""
var _prev_finished: bool = false

var _physics_accum: float = 0.0
var _paused: bool = false

# Contrôles
var speed_cmd_rate: float = 0.4    # variation par seconde du setpoint


func _ready() -> void:
	# Détection du mode CLIENT (Godot piloté par le sim Python via UDP)
	for arg in OS.get_cmdline_user_args():
		if arg == "--client":
			client_mode = true
	if client_mode:
		print("[PerceNeige3D] CLIENT MODE — physique pilotée par le sim Python")

	print("[PerceNeige3D] Build starting…")
	_build_environment()
	_build_physics()
	_build_tunnel()
	_build_track()
	_build_stations()
	_build_station_halls()
	_build_machine_room()
	_build_lights()
	_build_cabin()

	if client_mode:
		# Démarre directement la trip pour que la cabine se positionne
		# selon l'état reçu (sinon physics.s = START_S = 20m bloqué)
		physics.trip_started = true
		physics.doors_open = false
		_build_state_receiver()
		# HUD minimal (juste status pour debug)
		_build_audio()   # le son ambient cruise est sympa à garder
	else:
		_build_hud()
		_build_audio()
		_build_announcements()
	print("[PerceNeige3D] Ready.")


func _build_state_receiver() -> void:
	state_receiver = StateReceiver.new()
	state_receiver.name = "StateReceiver"
	add_child(state_receiver)
	state_receiver.set_physics(physics)
	# fault_manager peut être set après si besoin (en client mode minimal,
	# on ne le construit pas pour ne pas dupliquer la logique Python)


func _build_announcements() -> void:
	announcements = Announcements.new()
	announcements.name = "Announcements"
	add_child(announcements)
	_build_fault_manager()


func _build_fault_manager() -> void:
	fault_manager = FaultManager.new()
	fault_manager.name = "FaultManager"
	add_child(fault_manager)
	fault_manager.set_physics(physics)
	fault_manager.set_announcements(announcements)
	# Connecte le HUD pour qu'il affiche la panne courante
	if hud != null:
		hud.set_fault_manager(fault_manager)
	_build_auto_operator()


func _build_auto_operator() -> void:
	auto_operator = AutoOperator.new()
	auto_operator.name = "AutoOperator"
	add_child(auto_operator)
	auto_operator.set_physics(physics)
	auto_operator.set_fault_manager(fault_manager)
	_build_exploitation_log()


func _build_exploitation_log() -> void:
	exploitation_log = ExploitationLog.new()
	exploitation_log.name = "ExploitationLog"
	add_child(exploitation_log)
	exploitation_log.set_physics(physics)


func _build_machine_room() -> void:
	machine_room = MachineRoomBuilder.new()
	machine_room.name = "MachineRoom"
	add_child(machine_room)
	machine_room.build(tunnel)
	print("[MachineRoom] poulie motrice ∅ 4160 mm + 3 moteurs DC construits")


func _build_track() -> void:
	track = TrackBuilder.new()
	track.name = "Track"
	add_child(track)
	track.build(tunnel)
	print("[Track] rails/dalle/câble construits (longueur=%.0fm)" % PNConstants.LENGTH)


func _build_stations() -> void:
	stations = StationsBuilder.new()
	stations.name = "Stations"
	add_child(stations)
	stations.build(tunnel)
	print("[Stations] Val Claret + Grande Motte construites")


func _build_station_halls() -> void:
	station_halls = StationHalls.new()
	station_halls.name = "StationHalls"
	add_child(station_halls)
	station_halls.build(tunnel)
	print("[StationHalls] Halls Val Claret + Grande Motte (concourses + sortie surface)")


func _build_audio() -> void:
	audio = TrainAudio.new()
	audio.name = "TrainAudio"
	add_child(audio)
	audio.set_physics(physics)


func _build_environment() -> void:
	var env: Environment = Environment.new()

	# --- Sky procédural (visible à travers les portails du tunnel) -------
	var sky: Sky = Sky.new()
	var sky_mat: PhysicalSkyMaterial = PhysicalSkyMaterial.new()
	sky_mat.rayleigh_coefficient = 2.0
	sky_mat.rayleigh_color = Color(0.50, 0.65, 1.0)
	sky_mat.mie_coefficient = 0.005
	sky_mat.mie_color = Color(0.90, 0.95, 1.0)
	sky_mat.mie_eccentricity = 0.80
	sky_mat.ground_color = Color(0.55, 0.58, 0.62)
	sky_mat.sun_disk_scale = 1.0
	sky_mat.energy_multiplier = 1.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.background_energy_multiplier = 1.0

	# --- Ambient : modéré (tunnel doit rester lisible sans être un faisceau aveuglant) ---
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.45, 0.50, 0.60)
	env.ambient_light_energy = 0.40
	env.ambient_light_sky_contribution = 0.3

	# --- SDFGI (global illumination) -------------------------------------
	env.sdfgi_enabled = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.4
	env.sdfgi_use_occlusion = true
	env.sdfgi_energy = 1.0
	env.sdfgi_read_sky_light = true

	# --- Brouillard (léger, tunnel feeling) ------------------------------
	env.fog_enabled = true
	env.fog_light_color = Color(0.55, 0.58, 0.65)
	env.fog_light_energy = 1.0
	env.fog_density = 0.004
	env.fog_height = 2500.0
	env.fog_height_density = 0.0
	env.fog_sky_affect = 0.5
	# Volumétrique plus subtil
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = Color(0.85, 0.88, 0.95)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.volumetric_fog_length = 80.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.5

	# --- Tonemap + glow --------------------------------------------------
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_strength = 1.0
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.5

	# --- SSR -------------------------------------------------------------
	env.ssr_enabled = true
	env.ssr_max_steps = 40

	# --- Ajustements couleur ---------------------------------------------
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.05

	var we: WorldEnvironment = WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	# --- Soleil : directional light (illumine l'extérieur des portails) --
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.2
	# Inclinaison : soleil d'après-midi sur le glacier (Sud-Ouest, 40° au-dessus)
	sun.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(160.0), 0.0)
	sun.shadow_enabled = false  # shadows désactivées pour perf sur tunnel long
	add_child(sun)


func _build_physics() -> void:
	physics = TrainPhysics.new()
	physics.direction = 1           # départ Val Claret → Glacier
	physics.s = PNConstants.START_S
	physics.v = 0.0
	physics.doors_open = true
	physics.maint_brake = true
	physics.trip_started = false
	physics.lights_head = true      # phares ON au démarrage


func _build_tunnel() -> void:
	tunnel = TunnelBuilder.new()
	tunnel.name = "Tunnel"
	tunnel.ring_spacing = 3.0
	tunnel.ring_segments = 20
	tunnel.tunnel_radius = PNConstants.TUNNEL_RADIUS
	add_child(tunnel)
	var p0: Vector3 = tunnel.path_points[0]
	var p10: Vector3 = tunnel.path_points[10]
	var plast: Vector3 = tunnel.path_points[tunnel.path_points.size() - 1]
	print("[Tunnel] %d rings, p0=%s, p10=%s, plast=%s" % [
		tunnel.path_points.size(), p0, p10, plast
	])


func _build_lights() -> void:
	lights = TunnelLights.new()
	lights.name = "TunnelLights"
	add_child(lights)
	lights.build(tunnel)


func _build_cabin() -> void:
	cabin = Cabin.new()
	cabin.name = "Cabin"
	cabin.is_ghost = false
	cabin.passing_side = -1.0  # rame 1 sur voie gauche au passing loop
	add_child(cabin)
	cabin.set_tunnel(tunnel)
	cabin.set_physics(physics)

	# Ghost (rame 2) — visible à s_ghost = LENGTH - physics.s, voie droite au passing loop
	cabin_ghost = Cabin.new()
	cabin_ghost.name = "CabinGhost"
	cabin_ghost.is_ghost = true
	cabin_ghost.passing_side = +1.0
	add_child(cabin_ghost)
	cabin_ghost.set_tunnel(tunnel)
	cabin_ghost.set_physics(physics)


func _build_hud() -> void:
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.set_physics(physics)


# ---------------------------------------------------------------------------
# Boucle principale — physique à pas fixe 60 Hz
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _paused:
		return

	# Inputs continus (désactivés en mode client : Python pilote)
	if not client_mode:
		_handle_continuous_input(delta)

		# Physique à pas fixe
		_physics_accum += delta
		var steps: int = 0
		while _physics_accum >= PHYSICS_DT and steps < 4:
			physics.step(PHYSICS_DT)
			_physics_accum -= PHYSICS_DT
			steps += 1

	# Masquage dynamique des brins de câble selon la position des rames
	track.update_cable_visibility(physics.s)
	# Animation des torons (brin gauche = fixe par rapport à rame 1,
	# brin droite = défile à 2×v en référentiel rame 1)
	track.update_cable_phase(physics.s, physics.v * float(physics.direction), delta)
	# Rotation de la poulie motrice selon la vitesse du câble
	machine_room.update_rotation(physics.v * float(physics.direction), delta)

	# Sync du plafond de vitesse imposé par la panne courante (s'il y en a une)
	if fault_manager != null:
		physics.speed_cap_external = fault_manager.get_speed_cap()

	# Annonces vocales + log : skip en mode client (Python s'en occupe)
	if not client_mode:
		_update_announcement_triggers()


func _update_announcement_triggers() -> void:
	if announcements == null:
		return

	# Trip vient de démarrer (départ) → annonce + log
	if physics.trip_started and not _prev_trip_started:
		announcements.queue("doors_close")
		if exploitation_log != null:
			exploitation_log.start_trip(physics.direction)

	# Trip vient de se terminer (arrivée) → log
	if physics.finished and not _prev_finished:
		if exploitation_log != null:
			exploitation_log.end_trip(true)
	_prev_finished = physics.finished

	# Update des max du voyage en cours chaque frame
	if exploitation_log != null:
		exploitation_log.update_extremes()

	# Détecte nouvelle panne déclenchée pour la logger
	if fault_manager != null:
		var fid: String = fault_manager.get_active_id()
		if fid != "" and fid != _prev_fault_id and exploitation_log != null:
			exploitation_log.record_fault(fid)
		_prev_fault_id = fid

	# Portes viennent de s'ouvrir → annonce "sortie côté gauche" (arrivée gare)
	if physics.doors_open and not _prev_doors_open:
		# Choix de l'annonce selon où on est arrivé
		if physics.s >= PNConstants.STOP_S - 5.0:
			# Arrivée Grande Motte (haut)
			announcements.queue("exit_upstream")
		elif physics.s <= PNConstants.START_S + 5.0:
			# Arrivée Val Claret (bas)
			announcements.queue("exit_downstream")
		else:
			announcements.queue("exit_left")
		_exit_announced_for_stop = true

	# Annonce de bienvenue : portes ouvertes immobile à une station, espacée
	# de 30s pour ne pas spammer.
	var now: float = Time.get_ticks_msec() / 1000.0
	if physics.doors_open and absf(physics.v) < 0.05 and (now - _last_welcome_time) > 30.0:
		var at_low: bool = physics.s <= PNConstants.START_S + 5.0
		var at_high: bool = physics.s >= PNConstants.STOP_S - 5.0
		if at_low or at_high:
			announcements.queue("welcome")
			_last_welcome_time = now

	# Reset du flag exit_announced quand on quitte la station
	if not physics.doors_open and _exit_announced_for_stop:
		_exit_announced_for_stop = false

	# Sauvegarde l'état pour la frame suivante
	_prev_doors_open = physics.doors_open
	_prev_trip_started = physics.trip_started
	_prev_direction = physics.direction


func _handle_continuous_input(delta: float) -> void:
	if Input.is_action_pressed("speed_up"):
		physics.speed_cmd = clampf(physics.speed_cmd + speed_cmd_rate * delta, 0.0, 1.0)
	if Input.is_action_pressed("speed_down"):
		physics.speed_cmd = clampf(physics.speed_cmd - speed_cmd_rate * delta, 0.0, 1.0)

	# Frein service : tant que bouton enfoncé
	if Input.is_action_pressed("brake"):
		physics.brake = minf(1.0, physics.brake + 1.5 * delta)
	# Note : le relâchement est géré par le régulateur (qui baisse brake)

	# Urgence : latch sur press
	if Input.is_action_just_pressed("emergency"):
		physics.emergency = true
		physics.speed_cmd = 0.0

	if Input.is_action_just_pressed("toggle_headlights"):
		physics.lights_head = not physics.lights_head
		cabin.set_headlights(physics.lights_head)
		print("[Headlights] %s" % ["ON" if physics.lights_head else "OFF"])

	if Input.is_action_just_pressed("ready_depart"):
		if physics.emergency:
			physics.release_emergency()
			print("[Emergency released]")
		elif not physics.trip_started:
			physics.start_trip()
			print("[Trip started]")

	if Input.is_action_just_pressed("pause"):
		_paused = not _paused
		print("[Paused] %s" % _paused)

	if Input.is_action_just_pressed("toggle_view"):
		cabin.toggle_view()


func _unhandled_input(event: InputEvent) -> void:
	# Pannes + auto-exploitation
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1 and fault_manager != null:
			fault_manager.trigger_random()
		elif event.keycode == KEY_F2 and fault_manager != null:
			fault_manager.clear_active()
		elif event.keycode == KEY_F3 and auto_operator != null:
			auto_operator.toggle()
