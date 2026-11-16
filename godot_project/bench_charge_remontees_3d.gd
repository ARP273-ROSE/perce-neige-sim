## Banc des charges des remontées (16/11/2026, retour d'utilisateur : « on met des gens que dans le funi
## Perce-Neige et nulle part ailleurs […] respecte physique complète du poids et logique d'utilisation »).
##   godot --headless --fixed-fps 60 --path godot_project -s bench_charge_remontees_3d.gd
## Pour un télésiège, une télécabine, le 3S, un téléphérique et le Funival, à 10 h 15, 13 h 00 et 19 h 00 :
##  - occupation : montée chargée le matin, moins à midi, nulle hors des heures d'ouverture ; descente presque vide ;
##  - passagers tirés par véhicule entre 0 et le nombre de places, en moyenne près de l'occupation ;
##  - puissance : plus forte quand la montée est chargée ;
##  - freinage d'urgence (monocâbles) : plus court quand la montée est chargée ;
##  - une ligne en évacuation à la corde (cap_exploitation() = 0) ne repart pas, chargée ou non.
extends SceneTree

var _main: Node = null
var _f: int = 0
var _ok: bool = true
var _lignes: Array = []
var _il: int = 0
var _t: float = 0.0
var _e: int = 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	OccupationRemontees.heure_forcee = -1.0
	print("BENCH_CHARGE_REMONTEES " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, get("_main"), 0 if _ok else 1)


func _choisir() -> void:
	var voulus: Dictionary = {}
	for e in _main.remontees.lignes:
		var lg: LigneRemontee = e[0]
		var k: String = ""
		if lg is Funival:
			k = "funival"
		elif lg.vaetvient():
			k = "tph"
		elif lg.tricable():
			k = "3s"
		elif lg.teleski():
			k = ""
		elif lg.famille.begins_with("cabine"):
			k = "tcd"
		elif lg.famille.begins_with("siege") and not lg.fixe():
			k = "tsd"
		if k != "" and not voulus.has(k):
			voulus[k] = lg
	for k in ["tsd", "tcd", "3s", "tph", "funival"]:
		if voulus.has(k):
			_lignes.append([k, voulus[k]])


func _puissance(lg: LigneRemontee, h: float) -> float:
	OccupationRemontees.heure_forcee = h
	lg._occ_t = 1.0e9
	lg._maj_occupation(0.0)
	if lg is Telepherique:
		var tp: Telepherique = lg
		tp._tour_cab = maxi(tp._tour_cab, 0) + 1
		tp._tirer_cabines()
		var v0: float = tp._v
		tp._v = tp.vitesse * (1.0 if tp._sens > 0.0 else -1.0)
		var p: float = tp.puissance_kw()
		tp._v = v0
		return p
	lg._charges_ponctuelles()         # (3S : charges ponctuelles, recalculées à chaque image en jeu)
	var vr: float = lg.vitesse_reelle
	lg.vitesse_reelle = lg.vitesse
	var p2: float = lg.puissance_kw()
	lg.vitesse_reelle = vr
	return p2


func _tick() -> void:
	_f += 1
	var relief: ReliefBuilder = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _main.get("perf_manager") != null:
		_main.perf_manager.banc = true
	_t += 1.0 / 60.0
	if _e == 0:
		if not _main.mode_skieur:
			_main.basculer_skieur()
		if _main.get("remontees") == null or not _main.remontees.pret:
			return
		_choisir()
		_verif("lignes de chaque genre trouvées", _lignes.size() == 5, str(_lignes.map(func(x): return x[0] + " " + String(x[1].name))))
		_e = 1
		_t = 0.0
		return
	if _il >= _lignes.size():
		_fin()
		return
	var k: String = _lignes[_il][0]
	var lg: LigneRemontee = _lignes[_il][1]
	match _e:
		1:
			_e = 2
			_t = 0.0
		2:
			if _t < 2.0:
				return
			_main.aller_a_remontee(lg)
			_e = 3
			_t = 0.0
		3:
			if not lg.pret and _t < 120.0:
				return
			if not lg.pret:
				_verif("%s %s prête" % [k, lg.name], false)
				_il += 1
				_e = 2
				return
			_mesurer(k, lg)
			# évacuation à la corde, à 10 h 15 (montée chargée) : la ligne s'arrête et ne repart pas
			OccupationRemontees.heure_forcee = 10.25
			lg._occ_t = 1.0e9
			lg.corde_en_cours = true
			_e = 4
			_t = 0.0
		4:
			if _t < 40.0:
				return
			var v: float = lg.vitesse_reelle
			lg.corde_en_cours = false
			_verif("%s : évacuation à la corde, chargée — arrêtée et pas repartie" % k, absf(v) < 0.01,
				"vitesse %.2f m/s après 40 s" % v)
			_il += 1
			_e = 2
			_t = 0.0


func _mesurer(k: String, lg: LigneRemontee) -> void:
	var places: int = (lg as Telepherique).places_cabine() if lg is Telepherique else lg.places_vehicule()
	var tm: Array = []
	for h in [10.25, 13.0, 19.0]:
		tm.append([OccupationRemontees.taux(lg, true, h), OccupationRemontees.taux(lg, false, h)])
	_verif("%s : montée chargée le matin, moins à 13 h, vide le soir ; descente plus légère" % k,
		tm[0][0] > tm[1][0] and tm[1][0] > 0.0 and tm[2][0] == 0.0 and tm[2][1] == 0.0 and tm[0][1] < tm[0][0],
		"montée %.0f / %.0f / %.0f %%, descente %.0f / %.0f / %.0f %%" % [tm[0][0] * 100, tm[1][0] * 100, tm[2][0] * 100,
			tm[0][1] * 100, tm[1][1] * 100, tm[2][1] * 100])
	# passagers tirés véhicule par véhicule
	var n: int = 0
	var somme: int = 0
	var hors: int = 0
	for t in range(200):
		var p: int = OccupationRemontees.occupants(lg, places, t % 40, t / 40, true, 10.25)
		somme += p
		n += 1
		if p < 0 or p > places:
			hors += 1
	var moy: float = float(somme) / float(n) / float(places)
	_verif("%s : passagers par véhicule entre 0 et %d places, moyenne près de l'occupation" % [k, places],
		hors == 0 and absf(moy - float(tm[0][0])) < 0.08, "moyenne %.0f %% pour %.0f %%" % [moy * 100, tm[0][0] * 100])
	# puissance
	var p_matin: float = _puissance(lg, 10.25)
	var p_soir: float = _puissance(lg, 19.0)
	_verif("%s : puissance plus forte la montée chargée" % k, p_matin > p_soir + 1.0,
		"%.0f kW à 10 h 15, %.0f kW à vide" % [p_matin, p_soir])
	# flèche (monocâbles) : brin montée plus creusé chargé, garde au sol tenue
	if lg._flechit_a_la_charge() and lg._n_appuis >= 2:
		var jm: int = 0
		for j in range(lg._n_appuis - 1):
			if lg._appuis[j + 1] - lg._appuis[j] > lg._appuis[jm + 1] - lg._appuis[jm]:
				jm = j
		var dm: float = (lg._appuis[jm] + lg._appuis[jm + 1]) * 0.5
		var fl: Array = []
		var garde_min: float = INF
		for h2 in [10.25, 19.0]:
			OccupationRemontees.heure_forcee = h2
			lg._occ_t = 1.0e9
			lg._maj_occupation(0.0)
			fl.append(lg._fleche(dm, true))
			if h2 == 10.25:
				for j2 in range(lg._n_appuis - 1):
					for t2 in [0.25, 0.5, 0.75]:
						var d2: float = lerpf(lg._appuis[j2], lg._appuis[j2 + 1], t2)
						garde_min = minf(garde_min, lg.y_cable(d2, true) + lg._fleche(d2, true) - lg.terrain(d2) - lg._garde_exigee(d2))
		_verif("%s : flèche du brin montée plus creuse chargé, garde au sol tenue" % k, fl[0] < fl[1] and garde_min > -0.05,
			"milieu de la plus grande portée (%.0f m) : %.2f m chargé, %.2f m à vide ; marge mini sur la garde %.2f m" % [
				lg._appuis[jm + 1] - lg._appuis[jm], fl[0], fl[1], garde_min])
	# freinage d'urgence (monocâbles)
	if not (lg is Telepherique):
		OccupationRemontees.heure_forcee = 10.25
		lg._occ_t = 1.0e9
		lg._maj_occupation(0.0)
		var a1: float = lg.a_urgence()
		OccupationRemontees.heure_forcee = 19.0
		lg._occ_t = 1.0e9
		lg._maj_occupation(0.0)
		var a0: float = lg.a_urgence()
		_verif("%s : arrêt d'urgence plus court la montée chargée" % k, a1 > a0,
			"%.2f m/s² chargée, %.2f m/s² à vide (référence %.2f)" % [a1, a0, LigneRemontee.A_URGENCE])
