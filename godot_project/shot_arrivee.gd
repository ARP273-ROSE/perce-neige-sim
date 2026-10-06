# Vue cabine figée à l'arrivée en gare (rame dans le sens `dir`) :
#   godot --path godot_project --rendering-driver vulkan --resolution 1376x1032 \
#     -s shot_arrivee.gd -- --quality=high --mode=normal s=40 dir=-1 préfixe
extends SceneTree

var _main: Node = null
var _f: int = 0
var _prefix: String = "/tmp/arrivee"
var _s: float = 40.0
var _dir: int = -1
var _cache: String = ""          # nom (méta) des pièces de la salle des machines à masquer
var _sans_vol: bool = false      # sans brouillard volumétrique
var _vue: int = 0                # 0 cabine, 2 salle des machines (avant la caméra libre)
var _gros_plan: bool = false     # caméra cabine resserrée sur le pupitre
var _gp_fov: float = 30.0
var _gp_plongee: float = 0.62
var _gp_lacet: float = 0.0
var _cam: PackedFloat32Array = []  # caméra libre dans le repère de la salle des machines : s', x, y, cap°, site°, fov
var _camt: PackedFloat32Array = [] # caméra libre dans le repère du tunnel : s, x, y, cap°, site°, fov


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("s="):
			_s = float(a.substr(2))
		elif a.begins_with("dir="):
			_dir = int(a.substr(4))
		elif a.begins_with("cache="):
			_cache = a.substr(6)
		elif a == "sans_vol":
			_sans_vol = true
		elif a.begins_with("vue="):
			_vue = int(a.substr(4))
		elif a == "pupitre":
			_gros_plan = true
		elif a.begins_with("fov="):
			_gp_fov = float(a.substr(4))
		elif a.begins_with("plongee="):
			_gp_plongee = float(a.substr(8))
		elif a.begins_with("lacet="):
			_gp_lacet = float(a.substr(6))
		elif a.begins_with("camt="):
			for v in a.substr(5).split(","):
				_camt.append(float(v))
		elif a.begins_with("cam="):
			for v in a.substr(4).split(","):
				_cam.append(float(v))
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
	if _f >= 5 and _f <= 60:
		ph.direction = _dir
		ph.s = _s
		ph.s_prev_step = _s
		ph.v = 0.0
	if _f == 6 and _main.get("hud") != null:
		_main.get("hud").visible = false
	if _f == 8 and _vue != 0:
		_main.get("cabin").set_view(_vue)
	if _f == 70 and _gros_plan:
		var cf: Camera3D = _main.get("cabin").camera_fpv
		cf.fov = _gp_fov
		cf.rotate_object_local(Vector3.UP, _gp_lacet)
		cf.rotate_object_local(Vector3.RIGHT, -_gp_plongee)
	if _f == 70:
		if _cache != "":
			for c in _main.get("machine_room").get_children():
				if String(c.get_meta("nom", "")) == _cache:
					(c as Node3D).visible = false
			var ext = _main.get("machine_room").get_node_or_null("Exterieur/" + _cache)
			if ext != null:
				ext.visible = false
		if _camt.size() >= 6:
			var tun = _main.get("tunnel")
			var xt: Transform3D = tun.transform_at(_camt[0])
			var ct := Camera3D.new()
			ct.fov = _camt[5]
			ct.near = 0.05
			get_root().add_child(ct)
			var pt: Vector3 = xt.origin + xt.basis.x * _camt[1] + xt.basis.y * _camt[2]
			var cp: float = deg_to_rad(_camt[3])
			var sp: float = deg_to_rad(_camt[4])
			var dt: Vector3 = (-xt.basis.z * cos(cp) + xt.basis.x * sin(cp)) * cos(sp) + xt.basis.y * sin(sp)
			ct.look_at_from_position(pt, pt + dt, xt.basis.y)
			ct.current = true
		if _cam.size() >= 6:
			var mr = _main.get("machine_room")
			var c := Camera3D.new()
			c.fov = _cam[5]
			c.near = 0.05
			get_root().add_child(c)
			var p: Vector3 = mr._to_world(Vector3(_cam[1], _cam[2], _cam[0]))
			var xf: Transform3D = mr._xf
			var cap: float = deg_to_rad(_cam[3])
			var site: float = deg_to_rad(_cam[4])
			var avant: Vector3 = -xf.basis.z
			var h: Vector3 = (avant * cos(cap) + xf.basis.x * sin(cap))
			h.y = 0.0
			var d: Vector3 = h.normalized() * cos(site) + Vector3.UP * sin(site)
			c.look_at_from_position(p, p + d, Vector3.UP)
			c.current = true
		if _sans_vol:
			var we: WorldEnvironment = _main.find_children("*", "WorldEnvironment", true, false)[0]
			we.environment.volumetric_fog_enabled = false
	if _f == 90:
		var img: Image = get_root().get_texture().get_image()
		var nom := "%s_s%d_d%d.png" % [_prefix, int(_s), _dir]
		img.save_png(nom)
		print("ARRIVEE ", nom)
		quit(0)
