class_name TrainAudio
extends Node
## Audio cabine — ambient loops, crossfade basé sur la vitesse.

var physics: TrainPhysics = null

var _player_slow: AudioStreamPlayer = null
var _player_cruise: AudioStreamPlayer = null
var _player_buzzer: AudioStreamPlayer = null       # buzzer gare haute
var _player_buzzer_low: AudioStreamPlayer = null   # buzzer gare basse (8 s, distinct)
var _player_door: AudioStreamPlayer = null
var _player_door_motion: AudioStreamPlayer = null
var _player_crossing: AudioStreamPlayer = null
var _player_vent: AudioStreamPlayer = null    # ventilation cabine

var _trip_was_started: bool = false
var _doors_were_open: bool = false   # défaut "portes fermées" : en mode client
                                      # on reçoit l'état réel au 1er tick et le flag
                                      # _first_update_consumed empêche toute fausse
                                      # transition (avant : init à `true` → 1er
                                      # tick avec doors_open=false vu comme une
                                      # transition open→close → jouait à tort le
                                      # buzzer + l'animation portes).
var _first_update_consumed: bool = false
var _crossing_active: bool = false   # clip de croisement asservi en cours
var _prev_buzzer_remaining: float = 0.0   # front montant du buzzer de départ
# Le clip crossing.wav couvre le transit aiguillage → aiguillage complet
# (202 m) enregistré à la vitesse de croisière réelle.
const CROSSING_CLIP_S: float = 20.0
const CROSSING_REF_SPEED: float = 10.1
# Fondu d'entrée/sortie du clip d'évitement (s) : l'ancien démarrage/stop
# secs s'entendait nettement avant et après le croisement. Le corps du
# clip joue à volume CONSTANT (−8 dB) — seuls les bords sont fondus.
const CROSSING_BASE_DB: float = -8.0
const CROSSING_FADE_S: float = 0.7
var _crossing_fade: float = 0.0      # 0..1 (gain linéaire du fondu)
var _crossing_fading_out: bool = false


func _ready() -> void:
	_build_players()


func _build_players() -> void:
	# Ambient loops (cruise + slow) — crossfadés selon la vitesse
	_player_slow = _create_player("res://sounds/ambient_slow.wav", -20.0, true)
	_player_cruise = _create_player("res://sounds/ambient_cruise.wav", -30.0, true)
	_player_buzzer = _create_player("res://sounds/buzzer_upper.wav", -10.0, false)
	_player_buzzer_low = _create_player("res://sounds/buzzer_lower.wav", -10.0, false)
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
		wav.loop_begin = 0
		# loop_end en FRAMES, calculé depuis la durée × mix_rate (robuste
		# quelle que soit la compression : QOA/ADPCM ont un data.size() en
		# octets compressés, inutilisable). L'ancien loop_end=0 créait une
		# boucle de longueur NULLE → silence définitif dès la fin du
		# premier passage (constaté sur l'export Web Android : plus aucun
		# son en boucle après le buzzer de départ).
		wav.loop_end = maxi(int(wav.get_length() * wav.mix_rate) - 1, 0)
	player.stream = stream
	player.volume_db = vol_db
	player.bus = "Master"
	# Safari : lecture Sample muette/instable → Stream (cf. PNConstants)
	if PNConstants.safari_web():
		player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(player)
	return player


func set_physics(p: TrainPhysics) -> void:
	physics = p


func _process(_delta: float) -> void:
	if physics == null:
		return

	# Premier tick après set_physics : on synchronise l'état "previous" sur
	# l'état courant SANS déclencher de transition. Sinon, en mode client
	# (Godot piloté par le sim Python), les valeurs reçues au 1er packet
	# (typiquement doors_open=false, trip_started=true) seraient lues comme
	# des transitions depuis les défauts du _ready et déclencheraient à tort
	# les sons de fermeture portes / démarrage trip.
	if not _first_update_consumed:
		_doors_were_open = physics.doors_open
		_trip_was_started = physics.trip_started
		_first_update_consumed = true
		return

	# Buzzer de départ : déclenché au DÉBUT de la séquence (portes qui se
	# ferment + buzzer 6-8 s, traction à la fin — cf. request_depart).
	# Gares haut/bas ont des buzzers distincts. UNIQUEMENT À QUAI : les
	# buzzers sont des haut-parleurs de quai — une reprise en plein tunnel
	# (après inversion de sens) est silencieuse, comme sur le PC.
	if physics.departure_buzzer_remaining > 0.0 and _prev_buzzer_remaining <= 0.0 \
			and physics.at_station():
		var at_upper: bool = physics.s > PNConstants.LENGTH * 0.5
		var buz: AudioStreamPlayer = _player_buzzer if at_upper else _player_buzzer_low
		if buz != null and buz.stream:
			buz.play()
	_prev_buzzer_remaining = physics.departure_buzzer_remaining

	# Démarrer les boucles d'ambiance quand la traction colle.
	if physics.trip_started and not _trip_was_started:
		if _player_slow.stream:
			_player_slow.play()
		if _player_cruise.stream:
			_player_cruise.play()
	_trip_was_started = physics.trip_started

	# Crossfade selon vitesse : slow dominant à basse vitesse, cruise à haute.
	# `gate` étouffe le tout à l'arrêt (−30 dB sous 1 m/s) : avant, la boucle
	# slow restait à −12 dB en boucle infinie à quai après le 1er trajet.
	if _player_slow.playing and _player_cruise.playing:
		var v_abs: float = absf(physics.v)
		var blend: float = clampf(v_abs / PNConstants.V_MAX, 0.0, 1.0)
		var gate: float = clampf(v_abs, 0.0, 1.0)
		_player_slow.volume_db = lerpf(-12.0, -40.0, blend) + lerpf(-30.0, 0.0, gate)
		_player_cruise.volume_db = lerpf(-40.0, -8.0, blend) + lerpf(-30.0, 0.0, gate)
		# Pitch du moteur : CALIBRÉ (_calib_audio : 172 Hz à l'arrêt →
		# 197 Hz à la croisière enregistrée → 202 Hz à V_MAX). La boucle
		# est enregistrée en croisière → rate = f(v)/197 : 0,87 → 1,03.
		# (l'ancien 0,85→1,35 exagérait le glissando d'un facteur ~4.)
		_player_cruise.pitch_scale = lerpf(0.873, 1.025, blend)

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

	# Son de croisement asservi à la GÉOMÉTRIE (port du servo Python) :
	# le clip démarre quand le NEZ de la rame franchit l'aiguillage
	# d'entrée, position de lecture recalée sur la progression dans
	# l'évitement, vitesse de lecture = v / vitesse d'enregistrement.
	# L'ancien déclencheur (± 40 m autour du milieu de ligne, lecture à
	# vitesse fixe depuis le début du clip) partait ~13 s trop tard :
	# l'entrée d'aiguillage du clip tombait au niveau du croisement réel.
	_update_crossing_servo(_delta)


func _update_crossing_servo(delta: float) -> void:
	if _player_crossing == null or _player_crossing.stream == null:
		return
	var s_front: float = physics.s + PNConstants.TRAIN_HALF * float(physics.direction)
	var prog: float = (s_front - PNConstants.PASSING_START) \
		/ (PNConstants.PASSING_END - PNConstants.PASSING_START)
	if physics.direction < 0:
		prog = 1.0 - prog
	var in_loop: bool = prog >= 0.0 and prog <= 1.0
	var v_abs: float = absf(physics.v)

	if in_loop and not _crossing_active:
		if v_abs > 0.5:
			_player_crossing.pitch_scale = clampf(v_abs / CROSSING_REF_SPEED, 0.35, 1.7)
			# Démarre INAUDIBLE puis fondu d'entrée (0,7 s) — le start sec
			# en pleine amplitude s'entendait nettement à l'aiguillage.
			_crossing_fade = 0.0
			_crossing_fading_out = false
			_player_crossing.volume_db = -60.0
			_player_crossing.play(prog * CROSSING_CLIP_S)
			_crossing_active = true
	elif in_loop and _crossing_active:
		_crossing_fading_out = false
		# Rame quasi arrêtée dans l'évitement → pause (pas de mouvement,
		# pas de crécelle d'aiguillage)
		if v_abs < 1.0:
			_player_crossing.stream_paused = true
			return
		_player_crossing.stream_paused = false
		var rate: float = clampf(v_abs / CROSSING_REF_SPEED, 0.35, 1.7)
		if absf(rate - _player_crossing.pitch_scale) > 0.03:
			_player_crossing.pitch_scale = rate
		# Resynchro sur dérive franche seulement (> 0,7 s — seek permanent = clics)
		var expected: float = prog * CROSSING_CLIP_S
		if _player_crossing.playing \
				and absf(_player_crossing.get_playback_position() - expected) > 0.7:
			_player_crossing.play(expected)
	elif not in_loop and _crossing_active:
		# La géométrie commande la SORTIE — en fondu (0,7 s), plus de
		# coupure sèche à l'aiguillage de sortie.
		_crossing_fading_out = true

	# Progression du fondu : le CORPS du clip joue à volume constant
	# (−8 dB), seuls les bords entrent/sortent en fondu.
	if _crossing_active:
		var step_f: float = delta / CROSSING_FADE_S
		_crossing_fade = clampf(
			_crossing_fade + (-step_f if _crossing_fading_out else step_f), 0.0, 1.0)
		_player_crossing.volume_db = CROSSING_BASE_DB \
			+ linear_to_db(maxf(_crossing_fade, 0.001))
		if _crossing_fading_out and _crossing_fade <= 0.0:
			_player_crossing.stop()
			_player_crossing.stream_paused = false
			_player_crossing.pitch_scale = 1.0
			_player_crossing.volume_db = CROSSING_BASE_DB
			_crossing_active = false
			_crossing_fading_out = false
