## Banc de la BOUCLE partie de la salle d'attente du bas (retour d'utilisateur, 11/10/2026 :
## « dans la salle d'attente du bas, il ressort devant la gare et rerentre ;
## il marche même si la porte du quai est fermée, au lieu de s'asseoir sur
## un banc ; il ne court pas s'il est en retard ; il n'arrive pas à monter »).
## La rame est en ligne : il doit rester dans la salle, s'asseoir, puis
## courir à la rame quand le quai s'ouvre et monter à bord, sans déblocage.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_boucle_salle_3d.gd -- --mode=normal
## Variante --pistes : parti des pistes, chaussé, il descend à ski.
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t: float = 0.0
var _ok: bool = true
var _lance: bool = false
var _etape_prec: int = -1
var _sorti: bool = false
var _assis: bool = false
var _couru: bool = false
var _t_assis: float = -1.0
var _pistes: bool = false
var _attend_depart: bool = false
var _levers: int = 0
var _d_banc: float = -1.0
var _etait_assis: bool = false


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)
	_pistes = "--pistes" in OS.get_cmdline_user_args()


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_BOUCLE_SALLE " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


func _tick() -> void:
	_f += 1
	var relief: ReliefBuilder = _main.get("relief")
	if relief == null or not relief.pret:
		if _f > 20000:
			_verif("relief prêt", false)
			_fin()
		return
	_t += 1.0 / 60.0
	var ga: GareAval = _main.station_halls.gare_aval
	var sk: SkieurJoueur = _main.skieur
	if _attend_depart:
		if not _main.physics.trip_started or _main.physics.s < 60.0:
			return
		_attend_depart = false
		sk.activer(ga._p2(Vector2(-7.5, 9.0), 0.1), 0.0)
		_main.basculer_skieur_auto()
		_verif("BOUCLE lancée (rame en ligne)", _main.skieur_auto != null)
		_t = 0.0
		return
	if not _lance:
		_lance = true
		_main.basculer_skieur()
		sk = _main.skieur
		if _pistes:
			# sur une piste, à mi-descente de la trace, chaussé
			var pts: PackedVector2Array = FantomesDonnees.points(SkieurAuto.DESCENTE)
			var q: Vector2 = pts[pts.size() / 2] + Vector2(12.0, 0.0)
			sk.activer(Vector3(q.x, relief.hauteur_sol(q.x, q.y) + 0.1, q.y), 0.0)
			_main.basculer_ski()
			_verif("chaussé sur la piste", sk.chausse)
		else:
			# la rame part (exploitation auto) : il entre en salle quand
			# elle est en ligne — personne à quai en bas
			if not _main.auto_operator.enabled:
				_main.auto_operator.toggle()
			_attend_depart = true
			return
		_main.basculer_skieur_auto()
		_verif("BOUCLE lancée", _main.skieur_auto != null)
		_t = 0.0
		return
	var sa: SkieurAuto = _main.skieur_auto
	if sa == null:
		_verif("BOUCLE toujours active", false)
		_fin()
		return
	if sa.etape != _etape_prec:
		_etape_prec = sa.etape
		print("  %s : étape %d" % [DomaineSkiable._mmss(_t), sa.etape])
	if _pistes:
		if sa.etape == SkieurAuto.Etape.SKI and not sk.chausse:
			_verif("garde ses skis sur la piste", false)
			_fin()
			return
		if sa.etape == SkieurAuto.Etape.VERS_GARE or _t > 1200.0:
			_verif("descendu à ski jusqu'à Val Claret", sa.etape == SkieurAuto.Etape.VERS_GARE, DomaineSkiable._mmss(_t))
			_verif("aucun déblocage", sa.debloquages == 0, "%d" % sa.debloquages)
			_fin()
		return
	var q: Vector2 = sa._local_aval(sk.global_position)
	if _f % 60 == 0 and false:
		print("    %.0f s : (%.1f ; %.1f ; h %.1f) chemin %d support %s attente %s" % [_t, q.x, q.y,
			sk.global_position.y - ga._o.y, sk.chemin.size(), sk.support != null, sa._attente])
		print("      marche : %s ; skieur repère voiture %s ; cible %s" % [sk.debug_marche,
			sa._rame._interior_cars[1].global_transform.affine_inverse() * sk.global_position,
			sa._rame._interior_cars[1].global_transform.affine_inverse() * (sk.chemin[0] if sk.chemin.size() > 0 else Vector3.ZERO)])
		print("      sol %s chute %.1f chutes %d refuge %s" % [sk.is_on_floor(), sk._chute, sk._chutes.size(), sa._local_aval(sk.refuge)])
		if sk.chemin.size() > 0:
			var c0: Vector3 = sk.chemin[0]
			var qc: Vector2 = sa._local_aval(c0)
			print("      vise (%.2f ; %.2f ; h %.2f) ; skieur y %.2f" % [qc.x, qc.y, c0.y - ga._o.y, sk.global_position.y - ga._o.y])
			var r7: Array = sa._porte(7)
			print("      porte 7 : z voiture %.2f ; feuilles fantôme %s ; frac %s" % [r7[2], _main.physics.ghost_door_leaves_open(), sa._rame._door_frac_cote])
			for d in sa._rame._doors:
				var nd: Node3D = d["node"]
				if nd.get_parent() == sa._rame._interior_cars[1] or true:
					var dz: Vector3 = nd.position - d["base"]
					if absf(float(d["base"].z) - float(r7[2])) < 6.0:
						print("        vantail side %s base %s depl %s parent %s" % [d["side"], d["base"], dz, nd.get_parent().name])
			var es: PhysicsDirectSpaceState3D = sk.get_world_3d().direct_space_state
			for hh in [0.05, 0.2, 0.4, 0.6, 0.9, 1.2, 1.5]:
				var a3: Vector3 = sk.global_position + Vector3.UP * hh
				var b3: Vector3 = a3 + (Vector3(c0.x, a3.y, c0.z) - a3).normalized() * 1.5
				var rq: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(a3, b3)
				rq.exclude = [sk.get_rid()]
				var hit: Dictionary = es.intersect_ray(rq)
				if not hit.is_empty():
					var vv: Node3D = sa._rame._interior_cars[1]
					var loc: Vector3 = vv.global_transform.affine_inverse() * hit.position
					var forme: Node = hit.collider.shape_owner_get_owner(hit.collider.shape_find_owner(hit.shape))
					var cs: CollisionShape3D = forme as CollisionShape3D
					if cs != null and cs.shape is BoxShape3D:
						var cl: Transform3D = vv.global_transform.affine_inverse() * cs.global_transform
						print("      boîte %s centre voiture %s taille %s désactivée %s" % [cs.name, cl.origin, (cs.shape as BoxShape3D).size, cs.disabled])
					print("      h+%.2f : touche %s/%s (%s) à %.2f m, repère voiture (%.2f ; %.2f ; %.2f) ; rame %s" % [hh,
						hit.collider.get_parent().name, hit.collider.name, forme.get_parent().name + "/" + forme.name,
						a3.distance_to(hit.position), loc.x, loc.y, loc.z, sa._rame.name])
	if _f % 1800 == 0:
		var ph2: TrainPhysics = _main.physics
		print("  %s : s %.0f v %.1f portes %s quai %.2f trip %s fini %s" % [DomaineSkiable._mmss(_t), ph2.s, ph2.v,
			ph2.doors_open, ga._ouverture, ph2.trip_started, ph2.finished])
	if q.y > 22.0:
		_sorti = true
	if _etait_assis and not sk.assis:
		_levers += 1
	_etait_assis = sk.assis
	if sk.assis and not _assis:
		_d_banc = q.distance_to(SkieurAuto.BANC)
		_assis = true
		_t_assis = _t
		print("  %s : assis sur le banc (%.1f ; %.1f)" % [DomaineSkiable._mmss(_t), q.x, q.y])
	if sk.course_auto and _assis:
		_couru = true
	if sa.etape == SkieurAuto.Etape.A_BORD or _t > 1400.0:
		_verif("resté dans la salle (pas ressorti sur la place)", not _sorti)
		_verif("assis sur un banc pendant que la rame est en ligne", _assis)
		# retour d'utilisateur, 13/10/2026 : « il n'arrive pas à s'asseoir sur le
		# banc, il rentre dedans et repart » — assis pile devant la planche,
		# et il ne se relève qu'une fois, pour la rame
		_verif("assis SUR la planche (calé devant le banc)", _d_banc >= 0.0 and _d_banc < 0.15, "%.2f m du point" % _d_banc)
		_verif("relevé une seule fois avant de monter", _levers <= 1, "%d" % _levers)
		_verif("couru à la rame à l'ouverture du quai", _couru)
		_verif("monté à bord", sa.etape == SkieurAuto.Etape.A_BORD and sk.support != null, DomaineSkiable._mmss(_t))
		_verif("aucun déblocage", sa.debloquages == 0, "%d" % sa.debloquages)
		_fin()
