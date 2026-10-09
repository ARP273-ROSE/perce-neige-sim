## Capture de contrôle d'un panneau rond de bord de piste (09/10/2026).
##   xvfb-run godot --path godot_project --rendering-driver opengl3 \
##     --resolution 1280x800 -s shot_panneau.gd -- --mode=normal préfixe
extends SceneTree
var _main: Node = null
var _f: int = 0
var _t0: int = -1
var _pre: String = "/tmp/panneau"
var _cam: Camera3D = null
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
	if _cam == null and _f - _t0 < 240:
		return
	var dom: Node = _main.get("domaine")
	var faces: Array = dom.find_children("PanneauxFaces*", "MultiMeshInstance3D", true, false)
	if faces.is_empty():
		if _f - _t0 > 900:
			print("pas de faces")
			quit(1)
		return
	if _cam == null:
		var mm: MultiMesh = (faces[min(3, faces.size() - 1)] as MultiMeshInstance3D).multimesh
		var xf: Transform3D = mm.get_instance_transform(0)
		_cam = Camera3D.new()
		get_root().add_child(_cam)
		_cam.global_position = xf.origin + xf.basis.z * 2.2 + Vector3.UP * 0.1
		_cam.look_at(xf.origin, Vector3.UP)
		_cam.fov = 50.0
		_cam.make_current()
		_t0 = _f
		print("faces : %d pistes" % faces.size())
		return
	if _f - _t0 == 4:
		get_root().get_texture().get_image().save_png(_pre + "_proche.png")
		_cam.global_position += (_cam.global_position - _cam.global_transform.origin)
		var d: Vector3 = -_cam.global_transform.basis.z
		_cam.global_position -= d * 10.0
	if _f - _t0 == 8:
		get_root().get_texture().get_image().save_png(_pre + "_loin.png")
		print("captures")
		quit(0)
