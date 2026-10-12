# Captures des bancs et porte-skis depuis l'intérieur (caméra libre
# accrochée à un palier) :
#   xvfb-run godot --path godot_project --rendering-driver opengl3 \
#     --resolution 1280x800 -s shot_bancs.gd -- --mode=normal s=1500 préfixe
extends SceneTree

var _main: Node = null
var _f: int = 0
var _prefix: String = "/tmp/bancs"
var _s: float = 1500.0
var _cam: Camera3D = null
const VUES: Array = [
	# [nom, position locale au palier, cible locale]
	["travers", Vector3(-0.6, 1.5, -0.2), Vector3(1.0, 0.5, 0.0)],
	["long", Vector3(0.3, 1.6, -2.0), Vector3(0.0, 0.5, 4.0)],
	["profil", Vector3(-0.9, 0.9, 0.0), Vector3(1.5, 0.45, 0.0)],
]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("s="):
			_s = float(a.substr(2))
		elif not a.begins_with("--"):
			_prefix = a
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _tick() -> void:
	_f += 1
	var ph = _main.get("physics")
	var cab = _main.get("cabin")
	if ph == null or cab == null:
		return
	ph.s = _s
	ph.s_prev_step = _s
	ph.v = 0.0
	var hud = _main.get("hud")
	if hud != null:
		hud.visible = false
	var i: int = (_f - 20) / 20
	if _f < 20:
		return
	if i >= VUES.size():
		quit(0)
		return
	var pal: Node3D = cab.find_child("Amenagement1_4", true, false)
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 70.0
		_cam.near = 0.05
		get_root().add_child(_cam)
	var v: Array = VUES[i]
	var o: Vector3 = pal.global_transform * (v[1] as Vector3)
	var c: Vector3 = pal.global_transform * (v[2] as Vector3)
	_cam.global_position = o
	_cam.look_at(c, Vector3.UP)
	_cam.make_current()
	if (_f - 20) % 20 == 19:
		var img: Image = get_root().get_texture().get_image()
		img.save_png("%s_%s.png" % [_prefix, v[0]])
		print("capture ", v[0])
