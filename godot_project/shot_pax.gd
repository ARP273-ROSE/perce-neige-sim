# Passagers de la rame vus de près (06/10/2026). Rendu Forward+ :
#   xvfb-run -a godot --path godot_project --rendering-driver vulkan \
#     --resolution 1376x1032 -s shot_pax.gd -- --quality=high --mode=normal \
#     [vue=dedans|couloir|porte|assis|orbite|orbite_loin] [pax=140] préfixe
#   dedans  : depuis le fond de la voiture avant, vers le poste
#   couloir : dans le couloir, à hauteur d'homme, vers l'arrière
#   porte   : depuis le quai, par une porte ouverte
#   assis   : de près, sur une rangée de perchoirs
extends SceneTree

var _main: Node = null
var _f: int = 0
var _prefix: String = "/tmp/pax"
var _vue: String = "dedans"
var _pax: int = 140


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("vue="):
			_vue = a.substr(4)
		elif a.begins_with("pax="):
			_pax = int(a.substr(4))
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
		ph.pax_car1 = _pax
		ph.pax_car2 = _pax
		ph.lights_cabin = true
		var cab = _main.get("cabin")
		if cab != null and cab.has_method("set_view"):
			cab.set_view(1)        # vue extérieure : la rame est dessinée en entier
		if _vue.begins_with("orbite") and cab != null:
			# caméra du jeu : orbite autour de la rame (molette = distance)
			cab.orbit_dist = 9.0 if _vue == "orbite" else 27.06
			cab.orbit_pitch = 0.06 if _vue == "orbite" else asin(10.0 / 27.06)
			cab.orbit_yaw = 1.30 if _vue == "orbite" else atan2(3.0, 25.0)
			return
		var tun = _main.get("tunnel")
		var s: float = ph.s
		# repère de la voiture avant (centre à s + 8 m)
		var xv: Transform3D = tun.transform_at(s + 8.0)
		var up: Vector3 = xv.basis.y
		var fwd: Vector3 = -xv.basis.z
		var right: Vector3 = xv.basis.x
		var y_oeil: float = -1.10 + 1.65
		var cam := Camera3D.new()
		cam.fov = 70.0
		cam.near = 0.05
		get_root().add_child(cam)
		var pos: Vector3
		var cible: Vector3
		match _vue:
			"couloir":
				pos = xv.origin + up * y_oeil + fwd * 4.0
				cible = xv.origin + up * (y_oeil - 0.35) - fwd * 3.0
			"porte":
				pos = xv.origin + up * (y_oeil - 0.1) + right * 2.6 + fwd * 0.6
				cible = xv.origin + up * (y_oeil - 0.5) - right * 0.3
			"assis":
				pos = xv.origin + up * (y_oeil - 0.2) + right * -0.2 + fwd * 2.2
				cible = xv.origin + up * (y_oeil - 0.8) + right * 0.95 + fwd * 0.6
			_:
				pos = xv.origin + up * y_oeil - fwd * 6.5
				cible = xv.origin + up * (y_oeil - 0.3) + fwd * 4.0
		cam.look_at_from_position(pos, cible, up)
		cam.current = true
		var lampe := OmniLight3D.new()
		lampe.omni_range = 12.0
		lampe.light_energy = 1.2
		get_root().add_child(lampe)
		lampe.global_position = xv.origin + up * 0.9
	if _f == 6 and _main.get("hud") != null:
		_main.get("hud").visible = false
	if _f == 120:
		var img: Image = get_root().get_texture().get_image()
		var nom := "%s_%s.png" % [_prefix, _vue]
		img.save_png(nom)
		print("PAX ", nom)
		quit(0)
