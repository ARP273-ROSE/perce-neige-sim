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
	"assise_bleue": [Color(0.10, 0.24, 0.55), 0.8, 0.0],
	"assise_noire": [Color(0.06, 0.06, 0.07), 0.8, 0.0],
	"assise_grise": [Color(0.33, 0.34, 0.36), 0.85, 0.0],
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
static func tube(parent: Node3D, pts: PackedVector3Array, r: float, m: String, seg: int = 10) -> MeshInstance3D:
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
			a.append([pts[i] + nrm * r, nrm])
		anneaux.append(a)
	for i in range(n - 1):
		for k in range(seg):
			var p00: Array = anneaux[i][k]
			var p01: Array = anneaux[i][k + 1]
			var p10: Array = anneaux[i + 1][k]
			var p11: Array = anneaux[i + 1][k + 1]
			for p in [p00, p10, p11, p00, p11, p01]:
				st.set_normal(p[1])
				st.add_vertex(p[0])
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, mat(m))
	return _mi(parent, mesh, Transform3D.IDENTITY, m)


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
