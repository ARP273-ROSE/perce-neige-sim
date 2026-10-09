## Banc des issues de secours de la face (07/10/2026) : rame arrêtée en
## tunnel, le skieur à bord enlève les D jaunes (ÉVACUER), passe par le trou,
## descend sur la voie et suit l'escalier de service vers l'amont ; à quai,
## pas d'évacuation, et les issues sont remises. 08/10/2026 : à pied sur la
## voie, l'exploitation AUTO enclenchée ne fait PAS repartir la rame (voie
## occupée) ; tombé dans la fosse entre les rails, il se hisse sur la dalle.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_issues_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _phase: int = 0
var _t: float = 0.0
var _ok: bool = true
var _cible: Vector3 = Vector3.ZERO
var _retenue_vue: bool = false
var _ecoute_vue: bool = false
var _t_trace: float = 0.0
var _auto_lance: bool = false
var _immobile: bool = true
var _s_evac: float = 0.0
var _s_av: float = 0.0
var _sens: float = 1.0
var _s_fosse: float = 0.0
var _t_repos: float = -1.0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_ISSUES " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


func _tick() -> void:
	_f += 1
	_t += 1.0 / 60.0
	var relief: ReliefBuilder = _main.get("relief")
	if relief == null or not relief.pret:
		if _f > 20000:
			_verif("relief prêt", false)
			_fin()
		return
	var ph: TrainPhysics = _main.physics
	var cab: Cabin = _main.cabin
	var tun: TunnelBuilder = _main.tunnel
	var track: TrackBuilder = _main.track
	match _phase:
		0:
			_main._apply_scenario(false, false, "normal")
			if _main.auto_operator != null and _main.auto_operator.enabled:
				_main.auto_operator.toggle()
			ph.s = 1500.0
			ph.s_prev_step = ph.s
			ph.s_render = ph.s
			ph.v = 0.0
			ph.trip_started = false
			_main.basculer_skieur()
			_phase = 1
			_t = 0.0
		1:
			if _t < 8.0:
				return
			# (l'entrée en skieur relance l'exploitation automatique quand la
			# rame est en ligne : ici elle doit rester arrêtée en tunnel)
			if _main.auto_operator != null and _main.auto_operator.enabled:
				_main.auto_operator.toggle()
			var sk: SkieurJoueur = _main.skieur
			var v0: Node3D = cab._interior_cars[0]
			var car_len: float = cab.train_length / float(cab.car_count)
			# au milieu de la voiture 1 (palier 5, le 2e à porte) : il devra
			# slalomer entre les porte-skis jusqu'au poste (retour d'utilisateur, 07/10/2026 :
			# « bloqué par les derniers porte-skis, je ne peux pas accéder à
			# l'avant »)
			var zc5: float = cab._panel_center(0, 5) - (0.0 - 0.5) * car_len
			sk.global_position = v0.global_transform * Vector3(0.0, TrainBodyBuilder.Y_FLOOR + 0.3, zc5)
			sk.velocity = Vector3.ZERO
			sk.support = v0
			_phase = 2
			_t = 0.0
		2:
			if _t < 1.0:
				return
			var sk: SkieurJoueur = _main.skieur
			var v0: Node3D = cab._interior_cars[0]
			var car_len: float = cab.train_length / float(cab.car_count)
			var zf: float = -car_len * 0.5
			_verif("rame arrêtée en tunnel, skieur à bord : ÉVACUER possible", _main.evacuation_possible(),
				"support %s, v %.2f, s %.0f" % [sk.support != null, ph.v, ph.s])
			_main.evacuer()
			var caches: int = 0
			for e in cab._issues:
				# surfaces de la caisse masquées (plus d'objet à part, 09/10/2026)
				var masque: bool = not (e["node"] as Node3D).visible and not (e["surfaces"] as Array).is_empty()
				for si in e["surfaces"]:
					if (e["caisse"] as MeshInstance3D).get_surface_override_material(int(si)) == null:
						masque = false
				if masque:
					caches += 1
			var desact: int = 0
			for cs in _main.collisions.issues.get(cab, []):
				if (cs as CollisionShape3D).disabled:
					desact += 1
			_verif("les 4 D jaunes sont enlevés : maillages cachés, collisions désactivées",
				cab.issues_retirees and cab._issues.size() == 4 and caches == 4 and desact == 4,
				"%d panneaux, %d cachés, %d collisions désactivées" % [cab._issues.size(), caches, desact])
			# chemin : le slalom des porte-skis (couloir à droite aux paliers
			# pairs, à gauche aux impairs ; le porte-skis est dans la moitié
			# arrière du palier), le poste, le D droit, le trou (fond de
			# calotte à zf + 0,45), la voie, puis l'escalier de service vers
			# l'avant de la rame
			var y: float = TrainBodyBuilder.Y_FLOOR + 0.3
			var pf: Vector3 = v0.global_transform * Vector3(0.0, y, zf)
			var s_av: float = ph.s
			var d_min: float = INF
			var s: float = ph.s - 40.0
			while s <= ph.s + 40.0:
				var d: float = tun.transform_at(s).origin.distance_to(pf)
				if d < d_min:
					d_min = d
					s_av = s
				s += 0.5
			var fwd: Vector3 = -v0.global_transform.basis.z
			var sens: float = 1.0 if fwd.dot(-tun.transform_at(s_av).basis.z) > 0.0 else -1.0
			# par l'issue droite (D de 0,98 à 1,62 m de l'axe), puis au-delà de
			# la calotte, sur la voie
			sk.chemin = []
			for q in [[-0.55, 1.4], [-0.55, 0.9], [0.55, 0.9], [0.55, 0.6], [0.55, -0.3], [0.55, -0.5], [-0.55, -0.5], [-0.55, -0.9],
					[-0.55, -1.9], [0.55, -1.9], [0.55, -2.3], [0.55, -3.3], [-0.55, -3.3], [-0.55, -4.5], [-0.55, -5.0], [1.0, -5.8]]:
				sk.chemin.append(v0.global_transform * Vector3(q[0], y, q[1]))
			sk.chemin.append_array([v0.global_transform * Vector3(1.15, y, zf + 1.4), v0.global_transform * Vector3(1.15, y, zf - 0.3)])
			for ds in [3.0, 8.0, 16.0, 26.0]:
				sk.chemin.append(track.point_passerelle(s_av + sens * ds))
			_cible = sk.chemin[sk.chemin.size() - 1]
			_s_evac = ph.s
			_s_av = s_av
			_sens = sens
			print("  avant de la rame à s %.1f, sens %+.0f ; zones de collision %d, triangles %d" % [s_av, sens, _main.collisions._zones.size(), _main.collisions.triangles])
			_phase = 3
			_t = 0.0
			_t_trace = 0.0
		3:
			var sk: SkieurJoueur = _main.skieur
			_t_trace += 1.0 / 60.0
			if _t_trace >= 2.0 and _t > 40.0:      # trace des 20 dernières secondes, en cas d'échec
				_t_trace = 0.0
				var v0t: Node3D = cab._interior_cars[0]
				var l: Vector3 = v0t.global_transform.affine_inverse() * sk.global_position
				var mur: String = "-"
				if sk.get_slide_collision_count() > 0 and sk.get_last_slide_collision().get_collider():
					mur = str(sk.get_last_slide_collision().get_collider().name) + "/" + str(sk.get_last_slide_collision().get_collider_shape().name if sk.get_last_slide_collision().get_collider_shape() else "")
				print("  t %3.0f : reste %d, voiture (%.2f, %.2f, %.2f), sol %s, support %s, contact %s" % [_t, sk.chemin.size(), l.x, l.y, l.z, sk.is_on_floor(), sk.support != null, mur])
			if sk.support == null:
				_retenue_vue = _retenue_vue or (_main.auto_operator != null and _main.auto_operator.retenue)
				_ecoute_vue = _ecoute_vue or _main.audio.ecoute == 4
				# à pied sur la voie : on enclenche l'exploitation AUTO — elle
				# ne doit PAS faire repartir la rame (retour d'utilisateur, 08/10/2026 : « il
				# est reparti, je me suis pris l'autre rame en pleine tête »)
				if not _auto_lance and _main.auto_operator != null and _t > 1.0:
					_auto_lance = true
					if not _main.auto_operator.enabled:
						_main.auto_operator.toggle()
			if _auto_lance:
				_immobile = _immobile and absf(ph.v) < 0.01 and absf(ph.s - _s_evac) < 0.5
			if sk.chemin.is_empty() or _t > 90.0:
				var d: Vector3 = sk.global_position - _cible
				var dh: float = Vector2(d.x, d.z).length()
				var mur: String = "-"
				if sk.get_slide_collision_count() > 0 and sk.get_last_slide_collision().get_collider():
					mur = str(sk.get_last_slide_collision().get_collider().name)
				_verif("slalom des porte-skis jusqu'au poste, par le trou, sur la voie, 26 m d'escalier de service vers l'avant",
					sk.chemin.is_empty() and dh < 1.0 and absf(d.y) < 0.6 and sk.is_on_floor() and sk.support == null,
					"%.0f s, reste %d points, %.2f m du but (dy %.2f), au sol %s, support %s, dernier contact %s" % [
						_t, sk.chemin.size(), dh, d.y, sk.is_on_floor(), sk.support != null, mur])
				_verif("à pied dans le tunnel : la rame est retenue, on entend le tunnel (écoute 4)",
					_retenue_vue and _ecoute_vue, "retenue %s, écoute 4 %s" % [_retenue_vue, _ecoute_vue])
				_verif("exploitation AUTO enclenchée pendant qu'il est sur la voie : la rame reste immobilisée (voie occupée, départ refusé)",
					_auto_lance and _immobile and ph.voie_occupee and not ph.trip_started and absf(ph.v) < 0.01,
					"auto %s, immobile %s, voie occupée %s, voyage %s, v %.2f, s %.1f → %.1f" % [
						_auto_lance, _immobile, ph.voie_occupee, ph.trip_started, ph.v, _s_evac, ph.s])
				if _main.auto_operator != null and _main.auto_operator.enabled:
					_main.auto_operator.toggle()
				_phase = 10
				_t = 0.0
		10:
			# tombé dans la fosse centrale entre les rails (70 cm sous la
			# dalle, plots de 89 cm) : il doit pouvoir se hisser sur la dalle
			# et rejoindre l'escalier (retour d'utilisateur, 08/10/2026 : « coincé entre les
			# deux rails, faudrait pouvoir remonter sur l'escalier à côté »)
			var sk: SkieurJoueur = _main.skieur
			# 10 m devant la rame (pas dessous : son plancher interdit de se
			# hisser), entre deux blochets (ils sont à (i + ½) × 1,51 m), à
			# 30 cm à gauche du câble, 12 cm au-dessus du fond
			var s_f: float = snappedf(_s_av + _sens * 10.0, track.sleeper_spacing)
			_s_fosse = s_f
			var e: Array = track._trench_edges(s_f, false, 0.0)
			var xt: Transform3D = tun.transform_at(s_f)
			var xc: float = (float(e[0]) + float(e[1])) * 0.5 - 0.30
			var yf: float = track.floor_y_local + track.slab_thickness - track.trench_depth + 0.12
			sk.global_position = xt.origin + xt.basis.x * xc + xt.basis.y * yf
			sk.velocity = Vector3.ZERO
			sk.support = null
			sk.chemin = [track.point_passerelle(s_f + _sens * 3.0)]
			_cible = sk.chemin[0]
			print("  dans la fosse à s %.1f : x %.2f, y %.2f (local) ; but à %.2f m" % [s_f, xc, yf, Vector2(sk.global_position.x - _cible.x, sk.global_position.z - _cible.z).length()])
			_phase = 11
			_t = 0.0
		11:
			var sk: SkieurJoueur = _main.skieur
			if _t < 1.5:
				return
			_t_trace += 1.0 / 60.0
			if _t_trace >= 2.0:
				_t_trace = 0.0
				var xt: Transform3D = tun.transform_at(_s_fosse)
				var l: Vector3 = xt.affine_inverse() * sk.global_position
				var mur: String = "-"
				if sk.get_slide_collision_count() > 0 and sk.get_last_slide_collision().get_collider():
					mur = str(sk.get_last_slide_collision().get_collider().name)
				print("  fosse t %3.0f : local x %.2f y %.2f ds %.1f, sol %s, marche %s, contact %s, reste %d" % [_t, l.x, l.y, -l.z, sk.is_on_floor(), sk.debug_marche, mur, sk.chemin.size()])
			if sk.chemin.is_empty() and _t_repos < 0.0:
				_t_repos = _t
			if (_t_repos >= 0.0 and _t - _t_repos > 0.5) or _t > 30.0:
				var d: Vector3 = sk.global_position - _cible
				var dh: float = Vector2(d.x, d.z).length()
				_verif("tombé dans la fosse entre les rails : il se hisse sur la dalle et rejoint l'escalier de service",
					sk.chemin.is_empty() and dh < 1.0 and absf(d.y) < 0.6 and sk.is_on_floor(),
					"%.0f s, %.2f m du but (dy %.2f), au sol %s, marche : %s" % [_t, dh, d.y, sk.is_on_floor(), sk.debug_marche])
				# retour à bord, rame à quai en bas : pas d'évacuation, issues remises
				var v0: Node3D = cab._interior_cars[0]
				var car_len: float = cab.train_length / float(cab.car_count)
				ph.s = PNConstants.START_S
				ph.s_prev_step = ph.s
				ph.s_render = ph.s
				ph.v = 0.0
				ph.doors_open = true
				sk.global_position = v0.global_transform * Vector3(0.0, TrainBodyBuilder.Y_FLOOR + 0.3, -car_len * 0.5 + 3.0)
				sk.velocity = Vector3.ZERO
				sk.support = v0
				sk.chemin.clear()
				_phase = 4
				_t = 0.0
		4:
			if _t < 1.0:
				return
			_verif("à quai, portes ouvertes : pas d'évacuation possible, issues remises",
				not _main.evacuation_possible() and not cab.issues_retirees
					and (cab._issues[0]["node"] as Node3D).visible
					and (cab._issues[0]["caisse"] as MeshInstance3D).get_surface_override_material(int(cab._issues[0]["surfaces"][0])) == null,
				"possible %s, retirées %s" % [_main.evacuation_possible(), cab.issues_retirees])
			# CONDUIRE au poste, la rame roule 1 km, retour en skieur : il se
			# relève DANS la voiture de tête (retour d'utilisateur, 08/10/2026 : « le skieur
			# est tout seul au milieu du tunnel »)
			var sk4: SkieurJoueur = _main.skieur
			sk4.global_position = _main._position_poste()
			sk4.support = cab._interior_cars[0]
			sk4._support_xf = sk4.support.global_transform
			_main._skieur_conduit()
			ph.s = 1800.0
			ph.s_prev_step = ph.s
			ph.s_render = ph.s
			ph.v = 0.0
			ph.trip_started = false
			_phase = 5
			_t = 0.0
		5:
			if _t < 1.0:
				return
			_main.basculer_skieur()
			_phase = 6
			_t = 0.0
		6:
			if _t < 2.0:
				return
			var sk6: SkieurJoueur = _main.skieur
			var d6: float = sk6.global_position.distance_to(_main._position_poste())
			_verif("CONDUIRE puis retour en skieur 1 km plus loin : relevé du siège, dans la voiture de tête",
				_main.mode_skieur and sk6.support == cab._interior_cars[0] and d6 < 1.5 and sk6.is_on_floor(),
				"skieur %s, support %s, %.1f m du poste, au sol %s" % [_main.mode_skieur,
					sk6.support.name if sk6.support else "aucun", d6, sk6.is_on_floor()])
			_fin()
