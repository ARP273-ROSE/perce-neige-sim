class_name StateReceiver
extends Node
## Mode CLIENT : reçoit l'état physique depuis le sim Python v1.9.1 via
## UDP localhost:7777. Met à jour le TrainPhysics local à chaque packet.
##
## Format paquet : 1 ligne JSON terminée par \n.
## Champs attendus :
##   { "s": float, "v": float, "direction": int (-1/+1),
##     "doors_open": bool, "trip_started": bool, "finished": bool,
##     "tension_dan": float, "power_kw": float,
##     "speed_cmd": float, "lights_head": bool, "lights_cabin": bool,
##     "emergency": bool, "rame2": bool (optional — rame pilotée 1/2),
##     "active_fault": string (optional) }
##
## Lancement Godot :
##   godot --path /path/to/project -- --client [--port=7777]
## Le `--` sépare les args Godot des args projet.

const DEFAULT_PORT: int = 7777
# Lien avec le sim Python : le sim envoie l'état à 60 Hz en MODE_RUN et un
# heartbeat {"hb":1} à 1 Hz sinon. Silence > LINK_WARN_S → overlay d'alerte ;
# silence > LINK_QUIT_S → le viewer se ferme tout seul (sinon il resterait
# orphelin à consommer du GPU si Python crashe sans faire stop()).
const LINK_WARN_S: float = 3.0
const LINK_QUIT_S: float = 30.0

var udp: PacketPeerUDP = null
## Retour vers le PC (port + 1) : boutons du pupitre 3D, mode skieur. Sans
## lui, un clic sur le pupitre de la vue 3D embarquée ne faisait que
## montrer le geste (Kevin, 07/10/2026 : « sur le PC les boutons marchent
## mais il ne se passe rien ensuite »).
var _retour: PacketPeerUDP = null
var _last_skieur: int = -1
var _last_skieur_vue: int = -1
var _last_skieur_ski: int = -1
var port: int = DEFAULT_PORT
var physics: TrainPhysics = null
var fault_manager: FaultManager = null
var cabin: Cabin = null            # bascule FPV/extérieure pilotée par le PC
var main: Node = null              # pour appliquer le numéro de rame (1/2)
var _last_ext_view: bool = false
var _last_view3d: int = -1
# -1 = pas encore reçu → le PREMIER paquet applique toujours le choix, même
# si c'est rame 1 (sinon un viewer relancé en cours de session garderait le
# côté de la rame précédente).
var _last_rame2: int = -1
var _last_packet_time: float = 0.0
var _packet_count: int = 0
var _overlay: Label = null


func _ready() -> void:
	# Parse les args projet (après --)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--port="):
			var p: int = int(arg.substr(7))
			if p >= 1024 and p <= 65535:
				port = p
			else:
				push_warning("[StateReceiver] --port=%s invalide — fallback %d"
					% [arg.substr(7), DEFAULT_PORT])

	udp = PacketPeerUDP.new()
	var err: int = udp.bind(port, "127.0.0.1")
	if err != OK:
		push_warning("[StateReceiver] Bind UDP %d échoué : %s" % [port, error_string(err)])
		return
	print("[StateReceiver] Écoute UDP localhost:%d (mode CLIENT — sim Python pilote)" % port)
	_retour = PacketPeerUDP.new()
	_retour.set_dest_address("127.0.0.1", port + 1)


## Message au PC, une ligne JSON (lu par GodotBridge.poll_messages).
func envoyer(d: Dictionary) -> void:
	if _retour != null:
		_retour.put_packet((JSON.stringify(d) + "\n").to_utf8_buffer())


func set_physics(p: TrainPhysics) -> void:
	physics = p


func set_fault_manager(fm: FaultManager) -> void:
	fault_manager = fm


func _process(_delta: float) -> void:
	if udp == null or physics == null:
		return
	# Vide la file UDP, applique le DERNIER packet (anti-lag : si plusieurs
	# packets sont en attente, seul le plus récent est appliqué)
	var latest: Dictionary = {}
	while udp.get_available_packet_count() > 0:
		var raw: PackedByteArray = udp.get_packet()
		var line: String = raw.get_string_from_utf8().strip_edges()
		if line.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			latest = parsed
			_packet_count += 1
	if not latest.is_empty():
		_apply(latest)
		_last_packet_time = Time.get_ticks_msec() / 1000.0
		# Diag minimal : log au 1er packet + tous les 300 packets (~5s à 60Hz)
		# pour vérifier que la cabine reçoit bien la position depuis Python.
		if _packet_count == 1 or _packet_count % 300 == 0:
			print("[StateReceiver] packet #%d : s=%.1f m, v=%.2f m/s, trip=%s, doors=%s"
				% [_packet_count, physics.s, physics.v,
				   physics.trip_started, physics.doors_open])
	_update_link_status()


# Helpers de lecture typée : un JSON valide mais mal typé ({"s": [1]}…) ne
# doit pas déclencher une erreur de conversion Variant à chaque paquet —
# champ absent ou mal typé → valeur courante conservée.
static func _f(d: Dictionary, k: String, cur: float) -> float:
	var v: Variant = d.get(k)
	return float(v) if (v is float or v is int) else cur


static func _i(d: Dictionary, k: String, cur: int) -> int:
	var v: Variant = d.get(k)
	return int(v) if (v is float or v is int) else cur


static func _b(d: Dictionary, k: String, cur: bool) -> bool:
	var v: Variant = d.get(k)
	return bool(v) if v is bool else cur


func _apply(d: Dictionary) -> void:
	# Update direct des champs (la physics locale est court-circuitée)
	physics.s = _f(d, "s", physics.s)
	# qualité 3D choisie au PC (menu Affichage) : auto / high / medium / low
	if d.has("qualite_3d") and main != null and main.get("perf_manager") != null:
		main.perf_manager.set_mode(str(d["qualite_3d"]))
	# élasticité du câble (sim PC ≥ 1.15.51) : écarts des rames à la poulie
	physics.el_x1 = _f(d, "el_x1", 0.0)
	physics.el_x2 = _f(d, "el_x2", 0.0)
	physics.v = _f(d, "v", physics.v)
	physics.direction = _i(d, "direction", physics.direction)
	physics.doors_open = _b(d, "doors_open", physics.doors_open)
	# le PC envoie l'état VISUEL des vantaux (doors_visual_open), calé sur
	# le clip sonore : la cabine l'anime tel quel
	physics.door_leaves_open = physics.doors_open
	# remplissage déclaré côté PC : la cabine affiche autant de passagers
	physics.pax_car1 = _i(d, "pax_car1", physics.pax_car1)
	physics.pax_car2 = _i(d, "pax_car2", physics.pax_car2)
	physics.ghost_pax = _i(d, "ghost_pax", physics.ghost_pax)
	physics.trip_started = _b(d, "trip_started", physics.trip_started)
	physics.finished = _b(d, "finished", physics.finished)
	if d.has("tension_dan"):
		physics.tension_dan = _f(d, "tension_dan", physics.tension_dan)
		physics.tension_dan_disp = physics.tension_dan
	if d.has("power_kw"):
		physics.power_kw = _f(d, "power_kw", physics.power_kw)
		physics.power_kw_disp = physics.power_kw
	physics.speed_cmd = _f(d, "speed_cmd", physics.speed_cmd)
	physics.lights_head = _b(d, "lights_head", physics.lights_head)
	physics.lights_cabin = _b(d, "lights_cabin", physics.lights_cabin)
	physics.emergency = _b(d, "emergency", physics.emergency)
	# pupitre (écran Pro-face, voyants) — sim PC ≥ 1.15.78
	physics.horn = _b(d, "horn", false)
	physics.arret_elec = _b(d, "arret_elec", false)
	if d.has("ready"):
		physics.pret_externe = 1 if _b(d, "ready", false) else 0
		physics.pret_autre_externe = _b(d, "ghost_ready", true)
	physics.maint_brake = _b(d, "maint_brake", physics.maint_brake)
	physics.brake = _f(d, "brake", physics.brake)
	physics.alarme_externe = d.has("active_fault") and str(d["active_fault"]) != ""
	# Éclairage du tunnel commandé par le sim PC (touche J)
	if d.has("tunnel_lights") and main != null and main.has_method("set_tunnel_lights"):
		var tl: bool = _b(d, "tunnel_lights", true)
		if tl != bool(main.tunnel_lights_on):
			main.set_tunnel_lights(tl)
	# Câble rompu (PC, mode Défi ou panne) : sans ce relais, la 3D
	# laissait le câble intact, l'autre rame continuer en miroir et la
	# machinerie suivre la rame qui dévale (retour du 01/10). La position
	# figée de l'autre rame vient du PC (ghost_s).
	if d.has("cable_rupture"):
		var cr: bool = _b(d, "cable_rupture", false)
		physics.cable_rupture = cr
		if not cr:
			physics.ghost_locked_s = -1.0
		elif d.has("ghost_s"):
			physics.ghost_locked_s = _f(d, "ghost_s", PNConstants.miroir(physics.s))
		elif physics.ghost_locked_s < 0.0:
			physics.ghost_locked_s = PNConstants.miroir(physics.s)
	# Mute global relayé par le sim PC (touche N) : le viewer embarqué a
	# son propre moteur audio — sans ce relais, couper le son côté PC
	# laissait la 3D sonore. Bus Master muté/démuté, la lecture continue.
	if d.has("muted"):
		var m: bool = _b(d, "muted", false)
		if AudioServer.is_bus_mute(0) != m:
			AudioServer.set_bus_mute(0, m)
	# Volume général du sim PC (F7/F8) : gain linéaire sur le bus Master.
	if d.has("volume"):
		var db: float = linear_to_db(maxf(_f(d, "volume", 1.0), 0.0001))
		if absf(AudioServer.get_bus_volume_db(0) - db) > 0.05:
			AudioServer.set_bus_volume_db(0, db)
	# Rame pilotée (1/2) choisie au menu du sim Python. Détermine la voie
	# prise dans l'évitement Abt (gauche pour rame 1, droite pour rame 2),
	# le brin de câble attaché à la cabine et les étiquettes R1/R2. Sans ce
	# relais, le viewer restait sur son défaut « rame 1 » et croisait du
	# mauvais côté quand la 2D disait rame 2.
	if d.has("rame2"):
		var r2: bool = _b(d, "rame2", false)
		if int(r2) != _last_rame2:
			_last_rame2 = int(r2)
			if main != null and main.has_method("apply_rame"):
				main.apply_rame(r2)
				print("[StateReceiver] rame pilotée = %d (voie %s)"
					% [2 if r2 else 1, "droite" if r2 else "gauche"])
	# Vue extérieure orbitale commandée par la touche O du sim PC.
	# Appliquée SUR CHANGEMENT seulement : entre deux bascules PC, la vue
	# reste modifiable localement (touche O du viewer focalisé).
	# "view3d" (0 cabine, 1 extérieure, 2 salle des machines) depuis la
	# v1.15.29 ; "ext_view" (booléen) reste lu pour un sim plus ancien.
	if d.has("view3d"):
		var vm: int = clampi(int(d["view3d"]), 0, 2)
		if vm != _last_view3d:
			_last_view3d = vm
			# (pas sous les pieds du skieur : il a sa propre caméra)
			if cabin != null and cabin.view_mode != vm \
					and not (main != null and main.get("mode_skieur") == true):
				cabin.set_view(vm)
	elif d.has("ext_view"):
		var ev: bool = _b(d, "ext_view", false)
		if ev != _last_ext_view:
			_last_ext_view = ev
			if cabin != null \
					and (cabin.view_mode == Cabin.ViewMode.EXTERIOR) != ev:
				cabin.set_view(Cabin.ViewMode.EXTERIOR if ev else Cabin.ViewMode.FPV)
	# Skieur (touche F9 / bouton SKIEUR du PC) : le PC décide, appliqué SUR
	# CHANGEMENT ; touches de marche tenues côté PC (bits : 1 avant, 2
	# arrière, 4 gauche, 8 droite, 16 courir)
	if d.has("skieur") and main != null and main.has_method("skieur_externe"):
		var sk: int = 1 if _b(d, "skieur", false) else 0
		if sk != _last_skieur:
			_last_skieur = sk
			main.skieur_externe(sk == 1)
	if main != null and main.get("skieur") != null:
		main.skieur.touches_ext = _i(d, "skieur_touches", 0)
	# chausser / déchausser (touche E du PC en mode skieur) : compteur
	var ns: int = _i(d, "skieur_ski", 0)
	if ns != _last_skieur_ski:
		if _last_skieur_ski >= 0 and main != null and main.has_method("basculer_ski"):
			main.basculer_ski()
		_last_skieur_ski = ns
	# 1re / 3e personne (touche V du PC en mode skieur) : compteur d'appuis
	var nv: int = _i(d, "skieur_vue", 0)
	if nv != _last_skieur_vue:
		if _last_skieur_vue >= 0 and main != null and main.get("commandes_skieur") != null \
				and main.mode_skieur:
			main.commandes_skieur.basculer_vue()
		_last_skieur_vue = nv
	# Panne active : déclenche localement pour effet visuel + son
	if d.has("active_fault") and fault_manager != null and d["active_fault"] is String:
		var fid: String = d["active_fault"]
		if fid != "" and fault_manager.get_active_id() != fid:
			fault_manager.trigger(fid)
		elif fid == "" and fault_manager.is_active():
			fault_manager.clear_active()


func _update_link_status() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	# _last_packet_time = 0 tant que rien n'est reçu → le délai court depuis
	# le démarrage du viewer, ce qui couvre aussi le cas « bind raté / sim
	# jamais lancé » (viewer inutile → autant se fermer).
	var silence: float = now - _last_packet_time
	if silence > LINK_QUIT_S:
		print("[StateReceiver] silence UDP > %d s — fermeture du viewer" % int(LINK_QUIT_S))
		get_tree().quit()
		return
	var warn: bool = _packet_count > 0 and silence > LINK_WARN_S
	if warn and _overlay == null:
		_build_overlay()
	if _overlay != null:
		_overlay.visible = warn


func _build_overlay() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_overlay = Label.new()
	_overlay.text = "⚠ Signal du simulateur perdu…"
	_overlay.add_theme_font_size_override("font_size", 28)
	_overlay.add_theme_color_override("font_color", Color(1.0, 0.55, 0.2))
	_overlay.add_theme_color_override("font_outline_color", Color.BLACK)
	_overlay.add_theme_constant_override("outline_size", 6)
	_overlay.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_overlay.position.y = 40.0
	layer.add_child(_overlay)


# Indique si on a reçu au moins un packet récent (utile pour debug / fallback)
## Âge (s) du dernier paquet reçu du sim PC : sert à extrapoler la position
## entre deux paquets (main.gd, lissage du rendu en mode client).
func packet_age() -> float:
	if _packet_count == 0:
		return 0.0
	return Time.get_ticks_msec() / 1000.0 - _last_packet_time


func is_connected_recently() -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	return _packet_count > 0 and (now - _last_packet_time) < 2.0
