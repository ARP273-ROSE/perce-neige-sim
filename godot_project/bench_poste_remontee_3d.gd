## Banc du poste de commande des remontées (retour d'utilisateur, 23/10/2026 : « un
## poste de conduite spécifique à chaque remontée, arrêts et redémarrages,
## petite, moyenne, grande vitesse, grande par défaut ») :
##  1. au pied du Marmottes Express : bouton POSTE, pupitre sur cette ligne ;
##  2. ARRÊT : décélération du frein de service, véhicules immobiles ;
##  3. DÉMARRER en PETITE vitesse : 40 % de la vitesse nominale ;
##  4. GRANDE vitesse puis ARRÊT D'URGENCE : arrêt en quelques secondes, les
##     sièges balancent ; RÉARMER seulement à l'arrêt ;
##  5. aux Boisses : le pupitre passe sur la télécabine.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_poste_remontee_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true
var _phase: int = 0
var _t: float = 0.0
var _lg: LigneRemontee = null
var _s0: float = 0.0
var _phi_max: float = 0.0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_POSTE_REMONTEE " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


func _ligne(cle: String) -> LigneRemontee:
	for e in _main.remontees.lignes:
		if (e[0] as Node).name == cle:
			return e[0]
	return null


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
	var cmd: CommandesSkieur = _main.commandes_skieur
	_t += 1.0 / 60.0
	match _phase:
		0:
			_lg = _ligne("tsd6_marmottes_express")
			_main.aller_a_remontee(_lg)
			_phase = 1
			_t = 0.0
		1:
			if not _lg.pret:
				_t = 0.0          # le délai part de la fin de la construction
				return
			if _t < 2.0:
				return
			_verif("pupitre : bouton POSTE et ligne du Marmottes Express", cmd._b_poste.visible and cmd.poste.ligne == _lg,
				"ligne %s" % [cmd.poste.ligne.nom_ligne if cmd.poste.ligne != null else "aucune"])
			_verif("pupitre : grande vitesse par défaut", _lg.cran == 2 and absf(_lg.vitesse_reelle - _lg.vitesse) < 0.01,
				"%.2f m/s" % _lg.vitesse_reelle)
			cmd._b_poste.button_pressed = true
			_lg.arreter()
			_phase = 2
			_t = 0.0
		2:
			if _lg.etat == "arret":
				var a: float = _lg.vitesse / _t
				_s0 = _lg._vehicules[0][1]
				_verif("ARRÊT : frein de service, ≈ 0,4 m/s²", absf(a - LigneRemontee.A_ARRET) < 0.05,
					"%.1f s, %.2f m/s²" % [_t, a])
				_phase = 3
				_t = 0.0
			elif _t > 60.0:
				_verif("ARRÊT : frein de service, ≈ 0,4 m/s²", false, "pas arrêtée en 60 s")
				_fin()
		3:
			if _t > 2.0:
				_verif("arrêtée : véhicules immobiles", absf(_lg._vehicules[0][1] - _s0) < 0.001)
				_lg.regler_cran(0)
				_lg.demarrer()
				_phase = 4
				_t = 0.0
		4:
			if _t > 20.0:
				var att: float = _lg.vitesse * LigneRemontee.CRANS[0]
				_verif("DÉMARRER en PETITE vitesse : 40 % du nominal", absf(_lg.vitesse_reelle - att) < 0.01,
					"%.2f m/s (consigne %.2f)" % [_lg.vitesse_reelle, att])
				_lg.regler_cran(2)
				_phase = 5
				_t = 0.0
		5:
			if _t > 25.0:
				_verif("GRANDE vitesse retrouvée", absf(_lg.vitesse_reelle - _lg.vitesse) < 0.01, "%.2f m/s" % _lg.vitesse_reelle)
				_lg.arret_urgence()
				_phi_max = 0.0
				_phase = 6
				_t = 0.0
		6:
			for e in _lg._vehicules:
				if _lg.zone(e[1])[0] == "ligne":
					_phi_max = maxf(_phi_max, absf((e[0] as VehiculeRemontee).phi))
			if _t > 0.5 and _t < 0.5 + 1.0 / 60.0:
				_verif("RÉARMER refusé tant que la ligne tourne", not _lg.rearmer() and _lg.etat == "urgence")
			if _t > 8.0:
				_verif("ARRÊT D'URGENCE : arrêt en moins de 5 s, les sièges balancent", _lg.vitesse_reelle <= 0.0 and _phi_max > 0.05,
					"balancement maxi %.2f rad" % _phi_max)
				_verif("RÉARMER à l'arrêt, puis redémarrage", _lg.rearmer() and _lg.etat == "arret")
				_lg.demarrer()
				_lg = _ligne("tcd10_boisses")
				_main.aller_a_remontee(_lg)
				_phase = 7
				_t = 0.0
		7:
			if not _lg.pret or _t < 3.0:
				if _t > 120.0:
					_verif("aux Boisses : le pupitre passe sur la télécabine", false, "ligne pas prête")
					_fin()
				return
			_verif("aux Boisses : le pupitre passe sur la télécabine", cmd.poste.ligne == _lg,
				"ligne %s" % [cmd.poste.ligne.nom_ligne if cmd.poste.ligne != null else "aucune"])
			_fin()
