## Banc du skieur jouable (07/10/2026) : collisions, escaliers, portes
## automatiques, embarquement, transport par la rame, sorties du haut.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_skieur_3d.gd -- --mode=normal
## 1. En bas : posé sur la place, il monte l'escalier, passe la porte
##    automatique de l'entrée et rejoint la cloison (salle d'attente).
## 2. Par la porte de la cloison, le palier et le quai en escalier, il monte
##    dans la voiture ; la rame part : il est emporté, toujours dedans.
## 3. En haut (rame posée à quai) : de la voiture au quai, au palier, à la
##    baie automatique du mur de tête, jusque sur la terrasse.
## 4. Par la porte de la piste Génépy (bas du quai gauche) : le couloir, la
##    porte automatique, la neige remontée au seuil.
## 5. AUTO : la rame attend le skieur resté sur le quai, part peu après
##    qu'il est monté ; ce qu'on entend (gare / cabine) suit le skieur.
## 6. Fosse de la gare basse : la tête passe sous les rails, et l'escalier
##    du bout ramène au niveau du quai.
## 7. Vue skieur quittée puis reprise en marche : il est toujours dans sa
##    voiture ; départ d'en haut : à table sur la terrasse.
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _phase: int = 0
var _t_phase: float = 0.0
var _ok: bool = true
var _ouv_max: float = 0.0
var _t_depart: float = -1.0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_SKIEUR " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


func _ga() -> GareAval:
	return _main.station_halls.gare_aval


func _dans_voiture(sk: SkieurJoueur, v: Node3D, car_len: float) -> bool:
	var l: Vector3 = v.global_transform.affine_inverse() * sk.global_position
	return absf(l.x) < 1.6 and absf(l.z) < car_len * 0.5 and l.y > TrainBodyBuilder.Y_FLOOR - 0.3


func _poser_dans_voiture(sk: SkieurJoueur, k: int) -> Array:
	var cab: Cabin = _main.cabin
	var v: Node3D = cab._interior_cars[1]
	var car_len: float = cab.train_length / float(cab.car_count)
	var z_c: float = (1.0 - (cab.car_count - 1) * 0.5) * car_len
	var zc: float = cab._panel_center(1, k) - z_c - 0.35
	var y: float = TrainBodyBuilder.Y_FLOOR + 0.3
	sk.global_position = v.global_transform * Vector3(0.0, y, zc)
	sk.velocity = Vector3.ZERO
	sk.support = null
	return [v, y, zc]


func _tick() -> void:
	_f += 1
	var relief: ReliefBuilder = _main.get("relief")
	if relief == null or not relief.pret:
		if _f > 4000:
			_verif("relief prêt", false)
			_fin()
		return
	var ph: TrainPhysics = _main.physics
	var tun: TunnelBuilder = _main.tunnel
	var cab: Cabin = _main.cabin
	var car_len: float = cab.train_length / float(cab.car_count)
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		var sk0: SkieurJoueur = _main.skieur
		_verif("vue skieur active, collisions construites", _main.mode_skieur and _main.collisions != null
			and _main.collisions.pret, "%d triangles" % _main.collisions.triangles)
		# rame à quai, portes ouvertes, sans automate : on part quand on veut
		if _main.auto_operator.enabled:
			_main.auto_operator.toggle()
		var ga: GareAval = _ga()
		var t: Vector2 = (GareAval.FACADE_B - GareAval.FACADE_A).normalized()
		var de: Vector2 = Vector2(-t.y, t.x)
		if Geometry2D.is_point_in_polygon((GareAval.FACADE_A + GareAval.FACADE_B) * 0.5 + de, PackedVector2Array(GareAval.HALL)):
			de = -de
		var mil: Vector2 = (GareAval.FACADE_A + GareAval.FACADE_B) * 0.5 + t * GareAval.ARCHE_DECALAGE
		var mil0: Vector2 = (GareAval.FACADE_A + GareAval.FACADE_B) * 0.5
		sk0.chemin = [ga._p2(mil + de * 16.0 + t * 1.4), ga._p2(mil + de * 9.0 + t * 1.4),
			ga._p2(mil0 + de * 2.0), ga._p2(mil0 - de * 2.5), ga._p2(Vector2(-3.55, 6.0)), ga._p2(Vector2(-3.55, 2.0))]
		_phase = 1
		_t_phase = 0.0
		return
	var sk: SkieurJoueur = _main.skieur
	var dt: float = 1.0 / 60.0
	_t_phase += dt
	match _phase:
		1:
			var pe: PorteAuto = _ga().get_node_or_null("PorteEntree")
			_ouv_max = maxf(_ouv_max, pe.ouverture())
			if sk.chemin.is_empty() or _t_phase > 60.0:
				var y_sol: float = _ga()._o.y
				_verif("en bas : escalier monté, porte d'entrée ouverte, salle atteinte",
					sk.chemin.is_empty() and _ouv_max > 0.9 and absf(sk.global_position.y - y_sol) < 0.3,
					"%.0f s, porte %.2f, %.2f m au-dessus du sol de la salle" % [_t_phase, _ouv_max, sk.global_position.y - y_sol])
				# portes de la salle ouvertes (embarquement), vers la voiture
				ph.doors_open = true
				ph.trip_started = false
				var v: Node3D = cab._interior_cars[1]
				var z_c: float = (1.0 - (cab.car_count - 1) * 0.5) * car_len
				var zc: float = cab._panel_center(1, 7) - z_c
				var xf: Transform3D = v.global_transform
				var y: float = TrainBodyBuilder.Y_FLOOR + 0.3
				sk.chemin = [_ga()._p2(Vector2(-3.55, -1.6)), xf * Vector3(2.6, y, zc + 3.0), xf * Vector3(2.4, y, zc),
					xf * Vector3(0.9, y, zc), xf * Vector3(0.3, y, zc)]
				_phase = 2
				_t_phase = 0.0
		2:
			if sk.support != null and sk.chemin.is_empty() or _t_phase > 40.0:
				_verif("embarquement : cloison, palier, quai en escalier, seuil, à bord", sk.support != null,
					"%.1f s, support %s" % [_t_phase, sk.support.name if sk.support else "aucun"])
				ph.request_depart()
				_phase = 3
				_t_phase = 0.0
		3:
			ph.speed_cmd = 1.0                 # le conducteur pousse la consigne
			if _t_depart < 0.0 and ph.trip_started:
				_t_depart = _t_phase
			if _t_depart > 0.0 and _t_phase - _t_depart > 40.0:
				var v3: Node3D = cab._interior_cars[1]
				_verif("en marche : emporté par la rame, toujours dans la voiture",
					sk.support == v3 and _dans_voiture(sk, v3, car_len) and ph.s > PNConstants.START_S + 80.0,
					"rame à %.0f m, support %s" % [ph.s, sk.support.name if sk.support else "aucun"])
				_main.basculer_skieur()           # on quitte la vue skieur en marche…
				_phase = 31
				_t_phase = 0.0
		31:
			ph.speed_cmd = 1.0
			if _t_phase > 4.0:
				_main.basculer_skieur()       # … et on y revient 4 s plus loin
				_phase = 32
				_t_phase = 0.0
		32:
			ph.speed_cmd = 1.0
			if _t_phase > 1.5:
				var v32: Node3D = cab._interior_cars[1]
				_verif("vue skieur quittée puis reprise en marche : toujours à sa place dans la voiture",
					sk.support == v32 and _dans_voiture(sk, v32, car_len) and sk.is_on_floor(),
					"rame à %.0f m, support %s" % [ph.s, sk.support.name if sk.support else "aucun"])
				if _main.auto_operator.enabled:
					_main.auto_operator.toggle()    # (rallumé en reprenant la vue skieur)
				# rame posée en haut, portes ouvertes
				_main._apply_scenario(true, false, "normal")
				ph.v = 0.0
				ph.trip_started = false
				ph.doors_open = true
				ph.door_leaves_open = true
				_phase = 4
				_t_phase = 0.0
		4:
			if _t_phase > 1.0:
				var r: Array = _poser_dans_voiture(sk, 5)
				var v4: Node3D = r[0]
				var porte: Vector3 = v4.global_transform * Vector3(2.4, r[1], r[2])
				var x0: Transform3D = tun.transform_at(PNConstants.LENGTH)
				var cote: float = signf((porte - x0.origin).dot(x0.basis.x))
				sk.chemin = [v4.global_transform * Vector3(0.9, r[1], r[2]), porte]
				for s_ in [PNConstants.LENGTH - 10.0, PNConstants.LENGTH + 2.0, PNConstants.LENGTH + MachineRoomBuilder.HALL_DEPTH - 1.0]:
					var xs: Transform3D = tun.transform_at(minf(s_, PNConstants.LENGTH))
					sk.chemin.append(xs.origin + xs.basis.x * (3.0 * cote) - xs.basis.z * (s_ - minf(s_, PNConstants.LENGTH)))
				for dd in [MachineRoomBuilder.HALL_DEPTH + 2.0, MachineRoomBuilder.HALL_DEPTH + 6.0]:
					sk.chemin.append(x0.origin + x0.basis.x * (3.0 * cote) - x0.basis.z * dd)
				_ouv_max = 0.0
				_phase = 5
				_t_phase = 0.0
		5:
			for p in _main.machine_room.get_children():
				if p is PorteAuto:
					_ouv_max = maxf(_ouv_max, (p as PorteAuto).ouverture())
			if sk.chemin.is_empty() or _t_phase > 50.0:
				var ga2: GareAmont = _main.station_halls.gare_amont
				var rel: Vector3 = sk.global_position - ga2._o
				_verif("en haut : quai, palier, baie automatique, terrasse",
					sk.chemin.is_empty() and _ouv_max > 0.9 and rel.dot(ga2._d) > 1.0 and absf(rel.y) < 0.4,
					"%.0f s, baie %.2f, %.1f m sur la terrasse" % [_t_phase, _ouv_max, rel.dot(ga2._d)])
				var r2: Array = _poser_dans_voiture(sk, 5)
				var v5: Node3D = r2[0]
				var sc: float = (StationsBuilder.PORTE_GENEPY.x + StationsBuilder.PORTE_GENEPY.y) * 0.5
				var xg: Transform3D = tun.transform_at(sc)
				sk.chemin = [v5.global_transform * Vector3(0.9, r2[1], r2[2]), v5.global_transform * Vector3(2.4, r2[1], r2[2])]
				for la in [-3.0, -4.4, -6.0, -7.8, -12.0]:
					sk.chemin.append(xg.origin + xg.basis.x * la)
				_ouv_max = 0.0
				_phase = 6
				_t_phase = 0.0
		6:
			var pg: PorteAuto = _main.station_halls.gare_amont.porte_genepy
			_ouv_max = maxf(_ouv_max, pg.ouverture())
			if sk.chemin.is_empty() or _t_phase > 50.0:
				var xg2: Transform3D = tun.transform_at(StationsBuilder.PORTE_GENEPY.x)
				var lat: float = (sk.global_position - xg2.origin).dot(xg2.basis.x)
				_verif("porte Génépy : couloir, porte automatique, neige au seuil",
					sk.chemin.is_empty() and _ouv_max > 0.9 and lat < -9.0 and sk.is_on_floor() and sk.dehors(relief),
					"%.0f s, porte %.2f, %.1f m de la voie, dehors %s" % [_t_phase, _ouv_max, lat, sk.dehors(relief)])
				# automate : skieur sur le quai, rame à quai portes ouvertes
				var xq: Transform3D = tun.transform_at(PNConstants.LENGTH - 8.0)
				sk.global_position = xq.origin + xq.basis.x * -3.2 + Vector3(0.0, -0.9, 0.0)
				sk.velocity = Vector3.ZERO
				sk.chemin.clear()
				if _main.auto_operator.enabled:
					_main.auto_operator.toggle()
				_main.auto_operator.toggle()          # automate neuf : rame à quai, portes ouvertes
				_phase = 7
				_t_phase = 0.0
		7:
			if _t_phase > 40.0:
				_verif("AUTO : la rame attend le skieur resté sur le quai ; on entend la gare, pas la cabine",
					not ph.trip_started and ph.doors_open and _main.audio.ecoute == 1,
					"voyage %s, portes %s, écoute %d" % [ph.trip_started, ph.doors_open, _main.audio.ecoute])
				_poser_dans_voiture(sk, 5)
				_phase = 8
				_t_phase = 0.0
		8:
			if ph.trip_started or _t_phase > 60.0:
				_verif("AUTO : départ peu après la montée du skieur ; sons de cabine à bord",
					ph.trip_started and _t_phase < 45.0 and _main.audio.ecoute == 0,
					"départ %.0f s après la montée, écoute %d" % [_t_phase, _main.audio.ecoute])
				_main.auto_operator.toggle()
				ph.speed_cmd = 1.0
				_phase = 85
				_t_phase = 0.0
		85:
			# l'autre rame quitte la gare basse : la fosse se vide
			ph.speed_cmd = 1.0
			if PNConstants.MIROIR_S - ph.s > 70.0 or _t_phase > 60.0:
				var xp: Transform3D = tun.transform_at(20.0)
				sk.global_position = xp.origin + xp.basis.y * -3.0
				sk.velocity = Vector3.ZERO
				sk.support = null
				_phase = 9
				_t_phase = 0.0
		9:
			if _t_phase > 2.0 and sk.chemin.is_empty() and _phase == 9:
				var xp2: Transform3D = tun.transform_at(20.0)
				var tete: float = (sk.global_position - xp2.origin).dot(xp2.basis.y) + SkieurJoueur.TAILLE
				_verif("fosse : la tête passe sous les rails", sk.is_on_floor()
					and tete < StationsBuilder.RAIL_HEAD_Y, "tête à %.2f m, rails à %.2f m (repère de la voie)"
					% [tete, StationsBuilder.RAIL_HEAD_Y])
				var chem: Array = []
				for e in [[6.0, 0.0], [5.6, 1.22], [4.6, 1.43], [0.75, 1.43], [0.75, 2.6]]:
					var x6: Transform3D = tun.transform_at(e[0])
					chem.append(x6.origin + x6.basis.x * e[1])
				sk.chemin = chem
				_phase = 10
				_t_phase = 0.0
		10:
			if sk.chemin.is_empty() or _t_phase > 40.0:
				var x7: Transform3D = tun.transform_at(0.75)
				var h7: float = (sk.global_position - x7.origin).dot(x7.basis.y)
				_verif("fosse : l'escalier remonte au niveau du quai", sk.chemin.is_empty()
					and absf(h7 - (StationsBuilder.FLOOR_Y_LOCAL + 0.5)) < 0.15,
					"%.0f s, pieds à %.2f m (quai à %.2f)" % [_t_phase, h7, StationsBuilder.FLOOR_Y_LOCAL + 0.5])
				# départ d'en haut : à table sur la terrasse
				_main.basculer_skieur()
				_main._skieur_place = false
				_main._depart_haut = true
				_main.basculer_skieur()
				_phase = 11
				_t_phase = 0.0
		11:
			if _t_phase > 1.5:
				var ga3: GareAmont = _main.station_halls.gare_amont
				var table: Vector3 = ga3._p(GareAmont.TABLE_SKIEUR.x, GareAmont.TABLE_SKIEUR.y + 0.55, 0.0)
				var dh: Vector3 = sk.global_position - table
				_verif("départ d'en haut : à table sur la terrasse, devant les frites",
					Vector2(dh.x, dh.z).length() < 1.6 and absf(dh.y) < 0.2 and sk.is_on_floor(),
					"%.2f m de l'assiette, %.2f m sous le plancher" % [Vector2(dh.x, dh.z).length(), -dh.y])
				_fin()
