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
		elif lg.famille == "perche_debrayable":
			k = "tkd"
		elif lg.teleski():
			k = ""
		elif lg.famille.begins_with("cabine"):
			k = "tcd"
		elif lg.famille.begins_with("siege") and not lg.fixe():
			k = "tsd"
		if k != "" and not voulus.has(k):
			voulus[k] = lg
	for k in ["tsd", "tcd", "3s", "tph", "funival", "tkd"]:
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
		_verif("lignes de chaque genre trouvées", _lignes.size() == 6, str(_lignes.map(func(x): return x[0] + " " + String(x[1].name))))
		_e = 1
		_t = 0.0
		return
	if _il >= _lignes.size():
		_skieurs_pistes()
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
			if k == "tkd":
				_e = 5
				_t = 0.0
				OccupationRemontees.heure_forcee = 10.25
				lg._occ_t = 1.0e9
				return
			_mesurer(k, lg)
			# évacuation à la corde, à 10 h 15 (montée chargée) : la ligne s'arrête et ne repart pas
			OccupationRemontees.heure_forcee = 10.25
			lg._occ_t = 1.0e9
			lg.corde_en_cours = true
			_e = 4
			_t = 0.0
		5:
			# TKD : skieurs tirés sous le brin de montée, skis sur la neige (le retour passe DY_RETOUR_TKD plus haut)
			if _t < 20.0:
				return
			# (sans écran, le serveur de rendu ne garde pas les transformées des MultiMesh : la ligne les garde)
			var n: int = lg.tires_positions.size()
			var relief2: ReliefBuilder = _main.get("relief")
			var sol_max: float = 0.0
			var hors_brin: int = 0
			var l_max: float = 0.0
			var xb: float = lg._x_brin(true)
			for j in range(n):
				var p: Vector3 = lg.tires_positions[j]
				sol_max = maxf(sol_max, absf(p.y - 0.02 - relief2.hauteur_sol(p.x, p.z)))
				# dans l'axe de sa pince, et cette pince sur le brin montée (plus près des pinces montantes que des
				# descendantes à la même distance)
				var inv: Transform3D = lg.global_transform.affine_inverse()
				var loc: Vector3 = inv * p
				var lp: Vector3 = inv * lg.tires_pinces[j]
				var x_m: float = INF
				var x_d: float = INF
				for e in lg._vehicules:
					if not is_instance_valid(e[0]):
						continue
					var lv: Vector3 = (e[0] as Node3D).position
					if absf(lv.z - lp.z) < 15.0:
						if signf(lv.x) == signf(xb):
							x_m = minf(x_m, absf(lv.x - lp.x))
						else:
							x_d = minf(x_d, absf(lv.x - lp.x))
				if absf(loc.x - lp.x) > 1.0 or x_m > x_d:
					hors_brin += 1
				# (la perche télescopique doit atteindre l'assiette sous les fesses du skieur)
				l_max = maxf(l_max, (lg.tires_pinces[j] - p - Vector3(0, 0.72, 0)).length())
			_verif("tkd : skieurs tirés au sol, sous le brin de montée (retour %.1f m plus haut)" % LigneRemontee.DY_RETOUR_TKD,
				n > 0 and sol_max < 0.05 and hors_brin == 0 and l_max <= 3.25 * VehiculeRemontee.PERCHE_TKD_MAX + 0.3,
				"%d skieurs tirés près de la caméra, écart au sol maxi %.2f m, %d hors du brin montée ; le premier à d %.0f m, %.1f m de sa pince à la hauteur de l'assiette, %.1f m au pire (perche de %.1f m au plus)" % [n, sol_max, hors_brin, -(lg.global_transform.affine_inverse() * lg.tires_positions[0]).z if n > 0 else 0.0, (lg.tires_pinces[0] - lg.tires_positions[0] - Vector3(0, 0.72, 0)).length() if n > 0 else 0.0, l_max, 3.25 * VehiculeRemontee.PERCHE_TKD_MAX])
			_il += 1
			_e = 2
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
	# Funival : places dessinées (debout dans la caisse) et passagers affichés
	if lg is Funival and lg._vehicules.size() >= 1 and is_instance_valid(lg._vehicules[0][0]):
		var vf: VehiculeRemontee = lg._vehicules[0][0]
		var pl: Array = vf._places_passagers()
		var dehors: int = 0
		for e in pl:
			var o: Vector3 = (e[0] as Transform3D).origin
			if absf(o.x) > VehiculeFunival.DEMI_LARGEUR - 0.15 or absf(o.z) > VehiculeFunival.Z_UTILE + 0.5:
				dehors += 1
		OccupationRemontees.heure_forcee = 10.25
		(lg as Telepherique)._tirer_cabines()
		vf.poser_passagers((lg as Telepherique).passagers_cabine(0), 1)
		_verif("funival : %d places debout dans la caisse, passagers posés" % pl.size(),
			pl.size() >= 272 and dehors == 0 and vf._pax_n == mini((lg as Telepherique).passagers_cabine(0), pl.size()),
			"%d places hors de la caisse ; %d passagers affichés pour %d" % [dehors, vf._pax_n, (lg as Telepherique).passagers_cabine(0)])
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


## Skieurs sur les pistes : à 11 h, autour de la caméra, au sol, sur les pistes, en descente ; à 19 h, personne.
var _sp_e: int = 0
var _sp_t: float = 0.0
var _sp_y0: Dictionary = {}


func _skieurs_pistes() -> void:
	var sp: SkieursPistes = _main.domaine.skieurs if _main.get("domaine") != null else null
	if sp == null:
		_verif("skieurs sur les pistes : présents", false, "pas de SkieursPistes")
		_fin()
		return
	_sp_t += 1.0 / 60.0
	match _sp_e:
		0:
			OccupationRemontees.heure_forcee = 11.0
			sp._t_maj = 0.0
			_sp_e = 1
			_sp_t = 0.0
		1:
			if _sp_t < 8.0:
				return
			var cam: Vector3 = get_root().get_camera_3d().global_position
			var relief: ReliefBuilder = _main.get("relief")
			var loin: int = 0
			var sol: float = 0.0
			var hors: int = 0
			for p in sp.positions:
				if Vector2(p.x - cam.x, p.z - cam.z).length() > SkieursPistes.PORTEE + 25.0:
					loin += 1
				sol = maxf(sol, absf(p.y - 0.02 - relief.hauteur_sol(p.x, p.z)))
				if _main.domaine.hors_piste(p):
					hors += 1
			_verif("skieurs sur les pistes à 11 h : présents autour de la caméra, au sol, sur les pistes",
				sp.positions.size() >= 5 and loin == 0 and sol < 0.05 and hors <= sp.positions.size() / 10,
				"%d skieurs (voulus %d sur %d), %d au-delà de %.0f m, écart au sol maxi %.2f m, %d hors piste" % [
					sp.positions.size(), sp.n_voulu, SkieursPistes.n_max(), loin, SkieursPistes.PORTEE, sol, hors])
			_sp_y0.clear()
			for k in range(sp._agents.size()):
				_sp_y0[int(sp._agents[k]["id"])] = sp._hauteur(sp._point(int(sp._agents[k]["i"]), float(sp._agents[k]["s"])))
			_sp_e = 2
			_sp_t = 0.0
		2:
			if _sp_t < 3.0:
				return
			var desc: int = 0
			var mont: int = 0
			for ag in sp._agents:
				if not _sp_y0.has(int(ag["id"])):
					continue
				var y1: float = sp._hauteur(sp._point(int(ag["i"]), float(ag["s"])))
				if y1 < float(_sp_y0[int(ag["id"])]) - 0.5:
					desc += 1
				elif y1 > float(_sp_y0[int(ag["id"])]) + 0.5:
					mont += 1
			_verif("skieurs sur les pistes : ils descendent", desc > 0 and mont <= desc / 10,
				"en 3 s, %d descendus, %d montés" % [desc, mont])
			OccupationRemontees.heure_forcee = 19.0
			sp._t_maj = 0.0
			_sp_e = 3
			_sp_t = 0.0
		3:
			if _sp_t < 1.0:
				return
			_verif("skieurs sur les pistes à 19 h : personne", sp.positions.is_empty(), "%d skieurs" % sp.positions.size())
			_fin()

