class_name Announcements
extends Node
## Système d'annonces vocales du Perce-Neige — port direct du SoundSystem.GROUPS
## du sim Python v1.9.1.
##
## Les fichiers MP3 sont les enregistrements RÉELS du funiculaire (Tignes),
## groupés par sujet et par langue (FR=fr, ANG=en, ITAL=it, ALLEM=de, ESP=es).
## Chaque groupe contient jusqu'à 5 fichiers contigus (1 par langue).
##
## Usage :
##   announcements.queue("doors_close")   → joue 01 (FR seulement)
##   announcements.queue("welcome")       → joue 11 dans la langue courante
##   announcements.is_announcing()        → true si annonce en cours
##   announcements.set_lang("en")         → bascule langue (auto-détecté sinon)

# Plage [start, end] inclusive de numéros de fichier pour chaque clé d'annonce.
const GROUPS: Dictionary = {
	"doors_close":     [1, 1],     # 01 FR seulement (chime + speech)
	"exit_left":       [6, 10],    # 06 FR .. 10 ESP
	"welcome":         [11, 11],   # 11 FR seulement (long zone message)
	"minor_incident":  [12, 16],
	"tech_incident":   [17, 21],
	"long_repair":     [22, 26],
	"stop_10min":      [27, 31],
	"restart":         [32, 36],
	"evac":            [37, 41],
	"exit_upstream":   [42, 46],
	"exit_downstream": [47, 51],
	"evac_car2":       [52, 56],
	"dim_light":       [57, 61],
	"return_station":  [62, 66],
	"brake_noise":     [67, 71],   # n'existe pas en MP3 — placeholder
}

# Décalage par langue (FR=0, EN=1, IT=2, DE=3, ES=4)
const LANG_OFFSET: Dictionary = {"fr": 0, "en": 1, "it": 2, "de": 3, "es": 4}

# Cooldown par groupe (s) — anti-spam si triggers répétés rapidement
const COOLDOWN_S: float = 8.0

@export var volume_db: float = -8.0

var lang: String = "fr"
var muted: bool = false

var _files_by_num: Dictionary = {}     # int → AudioStream
var _queue: Array = []                 # AudioStream[]
var _cooldowns: Dictionary = {}        # group_key → next allowed time (Time.get_ticks_msec/1000)
var _player: AudioStreamPlayer = null
var _on_complete_callable: Callable = Callable()


func _ready() -> void:
	_detect_lang()
	_load_files()
	_setup_player()


func _detect_lang() -> void:
	var loc: String = OS.get_locale().to_lower()
	if loc.begins_with("fr"):
		lang = "fr"
	elif loc.begins_with("it"):
		lang = "it"
	elif loc.begins_with("de"):
		lang = "de"
	elif loc.begins_with("es"):
		lang = "es"
	else:
		lang = "en"


func _load_files() -> void:
	# Scan res://sounds/announcements/ pour tous les MP3 numérotés "NN ...".
	var dir: DirAccess = DirAccess.open("res://sounds/announcements")
	if dir == null:
		push_warning("[Announcements] dossier res://sounds/announcements introuvable")
		return
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if f.ends_with(".mp3") and not dir.current_is_dir():
			# Format attendu : "NN ...mp3" — extraire le numéro
			var two: String = f.substr(0, 2)
			if two.is_valid_int():
				var num: int = two.to_int()
				var path: String = "res://sounds/announcements/" + f
				var stream: AudioStream = load(path)
				if stream != null:
					_files_by_num[num] = stream
		f = dir.get_next()
	dir.list_dir_end()
	print("[Announcements] %d fichiers MP3 chargés (langue=%s)" % [_files_by_num.size(), lang])


func _setup_player() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	_player.volume_db = volume_db
	_player.finished.connect(_on_player_finished)
	add_child(_player)


# Définit la langue manuellement (ex : depuis un menu).
func set_lang(new_lang: String) -> void:
	if LANG_OFFSET.has(new_lang):
		lang = new_lang


# True si une annonce est en cours OU dans la queue.
func is_announcing() -> bool:
	return _player.playing or _queue.size() > 0


# Coupe l'annonce en cours et vide la queue.
func stop_all() -> void:
	_queue.clear()
	if _player.playing:
		_player.stop()


func set_muted(m: bool) -> void:
	muted = m
	if muted and _player.playing:
		_player.stop()


# Met une annonce en queue. Respecte le cooldown par groupe pour éviter
# le spam si plusieurs triggers simultanés.
func queue(group_key: String) -> void:
	if muted:
		return
	if not GROUPS.has(group_key):
		push_warning("[Announcements] groupe inconnu : %s" % group_key)
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if _cooldowns.has(group_key) and now < _cooldowns[group_key]:
		return   # cooldown actif
	_cooldowns[group_key] = now + COOLDOWN_S

	var stream: AudioStream = _resolve_stream(group_key)
	if stream == null:
		return
	_queue.append(stream)
	_pump_queue()


# Force la lecture d'un groupe SANS cooldown (pour menu manuel F2 par exemple).
# Vide la queue avant.
func play_now(group_key: String) -> void:
	if muted:
		return
	stop_all()
	var stream: AudioStream = _resolve_stream(group_key)
	if stream == null:
		return
	_queue.append(stream)
	_pump_queue()


func _resolve_stream(group_key: String) -> AudioStream:
	var range_arr: Array = GROUPS[group_key]
	var start_num: int = range_arr[0]
	var end_num: int = range_arr[1]
	var group_size: int = end_num - start_num + 1
	# Si le groupe a 1 seul fichier → forcément FR (ou indépendant de la langue)
	if group_size == 1:
		return _files_by_num.get(start_num, null)
	# Sinon, applique l'offset de la langue (avec fallback sur FR si manquant)
	var offset: int = LANG_OFFSET.get(lang, 0)
	if offset >= group_size:
		offset = 0   # langue hors plage du groupe → fallback FR
	var num: int = start_num + offset
	var s: AudioStream = _files_by_num.get(num, null)
	if s == null:
		# Fallback : FR (premier du groupe)
		s = _files_by_num.get(start_num, null)
	return s


func _pump_queue() -> void:
	if _player.playing:
		return
	if _queue.is_empty():
		return
	_player.stream = _queue.pop_front()
	_player.play()


func _on_player_finished() -> void:
	_pump_queue()
