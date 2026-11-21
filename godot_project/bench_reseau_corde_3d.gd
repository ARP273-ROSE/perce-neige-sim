## Banc du mode réseau, descente à la corde chacun son tour (retour d'utilisateur du 21/11/2026) : relais local et deux
## jeux sans écran (reseau_banc_joueur.gd, scénarios « corde » puis « coupe »), A avec le module C++ (hôte), B en
## GDScript seul comme la PWA. Tous deux à bord du même siège de Grattalu arrêté en urgence, ils demandent la corde :
##   - corde : A puis B, jamais les deux à la fois ; B dessine la corde de A à ±0,3 m (p95) de sa vraie position ;
##   - coupe : A se déconnecte en pleine descente ; B part dans les 8 s.
extends SceneTree

const SEUIL_M: float = 0.3

var _port: int = 0
var _dos: String = ""
var _pids: Array = []
var _t0: int = 0
var _etape: int = 0
var _url: String = ""
var _scen: Array = ["corde", "coupe"]
var _k: int = 0
var _lignes: Array = []
var _ok: bool = true


func _initialize() -> void:
	_port = 19600 + (Time.get_ticks_usec() % 300)
	var racine: String = ProjectSettings.globalize_path("res://")
	var relais: String = racine.path_join("../reseau/relais/relais.py").simplify_path()
	_url = "ws://127.0.0.1:%d" % _port
	_pids.append(OS.create_process("python3", [relais, "--hote", "127.0.0.1", "--port", str(_port)]))
	print("RESEAU relais pid %d port %d" % [_pids[0], _port])
	_preparer()
	process_frame.connect(_tick)


func _preparer() -> void:
	_dos = "/tmp/reseau_corde_%d_%s" % [_port, _scen[_k]]
	DirAccess.make_dir_recursive_absolute(_dos)
	for f in ["code.txt", "cible.txt", "b_assis.txt", "A.json", "B.json"]:
		DirAccess.remove_absolute(_dos.path_join(f))
	_t0 = Time.get_ticks_msec()
	_etape = 0


func _lancer(role: String, extra: Array) -> void:
	var a: Array = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "reseau_banc_joueur.gd",
		"--", "--role=" + role, "--url=" + _url, "--sortie=" + _dos, "--scenario=" + String(_scen[_k])]
	a.append_array(extra)
	var pid: int = OS.create_process(OS.get_executable_path(), a)
	_pids.append(pid)
	print("RESEAU joueur %s (%s) pid %d" % [role, _scen[_k], pid])


func _lire(nom: String) -> Variant:
	var p: String = _dos.path_join(nom)
	if not FileAccess.file_exists(p):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(p))


func _fin() -> void:
	for pid in _pids:
		if pid > 0:
			OS.kill(pid)
	for l in _lignes:
		print("RESEAU " + l)
	print(("BANC OK " if _ok else "BANC ECHEC ") + "corde en réseau : " + " ; ".join(_lignes))
	quit(0 if _ok else 1)


func _tick() -> void:
	var t: float = float(Time.get_ticks_msec() - _t0) / 1000.0
	if t > 900.0:
		_lignes.append("%s : délai dépassé (étape %d)" % [_scen[_k], _etape])
		_ok = false
		_fin()
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
			if String(_scen[_k]) == "corde":
				_comparer_corde(a, b)
			else:
				_comparer_coupe(a, b)
			_k += 1
			if _k >= _scen.size():
				_fin()
			else:
				_preparer()


static func _debut(tr: Array, ph: String) -> float:
	for e in tr:
		if String(e[1]) == ph:
			return float(e[0])
	return -1.0


func _comparer_corde(a: Dictionary, b: Dictionary) -> void:
	var da: float = _debut(a["ph"], "descente")
	var sa: float = _debut(a["ph"], "sol")
	var db: float = _debut(b["ph"], "descente")
	var sb: float = _debut(b["ph"], "sol")
	var att_b: float = _debut(b["ph"], "attente")
	var ok_ordre: bool = bool(a["ok"]) and bool(b["ok"]) and da > 0.0 and sa > da and db > 0.0 and sb > db \
		and db >= sa - 0.2 and att_b > 0.0 and att_b < sa
	_lignes.append("corde : A descend %.1f → %.1f s, B attend dès %.1f, descend %.1f → %.1f s (temps commun relatif) — %s"
		% [0.0, sa - da, att_b - da, db - da, sb - da, "chacun son tour" if ok_ordre else "ORDRE FAUX"])
	_ok = _ok and ok_ordre
	# corde de A vue par B
	var vrai: Array = a["vrai"]
	var err: Array = []
	for v in b["vu"]:
		var tv: float = float(v[0])
		for k in range(vrai.size() - 1):
			var t1: float = float(vrai[k][0])
			var t2: float = float(vrai[k + 1][0])
			if tv >= t1 and tv <= t2 and t2 > t1:
				var f: float = (tv - t1) / (t2 - t1)
				var pv: Vector3 = Vector3(vrai[k][1], vrai[k][2], vrai[k][3]).lerp(
					Vector3(vrai[k + 1][1], vrai[k + 1][2], vrai[k + 1][3]), f)
				err.append(pv.distance_to(Vector3(v[1], v[2], v[3])))
				break
	if err.size() < 30:
		_lignes.append("corde : corde de A vue par B — %d mesures (trop peu)" % err.size())
		_ok = false
		return
	err.sort()
	var p95: float = err[int(err.size() * 0.95)]
	_lignes.append("corde : corde de A vue par B — %d mesures, médiane %.3f m, p95 %.3f m, max %.3f m"
		% [err.size(), err[err.size() / 2], p95, err[err.size() - 1]])
	_ok = _ok and p95 <= SEUIL_M


func _comparer_coupe(a: Dictionary, b: Dictionary) -> void:
	var q: float = float(a.get("quitte", -1.0))
	var db: float = _debut(b["ph"], "descente")
	var sb: float = _debut(b["ph"], "sol")
	var ok_c: bool = q > 0.0 and db > 0.0 and db - q <= 8.0 and db >= q - 0.2 and sb > db and bool(b["ok"])
	_lignes.append("coupe : A part en pleine descente, B descend %.1f s après, au sol %s — %s"
		% [db - q, "oui" if sb > 0.0 else "NON", "file reprise" if ok_c else "ÉCHEC"])
	_ok = _ok and ok_c
