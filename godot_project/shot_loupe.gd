## Capture de contrôle de la loupe sur le pupitre (08/10/2026) : vue cabine
## normale, puis loupe à fond.
##   xvfb-run godot --path godot_project --rendering-driver opengl3 \
##     --resolution 1920x1080 -s shot_loupe.gd -- --mode=normal préfixe
extends SceneTree

var _main: Node = null
var _f: int = 0
var _prefix: String = "/tmp/loupe"


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
	if _f == 60:
		_shot("normale")
		cab.set_loupe(true)
	elif _f == 150:
		_shot("loupe")
		cab.set_loupe(false)
	elif _f == 240:
		_shot("retour")
		quit(0)
