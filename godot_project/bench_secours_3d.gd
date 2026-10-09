## Banc de la sortie de secours (07/10/2026) : la rame arrêtée en tunnel à la
## chambre du galet 145, portes ouvertes (mode Défi) ; le skieur descend sur
## la passerelle, passe l'ouverture, suit la galerie jusqu'au portail sur
## la piste, chausse et skie jusqu'à Val Claret.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_secours_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _sag_prec: float = 1e9
var _phase: int = 0
var _t: float = 0.0
var _ok: bool = true
var _chute_min: float = INF


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_SECOURS " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


## Porte de la voiture 2 (panneau 5) : position monde.
func _porte(k: int) -> Array:
	var cab: Cabin = _main.cabin
	var v: Node3D = cab._interior_cars[1]
	var car_len: float = cab.train_length / float(cab.car_count)
	var z_c: float = (1.0 - (cab.car_count - 1) * 0.5) * car_len
	var zc: float = cab._panel_center(1, k) - z_c
	var y: float = TrainBodyBuilder.Y_FLOOR + 0.3
	return [v, y, zc]


func _tick() -> void:
	_f += 1
	var dt: float = 1.0 / 60.0
	_t += dt
	var relief: ReliefBuilder = _main.get("relief")
	if relief == null or not relief.pret:
		if _f > 20000:
			_verif("relief prêt", false)
			_fin()
		return
	var ph: TrainPhysics = _main.physics
	var ss: SortieSecours = _main.sortie_secours
	match _phase:
		0:
			_verif("galerie construite, portail sur le relief",
				ss != null and ss.pret and ss.sol.size() >= 4
					and absf(ss.portail.y - relief.hauteur(ss.portail.x, ss.portail.z)) < 0.01,
				"%d points, portail y %.1f" % [ss.sol.size() if ss else 0, ss.portail.y if ss else 0.0])
			# la galerie reste sous le relief affiché (remblai compris), sauf
			# les 2,5 derniers mètres, dans le mur de tête
			var pire: float = INF
			var i_pire: int = -1
			var u_port: float = Vector2(ss.portail.x - ss.sol[0].x, ss.portail.z - ss.sol[0].z).length()
			for i in range(1, ss.sol.size()):
				var q: Vector3 = ss.sol[i]
				if Vector2(q.x - ss.sol[0].x, q.z - ss.sol[0].z).length() > u_port - 5.0:
					break
				var cv: float = relief.hauteur_sol(q.x, q.z) - (q.y + SortieSecours.H_AXE + SortieSecours.R_GAL)
				if cv < pire:
					pire = cv
					i_pire = i
			_verif("galerie sous le relief affiché (couverture du tube ≥ 0,8 m, hors les 5 derniers m)", pire >= 0.8,
				"mini %.2f m au point %d/%d" % [pire, i_pire, ss.sol.size()])
			# rame arrêtée à la chambre, porte 5 face à l'ouverture, portes ouvertes
			_main._apply_scenario(false, false, "challenge")
			if _main.auto_operator != null and _main.auto_operator.enabled:
				_main.auto_operator.toggle()
			ph.s = TunnelBuilder.SORTIE_SECOURS_S
			ph.s_prev_step = ph.s
			ph.s_render = ph.s
			ph.v = 0.0
			ph.trip_started = false
			_phase = 1
			_t = 0.0
		1:
			if _t < 0.5:
				return
			# recale s : la porte du panneau 4 au droit de la chambre
			var r: Array = _porte(4)
			var porte: Vector3 = (r[0] as Node3D).global_transform * Vector3(2.4, r[1], r[2])
			var xf: Transform3D = _main.tunnel.transform_at(TunnelBuilder.SORTIE_SECOURS_S)
			var ecart: float = (porte - xf.origin).dot(-xf.basis.z)
			# l'affaissement d'embarquement (la charge posée par le scénario)
			# fait descendre la rame de ~3 cm/s : on attend qu'elle soit posée
			var sag: float = ph.boarding_sag_offset()
			var sag_bouge: bool = absf(sag - _sag_prec) > 1e-4
			_sag_prec = sag
			if (absf(ecart) > 0.05 or sag_bouge) and _t < 90.0:
				ph.s -= ecart
				ph.s_prev_step = ph.s
				ph.s_render = ph.s
				return
			ph.doors_open = true
			ph.door_leaves_open = true
			ph.portes_cotes = 3
			_main.basculer_skieur()
			if _main.auto_operator != null and _main.auto_operator.enabled:
				_main.auto_operator.toggle()
			_phase = 2
			_t = 0.0
		2:
			if _t < 6.0:
				return                 # les vantaux s'ouvrent (clip de 4 s)
			var sk: SkieurJoueur = _main.skieur
			var r2: Array = _porte(4)
			var v: Node3D = r2[0]
			sk.global_position = v.global_transform * Vector3(0.0, r2[1], r2[2])
			sk.velocity = Vector3.ZERO
			sk.support = v
			sk._support_xf = v.global_transform
			var xf2: Transform3D = _main.tunnel.transform_at(TunnelBuilder.SORTIE_SECOURS_S)
			# par la porte, le bout du palier (il descend sur la passerelle),
			# retour le long de la passerelle, puis l'ouverture
			# par la porte, il descend sur la passerelle (pas de palier de quai
			# en tunnel), puis l'ouverture
			# dans le repère de la VOITURE jusqu'à la porte (en courbe, elle est
			# en biais par rapport au repère du tunnel), puis l'ouverture
			# tout dans le repère de la voiture jusque dans la galerie : la
			# passerelle (0,33 m sous le plancher, x 1,02) puis le seuil de
			# l'ouverture (0,45 m sous le plancher, x 1,75)
			sk.chemin = [v.global_transform * Vector3(0.9, r2[1], r2[2]),
				v.global_transform * Vector3(1.05, TrainBodyBuilder.Y_FLOOR - 0.33 + 0.2, r2[2]),
				v.global_transform * Vector3(1.75, TrainBodyBuilder.Y_FLOOR - 0.45 + 0.2, r2[2])]
			sk.chemin.append_array(ss.chemin_sortie())
			_phase = 3
			_t = 0.0
		3:
			var sk3: SkieurJoueur = _main.skieur
			if _f % 60 == 0 and _t < 0.0:
				var xfc: Transform3D = _main.tunnel.transform_at(TunnelBuilder.SORTIE_SECOURS_S)
				var lc: Vector3 = xfc.affine_inverse() * sk3.global_position
				var noms: String = ""
				for ci in range(sk3.get_slide_collision_count()):
					var kc: KinematicCollision3D = sk3.get_slide_collision(ci)
					var oc: Object = kc.get_collider()
					var own: Object = (oc as CollisionObject3D).shape_owner_get_owner(
						(oc as CollisionObject3D).shape_find_owner(kc.get_collider_shape_index()))
					var chemin_c: String = str((oc as Node).get_path())
					var forme: String = ""
					if own is CollisionShape3D and (own as CollisionShape3D).shape is BoxShape3D:
						var plc: Vector3 = xfc.affine_inverse() * (own as CollisionShape3D).global_position
						forme = " boîte %s à (%.2f, %.2f, %.2f)" % [((own as CollisionShape3D).shape as BoxShape3D).size, plc.x, plc.y, plc.z]
					noms += " %s|%s%s(n %.2f,%.2f,%.2f)" % [chemin_c.get_slice("/", chemin_c.get_slice_count("/") - 2) + "/" + (oc as Node).name,
						(own as Node).name if own else "?", forme,
						kc.get_normal().dot(xfc.basis.x), kc.get_normal().y, kc.get_normal().dot(xfc.basis.z)]
				print("  t %.0f local (%.2f, %.2f, %.2f) reste %d %s |%s" % [_t, lc.x, lc.y, lc.z, sk3.chemin.size(), sk3.debug_marche, noms])
			var ecart_sol: float = sk3.global_position.y - relief.hauteur(sk3.global_position.x, sk3.global_position.z)
			if sk3.chemin.size() <= 1:
				_chute_min = minf(_chute_min, ecart_sol)
			if sk3.chemin.is_empty() or _t > 150.0 or sk3.global_position.y < ss.portail.y - 20.0:
				var dp: float = Vector2(sk3.global_position.x - ss.portail.x, sk3.global_position.z - ss.portail.z).length()
				var okm: bool = sk3.chemin.is_empty() and dp < 12.0 and sk3.is_on_floor() and sk3.dehors(relief)
				var loc: Vector3 = _main.tunnel.transform_at(TunnelBuilder.SORTIE_SECOURS_S).affine_inverse() * sk3.global_position
				_verif("de la voiture à la piste : passerelle, ouverture, galerie, portail", okm,
					"%.0f s, %.1f m du portail, au sol %s, dehors %s, reste %d points, %s ; local (%.2f, %.2f, %.2f) cible %s" % [
						_t, dp, sk3.is_on_floor(), sk3.dehors(relief), sk3.chemin.size(), sk3.debug_marche,
						loc.x, loc.y, loc.z, str(sk3.chemin[0]) if not sk3.chemin.is_empty() else "-"])
				if not okm:
					_fin()
					return
				_main.basculer_ski()
				_verif("chaussé sur la piste au portail", sk3.chausse, "")
				# descente : la trace n° 1 passe à côté ; de son point le plus proche à Val Claret
				var pts: PackedVector2Array = FantomesDonnees.points(0)
				var q: Vector2 = Vector2(sk3.global_position.x, sk3.global_position.z)
				var i0: int = 0
				var best: float = INF
				for i in range(pts.size()):
					var d: float = pts[i].distance_to(q)
					if d < best:
						best = d
						i0 = i
				sk3.chemin.clear()
				var i: int = i0 + 3
				while i < pts.size():
					sk3.chemin.append(Vector3(pts[i].x, 0.0, pts[i].y))
					i += 3
				sk3.chemin.append(Vector3(pts[pts.size() - 1].x, 0.0, pts[pts.size() - 1].y))
				sk3.vitesse_pilote = 11.0
				sk3._cap_ski = atan2(-(pts[i0 + 3].x - q.x), -(pts[i0 + 3].y - q.y))
				print("  trace 1 : point %d à %.0f m du portail" % [i0, best])
				_phase = 4
				_t = 0.0
		4:
			var sk4: SkieurJoueur = _main.skieur
			var p: Vector3 = sk4.global_position
			if (sk4.chemin.is_empty() and Vector2(p.x, p.z).length() < DomaineSkiable.R_ARRIVEE) or _t > 900.0:
				_verif("du portail à Val Claret à ski", Vector2(p.x, p.z).length() < DomaineSkiable.R_ARRIVEE,
					"%s, %.0f m de la gare" % [DomaineSkiable._mmss(_t), Vector2(p.x, p.z).length()])
				_fin()
