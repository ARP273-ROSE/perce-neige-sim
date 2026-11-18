## Les va-et-vient attendent le skieur qui arrive (question d'utilisateur du 15/11/2026 : « les TPH ou le Funival
## peuvent m'attendre ? ») : téléphérique du Fornet et Funival, mode auto. Skieur qui marche près du quai aval :
## portes ouvertes au-delà de l'attente normale (45 s) ; il s'arrête : départ peu après.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_attente_vaetvient_3d.gd
extends SceneTree

const LIGNES: Array = ["tph_fornet", "FUNIVAL"]
var _main: Node
var _f: int = 0
var _etat: int = 0
var _k: int = 0
var _lg: Telepherique = null
var _yaw0: float = 0.0
var _t: float = 0.0
var _t0: int = 0
var _ok: bool = true
var _marche: bool = false


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	_etat = 99
	Engine.time_scale = 1.0
	print("BENCH_ATTENTE_VAETVIENT " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _ok else 1)


## Quai aval : sur l'axe, au point d'arrêt du véhicule, au sol (Funival : au niveau de la voie).
func _quai() -> Vector3:
	var x: float = _lg._x_quai(true)
	var y: float = _lg.y_voie(maxf(x, 0.0)) + 0.4 if _lg is Funival else _lg.terrain(0.0) + 0.3
	return _lg.global_transform * Vector3(0, y, -x)


func _nom() -> String:
	return String(_lg.name) if _lg != null else "?"


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30 or _etat == 99:
		return
	var dt: float = get_root().get_process_delta_time()
	_t += dt
	var sk: SkieurJoueur = _main.skieur
	if sk != null:
		# marche en rond (cap qui tourne de 1,6 rad/s, ~2 m de rayon) : reste près du quai. Avant (18/11/2026), la
		# commande tournait (avance et virage alternés, la vue suivant la marche) : le skieur dérivait, sortait de la gare
		# aval du Funival et s'arrêtait à 64 m du quai vers 58 s — l'essai ne passait qu'à 0,6 s près, selon l'instant
		# d'arrivée du véhicule.
		sk.entree = Vector2(0.0, 1.0) if _marche else Vector2.ZERO
		if _marche:
			sk.cam_yaw = _yaw0 + _t * 1.6
	match _etat:
		0:
			_main.basculer_skieur()
			_etat = 1
		1:
			if sk != null and sk.actif:
				_etat = 2
		2:
			if _k >= LIGNES.size():
				_fin()
				return
			_lg = null
			for e in _main.remontees.lignes:
				var l: Node = e[0]
				if (LIGNES[_k] == "FUNIVAL" and l is Funival) or String(l.name) == LIGNES[_k]:
					_lg = l
			if _lg == null:
				_verif("ligne présente : " + LIGNES[_k], false)
				_k += 1
				return
			_main.aller_a_remontee(_lg)
			_t0 = Time.get_ticks_msec()
			_marche = false
			_etat = 3
		3:
			if _lg.pret and _lg.roule:
				Engine.time_scale = 4.0
				_t = 0.0
				_etat = 4
			elif Time.get_ticks_msec() - _t0 > 180000:
				_verif(_nom() + " : construite en 180 s", false)
				_k += 1
				_etat = 2
		4:
			# arrivée à quai : le skieur se met à marcher autour du quai aval
			if _lg._phase == "route":
				_etat = 5
			elif _t > 400.0:
				_verif(_nom() + " : cycle", false)
				_k += 1
				_etat = 2
		5:
			if _lg._phase == "quai":
				var q: Vector3 = _quai()
				sk.global_position = q + _lg.global_transform.basis.x * 3.0
				sk.velocity = Vector3.ZERO
				_yaw0 = sk.cam_yaw
				_marche = true
				_t = 0.0
				_etat = 6
		6:
			if _t > Telepherique.T_QUAI + 20.0:
				var q2: Vector3 = _quai()
				_verif(_nom() + " : attend le skieur qui arrive (portes ouvertes au-delà de 45 s)",
					_lg._phase == "quai" and _lg.ouverture_portes() >= 0.99,
					"phase %s, portes %.2f, skieur à %.0f m du quai" % [_lg._phase, _lg.ouverture_portes(), sk.global_position.distance_to(q2)])
				_marche = false
				_t = 0.0
				_etat = 7
			elif _lg._phase != "quai":
				_verif(_nom() + " : attend le skieur qui arrive", false, "parti après %.0f s" % _t)
				_marche = false
				_k += 1
				_etat = 2
		7:
			if _lg._phase == "route":
				_verif(_nom() + " : le skieur arrêté, départ", _t < 15.0, "%.1f s" % _t)
				_k += 1
				_etat = 2
				Engine.time_scale = 1.0
			elif _t > 60.0:
				_verif(_nom() + " : départ après l'arrêt du skieur", false)
				_k += 1
				_etat = 2
				Engine.time_scale = 1.0
