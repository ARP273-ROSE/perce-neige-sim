# Capture du skieur ASSIS sur le banc de la salle d'attente (BOUCLE, 1.19.13).
#   xvfb-run godot --path godot_project --rendering-driver opengl3 \
#     --resolution 1200x900 -s shot_assis.gd -- --mode=normal préfixe
extends SceneTree
var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _pre: String = "/tmp/assis"
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
	var ga: GareAval = _main.station_halls.gare_aval
	var sk: SkieurJoueur = _main.skieur
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	if _f > 20000:
		print("SHOT échec : pas de skieur")
		quit(1)
	if sk == null or not sk.actif:
		_t0 = _f
		return
	if _f == _t0 + 10:
		sk.activer(ga._p2(SkieurAuto.BANC, 0.05), 0.0)
	if _f == _t0 + 30:
		var n: Vector3 = ga._n
		sk.asseoir(atan2(n.x, n.z))
		sk.premiere_personne = false
		# caméra de trois quarts face, vers le banc
		sk.cam_yaw = atan2(n.x, n.z) + PI + 0.6
		sk.cam_pitch = -0.25
		sk.cam_dist = 3.0
	if _f == _t0 + 120:
		get_root().get_texture().get_image().save_png(_pre + "_banc.png")
		print("SHOT ", _pre + "_banc.png")
		quit(0)
