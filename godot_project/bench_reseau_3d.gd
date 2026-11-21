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
	for l2 in lignes:
		print("RESEAU " + l2)
	_fin(ok, "mode réseau : " + " ; ".join(lignes))
