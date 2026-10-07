# Sonde : coût de rendu de chaque branche (objets, appels, triangles
# mesurés par le moteur) en la masquant à tour de rôle, rame à l'arrêt.
#   xvfb-run godot --path godot_project --rendering-driver opengl3 \
#     --resolution 960x540 -s sonde_couts.gd -- --mode=normal --cran=3 s=600 \
#     [noms=PupitreConduite,hud,hud*,ecran,lumieres]
# Sans noms= : les enfants de la scène et de la cabine. hud* = chaque
# enfant du HUD ; ecran = l'écran Pro-face du pupitre ; lumieres = chaque
# lampe. --cran=3 fige la qualité (sinon le PerfManager la change en route).
extends SceneTree
var _main: Node = null
var _f: int = 0
var _s: float = 600.0
var _cibles: Array = []
var _i: int = -1
var _acc: Array = []
var _base: Array = []
const N: int = 8

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("s="):
			_s = float(a.substr(2))
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)

func _montrer(n: Node, v: bool) -> void:
	if n is SubViewport:
		(n as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS if v else SubViewport.UPDATE_DISABLED
		var pup = n.get_parent()
		pup.set("ecran", pup.get_node(NodePath(n.name)).get_child(0) if v else null)
	elif n == _main:
		pass
	else:
		n.set("visible", v)


func _mesure() -> Array:
	return [Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)]

func _tick() -> void:
	_f += 1
	var ph = _main.get("physics")
	var cab = _main.get("cabin")
	if ph == null or cab == null:
		return
	ph.s = _s
	ph.s_prev_step = _s
	ph.v = 0.0
	if _f == 80:
		var noms: String = ""
		for a in OS.get_cmdline_user_args():
			if a.begins_with("noms="):
				noms = a.substr(5)
		if noms != "":
			for nom in noms.split(","):
				if nom == "lumieres":
					# chaque lampe de la scène, une à une (les plus coûteuses ressortent)
					for l in _main.find_children("*", "Light3D", true, false):
						if (l as Light3D).visible:
							_cibles.append(l)
					continue
				if nom == "ecran":
					var pup = _main.get("cabin").find_child("PupitreConduite", true, false)
					_cibles.append(pup.get("_sv"))
					continue
				if nom == "hud*":
					for c in _main.get("hud").get_children():
						_cibles.append(c)
					continue
				var n: Node = _main.get(nom) as Node if nom in ["hud"] else _main.find_child(nom, true, false)
				if n != null:
					_cibles.append(n)
		else:
			for c in _main.get_children():
				if c is Node3D and (c as Node3D).visible:
					_cibles.append(c)
			for c in cab.get_children():
				if c is Node3D and (c as Node3D).visible:
					_cibles.append(c)
	if _f < 80:
		return
	var k: int = (_f - 80) / (N + 2)
	var ph_k: int = (_f - 80) % (N + 2)
	if k > _cibles.size():
		quit(0)
		return
	if ph_k == 0:
		if k >= 1:
			_montrer(_cibles[k - 1], true)
		if k < _cibles.size() and k > 0:
			_montrer(_cibles[k], false)
		_acc = [0.0, 0.0, 0.0]
		return
	if ph_k < 2:
		return
	var m: Array = _mesure()
	for j in range(3):
		_acc[j] += m[j] / N
	if ph_k == N + 1:
		if k == 0:
			_base = _acc.duplicate()
			print("BASE s=%.0f : %d objets, %d appels, %d triangles" % [_s, _base[0], _base[1], _base[2]])
			# la mesure 0 se fait sans rien masquer : on décale les cibles
			_cibles.push_front(_main)  # factice, jamais masqué (k=0)
		else:
			var nom: String = str(_main.get_path_to(_cibles[k]))
			var d0: float = _base[0] - _acc[0]
			var d1: float = _base[1] - _acc[1]
			var d2: float = _base[2] - _acc[2]
			if d0 >= 3 or d1 >= 3 or d2 > 2000:
				print("  %-45s -%4d obj  -%4d appels  -%7d tri" % [nom, d0, d1, d2])
