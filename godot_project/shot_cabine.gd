# Captures de la rame (vue cabine, vue extérieure, rame d'en face) pour
# comparer le rendu avec et sans fusion des maillages (--sans-fusion).
#   xvfb-run godot --path godot_project --rendering-driver opengl3 \
#     --resolution 1280x800 -s shot_cabine.gd -- --mode=normal préfixe
extends SceneTree

var _main: Node = null
var _f: int = 0
var _prefix: String = "/tmp/cabine"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_prefix = a
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _shot(nom: String) -> void:
	var img: Image = get_root().get_texture().get_image()
	img.save_png("%s_%s.png" % [_prefix, nom])
	print("capture ", nom)


func _tick() -> void:
	_f += 1
	var cab = _main.get("cabin")
	if cab == null:
		return
	var hud = _main.get("hud")
	if hud != null:
		hud.visible = false
	if _f == 30:
		_shot("fpv")
		cab.set_view(Cabin.ViewMode.EXTERIOR)
	elif _f == 60:
		_shot("ext")
		cab.orbit_yaw = 2.4
		cab.orbit_pitch = 0.15
		cab.orbit_dist = 14.0
	elif _f == 90:
		_shot("ext2")
		cab.orbit_yaw = -1.2
		cab.orbit_pitch = -0.05
		cab.orbit_dist = 9.0
	elif _f == 120:
		_shot("roues")
		quit(0)
