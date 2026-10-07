# Captures du skieur jouable (vue de la caméra du skieur) à des endroits
# clés : place de Val Claret, salle, quai, voiture, palier haut, porte
# Génépy. xvfb-run godot --path godot_project --rendering-driver opengl3 \
#   --resolution 1376x1032 -s shot_skieur.gd -- --mode=normal préfixe
extends SceneTree
var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _pre: String = "/tmp/skieur"
var _k: int = 0
var _vues: Array = []
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_pre = a
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)
func _vue(nom: String, pos: Vector3, yaw: float, pitch: float = -0.22, dist: float = 3.2) -> void:
	_vues.append([nom, pos, yaw, pitch, dist])
func _yaw_vers(a: Vector3, b: Vector3) -> float:
	var d: Vector3 = b - a
	return atan2(-d.x, -d.z)
func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	var sk: SkieurJoueur = _main.skieur
	var tun: TunnelBuilder = _main.tunnel
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		sk = _main.skieur
		var ga: GareAval = _main.station_halls.gare_aval
		var dep: Array = ga.point_depart()
		_vue("place", dep[0], dep[1], -0.10, 4.5)
		_vue("salle", ga._p2(Vector2(-1.5, 9.0), 0.05), _yaw_vers(ga._p2(Vector2(-1.5, 9.0)), ga._p2(Vector2(-2.5, 0.0))), -0.15, 3.0)
		var x10: Transform3D = tun.transform_at(10.0)
		var pq: Vector3 = x10.origin + x10.basis.x * 3.0 + x10.basis.y * -1.0
		_vue("quai", pq, _yaw_vers(pq, tun.transform_at(40.0).origin + tun.transform_at(40.0).basis.x * 2.0), -0.15, 3.0)
		var cab: Cabin = _main.cabin
		var v: Node3D = cab._interior_cars[1]
		var car_len: float = cab.train_length / float(cab.car_count)
		var z_c: float = (1.0 - (cab.car_count - 1) * 0.5) * car_len
		var zc: float = cab._panel_center(1, 5) - z_c - 0.35
		var pv: Vector3 = v.global_transform * Vector3(0.0, TrainBodyBuilder.Y_FLOOR + 0.1, zc)
		_vue("voiture", pv, _yaw_vers(pv, v.global_transform * Vector3(0.0, 0.0, zc - 5.0)), -0.20, 2.2)
		var xh: Transform3D = tun.transform_at(PNConstants.LENGTH)
		var ph_: Vector3 = xh.origin - xh.basis.z * 6.0 + xh.basis.x * -3.0 + Vector3(0, -0.9, 0)
		_vue("palier_haut", ph_, _yaw_vers(ph_, xh.origin - xh.basis.z * 20.0 + xh.basis.x * -3.0), -0.12, 3.0)
		var sc: float = (StationsBuilder.PORTE_GENEPY.x + StationsBuilder.PORTE_GENEPY.y) * 0.5
		var xg: Transform3D = tun.transform_at(sc)
		var pg_in: Vector3 = xg.origin + xg.basis.x * -3.0 + Vector3(0, -1.0, 0) - xg.basis.z * -4.0
		_vue("genepy_dedans", pg_in, _yaw_vers(pg_in, xg.origin + xg.basis.x * -6.0), -0.15, 2.5)
		var pg_out: Vector3 = xg.origin + xg.basis.x * -14.0 + Vector3(0, -1.0, 0)
		_vue("genepy_dehors", pg_out, _yaw_vers(pg_out, xg.origin + xg.basis.x * -7.0), -0.10, 4.0)
		var x14: Transform3D = tun.transform_at(14.0)
		var pfq: Vector3 = x14.origin + x14.basis.x * 2.8 + x14.basis.y * -1.05
		_vue("fosse_quai", pfq, _yaw_vers(pfq, tun.transform_at(2.0).origin), -0.45, 3.0)
		var pfd: Vector3 = x14.origin + x14.basis.y * -3.5
		_vue("fosse_dedans", pfd, _yaw_vers(pfd, tun.transform_at(2.0).origin + tun.transform_at(2.0).basis.x * 1.4), 0.05, 2.5)
		# escalier du bout de la terrasse : vu d'en bas, sur la neige
		var ep: Array = (_main.station_halls.gare_amont as GareAmont).escalier_points()
		var pe: Vector3 = (ep[1] as Vector3) + ((ep[1] as Vector3) - (ep[0] as Vector3)).normalized() * 3.0
		_vue("escalier_terrasse", pe, _yaw_vers(pe, ep[0]), 0.10, 4.5)
		if "--escalier" in OS.get_cmdline_user_args():
			_vues = _vues.slice(_vues.size() - 1)
		if "--fosse" in OS.get_cmdline_user_args():
			_vues = _vues.slice(_vues.size() - 3, _vues.size() - 1)
			_main.physics.s = 1500.0
			_main.physics.s_prev_step = 1500.0
		return
	var i: int = (_f - _t0) / 45
	var j: int = (_f - _t0) % 45
	if i >= _vues.size():
		quit(0)
		return
	var vu: Array = _vues[i]
	if j == 1:
		sk.global_position = vu[1]
		sk.velocity = Vector3.ZERO
		sk.support = null
		sk.cam_yaw = vu[2]
		sk.cam_pitch = vu[3]
		sk.cam_dist = vu[4]
		sk._cap = vu[2]
		PorteAuto.presences = [vu[1]]
	if j == 44:
		var img: Image = get_root().get_texture().get_image()
		img.save_png("%s_%d_%s.png" % [_pre, i, vu[0]])
		print("capture ", vu[0], " ", sk.global_position)
