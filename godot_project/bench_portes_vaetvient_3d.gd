# Portes à la main des va-et-vient (question d'utilisateur du 15/11/2026 : « le TPH, je peux ouvrir et fermer les
# portes ? ») : téléphérique du Fornet et Funival. En manuel, à quai : PORTES ferme et ouvre (cabines et collisions),
# DÉMARRER refusé portes ouvertes, départ portes fermées ; à l'arrivée suivante les portes restent fermées et le
# véhicule attend ; retour en auto : le cycle de quai reprend seul.
#   godot --headless --fixed-fps 60 --path godot_project -s bench_portes_vaetvient_3d.gd
extends SceneTree

const LIGNES: Array = ["tph_fornet", "FUNIVAL"]
var _main: Node
var _f: int = 0
var _etat: int = 0
var _k: int = 0
var _lg: Telepherique = null
var _ex: ExploitationRemontee = null
var _t: float = 0.0
var _t0: int = 0
var _ok: bool = true


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
	print("BENCH_PORTES_VAETVIENT " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _ok else 1)


func _nom() -> String:
	return String(_lg.name) if _lg != null else "?"


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30 or _etat == 99:
		return
	var dt: float = get_root().get_process_delta_time()
	_t += dt
	match _etat:
		0:
			_main.basculer_skieur()
			_etat = 1
		1:
			if _main.skieur != null and _main.skieur.actif:
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
			_etat = 3
		3:
			if _lg.pret and _lg.roule:
				_ex = _lg.exploitation()
				Engine.time_scale = 6.0
				_t = 0.0
				_etat = 4
			elif Time.get_ticks_msec() - _t0 > 180000:
				_verif(_nom() + " : construite en 180 s", false)
				_k += 1
				_etat = 2
		4:
			# attendre un quai, portes grandes ouvertes (cycle auto)
			if _lg._phase == "quai" and _lg.ouverture_portes() >= 1.0:
				_verif(_nom() + " : auto, portes ouvertes à quai", true)
				_ex.commande("mode", "manuel")
				_verif(_nom() + " : passage en manuel, portes toujours ouvertes", _lg.portes_manu and _lg.ouverture_portes() >= 0.99,
					"%.2f" % _lg.ouverture_portes())
				var r: String = _ex.commande("demarrer")
				_verif(_nom() + " : DÉMARRER refusé portes ouvertes", r != "", r)
				_ex.commande("portes", "fermer")
				_t = 0.0
				_etat = 5
			elif _t > 400.0:
				_verif(_nom() + " : quai atteint", false, "phase %s" % _lg._phase)
				_k += 1
				_etat = 2
		5:
			if _t > 3.0:
				_verif(_nom() + " : PORTES fermées", _lg.ouverture_portes() <= 0.0, "%.2f" % _lg.ouverture_portes())
				_verif(_nom() + " : toujours à quai", _lg._phase == "quai")
				_ex.commande("portes", "ouvrir")
				_t = 0.0
				_etat = 6
		6:
			if _t > 3.0:
				_verif(_nom() + " : PORTES rouvertes", _lg.ouverture_portes() >= 1.0, "%.2f" % _lg.ouverture_portes())
				_verif(_nom() + " : collisions des parois coupées portes ouvertes", _lg.arrivee_cabine(0).size() > 0 or _lg.arrivee_cabine(1).size() > 0)
				_ex.commande("portes", "fermer")
				_t = 0.0
				_etat = 7
		7:
			if _t > 3.0:
				var r2: String = _ex.commande("demarrer")
				_verif(_nom() + " : DÉMARRER portes fermées", r2 == "", r2)
				_t = 0.0
				_etat = 8
		8:
			if _lg._phase == "route" and _lg.vitesse_reelle > 0.5:
				_verif(_nom() + " : départ", true)
				_t = 0.0
				_etat = 9
			elif _t > 10.0:
				_verif(_nom() + " : départ", false, "phase %s v %.2f etat %s" % [_lg._phase, _lg.vitesse_reelle, _lg.etat])
				_k += 1
				_etat = 2
		9:
			# arrivée en manuel : portes fermées, le véhicule attend
			if _lg._phase == "quai":
				_t = 0.0
				_etat = 10
			elif _t > 400.0:
				_verif(_nom() + " : arrivée", false)
				_k += 1
				_etat = 2
		10:
			if _t > 20.0:
				_verif(_nom() + " : manuel, portes restées fermées à l'arrivée", _lg.ouverture_portes() <= 0.0)
				_verif(_nom() + " : manuel, pas de départ seul", _lg._phase == "quai")
				_ex.commande("mode", "auto")
				_t = 0.0
				_etat = 11
		11:
			if _lg._phase == "route":
				_verif(_nom() + " : auto, départ seul après le cycle de quai", true, "%.0f s" % _t)
				_k += 1
				_etat = 2
				Engine.time_scale = 1.0
			elif _t > 200.0:
				_verif(_nom() + " : auto, départ seul", false, "phase %s portes %.2f" % [_lg._phase, _lg.ouverture_portes()])
				_k += 1
				_etat = 2
				Engine.time_scale = 1.0
