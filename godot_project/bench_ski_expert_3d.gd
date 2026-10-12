## Banc du skieur EXPERT de la BOUCLE (retour d'utilisateur, 12/10/2026 : « il chausse
## très tard… chasse-neige à 40 km/h alors qu'il peut carver comme Odermatt
## à 100 km/h… il ne suit pas la piste, toujours dans le décor… il s'arrête
## 400 m avant la gare et marche à 2 km/h »). Parti en BOUCLE au départ de
## la trace (sous la gare du glacier), on mesure la descente jusqu'à la gare
## de Val Claret.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_ski_expert_3d.gd -- --mode=normal
## --mesure : affiche sans juger.
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _t: float = 0.0
var _lance: bool = false
var _ok: bool = true
var _mesure: bool = false
var _v_max: float = 0.0
var _v_sum: float = 0.0
var _n: int = 0
var _n_hors: int = 0
var _n_chasse: int = 0
var _ecart_max: float = 0.0
var _ecart_sum: float = 0.0
var _t_ski: float = -1.0
var _t_gare: float = -1.0
var _d_fin: float = -1.0
var _trace: PackedVector2Array


func _initialize() -> void:
	_mesure = "--mesure" in OS.get_cmdline_user_args()
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String) -> void:
	if _mesure:
		print("[MESURE] %s — %s" % [label, detail])
		return
	print("%s %s — %s" % ["[OK]  " if cond else "[ECHEC]", label, detail])
	_ok = _ok and cond


func _ecart(q: Vector2) -> float:
	var best: float = INF
	for i in range(_trace.size() - 1):
		var a: Vector2 = _trace[i]
		var b: Vector2 = _trace[i + 1]
		var ab: Vector2 = b - a
		var u: float = clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * u))
	return best


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	var sk: SkieurJoueur = _main.skieur
	if sk == null or not sk.actif or _main.get("domaine") == null:
		return
	if not _lance:
		_lance = true
		_trace = FantomesDonnees.points(SkieurAuto.DESCENTE)
		var p0: Vector2 = _trace[0]
		sk.activer(Vector3(p0.x, relief.hauteur_sol(p0.x, p0.y) + 0.1, p0.y), 0.0)
		_main.basculer_skieur_auto()
		_t = 0.0
		return
	_t += 1.0 / 60.0
	var sa: SkieurAuto = _main.skieur_auto
	if sa == null:
		_verif("BOUCLE active", false, "")
		_fin()
		return
	if sa.etape == SkieurAuto.Etape.SKI and sk.chausse:
		if _t_ski < 0.0:
			_t_ski = _t
		var v: float = sk.vitesse_ski()
		_v_max = maxf(_v_max, v)
		_v_sum += v
		_n += 1
		var q: Vector2 = Vector2(sk.global_position.x, sk.global_position.z)
		if _main.domaine.hors_piste(sk.global_position):
			_n_hors += 1

		if sk._posture == 2:
			_n_chasse += 1
	if sa.etape == SkieurAuto.Etape.VERS_GARE and _d_fin < 0.0:
		var dep: Vector3 = _main.station_halls.gare_aval.point_depart()[0]
		_d_fin = Vector2(sk.global_position.x - dep.x, sk.global_position.z - dep.z).length()
		_t_gare = _t
	if (sa.boucles >= 1) or _t > 1500.0:
		_fin()


func _fin() -> void:
	var n: int = maxi(_n, 1)
	var v_moy: float = _v_sum / n
	_verif("descente à ski, vitesse maxi ≥ 80 km/h (carve, pas de chasse-neige à 40 km/h)",
		_v_max * 3.6 >= 80.0, "maxi %.0f km/h, moyenne %.0f km/h" % [_v_max * 3.6, v_moy * 3.6])
	_verif("jamais en chasse-neige", _n_chasse == 0, "%.1f %% du temps" % (100.0 * _n_chasse / n))
	_verif("sur la piste (≥ 85 % du temps)", float(_n_hors) / n <= 0.15,
		"hors piste %.0f %% du temps" % (100.0 * _n_hors / n))
	_verif("déchaussé au pied de la gare (≤ 60 m)", _d_fin >= 0.0 and _d_fin <= 60.0, "à %.0f m de la gare" % _d_fin)
	_verif("boucle bouclée", _main.skieur_auto != null and _main.skieur_auto.boucles >= 1,
		"descente %s, gare %s" % [DomaineSkiable._mmss(_t_gare - _t_ski) if _t_gare > 0 else "-", DomaineSkiable._mmss(_t)])
	print("BENCH_SKI_EXPERT " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)
