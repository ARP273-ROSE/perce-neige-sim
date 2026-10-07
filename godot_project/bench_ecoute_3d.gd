## Banc de l'écoute (07/10/2026) : ce qu'on entend selon l'endroit — gare
## basse (souffle), gare haute (machinerie modulée par la distance), dehors
## (vent), tunnel à pied, rame ; et les buzzers de quai : celui de SA gare,
## entendu de la gare (même quand la rame repart du milieu du tunnel), jamais
## d'une rame en tunnel.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_ecoute_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _phase: int = 0
var _t: float = 0.0
var _ok: bool = true
var _gain_pres: float = 0.0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_ECOUTE " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


func _poser(p: Vector3, support: Node3D = null) -> void:
	var sk: SkieurJoueur = _main.skieur
	sk.global_position = p
	sk.velocity = Vector3.ZERO
	sk.support = support
	sk.chemin.clear()
	_t = 0.0


func _tick() -> void:
	_f += 1
	_t += 1.0 / 60.0
	var relief: ReliefBuilder = _main.get("relief")
	if relief == null or not relief.pret:
		if _f > 20000:
			_verif("relief prêt", false)
			_fin()
		return
	var ph: TrainPhysics = _main.physics
	var au: TrainAudio = _main.audio
	var tun: TunnelBuilder = _main.tunnel
	var cab: Cabin = _main.cabin
	match _phase:
		0:
			_main._apply_scenario(false, false, "normal")
			if _main.auto_operator != null and _main.auto_operator.enabled:
				_main.auto_operator.toggle()
			ph.s = PNConstants.START_S
			ph.s_prev_step = ph.s
			ph.s_render = ph.s
			ph.v = 0.0
			ph.trip_started = false
			_phase = 1
			_t = 0.0
		1:
			if _t < 0.5:
				return
			_verif("conduite, rame à quai en bas : buzzer de la gare basse", au.gare_ecoute == 1, "gare_ecoute %d" % au.gare_ecoute)
			cab.view_mode = Cabin.ViewMode.MACHINES
			_phase = 2
			_t = 0.0
		2:
			if _t < 0.5:
				return
			_verif("vue salle des machines : le buzzer du haut, même rame en bas", au.gare_ecoute == 2 and au.machine_view,
				"gare_ecoute %d, machine_view %s" % [au.gare_ecoute, au.machine_view])
			cab.view_mode = Cabin.ViewMode.FPV
			ph.s = 1500.0
			ph.s_prev_step = ph.s
			ph.s_render = ph.s
			_phase = 3
			_t = 0.0
		3:
			if _t < 0.5:
				return
			_verif("conduite en plein tunnel : aucun buzzer", au.gare_ecoute == 0, "gare_ecoute %d" % au.gare_ecoute)
			_main.basculer_skieur()
			_phase = 4
			_t = 0.0
		4:
			if _t < 8.0:
				return
			# quai du bas (haut du quai droit, comme le banc du skieur)
			var xq: Transform3D = tun.transform_at(41.0)
			var y_q: float = StationsBuilder.FLOOR_Y_LOCAL + _main.stations.platform_height + 0.05
			var x_porte: float = _main.stations.platform_inner_x + _main.stations.platform_width * 0.5
			_poser(xq.origin + xq.basis.x * x_porte + xq.basis.y * y_q)
			_phase = 5
		5:
			if _t < 1.0:
				return
			_verif("quai du bas : souffle (écoute 1), buzzer du bas, pas de machinerie",
				au.ecoute == 1 and au.gare_ecoute == 1 and au.gain_machinerie == 0.0 and au._sons_skieur.ecoute == 1,
				"écoute %d, gare %d, gain %.2f" % [au.ecoute, au.gare_ecoute, au.gain_machinerie])
			var xh: Transform3D = tun.transform_at(PNConstants.LENGTH - 30.0)
			_poser(xh.origin + xh.basis.x * -3.2 + Vector3(0.0, -0.9, 0.0))
			_phase = 6
		6:
			if _t < 1.0:
				return
			_verif("quai du haut, loin : machinerie atténuée (écoute 3), buzzer du haut",
				au.ecoute == 3 and au.gare_ecoute == 2 and au.gain_machinerie > 0.06 and au.gain_machinerie < 0.9,
				"écoute %d, gare %d, gain %.3f (%.1f dB), d %.0f m" % [au.ecoute, au.gare_ecoute, au.gain_machinerie,
					20.0 * log(maxf(au.gain_machinerie, 1e-4)) / log(10.0), _main.machine_room.distance_au_hall(_main.skieur.global_position)])
			_gain_pres = au.gain_machinerie
			var xh2: Transform3D = tun.transform_at(PNConstants.LENGTH - 8.0)
			_poser(xh2.origin + xh2.basis.x * -3.2 + Vector3(0.0, -0.9, 0.0))
			_phase = 7
		7:
			if _t < 1.0:
				return
			_verif("quai du haut, près de la machinerie : plus fort", au.ecoute == 3 and au.gain_machinerie > _gain_pres * 1.5,
				"gain %.3f contre %.3f à 22 m de plus, d %.0f m" % [au.gain_machinerie, _gain_pres,
					_main.machine_room.distance_au_hall(_main.skieur.global_position)])
			# rame en bas qui repart : on entend le buzzer du HAUT, pas celui du bas
			ph.s = PNConstants.START_S
			ph.s_prev_step = ph.s
			ph.s_render = ph.s
			au._player_buzzer.stop()
			au._player_buzzer_low.stop()
			ph.departure_buzzer_remaining = 0.0
			_phase = 8
			_t = 0.0
		8:
			if _t < 0.3:
				return
			ph.departure_buzzer_remaining = 6.0
			_phase = 9
			_t = 0.0
		9:
			if _t < 0.3:
				return
			_verif("sur le quai du haut, la rame d'en bas repart : buzzer du haut, pas celui du bas",
				au._player_buzzer.playing and not au._player_buzzer_low.playing,
				"haut %s, bas %s" % [au._player_buzzer.playing, au._player_buzzer_low.playing])
			au._player_buzzer.stop()
			au._player_buzzer_low.stop()
			ph.departure_buzzer_remaining = 0.0
			# dehors, au départ de la trace n° 4
			var p0: Vector2 = FantomesDonnees.points(3)[0]
			_poser(Vector3(p0.x, relief.hauteur_sol(p0.x, p0.y) + 0.1, p0.y))
			_phase = 10
		10:
			if _t < 1.0:
				return
			_verif("dehors : le vent (écoute 2), aucun buzzer", au.ecoute == 2 and au.gare_ecoute == 0 and au.gain_machinerie == 0.0,
				"écoute %d, gare %d, gain %.2f" % [au.ecoute, au.gare_ecoute, au.gain_machinerie])
			_poser(_main.track.point_passerelle(1500.0))
			_phase = 11
		11:
			if _t < 1.0:
				return
			_verif("à pied dans le tunnel : souffle (écoute 4), rame retenue, aucun buzzer",
				au.ecoute == 4 and au.gare_ecoute == 0 and _main.auto_operator.retenue,
				"écoute %d, gare %d, retenue %s" % [au.ecoute, au.gare_ecoute, _main.auto_operator.retenue])
			# dans la rame, en plein tunnel
			ph.s = 1500.0
			ph.s_prev_step = ph.s
			ph.s_render = ph.s
			_phase = 12
			_t = 0.0
		12:
			if _t < 0.5:
				return
			var v1: Node3D = cab._interior_cars[1]
			var car_len: float = cab.train_length / float(cab.car_count)
			var z_c: float = (1.0 - (cab.car_count - 1) * 0.5) * car_len
			var zc: float = cab._panel_center(1, 7) - z_c
			_poser(v1.global_transform * Vector3(0.9, TrainBodyBuilder.Y_FLOOR + 0.3, zc), v1)
			_phase = 13
		13:
			if _t < 1.0:
				return
			_verif("dans la rame en tunnel : sons de cabine (écoute 0), aucun buzzer", au.ecoute == 0 and au.gare_ecoute == 0,
				"écoute %d, gare %d" % [au.ecoute, au.gare_ecoute])
			ph.departure_buzzer_remaining = 1.5
			_phase = 14
			_t = 0.0
		14:
			if _t < 0.3:
				return
			_verif("la rame repart du milieu du tunnel, on est dedans : silence",
				not au._player_buzzer.playing and not au._player_buzzer_low.playing,
				"haut %s, bas %s" % [au._player_buzzer.playing, au._player_buzzer_low.playing])
			ph.departure_buzzer_remaining = 0.0
			# la rame « saute » en haut (banc) : on y repose le skieur après
			ph.s = PNConstants.STOP_S
			ph.s_prev_step = ph.s
			ph.s_render = ph.s
			_phase = 15
			_t = 0.0
		15:
			if _t < 0.5:
				return
			var v1: Node3D = cab._interior_cars[1]
			var car_len: float = cab.train_length / float(cab.car_count)
			var z_c: float = (1.0 - (cab.car_count - 1) * 0.5) * car_len
			var zc: float = cab._panel_center(1, 7) - z_c
			_poser(v1.global_transform * Vector3(0.9, TrainBodyBuilder.Y_FLOOR + 0.3, zc), v1)
			_phase = 16
		16:
			if _t < 1.0:
				return
			_verif("dans la rame à quai en haut : buzzer du haut", au.ecoute == 0 and au.gare_ecoute == 2,
				"écoute %d, gare %d" % [au.ecoute, au.gare_ecoute])
			_fin()
