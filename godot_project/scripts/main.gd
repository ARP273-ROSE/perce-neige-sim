extends Node3D
## Orchestrateur principal — construit la scène 3D, gère les inputs,
## fait tourner la physique à 60 Hz fixe.

const PHYSICS_HZ: float = 60.0
const PHYSICS_DT: float = 1.0 / PHYSICS_HZ

# Annonce de sortie ("Sortie des passagers", amont/aval) jouée automatiquement
# à l'ouverture des portes en gare. Coupée par défaut : elle tombait toujours
# juste après le demi-tour auto et était perçue comme une annonce de panne.
# Disponible à la demande via le bouton ANNONCES.
const AUTO_EXIT_ANNOUNCE: bool = false

var physics: TrainPhysics = null
var tunnel: TunnelBuilder = null
var track: TrackBuilder = null
var stations: StationsBuilder = null
var station_halls: StationHalls = null
var relief: ReliefBuilder = null
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
var challenge: Challenge = null
var challenge_panel: ChallengePanel = null
var fault_picker: FaultPicker = null

# Mode de jeu — comme la version PC : normal | challenge (Défi) | panne.
var run_mode: String = "normal"
var _scenario_rame2: bool = false

# Mode CLIENT : démarré avec --client en arg projet, le sim Python pilote
# l'état via UDP. La physique locale + l'auto-op + les annonces auto sont
# désactivés. Le HUD est masqué (Python a son propre HUD).
var client_mode: bool = false

# Préréglage de rendu (--quality=low|medium|high en arg projet) :
#   high   (défaut) : SDFGI + fog volumétrique + SSR — machines Vulkan solides
#   medium          : SDFGI off (le poste GPU le plus cher, peu utile dans un
#                     tunnel éclairé aux omnis sans ombres)
#   low             : SDFGI + fog volumétrique + SSR off — iGPU / fallback
var quality: String = "high"

# État précédent pour détection de transition (annonces)
var _prev_doors_open: bool = true
var _prev_trip_started: bool = false
var _prev_direction: int = 1
var _prev_announce_remaining: float = 0.0
var _welcome_played: bool = false
var _exit_announced_for_stop: bool = false
var _prev_fault_id: String = ""
var _prev_finished: bool = false

var _physics_accum: float = 0.0
var _paused: bool = false
var _light_cull_accum: float = 999.0   # force un 1er culling dès la frame 1
# Éclairage du tunnel (touche J, bouton TUNNEL, ou le sim PC) — demande du
# 03/10/2026 : « rajoute l'option de couper tous les éclairages du tunnel ».
var tunnel_lights_on: bool = true
var _client_s: float = NAN        # position rendue lissée en mode client
# Réglages graphiques selon la machine + ajustement en direct (PerfManager)
var perf_manager: PerfManager = null
var quality_mode: String = "auto"   # auto (détection + direct) | high | medium | low
var _ext_light: DirectionalLight3D = null   # vue extérieure seulement
var _compat: bool = RenderingServer.get_current_rendering_method() == "gl_compatibility"
var _env: Environment = null
# Skieur jouable (07/10/2026) : construit au premier passage en vue skieur
var skieur: SkieurJoueur = null
var collisions: CollisionsJeu = null
var commandes_skieur: CommandesSkieur = null
var mode_skieur: bool = false
var _skieur_place: bool = false        # déjà posé une fois (on le retrouve où on l'a laissé)
var _skieur_au_poste: bool = false     # assis au poste : la vue cabine est la sienne
var _skieur_voiture: Node3D = null     # voiture où il était en quittant la vue skieur
var _skieur_local: Vector3 = Vector3.ZERO
var _depart_haut: bool = false         # scénario parti d'en haut (sens descente)
const AMBIENT_ON: float = 0.40
const AMBIENT_OFF: float = 0.0        # noir total : seuls phares, cabine et gares éclairent
## Halls de gare en rendu Compatibility (PWA), voir _process
const AMBIENT_GARE_WEB: float = 0.40
const SOL_CIEL: Color = Color(0.55, 0.58, 0.62)    # sol du ciel physique (_build_environment)
const SOL_ROCHE: Color = Color(0.17, 0.17, 0.18)
var _sol_ext: bool = false
const FOG_LIGHT_ON: float = 1.0
const FOG_LIGHT_OFF: float = 0.0      # le brouillard ne doit pas « éclairer » le fond

# Contrôles
var speed_cmd_rate: float = 0.4    # variation par seconde du setpoint


func _ready() -> void:
	# Détection du mode CLIENT (Godot piloté par le sim Python via UDP)
	for arg in OS.get_cmdline_user_args():
		if arg == "--client":
			client_mode = true
		elif arg.begins_with("--quality="):
			var q: String = arg.substr(10)
			if q in ["low", "medium", "high"]:
				quality = q
				quality_mode = q
			elif q == "auto":
				quality_mode = "auto"
			else:
				push_warning("[PerceNeige3D] --quality=%s inconnu — auto conservé" % q)
	if OS.has_feature("web"):
		# Export Web (iPad PWA) : la plateforme impose le rendu
		# Compatibility → SDFGI/fog volumétrique/SSR n'existent pas,
		# on force le préréglage low pour rester cohérent.
		quality = "low"
		# iPad Pro ProMotion : capper à 60 fps donnait une cadence
		# 1-vsync/2-vsync irrégulière (rails toujours saccadés, retour
		# d'essai 2026-07-12) → rendu au taux natif de l'écran (120 Hz),
		# et la facture GPU est payée par un rendu 3D à 70 % upscalé
		# bilinéaire (l'UI reste à la résolution native).
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		get_viewport().scaling_3d_scale = 0.6
	if client_mode:
		print("[PerceNeige3D] CLIENT MODE — physique pilotée par le sim Python")
	if quality != "high":
		print("[PerceNeige3D] Préréglage rendu : %s" % quality)

	print("[PerceNeige3D] Build starting…")
	_build_environment()
	# Réglages selon la machine (cran de départ) puis ajustement en direct.
	# L'environnement est construit avec tous les effets (qualité haute) en
	# mode auto : le PerfManager retire ce que la machine ne tient pas.
	perf_manager = PerfManager.new()
	perf_manager.name = "PerfManager"
	add_child(perf_manager)
	perf_manager.setup(self, _env, quality_mode)
	_build_physics()
	_build_tunnel()
	_build_track()
	_build_stations()
	_build_station_halls()
	_build_relief()
	_build_machine_room()
	if station_halls != null and machine_room != null:
		station_halls.build_amont(machine_room)
	# le relief s'écarte des gares (bâtiments, place, terrasse, quais)
	if relief != null and station_halls != null:
		for g in [station_halls.gare_aval, station_halls.gare_amont]:
			if g != null:
				relief.amenagements.append(g.amenagement_relief())
	if _compat:
		_remplissage_gares_web()
	_build_lights()
	_build_cabin()

	if client_mode:
		# Démarre directement la trip pour que la cabine se positionne
		# selon l'état reçu (sinon physics.s = START_S = 20m bloqué)
		physics.trip_started = true
		physics.doors_open = false
		_build_state_receiver()
		# PAS de TrainAudio en mode client : le sim Python joue déjà les
		# versions réelles de TOUT (boucles d'ambiance crossfadées,
		# croisement, buzzers, portes, annonces) — les deux ensemble
		# donnaient un doublon phasé de chaque son pendant le trajet.
	else:
		_build_hud()
		_build_audio()
		_build_announcements()
		# Écran tactile (iPad) ou navigateur (PWA, même sur PC à la souris :
		# retour du 06/10/2026, « dans le navigateur du PC » il n'y avait
		# aucun bouton) : boutons à l'écran qui émettent les mêmes actions
		# que le clavier.
		# (--tactile : rendus de contrôle de la disposition iPad)
		if DisplayServer.is_touchscreen_available() or OS.has_feature("web") \
				or OS.get_cmdline_user_args().has("--tactile"):
			var touch: TouchControls = TouchControls.new()
			touch.name = "TouchControls"
			touch.setup(self)   # accès direct AUTO/PANNE + reflet d'état
			add_child(touch)
		# Web : le déverrouillage audio (reprise des AudioContext dans le
		# geste utilisateur + audioSession 'playback' anti-mode-silencieux
		# iPad) est géré par le hook JS injecté via html/head_include du
		# preset d'export — plus de voile ni de bip de test (retirés à la
		# demande de Kevin, essai iPad 2026-07-12).
		if "--autotest" in OS.get_cmdline_user_args():
			auto_operator.enabled = true
			auto_operator._enter_initial_state()
			print("[Autotest] auto-exploitation forcée ON")
		elif "--drivetest" in OS.get_cmdline_user_args():
			_drivetest()
		elif _cmdline_mode() != "":
			# --mode=normal|challenge|panne : démarrage direct dans un mode
			# donné, sans passer par le sélecteur (bancs headless).
			_apply_scenario(false, false, _cmdline_mode())
		else:
			# Sélecteur de scénario (gare de départ + rame + mode de jeu)
			var scen: ScenarioPanel = ScenarioPanel.new()
			scen.name = "ScenarioPanel"
			add_child(scen)
			scen.chosen.connect(_apply_scenario)
	_diag_masquer()
	print("[PerceNeige3D] Ready.")


## Allume ou coupe tout l'éclairage du tunnel (néons et leurs tubes). Pour
## une vraie nuit, la lumière ambiante et la teinte du brouillard baissent
## aussi : il ne reste que les phares, l'éclairage des gares, de la salle
## des machines et de la cabine.
func set_tunnel_lights(on: bool) -> void:
	tunnel_lights_on = on
	if lights != null:
		lights.set_enabled(on)
	if track != null:
		track.set_loop_lamps(on)     # réglettes de l'évitement
		if on:
			_light_cull_accum = 999.0      # rallumage dès l'image suivante
	if _env != null:
		_env.ambient_light_energy = AMBIENT_ON if on else AMBIENT_OFF
		_env.fog_light_energy = FOG_LIGHT_ON if on else FOG_LIGHT_OFF
		# Noir TOTAL (retour du 03/10 : « éclairages éteints le tunnel doit
		# être dans le noir total, là on le voit ») : le ciel, invisible
		# dans le tunnel, éclairait encore par ses reflets sur les parois
		# lisses ; en qualité haute (vue 3D du PC), l'illumination globale
		# SDFGI et le brouillard volumétrique réinjectaient aussi de la
		# lumière.
		_env.background_energy_multiplier = 1.0 if on else 0.0
		_env.sdfgi_energy = 1.0 if on else 0.0
		_env.volumetric_fog_gi_inject = 0.5 if on else 0.0
		# reflets spéculaires du ciel (pare-brise, rails, parois lisses) :
		# ciel à énergie nulle plutôt que source de reflets désactivée —
		# même effet, sans changer les shaders à chaud (iPad, 05/10/2026)
		_energie_ciel(1.0 if on else 0.0)
	print("[Tunnel] éclairage %s" % ["allumé" if on else "coupé"])


func _energie_ciel(e: float) -> void:
	if _env == null or _env.sky == null:
		return
	if _env.sky.sky_material is PhysicalSkyMaterial:
		(_env.sky.sky_material as PhysicalSkyMaterial).energy_multiplier = e
	elif _env.sky.sky_material is ProceduralSkyMaterial:
		(_env.sky.sky_material as ProceduralSkyMaterial).sky_energy_multiplier = e
		(_env.sky.sky_material as ProceduralSkyMaterial).ground_energy_multiplier = e


func toggle_tunnel_lights() -> void:
	set_tunnel_lights(not tunnel_lights_on)


## Éclairage intérieur de la cabine (touche C, bouton CABINE) — comme le PC.
func toggle_cabin_lights() -> void:
	if physics == null:
		return
	physics.lights_cabin = not physics.lights_cabin
	print("[Cabine] éclairage %s" % ["allumé" if physics.lights_cabin else "éteint"])


# Diagnostic de performance : --masquer=hud,cabin,lights,voie/Nom… cache des
# groupes pour mesurer ce qu'ils coûtent dans l'export Web réel (banc
# tests/web_perf.py, Chromium sur GPU).
func _diag_masquer() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--masquer="):
			continue
		for nom in arg.substr(10).split(","):
			var n: Node = null
			if nom.begins_with("voie/"):
				n = track.get_node_or_null(nom.substr(5)) if track != null else null
			elif nom.begins_with("hud/"):
				n = hud.get_node_or_null(nom.substr(4)) if hud != null else null
			else:
				n = get(nom) as Node
			if n != null:
				n.set("visible", false)
				print("[Diag] masqué : ", nom)


# Applique le scénario choisi au démarrage : gare haute = départ en
# descente ; rame 2 = voie DROITE dans l'évitement (la rame 1 prend la
# gauche) — les deux cabines échangent leur voie.
func _apply_scenario(from_top: bool, rame2: bool, mode: String = "normal") -> void:
	set_run_mode(mode)
	if from_top:
		physics.s = PNConstants.STOP_S
		physics.s_prev_step = physics.s
		physics.s_render = physics.s
		physics.direction = -1
		# Re-tire la charge passagers pour un départ en DESCENTE (rame
		# quasi vide, contrepoids chargé) — le premier roll de
		# _build_physics supposait une montée.
		physics.roll_pax()
	apply_rame(rame2)
	_scenario_rame2 = rame2
	_depart_haut = from_top
	print("[Scenario] depart %s, rame %d, mode %s" % [
		"gare haute" if from_top else "gare basse", 2 if rame2 else 1, run_mode])


# Bascule de mode de jeu (sélecteur de départ, ou touche M en cours de
# partie). NORMAL = exploitation Von Roll classique ; DÉFI = conduite
# notée sans aucun filet ; PANNES = conduite manuelle avec incidents.
func _cmdline_mode() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			var m: String = arg.substr(7)
			if m in ["normal", "challenge", "panne"]:
				return m
	return ""


func set_run_mode(mode: String) -> void:
	if not mode in ["normal", "challenge", "panne"]:
		mode = "normal"
	run_mode = mode
	if physics != null:
		physics.challenge_mode = (mode == "challenge")
	if fault_manager != null:
		fault_manager.scheduler_enabled = (mode == "panne")
		# Changer de mode remet la ligne en ordre de marche.
		if fault_manager.is_active():
			fault_manager.clear_active()
	if challenge != null:
		challenge.enabled = (mode == "challenge")
		challenge.reset_trip()
		challenge.clear_crash()
	# En Défi comme en Pannes, on CONDUIT : l'exploitation automatique est
	# coupée (elle écraserait la consigne du conducteur à chaque frame).
	if auto_operator != null and mode != "normal" and auto_operator.enabled:
		auto_operator.toggle()
	if hud != null:
		hud.set_run_mode(mode)
	if fault_picker != null and mode != "panne" and fault_picker.is_open():
		fault_picker.toggle()


# Applique le NUMÉRO de rame pilotée à tout ce qui en dépend. Extrait de
# _apply_scenario pour que le mode CLIENT (sim Python) puisse l'appeler à
# la réception du champ "rame2" : sans ça le viewer restait sur son défaut
# rame 1 et les deux cabines apparaissaient inversées par rapport à la 2D
# (retour d'essai 2026-08-03).
#
# La voie prise dans l'évitement est un côté FIXE de la ligne (l'aiguille
# Abt est passive : c'est le profil des boudins de chaque rame qui la
# renvoie toujours du même bord), donc passing_side ne dépend PAS du sens
# de marche — il est appliqué dans le repère du tunnel, pas dans celui du
# conducteur.
func apply_rame(rame2: bool) -> void:
	if cabin != null:
		cabin.passing_side = +1.0 if rame2 else -1.0
		cabin.set_train_number(2 if rame2 else 1)
	if cabin_ghost != null:
		cabin_ghost.passing_side = -1.0 if rame2 else +1.0
		cabin_ghost.set_train_number(1 if rame2 else 2)
	# Propage le choix de rame aux représentations liées à rame 1 par défaut :
	# le câble (quel brin suit la cabine) et le mini-profil de ligne (quelle
	# étiquette porte le point piloté).
	if track != null:
		track.driver_is_rame2 = rame2
	if hud != null:
		hud.set_driver_rame2(rame2)


# Banc : vérifie le chemin bouton tactile → Input.action_press →
# is_action_pressed → consigne → vitesse, en conduite MANUELLE.
func _drivetest() -> void:
	await get_tree().create_timer(1.0).timeout
	physics.request_depart()
	print("[DriveTest] request_depart lancé")
	while not physics.trip_started:
		await get_tree().create_timer(0.5).timeout
	# --s=<m> : saute à cette abscisse (captures du tunnel en pleine ligne)
	# --vue=1 : vue extérieure (mesure du coût des passagers, tous dessinés)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--s="):
			physics.s = float(a.substr(4))
			physics.s_prev_step = physics.s
		elif a.begins_with("--vue=") and cabin != null:
			cabin.set_view(int(a.substr(6)))
	print("[DriveTest] trip démarré — action_press(speed_up) 6 s")
	Input.action_press("speed_up")
	await get_tree().create_timer(6.0).timeout
	Input.action_release("speed_up")
	print("[DriveTest] speed_cmd=%.2f v=%.2f (attendu : cmd>0.9, v>1)"
		% [physics.speed_cmd, physics.v])

	# Diagnostic : --mesh-stats en arg projet → imprime le nombre de vertices
	# par nœud et le total, puis continue normalement. Sert à vérifier que le
	# chunking/échantillonnage adaptatif tient ses promesses.
	if "--mesh-stats" in OS.get_cmdline_user_args():
		_print_mesh_stats()


func _print_mesh_stats() -> void:
	var totals: Dictionary = {"verts": 0, "meshes": 0, "mm_instances": 0}
	_collect_mesh_stats(self, totals)
	print("[MeshStats] %d MeshInstance3D, %d vertices, %d instances MultiMesh"
		% [totals["meshes"], totals["verts"], totals["mm_instances"]])


func _collect_mesh_stats(node: Node, totals: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var v: int = 0
		for si in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(si)
			if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
				v += arrays[Mesh.ARRAY_VERTEX].size()
		totals["verts"] += v
		totals["meshes"] += 1
		if v > 20000:
			print("[MeshStats]   %-28s %8d verts" % [node.name, v])
	elif node is MultiMeshInstance3D and node.multimesh != null:
		totals["mm_instances"] += node.multimesh.instance_count
	for child in node.get_children():
		_collect_mesh_stats(child, totals)


func _build_state_receiver() -> void:
	state_receiver = StateReceiver.new()
	state_receiver.name = "StateReceiver"
	add_child(state_receiver)
	state_receiver.set_physics(physics)
	state_receiver.cabin = cabin   # bascule de vue pilotée par le PC (O)
	state_receiver.main = self     # application du numéro de rame (1/2)
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
	_build_game_modes()


# Modes DÉFI et PANNES : notation du trajet + écran de collision + le
# sélecteur de panne manuel. Les trois nœuds existent en permanence ;
# seul le mode courant les active (challenge.enabled / scheduler_enabled).
func _build_game_modes() -> void:
	challenge = Challenge.new()
	challenge.name = "Challenge"
	add_child(challenge)
	challenge.setup(physics, fault_manager)

	challenge_panel = ChallengePanel.new()
	challenge_panel.name = "ChallengePanel"
	add_child(challenge_panel)
	challenge_panel.setup(challenge)
	challenge_panel.restart_requested.connect(restart_trip)

	fault_picker = FaultPicker.new()
	fault_picker.name = "FaultPicker"
	add_child(fault_picker)
	fault_picker.setup(fault_manager)

	physics.crash_occurred.connect(_on_crash)


# Collision (mode Défi) : la physique se fige, l'écran tremble, la panique
# passe en annonce d'évacuation — c'est ChallengePanel qui affiche la
# pique et l'avis passager.
func _on_crash(kind: String, speed: float) -> void:
	physics.frozen = true
	if cabin != null:
		cabin.shake(1.4 if kind != "buffer" else 1.2,
			minf(0.55, 0.10 + speed / 22.0))
	# Bande-son de l'accident : fracas (impact ou déraillement), ambiance
	# coupée, puis sting de fin de service — cf. TrainAudio.play_crash.
	if audio != null:
		audio.play_crash(kind)
	if exploitation_log != null:
		exploitation_log.end_trip(false)
	# L'annonce d'évacuation vient APRÈS le sting (le quai réagit une fois
	# le fracas retombé) — sinon les trois se superposent.
	if announcements != null:
		await get_tree().create_timer(6.5).timeout
		if physics.crashed:
			announcements.play_now("evac")


# Nouveau voyage après une collision (bouton NOUVEAU VOYAGE / touche R).
func restart_trip() -> void:
	if physics == null:
		return
	physics.restart_after_crash()
	if fault_manager != null:
		fault_manager.clear_active(true)   # remise en service complète
	if challenge != null:
		challenge.clear_crash()
		challenge.reset_trip()
	if announcements != null:
		announcements.stop_all()
	if audio != null:
		audio.reset_crash()
	apply_rame(_scenario_rame2)
	_prev_finished = false
	_prev_trip_started = false
	_welcome_played = false


## PWA (rendu Compatibility) : ni éclairage indirect, 8 lampes au plus par
## objet — les gares paraissaient dans le noir phares éteints (iPad,
## 07/10/2026). Leurs matériaux reçoivent une luminosité propre (un quart
## de leur couleur) : le hall s'éclaire sans surexposer la cabine, que des
## néons plus forts noyaient.
const REMPLISSAGE_GARE_WEB: float = 0.3


func _remplissage_gares_web() -> void:
	var vus: Dictionary = {}
	for racine in [stations, station_halls, machine_room]:
		if racine == null:
			continue
		for n in (racine as Node).find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n
			var mats: Array = []
			if mi.material_override != null:
				mats.append(mi.material_override)
			if mi.mesh != null:
				for i in range(mi.mesh.get_surface_count()):
					var m: Material = mi.get_surface_override_material(i)
					mats.append(m if m != null else mi.mesh.surface_get_material(i))
			for m in mats:
				if not (m is StandardMaterial3D) or vus.has(m):
					continue
				vus[m] = true
				var sm: StandardMaterial3D = m
				if sm.emission_enabled or sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
					continue
				sm.emission_enabled = true
				sm.emission = sm.albedo_color * REMPLISSAGE_GARE_WEB
				sm.emission_energy_multiplier = 1.0


func _build_machine_room() -> void:
	machine_room = MachineRoomBuilder.new()
	machine_room.name = "MachineRoom"
	add_child(machine_room)
	machine_room.build(tunnel)
	print("[MachineRoom] deux roues d'entraînement ∅ 4160 mm, câble en huit, 3 moteurs CC construits")


func _build_track() -> void:
	track = TrackBuilder.new()
	track.name = "Track"
	add_child(track)
	track.build(tunnel)
	Cabin.tag_layer.call_deferred(track, Cabin.LAYER_VOIE)   # vue extérieure
	print("[Track] rails/dalle/câble construits (longueur=%.0fm)" % PNConstants.LENGTH)


func _build_relief() -> void:
	var t0: int = Time.get_ticks_msec()
	relief = ReliefBuilder.new()
	relief.name = "Relief"
	add_child(relief)
	relief.build(tunnel, perf_manager.cran if perf_manager != null else 0)
	print("[Relief] massif 3D IGN (RGE ALTI + orthophoto) du lac de Tignes à la Grande Motte : lancé en %d ms"
		% (Time.get_ticks_msec() - t0))


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
	print("[StationHalls] gare aval Val Claret (salle d'attente, cloison vitrée, façade 2018)")


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
	sky_mat.ground_color = SOL_CIEL
	sky_mat.sun_disk_scale = 1.0
	sky_mat.energy_multiplier = 1.0
	sky.sky_material = sky_mat
	# PWA (rendu Compatibility) : le ciel physique y sort NOIR — vue
	# extérieure, verrière et baies de la gare du haut (« il fait toujours
	# nuit dans la gare du haut », 07/10/2026), lumière ambiante tirée du
	# ciel. Un ciel procédural (dégradé bleu, horizon clair) le remplace.
	if _compat:
		var proc: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
		proc.sky_top_color = Color(0.22, 0.42, 0.78)
		proc.sky_horizon_color = Color(0.70, 0.78, 0.88)
		proc.ground_horizon_color = SOL_CIEL
		proc.ground_bottom_color = SOL_CIEL
		sky.sky_material = proc
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.background_energy_multiplier = 1.0

	# --- Ambient : modéré (tunnel doit rester lisible sans être un faisceau aveuglant) ---
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.45, 0.50, 0.60)
	env.ambient_light_energy = AMBIENT_ON
	env.ambient_light_sky_contribution = 0.3
	# PWA : le ciel n'y éclairait pas (il sortait noir) et l'aspect du tunnel
	# a été réglé ainsi ; avec le ciel procédural, l'ambiante reste tirée
	# de la seule couleur, au même niveau (70 % : la part hors ciel)
	if _compat:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.45, 0.50, 0.60) * 0.7

	# --- SDFGI (global illumination) -------------------------------------
	# Le poste GPU le plus cher de tout le pipeline — coupé sous high.
	env.sdfgi_enabled = (quality == "high")
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
	# Volumétrique plus subtil (coût froxels × lumières — coupé en low)
	env.volumetric_fog_enabled = (quality != "low")
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
	env.ssr_enabled = (quality != "low")
	env.ssr_max_steps = 40

	# --- Ajustements couleur ---------------------------------------------
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.05

	_env = env
	var we: WorldEnvironment = WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	# (Pas de soleil — retour du 03/10 : « y a pas de soleil, c'est un
	# tunnel ». La lumière directionnelle, sans ombres, éclairait parois,
	# voie et pupitre même éclairage du tunnel coupé. Les halls de gare ont
	# leur propre lumière du jour.)
	# Seule exception : la vue extérieure (vue d'ensemble, parois
	# translucides) garde une lumière de « studio » qui n'éclaire QUE les
	# rames et la voie (couches Cabin.LAYER_RAME / LAYER_VOIE), allumée dans
	# cette vue seulement.
	_ext_light = DirectionalLight3D.new()
	_ext_light.name = "LumiereVueExterieure"
	_ext_light.light_color = Color(1.0, 0.96, 0.88)
	_ext_light.light_energy = 1.2
	_ext_light.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(160.0), 0.0)
	_ext_light.shadow_enabled = false
	_ext_light.light_cull_mask = Cabin.LAYER_RAME | Cabin.LAYER_VOIE
	_ext_light.visible = false
	add_child(_ext_light)


func _build_physics() -> void:
	physics = TrainPhysics.new()
	physics.direction = 1           # départ Val Claret → Glacier
	physics.s = PNConstants.START_S
	physics.v = 0.0
	physics.doors_open = true
	physics.maint_brake = true
	physics.trip_started = false
	physics.lights_head = true      # phares ON au démarrage
	# Charge passagers initiale (montée chargée / contrepoids vide) — sans
	# ça dm = 0 : tension/puissance fausses et compteur pax à 0.
	physics.roll_pax()


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

	# Ghost (rame 2) — visible à s_ghost = MIROIR_S − physics.s, voie droite au passing loop
	cabin_ghost = Cabin.new()
	cabin_ghost.name = "CabinGhost"
	cabin_ghost.is_ghost = true
	cabin_ghost.passing_side = +1.0
	add_child(cabin_ghost)
	cabin_ghost.set_tunnel(tunnel)
	cabin_ghost.set_physics(physics)

	# Vue « salle des machines » (O ×2 / bouton VUE) : caméra libre posée
	# dans la gare amont, elle ne suit pas la rame (demande du 2026-09-30).
	if machine_room != null:
		var cam_mr: MachineRoomCamera = MachineRoomCamera.new()
		cam_mr.name = "CameraSalleMachines"
		add_child(cam_mr)
		cam_mr.setup(machine_room)
		cabin.camera_machines = cam_mr
		cabin.machine_room = machine_room


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
		# Position de RENDU interpolée entre les deux derniers états
		# physiques — supprime la saccade du défilement (rails/tunnel)
		# quand le rendu ne tombe pas pile sur les pas de 1/60 s.
		# + écart élastique de la rame au bout de son brin de câble (en
		# marche comme à l'arrêt : jusqu'à ~50 cm en bas, millimétrique en
		# haut — la longueur de câble déroulée fait le tri)
		# + affaissement d'embarquement (le brin s'allonge sous la charge
		# croissante à quai : la rame « descend doucement » en gare basse)
		physics.s_poulie_render = lerpf(physics.s_prev_step, physics.s,
			clampf(_physics_accum / PHYSICS_DT, 0.0, 1.0))
		physics.s_render = physics.s_poulie_render \
			+ physics.rebound_offset() + physics.boarding_sag_offset()
	else:
		# Mode client : l'état arrive du sim Python (s = poulie, el_x1 =
		# écart élastique de la rame). Retour du 04/10 : « sur un PC moins
		# puissant ça saccade » — le PC chargé envoie ses paquets à rythme
		# irrégulier et la rame avançait par sauts. Entre deux paquets, la
		# position avance avec la vitesse reçue, puis se recale en douceur
		# (0,12 s) sur la position envoyée ; un vrai saut (nouveau voyage,
		# demi-tour) est pris tel quel.
		var age: float = state_receiver.packet_age() if state_receiver != null else 0.0
		var cible: float = physics.s + physics.v * clampf(age, 0.0, 0.15)
		if is_nan(_client_s) or absf(cible - _client_s) > 5.0:
			_client_s = cible
		else:
			_client_s += physics.v * delta
			_client_s += (cible - _client_s) * minf(1.0, delta / 0.12)
		physics.s_poulie_render = _client_s
		physics.s_render = _client_s + physics.el_x1

	# Culling des lumières du tunnel à 2 Hz (les ~230 OmniLight3D pèsent
	# sur le clustering Forward+ et le fog volumétrique même hors champ)
	_light_cull_accum += delta
	if _light_cull_accum >= 0.5:
		_light_cull_accum = 0.0
		# en vue salle des machines, la rame qui compte est celle qui
		# approche de la gare amont, pilotée ou non
		var s_web: float = physics.s
		if cabin != null and cabin.view_mode == Cabin.ViewMode.MACHINES:
			var s_g: float = PNConstants.miroir(physics.s)
			if absf(PNConstants.LENGTH - s_g) < absf(PNConstants.LENGTH - physics.s):
				s_web = s_g
		lights.update_light_culling(physics.s, s_web)

	# Masquage dynamique des brins de câble selon la position des rames
	# (s_render : suit la cabine interpolée, sinon le câble « vibre »
	# d'une frame par rapport à la rame)
	track.update_cable_visibility(physics.s_render, physics.ghost_s_render())
	# Animation des torons (brin gauche = fixe par rapport à rame 1,
	# brin droite = défile à 2×v en référentiel rame 1)
	track.update_cable_phase(physics.s_render, physics.ghost_s_render())
	# Câble rompu : brèche, bouts rétractés, câble retombé sur la longrine
	track.update_cable_rupture(physics.cable_rupture, physics.s_render,
		physics.direction, physics.tension_dan, delta, physics.v)
	# Galets : tournent sous le câble (v / R de la bande), ralentissent
	# seuls une fois le culot passé ; animés autour de la caméra
	var s_cam: float = physics.s_render
	if cabin != null and cabin.view_mode == Cabin.ViewMode.MACHINES:
		s_cam = PNConstants.LENGTH - 20.0
	track.update_galets_rames(physics.s_render, physics.ghost_s_render(), s_cam,
		delta, physics.cable_rupture)
	# Son : vue salle des machines → ambiance de la gare haute
	if audio != null and cabin != null:
		audio.machine_view = cabin.view_mode == Cabin.ViewMode.MACHINES
	if _ext_light != null and cabin != null:
		_ext_light.visible = cabin.view_mode == Cabin.ViewMode.EXTERIOR
	# voyant « Alarmes » et bouton DÉFAUTS de l'écran du pupitre (PWA)
	if fault_manager != null and physics != null and not client_mode:
		physics.alarme_externe = fault_manager.is_active()
	# relief 3D du massif (vue extérieure seulement), translucide le long
	# du tunnel
	# skieur : à l'air libre, c'est le jour (relief, ciel, soleil) ; dans
	# une rame en plein tunnel, le relief ne sert à rien
	var dehors: bool = mode_skieur and skieur != null and skieur.dehors(relief)
	if _ext_light != null and dehors:
		_ext_light.visible = true
	if relief != null and cabin != null:
		var vue_ext: bool = cabin.view_mode == Cabin.ViewMode.EXTERIOR
		var ext: bool = (vue_ext or dehors) and relief.pret
		relief.visible = (vue_ext or (mode_skieur and not _skieur_en_tunnel())) and relief.pret
		relief.montrer_trait(vue_ext)
		# le tunnel se voit à travers le relief opaque (trait ambre) ; plus
		# de silhouette des rames (« enlève complètement cette silhouette
		# jaune, ça laisse des traces », 07/10/2026)
		if ext and physics != null:
			relief.set_rames(physics.s_render, physics.ghost_s_render())
		# le brouillard du tunnel (≈ 250 m de visibilité) noierait tout au
		# loin : en vue extérieure il s'éclaircit avec le recul de la caméra
		if _env != null:
			var k_f: float = (clampf(15.0 / cabin.orbit_dist, 0.0, 1.0) if vue_ext else 0.12) if ext else 1.0
			_env.fog_density = 0.004 * k_f
			_env.volumetric_fog_density = 0.008 * k_f if k_f > 0.3 else 0.0
			_env.fog_sky_affect = 0.0 if ext else 0.5    # ciel bleu dehors
			# sous l'horizon du ciel : gris roche en vue extérieure (caméra
			# sous la montagne : on voit « la roche », pas un vide clair)
			if _env.sky != null and ext != _sol_ext:
				_sol_ext = ext
				var sol: Color = SOL_ROCHE if ext else SOL_CIEL
				if _env.sky.sky_material is PhysicalSkyMaterial:
					(_env.sky.sky_material as PhysicalSkyMaterial).ground_color = sol
				elif _env.sky.sky_material is ProceduralSkyMaterial:
					var ps: ProceduralSkyMaterial = _env.sky.sky_material
					ps.ground_bottom_color = sol
					ps.ground_horizon_color = sol
			# dehors il fait jour, même tunnel éteint
			var ciel: float = 1.0 if (ext or tunnel_lights_on) else 0.0
			if _env.background_energy_multiplier != ciel:
				_env.background_energy_multiplier = ciel
				_energie_ciel(ciel)
	# gare aval : portes coulissantes et panneau des départs
	if station_halls != null and physics != null:
		station_halls.mettre_a_jour(delta, physics)
	# Halls de gare en rendu Compatibility (PWA) : 8 lampes au plus par
	# objet, les grands sols et murs du hall ne recevaient qu'une partie des
	# néons (« la gare du haut semble dans le noir », iPad 07/10/2026, phares
	# éteints) ; le PC, lui, a l'éclairage indirect. La lumière ambiante
	# monte quand la caméra cabine y entre.
	if _env != null and cabin != null and physics != null and tunnel != null:
		var amb: float = AMBIENT_ON if tunnel_lights_on else AMBIENT_OFF
		if _compat and (cabin.view_mode == Cabin.ViewMode.FPV or cabin.view_mode == Cabin.ViewMode.SKIEUR):
			var sr: float = physics.s_render
			if sr > tunnel.station_high_start - 20.0 or sr < tunnel.station_low_end + 20.0:
				amb = AMBIENT_GARE_WEB
		_env.ambient_light_energy = move_toward(_env.ambient_light_energy, amb, delta * 1.5)
	if machine_room != null and cabin != null:
		# panorama photographié depuis la gare : vu des baies de la gare et
		# de la salle des machines seulement ; la vue extérieure a le relief
		machine_room.set_exterieur_lointain(false)
		var cam_e: Camera3D = get_viewport().get_camera_3d()
		var d_hall: float = machine_room.distance_au_hall(cam_e.global_position) \
			if cam_e != null else INF
		machine_room.set_exterieur_visible(cabin.view_mode != Cabin.ViewMode.EXTERIOR
			and not mode_skieur
			and (d_hall < 150.0 or (cabin.view_mode == Cabin.ViewMode.FPV and d_hall < 450.0)))
	if mode_skieur:
		_maj_skieur()
	# numéros des supports : rétroréfléchissants dans les phares (vue cabine)
	if track != null and cabin != null:
		track.set_retro(cabin.head_glow() if cabin.view_mode == Cabin.ViewMode.FPV else 0.0)
	# Rotation des roues motrices et défilement du câble de la salle. Le sens
	# de référence est celui de la rame 1 (son brin entre sur la roue aval
	# quand elle monte) : si l'on conduit la rame 2, la rame 1 descend.
	# Câble rompu : la machinerie freine jusqu'à l'arrêt (update_machine).
	physics.update_machine(track != null and track.driver_is_rame2, delta)
	machine_room.update_rotation(physics.machine_v, delta)
	# … et son câble se détend avec celui du tunnel (retombe sous les roues)
	machine_room.set_cable_slack(track.cable_slack())

	# Sync du plafond de vitesse imposé par la panne courante (s'il y en a une)
	if fault_manager != null:
		physics.speed_cap_external = fault_manager.get_speed_cap()

	# Annonces vocales + log : skip en mode client (Python s'en occupe)
	if not client_mode:
		_update_announcement_triggers()


func _update_announcement_triggers() -> void:
	if announcements == null:
		return

	# Annonce « fermeture des portes » au DÉBUT de la séquence de départ
	# (phase 1 : annonce seule, portes encore ouvertes — la fermeture et
	# le buzzer suivent, chacun son tour).
	if physics.announce_phase_remaining > 0.0 and _prev_announce_remaining <= 0.0:
		announcements.queue("doors_close")
	_prev_announce_remaining = physics.announce_phase_remaining

	# Trip vient de démarrer (départ) → log + arme l'annonce d'approche
	if physics.trip_started and not _prev_trip_started:
		_welcome_played = false
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

	# Portes viennent de s'ouvrir → annonce "sortie des passagers" (arrivée gare).
	# DÉSACTIVÉ (retour d'essai 2026-07-12) : les portes ne s'ouvrent qu'au
	# demi-tour automatique du terminus, donc cette annonce partait
	# systématiquement « juste après le demi-tour » — Kevin l'entendait comme
	# une annonce de panne intempestive. Elle reste diffusable À LA DEMANDE
	# via le bouton ANNONCES (menu tactile). Repasser AUTO_EXIT_ANNOUNCE à
	# true pour restaurer le comportement automatique.
	if AUTO_EXIT_ANNOUNCE and physics.doors_open and not _prev_doors_open:
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

	# Annonce « zone Grande Motte » (fichier 11) : comme dans la réalité et
	# le sim Python, elle passe en APPROCHE FINALE de la gare supérieure
	# (montée, à ANNONCE_ARRIVEE_D m de l'arrêt), une fois par trajet.
	# Retour d'essai Android 2026-07 : l'ancienne version la jouait à
	# l'allumage à quai puis TOUTES LES 30 s → annonce fantôme au boot.
	# RÉACTIVÉE (Kevin 2026-07-24) : c'est LA bonne annonce d'accueil ; le
	# charabia « please do not leave… » venait d'une autre source
	# (ambiance de quai contaminée, corrigée) — approche finale gare haute,
	# une fois par trajet. Diffusable aussi via le bouton ANNONCES.
	# 🔴 06/10/2026 : 54,24 s d'annonce, rampement réduit à 35 m (≈ 49 s) →
	# coupée par l'arrêt ; déclenchée à ANNONCE_ARRIVEE_D de l'arrêt quelle
	# que soit la vitesse, elle finit 3 s avant (annonce_arrivee.sage).
	var d_arret: float = PNConstants.STOP_S - physics.s
	if (physics.trip_started and not _welcome_played
			and physics.direction > 0
			and d_arret > 0.0 and d_arret <= PNConstants.ANNONCE_ARRIVEE_D):
		announcements.queue("welcome")
		_welcome_played = true

	# Reset du flag exit_announced quand on quitte la station
	if not physics.doors_open and _exit_announced_for_stop:
		_exit_announced_for_stop = false

	# Sauvegarde l'état pour la frame suivante
	_prev_doors_open = physics.doors_open
	_prev_trip_started = physics.trip_started
	_prev_direction = physics.direction


func _handle_continuous_input(delta: float) -> void:
	if mode_skieur:
		# le clavier fait marcher le skieur (ZQSD, flèches, Maj) : rien de
		# la conduite ; V bascule 1re / 3e personne
		if Input.is_action_just_pressed("toggle_view") and commandes_skieur != null:
			commandes_skieur.basculer_vue()
		if Input.is_action_just_pressed("pause"):
			_paused = not _paused
		return
	if Input.is_action_pressed("speed_up"):
		physics.speed_cmd = clampf(physics.speed_cmd + speed_cmd_rate * delta, 0.0, 1.0)
	if Input.is_action_pressed("speed_down"):
		physics.speed_cmd = clampf(physics.speed_cmd - speed_cmd_rate * delta, 0.0, 1.0)

	# Frein service : tant que bouton enfoncé. On lève le flag
	# manual_brake_held → le régulateur coupe le couple et met le frein à
	# fond (il ne tire plus contre le frein). Le relâchement rend la main
	# au régulateur (qui redescend brake).
	physics.manual_brake_held = Input.is_action_pressed("brake")

	# Urgence : latch sur press
	if Input.is_action_just_pressed("emergency"):
		physics.emergency = true
		physics.speed_cmd = 0.0

	if Input.is_action_just_pressed("toggle_headlights"):
		physics.lights_head = not physics.lights_head
		cabin.set_headlights(physics.lights_head)
		print("[Headlights] %s" % ["ON" if physics.lights_head else "OFF"])

	if Input.is_action_just_pressed("ready_depart"):
		if physics.arret_elec:
			_flash("Arrêt électrique engagé : le relâcher d'abord")
		elif physics.emergency:
			physics.release_emergency()
			print("[Emergency released]")
		elif not physics.trip_started:
			# Séquence réelle : portes (3,5 s) puis buzzer 6-8 s, la
			# traction ne colle qu'à la fin.
			physics.request_depart()
			print("[Departure sequence] portes puis buzzer")

	if Input.is_action_just_pressed("pause"):
		_paused = not _paused
		print("[Paused] %s" % _paused)

	if Input.is_action_just_pressed("toggle_view"):
		cabin.toggle_view()
		_orbit_touches.clear()   # plus de doigt fantôme d'une vue à l'autre
		_orbit_pinch_dist = 0.0


# Caméra orbitale (vue extérieure) : suivi des doigts pour le pincement.
var _orbit_touches: Dictionary = {}
var _orbit_pinch_dist: float = 0.0


# Pupitre de la vue cabine (06/10/2026, « faudrait pouvoir appuyer sur ces
# boutons ») : clic gauche ou doigt (émulé en souris) sur une commande. En
# _unhandled_input : les boutons tactiles de l'écran passent avant.
var _commande_tenue: String = ""


func _pupitre_clic(pos: Vector2, enfonce: bool) -> bool:
	if not enfonce:
		if _commande_tenue == "":
			return false
		_commande_pupitre(_commande_tenue, false)
		_commande_tenue = ""
		return true
	if cabin == null or cabin.view_mode != Cabin.ViewMode.FPV:
		return false
	var nom: String = cabin.pupitre_commande_sous(pos)
	if nom == "":
		return false
	if _commande_tenue != "":
		_commande_pupitre(_commande_tenue, false)
	_commande_tenue = nom
	_commande_pupitre(nom, true)
	return true


## Action d'une commande du pupitre. Embarqué dans le PC (client_mode), la
## rame est pilotée par le PC : seul le geste est montré.
func _commande_pupitre(nom: String, enfonce: bool) -> void:
	if nom == "marche" and enfonce and not client_mode and physics != null \
			and cabin.pupitre_en_marche() and absf(physics.v) > 0.05:
		_flash("Commutateur général : rame en marche")
		return
	cabin.pupitre_appuyer(nom, enfonce)
	if client_mode or physics == null:
		return
	if nom == "klaxon":
		physics.horn = enfonce
		if audio != null:
			audio.set_horn(enfonce)
		return
	if nom == "rouge_1":
		# URGENCE (gros coup-de-poing) : comme E-STOP ; un nouvel appui le
		# déverrouille
		if enfonce:
			if physics.emergency:
				physics.release_emergency()
			else:
				Input.action_press("emergency")
		else:
			Input.action_release("emergency")
		return
	if nom == "rouge_2":
		# ARRÊT ÉLEC (petit coup-de-poing) : arrêt de service verrouillé,
		# un nouvel appui le relâche
		if enfonce:
			physics.arret_elec = not physics.arret_elec
			_flash("Arrêt électrique engagé" if physics.arret_elec else "Arrêt électrique relâché")
		return
	if nom.begins_with("vite_"):
		# sélecteur −VITE/+VITE : comme les boutons de consigne, tant qu'on
		# le tient
		var action: String = "speed_down" if nom == "vite_moins" else "speed_up"
		if enfonce:
			Input.action_press(action)
		else:
			Input.action_release(action)
		return
	if nom == "montee":
		# MONTÉE = « on est prêt » : comme le bouton PRÊT/DÉPART (relâche
		# l'urgence, sinon lance la séquence de départ) ; allume PRÊT
		if enfonce and not cabin.pupitre_en_marche():
			_flash("Commutateur général sur arrêt")
			return
		if enfonce and physics.arret_elec:
			_flash("Arrêt électrique engagé : le relâcher d'abord")
			return
		if enfonce:
			Input.action_press("ready_depart")
		else:
			Input.action_release("ready_depart")
		return
	if not enfonce:
		return
	match nom:
		# PORTES 1 à 6 = côté gauche en regardant vers le haut (bit 0),
		# 7 à 12 = côté droit (bit 1) — chaque groupe ne commande que son
		# côté ; le dernier côté fermé lance la vraie séquence de fermeture
		"ouverture_0", "ouverture_1":
			var bit: int = 1 << int(nom.right(1))
			if not physics.doors_open:
				physics.portes_cotes = bit
				toggle_doors()
			elif physics.announce_phase_remaining <= 0.0 \
					and physics.door_phase_remaining <= 0.0:
				physics.portes_cotes |= bit
		"fermeture_0", "fermeture_1":
			var bit: int = 1 << int(nom.right(1))
			if physics.doors_open and (physics.portes_cotes & bit) != 0:
				if physics.portes_cotes == bit:
					toggle_doors()
				else:
					physics.portes_cotes &= ~bit
		"cabine", "compartiment":
			toggle_cabin_lights()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _pupitre_clic(event.position, event.pressed):
			get_viewport().set_input_as_handled()
			return
	# Pannes + auto-exploitation + inversion de sens
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_K:
			basculer_skieur()
			return
		if mode_skieur and not (event.keycode in [KEY_F1, KEY_F2, KEY_F3, KEY_J, KEY_C]):
			return                # les lettres font marcher le skieur
		if event.keycode == KEY_F1 and fault_manager != null:
			fault_manager.trigger_random()
		elif event.keycode == KEY_F2 and fault_manager != null:
			fault_manager.clear_active()
		elif event.keycode == KEY_F3 and auto_operator != null:
			auto_operator.toggle()
		elif event.keycode == KEY_I:
			do_reverse()
		elif event.keycode == KEY_D:
			toggle_doors()
		elif event.keycode == KEY_M:
			# Rotation des modes, comme la touche M du PC.
			var order: Array = ["normal", "challenge", "panne"]
			var idx: int = order.find(run_mode)
			set_run_mode(order[(maxi(idx, 0) + 1) % order.size()])
			print("[Mode] %s" % run_mode)
		elif event.keycode == KEY_F and run_mode == "panne" \
				and fault_picker != null:
			fault_picker.toggle()
		elif event.keycode == KEY_R:
			# Nouveau voyage — UNIQUEMENT quand le service est terminé :
			# après une collision (mode Défi) ou une panne catastrophique.
			# Sinon un R malencontreux annulerait un trajet en cours.
			if physics.crashed or (fault_manager != null
					and fault_manager.is_active_catastrophic()):
				restart_trip()
			else:
				print("[R] ignoré — trajet en cours (R sert après une collision "
					+ "ou une panne catastrophique)")
		elif event.keycode == KEY_J:
			toggle_tunnel_lights()
		elif event.keycode == KEY_C:
			toggle_cabin_lights()
		elif event.keycode == KEY_O and cabin != null:
			# Cycle cabine → extérieure → salle des machines (aussi piloté
			# par la touche O du sim PC via le state dict "view3d").
			cabin.toggle_view()
		_orbit_touches.clear()   # plus de doigt fantôme d'une vue à l'autre
		_orbit_pinch_dist = 0.0


# --- Caméra orbitale : drag 1 doigt = angle, pincement = zoom, clic
# gauche maintenu = angle, molette = zoom. Dans _input (PAS
# _unhandled_input) : priorité maximale, aucun Control ne peut avaler le
# geste (retour d'essai Safari 2026-07-24 : « marche pas dans la PWA »).
# Actif uniquement en vue EXTÉRIEURE ; les taps sur les boutons tactiles
# restent fonctionnels (on ne consomme pas l'événement).
func _input(event: InputEvent) -> void:
	if cabin == null:
		return
	# 🔴 Le suivi des doigts se fait dans TOUS les modes de vue. Un doigt posé
	# en vue extérieure et relâché en vue cabine — le bouton VUE lui-même,
	# qui bascule sur l'appui — restait mémorisé : le drag suivant passait
	# pour un pincement à deux doigts et ne tournait plus rien (« en gare ça
	# tourne, en ligne plus possible », retour 2026-09-26).
	if event is InputEventScreenTouch:
		if event.pressed:
			_orbit_touches[event.index] = event.position
		else:
			_orbit_touches.erase(event.index)
		_orbit_pinch_dist = 0.0
		return
	var mr_view: bool = cabin.view_mode == cabin.ViewMode.MACHINES \
		and cabin.camera_machines != null
	if cabin.view_mode != cabin.ViewMode.EXTERIOR and not mr_view:
		return
	if event is InputEventScreenDrag:
		_orbit_touches[event.index] = event.position
		if _orbit_touches.size() == 1:
			_view_rotate(mr_view, event.relative.x, event.relative.y)
		elif _orbit_touches.size() >= 2:
			var pts: Array = _orbit_touches.values()
			var d: float = (pts[0] as Vector2).distance_to(pts[1] as Vector2)
			if _orbit_pinch_dist > 1.0 and d > 1.0:
				_view_zoom(mr_view, _orbit_pinch_dist / d)
			_orbit_pinch_dist = d
			# salle des machines : deux doigts qui glissent ensemble =
			# déplacer le point visé (chaque doigt compte pour moitié)
			if mr_view:
				cabin.camera_machines.pan_by(event.relative.x * 0.5, event.relative.y * 0.5)
	elif event is InputEventMagnifyGesture:
		# Safari/iPadOS et trackpads livrent parfois le pincement en
		# geste de magnification plutôt qu'en deux ScreenTouch.
		_view_zoom(mr_view, 1.0 / maxf(event.factor, 0.01))
	elif event is InputEventPanGesture:
		_view_rotate(mr_view, event.delta.x * 2.0, event.delta.y * 2.0)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_view_zoom(mr_view, 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_view_zoom(mr_view, 1.1)
	elif event is InputEventMouseMotion and _orbit_touches.is_empty():
		# Souris réelle uniquement : sur tactile, Godot émet AUSSI des
		# événements souris émulés — le dict de touches actives les
		# neutralise (pas de double rotation).
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_view_rotate(mr_view, event.relative.x, event.relative.y)
		elif mr_view and event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			cabin.camera_machines.pan_by(event.relative.x, event.relative.y)


func _view_rotate(mr_view: bool, dx: float, dy: float) -> void:
	if mr_view:
		cabin.camera_machines.rotate_by(dx, dy)
	else:
		cabin.orbit_rotate(dx, dy)


func _view_zoom(mr_view: bool, factor: float) -> void:
	if mr_view:
		cabin.camera_machines.zoom(factor)
	else:
		cabin.orbit_zoom(factor)


# Inversion du sens de marche (touche I / bouton INVERSER) — cas d'usage :
# panne en plein tunnel, on fait demi-tour pour revenir à la gare. Comme le
# PC : arrêt total requis, annonce « retour en gare », puis PRÊT/DÉPART
# relance (sans buzzer en tunnel). En mode AUTO, l'automate se recale et
# relance le départ tout seul.
## Portes à la demande (bouton PORTES / touche D). Refus affiché au HUD.
func toggle_doors() -> void:
	if client_mode or physics == null:
		return
	var msg: String = physics.toggle_doors()
	if msg != "":
		print("[Portes] " + msg)
		_flash(msg)


func _flash(msg: String) -> void:
	if hud != null and hud.has_method("flash"):
		hud.flash(msg)


func do_reverse() -> void:
	if client_mode or physics == null:
		return
	var en_gare: bool = physics.at_station()
	if not physics.reverse_trip():
		print("[Reverse] refusé — rame pas à l'arrêt (v=%.2f m/s)" % physics.v)
		return
	# « Retour en gare » : SEULEMENT en plein tunnel (situation anormale),
	# comme le PC (reverse_trip : « reversing at a terminus is the normal
	# turnaround and silently flips the direction ») — retour de Kevin du
	# 07/10/2026 : « quand j'inverse en gare après un trajet normal, j'ai
	# l'annonce anormale »
	if announcements != null:
		announcements.stop_all()
		if not en_gare:
			announcements.play_now("return_station")
	if exploitation_log != null:
		exploitation_log.end_trip(false)
	# En Défi, le demi-tour vaut une remarque des passagers (port des
	# REVERSE_QUIPS du PC) — affichée dans le bandeau de résultat.
	if run_mode == "challenge" and challenge != null:
		challenge.result_lines = [PNQuips.pick_quip(PNQuips.REVERSE, challenge.lang)]
		challenge.last_score = -1.0
		challenge.review = {}
		challenge.result_t = 6.0
		challenge.result_ready.emit({"quip_only": true})
	if auto_operator != null and auto_operator.enabled:
		auto_operator._enter_initial_state()


# --- Skieur jouable (07/10/2026) ---------------------------------------------------
# « un skieur capable de monter les escaliers des gares et de marcher à
# l'intérieur sans passer au travers du plancher, des murs, des portes ou du
# wagon, qui peut marcher dans le wagon, voyager dans le funiculaire et
# aller au poste de pilotage » (Kevin). Bouton SKIEUR, touche K.

## Bascule conduite ↔ skieur.
func basculer_skieur() -> void:
	if client_mode or tunnel == null or cabin == null:
		return
	if mode_skieur:
		_sortir_skieur()
	else:
		_entrer_skieur()


func _entrer_skieur() -> void:
	if relief == null or not relief.pret:
		_flash("Le relief se prépare encore : réessayer dans un instant")
		return
	if collisions == null:
		collisions = CollisionsJeu.new()
		collisions.name = "Collisions"
		add_child(collisions)
		var zones: Array = []
		for s in [0.0, PNConstants.LENGTH]:
			var o: Vector3 = tunnel.transform_at(s).origin
			zones.append(Rect2(o.x - 250.0, o.z - 250.0, 500.0, 500.0))
		collisions.construire(self, zones)
	if skieur == null:
		skieur = SkieurJoueur.new()
		skieur.name = "Skieur"
		add_child(skieur)
		skieur.conduite_demandee.connect(_skieur_conduit)
		commandes_skieur = CommandesSkieur.new()
		commandes_skieur.name = "CommandesSkieur"
		commandes_skieur.skieur = skieur
		commandes_skieur.main = self
		add_child(commandes_skieur)
	if _skieur_au_poste:
		# il se lève du siège du conducteur
		_skieur_au_poste = false
		var seat: Node3D = cabin.interior_root.get_node_or_null("DriverSeatBase") as Node3D
		var p: Vector3 = seat.global_position + seat.global_transform.basis.z * 0.7 if seat != null \
			else skieur.global_position
		skieur.activer(p, cabin.global_transform.basis.get_euler().y)
	elif not _skieur_place and station_halls != null and station_halls.gare_aval != null:
		# départ d'en bas : sur la place ; d'en haut : à table sur la terrasse
		var gare: Node = station_halls.gare_amont if _depart_haut and station_halls.gare_amont != null \
			else station_halls.gare_aval
		var dep: Array = gare.point_depart()
		skieur.activer(dep[0], dep[1])
		skieur.refuge = dep[0]
		_skieur_place = true
	elif _skieur_voiture != null and is_instance_valid(_skieur_voiture):
		# il était dans une rame : on le repose à sa place dans la voiture,
		# où qu'elle soit rendue (« je suis revenu au skieur et je suis tombé
		# sous le tunnel », Kevin, 07/10/2026)
		skieur.activer(_skieur_voiture.global_transform * _skieur_local, skieur.cam_yaw)
		skieur.support = _skieur_voiture
		skieur._support_xf = _skieur_voiture.global_transform
	else:
		skieur.activer(skieur.global_position, skieur.cam_yaw)
	_skieur_voiture = null
	mode_skieur = true
	cabin.set_view(Cabin.ViewMode.SKIEUR)
	skieur.camera.make_current()
	commandes_skieur.visible = true
	# le funiculaire tourne tout seul pendant qu'on marche
	if auto_operator != null and not auto_operator.enabled and run_mode == "normal":
		auto_operator.toggle()
	_mode_skieur_ui(true)
	_flash("Skieur : joystick ou ZQSD pour marcher, glisser pour regarder")


func _sortir_skieur() -> void:
	mode_skieur = false
	PorteAuto.presences = []
	# dans une rame : on retient sa place dans la voiture
	_skieur_voiture = null
	if skieur != null and skieur.support != null:
		_skieur_voiture = skieur.support
		_skieur_local = skieur.support.global_transform.affine_inverse() * skieur.global_position
	if auto_operator != null:
		auto_operator.retenue = false
		auto_operator.a_bord = false
	if audio != null:
		audio.ecoute = 0
	if skieur != null:
		skieur.desactiver()
	if commandes_skieur != null:
		commandes_skieur.visible = false
	cabin.set_view(Cabin.ViewMode.FPV)
	_mode_skieur_ui(false)


func _mode_skieur_ui(on: bool) -> void:
	if hud != null and hud.has_method("set_mode_skieur"):
		hud.set_mode_skieur(on)
	var touch: Node = get_node_or_null("TouchControls")
	if touch != null and touch.has_method("set_mode_skieur"):
		touch.set_mode_skieur(on)


## CONDUIRE : il s'assied au poste de la rame qu'il occupe.
func _skieur_conduit() -> void:
	_skieur_au_poste = true
	_sortir_skieur()
	if auto_operator != null and auto_operator.enabled:
		auto_operator.toggle()
	_flash("Au poste de conduite — SKIEUR pour se lever")


## Le skieur est dans une gare : salle, quais, couloirs (pas sur la place,
## la terrasse ou la neige).
func _skieur_en_gare() -> bool:
	if skieur == null or tunnel == null:
		return false
	var p: Vector3 = skieur.global_position
	for e in [[0.0, -32.0, 46.0, 15.0], [PNConstants.LENGTH, -50.0, MachineRoomBuilder.HALL_DEPTH + 0.3, 7.6]]:
		var xf: Transform3D = tunnel.transform_at(e[0])
		var rel: Vector3 = p - xf.origin
		var le_long: float = rel.dot(-xf.basis.z)
		if le_long > e[1] and le_long < e[2] and absf(rel.dot(xf.basis.x)) < e[3] \
				and absf(rel.dot(xf.basis.y) - le_long * 0.08) < 9.0:
			return not skieur.dehors(relief)
	return false


## Le skieur est dans une rame en plein tunnel (loin des deux gares).
func _skieur_en_tunnel() -> bool:
	if skieur == null or skieur.support == null:
		return false
	var s_r: float = physics.s_render if cabin.is_ancestor_of(skieur.support) else physics.ghost_s_render()
	return s_r > 80.0 and s_r < PNConstants.LENGTH - 80.0


func _maj_skieur() -> void:
	if skieur == null or commandes_skieur == null:
		return
	# portes automatiques : elles s'ouvrent devant le skieur
	PorteAuto.presences = [skieur.global_position]
	# l'automate attend le skieur qui est en gare sans être monté, et part
	# peu après qu'il est monté
	if auto_operator != null:
		auto_operator.a_bord = skieur.support != null
		auto_operator.retenue = skieur.support == null and _skieur_en_gare()
	if audio != null:
		audio.ecoute = 0 if skieur.support != null else (1 if _skieur_en_gare() else 2)
	# CONDUIRE : à côté du siège du poste de la rame pilotée
	var pres: bool = false
	if skieur.support != null and cabin.is_ancestor_of(skieur.support) and cabin.interior_root != null:
		var seat: Node3D = cabin.interior_root.get_node_or_null("DriverSeatBase") as Node3D
		if seat != null:
			pres = skieur.global_position.distance_to(seat.global_position) < 1.8
	commandes_skieur.set_conduite_possible(pres)
