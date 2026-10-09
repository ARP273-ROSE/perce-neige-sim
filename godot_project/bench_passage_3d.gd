## Banc du passage d'intercirculation (09/10/2026, retour d'utilisateur : « fais en sorte
## qu'on puisse passer d'un wagon à l'autre en marchant à l'intérieur de la
## rame sans passer par une faille spatio-temporelle » ; avant, arrivé à la
## cloison, le jeu le disait « percuté par la rame » et le renvoyait en bas).
## Rame en marche en tunnel, le skieur part du fond de la voiture 1 et doit
## arriver dans la voiture 2 par la baie de la cloison, sans être éjecté.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_passage_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _phase: int = 0
var _t: float = 0.0
var _ok: bool = true
var _d_max: float = 0.0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_PASSAGE " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


func _point(cab: Cabin, idx: int, k: int) -> Vector3:
	var v: Node3D = cab._interior_cars[idx]
	var car_len: float = cab.train_length / float(cab.car_count)
	var z_c: float = (float(idx) - (cab.car_count - 1) * 0.5) * car_len
	return v.global_transform * Vector3(0.0, TrainBodyBuilder.Y_FLOOR + 0.3, cab._panel_center(idx, k) - z_c)


func _tick() -> void:
	_f += 1
	var dt: float = 1.0 / 60.0
	_t += dt
	var relief: ReliefBuilder = _main.get("relief")
	if relief == null or not relief.pret:
		if _f > 20000:
			_verif("relief prêt", false)
			_fin()
		return
	var ph: TrainPhysics = _main.physics
	var cab: Cabin = _main.cabin
	match _phase:
		0:
			ph.s = 1500.0
			ph.s_prev_step = ph.s
			ph.s_render = ph.s
			ph.trip_started = true
			_main.basculer_skieur()
			if _main.auto_operator != null and _main.auto_operator.enabled:
				_main.auto_operator.toggle()
			_phase = 1
			_t = 0.0
		1:
			if _t < 1.0:
				return
			var sk: SkieurJoueur = _main.skieur
			sk.global_position = _point(cab, 0, TrainBodyBuilder.N_PANNEAUX - 2)
			sk.velocity = Vector3.ZERO
			sk.support = cab._interior_cars[0]
			sk._support_xf = cab._interior_cars[0].global_transform
			_phase = 2
			_t = 0.0
		2:
			var sk2: SkieurJoueur = _main.skieur
			ph.v = 2.0                    # rame « en marche » : le contrôle du choc est armé
			sk2.chemin = [_point(cab, 1, 2)]
			var c1: Vector3 = cab._interior_cars[1].global_position
			_d_max = maxf(_d_max, sk2.global_position.distance_to(cab._interior_cars[0].global_position))
			var dans_v2: bool = sk2.support == cab._interior_cars[1]
			if (dans_v2 and sk2.global_position.distance_to(_point(cab, 1, 2)) < 0.8) or _t > 40.0:
				_verif("de la voiture 1 à la voiture 2 par la baie de la cloison, rame en marche",
					dans_v2 and _t <= 40.0 and _d_max < 20.0,
					"%.0f s, support voiture 2 %s, écart max %.1f m, à %.1f m du but" % [
						_t, dans_v2, _d_max, sk2.global_position.distance_to(_point(cab, 1, 2))])
				_fin()
