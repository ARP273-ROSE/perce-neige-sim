## Banc de toutes les lignes du domaine : on va au pied de chacune (carte),
## on attend qu'elle soit construite (par tranches), on relève le temps de
## construction, le nombre de véhicules, la pire image pendant 3 s, et que
## le skieur est debout au sol.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_toutes_lignes_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true
var _i: int = -1
var _t: float = 0.0
var _lg: LigneRemontee = null
var _t_constr: float = 0.0
var _pire: float = 0.0
var _phase: int = 0
var _bilan: Array = []


func _initialize() -> void:
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
	if _f < _t0 + 60:
		return
	var lignes: Array = _main.remontees.lignes
	var dt: float = 1.0 / 60.0
	_t += dt
	match _phase:
		0:
			_i += 1
			if _i >= lignes.size():
				var lents: int = 0
				for b in _bilan:
					if float(b[2]) > 40.0:
						lents += 1
				print("BILAN %d lignes, %d avec une image > 40 ms" % [_bilan.size(), lents])
				print("BENCH_TOUTES_LIGNES " + ("OK" if _ok else "ECHEC"))
				quit(0 if _ok else 1)
				return
			_lg = lignes[_i][0]
			_main.aller_a_remontee(_lg)
			_phase = 1
			_t = 0.0
		1:
			if _lg.pret:
				_t_constr = _t
				_pire = 0.0
				_phase = 2
				_t = 0.0
			elif _t > 120.0:
				print("[ECHEC] %s : pas construite en 120 s" % _lg.nom_ligne)
				_ok = false
				_phase = 0
		2:
			_pire = maxf(_pire, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			if _t > 3.0:
				var sk: SkieurJoueur = _main.skieur
				var debout: bool = sk.is_on_floor() or absf(sk.global_position.y - relief.hauteur_sol(sk.global_position.x, sk.global_position.z)) < 1.0
				var ok: bool = _lg.nombre_vehicules() > 0 and debout
				_ok = _ok and ok
				_bilan.append([_lg.nom_ligne, _t_constr, _pire])
				print("%s %-34s %3d véh. construite en %4.1f s, pire image %5.1f ms%s" % ["[OK]  " if ok else "[ECHEC]", _lg.nom_ligne,
					_lg.nombre_vehicules(), _t_constr, _pire, "" if debout else " — skieur pas au sol"])
				_phase = 0
