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
const R_DISQUE: float = 0.45
var n_panneaux: int = 0
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


## Panneaux ronds : poteaux et disques en MultiMesh par couleur, le texte en
## Label3D (deux par panneau), visibles à 350 m.
func _construire_panneaux() -> void:
	var poteau: CylinderMesh = CylinderMesh.new()
	poteau.top_radius = 0.035
	poteau.bottom_radius = 0.04
	poteau.height = H_POTEAU
	poteau.radial_segments = 6
	poteau.rings = 1
	var disque: CylinderMesh = CylinderMesh.new()
	disque.top_radius = R_DISQUE
	disque.bottom_radius = R_DISQUE
	disque.height = 0.035
	disque.radial_segments = 28
	disque.rings = 1
	var m_pot: StandardMaterial3D = StandardMaterial3D.new()
	m_pot.albedo_color = Color(0.35, 0.36, 0.38)
	m_pot.roughness = 0.7
	var par_couleur: Dictionary = {}          # couleur → [[xf poteau, xf disque], …]
	var textes: Array = []                    # [position, normale, nom, couleur]
	for ip in range(PistesDonnees.PISTES.size()):
		var c: int = PistesDonnees.PISTES[ip][1]
		var nom: String = PistesDonnees.PISTES[ip][0]
		if c < 0 or nom == "":
			continue
		var pts: PackedVector2Array = _axes[ip]
		var reste: float = 12.0
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var l: float = a.distance_to(b)
			if l < 1e-3:
				continue
			var t: Vector2 = (b - a) / l
			var nrm: Vector2 = Vector2(-t.y, t.x)          # la droite en descendant
			var u: float = reste
			while u < l:
				var q: Vector2 = a + t * u + nrm * (PistesDonnees.LARGEUR * 0.5 + 1.5)
				if relief.dans_le_bloc(q.x, q.y):
					var y: float = relief.hauteur_sol(q.x, q.y)
					var pied: Vector3 = Vector3(q.x, y, q.y)
					# le disque fait face au skieur qui descend (normale −t)
					var nz: Vector3 = Vector3(-t.x, 0.0, -t.y)
					var nx: Vector3 = Vector3.UP.cross(nz).normalized()
					var base: Basis = Basis(nx, Vector3.UP, nz)
					if not par_couleur.has(c):
						par_couleur[c] = []
					(par_couleur[c] as Array).append([
						Transform3D(Basis.IDENTITY, pied + Vector3.UP * (H_POTEAU * 0.5)),
						Transform3D(base * Basis(Vector3.RIGHT, PI * 0.5), pied + Vector3.UP * (H_POTEAU + R_DISQUE))])
					textes.append([pied + Vector3.UP * (H_POTEAU + R_DISQUE), nz, nom, c])
				u += PAS_PANNEAU
			reste = u - l
	for c in par_couleur:
		var xs: Array = par_couleur[c]
		for k in range(2):
			var mm: MultiMesh = MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = poteau if k == 0 else disque
			mm.instance_count = xs.size()
			for i in range(xs.size()):
				mm.set_instance_transform(i, xs[i][k])
			var mi: MultiMeshInstance3D = MultiMeshInstance3D.new()
			mi.name = "Panneaux%s" % ("Poteaux" if k == 0 else "Disques")
			mi.multimesh = mm
			if k == 0:
				mi.material_override = m_pot
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
	for e in textes:
		var pos: Vector3 = e[0]
		var nz: Vector3 = e[1]
		var nx: Vector3 = Vector3.UP.cross(nz).normalized()
		var nom: String = e[2]
		for k in range(2):
			var l: Label3D = Label3D.new()
			l.text = "TIGNES" if k == 0 else nom.to_upper()
			l.font_size = 48 if k == 0 else 72
			# le nom tient dans le disque (0,78 m) quelle que soit sa longueur
			var larg: float = float(maxi(nom.length(), 4)) * 0.58 * 72.0
			l.pixel_size = 0.0022 if k == 0 else minf(0.0036, 0.78 / larg)
			l.modulate = Color.WHITE
			l.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
			l.outline_size = 8
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
			l.visibility_range_end = 350.0
			l.layers = 1 | Cabin.LAYER_VOIE
			l.transform = Transform3D(Basis(nx, Vector3.UP, nz),
				pos + nz * 0.025 + Vector3.UP * (0.22 if k == 0 else -0.08))
			racine.add_child(l)
		n_panneaux += 1


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
