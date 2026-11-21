## Banc des véhicules des remontées vus de loin, chemin GDScript (PWA, sans module) : retour d'essai PWA du 19/11/2026,
## « au loin, les sièges et les cabines s'empilent, certains avancent, d'autres restent figés en milieu de ligne ».
## Pendant 90 s, toutes les 2 s,
## pour chaque ligne qui roule : véhicule figé (abscisse inchangée sur 10 s alors que la ligne tourne), véhicule
## dessiné loin de sa place logique (> 5 m), deux véhicules dessinés l'un sur l'autre (< 2 m) sur la même ligne.
extends SceneTree
var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _att: int = 0
var _hist: Dictionary = {}     # ligne → [[t, s par véhicule]...]
var _t: float = 0.0
var _duree: float = 180.0
var _figes: Dictionary = {}
var _decal: Dictionary = {}
var _empil: Dictionary = {}
var _n_mes: int = 0


func _initialize() -> void:
	LigneRemontee.noyau_desactive = OS.get_environment("NOYAU") != "1"
	# chemin de la PWA : véhicules lointains en instances allégées (VehiculesLod), comme à l'export web
	LigneRemontee.lod_force = LigneRemontee.noyau_desactive
	_duree = 90.0
	OccupationRemontees.heure_forcee = 11.0
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


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
	if _att == 0:
		_main.aller_a_remontee(_main.remontees.ligne_par_id(OS.get_environment("CLE") if OS.has_environment("CLE") else "tsd6_grattalu"))
	_att += 1
	if _att < 300:
		return
	_t += 1.0 / 60.0
	if _att % 120 != 0:
		return
	_n_mes += 1
	for e in _main.remontees.lignes:
		var lg: LigneRemontee = e[0]
		if not lg.pret or not lg.roule or lg is Funival or lg.vaetvient() or lg.teleski():
			continue
		var cle: String = String(lg.name)
		var ss: PackedFloat64Array = PackedFloat64Array()
		for i in range(lg.nombre_vehicules()):
			ss.append(float(lg._vehicules[i][1]))
		if not _hist.has(cle):
			_hist[cle] = []
		var h: Array = _hist[cle]
		h.append([_t, ss, lg.regime()])
		if h.size() > 6:
			h.pop_front()
		# instances allégées orphelines : une place du tampon dont le véhicule ne pointe pas vers elle reste dessinée,
		# figée (table place → véhicule jamais écrite, retour d'essai PWA du 21/11/2026, gare aval de Bellevarde)
		if lg._lod_mm.size() == 2:
			for k in range(2):
				for j in range(lg._lod_nb[k]):
					var iq: int = (lg._lod_qui[k] as PackedInt32Array)[j]
					if iq < 0 or iq >= lg._lod_slot.size() or lg._lod_slot[iq] != j or lg._lod_niv[iq] != k + 1:
						_figes[cle + "_orphelin"] = int(_figes.get(cle + "_orphelin", 0)) + 1
						if int(_figes[cle + "_orphelin"]) == 1:
							print("ORPHELIN %s niveau %d place %d (véhicule %d)" % [cle, k + 1, j, iq])
		# figés : 10 s sans bouger alors que la ligne tourne (véhicules dessinés, en ligne)
		var vus: Dictionary = {}
		# dessinés : nœud (niveau 0) ou instance allégée (1, 2) ; place logique : _lod_pose
		var dess: Array = []
		for i in range(lg.nombre_vehicules()):
			var niv: int = lg._lod_niv[i] if i < lg._lod_niv.size() else 0
			var p_log: Vector3 = lg.to_global(lg._lod_pose(i).origin)
			var p_des: Variant = null
			if niv == 0:
				var v: Node3D = lg.vehicule(i)
				if v.visible and v.is_visible_in_tree():
					p_des = v.global_position
			elif niv == 1 or niv == 2:
				var b: PackedFloat32Array = lg._lod_b1 if niv == 1 else lg._lod_b2
				var o: int = lg._lod_slot[i] * 12
				if o >= 0 and o + 11 < b.size():
					p_des = lg.to_global(Vector3(b[o + 3], b[o + 7], b[o + 11])) if not lg.top_level else Vector3(b[o + 3], b[o + 7], b[o + 11])
			if p_des == null or lg.zone(float(lg._vehicules[i][1]))[0] != "ligne":
				continue
			vus[i] = true
			# (au-delà de 250 m, posés une image sur quatre : 4 images de retard au plus)
			var tol: float = 5.0 + lg.vitesse * 4.0 / 30.0
			if (p_des as Vector3).distance_to(p_log) > tol:
				_decal[cle] = int(_decal.get(cle, 0)) + 1
				if int(_decal[cle]) <= 2:
					print("DECALE %s véhicule %d niveau %d : %.1f m de sa place" % [cle, i, niv, (p_des as Vector3).distance_to(p_log)])
			dess.append([p_des, i, niv, float(lg._vehicules[i][1]), p_log])
		if h.size() >= 6 and lg._au_magasin.is_empty():
			for i in vus:
				# (ligne arrêtée ou non traitée : regime ou pas — un véhicule dessiné qui ne bouge plus alors que sa
				# ligne est censée tourner)
				if lg.etat == "marche" and absf(float((h[0][1] as PackedFloat64Array)[i]) - ss[i]) < 0.01:
					_figes[cle] = int(_figes.get(cle, 0)) + 1
					if int(_figes[cle]) == 1:
						print("FIGE %s véhicule %d niveau %d, ligne traitée %s, régime %.2f, au repos %s, cachés loin %d, noyau %s, t %.0f s" % [cle, i, lg._lod_niv[i] if i < lg._lod_niv.size() else -1, lg.is_processing(), lg.regime(), str(lg.get_meta("au_repos", "?")), Array(lg._caches_loin).count(1), lg._noyau != null, _t])
		for a in range(dess.size()):
			for b2 in range(a + 1, dess.size()):
				if (dess[a][0] as Vector3).distance_to(dess[b2][0]) < 2.0:
					_empil[cle] = int(_empil.get(cle, 0)) + 1
					if int(_empil[cle]) <= 2:
						print("EMPILE %s : %s / %s ; pas_lod %d, vue_active %s, noyau %s, lod_mm %d, jusqua %.0f" % [cle, str(dess[a]), str(dess[b2]), lg.pas_lod, lg.vue_active, lg._noyau != null, lg._lod_mm.size(), lg._vehicules_jusqua])
	if _t >= _duree:
		print("LOINTAINS mesures %d ; figés %s ; dessinés loin de leur place %s ; empilés %s" % [_n_mes, str(_figes), str(_decal), str(_empil)])
		var ok: bool = _figes.is_empty() and _empil.is_empty() and _n_mes > 30
		print("%s véhicules lointains (GDScript) : aucun figé, aucun empilé — %d relevés" % ["[OK]  " if ok else "[ECHEC]", _n_mes])
		print("BENCH_VEHICULES_LOINTAINS " + ("OK" if ok else "ECHEC"))
		FinBanc.quitter(self, _main, 0 if ok else 1)
