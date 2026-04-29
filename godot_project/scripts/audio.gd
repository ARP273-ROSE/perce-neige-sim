class_name TrainAudio
extends Node
## Audio cabine — ambient loops, crossfade basé sur la vitesse.

var physics: TrainPhysics = null

var _player_slow: AudioStreamPlayer = null
var _player_cruise: AudioStreamPlayer = null
var _player_buzzer: AudioStreamPlayer = null
var _player_door: AudioStreamPlayer = null
var _player_door_motion: AudioStreamPlayer = null
var _player_crossing: AudioStreamPlayer = null
var _player_vent: AudioStreamPlayer = null    # ventilation cabine

var _trip_was_started: bool = false
var _doors_were_open: bool = true
var _crossing_played: bool = false   # une seule fois par trip
const CROSSING_S_CENTER: float = PNConstants.LENGTH * 0.5    # = 1737 m
const CROSSING_S_WINDOW: float = 40.0   # fenêtre de déclenchement ±40 m


func _ready() -> void:
	_build_players()


func _build_players() -> void:
	# Ambient loops (cruise + slow) — crossfadés selon la vitesse
	_player_slow = _create_player("res://sounds/ambient_slow.wav", -20.0, true)
	_player_cruise = _create_player("res://sounds/ambient_cruise.wav", -30.0, true)
	_player_buzzer = _create_player("res://sounds/buzzer_upper.wav", -10.0, false)
	_player_door = _create_player("res://sounds/door_buzzer.wav", -10.0, false)
	_player_crossing = _create_player("res://sounds/crossing.wav", -8.0, false)
	_player_door_motion = _create_player("res://sounds/door_motion.wav", -14.0, false)
	# Ventilation cabine — réutilise ambient_slow en boucle, très baissée et
	# pitchée plus haut pour suggérer un souffle continu de ventilo
	_player_vent = _create_player("res://sounds/ambient_slow.wav", -32.0, true)
	_player_vent.pitch_scale = 1.6


func _create_player(path: String, vol_db: float, loop: bool) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	var stream: AudioStream = load(path)
	if stream == null:
		push_warning("Audio stream not found: %s" % path)
		add_child(player)
		return player
	if stream is AudioStreamWAV and loop:
		var wav: AudioStreamWAV = stream
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = wav.data.size() / (4 if wav.stereo else 2)
	player.stream = stream
	player.volume_db = vol_db
	player.bus = "Master"
	add_child(player)
	return player


func set_physics(p: TrainPhysics) -> void:
	physics = p


func _process(_delta: float) -> void:
	if physics == null:
		return

	# Démarrer l'ambient quand le trip démarre
	if physics.trip_started and not _trip_was_started:
		if _player_slow.stream:
			_player_slow.play()
		if _player_cruise.stream:
			_player_cruise.play()
	_trip_was_started = physics.trip_started

	# Crossfade selon vitesse : slow dominant à basse vitesse, cruise à haute
	if _player_slow.playing and _player_cruise.playing:
		var v_abs: float = absf(physics.v)
		var blend: float = clampf(v_abs / PNConstants.V_MAX, 0.0, 1.0)
		_player_slow.volume_db = lerpf(-12.0, -40.0, blend)
		_player_cruise.volume_db = lerpf(-40.0, -8.0, blend)
		# Pitch du moteur monte avec v → effet "whine" classique (1.0 → 1.35)
		_player_cruise.pitch_scale = lerpf(0.85, 1.35, blend)

	# Ventilation cabine : démarre dès que la cabine est en service, indep de v
	if not _player_vent.playing and _player_vent.stream:
		_player_vent.play()

	# Buzzer + animation portes (fermeture)
	if not physics.doors_open and _doors_were_open:
		if _player_door.stream:
			_player_door.play()
		if _player_door_motion.stream:
			_player_door_motion.play()
	# Animation portes (ouverture)
	if physics.doors_open and not _doors_were_open:
		if _player_door_motion.stream:
			_player_door_motion.play()
	_doors_were_open = physics.doors_open

	# Son de croisement au passage de rame 2 (s ≈ LENGTH/2)
	if physics.trip_started and not _crossing_played:
		if absf(physics.s - CROSSING_S_CENTER) < CROSSING_S_WINDOW:
			if _player_crossing.stream:
				_player_crossing.play()
			_crossing_played = true
	# Reset à chaque nouveau trip
	if not physics.trip_started:
		_crossing_played = false
