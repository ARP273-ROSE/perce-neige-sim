# Captures de l'aiguillage Abt en vrai rendu Godot (sans GPU : Xvfb + Mesa).
#   xvfb-run -s "-screen 0 1600x1000x24" godot --path godot_project \
#     --rendering-driver opengl3 -s shot_aiguillage.gd -- dossier_sortie
extends SceneTree

var _tunnel: TunnelBuilder
var _root: Node3D
var _cam: Camera3D
var _out: String = "/tmp"
var _shots: Array = []
var _frame: int = 0
var _idx: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_root = Node3D.new()
	get_root().add_child(_root)
	_tunnel = TunnelBuilder.new()
	_tunnel.ring_spacing = 3.0
	_tunnel.ring_segments = 24
	_tunnel.tunnel_radius = PNConstants.TUNNEL_RADIUS
	_root.add_child(_tunnel)
	process_frame.connect(_suite, CONNECT_ONE_SHOT)


func _suite() -> void:
	var tr: TrackBuilder = TrackBuilder.new()
	_root.add_child(tr)
	tr.build(_tunnel)
	# parois du tunnel masquées : on regarde la voie en plein jour
	for c in _tunnel.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).visible = false
	for n in ["SegmentRings", "CrownPipe", "GalleryJoints", "LoopLamps"]:
		var node: Node = tr.get_node_or_null(n)
		if node != null:
			(node as Node3D).visible = false
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.70)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.ambient_light_energy = 0.9
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	_root.add_child(we)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_energy = 1.3
	_root.add_child(sun)
	sun.look_at_from_position(Vector3(0, 10, 0), Vector3(3, 0, 4), Vector3.UP)
	_cam = Camera3D.new()
	_cam.near = 0.02
	_cam.far = 400.0
	_cam.fov = 60.0
	_root.add_child(_cam)
	_cam.current = true
	var s0: float = PNConstants.PASSING_START
	# [nom, s caméra, x, y, s visée, x, y, fov]
	_shots = [
		["1_voie_unique", s0 - 5.0, 0.0, 0.45, s0 + 16.0, 0.0, -1.30, 55.0],
		["2_coeur_X", s0 + 19.0, 0.0, -0.30, s0 + 30.0, 0.0, -1.30, 55.0],
		["3_fenetre", s0 + 17.3, -0.66, -1.17, s0 + 17.6, 0.25, -1.36, 50.0],
		["3b_fenetre_dessus", s0 + 15.2, -0.30, -0.92, s0 + 17.5, -0.36, -1.33, 45.0],
		["4_galet_deviation", s0 + 19.9, 0.10, -0.85, s0 + 22.0, -0.55, -1.40, 45.0],
		["5_dessus", s0 + 20.0, 0.0, 16.0, s0 + 20.0, 0.0, -1.3, 42.0],
		["6_courbe_cable", 1420.0, -0.12, -0.9, 1440.0, -0.12, -1.36, 40.0],
	]
	if OS.get_cmdline_user_args().size() > 1:
		var keep: PackedStringArray = OS.get_cmdline_user_args()[1].split(",")
		_shots = _shots.filter(func(sh: Array) -> bool: return keep.has(sh[0]))
	process_frame.connect(_tick)


func _place(sh: Array) -> void:
	var a: Transform3D = _tunnel.transform_at(sh[1])
	var b: Transform3D = _tunnel.transform_at(sh[4])
	var eye: Vector3 = a.origin + a.basis.x * sh[2] + a.basis.y * sh[3]
	var tgt: Vector3 = b.origin + b.basis.x * sh[5] + b.basis.y * sh[6]
	var up: Vector3 = a.basis.y
	if sh[0] == "5_dessus":
		up = -a.basis.z
	_cam.fov = sh[7]
	_cam.look_at_from_position(eye, tgt, up)


func _tick() -> void:
	_frame += 1
	if _idx >= _shots.size():
		quit(0)
		return
	if _frame == 1:
		_place(_shots[_idx])
	elif _frame == 4:
		var img: Image = get_root().get_viewport().get_texture().get_image()
		var p: String = "%s/aiguillage_%s.png" % [_out, _shots[_idx][0]]
		img.save_png(p)
		print("capture ", p, " ", img.get_size())
		_idx += 1
		_frame = 0
