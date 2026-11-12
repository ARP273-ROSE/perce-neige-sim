## Banc des échelles des pylônes en treillis (retour d'utilisateur du 12/11/2026 : « je veux grimper partout ») : pour
## le 3S (P1 à fût, ouvrage du haut) et les deux téléphériques, déchaussé au pied, GRIMPER monte jusqu'en haut ;
## de nouveau : redescend et lâche, au sol, sans chute.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_echelle_treillis_3d.gd
extends SceneTree
var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _p: int = 0
var _lg: LigneRemontee = null
var _py: PyloneTreillis = null
var _t: float = 0.0
var _cas: Array = [["olympique", 0], ["olympique", 1], ["olympique", -1], ["tph_grande_motte", 0]]     # (le Fornet : une seule portée, sans pylône)
var _i: int = 0
var _ok: bool = true
var _y_depart: float = 0.0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _fin_cas(ok: bool, msg: String) -> void:
	print(("[OK]    " if ok else "[ECHEC] ") + "%s P%d : %s" % [_cas[_i][0], _py.numero if _py != null else 0, msg])
	_ok = _ok and ok
	_i += 1
	_p = 0
	_t = 0.0
	if _i >= _cas.size():
		print("BENCH_ECHELLE_TREILLIS " + ("OK" if _ok else "ECHEC"))
		FinBanc.quitter(self, _main, 0 if _ok else 1)


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30 or _i >= _cas.size():
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	if _f < _t0 + 60 or not _main.mode_skieur:
		return
	var sk: SkieurJoueur = _main.skieur
	if _p == 0:
		_lg = null
		for e in _main.remontees.lignes:
			if (e[0] as Node).name == _cas[_i][0]:
				_lg = e[0]
		_main.aller_a_remontee(_lg)
		_p = 1
		_t = 0.0
		return
	if _p == 1:
		_t += 1.0 / 60.0
		if not _lg.pret:
			if _t > 200.0:
				_fin_cas(false, "ligne pas construite")
			return
		var k: int = int(_cas[_i][1])
		_py = _lg._pyl_treillis[k if k >= 0 else _lg._pyl_treillis.size() + k]
		if not _py.a_echelle:
			_fin_cas(false, "pas d'échelle")
			return
		var b: Vector3 = _py.echelle_a_hauteur(-10000.0)
		b = _py.global_transform * _py.echelle_bas
		var n: Vector3 = (_py.global_transform.basis.z * Vector3(1, 0, 1)).normalized()
		var q: Vector3 = b + n * 1.0
		sk.global_position = Vector3(q.x, relief.hauteur_sol(q.x, q.z) + 0.1, q.z)
		sk.velocity = Vector3.ZERO
		if sk.chausse:
			sk.basculer_ski()
		_p = 2
		_t = 0.0
		return
	if _p == 2:
		_t += 1.0 / 60.0
		if _t < 4.0:
			return
		var pied: Vector3 = _py.global_transform * _py.echelle_bas
		var ecart_h: float = sk.global_position.y - relief.hauteur_sol(sk.global_position.x, sk.global_position.z)
		if not sk.is_on_floor() or absf(ecart_h) > 0.5 or Vector2(sk.global_position.x - pied.x, sk.global_position.z - pied.z).length() > 2.0:
			# (replacé ailleurs entre-temps — aller_a_remontee —, ou pas encore posé : on recommence)
			_p = 1
			_t = 0.0
			return
		print("   avant : au sol %s, %.2f m sur le relief" % [sk.is_on_floor(), ecart_h])
		if _main.remontees.echelle_proche(sk.global_position) != _py:
			_fin_cas(false, "échelle pas proposée (bouton GRIMPER) à %.1f m" % Vector2(sk.global_position.x - (_py.global_transform * _py.echelle_bas).x, sk.global_position.z - (_py.global_transform * _py.echelle_bas).z).length())
			return
		_y_depart = sk.global_position.y
		_main.basculer_echelle()
		if not sk.sur_echelle():
			_fin_cas(false, "prise refusée")
			return
		_p = 3
		_t = 0.0
		return
	if _p == 3:
		_t += 1.0 / 60.0
		if sk.echelle_en_haut():
			var haut: Vector3 = _py.global_transform * _py.echelle_haut
			if absf(sk.global_position.y - haut.y) > 0.5:
				_fin_cas(false, "en haut à %.1f m de la tête de l'échelle" % (sk.global_position.y - haut.y))
				return
			_main.basculer_echelle()
			_p = 4
			_t = 0.0
		elif _t > 90.0:
			_fin_cas(false, "pas monté en 90 s")
		return
	if _p == 4:
		_t += 1.0 / 60.0
		if not sk.sur_echelle():
			_p = 5
			_t = 0.0
		elif _t > 120.0:
			_fin_cas(false, "pas redescendu")
		return
	if _p == 5:
		_t += 1.0 / 60.0
		if _t > 4.0:
			# (revenu à la hauteur d'où il est parti : au pied de certains pylônes, le sol des collisions est
			# sous la hauteur du relief lissé)
			var h: float = sk.global_position.y - _y_depart
			_fin_cas(absf(h) < 0.4 and sk._chute_t <= 0.0 and sk.is_on_floor(), "monté (%.1f m), redescendu, à %.2f m de son départ, au sol %s (relief %.2f)" % [(_py.global_transform * _py.echelle_haut).y - (_py.global_transform * _py.echelle_bas).y, h, sk.is_on_floor(), sk.global_position.y - relief.hauteur_sol(sk.global_position.x, sk.global_position.z)])
