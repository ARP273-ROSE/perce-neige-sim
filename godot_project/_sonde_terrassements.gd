extends SceneTree
# Hauteur des terrassements de gare au-dessus (remblai) et au-dessous (déblai) du terrain : une ligne par gare.
var _main: Node
var _f: int = 0
var _etat: int = 0
var _lignes: Array = []
var _k: int = 0
var _t0: int = 0
var _att: int = 0

func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)

func _mesure(lg: LigneRemontee, aval: bool) -> void:
	var tri: PackedVector3Array = (lg.get("_terrassements") as Dictionary).get(aval, PackedVector3Array())
	if tri.is_empty():
		return
	var L: float = lg.longueur_h()
	var y0: float = lg.terrain(0.0 if aval else L)
	var rem: float = 0.0
	var deb: float = 0.0
	var etendue: float = 0.0
	for v in tri:
		var s: float = lg._sol(v.x, v.z)
		if absf(v.y - y0) < 0.02:
			rem = maxf(rem, v.y - s)
			deb = maxf(deb, s - v.y)
		etendue = maxf(etendue, maxf(absf(v.x), absf(v.z - (0.0 if aval else -L))))
	print("TERR %-26s %-5s remblai %5.1f déblai %5.1f étendue %5.1f y0 %7.1f" % [lg.name, "aval" if aval else "amont", rem, deb, etendue, y0 + lg.global_position.y])

func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30 or _etat == 99:
		return
	match _etat:
		0:
			var scen: Node = _main.get_node_or_null("ScenarioPanel")
			if scen != null:
				scen.queue_free()
			_main.basculer_skieur()
			_etat = 1
		1:
			if _main.get("skieur") != null and _main.skieur.actif:
				for e in _main.remontees.lignes:
					_lignes.append(e[0])
				_etat = 2
		2:
			if _k >= _lignes.size():
				_etat = 99
				print("TERR FIN")
				quit()
				return
			_main.aller_a_remontee(_lignes[_k])
			_t0 = Time.get_ticks_msec()
			_etat = 3
		3:
			var lg: LigneRemontee = _lignes[_k]
			if lg.role == "haut" and lg.jumelee != null and not lg.pret:
				_main.skieur.global_position = lg.global_transform.origin + Vector3(0, lg.terrain(0.0) + 1.0, 0)
			if lg.pret:
				_mesure(lg, true)
				_mesure(lg, false)
				_k += 1
				_etat = 2
			elif Time.get_ticks_msec() - _t0 > 200000:
				_k += 1
				_etat = 2
