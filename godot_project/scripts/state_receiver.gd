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

var udp: PacketPeerUDP = null
var port: int = DEFAULT_PORT
var physics: TrainPhysics = null
var fault_manager: FaultManager = null
var _last_packet_time: float = 0.0
var _packet_count: int = 0


func _ready() -> void:
	# Parse les args projet (après --)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--port="):
			port = int(arg.substr(7))

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
	if latest.is_empty():
		return
	_apply(latest)
	_last_packet_time = Time.get_ticks_msec() / 1000.0


func _apply(d: Dictionary) -> void:
	# Update direct des champs (la physics locale est court-circuitée)
	if d.has("s"):
		physics.s = float(d["s"])
	if d.has("v"):
		physics.v = float(d["v"])
	if d.has("direction"):
		physics.direction = int(d["direction"])
	if d.has("doors_open"):
		physics.doors_open = bool(d["doors_open"])
	if d.has("trip_started"):
		physics.trip_started = bool(d["trip_started"])
	if d.has("finished"):
		physics.finished = bool(d["finished"])
	if d.has("tension_dan"):
		physics.tension_dan = float(d["tension_dan"])
		physics.tension_dan_disp = physics.tension_dan
	if d.has("power_kw"):
		physics.power_kw = float(d["power_kw"])
		physics.power_kw_disp = physics.power_kw
	if d.has("speed_cmd"):
		physics.speed_cmd = float(d["speed_cmd"])
	if d.has("lights_head"):
		physics.lights_head = bool(d["lights_head"])
	if d.has("lights_cabin"):
		physics.lights_cabin = bool(d["lights_cabin"])
	if d.has("emergency"):
		physics.emergency = bool(d["emergency"])
	# Panne active : déclenche localement pour effet visuel + son
	if d.has("active_fault") and fault_manager != null:
		var fid: String = String(d["active_fault"])
		if fid != "" and fault_manager.get_active_id() != fid:
			fault_manager.trigger(fid)
		elif fid == "" and fault_manager.is_active():
			fault_manager.clear_active()


# Indique si on a reçu au moins un packet récent (utile pour debug / fallback)
func is_connected_recently() -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	return _packet_count > 0 and (now - _last_packet_time) < 2.0
