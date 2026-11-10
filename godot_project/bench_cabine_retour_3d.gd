## Banc « je reste dans la cabine » (retour d'utilisateur, 02/11/2026 : « le cas où je ne
## descends pas de la cabine et que je repars dans l'autre sens, je reste debout ») :
## montée à bord en bas, on ne touche à rien en haut : il doit repartir assis, avec
## sa pique, et revenir jusqu'en bas.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_cabine_retour_3d.gd
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true
var _phase: int = 0
var _t: float = 0.0
var _lg: LigneRemontee = null
var _piques: Array = []


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_CABINE_RETOUR " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _ok else 1)


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	if _f < _t0 + 60 or not _main.mode_skieur:
		return
	var sk: SkieurJoueur = _main.skieur
	var rm: RemonteesDomaine = _main.remontees
	_t += 1.0 / 60.0
	match _phase:
		0:
			for e in rm.lignes:
				if (e[0] as Node).name == "tcd8_brevieres":
					_lg = e[0]
			rm.pique.connect(func(evt: String, _l: LigneRemontee) -> void: _piques.append(evt))
			_main.aller_a_remontee(_lg)
			_phase = 1
			_t = 0.0
		1:
			if _lg.pret:
				_phase = 2
				_t = 0.0
			elif _t > 180.0:
				_verif("ligne construite", false)
				_fin()
		2:
			for i in range(_lg._vehicules.size()):
				var z: Array = _lg.zone(_lg._vehicules[i][1])
				if z[0] == "gare_aval" and rm._repos <= 0.0:
					var x: float = z[1]
					if x > LigneRemontee.L_FREIN + 4.0 and x < z[2] - LigneRemontee.L_FREIN - 6.0:
						var v: VehiculeRemontee = _lg.vehicule(i)
						sk.activer(v.global_transform * (v.place_assise(2) + Vector3(0, 0.05, 0)), 0.0)
						_phase = 3
						_t = 0.0
						return
			if _t > 200.0:
				_verif("une cabine à quai", false)
				_fin()
		3:
			if _t > 1.5 and rm.a_bord.is_empty():
				_verif("arrivé en haut, portes ouvertes, debout", not sk.assis)
				_phase = 4
				_t = 0.0
			elif _t > 500.0:
				_verif("arrivé en haut", false, "toujours à bord")
				_fin()
		4:
			if not rm.a_bord.is_empty():
				_verif("resté à bord : assis pour le retour", sk.assis and sk.embarque, "après %.1f s" % _t)
				_verif("resté à bord : pique RESTE", _piques.has("RESTE"), str(_piques))
				_phase = 5
				_t = 0.0
			elif _t > 120.0:
				_verif("resté à bord : assis pour le retour", false, "toujours debout, assis=%s" % str(sk.assis))
				_fin()
		5:
			if rm.a_bord.is_empty():
				var bas: Vector3 = _lg.global_transform.origin
				var d: float = Vector2(sk.global_position.x - bas.x, sk.global_position.z - bas.z).length()
				_verif("revenu en bas, portes ouvertes", d < 60.0, "%.0f m de la gare aval, %.0f s" % [d, _t])
				_fin()
			elif _t > 500.0:
				_verif("revenu en bas", false, "toujours à bord")
				_fin()
