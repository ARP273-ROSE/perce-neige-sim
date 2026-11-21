## Banc du mode réseau, commandes des remontées et perche partagée (retours d'utilisateur du 21/11/2026 : « mon frère a
## demandé un arrêt que je n'ai pas eu, et du coup on est désynchronisés sur la télécabine de la Daille » ; au téléski
## du Montet, sur la même perche, l'autre était dessiné 6 m devant au lieu d'à côté). Relais local et deux jeux sans
## écran (reseau_banc_joueur.gd), A avec le module C++ (hôte), B en GDScript seul comme la PWA :
##   - arret_a : A vient de toucher au poste de la Daille (la main lui reste) ; B l'arrête : A la voit s'arrêter dans
##     les 2 s, elle reste arrêtée chez les deux ; B la redémarre : les deux roulent, cabines à moins de 0,5 m les unes
##     des autres, dans les 10 s ;
##   - arret_b : A est loin (Daille pas construite chez lui) quand B l'arrête ; A y arrive plus d'une minute après : il
##     la trouve arrêtée, et B ne la voit pas repartir ;
##   - perche : A et B prennent ensemble la même perche du Montet (biplace) : chacun voit l'autre à l'autre place de
##     sa perche, à moins de 0,5 m (p95).
extends SceneTree

const SEUIL_PERCHE_M: float = 0.5
const SEUIL_PHASE_M: float = 0.5

var _port: int = 0
var _dos: String = ""
var _pids: Array = []
var _t0: int = 0
var _etape: int = 0
var _url: String = ""
var _scen: Array = ["perche", "arret_a", "arret_b"]
var _k: int = 0
var _lignes: Array = []
var _ok: bool = true


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenarios="):
			_scen = Array(a.trim_prefix("--scenarios=").split(","))
	_port = 19900 + (Time.get_ticks_usec() % 300)
	var racine: String = ProjectSettings.globalize_path("res://")
	var relais: String = racine.path_join("../reseau/relais/relais.py").simplify_path()
	_url = "ws://127.0.0.1:%d" % _port
	_pids.append(OS.create_process("python3", [relais, "--hote", "127.0.0.1", "--port", str(_port)]))
	print("RESEAU relais pid %d port %d" % [_pids[0], _port])
	_preparer()
	process_frame.connect(_tick)


func _preparer() -> void:
	_dos = "/tmp/reseau_cmd_%d_%s" % [_port, _scen[_k]]
	DirAccess.make_dir_recursive_absolute(_dos)
	for f in ["code.txt", "depart.txt", "A.json", "B.json"]:
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
	print(("BANC OK " if _ok else "BANC ECHEC ") + "commandes en réseau : " + " ; ".join(_lignes))
	quit(0 if _ok else 1)


func _tick() -> void:
	var t: float = float(Time.get_ticks_msec() - _t0) / 1000.0
	if t > 1000.0:
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
			match String(_scen[_k]):
				"perche":
					_comparer_perche(a, b)
				"arret_a":
					_comparer_arret_a(a, b)
				"arret_b":
					_comparer_arret_b(a, b)
			_k += 1
			if _k >= _scen.size():
				_fin()
			else:
				_preparer()


static func _p95(v: Array) -> float:
	if v.is_empty():
		return INF
	var w: Array = v.duplicate()
	w.sort()
	return float(w[mini(w.size() - 1, int(floor(0.95 * w.size())))])


func _comparer_perche(a: Dictionary, b: Dictionary) -> void:
	var ok: bool = bool(a["ok"]) and bool(b["ok"])
	var txt: Array = []
	for r in [[a, "A voit B"], [b, "B voit A"]]:
		var d: Dictionary = r[0]
		var ec: Array = []
		var lat: Array = []
		var lon: Array = []
		var meme: int = 0
		for e in d["perche"]:
			ec.append(float(e[1]))
			lat.append(absf(float(e[2])))
			lon.append(absf(float(e[3])))
			if bool(e[4]):
				meme += 1
		var p_ec: float = _p95(ec)
		var lat_m: float = 0.0
		for x in lat:
			lat_m += float(x) / maxf(lat.size(), 1)
		var ok_r: bool = not ec.is_empty() and p_ec <= SEUIL_PERCHE_M and lat_m > 0.5 and meme == ec.size()
		ok = ok and ok_r
		txt.append("%s : %d relevés, écart à sa place p95 %.2f m, en travers %.2f m (moyenne), en long p95 %.2f m, même perche %d/%d%s"
			% [r[1], ec.size(), p_ec, lat_m, _p95(lon), meme, ec.size(), "" if ok_r else " — FAUX"])
	_lignes.append("perche : " + " ; ".join(txt))
	_ok = _ok and ok


static func _par_cle(d: Dictionary) -> Dictionary:
	var o: Dictionary = {}
	for e in d["lignes"]:
		o[int(e[0])] = e
	return o


func _comparer_arret_a(a: Dictionary, b: Dictionary) -> void:
	var ea: Dictionary = _par_cle(a)
	var eb: Dictionary = _par_cle(b)
	var t_arret: float = float(b["evts"].get("arret_B", -1.0))
	var t_dep: float = float(b["evts"].get("depart_B", -1.0))
	var ok: bool = bool(a["ok"]) and bool(b["ok"]) and t_arret > 0.0 and t_dep > t_arret
	# A voit l'arrêt
	var vu: float = INF
	var ka: Array = ea.keys()
	ka.sort()
	for k in ka:
		if k * 0.5 >= t_arret - 0.25 and String(ea[k][1]) != "marche":
			vu = k * 0.5 - t_arret
			break
	# arrêtée chez les deux de 3 s après l'arrêt jusqu'au départ
	var repart: Array = []
	for k2 in ka:
		var t2: float = k2 * 0.5
		if t2 > t_arret + 3.0 and t2 < t_dep - 0.5:
			if String(ea[k2][1]) == "marche":
				repart.append("A %.1f s" % (t2 - t_arret))
			if eb.has(k2) and String(eb[k2][1]) == "marche":
				repart.append("B %.1f s" % (t2 - t_arret))
	# après le départ : les deux en marche, cabines calées
	var cale: float = INF
	var ecarts: Array = []
	var fin_k: int = ka.back() if not ka.is_empty() else 0
	for k3 in ka:
		if k3 * 0.5 < t_dep or not eb.has(k3):
			continue
		var x: Array = ea[k3]
		var y: Array = eb[k3]
		var ec: float = INF
		if String(x[1]) == "marche" and String(y[1]) == "marche" and float(x[2]) >= 0.0 and float(y[2]) >= 0.0:
			ec = absf(wrapf(float(x[2]) - float(y[2]), -float(x[3]) * 0.5, float(x[3]) * 0.5))
		ecarts.append([k3, ec])
	for i in range(ecarts.size()):
		var tous: bool = true
		for j in range(i, ecarts.size()):
			if float(ecarts[j][1]) > SEUIL_PHASE_M:
				tous = false
				break
		if tous:
			cale = int(ecarts[i][0]) * 0.5 - t_dep
			break
	var ec_fin: float = float(ecarts.back()[1]) if not ecarts.is_empty() else INF
	var ok_vu: bool = vu <= 2.0
	var ok_rep: bool = repart.is_empty()
	var ok_cale: bool = cale <= 10.0
	ok = ok and ok_vu and ok_rep and ok_cale
	_lignes.append("arret_a : arrêt de B vu par A après %s ; repartie pendant l'arrêt : %s ; après le départ, cabines calées à %.1f m près au bout de %s (écart final %.2f m)%s"
		% ["%.1f s" % vu if vu < INF else "JAMAIS", "non" if ok_rep else ", ".join(repart.slice(0, 4)), SEUIL_PHASE_M,
		"%.1f s" % cale if cale < INF else "JAMAIS", ec_fin, "" if ok else " — FAUX"])
	_ok = _ok and ok
	print("RESEAU fin de relevé A %d s après le départ" % int(fin_k * 0.5 - t_dep))


func _comparer_arret_b(a: Dictionary, b: Dictionary) -> void:
	var t_arret: float = float(b["evts"].get("arret_B", -1.0))
	var t_a: float = float(a["evts"].get("daille_A", -1.0))
	var ok: bool = bool(a["ok"]) and bool(b["ok"]) and t_arret > 0.0 and t_a > 0.0
	var a_marche: int = 0
	var a_n: int = 0
	for e in a["lignes"]:
		if int(e[0]) * 0.5 >= t_a and bool(e[5]):
			a_n += 1
			if String(e[1]) == "marche":
				a_marche += 1
	var b_marche: Array = []
	for e2 in b["lignes"]:
		if int(e2[0]) * 0.5 > t_arret + 3.0 and String(e2[1]) == "marche":
			b_marche.append(int(e2[0]) * 0.5 - t_arret)
	var ok2: bool = ok and a_n > 0 and a_marche == 0 and b_marche.is_empty()
	_lignes.append("arret_b : A arrive %.0f s après l'arrêt ; Daille chez A : %d relevés, %d en marche ; chez B repartie : %s%s"
		% [t_a - t_arret, a_n, a_marche, "non" if b_marche.is_empty() else "OUI dès %.0f s" % float(b_marche[0]),
		"" if ok2 else " — FAUX"])
	_ok = _ok and ok2
