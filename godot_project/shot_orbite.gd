# Vue extérieure du jeu (caméra orbitale) figée, pour regarder le câble
# devant/sous la rame comme le joueur :
#   xvfb-run -a godot --path godot_project --rendering-driver vulkan \
#     --resolution 1376x1032 -s shot_orbite.gd -- --quality=high --mode=normal \
#     s=1400 yaw=3.14 pitch=0.05 dist=10 préfixe
extends SceneTree

var _main: Node = null
var _f: int = 0
var _prefix: String = "/tmp/orbite"
var _s: float = 1400.0
var _yaw: float = PI
var _pitch: float = 0.05
var _dist: float = 10.0
var _descente: float = 0.0     # m parcourus en descente avant la photo
var _plongee: bool = false      # caméra fixe plongeant sur le premier galet


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("s="):
			_s = float(a.substr(2))
		elif a.begins_with("yaw="):
			_yaw = float(a.substr(4))
		elif a.begins_with("pitch="):
			_pitch = float(a.substr(6))
		elif a.begins_with("dist="):
			_dist = float(a.substr(5))
		elif a == "plongee":
			_plongee = true
		elif a.begins_with("descente="):
			_descente = float(a.substr(9))
		elif not a.begins_with("--"):
			_prefix = a
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _tick() -> void:
	_f += 1
	var ph = _main.get("physics")
	if ph == null:
		return
	if _f >= 5 and _f <= 105:
		# rame qui descend jusqu'à _s (la visibilité des segments du câble
		# dépend du chemin parcouru, pas seulement de la position)
		var s_f: float = _s + _descente * float(105 - _f) / 100.0
		ph.s = s_f
		ph.s_prev_step = s_f
	if _f == 5:
		_main.set_tunnel_lights(true)
		var cab = _main.get("cabin")
		cab.set_view(1)
		cab.orbit_yaw = _yaw
		cab.orbit_pitch = _pitch
		cab.orbit_dist = _dist
	if _f == 106 and _plongee:
		# au-dessus de la voie, devant la rame : le câble quitte le culot,
		# touche le premier galet et repart de galet en galet
		var tr = _main.get("track")
		var tun = _main.get("tunnel")
		var s1: float = tr.coupe_brin(-1, ph.s)
		var y_c: float = tr._roller_axis_y() + tr.pulley_radius + tr.cable_radius
		# près du premier galet, en plongée oblique depuis l'amont : le câble
		# arrive du culot, touche R1 et repart de galet en galet
		var xr: Transform3D = tun.transform_at(s1)
		var lat: float = tr.strand_local_at(-1, s1).x
		var p1: Vector3 = xr.origin + xr.basis.x * lat + xr.basis.y * y_c
		var cam := Camera3D.new()
		cam.fov = 50.0
		cam.near = 0.02
		get_root().add_child(cam)
		cam.look_at_from_position(p1 + xr.basis.y * 0.55 + xr.basis.x * 0.35 - xr.basis.z * 1.6,
			p1 + xr.basis.z * 1.5, xr.basis.y)
		var lampe := OmniLight3D.new()
		lampe.omni_range = 8.0
		lampe.light_energy = 1.5
		get_root().add_child(lampe)
		lampe.global_position = p1 + xr.basis.y * 0.8 - xr.basis.z * 1.0
		cam.current = true
		print("ORBITE premier galet %.1f, rame %.1f" % [s1, ph.s])
	if _f == 6 and _main.get("hud") != null:
		_main.get("hud").visible = false
	if _f == 120:
		var img: Image = get_root().get_texture().get_image()
		var nom := "%s_s%d_y%.2f_p%.2f.png" % [_prefix, int(_s), _yaw, _pitch]
		img.save_png(nom)
		print("ORBITE ", nom)
		quit(0)
