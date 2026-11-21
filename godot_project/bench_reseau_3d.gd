## Banc du mode réseau : relais local (reseau/relais/relais.py, python3 + websockets) et deux jeux sans écran
## (reseau_banc_joueur.gd), l'un avec le module C++ (A, hôte), l'autre en GDScript seul comme la PWA (B).
## A skie 14 s en ligne droite à 10 m/s puis s'assied sur un siège du TSD de Grattalu ; B doit le dessiner à moins
## de 1 m de sa vraie position (temps commun), à ski puis à bord (véhicules calés par l'hôte).
## Temps réel (pas de --fixed-fps chez les joueurs : l'horloge commune est celle du relais).
extends SceneTree

const SEUIL: float = 1.0

var _port: int = 0
var _dos: String = ""
var _pids: Array = []
var _t0: int = 0
var _etape: int = 0
var _url: String = ""


func _initialize() -> void:
	_port = 18800 + (Time.get_ticks_usec() % 700)
	_dos = "/tmp/reseau_banc_%d" % _port
	DirAccess.make_dir_recursive_absolute(_dos)
	for f in ["code.txt", "A.json", "B.json"]:
		DirAccess.remove_absolute(_dos.path_join(f))
	var racine: String = ProjectSettings.globalize_path("res://")
	var relais: String = racine.path_join("../reseau/relais/relais.py").simplify_path()
	_url = "ws://127.0.0.1:%d" % _port
	_pids.append(OS.create_process("python3", [relais, "--hote", "127.0.0.1", "--port", str(_port)]))
	print("RESEAU relais pid %d port %d" % [_pids[0], _port])
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_tick)


func _lancer(role: String, extra: Array) -> void:
	var a: Array = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "reseau_banc_joueur.gd",
		"--", "--role=" + role, "--url=" + _url, "--sortie=" + _dos]
	a.append_array(extra)
	var pid: int = OS.create_process(OS.get_executable_path(), a)
	_pids.append(pid)
	print("RESEAU joueur %s pid %d" % [role, pid])


func _lire(nom: String) -> Variant:
	var p: String = _dos.path_join(nom)
	if not FileAccess.file_exists(p):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(p))


func _fin(ok: bool, msg: String) -> void:
	for pid in _pids:
		if pid > 0:
			OS.kill(pid)
	print(("BANC OK " if ok else "BANC ECHEC ") + msg)
	quit(0 if ok else 1)


func _tick() -> void:
	var t: float = float(Time.get_ticks_msec() - _t0) / 1000.0
	if t > 1400.0:
		_fin(false, "délai dépassé (étape %d)" % _etape)
		return
	match _etape:
		0:
			if t > 1.5:
				_lancer("A", [])
				_etape = 1
		1:
			var c: String = FileAccess.get_file_as_string(_dos.path_join("code.txt")) \
				if FileAccess.file_exists(_dos.path_join("code.txt")) else ""
			if c.length() == 8:
				_lancer("B", ["--code=" + c, "--sans-noyau"])
				_etape = 2
		2:
			var a: Variant = _lire("A.json")
			var b: Variant = _lire("B.json")
			if a == null or b == null:
				return
			_comparer(a, b)


static func _verite(notes: Array, t: float) -> Array:
	for k in range(notes.size() - 1):
		var ta: float = float(notes[k][0])
		var tb: float = float(notes[k + 1][0])
		if t >= ta and t <= tb and tb > ta:
			var f: float = (t - ta) / (tb - ta)
			var pa: Vector3 = Vector3(notes[k][1], notes[k][2], notes[k][3])
			var pb: Vector3 = Vector3(notes[k + 1][1], notes[k + 1][2], notes[k + 1][3])
			return [pa.lerp(pb, f), String(notes[k][4])]
	return []


func _comparer(a: Dictionary, b: Dictionary) -> void:
	var na: Array = a["notes"]
	var nb: Array = b["notes"]
	if not bool(a["ok"]) or na.is_empty() or nb.is_empty():
		_fin(false, "joueur A en échec ou notes vides (A %d, B %d)" % [na.size(), nb.size()])
		return
	# temps de début de chaque phase chez A
	var debut: Dictionary = {}
	var fin_ph: Dictionary = {}
	for n in na:
		var ph: String = n[4]
		if not debut.has(ph):
			debut[ph] = float(n[0])
		fin_ph[ph] = float(n[0])
	var err: Dictionary = {"ski": [], "assis": []}
	var bord: int = 0
	for n2 in nb:
		var tb: float = float(n2[0])
		var v: Array = _verite(na, tb)
		if v.is_empty():
			continue
		var ph2: String = v[1]
		# régime établi : 2 s après le début du ski ; à bord, les 15 dernières secondes (calage des véhicules fait)
		if ph2 == "ski" and (tb < float(debut["ski"]) + 2.0 or tb > float(fin_ph["ski"]) - 0.5):
			continue
		if ph2 == "assis" and tb < float(fin_ph["assis"]) - 15.0:
			continue
		var e: float = Vector3(n2[1], n2[2], n2[3]).distance_to(v[0])
		(err[ph2] as Array).append(e)
		if ph2 == "assis" and bool(n2[5]):
			bord += 1
	var lignes: Array = []
	var ok: bool = true
	for ph3 in ["ski", "assis"]:
		var l: Array = err[ph3]
		if l.is_empty():
			ok = false
			lignes.append("%s : aucune mesure" % ph3)
			continue
		l.sort()
		var med: float = l[l.size() / 2]
		var p95: float = l[int(l.size() * 0.95)]
		var mx: float = l[l.size() - 1]
		lignes.append("%s : %d mesures, médiane %.2f m, p95 %.2f m, max %.2f m" % [ph3, l.size(), med, p95, mx])
		if p95 > SEUIL:
			ok = false
	var n_assis: int = (err["assis"] as Array).size()
	lignes.append("à bord (dans un véhicule de B) : %d/%d ; calages appliqués par B : %d" % [bord, n_assis,
		int(b.get("calages", 0))])
	if n_assis > 0 and bord < n_assis * 0.9:
		ok = false
	var ok_l: bool = _comparer_lignes(a, b, lignes)
	ok = ok and ok_l
	for l2 in lignes:
		print("RESEAU " + l2)
	_fin(ok, "mode réseau : " + " ; ".join(lignes))


## Remontées « calées partout » : mêmes positions et mêmes états chez A et B, aux mêmes instants (grille de temps
## commun) ; arrêt d'urgence de A vu par B ; arrêt du TPH par B (pilote accordé par l'hôte A) vu par A.
func _comparer_lignes(a: Dictionary, b: Dictionary, lignes: Array) -> bool:
	var la: Dictionary = {}
	for e in a.get("lignes", []):
		la[int(e[0])] = e[1]
	var lb: Array = b.get("lignes", [])
	if la.is_empty() or lb.is_empty():
		lignes.append("remontées : aucun relevé (A %d, B %d)" % [la.size(), lb.size()])
		return false
	var ok: bool = true
	var k0: int = -1
	var ecarts: Dictionary = {}
	var premier: Dictionary = {}
	for e2 in lb:
		var k: int = int(e2[0])
		if not la.has(k):
			continue
		var da: Dictionary = la[k]
		var db: Dictionary = e2[1]
		if k0 < 0:
			k0 = k
		for n in db:
			if not da.has(n):
				continue
			# 20 s de mise en route du calage, comptées depuis le premier relevé commun de la remontée
			if not premier.has(n):
				premier[n] = k
			if k < int(premier[n]) + 40:
				continue
			var va: Array = da[n]
			var vb: Array = db[n]
			var err: float
			if n == "perce_neige":
				err = absf(float(va[1]) - float(vb[1]))
			elif va.size() == 4 and va[2] is String:
				if String(va[2]) != String(vb[2]):
					err = 99.0
				else:
					err = absf(float(va[1]) - float(vb[1]))
			else:
				if String(va[0]) != "marche" or String(vb[0]) != "marche" or float(va[3]) < 0.98 or float(vb[3]) < 0.98:
					continue
				var esp: float = float(va[2])
				err = absf(wrapf(float(va[1]) - float(vb[1]), -esp * 0.5, esp * 0.5))
			if not ecarts.has(n):
				ecarts[n] = []
			(ecarts[n] as Array).append(err)
	for n2 in ["perce_neige", "funival", "tph_grande_motte", "tsd6_bollin", "tsd6_fresse", "tsd6_grattalu"]:
		var l: Array = ecarts.get(n2, [])
		if l.size() < 10:
			ok = false
			lignes.append("%s : %d relevés communs (trop peu)" % [n2, l.size()])
			continue
		l.sort()
		var p95: float = l[int(l.size() * 0.95)]
		lignes.append("%s : %d relevés, écart médian %.2f m, p95 %.2f m" % [n2, l.size(), l[l.size() / 2], p95])
		if p95 > SEUIL:
			ok = false
	# arrêt d'urgence de A (hôte, pilote par défaut) vu par B dans les 4 s
	var ka: int = int((a.get("evts", {}) as Dictionary).get("urgence_A", -1))
	var vu_b: int = -1
	for e3 in lb:
		var db3: Dictionary = e3[1]
		if int(e3[0]) >= ka and db3.has("tsd6_grattalu") and String(db3["tsd6_grattalu"][0]) == "urgence":
			vu_b = int(e3[0])
			break
	var ok_u: bool = ka >= 0 and vu_b >= 0 and vu_b - ka <= 8
	lignes.append("urgence de A sur Grattalu vue par B : %s" % (("après %.1f s" % ((vu_b - ka) * 0.5)) if ok_u else "NON"))
	ok = ok and ok_u
	# arrêt du TPH demandé par B (il en prend la main) vu par A
	var kb: int = int((b.get("evts", {}) as Dictionary).get("arret_B", -1))
	var vu_a: int = -1
	for k4 in la:
		var da4: Dictionary = la[k4]
		if k4 >= kb and da4.has("tph_grande_motte") and String(da4["tph_grande_motte"][0]) in ["arret_normal", "arret"]:
			if vu_a < 0 or k4 < vu_a:
				vu_a = k4
	var pil: int = int((a.get("pilotes", {}) as Dictionary).get("tph_grande_motte", -1))
	var ok_p: bool = kb >= 0 and vu_a >= 0 and vu_a - kb <= 8 and pil == int(b.get("id", -2))
	lignes.append("arrêt du TPH par B vu par A : %s ; pilote du TPH chez A : %s" % [
		("après %.1f s" % ((vu_a - kb) * 0.5)) if vu_a >= 0 and kb >= 0 else "NON", "B" if pil == int(b.get("id", -2)) else str(pil)])
	ok = ok and ok_p
	return ok
