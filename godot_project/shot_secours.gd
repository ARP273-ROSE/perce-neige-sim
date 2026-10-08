## Captures de la sortie de secours (contrôle à l'œil) : l'ouverture vue de
## la passerelle, l'intérieur de la galerie, le portail vu de la piste.
##   xvfb-run godot --path godot_project --rendering-driver opengl3 \
##     --resolution 1376x1032 -s shot_secours.gd -- --mode=normal préfixe
extends SceneTree

var _main: Node = null
var _f: int = 0
var _pre: String = "/tmp/secours"
var _vues: Array = []           # [nom, position, yaw, pitch, dist]
var _t0: int = -1


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
	if _t0 < 0:
		# rame arrêtée à la chambre, portes ouvertes (Défi), skieur
		_main._apply_scenario(false, false, "challenge")
		var ph: TrainPhysics = _main.physics
		ph.s = TunnelBuilder.SORTIE_SECOURS_S + 6.0
		ph.s_prev_step = ph.s
		ph.s_render = ph.s
		ph.v = 0.0
		ph.trip_started = false
		ph.doors_open = true
		ph.door_leaves_open = true
		_main.basculer_skieur()
		if _main.auto_operator != null and _main.auto_operator.enabled:
			_main.auto_operator.toggle()
		var ss: SortieSecours = _main.sortie_secours
		var tun: TunnelBuilder = _main.tunnel
		var xf: Transform3D = tun.transform_at(TunnelBuilder.SORTIE_SECOURS_S - 5.0)
		var pp: Vector3 = ss.point_passerelle(_main.track) - tun.transform_at(TunnelBuilder.SORTIE_SECOURS_S).basis.z * 5.0
		var ouv: Vector3 = ss.sol[0] + Vector3.UP * 1.0
		_vues = [["passerelle", pp, _yaw_vers(pp, ouv), -0.05, 2.5],
			["galerie", ss.sol[1] + Vector3.UP * 0.05, _yaw_vers(ss.sol[1], ss.sol[mini(3, ss.sol.size() - 1)]), -0.05, 3.0],
			["portail_dedans", ss.sol[maxi(ss.sol.size() - 3, 0)] + Vector3.UP * 0.05, _yaw_vers(ss.sol[maxi(ss.sol.size() - 3, 0)], ss.portail), 0.0, 3.0],
			["portail_dehors", ss.portail + ss._dir_fin * 16.0 + Vector3.UP * 0.05, _yaw_vers(ss.portail + ss._dir_fin * 16.0, ss.portail), 0.05, 5.0]]
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
		sk.global_position = vu[1]
		sk.velocity = Vector3.ZERO
		sk.support = null
		sk.cam_yaw = vu[2]
		sk.cam_pitch = vu[3]
		sk.cam_dist = vu[4]
		sk._cap = vu[2]
		sk.premiere_personne = i == 0
	if j == 59:
		var img: Image = get_root().get_texture().get_image()
		img.save_png("%s_%d_%s.png" % [_pre, i, vu[0]])
		print("capture ", vu[0], " ", sk.global_position)
