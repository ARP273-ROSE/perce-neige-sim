## Banc du funiculaire en réseau (retours d'utilisateur, 23/11/2026) : rames échangées dans le repère de la RAME 1
## (« rame 1 ou 2 à l'écran initial : on monte ensemble mais l'un dans la 1, l'autre dans la 2 ») et skieur laissé dans
## une rame hors mode skieur, toujours publié à sa place (« il devient immobile dans le tunnel, le funi part sans lui »).
##   godot --headless --fixed-fps 60 --path godot_project -s bench_reseau_rame_rangee_3d.gd
extends SceneTree
var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true

func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)

func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond

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
	var rc: ReseauClient = _main.reseau_client()
	for r2 in [false, true]:
		_main.apply_rame(r2)
		for rame in [_main.cabin, _main.cabin_ghost]:
			var voit: Node3D = (rame as Cabin)._interior_cars[0]
			_main._skieur_voiture = voit
			_main._skieur_local = Vector3(0.3, 1.0, 2.0)
			_main.skieur.actif = false
			var e: Dictionary = rc.etat_local()
			var attendu: int = (0 if rame == _main.cabin else 1) ^ (1 if r2 else 0)
			var ok: bool = not e.is_empty() and String(e.get("l", "")) == "perce_neige" and int(e.get("i", -1)) == attendu
			# même place une fois ramené dans la rame locale du même numéro commun
			if ok:
				var o: Vector3 = Vector3(e["o"][0], e["o"][1], e["o"][2])
				var p: Vector3 = rc._rame_locale(int(e["i"])).global_transform * o
				ok = p.distance_to(voit.global_transform * _main._skieur_local) < 0.01
			_verif("rame %s menée, skieur rangé dans %s" % ["2" if r2 else "1", "la nôtre" if rame == _main.cabin else "l'autre"], ok, str(e.get("i", "—")))
	# abscisse commune : la rame 1 est toujours en s chez qui mène la 1, en MIROIR − s chez qui mène la 2
	_main.apply_rame(true)
	var c: Array = rc._pn_commun(1000.0, 3.0, 1)
	_verif("abscisse commune (rame 2 → rame 1)", absf(float(c[0]) - (PNConstants.MIROIR_S - 1000.0)) < 1e-3 and float(c[1]) == -3.0 and int(c[2]) == -1)
	print("BENCH_RESEAU_RAME_RANGEE " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _ok else 1)
	process_frame.disconnect(_tick)
