## Garde-fous (retour d'utilisateur du 16/11/2026 : « il faut que tu mettes des rambardes et des garde-fous un peu partout
## pour éviter que je tombe d'une plate-forme ou d'un escalier ») : sonde des deux gares de chaque remontée. Sur une
## grille de 1 m, tout point de plancher (décor) surélevé d'au moins 1 m au-dessus du terrain est essayé dans 8
## directions : si le corps du skieur peut avancer de 0,8 m et qu'il n'y a plus de sol à moins de 1,2 m dessous, c'est
## un bord sans garde-fou. Relevé par gare ; le banc échoue au-delà du nombre toléré (--tolere=N, 0 par défaut : voir _tolere ;
## --lignes=a,b pour n'en sonder que certaines ; --liste pour le détail des points).
##   godot --headless --fixed-fps 60 --path godot_project -s bench_garde_fous_3d.gd
extends SceneTree

var _main: Node
var _f: int = 0
var _etat: int = 0
var _lignes: Array = []
var _k: int = 0
var _t0: int = 0
var _att: int = 0
var _total: int = 0
var _pn: int = 0
var _n_pn: int = 0
## Aucun bord toléré. Ne comptent pas : les talus de neige de la gare sondée, le sol d'une autre remontée, le bord de
## quai du Funival sur sa voie.
var _tolere: int = 0
var _filtre: PackedStringArray = PackedStringArray()
var _liste: bool = false
var _bilan: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tolere="):
			_tolere = int(a.substr(9))
		if a.begins_with("--lignes="):
			_filtre = a.substr(9).split(",")
		if a == "--liste":
			_liste = true
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _sol(esp: PhysicsDirectSpaceState3D, p: Vector3, haut: float, bas: float, masque: int) -> Variant:
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(p + Vector3.UP * haut, p - Vector3.UP * bas, masque)
	var r: Dictionary = esp.intersect_ray(q)
	return r["position"] if not r.is_empty() else null


## Nom du corps qui porte le sol en `p` (pour --liste).
func _qui(esp: PhysicsDirectSpaceState3D, p: Vector3) -> String:
	var r: Dictionary = esp.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.4, p - Vector3.UP * 0.4, CollisionsJeu.COUCHE_DECOR))
	if r.is_empty():
		return "?"
	var c: Node = r["collider"]
	var forme: String = ""
	if c is CollisionObject3D and _liste:
		var co: CollisionObject3D = c
		var sh: Shape3D = co.shape_owner_get_shape(co.shape_find_owner(int(r["shape"])), 0)
		if sh is BoxShape3D:
			forme = " boîte %s" % str((sh as BoxShape3D).size.snapped(Vector3(0.01, 0.01, 0.01)))
		else:
			forme = " " + sh.get_class()
	return "%s/%s%s" % [c.get_parent().name if c.get_parent() != null else "", c.name, forme]


## Vrai si le point (repère de la ligne) repose sur une face inclinée du terrassement de neige de la gare.
func _sur_talus(tri: PackedVector3Array, p: Vector3) -> bool:
	for k in range(0, tri.size(), 3):
		var a: Vector3 = tri[k]
		var b: Vector3 = tri[k + 1]
		var c: Vector3 = tri[k + 2]
		var nrm: Vector3 = (b - a).cross(c - a)
		if nrm.length_squared() < 1e-9 or absf(nrm.normalized().y) > 0.995:
			continue
		var d: float = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(d) < 1e-9:
			continue
		var u: float = ((b.z - c.z) * (p.x - c.x) + (c.x - b.x) * (p.z - c.z)) / d
		var v: float = ((c.z - a.z) * (p.x - c.x) + (a.x - c.x) * (p.z - c.z)) / d
		if u < -0.02 or v < -0.02 or u + v > 1.02:
			continue
		if absf(u * a.y + v * b.y + (1.0 - u - v) * c.y - p.y) < 0.2:
			return true
	return false


## Bords sans garde-fou autour du point `c` (monde), plate-forme attendue vers c.y.
func _sonder(lg: LigneRemontee, c: Vector3, nom: String) -> int:
	var talus: PackedVector3Array = (lg.get("_terrassements") as Dictionary).get(nom == "aval", PackedVector3Array())
	return _sonder_repere(lg.global_transform, c, "%s %s" % [lg.name, nom], talus, 28, 52, 0.5)


## Même sonde dans un repère quelconque (gares du funiculaire) : grille de ±nx × ±nz m autour de `c`.
func _sonder_repere(xf: Transform3D, c: Vector3, titre: String, talus: PackedVector3Array, nx: int, nz: int, pas: float = 1.0) -> int:
	var esp: PhysicsDirectSpaceState3D = _main.get_world_3d().direct_space_state
	var relief = _main.relief
	var bx: Vector3 = xf.basis.x.normalized()
	var bz: Vector3 = xf.basis.z.normalized()
	var corps: CapsuleShape3D = CapsuleShape3D.new()
	corps.radius = 0.28
	corps.height = 1.5
	var pq: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	pq.shape = corps
	pq.collision_mask = CollisionsJeu.COUCHE_DECOR | CollisionsJeu.COUCHE_VEHICULE
	var n: int = 0
	var vus: Array = []
	var inv: Transform3D = xf.affine_inverse()
	# 1. sol de chaque case de 1 m : plancher du décor (cherché depuis la hauteur de la tête, les toits sont ignorés),
	#    sinon le terrain
	var sol: Dictionary = {}                 # Vector2i → [y, plancher ?, point]
	for ix in range(-nx, nx + 1):
		for iz in range(-nz, nz + 1):
			var p: Vector3 = c + (bx * float(ix) + bz * float(iz)) * pas
			var yr: float = relief.hauteur_sol(p.x, p.z)
			var s: Variant = _sol(esp, Vector3(p.x, c.y, p.z), 2.0, 6.0, CollisionsJeu.COUCHE_DECOR)
			if s != null and (s as Vector3).y > yr + 0.3:
				sol[Vector2i(ix, iz)] = [(s as Vector3).y, true, s]
			else:
				sol[Vector2i(ix, iz)] = [yr, false, Vector3(p.x, yr, p.z)]
	# 2. accessible à pied depuis le terrain : de proche en proche, 0,8 m de dénivelé au plus par mètre (escaliers,
	#    rampes) — les toits des cabanes n'en sont pas
	var acces: Dictionary = {}
	var file: Array = []
	for k in sol:
		if not sol[k][1]:
			acces[k] = true
			file.append(k)
	while not file.is_empty():
		var k0: Vector2i = file.pop_back()
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var k1: Vector2i = k0 + dv
			if acces.has(k1) or not sol.has(k1):
				continue
			if absf(float(sol[k1][0]) - float(sol[k0][0])) <= 0.8 * pas * Vector2(dv).length():
				# entre deux planchers, le corps doit passer (barrières des baies, garde-corps) : glissé à la hauteur du
				# plus haut des deux
				if sol[k0][1] or sol[k1][1]:
					var pa: Vector3 = sol[k0][2]
					var pb: Vector3 = sol[k1][2]
					var yh: float = maxf(pa.y, pb.y) + 1.05
					pq.transform = Transform3D(Basis.IDENTITY, Vector3(pa.x, yh, pa.z))
					pq.motion = Vector3(pb.x - pa.x, 0.0, pb.z - pa.z)
					var fr: PackedFloat32Array = esp.cast_motion(pq)
					if fr.size() < 2 or fr[0] < 0.999:
						continue
				acces[k1] = true
				file.append(k1)
	# 3. bords ouverts des planchers accessibles
	for k2 in sol:
		if not sol[k2][1] or not acces.has(k2):
			continue
		var ps: Vector3 = sol[k2][2]
		if ps.y - relief.hauteur_sol(ps.x, ps.z) < 1.0:
			continue
		if _sur_talus(talus, inv * ps):
			continue                          # talus de neige damée : une pente à skier, pas une plate-forme
		var rp: Dictionary = esp.intersect_ray(PhysicsRayQueryParameters3D.create(ps + Vector3.UP * 0.4, ps - Vector3.UP * 0.4, CollisionsJeu.COUCHE_DECOR))
		if not rp.is_empty() and (rp["collider"] as Node).get_parent() is LigneRemontee and not titre.begins_with(String((rp["collider"] as Node).get_parent().name) + " "):
			continue                          # sol d'une autre remontée (son talus) : elle a sa propre sonde
		var large: bool = true
		for dq in [bx * 0.3, -bx * 0.3, bz * 0.3, -bz * 0.3]:
			var sv: Variant = _sol(esp, ps + dq, 0.4, 0.4, CollisionsJeu.COUCHE_DECOR)
			if sv == null or absf((sv as Vector3).y - ps.y) > 0.25:
				large = false
				break
		if not large:
			continue
		pq.transform = Transform3D(Basis.IDENTITY, ps + Vector3.UP * 0.95)
		if not esp.intersect_shape(pq, 1).is_empty():
			continue
		for kd in range(8):
			var a: float = TAU * kd / 8.0
			var dir: Vector3 = (bx * cos(a) + bz * sin(a)).normalized()
			pq.motion = dir * 0.8
			var frac: PackedFloat32Array = esp.cast_motion(pq)
			if frac.size() < 2 or frac[0] < 0.999:
				continue                      # arrêté par un mur, une barrière, un garde-corps
			var q: Vector3 = ps + dir * 0.8
			var sq: Variant = _sol(esp, q, 0.6, 1.2, CollisionsJeu.COUCHE_DECOR | CollisionsJeu.COUCHE_VEHICULE)
			if sq != null:
				continue                      # du sol à moins de 1,2 m dessous (marche, rampe, quai)
			var sv2: Dictionary = esp.intersect_ray(PhysicsRayQueryParameters3D.create(q + Vector3.UP * 0.6, q - Vector3.UP * 1.7, CollisionsJeu.COUCHE_DECOR))
			if not sv2.is_empty() and String((sv2["collider"] as Node).name) == "VoieFunival":
				continue                      # bord de quai du Funival sur sa voie (1,3 m : la hauteur du plancher des rames)
			if q.y - relief.hauteur_sol(q.x, q.z) < 1.2:
				continue                      # le terrain est juste là
			n += 1
			if vus.size() < 40:
				# point (repère de la ligne), direction du vide (x, z locaux), hauteur au-dessus du terrain au point d'arrivée
				vus.append([inv * ps, Vector2(cos(a), sin(a)).snapped(Vector2(0.1, 0.1)),
					snappedf(q.y - relief.hauteur_sol(q.x, q.z), 0.1), _qui(esp, ps)])
			break
	_bilan.append([n, titre])
	if n > 0:
		print("GARDE-FOUS %-40s : %d bords ouverts%s" % [titre, n, ("  ex. (local) " + str(vus)) if _liste else ""])
	return n


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30 or _etat == 99:
		return
	match _etat:
		0:
			var scen: Node = _main.get_node_or_null("ScenarioPanel")
			if scen != null:
				scen.queue_free()
			_main.basculer_skieur()
			_etat = 1
		1:
			if _main.get("skieur") != null and _main.skieur.actif:
				for e in _main.remontees.lignes:
					if _filtre.is_empty() or _filtre.has(String(e[0].name)):
						_lignes.append(e[0])
				_etat = 2
		2:
			if _k >= _lignes.size() and _pn < 2 and (_filtre.is_empty() or _filtre.has("perce_neige")):
				# gares du funiculaire Perce-Neige : place et hall du bas, terrasse et restaurant du haut
				var gare: Node3D = _main.station_halls.gare_aval if _pn == 0 else _main.station_halls.gare_amont
				var dep: Vector3 = gare.point_depart()[0]
				_att += 1
				if _att == 1:
					_main.skieur.global_position = dep + Vector3(0, 0.5, 0)
					_main.collisions.assurer_autour(dep)
				_main.skieur.velocity = Vector3.ZERO
				if _att >= 120:
					_main.collisions.assurer_autour(dep)
					# (repère de la gare : x est / z nord en bas, x droite / z vers l'amont en haut)
					var o: Vector3 = gare.get("_o")
					var ax: Vector3 = gare.get("_e") if _pn == 0 else gare.get("_x")
					var az: Vector3 = gare.get("_n") if _pn == 0 else gare.get("_d")
					_total += _sonder_repere(Transform3D(Basis(ax, Vector3.UP, az), Vector3(o.x, dep.y, o.z)), dep,
						"perce_neige " + ("aval" if _pn == 0 else "amont"), PackedVector3Array(), 90, 90, 0.5)
					_n_pn += 1
					_pn += 1
					_att = 0
				return
			if _k >= _lignes.size():
				_bilan.sort_custom(func(x, y): return x[0] > y[0])
				print("BILAN GARDE-FOUS : %d bords ouverts sur %d gares (toléré %d)" % [_total, _lignes.size() * 2 + _n_pn, _tolere])
				var bon: bool = _total <= _tolere
				_etat = 99
				print("BENCH_GARDE_FOUS " + ("OK" if bon else "ECHEC"))
				FinBanc.quitter(self, _main, 0 if bon else 1)
				return
			_main.aller_a_remontee(_lignes[_k])
			_t0 = Time.get_ticks_msec()
			_att = 0
			_etat = 3
		3:
			var lg: LigneRemontee = _lignes[_k]
			if lg.role == "haut" and lg.jumelee != null and not lg.pret:
				_main.skieur.global_position = lg.global_transform.origin + Vector3(0, lg.terrain(0.0) + 1.0, 0)
			if lg.pret:
				_att += 1
				# gare aval, puis gare amont (le skieur y est posé pour que les collisions y soient)
				if _att == 60:
					var ca: Vector3 = lg.global_transform * Vector3(0, lg.terrain(0.0), 0)
					_main.collisions.assurer_autour(ca)
					_total += _sonder(lg, ca, "aval")
					var cb: Vector3 = lg.global_transform * Vector3(0, lg.terrain(lg.longueur_h()), -lg.longueur_h())
					_main.skieur.global_position = cb + Vector3(6, 3, 0)
					_main.skieur.velocity = Vector3.ZERO
					_main.collisions.assurer_autour(cb)
				if _att >= 60:
					_main.skieur.velocity = Vector3.ZERO
				if _att == 150:
					var cb2: Vector3 = lg.global_transform * Vector3(0, lg.terrain(lg.longueur_h()), -lg.longueur_h())
					_total += _sonder(lg, cb2, "amont")
					_k += 1
					_etat = 2
			elif Time.get_ticks_msec() - _t0 > 200000:
				print("GARDE-FOUS %s : non construite en 200 s" % lg.name)
				_k += 1
				_etat = 2
