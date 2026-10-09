## Capture de contrôle du domaine élargi (09/10/2026) : caméra libre très
## haute au-dessus de Tignes, regard vers Val d'Isère.
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
	if _cam == null:
		_main.cabin.set_view(Cabin.ViewMode.EXTERIOR)
		_cam = Camera3D.new()
		_cam.far = 60000.0
		get_root().add_child(_cam)
		_cam.global_position = Vector3(-2500.0, 7500.0, 9000.0)
		_cam.look_at(Vector3(5500.0, 2200.0, -1000.0), Vector3.UP)
		_cam.fov = 60.0
		_cam.make_current()
		_t0 = _f
		return
	if _f - _t0 < 30:
		_cam.make_current()
	if _f - _t0 == 30:
		get_root().get_texture().get_image().save_png("/tmp/pnshots7/domaine_sud.png")
		_cam.global_position = Vector3(2000.0, 9000.0, -11000.0)
		_cam.look_at(Vector3(4000.0, 2400.0, 1500.0), Vector3.UP)
	if _f - _t0 == 60:
		get_root().get_texture().get_image().save_png("/tmp/pnshots7/domaine_nord.png")
		print("captures")
		quit(0)
