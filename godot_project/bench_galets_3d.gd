# Banc des galets de ligne (05/10/2026) — demande de Kevin : « leur bonne
# vitesse de rotation en fonction de la vitesse du câble, et leur
# ralentissement progressif une fois que le câble est parti ; le câble
# s'accroche au milieu de la voiture amont de chaque rame ».
#   godot --headless --path godot_project -s bench_galets_3d.gd -- --mode=normal
extends SceneTree

const DT: float = 1.0 / 60.0

var _main: Node = null
var _f: int = 0
var _ok: bool = true


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _check(label: String, cond: bool, detail: String) -> void:
	print("%s %s — %s" % ["[OK]  " if cond else "[FAIL]", label, detail])
	_ok = _ok and cond


## Indice du premier galet du brin en amont de s (et le suivant).
func _galet_apres(tr: TrackBuilder, side_i: int, s: float) -> int:
	var best: int = -1
	var best_s: float = INF
	for q in range(tr.galets_count()):
		var e: Dictionary = tr.galet_etat(q)
		if int(e.side) == side_i and float(e.s) > s and float(e.s) < best_s:
			best = q
			best_s = e.s
	return best


func _tick() -> void:
	_f += 1
	if _f < 5:
		return
	var tr: TrackBuilder = _main.get("track")
	if tr == null:
		return
	process_frame.disconnect(_tick)
	tr.driver_is_rame2 = false
	var r: float = tr.pulley_radius

	# 1. Rame 1 monte à 10 m/s depuis s = 1000 : galets portés en amont du culot
	var s: float = 1000.0
	for i in range(240):
		s += 10.0 * DT
		tr.update_galets_rames(s, PNConstants.LENGTH - s, s, DT)
	var att: float = TrackBuilder.attache_s(s)
	_check("culot au milieu de la voiture amont", absf(att - s - PNConstants.CAR_LEN_M * 0.5) < 1e-3,
		"rame %.1f m → culot %.1f m" % [s, att])
	# chaînette : du culot, une seule portée jusqu'au premier galet touché
	var ch: Vector2 = tr.chainette(att)
	var pose: float = tr.coupe_brin(-1, s)
	var d_r1: float = pose - att
	_check("premier galet touché vers x0 (audit : 17 à 25 m)", d_r1 > 10.0 and d_r1 < 40.0,
		"a = %.0f m, x0 continu = %.1f m, galet R1 à %.1f m du culot" % [ch.x, ch.y, d_r1])
	var y0: float = TrackBuilder.chainette_y(0.0, d_r1, TrackBuilder.CULOT_DY, ch.x)
	var y1: float = TrackBuilder.chainette_y(d_r1, d_r1, TrackBuilder.CULOT_DY, ch.x)
	var pente_r1: float = (TrackBuilder.chainette_y(d_r1, d_r1, TrackBuilder.CULOT_DY, ch.x)
		- TrackBuilder.chainette_y(d_r1 - 0.01, d_r1, TrackBuilder.CULOT_DY, ch.x)) / 0.01
	# portée suivante (même niveau) : pente au départ −L/2a
	var l_suiv: float = float(tr.galet_etat(_galet_apres(tr, -1, pose + 0.01)).s) - pose
	var coude: float = rad_to_deg(absf(pente_r1 - (-l_suiv / (2.0 * ch.x))))
	# appuis discrets : le galet R1 dévie un peu le câble (0,2 à 0,6°, sur
	# un galet de 25 cm de rayon : invisible)
	_check("chaînette en cosh : 12 cm au culot, 0 sur R1, sans angle visible",
		absf(y0 - TrackBuilder.CULOT_DY) < 1e-5 and absf(y1) < 1e-5 and coude < 0.8,
		"y(0) = %.4f m, y(D) = %.5f m, coude sur R1 %.2f°" % [y0, y1, coude])
	var l_mi: float = l_suiv
	var fl: float = tr.fleche(-1, pose + l_mi * 0.5)
	var w_c: float = PNConstants.CABLE_KG_M * 9.80665
	_check("flèche des portées en cosh (≈ L²/8a, 1 à 2,5 cm)", fl > 0.008 and fl < 0.03
		and tr.fleche(-1, pose) < 1e-4,
		"portée %.1f m : flèche %.1f cm (galet : %.4f)" % [l_mi, fl * 100.0, tr.fleche(-1, pose)])
	var q_libre: int = _galet_apres(tr, -1, att)
	if q_libre >= 0 and float(tr.galet_etat(q_libre).s) < pose:
		_check("galet survolé par la chaînette : libre", not tr.galet_etat(q_libre).cable,
			"galet à %.1f m (décollage à %.1f m)" % [tr.galet_etat(q_libre).s, pose])
	var q_porte: int = _galet_apres(tr, -1, pose)
	var e1: Dictionary = tr.galet_etat(q_porte)
	_check("galet porteur à v / R", e1.cable and absf(absf(e1.w) - 10.0 / r) < 0.5,
		"s = %.1f, ω = %.1f rad/s (attendu %.1f)" % [e1.s, e1.w, 10.0 / r])
	# brin de la rame 2 (descend) : sens de rotation opposé
	var q2: int = _galet_apres(tr, 1, tr.coupe_brin(1, PNConstants.LENGTH - s))
	var e2: Dictionary = tr.galet_etat(q2)
	_check("brin de la rame descendante : sens opposé",
		e2.cable and signf(e2.w) == -signf(e1.w) and absf(absf(e2.w) - 10.0 / r) < 0.5,
		"ω = %.1f / %.1f rad/s" % [e1.w, e2.w])
	# sous la rame (en aval du culot) : pas de câble lest
	var q_sous: int = _galet_apres(tr, -1, s - 14.0)
	var e_sous: Dictionary = tr.galet_etat(q_sous)
	_check("pas de câble sous la rame", float(e_sous.s) > att or not e_sous.cable,
		"galet à %.1f m : câble %s" % [e_sous.s, e_sous.cable])

	# 2. La rame avance : quand le galet porteur n'est plus le premier
	# appui, le câble le survole — il est libéré et ralentit seul
	var garde: int = 0
	while tr.galet_etat(q_porte).cable and garde < 6000:
		s += 10.0 * DT
		tr.update_galets_rames(s, PNConstants.LENGTH - s, s, DT)
		garde += 1
	var w0: float = absf(tr.galet_etat(q_porte).w)
	_check("libéré au passage du décollage", not tr.galet_etat(q_porte).cable and w0 > 30.0,
		"ω juste après : %.1f rad/s" % w0)
	# la rame s'arrête ; on attend en restant près du galet (zone animée)
	var w_prec: float = w0
	var monotone: bool = true
	var t: float = 0.0
	var w_t: Dictionary = {}
	while t < 130.0:
		tr.update_galets_rames(s, PNConstants.LENGTH - s, s, DT)
		t += DT
		var w: float = absf(tr.galet_etat(q_porte).w)
		monotone = monotone and w <= w_prec + 1e-4
		w_prec = w
		for tt in [5.0, 30.0, 60.0]:
			if not w_t.has(tt) and t >= tt:
				w_t[tt] = w
	var attendu_30: float = TrackBuilder.galet_w_libre(w0, 30.0)
	_check("ralentissement progressif (décroissant)", monotone,
		"5 s : %.1f, 30 s : %.1f, 60 s : %.1f rad/s" % [w_t[5.0], w_t[30.0], w_t[60.0]])
	_check("loi de l'audit (I ω' = −M_c − c ω)", absf(w_t[30.0] - attendu_30) < 0.3,
		"30 s : %.2f (attendu %.2f)" % [w_t[30.0], attendu_30])
	_check("arrêté au bout de ~2 min", absf(tr.galet_etat(q_porte).w) < 1e-3,
		"ω à 130 s : %.4f" % tr.galet_etat(q_porte).w)
	# le galet en amont, encore sous le câble, est arrêté avec la rame
	var q_suiv: int = _galet_apres(tr, -1, tr.coupe_brin(-1, s))
	_check("rame arrêtée : galets porteurs immobiles", absf(tr.galet_etat(q_suiv).w) < 0.05,
		"ω = %.3f" % tr.galet_etat(q_suiv).w)

	# 3. Culot : au-dessus des joues, sous la caisse, sur le brin
	tr.update_cable_phase(s, PNConstants.LENGTH - s)
	var culot: MeshInstance3D = tr.get_node_or_null("CulotG_culot")
	var y_cable: float = tr._roller_axis_y() + tr.pulley_radius + tr.cable_radius
	if culot != null:
		var xf: Transform3D = _main.get("tunnel").transform_at(TrackBuilder.attache_s(s))
		var rel: Vector3 = culot.position - xf.origin
		var y: float = rel.dot(xf.basis.y)
		var bas: float = y - 0.065
		var haut_joues: float = tr._roller_axis_y() + RollerMesh.R_JOUE
		_check("culot au-dessus des joues des galets", bas > haut_joues,
			"bas du culot %.3f, haut des joues %.3f" % [bas, haut_joues])
		_check("culot sous la caisse", y + 0.065 < TrackBuilder.CAISSE_Y,
			"haut %.3f, caisse %.3f" % [y + 0.065, TrackBuilder.CAISSE_Y])
		_check("culot sur le brin de sa rame", absf(rel.dot(xf.basis.x) - tr.strand_local_at(-1, TrackBuilder.attache_s(s)).x) < 0.01,
			"x = %.3f" % rel.dot(xf.basis.x))
	else:
		_check("culot construit", false, "absent")
	_check("joues au-dessus du câble posé", tr._roller_axis_y() + RollerMesh.R_JOUE > y_cable + tr.cable_radius,
		"joues %.3f, dessus du câble %.3f" % [tr._roller_axis_y() + RollerMesh.R_JOUE, y_cable + tr.cable_radius])
	# 4. Supports entre deux traverses (plots en (i + ½) × espacement) :
	#    les joues (± R_JOUE) et la fourche ne touchent aucun plot
	var esp: float = tr.sleeper_spacing
	var marge_min: float = INF
	var s_pire: float = 0.0
	for st in tr.station_list():
		var u: float = float(st.s) / esp
		var d_plot: float = absf(u - (floor(u) + 0.5)) * esp   # distance au plot le plus proche
		var marge: float = d_plot - tr.sleeper_width * 0.5 - RollerMesh.R_JOUE
		if marge < marge_min:
			marge_min = marge
			s_pire = st.s
	_check("supports entre deux traverses", marge_min > 0.1,
		"jeu mini joue / plot %.2f m (s = %.1f)" % [marge_min, s_pire])
	var nums: Array = []
	for st in tr.station_list():
		if int(st.get("num", 0)) in [1, 238]:
			nums.append(float(st.s))
	_check("n° 1 après le quai aval, n° 238 avant le quai amont",
		nums.size() == 2 and nums[0] > 51.0 and nums[1] < 3425.0,
		"%s" % str(nums))
	print("BENCH_GALETS %s" % ("OK" if _ok else "ÉCHEC"))
	quit(0 if _ok else 1)
