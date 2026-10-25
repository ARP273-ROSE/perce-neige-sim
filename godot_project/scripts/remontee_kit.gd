class_name RemonteeKit
extends RefCounted
## Kit commun des remontées mécaniques (pylônes, véhicules, lignes) :
## matériaux partagés et primitives (boîte, cylindre, tube cintré, galet).
## Tout est posé dans le repère LOCAL du parent : X en travers de la ligne,
## Y vers le haut, −Z vers l'amont.

static var _mats: Dictionary = {}

const COULEURS: Dictionary = {
	"galva": [Color(0.70, 0.72, 0.74), 0.45, 0.85],
	"peinture_gris": [Color(0.62, 0.64, 0.66), 0.55, 0.30],      # pylônes Doppelmayr / Poma
	"peinture_anthracite": [Color(0.20, 0.21, 0.23), 0.55, 0.30],
	"acier": [Color(0.48, 0.50, 0.52), 0.35, 0.90],
	"acier_noir": [Color(0.09, 0.09, 0.10), 0.45, 0.60],
	"caoutchouc": [Color(0.05, 0.05, 0.05), 0.85, 0.0],
	"beton": [Color(0.66, 0.65, 0.62), 0.95, 0.0],
	"jaune_securite": [Color(0.95, 0.75, 0.08), 0.6, 0.1],
	"rouge_ressort": [Color(0.72, 0.10, 0.08), 0.5, 0.3],
	"jaune_ressort": [Color(0.92, 0.78, 0.10), 0.5, 0.3],
	"bleu_ressort": [Color(0.12, 0.30, 0.72), 0.5, 0.3],
	"assise_bleue": [Color(0.10, 0.26, 0.58), 0.62, 0.0],
	"assise_noire": [Color(0.13, 0.13, 0.15), 0.62, 0.0],          # garniture synthétique, pas un aplat noir
	"assise_grise": [Color(0.36, 0.37, 0.40), 0.70, 0.0],
	"coque_siege": [Color(0.22, 0.23, 0.25), 0.45, 0.15],      # coque plastique du dossier, bac d'assise
	"cable": [Color(0.30, 0.30, 0.30), 0.40, 0.85],
	"caillebotis": [Color(0.55, 0.57, 0.58), 0.6, 0.7],
	"blanc_plaque": [Color(0.94, 0.94, 0.92), 0.6, 0.0],
	"cabine_rouge": [Color(0.72, 0.07, 0.10), 0.35, 0.35],
	"cabine_noire": [Color(0.07, 0.07, 0.08), 0.35, 0.35],
	"cabine_blanche": [Color(0.92, 0.93, 0.94), 0.35, 0.30],
	"cabine_bleue": [Color(0.08, 0.28, 0.62), 0.35, 0.35],
	"joint": [Color(0.04, 0.04, 0.04), 0.9, 0.0],
	# d'après photos de lignes Doppelmayr (Commons, Bürserberg 2024) :
	"galva_pylone": [Color(0.66, 0.68, 0.69), 0.55, 0.75],     # acier galvanisé brut, mat
	"galva_patine": [Color(0.55, 0.53, 0.48), 0.75, 0.55],     # flasques ternies, rouille légère
	"garniture": [Color(0.80, 0.78, 0.70), 0.70, 0.0],         # garniture de galet claire
	"moyeu": [Color(0.74, 0.75, 0.76), 0.30, 0.85],            # jante alu
	"moyeu_rouge": [Color(0.70, 0.12, 0.12), 0.45, 0.30],
	"plaque_bleue": [Color(0.06, 0.30, 0.68), 0.5, 0.1],
	"jaune_poulie": [Color(0.93, 0.68, 0.06), 0.45, 0.25],      # poulie de demi-tour (photo Commons)
	# pince D-Line (photos Commons, maquettes Doppelmayr Wolfurt / Valiserabahn)
	"alu_pince": [Color(0.72, 0.73, 0.74), 0.38, 0.80],
	"ressort_gris": [Color(0.62, 0.64, 0.67), 0.45, 0.55],
	"polyurethane": [Color(0.93, 0.91, 0.84), 0.55, 0.0],
	"noir_mat": [Color(0.05, 0.05, 0.06), 0.80, 0.10],
	"pierre": [Color(0.52, 0.50, 0.46), 0.95, 0.0],            # moellons des cabines de conducteur
	"neige_damee": [Color(0.96, 0.97, 0.99), 0.92, 0.0],       # talus et rampes des gares
	"toit_bardeaux": [Color(0.24, 0.23, 0.22), 0.9, 0.0],
	# carénages de gare par constructeur (photos des reportages, voir GareCarenage)
	"vitrage_sombre": [Color(0.09, 0.11, 0.14), 0.12, 0.35],   # vitres vues de jour, opaques
	"toit_bleu_nuit": [Color(0.07, 0.10, 0.20), 0.35, 0.45],   # toit nervuré UNI-G (Tignes)
	"bleu_doppelmayr": [Color(0.10, 0.24, 0.62), 0.45, 0.15],
	"toit_noir": [Color(0.05, 0.05, 0.06), 0.30, 0.40],        # voûte Poma / Ingélo
	"rouge_val": [Color(0.74, 0.07, 0.09), 0.45, 0.15],        # liseré Val d'Isère
	"mousse_rouge": [Color(0.82, 0.14, 0.08), 0.85, 0.0],      # protections des poteaux
	"bois_meleze": [Color(0.56, 0.36, 0.19), 0.80, 0.0],       # bardage des gares de télécabine
	"crepi": [Color(0.86, 0.84, 0.79), 0.95, 0.0],
	# téléskis (photos Commons : Poma, Doppelmayr, enrouleurs)
	"orange_perche": [Color(0.95, 0.40, 0.06), 0.55, 0.05],
	"vert_treillis": [Color(0.08, 0.36, 0.30), 0.55, 0.30],     # portiques Doppelmayr
	"filet_bleu": [Color(0.12, 0.34, 0.82), 0.85, 0.0],
	"mousse_jaune": [Color(0.92, 0.88, 0.22), 0.85, 0.0],
	"bois_vert": [Color(0.24, 0.40, 0.33), 0.85, 0.0],          # cabane du perchman
	"tapis_vert": [Color(0.16, 0.42, 0.20), 0.90, 0.0],
	"feu_vert": [Color(0.10, 0.85, 0.25), 0.30, 0.0],
	# gares de l'Olympique (vidéos de la ligne) : chalet aval, gare amont
	"toit_brun": [Color(0.30, 0.22, 0.17), 0.85, 0.0],
	"bois_fonce": [Color(0.36, 0.22, 0.14), 0.85, 0.0],
	"panneau_solaire": [Color(0.08, 0.10, 0.16), 0.25, 0.6],
}


static func mat(nom: String) -> StandardMaterial3D:
	if _mats.has(nom):
		return _mats[nom]
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.resource_name = "remontee_" + nom
	if nom == "vitre":
		m.albedo_color = Color(0.55, 0.68, 0.74, 0.35)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.05
		m.metallic = 0.4
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif nom == "vitre_bleue":
		m.albedo_color = Color(0.10, 0.42, 0.62, 0.62)   # vitrage bleuté (Grande Motte)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.04
		m.metallic = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif nom == "vitre_bleu_clair":
		m.albedo_color = Color(0.42, 0.66, 0.80, 0.50)   # vitrage bleuté clair (Olympique, vidéos)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.04
		m.metallic = 0.4
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif nom == "vitre_teintee":
		m.albedo_color = Color(0.20, 0.21, 0.23, 0.55)  # polycarbonate gris (Omega)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.04
		m.metallic = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif nom == "bulle":
		m.albedo_color = Color(0.62, 0.45, 0.25, 0.42)    # polycarbonate fumé orangé
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.08
		m.metallic = 0.2
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		var c: Array = COULEURS.get(nom, [Color(1, 0, 1), 0.5, 0.0])
		m.albedo_color = c[0]
		m.roughness = c[1]
		m.metallic = c[2]
	_mats[nom] = m
	return m


static func _mi(parent: Node3D, mesh: Mesh, xf: Transform3D, nom: String) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = nom
	mi.transform = xf
	parent.add_child(mi)
	return mi


## Boîte de dimensions `taille`, centrée en `xf`.
static func boite(parent: Node3D, taille: Vector3, xf: Transform3D, m: String) -> MeshInstance3D:
	var b: BoxMesh = BoxMesh.new()
	b.size = taille
	b.material = mat(m)
	return _mi(parent, b, xf, m)


static func boite_en(parent: Node3D, taille: Vector3, centre: Vector3, m: String) -> MeshInstance3D:
	return boite(parent, taille, Transform3D(Basis.IDENTITY, centre), m)


## Cylindre d'axe Y local (r_bas, r_haut, hauteur h), centré en `xf`.
static func cylindre(parent: Node3D, r_bas: float, r_haut: float, h: float, xf: Transform3D, m: String,
		seg: int = 16) -> MeshInstance3D:
	var c: CylinderMesh = CylinderMesh.new()
	c.bottom_radius = r_bas
	c.top_radius = r_haut
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	c.material = mat(m)
	return _mi(parent, c, xf, m)


## Barre cylindrique de a à b (repère du parent).
static func barre(parent: Node3D, a: Vector3, b: Vector3, r: float, m: String, seg: int = 8) -> MeshInstance3D:
	var l: float = a.distance_to(b)
	if l < 0.001:
		return null
	var y: Vector3 = (b - a) / l
	var x: Vector3 = y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y)
	return cylindre(parent, r, r, l, Transform3D(Basis(x, y, z), (a + b) * 0.5), m, seg)


## Barre de section rectangulaire (largeur w, épaisseur e) de a à b ; `haut`
## oriente l'épaisseur.
static func poutre(parent: Node3D, a: Vector3, b: Vector3, w: float, e: float, m: String,
		haut: Vector3 = Vector3.UP) -> MeshInstance3D:
	var l: float = a.distance_to(b)
	if l < 0.001:
		return null
	var z: Vector3 = (b - a) / l
	var x: Vector3 = haut.cross(z)
	if x.length() < 0.01:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	var y: Vector3 = z.cross(x)
	return boite(parent, Vector3(w, e, l), Transform3D(Basis(x, y, z), (a + b) * 0.5), m)


## Tube cintré : section circulaire de rayon r balayée le long de `pts`.
## `matiere` : matériau imposé (câble à torons) ; le tube reçoit alors les
## UV du shader des câbles du funiculaire : UV.x = tour autour du câble,
## UV.y = 2 × abscisse (m).
static func tube(parent: Node3D, pts: PackedVector3Array, r: float, m: String, seg: int = 10,
		matiere: Material = null) -> MeshInstance3D:
	if pts.size() < 2:
		return null
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = pts.size()
	var prec_x: Vector3 = Vector3.ZERO
	var anneaux: Array = []
	for i in range(n):
		var t: Vector3
		if i == 0:
			t = pts[1] - pts[0]
		elif i == n - 1:
			t = pts[n - 1] - pts[n - 2]
		else:
			t = pts[i + 1] - pts[i - 1]
		t = t.normalized()
		var x: Vector3
		if i == 0:
			x = t.cross(Vector3.UP if absf(t.y) < 0.95 else Vector3.RIGHT).normalized()
		else:
			x = (prec_x - t * prec_x.dot(t)).normalized()     # transport parallèle
		prec_x = x
		var y: Vector3 = t.cross(x)
		var a: Array = []
		for k in range(seg + 1):
			var ang: float = TAU * float(k) / seg
			var nrm: Vector3 = x * cos(ang) + y * sin(ang)
			a.append([pts[i] + nrm * r, nrm, float(k) / seg])
		anneaux.append(a)
	var absc: float = 0.0
	for i in range(n - 1):
		var v0: float = absc * 2.0
		absc += pts[i].distance_to(pts[i + 1])
		var v1: float = absc * 2.0
		for k in range(seg):
			var p00: Array = anneaux[i][k]
			var p01: Array = anneaux[i][k + 1]
			var p10: Array = anneaux[i + 1][k]
			var p11: Array = anneaux[i + 1][k + 1]
			for q in [[p00, v0], [p10, v1], [p11, v1], [p00, v0], [p11, v1], [p01, v0]]:
				var p: Array = q[0]
				st.set_normal(p[1])
				st.set_uv(Vector2(p[2], q[1]))
				st.add_vertex(p[0])
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, matiere if matiere != null else mat(m))
	return _mi(parent, mesh, Transform3D.IDENTITY, m)


## Câble tracteur : le shader à torons du câble du funiculaire (Fatzer 52 mm,
## 6 torons, pas 0,45 m), pas mis à l'échelle du diamètre (mm) ; sa phase
## (`cable_phase`, m) fait défiler les torons à la vitesse du câble (retour
## d'utilisateur, 23/10/2026 : « le câble tracteur est le même que celui du funi »).
static func materiau_cable_tracteur(diametre_mm: float) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = load("res://scripts/cable_shader.gdshader")
	m.set_shader_parameter("cut_below_s", -1.0)
	m.set_shader_parameter("cable_phase", 0.0)
	m.set_shader_parameter("strand_pitch", 0.45 * diametre_mm / 52.0)
	return m


## Arc de cercle (pour tube) : centre c, dans le plan (u, v), de a0 à a1.
static func arc(c: Vector3, u: Vector3, v: Vector3, r: float, a0: float, a1: float, n: int = 10) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for i in range(n + 1):
		var a: float = lerpf(a0, a1, float(i) / n)
		out.append(c + (u * cos(a) + v * sin(a)) * r)
	return out


## Galet de balancier (garniture caoutchouc sur jante acier) d'axe X local,
## rayon extérieur `r`, largeur `l`, centré en `c`.
static var _galet_mesh: ArrayMesh = null


## Galet : EXACTEMENT celui du funiculaire (RollerMesh : joues évasées en
## alliage, bande de roulement caoutchouc au fond de la gorge, moyeu à bras),
## mis à l'échelle en gardant ses proportions (retour d'utilisateur, 22/10/2026) —
## `r` est le rayon au fond de la gorge, là où appuie le câble, comme
## RollerMesh.R_BANDE ; l'axe du câble est donc à r + rayon du câble de l'axe
## du galet. Axe du galet selon X local, centre en `c`.
static func galet(parent: Node3D, c: Vector3, r: float = 0.21, _l: float = 0.0, _moyeu: String = "",
		_garniture: String = "") -> void:
	if _galet_mesh == null:
		_galet_mesh = RollerMesh.build_galet(false)
	var k: float = r / RollerMesh.R_BANDE
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = _galet_mesh
	mi.name = "Galet"
	# axe Y du maillage → X local, mise à l'échelle uniforme
	mi.transform = Transform3D(Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3(k, k, k)), c)
	parent.add_child(mi)


## Coussin : boîte aux arêtes arrondies (rayon r), taille `taille`, centrée
## en `xf`. Maillage partagé par (taille, r) ; un pas d'arrondi par arête
## (normales lissées) pour rester léger : des dizaines de sièges à l'écran.
static var _coussins: Dictionary = {}


static func coussin(parent: Node3D, taille: Vector3, xf: Transform3D, m: String, r: float = 0.04) -> MeshInstance3D:
	var cle: String = "%.3f|%.3f|%.3f|%.3f" % [taille.x, taille.y, taille.z, r]
	if not _coussins.has(cle):
		_coussins[cle] = _maillage_coussin(taille * 0.5, minf(r, minf(taille.x, minf(taille.y, taille.z)) * 0.5 - 0.001))
	var mesh: ArrayMesh = _coussins[cle]
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(m)
	mi.name = m
	mi.transform = xf
	parent.add_child(mi)
	return mi


static func _maillage_coussin(h: Vector3, r: float) -> ArrayMesh:
	# abscisses d'une face : bord, un pas sur l'arrondi, intérieur, symétrique
	var axe = func(hh: float) -> Array:
		var out: Array = [-hh, -hh + r * (1.0 - cos(PI / 4.0)), -hh + r]
		var o2: Array = out.duplicate()
		o2.reverse()
		for v in o2:
			out.append(-float(v))
		return out
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner: Vector3 = h - Vector3(r, r, r)
	# six faces : (axe normal, signe)
	for f in [[0, 1.0], [0, -1.0], [1, 1.0], [1, -1.0], [2, 1.0], [2, -1.0]]:
		var n: int = f[0]
		var sg: float = f[1]
		var u_ax: int = (n + 1) % 3
		var v_ax: int = (n + 2) % 3
		var us: Array = axe.call(h[u_ax])
		var vs: Array = axe.call(h[v_ax])
		var grille: Array = []
		for u in us:
			var ligne: Array = []
			for v in vs:
				var q: Vector3 = Vector3.ZERO
				q[n] = sg * h[n]
				q[u_ax] = u
				q[v_ax] = v
				var c: Vector3 = q.clamp(-inner, inner)
				var d: Vector3 = (q - c).normalized()
				ligne.append([c + d * r, d])
			grille.append(ligne)
		for i in range(us.size() - 1):
			for j in range(vs.size() - 1):
				var quad: Array = [grille[i][j], grille[i + 1][j], grille[i + 1][j + 1], grille[i][j + 1]]
				var tri: Array = [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]
				if sg > 0.0:          # Godot : faces avant dans le sens horaire
					tri = [quad[0], quad[2], quad[1], quad[0], quad[3], quad[2]]
				for p in tri:
					st.set_normal(p[1])
					st.add_vertex(p[0])
	return st.commit()


## Caisson lisse : section rectangulaire balayée le long de `pts` (dans un
## plan vertical) ; largeur (dans le plan de la courbe) de l0 à l1,
## épaisseur e hors du plan (selon `hors`). Pour les suspentes en caisson.
static func caisson(parent: Node3D, pts: PackedVector3Array, l0: float, l1: float, e: float, m: String,
		hors: Vector3 = Vector3.FORWARD) -> MeshInstance3D:
	var n: int = pts.size()
	if n < 2:
		return null
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var anneaux: Array = []
	for i in range(n):
		var t: Vector3 = (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var lat: Vector3 = hors.cross(t).normalized()          # dans le plan de la courbe
		var w: float = lerpf(l0, l1, float(i) / (n - 1)) * 0.5
		var c: Vector3 = pts[i]
		anneaux.append([c + lat * w + hors * e * 0.5, c - lat * w + hors * e * 0.5,
			c - lat * w - hors * e * 0.5, c + lat * w - hors * e * 0.5])
	for i in range(n - 1):
		for k in range(4):
			var a0: Vector3 = anneaux[i][k]
			var a1: Vector3 = anneaux[i][(k + 1) % 4]
			var b0: Vector3 = anneaux[i + 1][k]
			var b1: Vector3 = anneaux[i + 1][(k + 1) % 4]
			var nrm: Vector3 = (b0 - a0).cross(a1 - a0).normalized()
			var ordre: Array = [a0, b0, b1, a0, b1, a1]
			if nrm.dot((a0 + a1) * 0.5 - pts[i]) < 0.0:
				nrm = -nrm
				ordre = [a0, b1, b0, a0, a1, b1]
			# Godot : face avant dans le sens horaire vue de la normale
			if (ordre[1] - ordre[0]).cross(ordre[2] - ordre[0]).dot(nrm) > 0.0:
				ordre = [ordre[0], ordre[2], ordre[1], ordre[3], ordre[5], ordre[4]]
			for v in ordre:
				st.set_normal(nrm)
				st.add_vertex(v)
	# bouts
	for bout in [0, n - 1]:
		var r: Array = anneaux[bout]
		var nb: Vector3 = (pts[bout] - pts[1 if bout == 0 else n - 2]).normalized()
		for v in [r[0], r[1], r[2], r[0], r[2], r[3]]:
			st.set_normal(nb)
			st.add_vertex(v)
	var mesh: ArrayMesh = st.commit()
	var mt: StandardMaterial3D = (mat(m) as StandardMaterial3D).duplicate()
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mt)
	return _mi(parent, mesh, Transform3D.IDENTITY, m)


## Demi-cône ouvert par-dessous (gouttière évasée) d'axe a → b, rayon r0
## en a et r1 en b ; seule la moitié haute (+Y) est tracée, double face.
static func demi_cone(parent: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, m: String, seg: int = 10) -> MeshInstance3D:
	var ax: Vector3 = (b - a).normalized()
	var x: Vector3 = Vector3.UP.cross(ax).normalized()
	if x.length() < 0.01:
		x = Vector3.RIGHT
	var y: Vector3 = ax.cross(x).normalized()
	if y.y < 0.0:
		y = -y
		x = -x
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(seg):
		var t0: float = PI * float(k) / seg
		var t1: float = PI * float(k + 1) / seg
		var d0: Vector3 = x * cos(t0) + y * sin(t0)
		var d1: Vector3 = x * cos(t1) + y * sin(t1)
		for q in [[a + d0 * r0, d0], [b + d0 * r1, d0], [b + d1 * r1, d1], [a + d0 * r0, d0], [b + d1 * r1, d1], [a + d1 * r0, d1]]:
			st.set_normal(q[1])
			st.add_vertex(q[0])
	var mesh: ArrayMesh = st.commit()
	var mt: StandardMaterial3D = (mat(m) as StandardMaterial3D).duplicate()
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mt)
	return _mi(parent, mesh, Transform3D.IDENTITY, m)


## Ressort hélicoïdal d'axe `axe` (unitaire), de longueur `l`.
static func ressort(parent: Node3D, base: Vector3, axe: Vector3, l: float, r: float, rf: float, spires: int, m: String) -> void:
	var x: Vector3 = axe.cross(Vector3.UP if absf(axe.y) < 0.9 else Vector3.RIGHT).normalized()
	var y: Vector3 = axe.cross(x)
	var pts: PackedVector3Array = PackedVector3Array()
	var n: int = spires * 12
	for i in range(n + 1):
		var t: float = float(i) / n
		var a: float = TAU * spires * t
		pts.append(base + axe * (l * t) + (x * cos(a) + y * sin(a)) * r)
	tube(parent, pts, rf, m, 6)
