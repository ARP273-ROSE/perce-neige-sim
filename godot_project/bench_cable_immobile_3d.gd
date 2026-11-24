## Banc du câble immobile en marche établie (retours d'utilisateur des 19 et 20/11/2026 : « oscillation verticale de
## 1 Hz de tous les câbles ») : flèche dessinée (LigneRemontee._fleche, même calcul que le nuanceur ; noyau C++ :
## fleche_en) en trois points fixes de portée, deux brins, 20 s à vitesse nominale, sur un TSD, une TCD, un TSF, le
## 3S et un téléphérique. 3S et téléphérique (porteurs creusés sous chaque cabine, lentement) : composante rapide
## (au-dessus de 0,5 Hz) ≤ 1 cm. Monocâbles : depuis le 24/11/2026 (« physique parfaite » : chaque véhicule casse le
## câble de son poids réel), le câble monte et descend au passage des véhicules — l'amplitude doit être PHYSIQUE :
## non nulle (≥ 5 mm) et dans l'enveloppe P·e/8H (charges égales) + ΔP·x(L−x)/(L·H) (un véhicule plein au lieu d'un
## vide), + 2 cm (audit_physique/physique_cables.sage). NOYAU=1 : avec le module C++.
extends SceneTree
var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _lignes: Array = ["tsd6_grattalu", "tcd10_daille", "tsf4_almes", "olympique", "tph_grande_motte"]
var _k: int = 0
var _att: int = 0
var _lg: LigneRemontee = null
var _pts: Array = []
var _series: Array = []
var _echecs: int = 0
var _bilan: Array = []


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
	if _k >= _lignes.size():
		var ok: bool = _echecs == 0 and _bilan.size() == _lignes.size()
		for b in _bilan:
			print(b)
		print("%s câble immobile en marche (%s) : %d lignes, %d échecs" % ["[OK]  " if ok else "[ECHEC]",
			"C++" if not LigneRemontee.noyau_desactive else "GDScript", _bilan.size(), _echecs])
		print("BENCH_CABLE_IMMOBILE " + ("OK" if ok else "ECHEC"))
		FinBanc.quitter(self, _main, 0 if ok else 1)
		return
	if _att == 0:
		_lg = _main.remontees.ligne_par_id(_lignes[_k])
		if _lg == null:
			_bilan.append("[ECHEC] %s introuvable" % _lignes[_k])
			_echecs += 1
			_k += 1
			return
		_main.aller_a_remontee(_lg)
		_pts.clear()
		_series.clear()
	_att += 1
	if not _lg.pret or _att < 600:
		return
	if _pts.is_empty():
		var n: int = _lg._n_appuis
		if n < 2:
			_bilan.append("[ECHEC] %s sans appuis" % _lg.name)
			_echecs += 1
			_k += 1
			_att = 0
			return
		# trois portées de ligne, au milieu et aux quarts
		for j in [int(n / 4), int(n / 2), int(3 * n / 4)]:
			var jj: int = clampi(j, 0, n - 2)
			for t in [0.25, 0.5]:
				_pts.append(lerpf(_lg._appuis[jj], _lg._appuis[jj + 1], t))
		for _q in range(_pts.size() * 2):
			_series.append([])
	var trop: bool = _att > 600 + 60 * 150
	if _lg.etat == "marche" and _lg.regime() >= 0.99:
		for q in range(_pts.size()):
			for b in range(2):
				(_series[q * 2 + b] as Array).append(_lg._fleche(_pts[q], b == 0))
	elif not trop:
		return
	if (_series[0] as Array).size() < 1200 and not trop:
		return
	if (_series[0] as Array).size() < 300:
		_bilan.append("[ECHEC] %s : %d relevés en marche seulement (état %s, régime %.2f)" % [_lg.name, (_series[0] as Array).size(), _lg.etat, _lg.regime()])
		_echecs += 1
		_k += 1
		_att = 0
		return
	if OS.get_environment("DUMP") == "1":
		var out: String = ""
		for r in range((_series[0] as Array).size()):
			var l: Array = []
			for sr0 in _series:
				l.append("%.5f" % float((sr0 as Array)[r]) if r < (sr0 as Array).size() else "nan")
			out += " ".join(l) + "\n"
		var fh := FileAccess.open("/tmp/cable_imm_%s.txt" % _lg.name, FileAccess.WRITE)
		fh.store_string(out)
		fh.close()
	var lent: bool = _lg.tricable() or _lg.vaetvient()
	var pire: float = 0.0
	var marge: float = 0.0          # monocâbles : écart à l'enveloppe physique (≤ 0 attendu)
	var plus_petite: float = INF
	var g: float = 9.81
	var p_vide: float = _lg.masse_vehicule() * g
	var p_plein: float = (_lg.masse_vehicule() + OccupationRemontees.PAX_KG * _lg.places_vehicule()) * g
	var h: float = _lg._tension
	var iq: int = -1
	for sr in _series:
		iq += 1
		var a: Array = sr
		var amp: float = 0.0
		if lent:
			# porteurs creusés sous les cabines qui passent : lent, une bosse par passage. Une oscillation, c'est des
			# allers-retours rapprochés : écarts entre extrêmes successifs (série lissée sur 0,1 s) séparés de moins
			# de 1,5 s
			var lis: Array = []
			for i in range(3, a.size() - 3):
				var m: float = 0.0
				for k2 in range(i - 3, i + 4):
					m += a[k2]
				lis.append(m / 7.0)
			var ext: Array = []        # [indice, valeur]
			for i in range(1, lis.size() - 1):
				if (lis[i] - lis[i - 1]) * (lis[i + 1] - lis[i]) < 0.0:
					ext.append([i, lis[i]])
			for k3 in range(1, ext.size()):
				if int(ext[k3][0]) - int(ext[k3 - 1][0]) < 90:
					amp = maxf(amp, absf(float(ext[k3][1]) - float(ext[k3 - 1][1])))
		else:
			var lo: float = INF
			var hi: float = -INF
			for x in a:
				lo = minf(lo, x)
				hi = maxf(hi, x)
			amp = hi - lo
			var dq: float = float(_pts[iq / 2])
			var ip: int = _lg._portee_de(dq)
			var x1: float = _lg._appuis[ip]
			var x2: float = _lg._appuis[ip + 1]
			var env: float = p_plein * maxf(_lg.espacement, 8.0) / (8.0 * h) + (p_plein - p_vide) * (dq - x1) * (x2 - dq) / ((x2 - x1) * h) + 0.02
			marge = maxf(marge, amp - env)
			# (mouvement exigé dans la zone détaillée autour du point de vue seulement : au-delà, poids moyen)
			if x1 >= _lg._zone_loc.x - 1e-3 and x2 <= _lg._zone_loc.y + 1e-3:
				plus_petite = minf(plus_petite, amp)
		pire = maxf(pire, amp)
	var ok1: bool = pire <= 0.01 if lent else (marge <= 0.0 and plus_petite >= 0.005 and plus_petite < INF)
	if not ok1:
		_echecs += 1
	if lent:
		_bilan.append("%s %s : aller-retour rapide %.4f m (seuil 0,01)" % ["[OK]  " if ok1 else "[ECHEC]", _lg.name, pire])
	else:
		_bilan.append("%s %s : amplitude %.3f m (mini %.3f, ≥ 0,005), dépassement de l'enveloppe physique %.3f m (≤ 0)" % [
			"[OK]  " if ok1 else "[ECHEC]", _lg.name, pire, plus_petite, marge])
	_k += 1
	_att = 0
