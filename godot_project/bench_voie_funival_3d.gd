## Voie du Funival (retour d'utilisateur du 16/11/2026 : « si je marche sur la voie du Funival, je finis au centre de la
## terre ») : skieur à pied posé sur la voie à plusieurs endroits (pont, portail, tunnel, évitement, près de la salle
## amont) ; il tient sur le radier, et marche le long de la voie sans passer au travers.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_voie_funival_3d.gd
extends SceneTree

var _main: Node
var _f: int = 0
var _etat: int = 0
var _lg: Funival = null
var _t: float = 0.0
var _t0: int = 0
var _ok: bool = true
var _k: int = 0
var _pts: Array = []


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	_etat = 99
	print("BENCH_VOIE_FUNIVAL " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _ok else 1)


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
					if e[0] is Funival:
						_lg = e[0]
				_main.aller_a_remontee(_lg)
				_t0 = Time.get_ticks_msec()
				_etat = 2
		2:
			if _lg.pret:
				_lg.exploitation().commande("arreter")      # (véhicules à l'arrêt : la voie est libre)
				var L: float = _lg.longueur_h()
				_pts = [["pont", _lg.portail_d * 0.5], ["portail", _lg.portail_d + 6.0], ["tunnel", _lg.portail_d + 300.0],
					["évitement", L * 0.5 + 40.0], ["haut du tunnel", L - Funival.L_HALL - 40.0]]
				_etat = 3
			elif Time.get_ticks_msec() - _t0 > 240000:
				_verif("Funival construit", false)
				_fin()
		3:
			if _k >= _pts.size():
				_fin()
				return
			var d: float = _pts[_k][1]
			var p: Vector3 = _lg.global_transform * Vector3(_lg.x_voie(d, 0) + 0.3, _lg.y_voie(d) + 0.4, -d)
			_main.collisions.assurer_autour(p)
			sk.activer(p, 0.0)
			# il remonte la voie sur 15 m
			var d2: float = d + 15.0
			sk.chemin = [_lg.global_transform * Vector3(_lg.x_voie(d2, 0) + 0.3, _lg.y_voie(d2), -d2)]
			_t = 0.0
			_etat = 4
		4:
			var loc: Vector3 = _lg.global_transform.affine_inverse() * sk.global_position
			var dy: float = loc.y - _lg.y_voie(-loc.z)
			if dy < -3.0 or _t > 25.0 or (sk.chemin.is_empty() and _t > 2.0):
				_verif("%s : tient sur la voie et la remonte" % _pts[_k][0], dy > -1.0 and dy < 1.5 and -loc.z > float(_pts[_k][1]) + 8.0,
					"%.2f m au-dessus du rail, avancé de %.1f m en %.0f s" % [dy, -loc.z - float(_pts[_k][1]), _t])
				sk.chemin = []
				_k += 1
				_etat = 3
