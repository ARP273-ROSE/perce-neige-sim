## Captures des postures du skieur à ski (09/10/2026) : glisse, schuss,
## chasse-neige, les 4 images de la poussée sur les bâtons — de dos et de profil.
##   xvfb-run godot --path godot_project --rendering-driver opengl3 \
##     --resolution 1024x768 -s shot_postures.gd -- --mode=normal préfixe
extends SceneTree
var _main: Node = null
var _f: int = 0
var _t0: int = -1
var _pre: String = "/tmp/postures"
var _cam: Camera3D = null
var _i: int = 0
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_pre = a
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)
func _tick() -> void:
	_f += 1
	var relief: ReliefBuilder = _main.get("relief")
	if relief == null or not relief.pret:
		return
	if _t0 < 0:
		_main.basculer_skieur()
		_t0 = _f
		return
	var sk: SkieurJoueur = _main.skieur
	if sk == null or not sk.actif:
		return
	if _cam == null:
		if _f - _t0 < 30:
			return
		var p0: Vector2 = FantomesDonnees.points(3)[0]
		sk.global_position = Vector3(p0.x, relief.hauteur_sol(p0.x, p0.y) + 0.1, p0.y)
		sk.support = null
		_main.basculer_ski()
		sk.set_process(false)
		_cam = Camera3D.new()
		get_root().add_child(_cam)
		_cam.fov = 40.0
		_cam.make_current()
		_t0 = _f
		return
	var vues: Array = [[0, "glisse"], [1, "schuss"], [2, "chasse"],
		[10, "poussee0"], [11, "poussee1"], [12, "poussee2"], [13, "poussee3"]]
	var k: int = (_f - _t0) / 8
	if k >= vues.size() * 2:
		print("captures")
		quit(0)
		return
	var v: Array = vues[k / 2]
	var cote: bool = k % 2 == 1
	if (_f - _t0) % 8 == 1:
		if int(v[0]) >= 10:
			sk._poser_poussee(int(v[0]) - 10)
		else:
			sk._poser_posture(v[0])
		var o: Vector3 = sk._visuel.global_position + Vector3.UP * 0.8
		var av: Vector3 = -sk._visuel.global_transform.basis.z
		var dr: Vector3 = sk._visuel.global_transform.basis.x
		_cam.global_position = o + (dr * 3.2 if cote else -av * 3.2) + Vector3.UP * 0.6
		_cam.look_at(o, Vector3.UP)
	if (_f - _t0) % 8 == 6:
		get_root().get_texture().get_image().save_png("%s_%s_%s.png" % [_pre, v[1], "profil" if cote else "dos"])
