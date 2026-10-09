class_name DomaineSkiable
extends Node3D
## Le domaine skiable du skieur jouable (07/10/2026) : jalons des pistes
## d'OpenStreetMap (PistesDonnees), nom de la piste où l'on est, et le
## fantôme des descentes de Kevin (FantomesDonnees).
## Kevin : « tu as balisé les pistes ? » ; « je t'ai mis mes trajectoires
## GPX, si jamais ça peut t'aider ».
##
## Jalons : un de chaque côté de la piste tous les PAS_JALON mètres, de la
## couleur de la piste (verte, bleue, rouge, noire) ; regroupés par cases
## de 1 km pour n'afficher que ceux d'à côté.

const PAS_JALON: float = 40.0
const H_JALON: float = 1.6
const CASE: float = 1000.0
const COULEURS: Array = [Color(0.10, 0.58, 0.22), Color(0.10, 0.33, 0.85),
	Color(0.85, 0.12, 0.10), Color(0.06, 0.06, 0.07)]
## Un fantôme part quand le skieur chaussé bouge à moins de R_DEPART de son
## départ ; arrivée : à moins de R_ARRIVEE de la gare de Val Claret.
## Panneaux ronds des bords de piste (Kevin, 07/10/2026 : « rajoute les
## panneaux ronds des bords de piste de la couleur adéquate avec marqué
## Tignes et le nom de la piste, sinon je suis perdu ») : un disque de la
## couleur de la piste sur un poteau, à droite en descendant, au départ et
## tous les PAS_PANNEAU mètres, « TIGNES » et le nom de la piste.
const PAS_PANNEAU: float = 250.0
const H_POTEAU: float = 2.2
const ENFONCE: float = 1.2                # le poteau descend 1,2 m sous le sol calculé : le sol
                                           # AFFICHÉ (maille 25 m) s'en écarte, et le panneau
                                           # « flottait dans l'air » (Kevin, 08/10/2026)
const R_DISQUE: float = 0.45
var n_panneaux: int = 0
var _piquets: Dictionary = {}           # piste → [côté −, côté +] : [[pied, tangente de l'axe]…]
const R_DEPART: float = 40.0
const R_ARRIVEE: float = 200.0

var relief: ReliefBuilder = null
var fantome: FantomeSki = null
var _construit: bool = false
var _axes: Array = []                  # axes des pistes (PackedVector2Array)
var _cadres: Array = []                # leur emprise (Rect2), pour ne tester que les voisines
var _t_piste: float = 0.0
var _piste: Array = ["", -1]
## Chrono du skieur depuis le départ du fantôme (−1 : pas de course).
var chrono: float = -1.0
## Dernier résultat d'une course contre le fantôme (texte), "" sinon.
var resultat: String = ""


func construire(r: ReliefBuilder) -> void:
	relief = r
	if _construit or relief == null or not relief.pret:
		return
	_construit = true
	var cases: Dictionary = {}          # Vector3i(case x, case z, couleur) → [Transform3D]
	_axes.clear()
	_cadres.clear()
	for i in range(PistesDonnees.PISTES.size()):
		var a: PackedVector2Array = PistesDonnees.axe(i)
		_axes.append(a)
		var cadre: Rect2 = Rect2(a[0], Vector2.ZERO)
		for v in a:
			cadre = cadre.expand(v)
		_cadres.append(cadre.grow(PistesDonnees.LARGEUR))
	for ip in range(PistesDonnees.PISTES.size()):
		var c: int = PistesDonnees.PISTES[ip][1]
		if c < 0:
			continue
		var pts: PackedVector2Array = _axes[ip]
		var reste: float = PAS_JALON * 0.5
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var l: float = a.distance_to(b)
			if l < 1e-3:
				continue
			var t: Vector2 = (b - a) / l
			var nrm: Vector2 = Vector2(-t.y, t.x)
			var u: float = reste
			while u < l:
				var q: Vector2 = a + t * u
				for sg in [-1.0, 1.0]:
					var j: Vector2 = q + nrm * sg * (PistesDonnees.LARGEUR * 0.5)
					if not relief.dans_le_bloc(j.x, j.y):
						continue
					var y: float = relief.hauteur_sol(j.x, j.y)
					if not _piquets.has(ip):
						_piquets[ip] = [[], []]
					(_piquets[ip][0 if sg < 0.0 else 1] as Array).append([Vector3(j.x, y, j.y), t])
					var cle: Vector3i = Vector3i(int(floor(j.x / CASE)), int(floor(j.y / CASE)), c)
					if not cases.has(cle):
						cases[cle] = []
					(cases[cle] as Array).append(Transform3D(Basis.IDENTITY, Vector3(j.x, y + H_JALON * 0.5, j.y)))
				u += PAS_JALON
			reste = u - l
	_construire_panneaux()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.028
	mesh.bottom_radius = 0.034
	mesh.height = H_JALON
	mesh.radial_segments = 6
	mesh.rings = 1
	var mats: Array = []
	for col in COULEURS:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.6
		mats.append(m)
	var n: int = 0
	for cle in cases:
		var xs: Array = cases[cle]
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xs.size()
		for k in range(xs.size()):
			mm.set_instance_transform(k, xs[k])
		var mi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mi.name = "Jalons"
		mi.multimesh = mm
		mi.material_override = mats[(cle as Vector3i).z]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 900.0
		mi.layers = 1 | Cabin.LAYER_VOIE
		add_child(mi)
		n += xs.size()
	fantome = FantomeSki.new()
	fantome.name = "Fantome"
	fantome.relief = relief
	add_child(fantome)
	print("[Domaine] %d jalons, %d panneaux, %d fantômes" % [n, n_panneaux, FantomesDonnees.DESCENTES.size()])


## Panneaux ronds : poteaux et disques en MultiMesh par couleur ; face
## dessinée par piste (PanneauPiste : nom en arc, TIGNES en arc) et numéro de
## balise en Label3D ; visibles à 350 m.
func _construire_panneaux() -> void:
	var poteau: CylinderMesh = CylinderMesh.new()
	poteau.top_radius = 0.055
	poteau.bottom_radius = 0.065
	poteau.height = H_POTEAU + ENFONCE
	poteau.radial_segments = 8
	poteau.rings = 1
	var disque: CylinderMesh = CylinderMesh.new()
	disque.top_radius = R_DISQUE
	disque.bottom_radius = R_DISQUE
	disque.height = 0.035
	disque.radial_segments = 28
	disque.rings = 1
	# liseré blanc : un disque un peu plus grand, juste derrière
	var cercle: CylinderMesh = CylinderMesh.new()
	cercle.top_radius = R_DISQUE + 0.06
	cercle.bottom_radius = R_DISQUE + 0.06
	cercle.height = 0.03
	cercle.radial_segments = 28
	cercle.rings = 1
	var m_cercle: StandardMaterial3D = StandardMaterial3D.new()
	m_cercle.albedo_color = Color(0.96, 0.96, 0.94)
	m_cercle.roughness = 0.5
	var m_pot: StandardMaterial3D = StandardMaterial3D.new()
	m_pot.albedo_color = Color(0.35, 0.36, 0.38)
	m_pot.roughness = 0.7
	var par_couleur: Dictionary = {}          # couleur → [[xf poteau, xf disque], …]
	var textes: Array = []                    # [position, normale, nom, couleur, n° de balise, piste]
	# Au SOMMET d'un piquet de bord de piste sur trois, du côté droit en
	# descendant ; numéros DÉCROISSANTS vers la plaine (le plus grand en haut,
	# 1 en bas) — Kevin, 09/10/2026 : « les panneaux c'est décroissant vers le
	# bas, et ça ne flotte pas en lévitation : sur les piquets de bord de
	# piste, tous les 3 piquets un panneau au sommet ». Le sens d'un tracé OSM
	# n'est pas garanti : la descente se lit à l'altitude de ses deux bouts.
	for ip in _piquets:
		var c: int = PistesDonnees.PISTES[ip][1]
		var nom: String = PistesDonnees.PISTES[ip][0]
		if c < 0 or nom == "":
			continue
		var pts: PackedVector2Array = _axes[ip]
		var h0: float = relief.hauteur_sol(pts[0].x, pts[0].y)
		var h1: float = relief.hauteur_sol(pts[pts.size() - 1].x, pts[pts.size() - 1].y)
		var descend: bool = h0 >= h1          # l'axe va-t-il vers le bas ?
		# droite en descendant : nrm (+) si l'axe descend, sinon l'autre côté
		var cote: Array = _piquets[ip][1 if descend else 0]
		var ordre: Array = cote.duplicate()
		if not descend:
			ordre.reverse()
		var choisis: Array = []
		for k in range(ordre.size()):
			if k % 3 == 1:
				choisis.append(ordre[k])
		var total: int = choisis.size()
		for k in range(total):
			var pied: Vector3 = choisis[k][0]
			var t: Vector2 = choisis[k][1]
			var t_desc: Vector2 = t if descend else -t
			# le disque fait face au skieur qui descend (normale vers l'amont)
			var nz: Vector3 = Vector3(-t_desc.x, 0.0, -t_desc.y)
			var nx: Vector3 = Vector3.UP.cross(nz).normalized()
			var base: Basis = Basis(nx, Vector3.UP, nz)
			var centre: Vector3 = pied + Vector3.UP * (H_JALON + R_DISQUE * 0.85)
			if not par_couleur.has(c):
				par_couleur[c] = []
			(par_couleur[c] as Array).append([
				Transform3D(Basis.IDENTITY, pied + Vector3.UP * (H_JALON * 0.5)),
				Transform3D(base * Basis(Vector3.RIGHT, PI * 0.5), centre),
				Transform3D(base * Basis(Vector3.RIGHT, PI * 0.5), centre - nz * 0.012)])
			textes.append([centre, nz, nom, c, total - k, ip])
	for c in par_couleur:
		var xs: Array = par_couleur[c]
		for k in range(1, 3):        # le piquet de bord de piste sert de poteau
			var mm: MultiMesh = MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = [poteau, disque, cercle][k]
			mm.instance_count = xs.size()
			for i in range(xs.size()):
				mm.set_instance_transform(i, xs[i][k])
			var mi: MultiMeshInstance3D = MultiMeshInstance3D.new()
			mi.name = "Panneaux%s" % ["Poteaux", "Disques", "Cercles"][k]
			mi.multimesh = mm
			if k == 0:
				mi.material_override = m_pot
			elif k == 2:
				mi.material_override = m_cercle
			else:
				var m: StandardMaterial3D = StandardMaterial3D.new()
				m.albedo_color = COULEURS[c]
				m.roughness = 0.55
				mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 350.0
			mi.layers = 1 | Cabin.LAYER_VOIE
			add_child(mi)
	var racine: Node3D = Node3D.new()
	racine.name = "PanneauxTextes"
	add_child(racine)
	# faces : une texture par piste (nom en arc + TIGNES), posée en quad sur
	# chaque panneau de la piste ; au centre, le numéro de balise (Label3D)
	var par_piste: Dictionary = {}            # ip → [nom, couleur, [Transform3D…]]
	for e in textes:
		var pos: Vector3 = e[0]
		var nz: Vector3 = e[1]
		var nx: Vector3 = Vector3.UP.cross(nz).normalized()
		var ip2: int = e[5]
		if not par_piste.has(ip2):
			par_piste[ip2] = [e[2], e[3], []]
		(par_piste[ip2][2] as Array).append(Transform3D(Basis(nx, Vector3.UP, nz), pos + nz * 0.021))
		var l: Label3D = Label3D.new()
		l.text = str(e[4])
		l.font_size = 160
		l.pixel_size = 0.0028
		l.modulate = Color.WHITE
		l.outline_size = 0
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		l.visibility_range_end = 350.0
		l.layers = 1 | Cabin.LAYER_VOIE
		l.transform = Transform3D(Basis(nx, Vector3.UP, nz), pos + nz * 0.026)
		racine.add_child(l)
		n_panneaux += 1
	if DisplayServer.get_name() != "headless":
		_faces_panneaux.call_deferred(par_piste)


## Dessine les faces (une SubViewport par piste, rendue une fois, copiée en
## texture puis libérée) et les pose en MultiMesh, une par piste.
func _faces_panneaux(par_piste: Dictionary) -> void:
	var px: int = 192 if OS.has_feature("web") else 256
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(2.0 * (R_DISQUE + 0.06), 2.0 * (R_DISQUE + 0.06))
	var lot: Array = []
	for ip in par_piste:
		var sv: SubViewport = SubViewport.new()
		sv.size = Vector2i(px, px)
		sv.transparent_bg = true
		sv.disable_3d = true
		sv.render_target_update_mode = SubViewport.UPDATE_ONCE
		var f: PanneauPiste = PanneauPiste.new()
		f.nom = String(par_piste[ip][0])
		f.couleur = COULEURS[int(par_piste[ip][1])]
		# la station de la piste (Kevin, 09/10/2026 : « sur le domaine de Val
		# d'Isère, tu mets Val d'Isère sur tes panneaux, pas Tignes »)
		f.station = "VAL D'ISÈRE" if StationsPistes.VAL_DISERE.has(int(ip)) else "TIGNES"
		f.size = Vector2(px, px)
		sv.add_child(f)
		add_child(sv)
		lot.append([ip, sv])
		if lot.size() >= 24:
			await _poser_faces(lot, par_piste, quad)
			lot = []
	if not lot.is_empty():
		await _poser_faces(lot, par_piste, quad)


func _poser_faces(lot: Array, par_piste: Dictionary, quad: QuadMesh) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for e in lot:
		var sv: SubViewport = e[1]
		var img: Image = sv.get_texture().get_image()
		sv.queue_free()
		if img == null or img.is_empty():
			continue
		img.generate_mipmaps()
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_texture = ImageTexture.create_from_image(img)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.roughness = 0.5
		var xs: Array = par_piste[e[0]][2]
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = quad
		mm.instance_count = xs.size()
		for i in range(xs.size()):
			mm.set_instance_transform(i, xs[i])
		var mi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mi.name = "PanneauxFaces"
		mi.multimesh = mm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 350.0
		mi.layers = 1 | Cabin.LAYER_VOIE
		add_child(mi)


## Piste sous le skieur : [nom, couleur] ("", −1 hors piste). Recalculé
## deux fois par seconde.
func piste_sous(p: Vector3, delta: float) -> Array:
	_t_piste -= delta
	if _t_piste > 0.0:
		return _piste
	_t_piste = 0.5
	var q: Vector2 = Vector2(p.x, p.z)
	var best: float = PistesDonnees.LARGEUR * 0.5 + 6.0
	_piste = ["", -1]
	for k in range(_axes.size()):
		if not (_cadres[k] as Rect2).has_point(q):
			continue
		var pts: PackedVector2Array = _axes[k]
		for i in range(pts.size() - 1):
			var c: Vector2 = Geometry2D.get_closest_point_to_segment(q, pts[i], pts[i + 1])
			var d: float = c.distance_to(q)
			if d < best:
				best = d
				_piste = [PistesDonnees.PISTES[k][0], PistesDonnees.PISTES[k][1]]
	return _piste


## À chaque image, skieur chaussé : départ du fantôme, chrono, arrivée.
func suivre(sk: SkieurJoueur, delta: float) -> void:
	if fantome == null or sk == null:
		return
	var q: Vector2 = Vector2(sk.global_position.x, sk.global_position.z)
	if chrono >= 0.0:
		chrono += delta
		if q.length() < R_ARRIVEE:
			var dt: float = chrono - fantome.duree
			resultat = "Arrivée : %s — fantôme %s (%s)" % [_mmss(chrono), _mmss(fantome.duree),
				("%+.0f s" % dt) if absf(dt) >= 1.0 else "à égalité"]
			chrono = -1.0
		elif chrono > fantome.duree + 900.0:
			chrono = -1.0                  # abandon
		return
	if not sk.chausse or sk.vitesse_ski() < 0.8:
		return
	for k in range(FantomesDonnees.DESCENTES.size()):
		var f: Array = FantomesDonnees.DESCENTES[k][1]
		if Vector2(f[0], f[1]).distance_to(q) < R_DEPART:
			fantome.demarrer(k)
			chrono = 0.0
			resultat = ""
			return


## Points (monde) d'une descente réelle, pour le pilote à ski (bancs, mode
## AUTO) : un tous les `pas` points (secondes).
func chemin_descente(k: int, pas: int = 3) -> Array:
	var out: Array = []
	var pts: PackedVector2Array = FantomesDonnees.points(k)
	var i: int = 0
	while i < pts.size():
		out.append(Vector3(pts[i].x, relief.hauteur_sol(pts[i].x, pts[i].y), pts[i].y))
		i += pas
	out.append(Vector3(pts[pts.size() - 1].x, 0.0, pts[pts.size() - 1].y))
	return out


static func _mmss(t: float) -> String:
	return "%d min %02d s" % [int(t) / 60, int(t) % 60]
