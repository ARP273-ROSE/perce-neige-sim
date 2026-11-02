## Le skieur à pied ne doit jamais rester coincé. Test de propriété, en marche
## enchaînée dans les gares : depuis là où il est, un segment droit dont la géométrie
## prouve qu'il est praticable (sol tous les 10 cm, marches ≤ 30 cm, place pour le
## corps) ; il doit aller au bout, en marche ou en course. S'il n'y arrive pas, on regarde s'il peut
## encore bouger dans une des 8 directions (sinon : vraiment coincé).
##   godot --headless --fixed-fps 60 --path godot_project -s bench_coince_3d.gd -- --n=500 --graine=1
extends SceneTree

const PAS: float = 0.10
const MARCHE: float = 0.30
const Y_LIBRE: float = 0.45          # au-dessus, le corps doit passer

var _main: Node = null
var _f: int = 0
var _st: int = 0
var _n: int = 300
var _i: int = 0
var _rng := RandomNumberGenerator.new()
var _zones: Array = []
var _a: Vector3
var _b: Vector3
var _t: float = 0.0
var _limite: float = 0.0
var _course: bool = false
var _echecs: int = 0
var _coinces: int = 0
var _essais: int = 0
var _dir_k: int = 0
var _p_fuite: Vector3
var _fuite_max: float = 0.0
var _etapes: int = 0
var _attente: int = 0
var _filet_ok: bool = false
var _d_prec: int = 0
var _q_prec: Vector3 = Vector3.ZERO
const P_PLATEFORME: Vector3 = Vector3(-639.19, 3029.91, 3163.47)
var _p_filet: Vector3 = P_PLATEFORME


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--n="):
			_n = int(String(a).substr(4))
		if String(a).begins_with("--graine="):
			_rng.seed = int(String(a).substr(9))
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _espace() -> PhysicsDirectSpaceState3D:
	return (_main.skieur as Node3D).get_world_3d().direct_space_state


func _rayon(de: Vector3, a: Vector3) -> Dictionary:
	var rq := PhysicsRayQueryParameters3D.create(de, a, _main.skieur.collision_mask, [_main.skieur.get_rid()])
	rq.hit_back_faces = false     # le dedans d'un maillage fermé (toit) n'est pas un sol
	return _espace().intersect_ray(rq)


func _nom_sol(h: Dictionary) -> String:
	var co: CollisionObject3D = h["collider"]
	var ow: Object = co.shape_owner_get_owner(co.shape_find_owner(h["shape"]))
	return str((ow as Node).name) if ow != null else ""


## Sols empilés à (x, z), sur 12 m sous `haut`.
func _sols(x: float, z: float, haut: float) -> Array:
	var out: Array = []
	var y: float = haut
	for _k in range(6):
		var h: Dictionary = _rayon(Vector3(x, y, z), Vector3(x, haut - 12.0, z))
		if h.is_empty():
			break
		var p: Vector3 = h["position"]
		var nom: String = _nom_sol(h)
		# sur les toits : inaccessible en jeu. Sur le relief nu : peu d'intérêt, 1 fois sur 10.
		if (h["normal"] as Vector3).y > 0.7 and not nom.to_lower().contains("toit") \
				and (nom != "Relief" or _rng.randf() < 0.1):
			out.append(p)
		y = p.y - 0.05
	return out


func _libre(p: Vector3) -> bool:
	var c := CapsuleShape3D.new()
	c.radius = SkieurJoueur.RAYON + 0.02
	c.height = maxf(SkieurJoueur.TAILLE - Y_LIBRE, c.radius * 2.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = c
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * (Y_LIBRE + c.height * 0.5))
	q.collision_mask = _main.skieur.collision_mask
	q.exclude = [_main.skieur.get_rid()]
	return _espace().intersect_shape(q, 1).is_empty()


## Praticable d'un bout à l'autre ? Renvoie le point d'arrivée au sol, ou null.
func _praticable(a: Vector3, cap: Vector3, l: float):
	var y: float = a.y
	var d: float = 0.0
	var p: Vector3 = a
	while d < l:
		d += PAS
		var q: Vector3 = a + cap * d
		var h: Dictionary = _rayon(Vector3(q.x, y + MARCHE + 0.02, q.z), Vector3(q.x, y - MARCHE, q.z))
		if h.is_empty() or (h["normal"] as Vector3).y < 0.7 or _nom_sol(h).to_lower().contains("toit"):
			return null
		p = h["position"]
		if not _libre(p):
			return null
		y = p.y
	return p


## Marche enchaînée : on part de là où il est, donc d'un endroit qu'on peut vraiment
## atteindre. Toutes les 25 étapes, ou s'il est tombé, on repart d'une autre graine.
func _graine() -> void:
	var sk: SkieurJoueur = _main.skieur
	var relief = _main.get("relief")
	var tun: TunnelBuilder = _main.tunnel
	var k: int = _rng.randi() % 4
	var p: Vector3
	if k == 0:
		# quais du funiculaire, en bas et en haut
		var s0: float = _rng.randf_range(5.0, 40.0)
		if _rng.randf() < 0.5:
			s0 = PNConstants.LENGTH - s0
		var x: Transform3D = tun.transform_at(s0)
		p = x.origin + x.basis.x * (_main.stations.platform_inner_x + 0.5) * (1.0 if _rng.randf() < 0.5 else -1.0) \
			+ x.basis.y * (StationsBuilder.FLOOR_Y_LOCAL + _main.stations.platform_height + 0.2)
	else:
		# autour d'une gare de remontée ou du funiculaire, au sol
		var r: Rect2 = relief._rects_pieces[_rng.randi() % relief._rects_pieces.size()]
		var q: Vector2 = Vector2(_rng.randf_range(r.position.x, r.end.x), _rng.randf_range(r.position.y, r.end.y))
		p = Vector3(q.x, relief.hauteur_sol(q.x, q.y) + 0.3, q.y)
	sk.global_position = p
	sk.velocity = Vector3.ZERO
	sk.support = null
	_etapes = 0


func _tirer() -> bool:
	var sk: SkieurJoueur = _main.skieur
	if not sk.is_on_floor():
		return false
	var h0: Dictionary = _rayon(sk.global_position + Vector3.UP * 0.2, sk.global_position + Vector3.DOWN * 0.3)
	if h0.is_empty():
		return false
	var a: Vector3 = h0["position"]
	var repli = null
	for _k in range(24):
		var ang: float = _rng.randf() * TAU
		var cap: Vector3 = Vector3(cos(ang), 0.0, sin(ang))
		var b = _praticable(a, cap, _rng.randf_range(1.0, 5.0))
		if b == null:
			continue
		var hb: Dictionary = _rayon(b + Vector3.UP * 0.2, b + Vector3.DOWN * 0.3)
		# de préférence vers les gares et les marches : c'est là que ça coince
		if absf(b.y - a.y) > 0.2 or (not hb.is_empty() and _nom_sol(hb) != "Relief"):
			_a = a
			_b = b
			return true
		repli = b
	if repli == null:
		return false
	_a = a
	_b = repli
	return true


func _poser() -> void:
	_main.skieur.chemin = []


func _viser(sk: SkieurJoueur, cible: Vector3, force: float) -> void:
	var d: Vector3 = cible - sk.global_position
	var y: float = atan2(-d.x, -d.z)
	sk.cam_yaw = y
	sk._ref_pouce = y
	sk.entree = Vector2(0.0, force)


func _tick() -> void:
	_f += 1
	if _main.get("skieur") != null:
		var sk0: SkieurJoueur = _main.skieur
		if sk0.degagements != _d_prec:
			if sk0.degagements > _d_prec and _st != 10 and _st != 12:
				print("DEGAGE de %s vers %s, %.2f m ; segment %s → %s ; marche[%s] ; chaussé %s" % [_q_prec, sk0.global_position,
					_q_prec.distance_to(sk0.global_position), _a, _b, sk0.debug_marche, sk0.chausse])
			_d_prec = sk0.degagements
		_q_prec = sk0.global_position
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _st == 0:
		_main.basculer_skieur()
		if _main.auto_operator.enabled:
			_main.auto_operator.toggle()
		_st = 1
		return
	if _main.collisions == null or not _main.collisions.pret or _f < 200:
		return
	var sk: SkieurJoueur = _main.skieur
	if _zones.is_empty():
		for r in relief._rects_pieces:
			var c: Vector2 = (r as Rect2).get_center()
			_zones.append([r, relief.hauteur_sol(c.x, c.y) + 40.0])
		var tun: TunnelBuilder = _main.tunnel
		for s in [0.0, 20.0, 40.0, PNConstants.LENGTH - 40.0, PNConstants.LENGTH - 20.0, PNConstants.LENGTH]:
			var o: Vector3 = tun.transform_at(s).origin
			var rz: Array = [Rect2(o.x - 12.0, o.z - 12.0, 24.0, 24.0), o.y + 8.0]
			for _k in range(max(1, relief._rects_pieces.size() / 6)):
				_zones.append(rz)
		sk.chausser(false) if sk.has_method("chausser") else null
		sk.chausse = false
		_st = 10
		_t = 0.0
		# le filet : corps pris dans le décor, sous le caillebotis de la gare amont
		sk.global_position = Vector3(-575.87, 3031.05, 3158.3)
		sk.velocity = Vector3.ZERO
		_p_fuite = sk.global_position
		return
	match _st:
		10:
			_t += 1.0 / 60.0
			sk.chausse = false
			_viser(sk, sk.global_position + Vector3.FORWARD, 0.85)
			if _t > 3.0:
				var parti: float = sk.global_position.distance_to(_p_fuite)
				print("%s filet : corps pris dans le décor → dégagé — %d dégagement, %.2f m" % ["[OK]  " if sk.degagements >= 1 and parti > 0.1 else "[INFO]", sk.degagements, parti])
				_filet_ok = sk.degagements >= 1
				sk.degagements = 0
				_st = 11
				_t = 0.0
		11:
			# plateforme d'une gare construite autour de lui (TSD4 de la Vanoise, gare amont)
			_t += 1.0 / 60.0
			sk.chausse = false
			sk.entree = Vector2.ZERO
			sk.global_position = P_PLATEFORME
			sk.velocity = Vector3.ZERO
			if (_ligne("tsd4_vanoise") != null and _ligne("tsd4_vanoise").pret) or _t > 90.0:
				_t = 0.0
				_st = 12
				# sous le dessus de la plateforme, quelle que soit sa hauteur (les gares sont
				# creusées depuis le 02/11/2026) : 0,91 m plus bas, comme au relevé d'origine
				var vn: LigneRemontee = _ligne("tsd4_vanoise")
				if vn != null and vn.pret:
					var y_pl: float = (vn.global_transform * Vector3(0, vn.terrain(vn.longueur_h()), 0)).y
					_p_filet = Vector3(P_PLATEFORME.x, y_pl - 0.91, P_PLATEFORME.z)
					sk.global_position = _p_filet
		12:
			_t += 1.0 / 60.0
			sk.chausse = false
			_viser(sk, sk.global_position + Vector3.FORWARD, 0.85)
			if _t > 3.0:
				var loin: float = sk.global_position.distance_to(_p_filet)
				# gares creusées (02/11/2026) : cette plateforme ne le prend plus forcément ; alors,
				# il doit simplement être libre. Le filet reste prouvé par le test du corps pris.
				var ok_pl: bool = (sk.degagements >= 1 and loin < SkieurJoueur.REPLI_PROCHE) or (sk.degagements == 0 and _libre(sk.global_position))
				print("%s filet : plateforme de gare autour de lui → reposé tout près, ou pas pris — %d dégagement, %.2f m" % [
					"[OK]  " if ok_pl else "[ECHEC]", sk.degagements, loin])
				_filet_ok = _filet_ok and ok_pl
				sk.degagements = 0
				sk.pieges_sans_issue = 0
				_st = 2
		2:
			# on ne marche qu'une fois les remontées proches construites : leurs plateformes
			# apparaîtraient sinon autour de lui, ce qui n'est pas le cas en jeu (construites
			# à 2 km) et reste couvert par le test du filet ci-dessus
			if _main.remontees._en_cours != null and _i < _n:
				sk.entree = Vector2.ZERO
				return
			# posé par le tirage avant que la plateforme n'apparaisse : retiré, pas de marche d'ici
			if _i < _n and _etapes == 0 and sk.is_on_floor() and not _libre(sk.global_position):
				_graine()
				return
			if _i >= _n:
				print("dégagements du filet pendant la marche : %d, sans issue : %d" % [sk.degagements, sk.pieges_sans_issue])
				print("BILAN %d segments praticables : %d pas au bout, dont %d vraiment coincés (%d tirages)" % [_i, _echecs, _coinces, _essais])
				# vraiment coincé : jamais. Arrêts (tombé dans une fosse au bord du segment, rame qui
				# gêne, temps dépassé) : tolérés à 1 %.
				# un déclenchement du filet en marche est un blocage
				# TAUX CONNU, non résolu (02/11/2026) : 13 filets sur 18 000 segments, 3 sur 4 800, soit
				# environ 0,07 %, surtout en gare amont vers (-544 ; 3028 ; 3116), où le segment affiché
				# est souvent ailleurs (tirage du banc probable, non prouvé). À 300 segments, ce verdict
				# échoue donc par intermittence sans régression : comparer au taux sur plusieurs graines.
				var bon: bool = _filet_ok and _coinces == 0 and sk.degagements == 0 and sk.pieges_sans_issue == 0 and _echecs * 100 <= _i
				if not bon and _coinces == 0 and sk.pieges_sans_issue == 0 and _filet_ok and _echecs * 100 <= _i:
					print("(échec dû au seul filet, %d sur %d segments ; taux de base connu 0,07 %% : voir la note ci-dessus dans le banc)" % [sk.degagements, _i])
				print("BENCH_COINCE " + ("OK" if bon else "ECHEC"))
				quit(0 if bon else 1)
				return
			sk.entree = Vector2.ZERO
			_attente += 1
			if _etapes >= 25 or _attente > 120:
				_graine()
				_attente = 0
				return
			_essais += 1
			if _tirer():
				_attente = 0
				_etapes += 1
				_course = _rng.randf() < 0.5
				_poser()
				var dist: float = Vector2(_b.x - _a.x, _b.z - _a.z).length()
				_limite = 3.0 * dist / (SkieurJoueur.V_COURSE if _course else SkieurJoueur.V_MARCHE) + 1.5
				_t = 0.0
				_st = 3
				return
		3:
			_t += 1.0 / 60.0
			sk.chausse = false
			var d: Vector3 = _b - sk.global_position
			if Vector2(d.x, d.z).length() < 0.35 and absf(d.y) < 0.8:
				sk.entree = Vector2.ZERO
				_i += 1
				_st = 2
				return
			_viser(sk, _b, 1.0 if _course else 0.85)
			if sk.global_position.distance_to(_b) > 40.0:
				# tombé puis rattrapé ailleurs : pas un blocage
				_etapes = 99
				_st = 2
				return
			if _t > _limite:
				_dir_k = 0
				_t = 0.0
				_p_fuite = sk.global_position
				_fuite_max = 0.0
				_st = 4
		4:
			# peut-il encore bouger ?
			_t += 1.0 / 60.0
			sk.chausse = false
			var ang: float = float(_dir_k) / 8.0 * TAU
			_viser(sk, sk.global_position + Vector3(cos(ang), 0.0, sin(ang)), 0.85)
			_fuite_max = maxf(_fuite_max, sk.global_position.distance_to(_p_fuite))
			if _t > 0.5:
				_t = 0.0
				_dir_k += 1
				if _dir_k >= 8:
					sk.entree = Vector2.ZERO
					_echecs += 1
					var coince: bool = _fuite_max < 0.30
					if coince:
						_coinces += 1
					print("%s %s → %s arrêté %s %s fuite %.2f marche[%s] mur %s sol %s" % ["COINCE" if coince else "ARRET ", _a, _b, _p_fuite, "course" if _course else "marche", _fuite_max, sk.debug_marche, sk.is_on_wall(), sk.is_on_floor()])
					_i += 1
					_etapes = 99
					_st = 2


func _ligne(cle: String) -> LigneRemontee:
	for e in (_main.remontees as RemonteesDomaine).lignes:
		if (e[0] as Node).name == cle:
			return e[0]
	return null
