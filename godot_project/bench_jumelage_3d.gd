## Banc du jumelage Bollin – Fresse (tronçons qui s'échangent leurs sièges à la gare intermédiaire) : un arrêt sur
## l'un arrête l'autre au même régime (retour d'utilisateur du 19/11/2026 : « si l'une ralentit ou s'arrête, l'autre
## doit suivre, sinon les véhicules se percutent au croisement »). Arrêt d'urgence sur Fresse, puis réarmement et
## redémarrage ; arrêt normal sur Bollin. À chaque image : même régime sur les deux lignes (écart < 1 %), et pas deux
## sièges l'un dans l'autre (centres à moins de 1,2 m) ; les deux lignes à l'arrêt après l'arrêt d'urgence.
##   NOYAU=0 : chemin GDScript (PWA)
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _att: int = 0
var _bo: LigneRemontee = null
var _fr: LigneRemontee = null
var _ph: int = 0
var _pire_regime: float = 0.0
var _pire_dist: float = INF
var _ok: bool = true


func _initialize() -> void:
	if OS.get_environment("NOYAU") == "0":
		LigneRemontee.noyau_desactive = true
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _tick() -> void:
	_f += 1
	var pm: Node = _main.get("perf_manager")
	if pm != null and not bool(pm.get("banc")):
		pm.set("banc", true)
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		if _f > 60 * 600:
			_verif("relief prêt", false)
			_fin()
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	if not _main.mode_skieur or _main.remontees == null or not _main.remontees.pret:
		return
	if _bo == null:
		_bo = _main.remontees.ligne_par_id("tsd6_bollin")
		_fr = _main.remontees.ligne_par_id("tsd6_fresse")
		_main.aller_a_remontee(_bo)
		return
	if not (_bo.pret and _fr.pret and _bo.roule and _fr.roule):
		return
	_att += 1
	if _att < 300:
		return
	_mesurer()
	var t: int = _att - 300
	match _ph:
		0:
			if t > 60 * 60:
				_verif("marche normale : pas deux sièges l'un dans l'autre (60 s)", _pire_dist > 1.2,
					"plus courte distance entre sièges %.2f m" % _pire_dist)
				_fr.exploitation().commande("urgence")
				print("BANC arrêt d'urgence sur Fresse (régimes %.2f / %.2f)" % [_bo.regime(), _fr.regime()])
				_ph = 1
				_main.set_meta("t_ph", _att)
		1:
			if _att - int(_main.get_meta("t_ph")) > 60 * 8:
				_verif("arrêt d'urgence de Fresse : Bollin arrêté aussi", _bo.regime() < 0.01 and _fr.regime() < 0.01,
					"régimes %.3f / %.3f" % [_bo.regime(), _fr.regime()])
				_fr.exploitation().commande("rearmer")
				_fr.exploitation().commande("demarrer")
				_ph = 2
				_main.set_meta("t_ph", _att)
		2:
			if _att - int(_main.get_meta("t_ph")) > 60 * 20:
				_verif("redémarrage : les deux lignes repartent ensemble", _bo.regime() > 0.2 and _fr.regime() > 0.2,
					"régimes %.3f / %.3f" % [_bo.regime(), _fr.regime()])
				_bo.exploitation().commande("arreter")
				_ph = 3
				_main.set_meta("t_ph", _att)
		3:
			if _att - int(_main.get_meta("t_ph")) > 60 * 30:
				_verif("arrêt normal de Bollin : Fresse arrêté aussi", _bo.regime() < 0.01 and _fr.regime() < 0.01,
					"régimes %.3f / %.3f" % [_bo.regime(), _fr.regime()])
				_verif("même régime sur les deux tronçons à chaque image", _pire_regime < 0.01, "pire écart %.4f" % _pire_regime)
				_verif("pas deux sièges l'un dans l'autre", _pire_dist > 1.2, "plus courte distance entre sièges %.2f m" % _pire_dist)
				_fin()


func _mesurer() -> void:
	_pire_regime = maxf(_pire_regime, absf(_bo.regime() - _fr.regime()))
	# sièges des deux tronçons près de la gare intermédiaire (haut de Bollin) : distances deux à deux
	var g: Vector3 = _bo.global_transform * Vector3(0, 0, -_bo.longueur_h())
	var pts: Array = []
	for lg in [_bo, _fr]:
		for i in range(lg.nombre_vehicules()):
			# (position logique du siège, jumelage compris : les nœuds au loin peuvent être figés par le niveau de détail)
			var s2: float = fposmod(float(lg._vehicules[i][1]), lg.longueur_boucle)
			var pw: Vector3 = lg.to_global(lg._pos_vehicule(i, s2))
			if pw.distance_to(g) < 120.0:
				pts.append([pw, String(lg.name), i, lg.zone(s2)[0], s2])
	for a in range(pts.size()):
		for b in range(a + 1, pts.size()):
			var dd: float = (pts[a][0] as Vector3).distance_to(pts[b][0])
			# (passage de main à la gare intermédiaire : le siège qui traverse est, l'espace d'une image, à la
			# fois le dernier point du tronçon qu'il quitte et le premier de l'autre — le même siège, pas deux)
			if dd < 0.3 and pts[a][1] != pts[b][1]:
				continue
			if dd < 1.2 and _pire_dist >= 1.2:
				print("BANC rapprochés (phase %d) : %s / %s à %.2f m" % [_ph, str(pts[a].slice(1)), str(pts[b].slice(1)), dd])
			_pire_dist = minf(_pire_dist, dd)


func _fin() -> void:
	print("BENCH_JUMELAGE " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _ok else 1)
