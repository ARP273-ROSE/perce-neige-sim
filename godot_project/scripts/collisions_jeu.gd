class_name CollisionsJeu
extends Node3D
## Collisions du skieur jouable (demande de Kevin du 07/10/2026 : « un
## skieur capable de monter les escaliers des gares et de marcher à
## l'intérieur sans passer au travers du plancher, des murs, des portes ou
## du wagon »). Construites une seule fois, au premier passage en vue
## skieur (rien ne coûte tant qu'on conduit), par petites tranches sur
## plusieurs images (BUDGET_US) : les gros maillages en triangles
## gelaient l'image une à plusieurs secondes sur iPad, son coupé.
##
##  - GARES : les VRAIS maillages (salles, quais en escalier, halls, salle
##    des machines, tunnel et voie près des gares), en triangles — ce qu'on voit
##    est ce qui arrête. Les pièces qui bougent (vantaux de la salle
##    d'attente, portes automatiques) ont leur propre corps, accroché à
##    elles.
##  - RAMES : des collisions SIMPLIFIÉES dans le repère de chaque voiture
##    (235 000 triangles par rame en vrai) : paroi du tube en pans, paliers,
##    bancs, porte-skis, pupitre, fonds ; aux portes, un panneau accroché
##    au vantail (il s'efface quand la porte s'ouvre).
##  - RELIEF : triangles tirés des altitudes du jeu (ReliefBuilder.hauteur),
##    fins près des gares (pièces de 2 m), sans les trous des bâtiments.

const COUCHE_DECOR: int = 1
const COUCHE_VEHICULE: int = 2
const COUCHE_SKIEUR: int = 4
const DEMI_ZONE_GARE: float = 160.0     # zone des gares (m) : maillages réels
const R_PAROI: float = 1.64             # rayon intérieur du tube des voitures

var pret: bool = false
var triangles: int = 0
const BUDGET_US: int = 7000
var budget_us: int = BUDGET_US          # vue 3D du PC : 14 000 (le PC rend à part)
var _n_taches: int = 0                  # pour la progression
var _taches: Array = []                 # Callables à exécuter, dans l'ordre
var _t0: int = 0
var _decor: StaticBody3D = null
var _formes: Dictionary = {}            # Mesh → Shape3D (formes partagées)
## Nœuds dont le sous-arbre bouge : un corps à part, accroché à eux.
var mobiles: Array = []
var _main: Node = null
var _zones: Array = []                  # AABB déjà couverts (gares, galerie, à la demande)
var _zones_relief: Array = []           # Rect2 (x, z) du relief déjà en collision
var _deja: Dictionary = {}              # id de MeshInstance3D déjà en collision
var _deja_mm: Dictionary = {}           # id de MultiMeshInstance3D → PackedByteArray des instances faites
## Panneaux d'issue de secours des calottes : Cabin → CollisionShape3D[]
## (désactivés à l'évacuation, cf. set_issues)
var issues: Dictionary = {}


## Construit tout. `zones_terrain` : rectangles (Rect2 x, z) où poser le
## relief (le reste du massif n'a pas de sol).
func construire(main: Node, zones_terrain: Array, synchrone: bool = false) -> void:
	_t0 = Time.get_ticks_msec()
	_main = main
	_decor = StaticBody3D.new()
	_decor.name = "Decor"
	_decor.collision_layer = COUCHE_DECOR
	_decor.collision_mask = 0
	add_child(_decor)
	mobiles = main.get_tree().get_nodes_in_group("collision_mobile")
	var tun: TunnelBuilder = main.get("tunnel")
	var zones: Array = []
	for s in [0.0, PNConstants.LENGTH]:
		var o: Vector3 = tun.transform_at(s).origin
		zones.append(AABB(o - Vector3(DEMI_ZONE_GARE, 90.0, DEMI_ZONE_GARE),
			Vector3(2.0 * DEMI_ZONE_GARE, 180.0, 2.0 * DEMI_ZONE_GARE)))
	var ss: Node = main.get("sortie_secours")
	if ss != null and ss.get("pret"):
		zones.append(ss.zone_aabb())
	_zones = zones.duplicate()
	for nom in ["station_halls", "stations", "machine_room", "tunnel", "track", "sortie_secours"]:
		var racine: Node3D = main.get(nom) as Node3D
		if racine != null:
			_maillages(racine, zones)
	_n_taches = 0
	for m in mobiles:
		_taches.append(_corps_mobile.bind(m as Node3D))
	for nom2 in ["cabin", "cabin_ghost"]:
		var c: Cabin = main.get(nom2) as Cabin
		if c != null:
			_taches.append(_rame.bind(c))
	var relief: ReliefBuilder = main.get("relief")
	if relief != null:
		for z in zones_terrain:
			_zones_relief.append(z as Rect2)
			_taches.append(_terrain.bind(relief, z as Rect2))
	_n_taches = _taches.size()
	if synchrone or DisplayServer.get_name() == "headless":
		_avancer(1 << 62)
	else:
		set_process(true)


## Avancement de la construction (0-1).
func progres() -> float:
	if _n_taches <= 0:
		return 1.0
	return 1.0 - float(_taches.size()) / float(_n_taches)


func _process(_delta: float) -> void:
	_avancer(Time.get_ticks_usec() + budget_us)


## Exécute les tâches jusqu'à l'échéance ; prêt quand il n'en reste plus.
func _avancer(fin_us: int) -> void:
	while not _taches.is_empty():
		var c: Callable = _taches.pop_front()
		c.call()
		if Time.get_ticks_usec() > fin_us:
			return
	set_process(false)
	if not pret:
		pret = true
		print("[Collisions] %d triangles de décor, %d ms" % [triangles, Time.get_ticks_msec() - _t0])


## Collisions à la demande autour d'un point — évacuation à pied dans le
## tunnel (parois, voie, escalier de service) : une zone de ±80 m, par
## tranches, dès que le point sort des zones déjà couvertes (à 40 m du bord).
func assurer_autour(p: Vector3) -> void:
	if _main == null:
		return
	# le relief, partout où l'on marche dehors (Kevin, 08/10/2026 : « je passe
	# quasi partout au travers de la montagne ») : un carré de 400 m, dès
	# qu'on arrive à 80 m du bord de ce qui est déjà couvert
	var relief: ReliefBuilder = _main.get("relief")
	if relief != null and relief.pret:
		var couvert: bool = false
		for r in _zones_relief:
			if (r as Rect2).grow(-80.0).has_point(Vector2(p.x, p.z)):
				couvert = true
				break
		if not couvert:
			var r2: Rect2 = Rect2(p.x - 200.0, p.z - 200.0, 400.0, 400.0)
			_zones_relief.append(r2)
			_taches.append(_terrain.bind(relief, r2))
			if DisplayServer.get_name() == "headless":
				_avancer(1 << 62)
			else:
				set_process(true)
	for z in _zones:
		# (une zone de moins de 80 m — la galerie de secours — ne se rétrécit
		# pas : AABB.grow négatif y donnerait une taille négative)
		var zi: AABB = (z as AABB).grow(-minf(40.0, 0.45 * (z as AABB).size[(z as AABB).size.min_axis_index()]))
		if zi.has_point(p):
			return
	var zone: AABB = AABB(p - Vector3(80.0, 40.0, 80.0), Vector3(160.0, 80.0, 160.0))
	_zones.append(zone)
	for nom in ["tunnel", "track", "sortie_secours"]:
		var racine: Node3D = _main.get(nom) as Node3D
		if racine != null:
			_maillages(racine, [zone])
	if not _taches.is_empty():
		if DisplayServer.get_name() == "headless":
			_avancer(1 << 62)
		else:
			set_process(true)


## Panneaux d'issue de secours d'une rame : retirés (plus de collision) ou
## remis.
func set_issues(c: Cabin, retirees: bool) -> void:
	for cs in issues.get(c, []):
		if is_instance_valid(cs):
			(cs as CollisionShape3D).disabled = retirees


# --- gares : maillages réels -----------------------------------------------------

func _maillages(racine: Node3D, zones: Array) -> void:
	var pile: Array = [racine]
	while not pile.is_empty():
		var n: Node = pile.pop_back()
		if n in mobiles:
			continue
		if n is Node3D and not (n as Node3D).visible and n != racine:
			continue
		for c in n.get_children():
			pile.append(c)
		if n is MultiMeshInstance3D:
			_taches.append(_multimesh.bind(n as MultiMeshInstance3D, zones))
			continue
		if not (n is MeshInstance3D):
			continue
		var mi: MeshInstance3D = n
		if mi.mesh == null or mi.has_meta("sans_collision") or _deja.has(mi.get_instance_id()):
			continue
		var ab: AABB = mi.global_transform * mi.get_aabb()
		if ab.size.length() > 600.0:
			continue              # panoramas, fonds lointains
		var dedans: bool = false
		for z in zones:
			if (z as AABB).intersects(ab):
				dedans = true
				break
		if not dedans:
			continue
		_deja[mi.get_instance_id()] = true
		_taches.append(_ajouter_forme.bind(_decor, mi.mesh, mi.global_transform,
			"%s_%s" % [mi.get_parent().name if mi.get_parent() else "", mi.name]))


## Pièces répétées qui portent leurs positions en méta « instances » (les
## marches des quais) : une forme par instance (une boîte pour une
## BoxMesh). Les autres MultiMesh (galets, numéros…) n'arrêtent personne.
## (Le moteur sans affichage des bancs ne rend pas les positions d'un
## MultiMesh : d'où la méta.)
func _multimesh(mmi: MultiMeshInstance3D, zones: Array) -> void:
	var mm: MultiMesh = mmi.multimesh
	if mm == null or mm.mesh == null or not mmi.has_meta("instances"):
		return
	var inst: Array = mmi.get_meta("instances")
	var ab_m: AABB = mm.mesh.get_aabb()
	var id: int = mmi.get_instance_id()
	if not _deja_mm.has(id):
		var faits: PackedByteArray = PackedByteArray()
		faits.resize(inst.size())
		_deja_mm[id] = faits
	var deja: PackedByteArray = _deja_mm[id]
	for i in range(inst.size()):
		if deja[i] != 0:
			continue
		var xf: Transform3D = mmi.global_transform * (inst[i] as Transform3D)
		var ab: AABB = xf * ab_m
		var dedans: bool = false
		for z in zones:
			if (z as AABB).intersects(ab):
				dedans = true
				break
		if not dedans:
			continue
		deja[i] = 1
		if mm.mesh is BoxMesh:
			if not _formes.has(mm.mesh):
				var b: BoxShape3D = BoxShape3D.new()
				b.size = (mm.mesh as BoxMesh).size
				_formes[mm.mesh] = b
				triangles += 12
			var cs: CollisionShape3D = CollisionShape3D.new()
			cs.shape = _formes[mm.mesh]
			cs.transform = xf
			cs.name = mmi.name
			_decor.add_child(cs)
		else:
			_ajouter_forme(_decor, mm.mesh, xf, mmi.name)


func _ajouter_forme(corps: CollisionObject3D, m: Mesh, xf: Transform3D, nom: String = "") -> void:
	if not _formes.has(m):
		var f: ConcavePolygonShape3D = m.create_trimesh_shape() as ConcavePolygonShape3D
		if f == null:
			_formes[m] = null
			return
		f.backface_collision = true
		_formes[m] = f
		triangles += f.get_faces().size() / 3
	var forme: Shape3D = _formes[m]
	if forme == null:
		return
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = forme
	cs.transform = xf
	if nom != "":
		cs.name = nom.replace("@", "").replace("/", "_").replace(":", "_")
	corps.add_child(cs)


## Corps accroché à un nœud qui bouge (vantail, porte automatique) : ses
## maillages, dans son repère.
func _corps_mobile(n: Node3D) -> void:
	var corps: StaticBody3D = StaticBody3D.new()
	corps.name = "CollisionMobile"
	corps.collision_layer = COUCHE_DECOR
	corps.collision_mask = 0
	n.add_child(corps)
	var inv: Transform3D = n.global_transform.affine_inverse()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh != null:
			_ajouter_forme(corps, m.mesh, inv * m.global_transform, "Mobile_" + n.name + "_" + m.name)


# --- rames : collisions simplifiées ---------------------------------------------

## Paliers de quai des portes (3,66 m : jusqu'au bord du quai), actifs en
## gare seulement — en tunnel, on descend de la porte sur la passerelle.
var paliers_quai: Array = []


func set_paliers_quai(en_gare: bool) -> void:
	for cs in paliers_quai:
		if is_instance_valid(cs) and (cs as CollisionShape3D).disabled == en_gare:
			(cs as CollisionShape3D).disabled = not en_gare


## Seuils des portes (x 1,18-1,64) : en collision portes FERMÉES seulement.
## Le vantail fermé est à 1,50 m de l'axe et le palier s'arrête à 1,20 :
## en s'appuyant sur une porte fermée en tunnel, on tombait par la fente
## (0,30 m, la largeur du skieur) sous la rame — « passer dans une faille
## spatio-temporelle » (Kevin, 08/10/2026). Portes ouvertes, rien : de la
## porte on descend sur la passerelle (sortie de secours) ou le quai.
var seuils: Array = []
var _seuils_fermes: bool = true


func set_seuils(fermes: bool) -> void:
	_seuils_fermes = fermes
	for s in seuils:
		(s as CollisionShape3D).disabled = not fermes


func _boite(parent: Node3D, taille: Vector3, xf: Transform3D, couche: int = COUCHE_VEHICULE) -> CollisionShape3D:
	var corps: StaticBody3D = parent.get_node_or_null("CollisionRame") as StaticBody3D
	if corps == null:
		corps = StaticBody3D.new()
		corps.name = "CollisionRame"
		corps.collision_layer = couche
		corps.collision_mask = 0
		corps.set_meta("vehicule", parent)
		parent.add_child(corps)
	var b: BoxShape3D = BoxShape3D.new()
	b.size = taille
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = b
	cs.transform = xf
	cs.name = "Rame_%.2fx%.2fx%.2f" % [taille.x, taille.y, taille.z]
	corps.add_child(cs)
	return cs


func _rame(c: Cabin) -> void:
	var car_len: float = c.train_length / float(c.car_count)
	var pas: float = TrainBodyBuilder.PANEL_L + TrainBodyBuilder.RIB_W
	var tilt: float = -atan(Cabin.FLOOR_GRADE)
	var y_palier: float = TrainBodyBuilder.Y_FLOOR + Cabin.STEP_LIFT
	var y_haut_porte: float = TrainBodyBuilder.Y_CENTER \
		+ TrainBodyBuilder.R_BODY * cos(deg_to_rad(TrainBodyBuilder.DOOR_TOP_T))
	for idx in range(c.car_count):
		var voiture: Node3D = c._interior_cars[idx]
		voiture.set_meta("vehicule", voiture)
		var z_c: float = (float(idx) - (c.car_count - 1) * 0.5) * car_len
		var z0: float = -car_len * 0.5 + 0.30
		var z1: float = car_len * 0.5 - 0.30
		# paliers (pas de jour sous les contremarches)
		var portes: Array = []
		for k in range(10):
			var zc: float = c._panel_center(idx, k) - z_c
			var xf: Transform3D = Transform3D(Basis(Vector3.RIGHT, tilt), Vector3(0.0, y_palier, zc))
			# au droit des portes, le seuil va jusqu'au bord du quai (1,85 m)
			# au droit des portes, le plancher s'arrête au seuil (x 1,20) : en
			# tunnel on en descend sur la passerelle (x 0,80-1,24), juste
			# dessous ; en gare le palier de quai (3,66 m) couvre le vide
			var larg: float = 2.4 if TrainBodyBuilder.KINDS[k] == "door" else 2.5
			# 15 cm d'épaisseur : couvre la contremarche (12 cm) sans dépasser
			# sous la caisse (on passe dessous, dans la fosse de la gare basse)
			_boite(voiture, Vector3(larg, 0.15, pas + 0.02), xf * Transform3D(Basis.IDENTITY, Vector3(0.0, -0.05, 0.0)))
			if TrainBodyBuilder.KINDS[k] == "door":
				paliers_quai.append(_boite(voiture, Vector3(3.66, 0.15, pas + 0.02),
					xf * Transform3D(Basis.IDENTITY, Vector3(0.0, -0.05, 0.0))))
				# (10 cm seulement, à 1,40-1,50 : la fente restante, 20 cm, ne
				# laisse plus passer les 28 cm du skieur ; plus large, le seuil
				# barrait la PASSERELLE à qui longe la rame arrêtée, 08/10/2026)
				for side_s in [-1.0, 1.0]:
					var seuil: CollisionShape3D = _boite(voiture, Vector3(0.12, 0.15, pas + 0.02),
						xf * Transform3D(Basis.IDENTITY, Vector3(side_s * 1.44, -0.05, 0.0)))
					seuil.disabled = not _seuils_fermes
					seuils.append(seuil)
			if TrainBodyBuilder.KINDS[k] == "door":
				portes.append([zc - TrainBodyBuilder.PANEL_L * 0.5, zc + TrainBodyBuilder.PANEL_L * 0.5])
			# bancs et porte-skis, dans le repère de leur palier
			var pal: Node3D = voiture.get_node_or_null("Amenagement%d_%d" % [idx + 1, k]) as Node3D
			if pal != null:
				# boîtes DROITES dans le repère de la voiture (le palier est
				# incliné de la pente des gares) : une face qui surplombe de
				# 5° n'est plus un mur le long duquel le corps glisse, et le
				# skieur s'arrêtait net contre un porte-skis (07/10/2026)
				var xp: Transform3D = Transform3D(Basis.IDENTITY, pal.position)
				# bancs : l'assise (0,73-1,13 m) et le dossier, pas la lèvre
				# avant ; porte-skis : 5 cm de moins de chaque côté que l'arceau.
				# Kevin, 07/10/2026 : « bloqué par les derniers porte-skis, je
				# ne peux pas accéder à l'avant » — le couloir entre porte-skis
				# (0,41) et banc (0,70) ne faisait que 28 cm, la largeur du
				# skieur ; il fait maintenant 39 cm
				if TrainBodyBuilder.KINDS[k] == "win":
					# bancs d'extrémité : 45 cm de moins vers le bout — sinon
					# le banc et le pupitre (ou la calotte) se chevauchent de
					# 20 cm le long de la voiture et l'on ne passe pas vers
					# les issues de secours
					var l_banc: float = TrainBodyBuilder.PANEL_L - 0.10
					var dz_banc: float = 0.0
					if idx == 0 and k == 0:
						l_banc -= 0.45
						dz_banc = 0.225
					elif idx == c.car_count - 1 and k == 9:
						l_banc -= 0.45
						dz_banc = -0.225
					for side in [-1.0, 1.0]:
						_boite(voiture, Vector3(0.80, 0.50, l_banc),
							xp * Transform3D(Basis.IDENTITY, Vector3(side * 1.13, 0.25, dz_banc)))
				# porte-skis : PLUS de collision (Kevin, 08/10/2026 : « c'est la
				# galère de marcher dans le funi, permets de passer au travers
				# des porte-skis orange ») — on les traverse
		# paroi du tube en pans de 12°, du plafond au plancher ; au droit des
		# portes, ouverte sous le haut des vantaux (le vantail la ferme)
		var th_sol: float = acos(clampf((TrainBodyBuilder.Y_FLOOR - TrainBodyBuilder.Y_CENTER) / R_PAROI, -1.0, 1.0))
		var n_pans: int = int(ceil(th_sol / deg_to_rad(12.0)))
		for side in [-1.0, 1.0]:
			for i in range(n_pans):
				var ta: float = th_sol * float(i) / n_pans
				var tb: float = th_sol * float(i + 1) / n_pans
				var tm: float = (ta + tb) * 0.5
				var corde: float = 2.0 * R_PAROI * sin((tb - ta) * 0.5) + 0.06
				var centre: Vector3 = Vector3(side * sin(tm) * (R_PAROI + 0.07),
					TrainBodyBuilder.Y_CENTER + cos(tm) * (R_PAROI + 0.07), 0.0)
				var base: Basis = Basis(Vector3.BACK, -side * tm)
				var y_bas: float = TrainBodyBuilder.Y_CENTER + cos(tb) * R_PAROI
				var sous_portes: bool = y_bas < y_haut_porte - 0.05
				var trous: Array = portes if sous_portes else []
				# issues de secours des calottes : les pans du bas (sous 60 cm)
				# s'arrêtent 1,1 m avant les extrémités de rame, sinon le D
				# (0,16 m de large au ras du plancher, rabattu sur ρ ≤ 1,62) est
				# infranchissable pour la capsule (0,28 m)
				if y_bas < TrainBodyBuilder.Y_FLOOR + 0.6:
					trous = trous.duplicate()
					if idx == 0:
						trous.append([z0 - 0.1, z0 + 1.1])
					if idx == c.car_count - 1:
						trous.append([z1 - 1.1, z1 + 0.1])
				var morceaux: Array = [[z0, z1]]
				if not trous.is_empty():
					morceaux = _hors(z0, z1, trous)
				for mo in morceaux:
					var l: float = float(mo[1]) - float(mo[0])
					if l < 0.02:
						continue
					_boite(voiture, Vector3(0.14, corde, l),
						Transform3D(base, centre + Vector3(0.0, 0.0, (float(mo[0]) + float(mo[1])) * 0.5)))
		# fonds : calotte à l'extrémité de rame (avec ses deux issues de
		# secours), cloison à l'attelage
		for e in [-1.0, 1.0]:
			var ze: float = (z0 - 0.05) if e < 0.0 else (z1 + 0.05)
			if (idx == 0 and e < 0.0) or (idx == c.car_count - 1 and e > 0.0):
				_calotte(c, voiture, e * (car_len * 0.5 - 0.45))   # devant le pupitre, sous le pare-brise
			else:
				_boite(voiture, Vector3(3.4, 3.4, 0.10), Transform3D(Basis.IDENTITY,
					Vector3(0.0, TrainBodyBuilder.Y_CENTER, ze)))
		# plafond (on ne grimpe pas sur les porte-skis)
		_boite(voiture, Vector3(2.6, 0.10, z1 - z0), Transform3D(Basis.IDENTITY,
			Vector3(0.0, TrainBodyBuilder.Y_CENTER + R_PAROI - 0.10, (z0 + z1) * 0.5)))
	# poste de conduite : pupitre et siège (voiture de tête)
	if c.interior_root != null and not c._interior_cars.is_empty():
		var v0: Node3D = c._interior_cars[0]
		var z_l: float = -c.train_length * 0.5     # avant de la rame, repère de la rame
		# (repère de la voiture 1 = repère de la rame décalé de v0.position.z :
		# avec le signe inversé, pupitre et siège étaient posés 16 m derrière
		# la voiture — ni l'un ni l'autre n'arrêtait personne)
		var dz: float = v0.position.z
		var seat: Node3D = c.interior_root.get_node_or_null("DriverSeatBase") as Node3D
		var y_seat: float = seat.position.y if seat != null else -0.40
		_boite(v0, Vector3(1.30, 0.70, 0.45), Transform3D(Basis.IDENTITY,
			Vector3(0.0, y_seat + 0.15, z_l + 0.62 - dz)))
		if seat != null:
			_boite(v0, Vector3(0.55, 0.55, 0.55), Transform3D(Basis.IDENTITY,
				Vector3(0.0, y_seat - 0.22, seat.position.z - dz)))
	# vantaux des portes : un panneau par porte, accroché au vantail
	var car_len2: float = car_len
	for d in c._doors:
		var vantail: Node3D = d["node"]
		var voit: Node3D = vantail.get_parent() as Node3D
		var idx2: int = c._car_roots.find(voit)
		if idx2 < 0:
			continue
		var z_c2: float = (float(idx2) - (c.car_count - 1) * 0.5) * car_len2
		var y_bas2: float = TrainBodyBuilder.Y_FLOOR
		for k2 in range(10):
			if TrainBodyBuilder.KINDS[k2] != "door":
				continue
			var zc2: float = c._panel_center(idx2, k2) - z_c2
			var base_v: Vector3 = d["base"]
			var x2: float = float(d["side"]) * (R_PAROI + 0.04) * 0.92
			_boite(vantail, Vector3(0.10, y_haut_porte - y_bas2, TrainBodyBuilder.PANEL_L + 0.06),
				Transform3D(Basis.IDENTITY, Vector3(x2, (y_bas2 + y_haut_porte) * 0.5, zc2) - base_v))
		var corps_v: Node = vantail.get_node_or_null("CollisionRame")
		if corps_v != null:
			corps_v.set_meta("vehicule", voit)


## Fond de calotte : plein au milieu et autour des deux issues de secours
## (D jaunes de part et d'autre du pare-brise, x 0,98-1,62 m, du plancher
## au haut du D) ; les panneaux des issues sont des formes à part, que
## set_issues désactive à l'évacuation — on passe alors par le trou et l'on
## descend sur la voie.
func _calotte(c: Cabin, voiture: Node3D, ze: float) -> void:
	var yc: float = TrainBodyBuilder.Y_CENTER
	var x0: float = TrainBodyBuilder.DOOR_X0
	var x1: float = TrainBodyBuilder.DOOR_RHO
	var y_bas: float = TrainBodyBuilder.Y_FLOOR - 0.10
	var y_haut: float = yc + TrainBodyBuilder._face_y(TrainBodyBuilder.DOOR_TOP_REAL)
	# plancher du poste jusqu'au fond (les paliers s'arrêtent à 1,25 m de
	# l'axe : devant les issues, à 0,98-1,62 m, on marchait sur rien)
	_boite(voiture, Vector3(3.3, 0.15, 1.8), Transform3D(Basis.IDENTITY,
		Vector3(0.0, TrainBodyBuilder.Y_FLOOR + Cabin.STEP_LIFT - 0.05, ze - signf(ze) * 0.9)))
	_boite(voiture, Vector3(2.0 * x0, 3.4, 0.10), Transform3D(Basis.IDENTITY, Vector3(0.0, yc, ze)))
	if not issues.has(c):
		issues[c] = []
	for side in [-1.0, 1.0]:
		var xm: float = side * (x0 + x1) * 0.5
		_boite(voiture, Vector3(0.40, 3.4, 0.10), Transform3D(Basis.IDENTITY, Vector3(side * (x1 + 0.20), yc, ze)))
		_boite(voiture, Vector3(x1 - x0, yc + 1.7 - y_haut, 0.10),
			Transform3D(Basis.IDENTITY, Vector3(xm, (y_haut + yc + 1.7) * 0.5, ze)))
		_boite(voiture, Vector3(x1 - x0, y_bas - (yc - 1.7), 0.10),
			Transform3D(Basis.IDENTITY, Vector3(xm, (y_bas + yc - 1.7) * 0.5, ze)))
		(issues[c] as Array).append(_boite(voiture, Vector3(x1 - x0, y_haut - y_bas, 0.10),
			Transform3D(Basis.IDENTITY, Vector3(xm, (y_bas + y_haut) * 0.5, ze))))


## Morceaux de [z0, z1] hors des intervalles `trous`.
static func _hors(z0: float, z1: float, trous: Array) -> Array:
	var out: Array = []
	var a: float = z0
	var tri: Array = trous.duplicate()
	tri.sort_custom(func(p, q): return float(p[0]) < float(q[0]))
	for t in tri:
		if float(t[0]) > a:
			out.append([a, minf(float(t[0]), z1)])
		a = maxf(a, float(t[1]))
	if a < z1:
		out.append([a, z1])
	return out


# --- relief ------------------------------------------------------------------------

## Sol du relief sur le rectangle `r` (x, z, largeur, profondeur) : les
## triangles mêmes du bloc affiché (nœuds de sa grille, même diagonale),
## sauf dans les pièces fines des gares, maillées à 2 m sans les trous des
## bâtiments.
func _terrain(relief: ReliefBuilder, r: Rect2) -> void:
	var faces: PackedVector3Array = PackedVector3Array()
	var pieces: Array = relief._rects_pieces
	# bloc : nœuds de la grille (pas d'affichage _pas)
	var dx: float = relief._dx * relief._pas
	var dz: float = relief._dz * relief._pas
	var j0: int = maxi(int(floor((r.position.x - ReliefDonnees.X_OUEST) / dx)), 0)
	var j1: int = mini(int(ceil((r.end.x - ReliefDonnees.X_OUEST) / dx)), (ReliefDonnees.NX - 1) / relief._pas)
	var i0: int = maxi(int(floor((r.position.y - ReliefDonnees.Z_NORD) / dz)), 0)
	var i1: int = mini(int(ceil((r.end.y - ReliefDonnees.Z_NORD) / dz)), (ReliefDonnees.NZ - 1) / relief._pas)
	var n: int = ReliefDonnees.NX
	var p: int = relief._pas
	for i in range(i0, i1):
		for j in range(j0, j1):
			var x0: float = ReliefDonnees.X_OUEST + j * dx
			var z0: float = ReliefDonnees.Z_NORD + i * dz
			var maille: Rect2 = Rect2(x0, z0, dx, dz)
			var dans_piece: bool = false
			for pc in pieces:
				if (pc as Rect2).intersects(maille):
					dans_piece = true     # recouverte par la pièce fine (ci-dessous)
					break
			if dans_piece:
				continue
			var pa: Vector3 = Vector3(x0, relief._h[(i * p) * n + j * p], z0)
			var pb: Vector3 = Vector3(x0 + dx, relief._h[(i * p) * n + (j + 1) * p], z0)
			var pc2: Vector3 = Vector3(x0, relief._h[((i + 1) * p) * n + j * p], z0 + dz)
			var pd: Vector3 = Vector3(x0 + dx, relief._h[((i + 1) * p) * n + (j + 1) * p], z0 + dz)
			# même découpe que les tuiles : (a, b, c) puis (b, d, c)
			faces.append_array([pa, pb, pc2, pb, pd, pc2])
	# pièces fines des gares (2 m), étendues aux mailles du bloc qu'elles
	# touchent (hors de la pièce : les triangles du bloc, échantillonnés)
	for pc3 in pieces:
		var pr: Rect2 = pc3 as Rect2
		if not pr.intersects(r):
			continue
		var gx0: float = ReliefDonnees.X_OUEST + floor((pr.position.x - ReliefDonnees.X_OUEST) / dx) * dx
		var gx1: float = ReliefDonnees.X_OUEST + ceil((pr.end.x - ReliefDonnees.X_OUEST) / dx) * dx
		var gz0: float = ReliefDonnees.Z_NORD + floor((pr.position.y - ReliefDonnees.Z_NORD) / dz) * dz
		var gz1: float = ReliefDonnees.Z_NORD + ceil((pr.end.y - ReliefDonnees.Z_NORD) / dz) * dz
		var rp: Rect2 = Rect2(gx0, gz0, gx1 - gx0, gz1 - gz0)
		var pas: float = ReliefBuilder.PAS_PIECE
		var nx: int = int(ceil(rp.size.x / pas))
		var nz: int = int(ceil(rp.size.y / pas))
		var h: PackedFloat32Array = PackedFloat32Array()
		h.resize((nx + 1) * (nz + 1))
		var trou: PackedByteArray = PackedByteArray()
		trou.resize((nx + 1) * (nz + 1))
		for jj in range(nz + 1):
			for ii in range(nx + 1):
				var x: float = rp.position.x + ii * pas
				var z: float = rp.position.y + jj * pas
				var tp: Array = relief.terrain_piece(x, z)
				var hh: float = float(tp[0])
				if is_nan(hh):
					hh = relief._hauteur_tri(x, z)
				h[jj * (nx + 1) + ii] = hh
				trou[jj * (nx + 1) + ii] = 1 if bool(tp[1]) else 0
		for jj in range(nz):
			for ii in range(nx):
				var a: int = jj * (nx + 1) + ii
				var b: int = a + 1
				var c3: int = a + nx + 1
				var d: int = c3 + 1
				var xa: float = rp.position.x + ii * pas
				var za: float = rp.position.y + jj * pas
				# maille retirée si son centre est dans un bâtiment (pas dès
				# qu'un coin y touche : sinon 2 m de vide devant les portes)
				if trou[a] + trou[b] + trou[c3] + trou[d] > 0 \
						and bool(relief.terrain_piece(xa + pas * 0.5, za + pas * 0.5)[1]):
					continue
				faces.append_array([Vector3(xa, h[a], za), Vector3(xa + pas, h[b], za),
					Vector3(xa, h[c3], za + pas), Vector3(xa + pas, h[b], za),
					Vector3(xa + pas, h[d], za + pas), Vector3(xa, h[c3], za + pas)])
	if faces.is_empty():
		return
	var f: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	f.set_faces(faces)
	f.backface_collision = true
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.name = "Relief"
	cs.shape = f
	_decor.add_child(cs)
	triangles += faces.size() / 3
