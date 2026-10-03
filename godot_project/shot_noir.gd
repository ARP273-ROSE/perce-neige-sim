# Vue cabine dans le tunnel, éclairage du tunnel coupé, pour vérifier le
# « noir total » (retour du 03/10 : « noir ça veut dire qu'on ne voit rien
# du tout, même à 1 m »).
#   xvfb-run -a godot --path godot_project --rendering-driver opengl3 \
#     --resolution 1376x1032 -s shot_noir.gd -- [s=1300] [phares] [cabine] [tunnel]
#     [p=énergie,angle,att_cône,att_distance,inclinaison] [env.prop=valeur]
#     [vitre-off] [pb-off] [sans-glow] préfixe
# Rendu PC (Forward+) : --rendering-driver vulkan --rendering-method forward_plus
# (lavapipe récent ou GPU). Affiche la luminance moyenne et le 99e centile de
# l'image (0-255), puis les lumières et les matériaux transparents/émissifs
# proches de la caméra (MATDBG) : c'est ainsi qu'on a trouvé le voile brun du
# pare-brise (03/10/2026).
extends SceneTree

var _main: Node = null
var _f: int = 0
var _prefix: String = "/tmp/noir"
var _s: float = 1300.0
var _phares: bool = false
var _cabine: bool = false
var _sans_glow: bool = false
var _vitre_off: bool = false
var _tunnel: bool = false
var _caches: PackedStringArray = []   # cache=<nœud sous Main> : masque ce nœud
var _matdbg_dist: float = 4.0    # matdbg=<m> : rayon de la liste des matériaux
var _pb_off: bool = false
var _env_set: Dictionary = {}       # env.propriété=valeur (str_to_var)
var _params: PackedStringArray = []   # p=énergie,angle,att_cône,att_distance,inclinaison°


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("s="):
			_s = float(a.substr(2))
		elif a == "phares":
			_phares = true
		elif a == "cabine":
			_cabine = true
		elif a.begins_with("env."):
			var kv := a.substr(4).split("=")
			_env_set[kv[0]] = str_to_var(kv[1])
		elif a.begins_with("p="):
			_params = a.substr(2).split(",")
		elif a.begins_with("matdbg="):
			_matdbg_dist = float(a.substr(7))
		elif a.begins_with("cache="):
			_caches.append(a.substr(6))
		elif a == "tunnel":
			_tunnel = true
		elif a == "vitre-off":
			_vitre_off = true
		elif a == "pb-off":
			_pb_off = true
		elif a == "sans-glow":
			_sans_glow = true
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
		ph.lights_head = _phares
		ph.lights_cabin = _cabine
		_main.set_tunnel_lights(_tunnel)
		for c in _caches:
			if c.begins_with("*"):
				for n in _main.find_children(c, "Node3D", true, false):
					(n as Node3D).visible = false
			else:
				(_main.get_node(c) as Node3D).visible = false
		if "--liste-voie" in OS.get_cmdline_user_args():
			var noms := {}
			for n in _main.get_node("Track").get_children():
				var k: String = String(n.name).rstrip("0123456789_")
				noms[k] = noms.get(k, 0) + 1
			print("VOIE ", noms)
		if _params.size() == 5:
			var cab = _main.get("cabin")
			cab.head_energy = float(_params[0])
			cab.headlight_front.spot_angle = float(_params[1])
			cab.headlight_front.spot_angle_attenuation = float(_params[2])
			cab.headlight_front.spot_attenuation = float(_params[3])
			cab.headlight_front.rotation.x = deg_to_rad(float(_params[4]))
		for k in _env_set:
			(_main.get_node("WorldEnvironment") as WorldEnvironment).environment.set(k, _env_set[k])
		var mats: Dictionary = _main.get("cabin").get("_body_mats")
		if _vitre_off:
			(mats["glass"] as StandardMaterial3D).emission_enabled = false
		if _pb_off:
			(mats["windshield"] as StandardMaterial3D).albedo_color.a = 0.0
		if _sans_glow:
			(_main.get_node("WorldEnvironment") as WorldEnvironment).environment.glow_enabled = false
	if _f == 6 and _main.get("hud") != null:
		_main.get("hud").visible = false
	if _f == 90:
		var img: Image = get_root().get_texture().get_image()
		var nom := "%s_s%d%s%s%s%s.png" % [_prefix, int(_s), "_phares" if _phares else "",
			(("_" + "_".join(PackedStringArray(_env_set.keys()))) if not _env_set.is_empty() else "")
				+ ("_vitreoff" if _vitre_off else "") + ("_tunnel" if _tunnel else "") + ("_pboff" if _pb_off else ""),
			("_" + "_".join(_params)) if _params.size() == 5 else "",
			"_cabine" if _cabine else ""]
		img.save_png(nom)
		var lum: PackedFloat32Array = []
		var somme := 0.0
		for y in range(0, img.get_height(), 4):
			for x in range(0, img.get_width(), 4):
				var c := img.get_pixel(x, y)
				var l := (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0
				lum.append(l)
				somme += l
		lum.sort()
		var cam := get_root().get_viewport().get_camera_3d()
		for n in get_root().find_children("*", "GeometryInstance3D", true, false):
			var g := n as GeometryInstance3D
			if not g.is_visible_in_tree():
				continue
			var ab: AABB = g.global_transform * g.get_aabb()
			if ab.grow(1.0).has_point(cam.global_position) or ab.get_center().distance_to(cam.global_position) < _matdbg_dist:
				var info := []
				if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
					var mi := g as MeshInstance3D
					for i in mi.mesh.get_surface_count():
						var m = mi.get_active_material(i)
						if m is BaseMaterial3D:
							var bm := m as BaseMaterial3D
							if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or bm.emission_enabled or bm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
								info.append("s%d tr=%d em=%s unsh=%s alb=%s" % [i, bm.transparency, bm.emission_enabled, bm.shading_mode == 0, bm.albedo_color])
						elif m != null:
							info.append("s%d %s" % [i, m.get_class()])
				if not info.is_empty():
					print("MATDBG %s %s" % [g.get_path(), info])
		for n in get_root().find_children("*", "Light3D", true, false):
			var l := n as Light3D
			if l.is_visible_in_tree() and l.light_energy > 0.0:
				var d := l.global_position.distance_to(cam.global_position)
				if d < 60.0:
					print("LUMIERE %s %s e=%.2f d=%.1f" % [l.get_path(), l.get_class(), l.light_energy, d])
		print("NOIR %s moyenne=%.2f p99=%.1f max=%.1f" % [nom, somme / lum.size(),
			lum[int(lum.size() * 0.99)], lum[lum.size() - 1]])
		quit(0)
