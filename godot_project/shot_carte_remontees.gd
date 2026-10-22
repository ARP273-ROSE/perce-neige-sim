## Capture de la carte des pistes dézoomée avec les remontées (« aller à »).
extends SceneTree
var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _pre: String = "/tmp/carte"
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_pre = a
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)
func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	if _f == _t0 + 60:
		_main.commandes_skieur._b_carte.button_pressed = true
		_main.commandes_skieur.carte.echelle = 0.045
	if _f == _t0 + 90:
		get_root().get_texture().get_image().save_png(_pre + "_carte.png")
		print("SHOT")
		quit(0)
