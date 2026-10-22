## Capture des remontées posées dans le jeu (vue skieur, relief réel).
##   xvfb-run godot --path godot_project --rendering-driver opengl3 \
##     --resolution 1400x900 -s shot_remontees_jeu.gd -- --mode=normal préfixe
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _pre: String = "/tmp/rj"
var _cam: Camera3D
var _vues: Array = []
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
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	if _f < _t0 + 60:
		return
	var rm: RemonteesDomaine = _main.remontees
	if _vues.is_empty():
		if rm == null or rm.lignes.is_empty():
			print("SHOT échec : pas de remontées")
			quit(1)
			return
		_cam = Camera3D.new()
		_cam.fov = 55
		_cam.far = 6000
		_main.add_child(_cam)
		_cam.make_current()
		for e in rm.lignes:
			var lg: LigneRemontee = e[0]
			var xf: Transform3D = lg.global_transform
			var L: float = lg.longueur_h()
			var d: float = float(lg.pylones[mini(2, lg.pylones.size() - 1)]["d"])
			var cible: Vector3 = xf * Vector3(0, lg.y_cable(d) - 4.0, -d)
			var oeil: Vector3 = xf * Vector3(-28, lg.terrain(d + 30) + 6, -d - 30)
			_vues.append([lg.name + "_pylone", oeil, cible])
			var c2: Vector3 = xf * Vector3(0, lg.terrain(L * 0.5) + 20, -L * 0.5)
			var o2: Vector3 = xf * Vector3(-L * 0.45, lg.terrain(L * 0.5) + L * 0.22, -L * 0.25)
			_vues.append([lg.name + "_ensemble", o2, c2])
			var c3: Vector3 = xf * Vector3(0, 3.0, 10)
			var o3: Vector3 = xf * Vector3(-16, 7.0, -14)
			_vues.append([lg.name + "_gare_aval", o3, c3])
		return
	if _i >= _vues.size():
		quit(0)
		return
	var v: Array = _vues[_i]
	if _f % 10 == 0:
		_cam.global_position = v[1]
		_cam.look_at(v[2], Vector3.UP)
	elif _f % 10 == 9:
		var f: String = "%s_%s.png" % [_pre, v[0]]
		get_root().get_texture().get_image().save_png(f)
		print("SHOT ", f)
		_i += 1
