## Passage d'un véhicule sous la tête d'un pylône (contrôle des dégagements :
## pince et suspente à l'extérieur du train de galets).
##   xvfb-run godot --path godot_project --rendering-driver opengl3 \
##     --resolution 1200x800 -s shot_passage_pylone.gd -- clé préfixe
extends SceneTree
var _f: int = 0
var _ligne: LigneRemontee
var _cam: Camera3D
var _vues: Array = []
var _i: int = 0
var _pre: String = "/tmp/passage"


func _initialize() -> void:
	var args: Array = []
	for a in OS.get_cmdline_user_args():
		args.append(a)
	var cle: String = args[0] if args.size() > 0 else "tsd6_marmottes_express"
	if args.size() > 1:
		_pre = args[1]
	var D: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/remontees/%s.json" % cle))
	var racine: Node3D = Node3D.new()
	get_root().add_child(racine)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.7, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.57, 0.62)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	racine.add_child(env)
	var sol: DirectionalLight3D = DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-40, 30, 0)
	sol.shadow_enabled = true
	racine.add_child(sol)
	_ligne = LigneRemontee.new()
	var prof: PackedVector2Array = PackedVector2Array()
	for p in D["profil"]:
		prof.append(Vector2(float(p[0]), float(p[1])))
	_ligne.profil = prof
	_ligne.pylones = D["pylones"]
	_ligne.voie = float(D["voie"])
	_ligne.vitesse = float(D["vitesse"])
	_ligne.espacement = float(D["espacement"])
	_ligne.famille = String(D["famille"])
	_ligne.sens_droite = bool(D["sens_droite"])
	racine.add_child(_ligne)
	_ligne.construire()
	_ligne.set_process(false)
	var d: float = float(D["pylones"][3]["d"])
	var py: Node3D = _ligne.get_node("P4")
	for k in range(2):
		var montee: bool = k == 0
		var cible: Vector3 = Vector3(_ligne._x_brin(montee), _ligne.y_cable(d, montee), -d)
		var best: float = 0.0
		var dm: float = INF
		var s: float = 0.0
		while s < _ligne.longueur_boucle:
			var q: float = (_ligne.point(s)[0] as Vector3).distance_to(cible)
			if q < dm:
				dm = q
				best = s
			s += 0.25
		_ligne._vehicules[k][1] = best
		_ligne._placer(k)
	_cam = Camera3D.new()
	_cam.fov = 50
	racine.add_child(_cam)
	var o: Vector3 = py.position
	var yc: float = _ligne.y_cable(d)
	_vues = [["face", o + Vector3(0, yc - o.y - 1.0, 10.0), o + Vector3(0, yc - o.y - 1.0, 0)],
		["cote", o + Vector3(_ligne._x_brin(true) * 2.2, yc - o.y + 0.5, 3.5), o + Vector3(_ligne._x_brin(true), yc - o.y - 0.6, 0)],
		["dessus", o + Vector3(0.5, yc - o.y + 6.0, 6.0), o + Vector3(0, yc - o.y, 0)]]
	process_frame.connect(_tick)


func _tick() -> void:
	_f += 1
	if _i >= _vues.size():
		quit(0)
		return
	var v: Array = _vues[_i]
	if _f % 6 == 1:
		_cam.position = v[1]
		_cam.look_at(v[2], Vector3.UP)
	elif _f % 6 == 0:
		get_root().get_texture().get_image().save_png("%s_%s.png" % [_pre, v[0]])
		print("SHOT ", v[0])
		_i += 1
