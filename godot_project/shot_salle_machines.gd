# Captures de la vue « salle des machines » (caméra libre + écorché), vrai
# rendu Godot sans GPU :
#   xvfb-run -s "-screen 0 1600x1000x24" godot --path godot_project \
#     --rendering-driver opengl3 -s shot_salle_machines.gd -- dossier_sortie
extends SceneTree

var _tunnel: TunnelBuilder
var _root: Node3D
var _cam: MachineRoomCamera
var _mr: MachineRoomBuilder
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
	var st: StationsBuilder = StationsBuilder.new()
	_root.add_child(st)
	st.build(_tunnel)
	_mr = MachineRoomBuilder.new()
	_root.add_child(_mr)
	_mr.build(_tunnel)
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.82)
	env.ambient_light_energy = 0.55
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	_root.add_child(we)
	_cam = MachineRoomCamera.new()
	_root.add_child(_cam)
	_cam.setup(_mr)
	_cam.current = true
	_mr.set_cutaway(true)
	# [nom, yaw, pitch, dist, pan x, pan s, pan y]
	_shots = [
		["1_defaut", 0.95, 0.32, 11.0, 0.0, 0.0, 0.0],
		["2_dessus", 0.3, 1.35, 13.0, 0.0, 0.0, 0.0],
		["3_dessous", -0.8, -0.45, 9.0, 0.0, 0.0, 0.0],
		["3b_contre_plongee", 2.2, -0.9, 6.0, 0.0, 0.0, 0.0],
		["4_cote_gauche", -1.7, 0.15, 10.0, 0.0, 0.0, 0.0],
		["5_zoom_roue_aval", 1.3, 0.2, 4.5, 0.0, -3.3, 0.8],
		["6_amont", 3.0, 0.35, 10.0, 0.0, 0.0, 0.0],
		["7_profil", 1.5708, 0.02, 11.0, 0.0, 0.0, 0.3],
		["8_hall", 0.55, 0.55, 9.0, 0.0, 0.8, 1.6],
		["9_sommet_aval", 0.9, 0.35, 2.6, 0.0, -3.3, 1.75],
		["9b_sommet_aval", 1.9, 0.45, 2.2, 0.2, -3.0, 1.75],
		["9c_sommet_aval", 1.35, 0.9, 2.0, 0.2, -3.3, 1.75],
		["10_croisement", -1.35, 0.05, 5.5, 0.0, 0.0, -0.4],
		["11_roue_aval_flanc", 1.5708, 0.05, 5.0, 0.2, -3.3, -0.3],
		["12_roue_aval_gauche", -1.5708, 0.05, 5.0, 0.2, -3.3, -0.3],
		["13_freins_bas", 1.05, 0.10, 2.2, 0.55, -3.9, -1.6],
		["14_freins_amont", 1.05, 0.10, 2.2, 0.55, 2.7, -1.6],
		["15_roue_aval_dessous", 0.55, -0.35, 4.0, 0.0, -3.3, 0.0],
		["16_roue_aval_haut", 0.9, 0.55, 3.2, 0.0, -3.3, 1.3],
	]
	if OS.get_cmdline_user_args().size() > 1:
		var keep: PackedStringArray = OS.get_cmdline_user_args()[1].split(",")
		_shots = _shots.filter(func(sh: Array) -> bool: return keep.has(sh[0]))
	process_frame.connect(_tick)


func _tick() -> void:
	_frame += 1
	if _idx >= _shots.size():
		quit(0)
		return
	var sh: Array = _shots[_idx]
	if _frame == 1:
		_cam.yaw = sh[1]
		_cam.pitch = sh[2]
		_cam.dist = sh[3]
		_cam.pan = Vector2(sh[4], sh[5])
		_cam.pan_y = sh[6]
	elif _frame == 5:
		var img: Image = get_root().get_viewport().get_texture().get_image()
		var p: String = "%s/salle_%s.png" % [_out, sh[0]]
		img.save_png(p)
		print("capture ", p)
		_idx += 1
		_frame = 0
