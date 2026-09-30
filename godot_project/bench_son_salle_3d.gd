# Banc du son de la vue « salle des machines » (PWA) — 2026-09-30.
#   godot --headless --path godot_project -s bench_son_salle_3d.gd
extends SceneTree

var _ok: bool = true


func _initialize() -> void:
	var ph: TrainPhysics = TrainPhysics.new()
	var au: TrainAudio = TrainAudio.new()
	get_root().add_child(au)
	au.set_physics(ph)
	process_frame.connect(_suite.bind(ph, au), CONNECT_ONE_SHOT)


func _pas(au: TrainAudio, n: int) -> void:
	for _i in range(n):
		au._process(1.0 / 60.0)


func _suite(ph: TrainPhysics, au: TrainAudio) -> void:
	au._process(1.0 / 60.0)             # 1er tick : synchronisation d'état
	var bus: int = AudioServer.get_bus_index("Cabine")
	_check("bus Cabine créé", bus > 0, "index %d" % bus)
	# vue cabine : rien ne joue côté salle, bus cabine à 0 dB
	ph.v = 6.0
	_pas(au, 30)
	_check("vue cabine : salle muette", not au._player_mr_idle.playing and not au._player_mr_run.playing,
		"repos %s, marche %s" % [au._player_mr_idle.playing, au._player_mr_run.playing])
	_check("vue cabine : bus Cabine à 0 dB", absf(AudioServer.get_bus_volume_db(bus)) < 0.1,
		"%.1f dB" % AudioServer.get_bus_volume_db(bus))
	# vue salle des machines
	au.machine_view = true
	_pas(au, 180)
	_check("vue salle : fondu terminé", au._mr_mix >= 0.999, "%.3f" % au._mr_mix)
	_check("vue salle : bus Cabine effacé", AudioServer.get_bus_volume_db(bus) < -70.0,
		"%.1f dB" % AudioServer.get_bus_volume_db(bus))
	_check("vue salle : les deux boucles jouent", au._player_mr_idle.playing and au._player_mr_run.playing, "")
	_check("6 m/s : hauteur 0,5", absf(au._player_mr_run.pitch_scale - 0.5) < 1e-3,
		"%.3f" % au._player_mr_run.pitch_scale)
	ph.v = 12.0
	_pas(au, 5)
	var att: float = TrainAudio.MR_BASE_DB + linear_to_db(TrainAudio.MR_GAIN_12)
	_check("12 m/s : hauteur 1 et gain 0,813", absf(au._player_mr_run.pitch_scale - 1.0) < 1e-3
		and absf(au._player_mr_run.volume_db - att) < 0.05,
		"pitch %.3f, %.2f dB (attendu %.2f)" % [au._player_mr_run.pitch_scale, au._player_mr_run.volume_db, att])
	ph.v = 1.0
	_pas(au, 5)
	_check("1 m/s : hauteur bornée à 0,25", absf(au._player_mr_run.pitch_scale - 0.25) < 1e-3,
		"%.3f" % au._player_mr_run.pitch_scale)
	ph.v = 0.0
	_pas(au, 5)
	_check("arrêt : machinerie muette, repos présent", au._player_mr_run.volume_db < -70.0
		and au._player_mr_idle.volume_db > -10.0,
		"marche %.1f dB, repos %.1f dB" % [au._player_mr_run.volume_db, au._player_mr_idle.volume_db])
	# retour cabine : fondu inverse, lecteurs arrêtés
	au.machine_view = false
	_pas(au, 240)
	_check("retour cabine : salle arrêtée, bus Cabine rétabli",
		not au._player_mr_idle.playing and absf(AudioServer.get_bus_volume_db(bus)) < 0.1,
		"repos %s, bus %.1f dB" % [au._player_mr_idle.playing, AudioServer.get_bus_volume_db(bus)])
	# même loi que le PC
	var l: Vector2 = TrainAudio.machine_room_levels(0.2)
	_check("fondu sous 0,3 m/s", l.x > 0.0 and l.x < 0.2, "gain %.3f à 0,2 m/s" % l.x)
	print("BENCH_SON_SALLE " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


func _check(label: String, cond: bool, detail: String) -> void:
	print("%s %s — %s" % ["[OK]  " if cond else "[FAIL]", label, detail])
	if not cond:
		_ok = false
