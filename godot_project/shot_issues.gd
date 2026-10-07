## Captures des issues de secours de la face et de la porte du personnel
## (contrôle à l'œil) : la calotte avant avec ses deux D jaunes, la même
## sans (évacuation), l'issue droite vue du poste, la porte du personnel et
## l'escalier de la fosse à Val Claret.
##   xvfb-run godot --path godot_project --rendering-driver opengl3 \
##     --resolution 1376x1032 -s shot_issues.gd -- --mode=normal préfixe
extends SceneTree

var _main: Node = null
var _f: int = 0
var _pre: String = "/tmp/issues"
var _vues: Array = []           # [nom, position, yaw, pitch, dist, 1re pers., évacué]
var _t0: int = -1
var _f_scenario: int = -1


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_pre = a
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _yaw_vers(de: Vector3, vers: Vector3) -> float:
	var d: Vector3 = vers - de
	return atan2(-d.x, -d.z)


func _tick() -> void:
	_f += 1
	var relief: ReliefBuilder = _main.get("relief")
	if relief == null or not relief.pret:
		return
	var cab: Cabin = _main.cabin
	var tun: TunnelBuilder = _main.tunnel
	if _t0 < 0 and _f_scenario < 0:
		# rame arrêtée en tunnel, skieur à bord
		_main._apply_scenario(false, false, "normal")
		var ph: TrainPhysics = _main.physics
		ph.s = 1500.0
		ph.s_prev_step = ph.s
		ph.s_render = ph.s
		ph.v = 0.0
		ph.trip_started = false
		_main.basculer_skieur()
		if _main.auto_operator != null and _main.auto_operator.enabled:
			_main.auto_operator.toggle()
		_f_scenario = _f
		return
	if _t0 < 0:
		# la rame n'est posée à s qu'à l'image suivante, et le skieur n'entre
		# qu'une fois les collisions construites (par tranches)
		if _f - _f_scenario < 120 or _main.skieur == null:
			return
		var v0: Node3D = cab._interior_cars[0]
		var car_len: float = cab.train_length / float(cab.car_count)
		var zf: float = -car_len * 0.5
		var y: float = TrainBodyBuilder.Y_FLOOR + 0.3
		var nez: Vector3 = v0.global_transform * Vector3(0.0, y, zf)
		# devant la rame, sur l'escalier de service (collisions à la demande)
		var ph2: TrainPhysics = _main.physics
		var s_av: float = ph2.s
		var d_min: float = INF
		var s: float = ph2.s - 40.0
		while s <= ph2.s + 40.0:
			var d: float = tun.transform_at(s).origin.distance_to(nez)
			if d < d_min:
				d_min = d
				s_av = s
			s += 0.5
		var sens: float = 1.0 if (-v0.global_transform.basis.z).dot(-tun.transform_at(s_av).basis.z) > 0.0 else -1.0
		var devant: Vector3 = _main.track.point_passerelle(s_av + sens * 5.0)
		_main.collisions.assurer_autour(devant)
		var poste: Vector3 = v0.global_transform * Vector3(0.4, y, zf + 2.6)
		var issue: Vector3 = v0.global_transform * Vector3(1.3, y + 0.6, zf + 0.5)
		var xq: Transform3D = tun.transform_at(41.0)
		var y_q: float = StationsBuilder.FLOOR_Y_LOCAL + _main.stations.platform_height + 0.05
		var x_p: float = _main.stations.platform_inner_x + _main.stations.platform_width * 0.5
		var quai: Vector3 = xq.origin + xq.basis.x * x_p + xq.basis.y * y_q
		var xq2: Transform3D = tun.transform_at(44.0)
		var porte: Vector3 = xq2.origin + xq2.basis.x * x_p + xq2.basis.y * (y_q + 0.3)
		_vues = [["face", devant, _yaw_vers(devant, nez), 0.12, 1.0, true, false],
			["face_evacuee", devant, _yaw_vers(devant, nez), 0.12, 1.0, true, true],
			["issue_du_poste", poste, _yaw_vers(poste, issue), 0.05, 1.0, true, true],
			["porte_personnel", quai - tun.transform_at(41.0).basis.z * -2.0, _yaw_vers(quai, porte), -0.15, 1.0, true, false]]
		_t0 = _f
		return
	var i: int = (_f - _t0 - 30) / 60
	var j: int = (_f - _t0 - 30) % 60
	if _f - _t0 < 30:
		return
	if i >= _vues.size():
		quit(0)
		return
	var vu: Array = _vues[i]
	var sk: SkieurJoueur = _main.skieur
	if j == 1:
		if bool(vu[6]) and not cab.issues_retirees:
			cab.retirer_issues(true)
		elif not bool(vu[6]) and cab.issues_retirees:
			cab.retirer_issues(false)
		sk.global_position = vu[1]
		sk.velocity = Vector3.ZERO
		sk.support = null
		sk.cam_yaw = vu[2]
		sk.cam_pitch = vu[3]
		sk.cam_dist = vu[4]
		sk._cap = vu[2]
		sk.premiere_personne = bool(vu[5])
	if j == 59:
		var img: Image = get_root().get_texture().get_image()
		img.save_png("%s_%d_%s.png" % [_pre, i, vu[0]])
		print("capture ", vu[0], " ", sk.global_position)
