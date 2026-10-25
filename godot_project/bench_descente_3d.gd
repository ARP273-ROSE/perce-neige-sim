## Banc de la descente en télésiège (retour d'utilisateur, 25/10/2026 : « les
## Leissières se prennent dans les deux sens — vérifier l'embarquement à
## l'amont ») : skieur à la ligne d'arrêt de la gare AMONT → assis par le
## siège suivant → emporté vers le bas → levé à la gare aval.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_descente_3d.gd -- --mode=normal [cle]
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true
var _phase: int = 0
var _t: float = 0.0
var _lg: LigneRemontee = null
var _y0: float = 0.0
var CLE: String = "tsd6_leissieres"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			CLE = a
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_DESCENTE " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	if _f < _t0 + 60:
		return
	var sk: SkieurJoueur = _main.skieur
	var rm: RemonteesDomaine = _main.remontees
	_t += 1.0 / 60.0
	match _phase:
		0:
			for e in rm.lignes:
				if (e[0] as Node).name == CLE:
					_lg = e[0]
			if _lg == null:
				_verif("ligne %s posée" % CLE, false)
				_fin()
				return
			# au pied de la gare AMONT : le skieur s'y rend, la ligne se construit
			var L: float = _lg.longueur_h()
			var p: Vector3 = _lg.global_transform * Vector3(_lg._x_brin(false) * 2.0, _lg.terrain(L), -L - 6.0)
			p.y = _main.relief.hauteur_sol(p.x, p.z) + 0.1
			_main.collisions.assurer_autour(p)
			sk.activer(p, 0.0)
			sk.dernier_sol = p
			_phase = 1
		1:
			if not _lg.pret:
				return
			var q: Vector3 = _lg.global_transform * _lg.point_embarquement(false)
			sk.activer(q + Vector3(0, 0.1, 0), 0.0)
			sk.basculer_ski(true)
			sk.dernier_sol = q
			_phase = 2
			_t = 0.0
		2:
			if not rm.a_bord.is_empty():
				_verif("gare amont : assis par le siège arrivé à la ligne d'arrêt", sk.embarque and sk.assis and not bool(rm.a_bord[3]),
					"%.1f s d'attente" % _t)
				_y0 = sk.global_position.y
				_phase = 3
				_t = 0.0
			elif _t > 40.0:
				_verif("gare amont : assis par le siège arrivé à la ligne d'arrêt", false, "rien en 40 s")
				_fin()
		3:
			if rm.a_bord.is_empty():
				var aval: Vector3 = _lg.global_transform * Vector3(0, _lg.terrain(0.0), 0)
				var d: float = Vector2(sk.global_position.x - aval.x, sk.global_position.z - aval.z).length()
				var dh: float = _lg.terrain(_lg.longueur_h()) - _lg.terrain(0.0)
				_verif("descendu et levé à la gare aval", not sk.embarque and d < 40.0 and sk.global_position.y < _y0 - 0.7 * dh,
					"%.0f s de trajet, %.1f m de la gare aval, %.0f m" % [_t, d, sk.global_position.y - _y0])
				_fin()
			elif _t > 600.0:
				_verif("descendu et levé à la gare aval", false, "toujours assis après 600 s")
				_fin()
