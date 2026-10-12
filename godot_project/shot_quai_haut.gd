# Quai de la gare haute (12/10/2026) : la barrière bleue hors du gabarit de
# la rame, et la bouche du tunnel au passage de la rame.
#   xvfb-run godot --path godot_project --rendering-driver opengl3 \
#     --resolution 1280x800 -s shot_quai_haut.gd -- --mode=normal préfixe
extends SceneTree

var _main: Node = null
var _f: int = 0
var _prefix: String = "/tmp/quai_haut"
var _cam: Camera3D = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_prefix = a
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _tick() -> void:
	_f += 1
	var ph: TrainPhysics = _main.get("physics")
	if ph == null or _f < 20:
		return
	var tun: TunnelBuilder = _main.tunnel
	var hud = _main.get("hud")
	if hud != null:
		hud.visible = false
	if _f < 60:
		var s: float = PNConstants.STOP_S
		ph.s = s
		ph.s_prev_step = s
		ph.s_render = s
		ph.v = 0.0
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 70.0
		get_root().add_child(_cam)
	match _f:
		30:
			# sur le quai gauche, en haut, regard vers l'aval le long de la rame
			var xa: Transform3D = tun.transform_at(PNConstants.STOP_S + PNConstants.TRAIN_HALF + 2.0)
			_cam.global_position = xa.origin + xa.basis.x * -2.6 + xa.basis.y * 0.4
			var xb: Transform3D = tun.transform_at(PNConstants.STOP_S - 4.0)
			_cam.look_at(xb.origin + xb.basis.x * -1.2 + xb.basis.y * -0.6, Vector3.UP)
			_cam.make_current()
		36:
			get_root().get_texture().get_image().save_png(_prefix + "_quai.png")
			print("capture quai")
		42:
			# comme la photo 095520 : du haut du quai droit, vers l'aval
			var xc: Transform3D = tun.transform_at(PNConstants.STOP_S + PNConstants.TRAIN_HALF - 1.0)
			_cam.global_position = xc.origin + xc.basis.x * 3.0 + xc.basis.y * 0.6
			var xd: Transform3D = tun.transform_at(PNConstants.STOP_S - 25.0)
			_cam.look_at(xd.origin + xd.basis.x * 1.5 + xd.basis.y * 0.3, Vector3.UP)
			_cam.make_current()
		48:
			get_root().get_texture().get_image().save_png(_prefix + "_aval.png")
			print("capture aval")
			quit(0)
