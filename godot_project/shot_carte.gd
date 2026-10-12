# Carte des pistes (12/10/2026) : vrai tracé du funiculaire et rames en
# direct. xvfb-run godot --path godot_project --rendering-driver opengl3 \
#   --resolution 1280x800 -s shot_carte.gd -- --mode=normal préfixe
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
	var ph: TrainPhysics = _main.physics
	ph.s = 1400.0
	ph.s_render = ph.s
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	var sk: SkieurJoueur = _main.skieur
	if sk == null or not sk.actif:
		_t0 = _f
		return
	if _f == _t0 + 10:
		var o: Vector3 = _main.tunnel.transform_at(1800.0).origin
		var q: Vector2 = Vector2(o.x + 150.0, o.z)
		sk.activer(Vector3(q.x, relief.hauteur_sol(q.x, q.y) + 0.1, q.y), 0.0)
	if _f == _t0 + 20:
		_main.basculer_ski()
		_main.commandes_skieur.carte.echelle = 0.07
	if _f == _t0 + 60:
		get_root().get_texture().get_image().save_png(_pre + ".png")
		print("SHOT carte")
		quit(0)
