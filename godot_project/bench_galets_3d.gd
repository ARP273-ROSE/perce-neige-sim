# Banc des galets de ligne (05/10/2026) — demande d'un utilisateur : « leur bonne
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


# Point du tronçon libre à l'abscisse s (comme TrackBuilder._update_culots).
func _point_amorce(tun, pr: Dictionary, s: float) -> Vector3:
	var d: float = float(pr.s1) - float(pr.att)
	var x: float = clampf(s - float(pr.att), 0.0, d)
	var xs: Array = pr.x
	var i: int = clampi(xs.bsearch(x) - 1, 0, xs.size() - 2)
	var u: float = clampf((x - float(xs[i])) / maxf(float(xs[i + 1]) - float(xs[i]), 1e-9), 0.0, 1.0)
	var lat: float = lerpf(float(pr.lat[i]), float(pr.lat[i + 1]), u)
	var y: float = lerpf(float(pr.y[i]), float(pr.y[i + 1]), u)
	var bx: Basis = tun.transform_at(float(pr.att) + x).basis
	return (pr.p_att as Vector3).lerp(pr.p_r1, x / d) + bx.x * lat + bx.y * y


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
	var l_suiv: float = float(tr.galet_etat(_galet_apres(tr, -1, pose + 0.01)).s) - pose
	# appuis discrets : le galet R1 dévie un peu le câble, VERS LE BAS (il
	# le porte), comme n'importe quel galet de la ligne (L/a ≈ 0,55°)
	var k_r1: int = tr.premier_appui(-1, att, ch.x)
	var coude: float = rad_to_deg(tr.coude_appui(-1, att, tr.strand_point(-1, att), ch.x, k_r1))
	_check("chaînette en cosh : 12 cm au culot, 0 sur R1, coude vers le bas",
		absf(y0 - TrackBuilder.CULOT_DY) < 1e-5 and absf(y1) < 1e-5 and coude <= 0.0 and coude > -0.8,
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
	if nums.size() == 2:
		# la pente de la gare haute (10 %) est atteinte au n° 238, pas avant
		_check("pente de la gare haute atteinte au n° 238",
			absf(SlopeProfile.gradient_at(nums[1]) - 0.10) < 1e-4
			and SlopeProfile.gradient_at(nums[1] - 5.0) > 0.1005,
			"pente %.3f au n° 238, %.3f 5 m avant" % [SlopeProfile.gradient_at(nums[1]),
				SlopeProfile.gradient_at(nums[1] - 5.0)])
	_check("n° 1 après le quai aval, n° 238 avant le quai amont",
		nums.size() == 2 and nums[0] > PNConstants.QUAI_BAS_FIN_S and nums[0] < PNConstants.QUAI_BAS_FIN_S + 1.6
			and nums[1] < PNConstants.QUAI_HAUT_DEBUT_S and nums[1] > PNConstants.QUAI_HAUT_DEBUT_S - 1.6,
		"%s" % str(nums))
	# 5. Toute la ligne, montée et descente (le câble part toujours vers
	#    l'amont) : dans les virages et l'évitement, le tronçon libre reste
	#    dans la gorge des galets qu'il survole bas, n'en traverse aucun,
	#    et suit les galets de déviation de l'aiguillage
	var tun = _main.get("tunnel")
	var sts: Array = tr.station_list()
	var pire_lat: float = 0.0
	var h_min: float = INF
	var dev_ok: bool = true
	var coude_haut: float = -INF
	var s_coude_haut: float = 0.0
	var depasse: float = -INF
	for side_i in [-1, 1]:
		var s_r: float = 20.0
		while s_r < 3457.0:
			var prof: Dictionary = tr.amorce_profil(side_i, s_r, 300)
			var att3: float = prof.att
			var d3: float = float(prof.s1) - att3
			if float(prof.s1) < PNConstants.LENGTH - 1.0:
				var k3: int = tr.premier_appui(side_i, att3, float(prof.a))
				var c3: float = rad_to_deg(tr.coude_appui(side_i, att3, prof.p_att, float(prof.a), k3))
				if c3 > coude_haut:
					coude_haut = c3
					s_coude_haut = s_r
			var vs: Array = tr.strand_vertices(side_i)
			for j in range(1, vs.size() - 1):
				var xv: float = float(vs[j].s) - att3
				if xv <= 0.3 or xv >= d3 - 0.01:
					continue
				var bx: Basis = tun.transform_at(vs[j].s).basis
				var pp: Vector3 = _point_amorce(tun, prof, float(vs[j].s))
				var dp: Vector3 = pp - (vs[j].p as Vector3)
				var hy: float = dp.dot(bx.y)
				h_min = minf(h_min, hy)
				# entre les joues (repère du galet, incliné en courbe) et hors
				# de la poulie de déviation ; au décollage, le jeu croît en
				# √h : 0,3 mm de marge sur h
				var hors: float = tr.penetration_galet(side_i, j, dp, 0.0003)
				depasse = maxf(depasse, hors)
				if hy < TrackBuilder.Y_HORS_GORGE:
					pire_lat = maxf(pire_lat, absf(dp.dot(bx.x)))
				if sts[j - 1].sheave and hors > 0.001:
					dev_ok = false
			s_r += 2.0
	_check("virages et évitement : câble entre les joues des galets survolés", depasse < 0.001,
		"pénétration maxi dans une joue ou une poulie %+.1f mm ; écart au centre maxi %.1f mm sous les lèvres" \
		% [depasse * 1000.0, pire_lat * 1000.0])
	_check("aucun galet traversé par le tronçon libre", h_min > -0.002,
		"hauteur mini au-dessus d'un galet survolé %.1f mm" % (h_min * 1000.0))
	_check("galets de déviation suivis", dev_ok, "")
	# un galet porte, il ne retient pas : au premier appui, le câble plie
	# vers le bas (ou à peine : 0,05° au plus, cas limite d'un galet
	# intermédiaire qui dépasse de la chaînette)
	_check("décollage sans coude vers le haut (premier galet)", coude_haut < 0.02,
		"coude le plus « vers le haut » %+.3f° (rame à %.0f m)" % [coude_haut, s_coude_haut])
	# 5 bis. En marche, le tronçon libre se déforme sans saut : un même
	#    point du câble (même abscisse) avance d'une position de la rame à
	#    l'autre (0,5 m) d'un pas comparable à ses voisins. Un saut de J
	#    donne un pas de J entre deux pas ordinaires ; un câble qui touche
	#    une joue et change de direction (physique) n'en donne pas.
	var saut: float = 0.0
	var s_saut: float = 0.0
	for side_i in [-1, 1]:
		var hist: Array = []
		var s_r: float = 20.0
		while s_r < 3440.0:
			hist.append(tr.amorce_profil(side_i, s_r, 120))
			if hist.size() > 4:
				hist.pop_front()
			if hist.size() == 4:
				var lo: float = float(hist[3].att) + 0.5
				var hi: float = INF
				for h4 in hist:
					hi = minf(hi, float(h4.s1))
				for q in range(6):
					var s_q: float = lerpf(lo, hi, (float(q) + 0.5) / 6.0)
					var pq: Array = []
					for h4 in hist:
						pq.append(_point_amorce(tun, h4, s_q))
					var d1: float = (pq[1] - pq[0]).length()
					var d2: float = (pq[2] - pq[1]).length()
					var d3: float = (pq[3] - pq[2]).length()
					var j2: float = d2 - maxf(d1, d3)
					if j2 > saut:
						saut = j2
						s_saut = s_r - 1.0
			s_r += 0.5
	# reste : 2 à 4,5 mm au changement de R1 près des gares (chaînette
	# posée sur la corde, approchée), et jusqu'à 8,6 mm sur un galet très
	# incliné en courbe (−8°, 1 541,7 m) : soulevé de 1,6 mm, le câble
	# glisse de 13 mm dans la gorge vers l'intérieur de la courbe (jeu en
	# √h, physique) — invisible sur un câble de 52 mm
	_check("tronçon libre sans saut en marche (pas de 0,5 m)", saut < 0.010,
		"saut maxi d'un point du câble %.1f mm au-delà de son pas (rame à %.0f m)" % [saut * 1000.0, s_saut])
	# 6. En marche, dans les deux sens : le câble n'est jamais interrompu
	#    après le premier galet (segments de 15 m masqués à tort)
	var trous: int = 0
	var n_pos: int = 0
	for sens in [-1.0, 1.0]:
		var s6: float = 3400.0 if sens < 0.0 else 20.0
		while s6 > 15.0 and s6 < 3420.0:
			var so6: float = PNConstants.LENGTH - s6
			tr.update_cable_visibility(s6, so6)
			for side_i in [-1, 1]:
				var segs: Array = tr.cable_left_segments if side_i < 0 else tr.cable_right_segments
				var cut6: float = tr.coupe_brin(side_i, s6 if side_i < 0 else so6)
				for seg in segs:
					if float(seg.s_end) > cut6 + 0.01 and not seg.mesh.visible:
						trous += 1
						break
			n_pos += 1
			s6 += sens * 1.0
	_check("câble continu au premier galet, en montée et en descente", trous == 0,
		"%d positions sur %d avec un segment manquant" % [trous, n_pos])
	# 7. Tronçon libre et câble posé : même repère d'anneau (angle compté
	#    de la droite de la voie) — sinon l'hélice des torons s'inverse au
	#    raccord
	tr.update_cable_phase(1000.0, PNConstants.LENGTH - 1000.0)
	var am: MeshInstance3D = tr.get_node_or_null("CulotG_amorce")
	var sens_ok: bool = false
	if am != null:
		var arr: Array = (am.mesh as ImmediateMesh).surface_get_arrays(0)
		var vx: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		# sommet d'angle 0 (UV.x = 0) le plus proche du premier galet : sa
		# normale doit pointer vers la droite de la voie
		var best: int = -1
		for i in range(uvs.size()):
			if absf(uvs[i].x) < 1e-4 and (best < 0 or uvs[i].y > uvs[best].y):
				best = i
		if best >= 0:
			var s7: float = uvs[best].y * 0.5
			sens_ok = nrm[best].dot(tun.transform_at(s7).basis.x) > 0.9
	_check("torons du tronçon libre dans le sens du câble posé", sens_ok, "")
	print("BENCH_GALETS %s" % ("OK" if _ok else "ÉCHEC"))
	quit(0 if _ok else 1)
