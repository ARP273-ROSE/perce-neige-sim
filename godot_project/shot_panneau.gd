## Capture de contrôle d'un panneau rond de bord de piste (09/10/2026).
##   xvfb-run godot --path godot_project --rendering-driver opengl3 \
##     --resolution 1280x800 -s shot_panneau.gd -- --mode=normal préfixe
extends SceneTree
var _main: Node = null
var _f: int = 0
var _t0: int = -1
var _pre: String = "/tmp/panneau"
var _cam: Camera3D = null
var _centre: Vector3 = Vector3.ZERO
var _nz: Vector3 = Vector3.FORWARD
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
		var p1: Vector3 = xf.origin + xf.basis.z * 3.5 + xf.basis.x * -1.0
		p1.y = relief.hauteur_sol(p1.x, p1.z) + 1.8
		_cam.global_position = p1
		_cam.look_at(xf.origin, Vector3.UP)
		_centre = xf.origin
		_nz = xf.basis.z
		_cam.fov = 50.0
		_cam.make_current()
		_t0 = _f
		print("faces : %d pistes" % faces.size())
		return
	if _f - _t0 == 4:
		get_root().get_texture().get_image().save_png(_pre + "_proche.png")
		# du bas de la piste, en regardant vers l'amont : on voit plusieurs
		# panneaux à la suite, numéros croissants en montant
		var p2: Vector3 = _centre + _nz * 30.0 + Vector3(_nz.z, 0, -_nz.x) * 6.0
		p2.y = relief.hauteur_sol(p2.x, p2.z) + 2.5
		_cam.global_position = p2
		var cible: Vector3 = _centre - _nz * 120.0
		cible.y = relief.hauteur_sol(cible.x, cible.z) + 1.5
		_cam.look_at(cible, Vector3.UP)
	if _f - _t0 == 8:
		get_root().get_texture().get_image().save_png(_pre + "_loin.png")
		print("captures")
		quit(0)
