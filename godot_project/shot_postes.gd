# Les deux postes de conduite (va-et-vient, 12/10/2026) : vue conducteur à
# la montée (poste avant) et à la descente (poste arrière), et la rame vue
# de l'extérieur par ses deux bouts.
#   xvfb-run godot --path godot_project --rendering-driver opengl3 \
#     --resolution 1280x800 -s shot_postes.gd -- --mode=normal préfixe
extends SceneTree

var _main: Node = null
var _f: int = 0
var _prefix: String = "/tmp/postes"
var _cam: Camera3D = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_prefix = a
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _shot(nom: String) -> void:
	get_root().get_texture().get_image().save_png("%s_%s.png" % [_prefix, nom])
	print("capture ", nom)


func _tick() -> void:
	_f += 1
	var ph: TrainPhysics = _main.get("physics")
	var cab: Cabin = _main.get("cabin")
	if ph == null or cab == null or _f < 20:
		return
	# rame en ligne, arrêtée à mi-pente
	ph.s = 1500.0
	ph.s_prev_step = ph.s
	ph.s_render = ph.s
	ph.v = 0.0
	var hud = _main.get("hud")
	if hud != null:
		hud.visible = false
	match _f:
		30:
			ph.direction = 1
		40:
			cab.camera_fpv.make_current()
		46:
			_shot("montee_poste_avant")
		50:
			ph.direction = -1
		60:
			cab.camera_fpv.make_current()
		66:
			_shot("descente_poste_arriere")
		70:
			_cam = Camera3D.new()
			_cam.fov = 60.0
			get_root().add_child(_cam)
		72, 82:
			# dans le tube, 9 m devant un bout de la rame, regard vers elle
			var v: Node3D = cab._interior_cars[0 if _f == 72 else cab.car_count - 1]
			var sgn: float = -1.0 if _f == 72 else 1.0
			var o: Vector3 = v.global_transform * Vector3(0.6, 0.6, sgn * 17.0)
			_cam.global_position = o
			_cam.look_at(v.global_transform * Vector3(0.0, 0.3, sgn * 8.0), Vector3.UP)
			_cam.make_current()
		78:
			_shot("bout_amont")
		88:
			_shot("bout_aval")
			quit(0)
