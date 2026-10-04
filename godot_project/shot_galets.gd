# Vues rapprochées des galets, de leurs supports et du culot d'attache
# (05/10/2026). Rendu Forward+ (Vulkan) :
#   xvfb-run -a godot --path godot_project --rendering-driver vulkan \
#     --resolution 1376x1032 -s shot_galets.gd -- --quality=high --mode=normal \
#     s=1000 vue=nez|cote|dessus|culot [recul=2.5] préfixe
#   nez    : depuis la vitre avant, le support suivant à `recul` m
#   cote   : depuis le côté de la voie, en plongée sur le support
#   dessus : à la verticale du support (on voit le V des joues)
#   culot  : dans la fosse, sous la voiture amont, vers le culot
extends SceneTree

var _main: Node = null
var _f: int = 0
var _prefix: String = "/tmp/galets"
var _s: float = 1000.0
var _vue: String = "nez"
var _recul: float = 2.5


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("s="):
			_s = float(a.substr(2))
		elif a.begins_with("vue="):
			_vue = a.substr(4)
		elif a.begins_with("recul="):
			_recul = float(a.substr(6))
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
	if _f == 5:
		ph.s = _s
		ph.s_prev_step = _s
		_main.set_tunnel_lights(true)
		var tr = _main.get("track")
		var tun = _main.get("tunnel")
		var s_nez: float = _s + PNConstants.TRAIN_HALF + 0.6
		var s_sup: float = -1.0
		for st in tr.station_list():
			if _vue == "culot":
				break
			if float(st.s) > s_nez + 1.0:
				s_sup = st.s
				break
		var cam := Camera3D.new()
		cam.fov = 60.0
		cam.near = 0.02
		get_root().add_child(cam)
		var y_axe: float = tr._roller_axis_y()
		if _vue == "culot":
			var att: float = TrackBuilder.attache_s(_s)
			var xf: Transform3D = tun.transform_at(att - 1.6)
			var xa: Transform3D = tun.transform_at(att)
			var pos: Vector3 = xf.origin + xf.basis.x * 0.32 + xf.basis.y * (y_axe - 0.05)
			var cible: Vector3 = xa.origin + xa.basis.x * -0.12 + xa.basis.y * (y_axe + 0.3)
			cam.look_at_from_position(pos, cible, xf.basis.y)
			var lampe := OmniLight3D.new()
			lampe.omni_range = 4.0
			lampe.light_energy = 2.0
			get_root().add_child(lampe)
			lampe.global_position = pos + xf.basis.y * 0.1 - xf.basis.z * 0.5
		else:
			var xs: Transform3D = tun.transform_at(s_sup)
			# voie de la rame 1 (gauche dans l'évitement)
			var dx: float = tun.passing_loop_offset(s_sup, -1.0)
			var centre: Vector3 = xs.origin + xs.basis.y * y_axe + xs.basis.x * (dx - 0.12)
			var pos: Vector3
			match _vue:
				"cote":
					var xc: Transform3D = tun.transform_at(s_sup - 0.6)
					pos = xc.origin + xc.basis.x * (dx + 0.95) + xc.basis.y * (y_axe + 0.75)
				"dessus":
					var xd: Transform3D = tun.transform_at(s_sup - 0.25)
					pos = xd.origin + xd.basis.x * (dx + 0.05) + xd.basis.y * (y_axe + 1.3)
				_:
					var xn: Transform3D = tun.transform_at(s_sup - _recul)
					pos = xn.origin + xn.basis.y * -0.2 \
						+ xn.basis.x * tun.passing_loop_offset(s_sup - _recul, -1.0)
			cam.look_at_from_position(pos, centre, xs.basis.y)
			print("GALETS support à s = %.1f, caméra %s" % [s_sup, _vue])
		cam.current = true
	if _f == 6 and _main.get("hud") != null:
		_main.get("hud").visible = false
	if _f == 90:
		var img: Image = get_root().get_texture().get_image()
		var nom := "%s_%s_s%d.png" % [_prefix, _vue, int(_s)]
		img.save_png(nom)
		print("GALETS ", nom)
		quit(0)
