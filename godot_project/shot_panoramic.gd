## Captures du restaurant Le Panoramic et de la terrasse de la gare amont du funiculaire (16/11/2026).
##   godot --path godot_project --resolution 1920x1080 -s shot_panoramic.gd -- préfixe
extends SceneTree

var _main: Node = null
var _f: int = 0
var _pre: String = "/tmp/pano"
var _cam: Camera3D
var _vues: Array = []
var _i: int = 0
var _att: int = 0
var _etat: int = 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_pre = a
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _cacher(n: Node) -> void:
	for c in n.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
		elif c is Control:
			(c as Control).visible = false
		else:
			_cacher(c)


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 60:
		return
	match _etat:
		0:
			_main.basculer_skieur()
			_etat = 1
		1:
			if _main.get("skieur") == null or not _main.skieur.actif:
				return
			var ga: GareAmont = _main.station_halls.gare_amont
			_main.perf_manager.mode = "fige"
			_main.skieur.activer(ga._p(4.0, 20.0, 0.3), 0.0)
			_main.skieur.visible = false
			_cam = Camera3D.new()
			_cam.fov = 60
			_cam.far = 8000
			_main.add_child(_cam)
			_cam.make_current()
			_vues = [["dessus", ga._p(28.0, 22.0, 85.0), ga._p(28.0, 21.0, 0.0)],
				["terrasse", ga._p(-4.0, 30.0, 2.2), ga._p(22.0, 18.0, 2.5)],
				["jonction", ga._p(6.0, 36.0, 1.8), ga._p(18.0, 34.0, 1.2)],
				["sud", ga._p(-25.0, 75.0, 14.0), ga._p(22.0, 25.0, 2.0)],
				["nord", ga._p(75.0, 60.0, 18.0), ga._p(30.0, 20.0, 2.0)]]
			_etat = 2
		2:
			_att += 1
			if _att < 300:
				return
			if _i >= _vues.size():
				quit(0)
				return
			var v: Array = _vues[_i]
			if (_att - 300) % 40 == 0:
				_cacher(get_root())
				_cam.global_position = v[1]
				_cam.look_at(v[2], Vector3.UP if _i > 0 else Vector3.FORWARD)
			elif (_att - 300) % 40 == 39:
				var f: String = "%s_%s.png" % [_pre, v[0]]
				get_root().get_texture().get_image().save_png(f)
				print("SHOT ", f)
				_i += 1
