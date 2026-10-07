## Captures du ski (contrôle à l'œil) : le skieur chaussé sur une descente
## réelle, le fantôme devant lui, les pistes damées et balisées.
##   xvfb-run godot --path godot_project --rendering-driver opengl3 \
##     --resolution 1376x1032 -s shot_ski.gd -- --mode=normal préfixe
extends SceneTree

var _main: Node = null
var _f: int = 0
var _pre: String = "/tmp/ski"
var _vues: Array = []         # [nom, descente, t (s), recul fantôme (s), dist caméra, tangage]
var _t0: int = -1


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_pre = a
	_vues = [["piste_haut", 3, 40, -2, 4.5, -0.25], ["virage", 3, 120, -2, 5.5, -0.35],
		["vers_val_claret", 3, 330, -6, 6.0, -0.30], ["glacier", 0, 30, -5, 5.0, -0.30]]
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _tick() -> void:
	_f += 1
	var relief: ReliefBuilder = _main.get("relief")
	if relief == null or not relief.pret:
		return
	if _t0 < 0:
		_main._depart_haut = true
		_main.basculer_skieur()
		_t0 = _f
		return
	var i: int = (_f - _t0 - 30) / 60
	var j: int = (_f - _t0 - 30) % 60
	if _f - _t0 < 30:
		return
	if i >= _vues.size():
		quit(0)
		return
	var vu: Array = _vues[i]
	var sk: SkieurJoueur = _main.skieur
	var pts: PackedVector2Array = FantomesDonnees.points(vu[1])
	var t: int = mini(vu[2], pts.size() - 10)
	if j == 1:
		if sk.chausse:
			_main.basculer_ski()
		var p: Vector2 = pts[t]
		sk.global_position = Vector3(p.x, relief.hauteur_sol(p.x, p.y), p.y)
		var d: Vector2 = pts[t + 4] - pts[t]
		sk._cap = atan2(-d.x, -d.y)
		_main.basculer_ski()
		sk.cam_yaw = sk._cap
		sk.cam_pitch = vu[5]
		sk.cam_dist = vu[4]
		var fa: FantomeSki = _main.domaine.fantome
		fa.demarrer(vu[1])
		fa.t = float(t - int(vu[3]))
		fa._placer()
	if j == 59:
		var img: Image = get_root().get_texture().get_image()
		img.save_png("%s_%d_%s.png" % [_pre, i, vu[0]])
		print("capture ", vu[0])
