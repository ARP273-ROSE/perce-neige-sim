## Banc des galets du 3S sur leurs câbles DESSINÉS (retour d'utilisateur du 21/11/2026, vidéo PWA de l'Olympique :
## « tu vois bien le câble qui bouge sous les galets » ; « le décollement des galets du pylône du câble tracteur, pas
## réaliste »). Pendant 30 s en marche, point de vue sous la ligne près du deuxième pylône :
##  1. galets du chariot de chaque cabine posée à moins de 250 m ↔ porteur dessiné (sommets tous les 4 m creusés par
##     le nuanceur, segments droits entre eux) : écart ≤ 2 cm ;
##  2. tracteur dessiné (levée − flèche) au-dessus de ses galets de sabot, sur tous les pylônes : ≤ 3 cm hors du passage
##     immédiat d'une pince (±1 m), ≤ LEVEE_SABOT_3S + 1 cm à son passage.
## NOYAU=1 : avec le module C++ (le 3S reste en GDScript ; même résultat attendu).
extends SceneTree
var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _lg: LigneRemontee = null
var _att: int = 0
var _n: int = 0
var _galets_max: float = 0.0
var _galets_n: int = 0
var _tr_hors: float = 0.0
var _tr_pince: float = 0.0
var _tr_n_pince: int = 0


func _initialize() -> void:
	LigneRemontee.noyau_desactive = OS.get_environment("NOYAU") != "1"
	OccupationRemontees.heure_forcee = 11.0
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


## Écart (m) entre le galet d'axe q (repère de la ligne) et le porteur dessiné, perpendiculairement au porteur : axe du
## galet à R_GALET_CHARIOT + rayon du porteur au-dessus de l'axe du porteur quand il roule dessus.
static func ecart_galet(lg: LigneRemontee, q: Vector3, montee: bool) -> float:
	var d: float = -q.z
	var yd: float = lg.y_porteur_dessine(d, montee)
	var pente: float = (lg.y_porteur_dessine(d - 0.05, montee) - lg.y_porteur_dessine(d + 0.05, montee)) / 0.1
	return (q.y - yd) * cos(atan(pente)) - (VehiculeRemontee.R_GALET_CHARIOT + 0.0285)


func _tick() -> void:
	_f += 1
	var pm: Node = _main.get("perf_manager")
	if pm != null and not bool(pm.get("banc")):
		pm.set("banc", true)
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	if not _main.mode_skieur or _main.remontees == null or not _main.remontees.pret:
		return
	if _lg == null:
		_lg = _main.remontees.ligne_par_id("olympique")
		if _lg == null:
			print("[ECHEC] olympique introuvable")
			print("BENCH_GALETS_3S ECHEC")
			FinBanc.quitter(self, _main, 1)
			return
		_main.aller_a_remontee(_lg)
		return
	if not _lg.pret:
		return
	_att += 1
	if _att == 60:
		var d0: float = float(_lg.pylones[1]["d"]) - 40.0
		var w: Vector3 = _lg.global_transform * Vector3(_lg._x_brin(true) + 12.0, 0, -d0)
		_main.skieur.activer(Vector3(w.x, relief.hauteur_sol(w.x, w.z) + 1.0, w.z), 0.0)
	if _att < 300:
		return
	if _lg.etat != "marche" or _lg.regime() < 0.99:
		if _att > 300 + 60 * 120:
			print("[ECHEC] olympique pas en marche (état %s, régime %.2f)" % [_lg.etat, _lg.regime()])
			print("BENCH_GALETS_3S ECHEC")
			FinBanc.quitter(self, _main, 1)
		return
	var xm: float = signf(_lg._x_brin(true))
	var vue: Vector3 = _lg.to_local(_main.skieur.global_position)
	# 1. galets du chariot ↔ porteur dessiné
	for i in range(_lg._vehicules.size()):
		var v: VehiculeRemontee = _lg._vehicules[i][0]
		var s: float = _lg._vehicules[i][1]
		if not v.visible or _lg.zone(s)[0] != "ligne":
			continue
		if Vector2(v.position.x - vue.x, v.position.z - vue.z).length() > 250.0:
			continue
		for g in v._galets_roul:
			var q: Vector3 = _lg.to_local((g as Node3D).global_position)
			var e: float = ecart_galet(_lg, q, signf(q.x) == xm)
			_galets_max = maxf(_galets_max, absf(e))
			_galets_n += 1
	# 2. tracteur sur ses galets de sabot
	for montee in [true, false]:
		var pinces: Array = []
		for e2 in _lg._vehicules:
			var v2: Node3D = e2[0]
			if (signf(v2.position.x) == xm) == montee:
				pinces.append(-v2.position.z)
		for p in _lg.pylones:
			var bs: Vector2 = LigneRemontee.bouts_sabot_3s(p)
			var d: float = bs.x + 0.6
			while d <= bs.y - 0.6:
				var ec: float = absf(_lg.levee_tracteur(d, montee) - _lg._fleche(d, montee))
				var pres: bool = false
				for dp in pinces:
					if absf(float(dp) - d) < 1.0:
						pres = true
				if pres:
					_tr_pince = maxf(_tr_pince, ec)
					_tr_n_pince += 1
				else:
					_tr_hors = maxf(_tr_hors, ec)
				d += 0.5
	_n += 1
	if _n < 1800:
		return
	var ok1: bool = _galets_n > 100 and _galets_max <= 0.02
	var ok2: bool = _tr_hors <= 0.03 and _tr_pince <= LigneRemontee.LEVEE_SABOT_3S + 0.01
	print("%s galets du chariot ↔ porteur dessiné : %.4f m au pire (%d relevés, seuil 0,02)" % ["[OK]  " if ok1 else "[ECHEC]", _galets_max, _galets_n])
	print("%s tracteur sur ses galets de sabot : %.4f m hors pince (seuil 0,03), %.4f m au passage d'une pince (%d relevés, seuil %.2f)" % ["[OK]  " if ok2 else "[ECHEC]", _tr_hors, _tr_pince, _tr_n_pince, LigneRemontee.LEVEE_SABOT_3S + 0.01])
	print("BENCH_GALETS_3S " + ("OK" if ok1 and ok2 else "ECHEC") + (" (C++)" if not LigneRemontee.noyau_desactive else " (GDScript)"))
	FinBanc.quitter(self, _main, 0 if ok1 and ok2 else 1)
