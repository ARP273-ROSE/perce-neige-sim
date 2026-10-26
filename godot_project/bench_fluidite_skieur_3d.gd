## Banc de fluidité du mode skieur (retour d'utilisateur, 26/10/2026 : « audit
## de performance du programme PC en mode skieur ») : coût CPU de chaque image
## (sans rendu : headless), en régime établi et pendant les constructions.
##   1. au pied des pistes, à l'arrêt : durées d'image (médiane, p95, p99, max)
##      et part de chaque système (on le coupe 4 s, on mesure ce qu'on gagne) ;
##   2. assis dans un télésiège ;
##   3. tournée de six remontées (dépose depuis la carte) : les à-coups, avec
##      ce qui se passait à ce moment-là.
##   godot --headless --path godot_project -s bench_fluidite_skieur_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _phase: String = "chauffe"
var _t: float = 0.0
var _us_prec: int = 0
var _durees: PackedFloat32Array = PackedFloat32Array()
var _acoups: Array = []
var _acoups_siege: Dictionary = {}
var _tout: PackedFloat32Array = PackedFloat32Array()
var _ablations: Array = []          # [nom, nœud]
var _k_abl: int = -1
var _ref: float = 0.0
var _resultats: Array = []
var _tournee: Array = ["tsd6_madeleine", "tcd10_vallon_iseran", "tsd6_fresse", "cabine_3s", "tke_legettaz", "tsd6_leissieres"]
var _k_tour: int = 0
const DT: float = 1.0 / 60.0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _stats(d: PackedFloat32Array) -> String:
	if d.is_empty():
		return "—"
	var s: Array = Array(d)
	s.sort()
	var n: int = s.size()
	var moy: float = 0.0
	for x in s:
		moy += x
	moy /= n
	var lourdes: int = 0
	for x in s:
		if x > 16.7:
			lourdes += 1
	return "moy %.2f ms · médiane %.2f · p95 %.2f · p99 %.2f · max %.1f · > 16,7 ms : %d/%d" % [
		moy, s[n / 2], s[int(n * 0.95)], s[int(n * 0.99)], s[n - 1], lourdes, n]


func _moy(d: PackedFloat32Array) -> float:
	var m: float = 0.0
	for x in d:
		m += x
	return m / maxf(1.0, d.size())


func _contexte() -> String:
	var rm: RemonteesDomaine = _main.remontees
	var n_pret: int = 0
	for e in rm.lignes:
		if (e[0] as LigneRemontee).pret:
			n_pret += 1
	return "construit : %s · %d lignes prêtes · poubelle %d" % [
		str(rm._en_cours.name) if rm._en_cours != null else "—", n_pret, rm._poubelle.size()]


func _tick() -> void:
	_f += 1
	var us: int = Time.get_ticks_usec()
	var ms: float = (us - _us_prec) / 1000.0
	_us_prec = us
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		# comme en jeu : collisions à la demande étalées, tranches mesurées
		_main.collisions.synchrone_sans_ecran = false
		LigneRemontee.mesurer_tranches = true
		return
	_t += DT
	var rm: RemonteesDomaine = _main.remontees
	var sk: SkieurJoueur = _main.skieur
	match _phase:
		"chauffe":
			# les lignes proches se construisent, les shaders se compilent
			if _t > 60.0 and rm._en_cours == null:
				_phase = "arret"
				_t = 0.0
				_durees.clear()
		"arret":
			_durees.append(ms)
			if _t > 20.0:
				_resultats.append("1. À l'arrêt au pied des pistes (20 s) : " + _stats(_durees))
				_resultats.append("   " + _contexte())
				_resultats.append("   nœuds %d · objets %d · mémoire statique %.0f Mo" % [
					Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT),
					Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
				_ref = _moy(_durees)
				for c in _main.get_children():
					# (sans Collisions ni Relief, le skieur passe sous la neige : tout
					# est caché, la mesure ne veut plus rien dire)
					if c is Node and c.process_mode != Node.PROCESS_MODE_DISABLED and c != sk and not (c.name in ["Collisions", "Relief"]):
						_ablations.append([c.name, c])
				# dans les remontées : chaque ligne prête, les sons
				for c in rm.get_children():
					if (c is LigneRemontee and (c as LigneRemontee).pret) or c is SonsRemontees:
						_ablations.append(["  Remontees/" + c.name, c])
				_k_abl = 0
				_phase = "ablation"
				_t = 0.0
				_durees.clear()
		"ablation":
			if _k_abl >= _ablations.size():
				var l: Array = _ablations.filter(func(a): return a.size() > 2)
				l.sort_custom(func(a, b): return a[2] > b[2])
				_resultats.append("   part de chaque système (gain quand on le coupe, sur %.2f ms) :" % _ref)
				for a in l.slice(0, 30):
					_resultats.append("     %-28s %6.2f ms" % [a[0], a[2]])
				_phase = "siege"
				_t = 0.0
				_main.aller_a_remontee(_ligne("tsd6_madeleine"))
				return
			var nd: Node = _ablations[_k_abl][1]
			if _t < DT * 1.5:
				nd.process_mode = Node.PROCESS_MODE_DISABLED
				_durees.clear()
			elif _t > 1.0:
				_durees.append(ms)
			if _t > 4.0:
				nd.process_mode = Node.PROCESS_MODE_INHERIT
				_ablations[_k_abl].append(_ref - _moy(_durees))
				_k_abl += 1
				_t = 0.0
				# chaque système rétabli : une seconde de mesure de référence
				_durees.clear()
		"siege":
			var lg: LigneRemontee = _ligne("tsd6_madeleine")
			if rm.a_bord.is_empty():
				if lg.pret and _t > 3.0 and _t < 60.0:
					var q: Vector3 = lg.global_transform * lg.point_embarquement(true)
					if sk.global_position.distance_to(q) > 1.0:
						sk.activer(q + Vector3(0, 0.1, 0), 0.0)
						sk.dernier_sol = q
				elif _t > 60.0:
					_resultats.append("2. Télésiège : pas embarqué en 60 s")
					_suivant()
				return
			if _durees.is_empty() and _t < 1e5:
				_t = 1e5
			_durees.append(ms)
			if ms > 33.0:
				var ec2: LigneRemontee = rm._en_cours
				_acoups_siege[str(ec2.name) if ec2 != null else "rien (collisions, relief…)"] = _acoups_siege.get(str(ec2.name) if ec2 != null else "rien (collisions, relief…)", 0) + 1
			if _t > 1e5 + 40.0:
				_resultats.append("2. Assis dans le télésiège de la Madeleine (40 s) : " + _stats(_durees))
				_resultats.append("   à-coups > 33 ms selon ce qui se construit : " + str(_acoups_siege))
				_resultats.append("   " + _contexte())
				_suivant()
		"tournee":
			_durees.append(ms)
			if ms > 33.0:
				var ec: LigneRemontee = rm._en_cours
				_acoups.append([ms, str(ec.name) if ec != null else "rien (collisions, relief…)"])
			if _t > 25.0:
				_resultats.append("   « %s » : %s" % [_tournee[_k_tour], _stats(_durees)])
				_tout.append_array(_durees)
				_durees.clear()
				_k_tour += 1
				if _k_tour >= _tournee.size():
					_resultats.append("3. Tournée de %d remontées (25 s chacune) : %s" % [_tournee.size(), _stats(_tout)])
					_resultats.append("   à-coups > 33 ms : %d" % _acoups.size())
					# à-coups regroupés par ligne en construction
					var par: Dictionary = {}
					for a in _acoups:
						par[a[1]] = par.get(a[1], []) + [a[0]]
					for k in par:
						var l: Array = par[k]
						l.sort()
						_resultats.append("     pendant « %s » : %d images > 33 ms, pire %.0f ms" % [k, l.size(), l[l.size() - 1]])
					_resultats.append("   pires tranches de construction d'un seul tenant, par étape :")
					var et: Array = LigneRemontee.tranches.keys()
					et.sort_custom(func(a, b): return LigneRemontee.tranches[a][0] > LigneRemontee.tranches[b][0])
					for k2 in et:
						_resultats.append("     %-42s %6.1f ms (%s)" % [k2, LigneRemontee.tranches[k2][0], LigneRemontee.tranches[k2][1]])
					_fin()
					return
				_aller()


func _suivant() -> void:
	var rm: RemonteesDomaine = _main.remontees
	rm.quitter()
	_phase = "tournee"
	_durees.clear()
	_k_tour = 0
	_aller()


func _aller() -> void:
	_t = 0.0
	var lg: LigneRemontee = _ligne(_tournee[_k_tour])
	if lg != null:
		_main.aller_a_remontee(lg)


func _ligne(cle: String) -> LigneRemontee:
	for e in (_main.remontees as RemonteesDomaine).lignes:
		var lg: LigneRemontee = e[0]
		if lg.name == cle or (cle == "cabine_3s" and lg.tricable()):
			return lg
	return null


func _fin() -> void:
	print("=== FLUIDITÉ DU MODE SKIEUR (CPU, sans rendu) — %s, %d cœurs" % [OS.get_processor_name(), OS.get_processor_count()])
	for r in _resultats:
		print(r)
	print("BENCH_FLUIDITE_SKIEUR OK")
	quit(0)
