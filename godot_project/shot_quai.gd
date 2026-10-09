## Capture de contrôle : la rame à quai vue du quai, portes ouvertes (comme
## les photos de Kevin du 09/10/2026 : 18 fenêtres par voiture, une porte
## toutes les trois fenêtres à partir de la deuxième).
extends SceneTree
var _main: Node = null
var _f: int = 0
var _t0: int = -1
var _cam: Camera3D = null
func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)
func _tick() -> void:
	_f += 1
	var relief: ReliefBuilder = _main.get("relief")
	if relief == null or not relief.pret:
		return
	var ph: TrainPhysics = _main.physics
	if _cam == null:
		ph.doors_open = true
		ph.door_leaves_open = true
		ph.portes_cotes = 3
		var cab: Cabin = _main.cabin
		var v0: Node3D = cab._interior_cars[0]
		_cam = Camera3D.new()
		_cam.fov = 70.0
		get_root().add_child(_cam)
		var xf: Transform3D = v0.global_transform
		# d'abord de face (perpendiculaire à la caisse), puis en enfilade
		_cam.global_position = xf * Vector3(3.3, 0.3, -1.5)
		_cam.look_at(xf * Vector3(0.0, 0.0, -1.5), Vector3.UP)
		_cam.make_current()
		_t0 = _f
		return
	_cam.make_current()
	ph.doors_open = true
	ph.door_leaves_open = true
	ph.portes_cotes = 3
	if _f - _t0 == 60:
		get_root().get_texture().get_image().save_png("/tmp/pnshots12/quai_face.png")
		var xf3: Transform3D = _main.cabin._interior_cars[0].global_transform
		_cam.global_position = xf3 * Vector3(4.2, 0.4, -9.0)
		_cam.look_at(xf3 * Vector3(0.5, -0.2, 4.0), Vector3.UP)
	if _f - _t0 == 90:
		get_root().get_texture().get_image().save_png("/tmp/pnshots12/quai.png")
		var xf2: Transform3D = _main.cabin._interior_cars[1].global_transform
		_cam.global_position = xf2 * Vector3(4.2, 0.4, 9.0)
		_cam.look_at(xf2 * Vector3(0.5, -0.2, -4.0), Vector3.UP)
	if _f - _t0 == 120:
		get_root().get_texture().get_image().save_png("/tmp/pnshots12/quai_bas.png")
		print("captures")
		quit(0)
