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
##     "emergency": bool, "active_fault": string (optional) }
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
var port: int = DEFAULT_PORT
var physics: TrainPhysics = null
var fault_manager: FaultManager = null
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
	physics.v = _f(d, "v", physics.v)
	physics.direction = _i(d, "direction", physics.direction)
	physics.doors_open = _b(d, "doors_open", physics.doors_open)
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
func is_connected_recently() -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	return _packet_count > 0 and (now - _last_packet_time) < 2.0
