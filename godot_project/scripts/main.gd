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
var sortie_secours: SortieSecours = null
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
## vue 3D embarquée dans le PC : sons du quai et du dehors (le PC joue ceux
## de la rame), dernier état du skieur envoyé au PC
var sons_skieur: SonsSkieur = null
## pistes balisées, fantôme des descentes de Kevin (à ski)
var domaine: DomaineSkiable = null
## la boucle toute seule (bouton AUTO du skieur, touche X)
var skieur_auto: SkieurAuto = null
var _skieur_en_attente: bool = false   # collisions en préparation : on entre dès qu'elles sont prêtes
var _t_skieur_attente: int = 0         # début de l'attente (ms)
var _t_skieur_prep_msg: float = 0.0    # dernier message d'avancement


## Message d'attente du skieur : HUD 3D (persistant) et PC (relais).
func _skieur_prep(texte: String, ms: int = -1) -> void:
	if texte != "":
		_flash(texte)
	if client_mode and state_receiver != null:
		state_receiver.envoyer({"skieur_prep": texte, "ms": ms})
var _paliers_en_gare: bool = true
var _seuils_fermes: int = -1            # seuils des portes en collision (portes fermées) ; -1 inconnu
var _skieur_etat_envoye: Array = []
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
## Skieur dehors : sous l'horizon du ciel, une brume claire (le bord du
## relief lointain n'y laisse plus une bande noire) ; soleil des gares
## (GareAmont.SOLEIL, comme l'ombrage du relief) ; ambiante forte (la neige
## renvoie la lumière).
const SOL_HIVER: Color = Color(0.78, 0.83, 0.90)
const AMBIENT_DEHORS: float = 1.0
var _sol_ext: int = 0                  # 0 ciel, 1 roche (vue extérieure), 2 hiver (skieur dehors)
var _soleil_skieur: bool = false
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
	# consigne à 100 % dès le départ hors Défi (en Défi, c'est au conducteur)
	physics.speed_cmd = 0.0 if physics.challenge_mode else 1.0
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
	# PRÊT/DÉPART refuse une consigne à 0 (comme le PC) : on la monte avant
	physics.speed_cmd = 1.0
	var refus: String = physics.request_depart()
	print("[DriveTest] request_depart lancé%s" % ((" — refusé : " + refus) if refus != "" else ""))
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
	relief.amenageurs.append(_amenagement_sortie_secours)
	relief.build(tunnel, perf_manager.cran if perf_manager != null else 0)
	print("[Relief] massif 3D IGN (RGE ALTI + orthophoto) du lac de Tignes à la Grande Motte : lancé en %d ms"
		% (Time.get_ticks_msec() - t0))


## Galerie de secours, de la chambre du tunnel à la piste : dès que les
## altitudes du relief sont lues (son sol les suit), avant les pièces fines
## (son aire et son remblai en font partie).
func _amenagement_sortie_secours() -> Dictionary:
	if sortie_secours != null or tunnel == null or relief == null:
		return {}
	sortie_secours = SortieSecours.new()
	sortie_secours.name = "SortieSecours"
	add_child(sortie_secours)
	sortie_secours.construire(tunnel, relief)
	Cabin.tag_layer.call_deferred(sortie_secours, Cabin.LAYER_VOIE)
	print("[SortieSecours] galerie de %d points, portail à %.1f m" % [sortie_secours.sol.size(), sortie_secours.portail.y])
	return sortie_secours.amenagement_relief(relief)


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
		# images longues à répétition (iPad ancien, navigateur) : le retard
		# est jeté, jamais rattrapé en rafale (rame à 4×, buzzers décalés)
		_physics_accum = minf(_physics_accum, PHYSICS_DT)
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
	# Son : vue salle des machines → ambiance de la gare haute ; gare de
	# l'auditeur (buzzers) et machinerie sur les quais du haut (skieur)
	if audio != null and cabin != null:
		audio.machine_view = cabin.view_mode == Cabin.ViewMode.MACHINES
		audio.gare_ecoute = _gare_ecoute()
		audio.gain_machinerie = _gain_machinerie()
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
	if _ext_light != null and dehors != _soleil_skieur:
		_soleil_skieur = dehors
		if dehors:
			_ext_light.basis = Basis.looking_at(-GareAmont.SOLEIL.normalized(), Vector3.UP)
		else:
			_ext_light.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(160.0), 0.0)
	if relief != null and cabin != null:
		var vue_ext: bool = cabin.view_mode == Cabin.ViewMode.EXTERIOR
		var ext: bool = (vue_ext or dehors) and relief.pret
		relief.visible = (vue_ext or (mode_skieur and not _skieur_en_tunnel())) and relief.pret
		if domaine != null:
			domaine.visible = mode_skieur and relief.visible
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
			var etat_sol: int = (2 if dehors else 1) if ext else 0
			if _env.sky != null and etat_sol != _sol_ext:
				_sol_ext = etat_sol
				var sol: Color = [SOL_CIEL, SOL_ROCHE, SOL_HIVER][etat_sol]
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
		if mode_skieur and skieur != null and _soleil_skieur:
			amb = AMBIENT_DEHORS
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
	if _skieur_en_attente and collisions != null:
		if collisions.pret:
			_entrer_skieur()
		else:
			_t_skieur_prep_msg += delta
			if _t_skieur_prep_msg >= 1.0:
				_t_skieur_prep_msg = 0.0
				_skieur_prep("Préparation du décor du skieur… %d %% (%d s)" % [
					int(collisions.progres() * 100.0), (Time.get_ticks_msec() - _t_skieur_attente) / 1000])
	if mode_skieur:
		_maj_skieur()
	elif skieur_auto != null and skieur != null and skieur.actif:
		_maj_skieur()        # BOUCLE en coulisse : le skieur vit, l'exploitation l'attend
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
	# au régulateur (qui redescend brake). Comme le PC (:8499), le frein
	# tenu ABAISSE aussi la consigne (0,8/s) : relâché, la rame ne
	# réaccélère plus toute seule vers la consigne d'avant (audit
	# 07/10/2026 : FREIN 5 s à 12 m/s → 7 m/s, puis retour à 12 tout seul).
	physics.manual_brake_held = Input.is_action_pressed("brake")
	if physics.manual_brake_held:
		physics.speed_cmd = maxf(0.0, physics.speed_cmd - 0.8 * delta)

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
		elif physics.emergency and not (fault_manager != null
				and fault_manager.is_active_catastrophic()):
			# urgence relâchée par PRÊT/DÉPART — sauf voyage terminé par
			# une panne catastrophique (seul R relance, comme le PC)
			physics.release_emergency()
			print("[Emergency released]")
		elif not physics.trip_started:
			# Séquence réelle : annonce, portes, confirmation de l'autre
			# rame puis buzzer 6-8 s, la traction ne colle qu'à la fin.
			# Refus (urgence, panne catastrophique, défaut porte, consigne
			# à 0…) affiché au HUD, comme les messages du PC.
			var refus: String = physics.request_depart()
			if refus != "":
				_flash(refus)
			else:
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
	if client_mode:
		# embarqué dans le PC : c'est le PC qui pilote la rame, on lui
		# transmet l'appui (« sur le PC les boutons marchent mais il ne se
		# passe rien ensuite », Kevin, 07/10/2026) ; clé EN MARCHE sur
		# arrêt : MONTÉE refusée, comme dans la PWA
		var refuse: bool = nom == "montee" and enfonce and not cabin.pupitre_en_marche()
		if state_receiver != null and not refuse:
			state_receiver.envoyer({"pupitre": nom, "enfonce": enfonce})
		return
	if physics == null:
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
		# K dans la PWA ; F9 dans la vue 3D du PC (K y est le klaxon)
		if event.keycode == (KEY_F9 if client_mode else KEY_K):
			basculer_skieur()
			return
		if mode_skieur and event.keycode == KEY_E:
			basculer_ski()
			return
		if mode_skieur and event.keycode == KEY_X:
			basculer_skieur_auto()
			return
		if mode_skieur and event.keycode == KEY_U:     # U : issUe de secours (I = inverser le sens)
			evacuer()
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
		elif event.keycode == KEY_J or event.keycode == KEY_C:
			# vue 3D du PC : c'est le PC qui tient ces états (le paquet suivant
			# écraserait une bascule locale) → on lui passe la touche
			if client_mode:
				if state_receiver != null:
					state_receiver.envoyer({"touche": "J" if event.keycode == KEY_J else "C"})
			elif event.keycode == KEY_J:
				toggle_tunnel_lights()
			else:
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
	if cabin.view_mode == cabin.ViewMode.FPV and not mode_skieur:
		# loupe sur le pupitre : molette ou pincement (cf. Cabin.loupe)
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				cabin.loupe_molette(1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				cabin.loupe_molette(-1)
		elif event is InputEventMagnifyGesture:
			cabin.loupe_molette(1 if event.factor > 1.0 else -1)
		return
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

## Bascule conduite ↔ skieur. Dans la vue 3D du PC, c'est le PC qui décide
## (touche F9, bouton SKIEUR) : on le lui demande.
func basculer_skieur() -> void:
	if client_mode:
		if state_receiver != null:
			state_receiver.envoyer({"skieur_basculer": true})
		return
	if tunnel == null or cabin == null:
		return
	if mode_skieur:
		# la BOUCLE continue en coulisse quand on quitte la vue skieur pour
		# changer de vue (Kevin, 09/10/2026 : « le mode boucle se désactive si
		# je quitte le mode skieur afin de changer de vue, il ne faudrait pas »)
		_sortir_skieur(skieur_auto != null)
	else:
		_entrer_skieur()


## Exploitation automatique depuis le HUD du skieur (Kevin, 07/10/2026 :
## « rajoute la possibilité d'activer / désactiver le mode auto même en mode
## skieur ») : sur la version Web l'automate local, sur le PC la touche X du
## PC (c'est lui qui tient l'exploitation).
func basculer_exploitation(on: bool) -> void:
	if client_mode:
		if state_receiver != null and on != _exploitation_pc:
			state_receiver.envoyer({"touche": "X"})
		return
	if auto_operator != null and auto_operator.enabled != on and run_mode == "normal":
		auto_operator.toggle()


## AUTO du skieur (bouton AUTO, touche X) : la boucle complète toute seule.
func basculer_skieur_auto() -> void:
	if skieur == null or not mode_skieur or domaine == null:
		return
	if skieur_auto == null:
		# la boucle a besoin du funiculaire en exploitation automatique :
		# c'est le seul cas où le skieur l'enclenche lui-même
		if client_mode:
			if state_receiver != null and not _exploitation_pc:
				state_receiver.envoyer({"touche": "X"})
		elif auto_operator != null and not auto_operator.enabled:
			auto_operator.toggle()
		skieur_auto = SkieurAuto.new()
		skieur_auto.demarrer(self)
		commandes_skieur.message("AUTO : il fait la boucle tout seul (AUTO pour reprendre la main)", 4.0)
	else:
		skieur_auto.arreter()
		skieur_auto = null
	commandes_skieur.set_auto(skieur_auto != null)


## Chausser / déchausser (bouton CHAUSSER, touche E ; E du PC relayée).
func basculer_ski() -> void:
	# la BOUCLE en coulisse chausse aussi hors de la vue skieur (09/10/2026 :
	# « il fait demi-tour tout le temps, allers-retours sans fin, ne chausse
	# jamais » — refusé ici, l'étape SKI retombait sur VERS_DEPART)
	if skieur == null or not (mode_skieur or skieur_auto != null):
		return
	var refus: String = skieur.basculer_ski()
	commandes_skieur.set_chausse(skieur.chausse)
	if refus != "":
		commandes_skieur.message(refus)
	elif skieur.chausse:
		commandes_skieur.message("Joystick : pointez où aller (haut = tout droit), vers vous = chasse-neige ; glisser à droite de l'écran = regarder"
			if DisplayServer.is_touchscreen_available() else
			"Q / D pour tourner, Z pour pousser, S chasse-neige, Maj schuss", 4.0)


## Issues de secours de la face (Kevin, 07/10/2026 : « de part et d'autre
## de la vitre frontale, les parties jaunes cerclées de noir sont des issues
## de secours et ça s'en va en cas d'évacuation. Donc en cas d'arrêt dans le
## tunnel, rajoute la possibilité d'enlever ces parties, de marcher sur
## l'escalier en partie droite du tunnel quand on regarde vers le haut et
## ensuite de retourner en gare à pied ou de sortir par la sortie de
## secours au milieu »). Possible dans une rame ARRÊTÉE EN TUNNEL ; on passe
## par le trou, on descend sur la voie, l'escalier de service ramène en
## gare ou à la galerie (bouton ÉVACUER, touche U — I est « inverser »).
func evacuation_possible() -> bool:
	if not mode_skieur or skieur == null or not skieur.actif or skieur.support == null:
		return false
	var c: Cabin = _rame_du_skieur()
	if c == null or c.issues_retirees or absf(physics.v) > 0.05:
		return false
	return _skieur_en_tunnel()


func _rame_du_skieur() -> Cabin:
	if skieur == null or skieur.support == null:
		return null
	if cabin != null and cabin.is_ancestor_of(skieur.support):
		return cabin
	if cabin_ghost != null and cabin_ghost.is_ancestor_of(skieur.support):
		return cabin_ghost
	return null


func evacuer() -> void:
	if not evacuation_possible():
		if commandes_skieur != null:
			commandes_skieur.message("Issues de secours : seulement dans une rame arrêtée en tunnel")
		return
	var c: Cabin = _rame_du_skieur()
	c.retirer_issues(true)
	if collisions != null:
		collisions.set_issues(c, true)
		collisions.assurer_autour(skieur.global_position)
	if commandes_skieur != null:
		commandes_skieur.message("Issues de secours retirées : par le trou, sur la voie ; l'escalier de droite ramène en gare ou à la galerie du milieu", 7.0)


## Issues remises quand la rame est de nouveau à quai, portes ouvertes
## (ou quand on quitte le skieur).
func _maj_issues(forcer: bool = false) -> void:
	for c in [cabin, cabin_ghost]:
		if c == null or not c.issues_retirees:
			continue
		var s_r: float = physics.s if c == cabin else physics.ghost_s_render()
		var a_quai: bool = s_r <= PNConstants.START_S + 5.0 or s_r >= PNConstants.STOP_S - 5.0
		if forcer or (a_quai and physics.doors_open):
			c.retirer_issues(false)
			if collisions != null:
				collisions.set_issues(c, false)


## Vue 3D du PC : le PC allume ou éteint le mode skieur (StateReceiver).
func skieur_externe(on: bool) -> void:
	if tunnel == null or cabin == null:
		return
	if on and not mode_skieur:
		_entrer_skieur()
		if not mode_skieur and not _skieur_en_attente and state_receiver != null:
			state_receiver._last_skieur = -1     # relief pas prêt : on réessaiera
	elif not on and mode_skieur:
		_sortir_skieur()


func _entrer_skieur() -> void:
	if relief == null or not relief.pret:
		_flash("Le relief se prépare encore : réessayer dans un instant")
		return
	if collisions == null:
		collisions = CollisionsJeu.new()
		collisions.name = "Collisions"
		collisions.budget_us = 14000 if client_mode else CollisionsJeu.BUDGET_US
		add_child(collisions)
		var zones: Array = []
		for s in [0.0, PNConstants.LENGTH]:
			var o: Vector3 = tunnel.transform_at(s).origin
			zones.append(Rect2(o.x - 250.0, o.z - 250.0, 500.0, 500.0))
		if sortie_secours != null and sortie_secours.pret:
			zones.append(sortie_secours.rect_terrain())
		collisions.construire(self, zones)
	if not collisions.pret:
		# par tranches sur quelques images (pas de gel) : on entre dès que
		# c'est prêt (_process) ; le message reste affiché, avec
		# l'avancement, et le PC le reçoit (Kevin, 08/10/2026 : « on ne sait
		# pas si ça marche ou pas, il n'y a pas de message »)
		if not _skieur_en_attente:
			_skieur_en_attente = true
			_t_skieur_attente = Time.get_ticks_msec()
			_skieur_prep("Préparation du décor du skieur…")
		return
	if _skieur_en_attente:
		var ms: int = Time.get_ticks_msec() - _t_skieur_attente
		print("[Skieur] décor prêt en %d ms" % ms)
		_skieur_prep("", ms)
	_skieur_en_attente = false
	if skieur == null:
		skieur = SkieurJoueur.new()
		skieur.name = "Skieur"
		add_child(skieur)
		skieur.relief = relief
		skieur.conduite_demandee.connect(_skieur_conduit)
		skieur.chute.connect(func() -> void:
			if commandes_skieur != null:
				commandes_skieur.message("Chute ! CHAUSSER (E) pour rechausser", 5.0))
		commandes_skieur = CommandesSkieur.new()
		commandes_skieur.name = "CommandesSkieur"
		commandes_skieur.skieur = skieur
		commandes_skieur.main = self
		add_child(commandes_skieur)
	if skieur_auto != null and skieur.actif:
		# la BOUCLE tournait en coulisse : on le retrouve où il en est
		var sup: Node3D = skieur.support
		skieur.activer(skieur.global_position, skieur.cam_yaw)
		if sup != null and is_instance_valid(sup):
			skieur.support = sup
			skieur._support_xf = sup.global_transform
	elif _skieur_au_poste:
		# il se lève du siège du conducteur — DANS la voiture de tête, où
		# qu'elle soit rendue (Kevin, 08/10/2026 : « en repassant en mode
		# skieur à l'arrivée, le skieur est tout seul au milieu du tunnel » :
		# le nœud du siège, fusionné avec l'intérieur, n'existait plus et
		# l'on retombait sur l'ancienne position monde)
		_skieur_au_poste = false
		skieur.activer(_position_poste(), cabin.global_transform.basis.get_euler().y)
		if not cabin._interior_cars.is_empty():
			skieur.support = cabin._interior_cars[0]
			skieur._support_xf = skieur.support.global_transform
	elif not _skieur_place and station_halls != null and station_halls.gare_aval != null:
		if client_mode:
			_depart_haut = physics.s > PNConstants.LENGTH * 0.5   # rame du PC en haut
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
	if client_mode and sons_skieur == null:
		sons_skieur = SonsSkieur.new()
		sons_skieur.name = "SonsSkieur"
		add_child(sons_skieur)
		sons_skieur.physics = physics
	_skieur_etat_envoye = []
	# commandes de conduite tenues au moment de la bascule (FREIN, +VITESSE,
	# Espace…) : relâchées, sinon elles restent « tenues » tout le mode skieur
	physics.manual_brake_held = false
	for a in ["brake", "speed_up", "speed_down", "emergency"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)
	# l'hiver : neige, relief ombré, pistes damées et balisées
	if domaine == null:
		domaine = DomaineSkiable.new()
		domaine.name = "DomaineSkiable"
		add_child(domaine)
		domaine.construire(relief)
	relief.set_hiver(1.0)
	commandes_skieur.set_chausse(skieur.chausse)
	mode_skieur = true
	cabin.set_view(Cabin.ViewMode.SKIEUR)
	skieur.camera.make_current()
	commandes_skieur.visible = true
	# Passer en skieur NE TOUCHE PAS à l'exploitation : automatique ou non,
	# on reste comme avant (Kevin, 08/10/2026 : « dès que je passe en mode
	# skieur ça repasse en exploitation auto, du coup pendant l'évacuation
	# le funi redémarre et m'écrase » ; auparavant, 07/10 : « le mode auto
	# est forcé et se déclenche alors que je suis encore dehors »). Seule
	# aide : à quai portes fermées, hors voyage, on les ouvre pour monter.
	if not client_mode and physics.at_station() and not physics.trip_started \
			and not physics.doors_open:
		toggle_doors()
	_mode_skieur_ui(true)
	_flash("Skieur : joystick ou ZQSD pour marcher, glisser pour regarder")


## `garder_boucle` : la BOUCLE (skieur automatique) continue en coulisse —
## le skieur reste actif et visible, portes automatiques, retenue de
## l'exploitation et garde-fous compris ; seuls la vue, le HUD et l'écoute
## reviennent à la cabine. On le retrouve où il en est en revenant.
func _sortir_skieur(garder_boucle: bool = false) -> void:
	mode_skieur = false
	var boucle: bool = garder_boucle and skieur_auto != null and skieur != null
	if not boucle:
		_maj_issues(true)
		if skieur_auto != null:
			skieur_auto.arreter()
			skieur_auto = null
			if commandes_skieur != null:
				commandes_skieur.set_auto(false)
		PorteAuto.presences = []
	# dans une rame : on retient sa place dans la voiture (pas en boucle : il
	# bouge pendant qu'on regarde ailleurs)
	_skieur_voiture = null
	if not boucle and skieur != null and skieur.support != null:
		_skieur_voiture = skieur.support
		_skieur_local = skieur.support.global_transform.affine_inverse() * skieur.global_position
	if not boucle:
		if auto_operator != null:
			auto_operator.retenue = false
			auto_operator.a_bord = false
			auto_operator.bloque = false
		_voie_occupee = false
		if physics != null:
			physics.voie_occupee = false
		_dans_tunnel = false
	if _bogies_caches != null and is_instance_valid(_bogies_caches):
		_bogies_caches.set_bogies_visibles(true)
	_bogies_caches = null
	if audio != null:
		audio.ecoute = 0
	if sons_skieur != null:
		sons_skieur.ecoute = 0
	if announcements != null:
		announcements.set_ecoute_skieur(0)
	if relief != null:
		relief.set_hiver(0.0)
	if domaine != null:
		domaine.visible = false
	if skieur != null:
		skieur.touches_ext = 0
		if not boucle:
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


## Garde-fous du skieur (08/10/2026). (1) À pied, une rame EN MARCHE qui
## l'atteint le percute : retour au refuge — pas « embarqué » par la caisse
## (« je me suis pris l'autre rame en pleine tête, ça m'a fait monter à
## bord »). (2) À bord, passé sous le plancher (fente, pénétration), il est
## reposé dessus. (3) À bord, roues et châssis de bogie de SA rame sont
## cachés : ils dépassent dans la voiture.
func _securite_skieur() -> void:
	if cabin == null or skieur == null:
		return
	var car_len: float = cabin.train_length / float(cabin.car_count)
	if skieur.support == null:
		if absf(physics.v) > 0.3:
			for c in [cabin, cabin_ghost]:
				if c == null:
					continue
				for car in c._car_roots:
					var loc: Vector3 = (car as Node3D).global_transform.affine_inverse() * skieur.global_position
					if absf(loc.x) < 1.70 and absf(loc.z) < car_len * 0.5 + 0.3 \
							and loc.y > -2.8 and loc.y < 2.2:
						_skieur_percute()
						return
	elif is_instance_valid(skieur.support):
		var loc2: Vector3 = skieur.support.global_transform.affine_inverse() * skieur.global_position
		if loc2.y < TrainBodyBuilder.Y_FLOOR - 0.10 and absf(loc2.x) < 1.15 \
				and absf(loc2.z) < car_len * 0.5 - 0.7:
			loc2.y = TrainBodyBuilder.Y_FLOOR + Cabin.STEP_LIFT + 0.12
			skieur.global_position = skieur.support.global_transform * loc2
			skieur.velocity = Vector3.ZERO
			print("[Skieur] passé sous le plancher : reposé (x %.2f, z %.2f)" % [loc2.x, loc2.z])
	var r: Cabin = _rame_du_skieur()
	if r != _bogies_caches:
		if _bogies_caches != null and is_instance_valid(_bogies_caches):
			_bogies_caches.set_bogies_visibles(true)
		_bogies_caches = r
		if r != null:
			r.set_bogies_visibles(false)


## À moins de 4,5 m de l'axe du tunnel (balayage tous les 25 m puis au
## mètre) ou de 3 m du sol de la galerie de secours.
func _pres_du_tunnel(p: Vector3) -> bool:
	if tunnel != null:
		var best: float = INF
		var sb: float = 0.0
		var s: float = 0.0
		while s <= PNConstants.LENGTH:
			var d: float = tunnel.transform_at(s).origin.distance_squared_to(p)
			if d < best:
				best = d
				sb = s
			s += 25.0
		s = maxf(0.0, sb - 25.0)
		var s1: float = minf(PNConstants.LENGTH, sb + 25.0)
		while s <= s1:
			var d2: float = tunnel.transform_at(s).origin.distance_squared_to(p)
			if d2 < best:
				best = d2
				sb = s
			s += 1.0
		# les 80 m aux deux bouts sont les gares (quais, salles, terrasse :
		# « en sortant de la gare du haut, à la porte de la terrasse, il croit
		# que je suis dans le tunnel », Kevin, 08/10/2026) : pas le tunnel
		if best < 4.5 * 4.5 and sb > 80.0 and sb < PNConstants.LENGTH - 80.0:
			return true
	if sortie_secours != null and sortie_secours.pret and sortie_secours.sol.size() > 1:
		for i in range(1, sortie_secours.sol.size()):
			var q: Vector3 = Geometry3D.get_closest_point_to_segment(p, sortie_secours.sol[i - 1], sortie_secours.sol[i])
			if q.distance_to(p) < 3.0:
				return true
	return false


func _skieur_percute() -> void:
	var ou: Vector3 = skieur.refuge if skieur.refuge != Vector3.ZERO else skieur.dernier_sol
	if ou == Vector3.ZERO:
		return
	skieur.global_position = ou + Vector3(0.0, 0.3, 0.0)
	skieur.velocity = Vector3.ZERO
	skieur.support = null
	if commandes_skieur != null:
		commandes_skieur.message("Percuté par la rame ! Retour en gare", 6.0)
	print("[Skieur] percuté par une rame en marche (v %.1f m/s)" % physics.v)


## CONDUIRE : il s'assied au poste de la rame qu'il occupe.
func _skieur_conduit() -> void:
	_skieur_au_poste = true
	_sortir_skieur()
	if client_mode and state_receiver != null:
		# le PC sort du mode skieur et rend la conduite (fin de son AUTO)
		state_receiver.envoyer({"skieur_conduire": true})
	if auto_operator != null and auto_operator.enabled:
		auto_operator.toggle()
	_flash("Au poste de conduite — SKIEUR pour se lever")


## Devant le siège du conducteur, dans la voiture de tête de la rame
## pilotée (le nœud du siège s'il existe encore, sinon 2,4 m derrière le
## nez de la voiture, au milieu).
func _position_poste() -> Vector3:
	var seat: Node3D = null
	if cabin.interior_root != null:
		seat = cabin.interior_root.get_node_or_null("DriverSeatBase") as Node3D
	if seat != null:
		return seat.global_position + seat.global_transform.basis.z * 0.7
	if cabin._interior_cars.is_empty():
		return skieur.global_position
	var v0: Node3D = cabin._interior_cars[0]
	var car_len: float = cabin.train_length / float(cabin.car_count)
	return v0.global_transform * Vector3(0.0, TrainBodyBuilder.Y_FLOOR + 0.3, -car_len * 0.5 + 2.4)


## Le skieur est dans une gare : salle, quais, couloirs (pas sur la place,
## la terrasse ou la neige). 0 : non, 1 : gare basse, 2 : gare haute.
var _zones_gare: Array = [[0.0, -32.0, 46.0, 15.0],
	[PNConstants.LENGTH, -50.0, MachineRoomBuilder.HALL_DEPTH + 0.3, 7.6]]
var _gare_skieur: int = 0                 # mis à jour par _maj_skieur
var _t_zone: float = 0.0                  # collisions à la demande (tunnel à pied)
var _exploitation_pc: bool = false        # exploitation auto du PC (état reçu)
var _voie_occupee: bool = false           # skieur à pied sur la voie : rame immobilisée
var _dans_tunnel: bool = false            # à moins de 4,5 m de l'axe du tunnel ou de 3 m de la galerie
var _t_dans_tunnel: float = 9.0           # recalculé toutes les secondes (balayage de l'axe)
var _bogies_caches: Cabin = null          # rame dont roues et bogies sont cachés (skieur à bord)
var _gain_mach_envoye: float = -1.0       # dernier gain machinerie envoyé au PC


## Gare où se trouve l'auditeur, pour les buzzers de quai (cf. TrainAudio.
## gare_ecoute) : skieur à pied → sa gare ; skieur dans une rame → la gare
## où cette rame est à quai ; vue salle des machines → la gare haute ;
## sinon (conduite) la gare où la rame pilotée est à quai.
func _gare_ecoute() -> int:
	if mode_skieur and skieur != null and skieur.actif:
		if skieur.support == null:
			return _gare_skieur
		var s_r: float = physics.s
		if cabin_ghost != null and cabin_ghost.is_ancestor_of(skieur.support):
			s_r = physics.ghost_s_render()
		if s_r <= PNConstants.START_S + 5.0:
			return 1
		return 2 if s_r >= PNConstants.STOP_S - 5.0 else 0
	if cabin != null and cabin.view_mode == Cabin.ViewMode.MACHINES:
		return 2
	if physics.s <= PNConstants.START_S + 5.0:
		return 1
	return 2 if physics.s >= PNConstants.STOP_S - 5.0 else 0


## Gain (0-1) de la salle des machines entendu par le skieur à pied en gare
## haute : −6 dB par doublement de la distance à la machinerie au-delà de
## 4 m, plancher −24 dB (audit_physique/son_gare_haute.sage).
func _gain_machinerie() -> float:
	if not (mode_skieur and skieur != null and skieur.actif and skieur.support == null) \
			or _gare_skieur != 2 or machine_room == null:
		return 0.0
	var d: float = machine_room.distance_au_hall(skieur.global_position)
	return clampf(4.0 / maxf(d, 4.0), 0.063, 1.0)
var _presence: Array = [Vector3.ZERO]
var _seat: Node3D = null
var _t_info: float = 1.0


func _skieur_en_gare() -> bool:
	return _gare_du_skieur() > 0


func _gare_du_skieur() -> int:
	if skieur == null or tunnel == null:
		return 0
	var p: Vector3 = skieur.global_position
	for k in range(_zones_gare.size()):
		var e: Array = _zones_gare[k]
		var xf: Transform3D = tunnel.transform_at(e[0])
		var rel: Vector3 = p - xf.origin
		var le_long: float = rel.dot(-xf.basis.z)
		if le_long > e[1] and le_long < e[2] and absf(rel.dot(xf.basis.x)) < e[3] \
				and absf(rel.dot(xf.basis.y) - le_long * 0.08) < 9.0:
			return 0 if skieur.dehors(relief) else k + 1
	return 0


## Le skieur est dans une rame en plein tunnel (loin des deux gares).
func _skieur_en_tunnel() -> bool:
	if skieur == null or skieur.support == null:
		return false
	var s_r: float = physics.s_render if cabin.is_ancestor_of(skieur.support) else physics.ghost_s_render()
	return s_r > 80.0 and s_r < PNConstants.LENGTH - 80.0


## |x| dans le repère de la voiture sous lequel le skieur est « dedans » :
## paroi du tube à 1,64 m, vantaux contre elle, capsule de 0,14 m
const SKIEUR_DEDANS_X: float = 1.25


func _maj_skieur() -> void:
	if skieur == null or commandes_skieur == null:
		return
	# portes automatiques : elles s'ouvrent devant le skieur
	_presence[0] = skieur.global_position
	PorteAuto.presences = _presence
	# l'automate attend le skieur qui est en gare sans être monté, et ferme
	# les portes dès qu'il est dedans — passé la ligne des portes : debout
	# dans l'embrasure, il est encore « en gare »
	if skieur_auto != null:
		skieur_auto.tick(get_process_delta_time())
	# paliers de quai des portes : en gare seulement (en tunnel, de la porte
	# on descend sur la passerelle — sortie de secours)
	if collisions != null and physics != null:
		var rames_en_gare: bool = physics.s < PNConstants.START_S + 60.0 or physics.s > PNConstants.STOP_S - 60.0
		if rames_en_gare != _paliers_en_gare:
			_paliers_en_gare = rames_en_gare
			collisions.set_paliers_quai(rames_en_gare)
		# seuils des portes : portes fermées seulement
		var fermes: int = 0 if physics.doors_open else 1
		if fermes != _seuils_fermes:
			_seuils_fermes = fermes
			collisions.set_seuils(fermes == 1)
	# à ski : vitesse, piste, course contre le fantôme (texte à 5 Hz)
	if skieur.chausse and domaine != null:
		var dt: float = get_process_delta_time()
		domaine.suivre(skieur, dt)
		_t_info += dt
		if _t_info >= 0.2:
			_t_info = 0.0
			var pi: Array = domaine.piste_sous(skieur.global_position, 1.0)
			var info: String = "%d km/h" % roundi(skieur.vitesse_ski() * 3.6)
			if str(pi[0]) != "" or int(pi[1]) >= 0:
				info += " · %s%s" % [pi[0], (" (%s)" % PistesDonnees.NOMS_COULEURS[pi[1]]) if int(pi[1]) >= 0 else ""]
			if domaine.chrono >= 0.0:
				info += " · %s" % DomaineSkiable._mmss(domaine.chrono)
			commandes_skieur.set_info(info)
		if domaine.resultat != "":
			commandes_skieur.message(domaine.resultat, 8.0)
			domaine.resultat = ""
	_gare_skieur = _gare_du_skieur()
	var en_gare: bool = _gare_skieur > 0
	var dedans: bool = false
	if skieur.support != null:
		var loc: Vector3 = skieur.support.global_transform.affine_inverse() * skieur.global_position
		dedans = absf(loc.x) < SKIEUR_DEDANS_X
	# à pied dans le tunnel (évacuation) : la rame reste là tant qu'il n'a
	# pas rejoint une gare ou la piste ; les collisions suivent ses pas.
	# « Dans le tunnel » = à moins de 4,5 m de l'axe du tunnel ou de 3 m de
	# la galerie de secours, À PIED — plus « sous la surface » : à ski, le
	# relief traversé par endroits disait « dans le tunnel » et immobilisait
	# le funi (Kevin, 08/10/2026 : « ce qui est faux »)
	if skieur.support != null or skieur.chausse:
		_dans_tunnel = false
		_t_dans_tunnel = 9.0
	else:
		_t_dans_tunnel += get_process_delta_time()
		if _t_dans_tunnel > 1.0:
			_t_dans_tunnel = 0.0
			_dans_tunnel = _pres_du_tunnel(skieur.global_position)
	var a_pied_tunnel: bool = skieur.support == null and not skieur.chausse and not en_gare and _dans_tunnel
	if skieur.support == null and collisions != null:
		_t_zone += get_process_delta_time()
		if _t_zone > 1.0:
			_t_zone = 0.0
			collisions.assurer_autour(skieur.global_position)
	# à pied sur la voie (tunnel, galerie) : la rame est IMMOBILISÉE, sans
	# limite de temps — l'exploitation automatique attend, tout départ est
	# refusé, le régulateur tient (Kevin, 08/10/2026 : « le funi ne devrait
	# pas pouvoir repartir une fois l'évacuation lancée ; il est reparti, je
	# me suis pris l'autre rame en pleine tête »)
	# hors des gares, à pied : il peut se hisser sur un rebord (GRIMPE_MAX)
	skieur.grimpe = skieur.support == null and not en_gare
	if a_pied_tunnel != _voie_occupee:
		_voie_occupee = a_pied_tunnel
		if not client_mode:
			physics.voie_occupee = a_pied_tunnel
		commandes_skieur.message("Skieur sur la voie : la rame est immobilisée" if a_pied_tunnel
			else "Voie libre : la rame peut repartir", 4.0)
	_maj_issues()
	_securite_skieur()
	commandes_skieur.set_evacuation_possible(evacuation_possible())
	commandes_skieur.set_exploitation(_exploitation_pc if client_mode else (auto_operator != null and auto_operator.enabled))
	var retenue: bool = (not dedans and (skieur.support != null or en_gare)) \
		or a_pied_tunnel or (skieur_auto != null and skieur_auto.descend())
	# ce qu'il entend : 0 rame, 1 gare basse, 2 dehors, 3 gare haute, 4 tunnel
	var ec: int = 0
	if skieur.support == null:
		ec = 4 if a_pied_tunnel else (3 if _gare_skieur == 2 else (1 if _gare_skieur == 1 else 2))
	if auto_operator != null:
		auto_operator.a_bord = dedans
		auto_operator.retenue = retenue
		auto_operator.bloque = a_pied_tunnel
	if not mode_skieur:
		ec = 0           # boucle en coulisse : on écoute depuis la cabine
	if audio != null:
		audio.ecoute = ec
	if sons_skieur != null:
		sons_skieur.ecoute = ec
	# la sono de la rame pilotée : dans cette rame, atténuée sur le quai de
	# la gare où elle est, coupée ailleurs (dehors, tunnel, autre rame)
	if announcements != null and mode_skieur:
		var gare_rame: int = 1 if physics.s <= PNConstants.START_S + 5.0 \
			else (2 if physics.s >= PNConstants.STOP_S - 5.0 else 0)
		var e_ann: int = 2
		# dans l'une OU l'autre rame : les deux ont leur sono, qui dit la même
		# chose (Kevin, 09/10/2026 : « dans la rame non choisie pour piloter,
		# pas d'annonces »)
		if skieur.support != null and _rame_du_skieur() != null:
			e_ann = 0
		elif skieur.support == null and ((ec == 1 and gare_rame == 1) or (ec == 3 and gare_rame == 2)):
			e_ann = 1
		announcements.set_ecoute_skieur(e_ann)
	if client_mode and state_receiver != null:
		# même règle d'attente et de départ pour l'exploitation AUTO du PC,
		# et le gain de la machinerie (quais du haut), au 1/20 près
		var gm: float = snappedf(_gain_machinerie(), 0.05)
		var etat: Array = [dedans, retenue, ec, gm, a_pied_tunnel, skieur_auto != null]
		if etat != _skieur_etat_envoye:
			_skieur_etat_envoye = etat
			state_receiver.envoyer({"skieur_etat": etat})
	# CONDUIRE : à côté du siège du poste de la rame pilotée
	var pres: bool = false
	if skieur.support != null and cabin.is_ancestor_of(skieur.support):
		pres = skieur.global_position.distance_to(_position_poste()) < 1.8
	commandes_skieur.set_conduite_possible(pres)
