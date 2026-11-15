## Évacuation verticale d'une ligne déraillée (question d'utilisateur du 15/11/2026 : « si TS, TC, TPH ou 3S déraille,
## il faut descendre à la corde ») : skieur assis sur le Marmottes Express, déraillement du câble en ligne ;
##  1. arrêt d'urgence, ligne grave, skieur toujours assis pendant l'arrivée des secouristes ;
##  2. à son tour, descente à la corde (corde visible, vitesse d'un descendeur) ;
##  3. au sol sous son siège, plus à bord ; ligne hors service une fois tout le monde au sol.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_evacuation_corde_3d.gd
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true
var _phase: int = 0
var _t: float = 0.0
var _lg: LigneRemontee = null
var _y_debut: float = 0.0
var _corde_vue: bool = false
var _v_max: float = 0.0
var _y_prec: float = 0.0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	_phase = 99
	Engine.time_scale = 1.0
	print("BENCH_EVACUATION_CORDE " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _ok else 1)


func _tick() -> void:
	_f += 1
	if _phase == 99:
		return
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
	_t += get_root().get_process_delta_time()
	match _phase:
		0:
			for e in rm.lignes:
				if String(e[0].name) == "tsd6_marmottes_express":
					_lg = e[0]
			_main.aller_a_remontee(_lg)
			_main.collisions.assurer_autour(_lg.global_transform.origin)
			_phase = 1
		1:
			if not _lg.pret:
				return
			var q: Vector3 = _lg.global_transform * _lg.point_embarquement(true)
			sk.activer(q + Vector3(0, 0.1, 0), 0.0)
			sk.basculer_ski(true)
			sk.dernier_sol = q
			_phase = 2
			_t = 0.0
		2:
			if not rm.a_bord.is_empty():
				_phase = 3
				_t = 0.0
			elif _t > 30.0:
				_verif("assis sur le télésiège", false, "rien en 30 s")
				_fin()
		3:
			# en ligne, assez haut au-dessus du sol
			var h: float = sk.global_position.y - relief.hauteur_sol(sk.global_position.x, sk.global_position.z)
			if _lg.zone_vehicule(rm.a_bord[1]) == "ligne" and h > 6.0 and _t > 20.0:
				var ok: bool = _lg.exploitation().declencher("sortie_cable")
				_verif("déraillement déclenché en ligne", ok, "%.1f m au-dessus du sol" % h)
				Engine.time_scale = 4.0
				_phase = 4
				_t = 0.0
			elif _t > 200.0:
				_verif("en ligne au-dessus du sol", false)
				_fin()
		4:
			if _t > 20.0:
				_verif("arrêt d'urgence, ligne grave", _lg.etat == "urgence" and _lg.vitesse_reelle <= 0.0
					and _lg.exploitation().evacuation() == "corde")
				_verif("skieur toujours assis à l'arrivée des secouristes", not rm.a_bord.is_empty() and sk.assis)
				var p0: Array = _lg.exploitation().pannes
				_verif("aucune remise en marche possible", _lg.exploitation().commande("demarrer") != "")
				_phase = 5
				_t = 0.0
		5:
			var mi: MeshInstance3D = rm.get("_corde_mi")
			if mi != null and mi.visible:
				if not _corde_vue:
					_y_debut = sk.global_position.y
					_y_prec = 0.0                    # (ici : durée de la descente, temps du jeu)
				_corde_vue = true
				_y_prec += get_root().get_process_delta_time()
			if rm.a_bord.is_empty():
				var sol: float = relief.hauteur_sol(sk.global_position.x, sk.global_position.z)
				_verif("corde visible pendant la descente", _corde_vue)
				_v_max = (_y_debut - sol) / maxf(_y_prec, 0.01)
				_verif("descente contrôlée (≤ 1 m/s en moyenne)", _v_max <= 1.05 and _v_max > 0.5, "%.2f m/s, %.0f s" % [_v_max, _y_prec])
				_verif("au sol sous le siège", absf(sk.global_position.y - sol) < 0.2 and not sk.embarque,
					"%.2f m du sol, descendu de %.1f m" % [sk.global_position.y - sol, _y_debut - sol])
				_verif("corde rangée", mi == null or not mi.visible)
				_phase = 6
				_t = 0.0
			elif _t > 400.0:
				_verif("descendu à la corde", false, "toujours à bord après 400 s")
				_fin()
		6:
			var ph: String = ""
			for p in _lg.exploitation().pannes:
				ph = p["phase"]
			if ph == "hors_service":
				_verif("ligne hors service une fois tout le monde au sol", true)
				_fin()
			elif _t > 200.0:
				_verif("ligne hors service une fois tout le monde au sol", false, ph)
				_fin()
