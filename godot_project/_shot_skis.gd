extends SceneTree
var _main: Node
var _f: int = 0
var _t0: int = 0
var _lg: LigneRemontee
var _cam: Camera3D
var _etape: int = 0
var _n: int = 0
func _initialize() -> void:
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
	var sk: SkieurJoueur = _main.skieur
	match _etape:
		0:
			for e in rm.lignes:
				if (e[0] as Node).name == "tsd6_marmottes_express":
					_lg = e[0]
			_main.aller_a_remontee(_lg)
			_etape = 1
		1:
			if not _lg.pret:
				return
			var q: Vector3 = _lg.global_transform * _lg.point_embarquement(true)
			sk.activer(q + Vector3(0, 0.1, 0), 0.0)
			print("chausse: '", sk.basculer_ski(true), "' ", sk.chausse)
			_etape = 2
		2:
			if rm.a_bord.is_empty():
				return
			_n += 1
			if _n == 1:
				print("assis ", sk.assis, " mesh assise ", sk._corps.multimesh.mesh == sk._image_assise, " posture ", sk._posture)
			if _n == 300:
				print("assis ", sk.assis, " mesh assise ", sk._corps.multimesh.mesh == sk._image_assise, " posture ", sk._posture)
				_cam = Camera3D.new()
				_cam.fov = 45
				_main.add_child(_cam)
				_cam.make_current()
			if _n >= 300:
				var xf: Transform3D = _lg.global_transform
				var p: Vector3 = sk.global_position
				_cam.global_position = p + xf.basis * Vector3(-3.5, 0.6, -2.0)
				_cam.look_at(p + Vector3(0, 0.3, 0), Vector3.UP)
			if _n == 304:
				get_root().get_texture().get_image().save_png("/pn/_shots_tmp/skis_assis.png")
				quit(0)
