## Quai amont du téléphérique du Fornet, portes des deux côtés (16/11/2026) : cabine à quai, portes ouvertes ; le
## skieur va au seuil de la porte de droite puis (2e passe) de celle de gauche, ressort, longe le quai jusqu'au
## fond et sort sur la neige par le côté ; puis, cabine repartie, il longe le quai d'un bout à l'autre sans rester
## bloqué par les portillons fermés (bande entre les baies et bandes extérieures).
##   godot --headless --fixed-fps 60 --path godot_project -s bench_fornet_quai_3d.gd
extends SceneTree

var _main: Node
var _f: int = 0
var _etat: int = 0
var _lg: Telepherique = null
var _t: float = 0.0
var _t0: int = 0
var _ok: bool = true
var _cab: int = -1
var _passe: int = 0
var _pts: Array = []
var _k: int = 0
var _nom: String = ""


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
	print("BENCH_FORNET_QUAI " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _ok else 1)


func _monde(x: float, u: float, dy: float = 0.2) -> Vector3:
	var L: float = _lg.longueur_h()
	return _lg.global_transform * Vector3(x, _lg.terrain(L) + dy, -L - u)


## Parcours `pts` (repère du quai : x, u) ; vrai quand il est fini ; échec s'il n'avance plus.
func _marcher(sk: SkieurJoueur) -> int:
	if sk.chemin.is_empty():
		if _k >= _pts.size():
			return 1
		sk.chemin = [_monde(_pts[_k].x, _pts[_k].y)]
		_k += 1
		_t = 0.0
	return -1 if _t > 25.0 else 0


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30 or _etat == 99:
		return
	_t += get_root().get_process_delta_time()
	var sk: SkieurJoueur = _main.skieur
	match _etat:
		0:
			var scen: Node = _main.get_node_or_null("ScenarioPanel")
			if scen != null:
				scen.queue_free()
			_main.basculer_skieur()
			_etat = 1
		1:
			if sk != null and sk.actif:
				for e in _main.remontees.lignes:
					if String(e[0].name) == "tph_fornet":
						_lg = e[0]
				# on se pose en haut : la ligne se construit autour
				var haut: Vector3 = _lg.global_transform * Vector3(14.0, _lg.terrain(_lg.longueur_h()) + 0.5, -_lg.longueur_h() - 30.0)
				_main.collisions.assurer_autour(haut)
				sk.activer(haut, 0.0)
				_t0 = Time.get_ticks_msec()
				_etat = 2
		2:
			if _lg.pret and _lg.roule:
				Engine.time_scale = 6.0
				_etat = 3
			elif Time.get_ticks_msec() - _t0 > 240000:
				_verif("Fornet construit", false)
				_fin()
		3:
			# une cabine à quai en haut, portes grandes ouvertes : on fige (manuel)
			for i in range(_lg.nombre_vehicules()):
				if _lg._phase == "quai" and _lg.zone_vehicule(i) == "gare_amont" and _lg.ouverture_portes() >= 1.0:
					_cab = i
			if _cab >= 0:
				Engine.time_scale = 1.0
				_lg.exploitation().commande("mode", "manuel")
				_passe = 0
				_etat = 4
			elif _t > 900.0:
				_verif("cabine à quai en haut", false)
				_fin()
		4:
			var xc: float = (_lg.global_transform.affine_inverse() * _lg.vehicule(_cab).global_position).x
			var cote: float = 1.0 if _passe == 0 else -1.0
			var W: float = _lg.voie * 0.5 + 3.0
			var lq: float = 2.0 * Telepherique.D_QUAI + 2.0
			_nom = "porte de droite" if _passe == 0 else "porte de gauche"
			# (posé dans la cabine, il y serait embarqué d'office : il part du quai, passe le portillon ouvert jusqu'au
			# seuil de la porte, entre la paroi de la cabine et la barrière, puis ressort)
			sk.activer(_monde(xc + cote * 2.6, Telepherique.D_QUAI, 0.25), 0.0)
			sk.chemin = []
			_pts = [Vector2(xc + cote * 1.68, Telepherique.D_QUAI), Vector2(xc + cote * 2.6, Telepherique.D_QUAI),
				Vector2(xc + cote * 2.6, lq - 2.0),
				Vector2(cote * (W - 1.0), lq - 1.5), Vector2(cote * (W + 4.0), lq - 1.5)]
			_k = 0
			_t = 0.0
			_etat = 5
		5:
			var r: int = _marcher(sk)
			if r != 0:
				var loc: Vector3 = _lg.global_transform.affine_inverse() * sk.global_position
				_verif("quai ↔ seuil de la cabine, puis neige, par la " + _nom, r == 1 and absf(loc.x) > _lg.voie * 0.5 + 3.0,
					"étape %d/%d, x %.1f, u %.1f" % [_k, _pts.size(), loc.x, -loc.z - _lg.longueur_h()])
				sk.chemin = []
				_passe += 1
				_etat = 4 if _passe < 2 else 6
		6:
			# cabine repartie : portillons fermés
			_lg.exploitation().commande("mode", "auto")
			Engine.time_scale = 6.0
			_t = 0.0
			_etat = 7
		7:
			if _lg._phase == "route" and _lg.zone_vehicule(_cab) == "ligne":
				Engine.time_scale = 1.0
				_passe = 0
				_etat = 8
			elif _t > 400.0:
				_verif("cabine repartie", false)
				_fin()
		8:
			# le quai sans cabine : bande entre les baies, puis bandes extérieures, du fond au nez et retour
			var W8: float = _lg.voie * 0.5 + 3.0
			var lq8: float = 2.0 * Telepherique.D_QUAI + 2.0
			var x8: float = [0.0, W8 - 0.9, -(W8 - 0.9)][_passe]
			_nom = ["bande entre les baies", "bande extérieure droite", "bande extérieure gauche"][_passe]
			sk.activer(_monde(x8, lq8 - 2.0, 0.25), 0.0)
			sk.chemin = []
			_pts = [Vector2(x8, 1.2), Vector2(x8, lq8 - 2.0)]
			_k = 0
			_t = 0.0
			_etat = 9
		9:
			var r9: int = _marcher(sk)
			if r9 != 0:
				var loc9: Vector3 = _lg.global_transform.affine_inverse() * sk.global_position
				_verif("sans cabine : " + _nom + " du fond au nez et retour", r9 == 1,
					"étape %d/%d, x %.1f, u %.1f" % [_k, _pts.size(), loc9.x, -loc9.z - _lg.longueur_h()])
				sk.chemin = []
				_passe += 1
				if _passe < 3:
					_etat = 8
				else:
					_fin()
