class_name SonsSkieur
extends Node
## Ce qu'entend le skieur sorti de la rame (07/10/2026, Kevin : « en vrai en
## bas on n'entend rien, à part des souffles d'air réguliers / vent
## sifflements suivis de silences dus aux surpressions dans le tunnel ») :
##   - en gare, rame en marche : une bouffée d'air toutes les 9 à 18 s, plus
##     forte quand la rame va vite, puis le silence ;
##   - dehors : un vent léger en boucle.
## Sons de tools_sons_skieur.py. Utilisé par TrainAudio (PWA) et seul dans
## la vue 3D embarquée du PC, où le PC joue tous les sons de la rame.

## 0 dans la rame, 1 en gare, 2 dehors — posé par main.gd
var ecoute: int = 0
var physics: TrainPhysics = null
var _souffle: AudioStreamPlayer = null
var _vent: AudioStreamPlayer = null
var _t_souffle: float = 4.0


func _ready() -> void:
	_souffle = _player("res://sounds/souffle_tunnel.wav", -10.0, false)
	_vent = _player("res://sounds/vent_dehors.wav", -80.0, true)


func _player(path: String, vol_db: float, boucle: bool) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	var stream: AudioStream = load(path)
	if stream is AudioStreamWAV and boucle:
		var wav: AudioStreamWAV = stream
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = maxi(int(wav.get_length() * wav.mix_rate) - 1, 0)
	p.stream = stream
	p.volume_db = vol_db
	# Safari : lecture Sample muette/instable → Stream (cf. PNConstants)
	if PNConstants.safari_web():
		p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(p)
	return p


func _process(delta: float) -> void:
	if _vent != null and _vent.stream != null:
		var dehors: bool = ecoute == 2
		if dehors and not _vent.playing:
			_vent.play()
		var cible: float = -16.0 if dehors else -80.0
		_vent.volume_db = move_toward(_vent.volume_db, cible, delta * 40.0)
		if not dehors and _vent.volume_db <= -79.0 and _vent.playing:
			_vent.stop()
	if _souffle == null or _souffle.stream == null or ecoute != 1 or physics == null:
		return
	var v: float = absf(physics.v)
	if v < 1.5:
		_t_souffle = maxf(_t_souffle, 2.0)
		return
	_t_souffle -= delta
	if _t_souffle <= 0.0 and not _souffle.playing:
		_souffle.volume_db = -22.0 + 14.0 * clampf(v / PNConstants.V_MAX, 0.0, 1.0)
		_souffle.pitch_scale = randf_range(0.85, 1.12)
		_souffle.play()
		_t_souffle = randf_range(9.0, 18.0)
