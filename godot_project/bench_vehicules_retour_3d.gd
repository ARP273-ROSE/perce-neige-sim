## Banc du retour des véhicules après une ligne mise au repos : retour d'essai PC du 20/11/2026 (1.75.3), en gare amont
## du Funival, « il est où le wagon ? » — la ligne, mise au repos quand le skieur était loin, avait caché ses véhicules
## (LigneRemontee.lointains_au_repos, chemin sans noyau) ; seule _etape_gdscript les remontrait, que le Funival et les
## téléphériques (leur propre _process_corps) n'appellent jamais : rames et cabines cachées pour de bon.
## Le skieur va loin (Grattalu), puis tour à tour au Funival, aux deux téléphériques et à une télécabine : aucun
## véhicule ne doit rester caché « parce que loin » à moins de la portée des véhicules, et les rames et cabines du
## Funival et des téléphériques doivent être visibles.
extends SceneTree
var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _att: int = 0
var _etape: int = 0
## (départ : une ligne d'où la cible est construite mais mise au repos — de Solaise, le Funival et le Fornet ; du Lac de
## Tignes, la Grande Motte)
var _cibles: Array = ["tcd10_solaise", "funival", "tcd10_solaise", "tph_fornet", "tsd6_grattalu", "tph_grande_motte", "tcd10_daille"]
# (et en ligne : le Funival et les deux téléphériques vérifiés aussi, cabine hors gare, après une mise au repos)
var _departs: Array = ["tcd10_solaise", "tsd6_grattalu"]
var _echecs: Array = []
var _vus: int = 0


func _initialize() -> void:
	LigneRemontee.noyau_desactive = OS.get_environment("NOYAU") != "1"
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
	if _etape >= _cibles.size():
		var ok: bool = _echecs.is_empty() and _vus >= 4
		for e in _echecs:
			print("CACHE ", e)
		print("%s véhicules revenus après repos : %d lignes vérifiées, %d véhicules cachés à tort" % ["[OK]  " if ok else "[ECHEC]", _vus, _echecs.size()])
		print("BENCH_VEHICULES_RETOUR " + ("OK" if ok else "ECHEC"))
		FinBanc.quitter(self, _main, 0 if ok else 1)
		return
	var cle: String = _cibles[_etape]
	var lg: LigneRemontee = _main.remontees.ligne_par_id(cle)
	if _att == 0:
		_main.aller_a_remontee(lg)
	# (Funival et téléphériques, arrivée en gare : mise au repos forcée, comme quand le skieur était loin au cran 0 —
	# la ligne reste construite ; retour d'essai PC du 20/11/2026 au Fornet aussi, « la cabine est invisible »)
	if _att == 300 and lg is Telepherique and lg.pret:
		lg.lointains_au_repos()
	_att += 1
	if _att < 600:
		return
	_att = 0
	_etape += 1
	if cle in _departs:
		for k in ["funival", "tph_grande_motte", "tph_fornet"]:
			var l2: LigneRemontee = _main.remontees.ligne_par_id(k)
			print("REPOS %s depuis %s : au_repos=%s, véhicules %d, cachés loin %d" % [k, cle, l2.get_meta("au_repos", false), l2.nombre_vehicules(), Array(l2._caches_loin).count(1)])
		return
	if not lg.pret:
		_echecs.append("%s pas prête" % cle)
		return
	_vus += 1
	var sk: Vector3 = _main.skieur.global_position
	for i in range(lg.nombre_vehicules()):
		var v: Node3D = lg.vehicule(i)
		var cache_loin: bool = i < lg._caches_loin.size() and lg._caches_loin[i] == 1
		var proche: bool = v.global_position.distance_to(sk) < lg._vehicules_jusqua - 30.0
		if lg is Telepherique:
			if not v.visible:
				_echecs.append("%s véhicule %d invisible (caché loin %s)" % [cle, i, cache_loin])
		elif cache_loin and proche:
			_echecs.append("%s véhicule %d caché « loin » à %.0f m" % [cle, i, v.global_position.distance_to(sk)])
	print("LIGNE %s : %d véhicules, cachés loin %d" % [cle, lg.nombre_vehicules(), Array(lg._caches_loin).count(1)])
