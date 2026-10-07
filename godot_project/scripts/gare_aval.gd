class_name GareAval
extends Node3D
## Gare AVAL (Val Claret) telle que réaménagée en 2018 (STGM, architecte ICM
## Architectures) — refonte du 07/10/2026 à la demande de Kevin : « refais
## complet le design extérieur de la gare aval […] et si tu arrives à
## interpréter les photos de la salle d'attente et des portes coulissantes
## entre celle-ci et le quai, tu la modélises ».
##
## Sources (relevé du 07/10/2026, détail dans SOURCES.md, ligne 24g) :
##  - emprises et hauteurs : IGN BD TOPO V3 (bâtiment 42744420 = hall,
##    403 m², 6,4 m ; bâtiment 2729829 = arches et auvent d'entrée) ; LiDAR
##    HD IGN (toit plat à 2115 m, sommet de l'arche rouge à 2119,75 m) ;
##    orthophoto IGN du 23/08/2024 (toit en herbe, arches) ;
##  - photos de Kevin du 26/04/2026 (093457 à 093522 : salle d'attente,
##    cloison vitrée, portes, balustrade, panneau des départs) ;
##  - photos d'ICM Architectures (façade « DESTINATION GLACIER », arches,
##    escalier, 2018) ; vidéo de descente de 2013 (fosse, vue du quai).
##
## Repère local de la gare : origine sur l'axe de la voie à s = 0, au niveau
## du sol du hall (axe du tunnel − 1,10 m, ≈ 2109,9 m ; LiDAR : 2109,1-2109,4),
## X vers l'EST, Z vers le NORD (s'éloigne du quai), Y vers le haut. Les
## emprises IGN (précision 3 m) sont recalées pour que la cloison vitrée soit
## centrée sur la voie, perpendiculaire à elle.
##
## INCONNUS (valeurs du simulateur, pas des données) : la façade ouest et
## le mur nord (non photographiés, bardage bois supposé) ; la place exacte
## des colonnes, bancs, écrans et du comptoir dans la salle ; le sens
## d'ouverture des vantaux (deux vantaux qui s'écartent, supposé) ; le
## rayon des petites arches (6,2 m, déduit du LiDAR) et l'écart entre
## arches (2,35 m).

const H_SOL: float = -1.10          # sol du hall sous l'axe du tunnel à s = 0
const H_TOIT: float = 6.0           # dessus du toit (LiDAR 2115 m)
const H_PLAFOND: float = 4.15       # plafond « origami » : 3,4 → 4,1 m
const H_PLACE_ABS: float = 2107.6   # place devant l'escalier (LiDAR)
# emprise du hall (BD TOPO 42744420, repère local) ; les deux premiers
# sommets sont la cloison vitrée, ± 5,6 m de part et d'autre de la voie
const HALL: Array = [Vector2(5.6, 0.0), Vector2(-5.6, 0.0), Vector2(-10.89, 4.40),
	Vector2(-11.74, 13.80), Vector2(-13.87, 17.23), Vector2(-2.58, 20.68),
	Vector2(-4.49, 26.41), Vector2(6.06, 28.58)]
const FACADE_A: Vector2 = Vector2(-13.87, 17.23)    # façade d'entrée (vers le NNO)
const FACADE_B: Vector2 = Vector2(-2.58, 20.68)
# auvent et arches (BD TOPO 2729829)
const AUVENT: Array = [Vector2(-13.87, 17.23), Vector2(-14.54, 19.69), Vector2(-15.6, 22.82),
	Vector2(-4.49, 26.41), Vector2(-4.02, 25.11), Vector2(-2.58, 20.68)]
const ARCHE_D: float = 10.1         # arche rouge : à 10,1 m devant la façade
const ARCHE_DECALAGE: float = 0.84  # axe des arches décalé vers l'est
const LARGEUR_ESCALIER: float = 11.5
const GIRON: float = 0.33

var tunnel: TunnelBuilder = null
var _o: Vector3 = Vector3.ZERO      # origine (monde)
var _e: Vector3 = Vector3.RIGHT     # est
var _n: Vector3 = Vector3.FORWARD   # nord
var _mats: Dictionary = {}
var _vantaux: Array = []            # [nœud, position fermée, sens]
var _ouverture: float = 0.0
var _panneau: Array = []            # lignes du panneau des départs (Label3D)
var _t_panneau: float = 0.0
var _page: int = 0


func construire(t: TunnelBuilder) -> void:
	tunnel = t
	var xf: Transform3D = tunnel.transform_at(0.0)
	_e = -xf.basis.x
	_e.y = 0.0
	_e = _e.normalized()
	_n = xf.basis.z
	_n.y = 0.0
	_n = _n.normalized()
	_o = xf.origin + Vector3(0.0, H_SOL, 0.0)
	_materiaux()
	_hall()
	_plafond()
	_cloison()
	_balustrade()
	_mobilier()
	_facade()
	_auvent()
	_arches()
	_escalier()
	_lumieres()
	_voyageurs()
	# ~550 boîtes, barres et lames : fusionnées par matériau (quelques
	# appels de dessin, cf. MeshMerge) ; les vantaux restent mobiles
	var garder: Array = []
	for v in _vantaux:
		garder.append(v[0])
	MeshMerge.merge(self, garder, "GareAval")
	# éclairée en vue extérieure par la lumière de jour de cette vue (qui
	# n'éclaire que les rames et la voie)
	Cabin.tag_layer(self, Cabin.LAYER_VOIE)


## Point local (x est, z nord, y au-dessus du sol du hall) → monde.
func _p(x: float, z: float, y: float = 0.0) -> Vector3:
	return _o + _e * x + _n * z + Vector3(0.0, y, 0.0)


func _p2(v: Vector2, y: float = 0.0) -> Vector3:
	return _p(v.x, v.y, y)


# --- matériaux --------------------------------------------------------------

func _mat(nom: String, c: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[nom] = m
	return m


## Bardage à claire-voie : lames verticales de bois clair de 4 cm, jours de
## 2 cm sur fond sombre (photos ICM 2018 et salle d'attente) — texture d'une
## période répétée tous les 6 cm (UV en mètres).
func _mat_lames(nom: String, bois: Color, jour: Color) -> StandardMaterial3D:
	var img: Image = Image.create(16, 2, false, Image.FORMAT_RGB8)
	for i in range(16):
		var c: Color = bois if i < 11 else jour
		if i < 11:
			c = c.darkened(0.06 * absf(i - 5.0) / 5.0)   # léger galbe de la lame
		img.set_pixel(i, 0, c)
		img.set_pixel(i, 1, c)
	# mipmaps : de loin les lames se fondent en leur teinte moyenne (sans
	# elles, moiré) ; filtrage anisotrope pour les murs vus en biais
	img.generate_mipmaps()
	var m: StandardMaterial3D = _mat(nom, Color.WHITE, 0.85)
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.uv1_scale = Vector3(1.0 / 0.06, 1.0, 1.0)
	return m


func _materiaux() -> void:
	_mat_lames("bardage", Color("b08d61"), Color("1b110c"))
	_mat_lames("lames_int", Color("c5a06b"), Color("3a2a1c"))
	_mat("blanc", Color("ece8e0"), 0.9)
	_mat("sol", Color("2b3044"), 0.95)
	_mat("toit", Color("5e6b3e"), 1.0)
	_mat("marine", Color("2b2e45"), 0.5, 0.2)
	_mat("rouge", Color("8c2531"), 0.55)
	_mat("rouge_bandeau", Color("b5303d"), 0.6)
	_mat("lamelle", Color("974c23"), 0.6)
	_mat("noir", Color("18181a"), 0.5, 0.4)
	_mat("galva", Color("a9adb0"), 0.35, 0.7)
	_mat("beton", Color("8e8e8a"), 0.9)
	_mat("gris_poteau", Color("7f8285"), 0.5, 0.3)
	_mat("anthracite", Color("3a3b3e"), 0.85, 0.2)
	_mat("bois_massif", Color("a8794a"), 0.7)
	_mat("colonne", Color("9a7549"), 0.75)
	var p: StandardMaterial3D = _mat("plafond", Color("efe6d2"), 0.9)
	p.emission_enabled = true                      # éclairage LED indirect
	p.emission = Color("efe0c0") * 0.35
	var v: StandardMaterial3D = _mat("verre", Color(0.80, 0.90, 0.95, 0.16), 0.05, 0.2)
	v.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var vf: StandardMaterial3D = _mat("verre_fonce", Color(0.10, 0.12, 0.15, 0.80), 0.1, 0.3)
	vf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var led: StandardMaterial3D = _mat("led", Color("fff2d6"), 0.5)
	led.emission_enabled = true
	led.emission = Color("ffe9c4")
	led.emission_energy_multiplier = 2.5
	var ecr: StandardMaterial3D = _mat("ecran_panneau", Color("0d1a4a"), 0.4)
	ecr.emission_enabled = true
	ecr.emission = Color("102a7a")
	ecr.emission_energy_multiplier = 0.6
	var orange: StandardMaterial3D = _mat("ecran_orange", Color("d9822b"), 0.5)
	orange.emission_enabled = true
	orange.emission = Color("d9822b")
	orange.emission_energy_multiplier = 0.5
	var bleu: StandardMaterial3D = _mat("ecran_bleu", Color("6f9fd6"), 0.5)
	bleu.emission_enabled = true
	bleu.emission = Color("8fb8e8")
	bleu.emission_energy_multiplier = 0.5


# --- primitives ---------------------------------------------------------------

func _instance(mesh: Mesh, nom: String) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = nom
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Boîte de taille (lx, ly, lz) dans le repère local, centrée en (x, z, y).
func _boite(m: String, lx: float, ly: float, lz: float, x: float, z: float, y: float,
		rot_y: float = 0.0, nom: String = "") -> MeshInstance3D:
	var b: BoxMesh = BoxMesh.new()
	b.size = Vector3(lx, ly, lz)
	b.material = _mats[m]
	var mi: MeshInstance3D = _instance(b, nom if nom != "" else m)
	# repère direct (x est, y haut, z SUD) : en (est, haut, nord) il serait en
	# miroir et MeshMerge ne le fusionnerait pas ; même orientation des
	# boîtes avec la rotation inversée
	mi.transform = Transform3D(_base() * Basis(Vector3.UP, -rot_y), _p(x, z, y))
	return mi


func _base() -> Basis:
	return Basis(_e, Vector3.UP, -_n)


## Barre de section carrée `c` de a à b (monde).
func _barre(m: String, a: Vector3, b: Vector3, c: float) -> void:
	var l: float = a.distance_to(b)
	if l < 0.01:
		return
	var bx: BoxMesh = BoxMesh.new()
	bx.size = Vector3(c, c, l)
	bx.material = _mats[m]
	var mi: MeshInstance3D = _instance(bx, m)
	mi.transform = Transform3D(Basis.looking_at(b - a, Vector3.UP if absf((b - a).normalized().y) < 0.99 else _n),
		(a + b) * 0.5)


func _cylindre(m: String, r: float, h: float, base: Vector3, seg: int = 16) -> MeshInstance3D:
	var c: CylinderMesh = CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	c.material = _mats[m]
	var mi: MeshInstance3D = _instance(c, m)
	mi.position = base + Vector3(0.0, h * 0.5, 0.0)
	return mi


## Quadrilatère a-b-c-d (monde) avec UV en mètres (u le long de a→b, v
## vers le haut).
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var l: float = a.distance_to(b)
	var h: float = a.distance_to(d)
	for e in [[a, Vector2(0, h)], [b, Vector2(l, h)], [c, Vector2(l, 0)],
			[a, Vector2(0, h)], [c, Vector2(l, 0)], [d, Vector2(0, 0)]]:
		st.set_uv(e[1])
		st.add_vertex(e[0])


func _polygone(m: String, pts: Array, y: float, nom: String, uv_echelle: float = 1.0) -> void:
	var poly: PackedVector2Array = PackedVector2Array(pts)
	var idx: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		st.set_uv(poly[i] * uv_echelle)
		st.add_vertex(_p2(poly[i], y))
	st.generate_normals()
	st.set_material(_mats[m])
	_instance(st.commit(), nom)


# --- hall : sol, toit, murs ----------------------------------------------------

func _hall() -> void:
	_polygone("sol", HALL, 0.0, "SolHall")
	_polygone("noir", HALL, H_PLAFOND + 0.30, "FondPlafond")   # vu entre les facettes
	_polygone("toit", HALL, H_TOIT, "ToitHerbe", 0.5)          # toit végétalisé (orthophoto)
	var st_ext: SurfaceTool = SurfaceTool.new()
	st_ext.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_bas: SurfaceTool = SurfaceTool.new()
	st_bas.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_haut: SurfaceTool = SurfaceTool.new()
	st_haut.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = HALL.size()
	for i in range(n):
		var a: Vector2 = HALL[i]
		var b: Vector2 = HALL[(i + 1) % n]
		if i == 0:
			continue                     # cloison vitrée (_cloison)
		var facade: bool = a == FACADE_A and b == FACADE_B
		# parement extérieur (bardage), un peu à l'extérieur du mur
		var dir: Vector2 = (b - a).normalized()
		var dehors: Vector2 = Vector2(dir.y, -dir.x)   # le polygone tourne dans le sens horaire (vu de dessus)
		if Geometry2D.is_point_in_polygon((a + b) * 0.5 + dehors * 0.5, PackedVector2Array(HALL)):
			dehors = -dehors
		var ae: Vector2 = a + dehors * 0.25
		var be: Vector2 = b + dehors * 0.25
		if not facade:
			_quad(st_ext, _p2(ae, -2.6), _p2(be, -2.6), _p2(be, H_TOIT), _p2(ae, H_TOIT))
		# parement intérieur : lames de bois jusqu'à 2,7 m, enduit blanc au-dessus
		_quad(st_bas, _p2(a, 0.0), _p2(b, 0.0), _p2(b, 2.7), _p2(a, 2.7))
		_quad(st_haut, _p2(a, 2.7), _p2(b, 2.7), _p2(b, H_PLAFOND + 0.3), _p2(a, H_PLAFOND + 0.3))
	for e in [[st_ext, "bardage", "BardageHall"], [st_bas, "lames_int", "LamesHall"],
			[st_haut, "blanc", "EnduitHall"]]:
		(e[0] as SurfaceTool).generate_normals()
		(e[0] as SurfaceTool).set_material(_mats[e[1]])
		_instance((e[0] as SurfaceTool).commit(), e[2])


## Plafond « origami » (photos 093506 / 093522) : grandes facettes crème
## inclinées, joints noirs en creux, éclairage LED indirect.
func _plafond() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var poly: PackedVector2Array = PackedVector2Array(HALL)
	var pas: float = 2.6
	var hauteur := func(i: int, j: int) -> float:
		var v: float = sin(i * 12.9898 + j * 78.233) * 43758.5453
		return 3.45 + 0.65 * (v - floor(v))
	for i in range(-6, 3):
		for j in range(0, 12):
			var x0: float = i * pas
			var z0: float = j * pas
			var q: Array = [Vector3(x0, hauteur.call(i, j), z0), Vector3(x0 + pas, hauteur.call(i + 1, j), z0),
				Vector3(x0 + pas, hauteur.call(i + 1, j + 1), z0 + pas), Vector3(x0, hauteur.call(i, j + 1), z0 + pas)]
			for tri in [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]:
				var g: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
				if not Geometry2D.is_point_in_polygon(Vector2(g.x, g.z), poly):
					continue
				for v in tri:
					var w: Vector3 = g + (v - g) * 0.96          # joints noirs
					st.add_vertex(_p(w.x, w.z, w.y))
	st.generate_normals()
	st.set_material(_mats["plafond"])
	_instance(st.commit(), "PlafondOrigami")


# --- cloison vitrée et portes coulissantes ------------------------------------

## Cloison entre la salle d'attente et le quai (photos 093457 / 093458 /
## 093500) : menuiseries bleu marine ; deux jeux de portes coulissantes
## automatiques à deux vantaux (≈ 1 m × 2,25 m, traverse vers 45 %), un au
## pied de chaque quai ; vitrine fixe de 4 m face à la fosse ; bandeau rouge
## « ALTITUDE EXPERIENCES... » ; vitrage haut ; panneau des départs.
func _cloison() -> void:
	var h_portes: float = 2.25
	var y_bandeau: float = 2.45
	var y_haut: float = 3.15
	# jusqu'au plafond de la salle du quai (axe + demi-hauteur de la salle)
	var y_fin: float = maxf(tunnel.station_room_half_height - H_SOL, 3.75)
	# piédroits et montants pleins (marine)
	for seg in [[-5.6, -4.6], [-2.5, -2.0], [2.0, 2.5], [4.6, 5.6]]:
		_boite("marine", seg[1] - seg[0], y_bandeau, 0.20, (seg[0] + seg[1]) * 0.5, 0.0, y_bandeau * 0.5)
	# mur de fond de fosse, sous le sol du hall
	_boite("marine", 11.2, 1.7, 0.25, 0.0, 0.05, -0.85, 0.0, "MurFondFosse")
	# vitrine fixe centrale : 4 vitres, traverse à 1,0 m
	_boite("verre", 4.0, y_bandeau, 0.02, 0.0, 0.0, y_bandeau * 0.5, 0.0, "Vitrine")
	for x in [-2.0, -1.0, 0.0, 1.0, 2.0]:
		_boite("marine", 0.07, y_bandeau, 0.10, x, 0.0, y_bandeau * 0.5)
	_boite("marine", 4.0, 0.07, 0.10, 0.0, 0.0, 1.0)
	_boite("marine", 4.0, 0.08, 0.12, 0.0, 0.0, 0.04)
	# deux jeux de portes, centrés à ± 3,55 m (pied de chaque quai)
	for cote in [-1.0, 1.0]:
		var xc: float = cote * 3.55
		# dormant : linteau et imposte pleine jusqu'au bandeau
		_boite("marine", 2.1, y_bandeau - h_portes, 0.20, xc, 0.0, (h_portes + y_bandeau) * 0.5)
		for k in [-1.0, 1.0]:
			var vantail: Node3D = Node3D.new()
			vantail.name = "Vantail"
			add_child(vantail)
			var x0: float = xc + k * 0.525
			vantail.position = _p(x0, 0.0, 0.0)
			vantail.basis = _base()
			_vantail(vantail, h_portes)
			_vantaux.append([vantail, x0, k])
	# « 2 » peint sur le montant de la porte de droite (côté ouest, vu du hall)
	_etiquette("2", _p(-4.55, 0.11, 1.9), 64, Color.WHITE, 0.004, _n)
	# affichette (lue sur la photo 093500)
	_etiquette("PORTES AUTOMATIQUES\nInterdiction à toute personne\nétrangère au service d'en\nactionner l'ouverture",
		_p(-3.0, 0.03, 1.55), 24, Color(0.1, 0.1, 0.12), 0.0016, _n, Color.WHITE)
	# bandeau rouge, texte côté hall
	_boite("rouge_bandeau", 11.2, y_haut - y_bandeau, 0.16, 0.0, 0.02, (y_bandeau + y_haut) * 0.5, 0.0, "Bandeau")
	_etiquette("ALTITUDE EXPERIENCES...", _p(0.0, 0.11, (y_bandeau + y_haut) * 0.5), 96, Color.WHITE, 0.0042, _n)
	# vitrage haut jusqu'au plafond de la salle du quai
	_boite("verre", 11.2, y_fin - y_haut, 0.02, 0.0, 0.0, (y_haut + y_fin) * 0.5, 0.0, "VitrageHaut")
	for x in [-5.6, -3.4, -1.1, 1.1, 3.4, 5.6]:
		_boite("marine", 0.08, y_fin - y_haut, 0.10, x, 0.0, (y_haut + y_fin) * 0.5)
	_boite("marine", 11.2, 0.10, 0.12, 0.0, 0.0, y_fin)
	# robinet d'incendie armé (enrouleur rouge, côté quai, derrière la vitrine)
	var ria: MeshInstance3D = _cylindre("rouge", 0.36, 0.22, _p(1.35, -0.45, 1.05), 20)
	ria.basis = _base() * Basis(Vector3.RIGHT, PI * 0.5)
	# panneau des départs (LED), au-dessus du bandeau, côté hall
	_boite("ecran_panneau", 1.0, 0.70, 0.08, -0.55, 0.30, y_haut + 0.42, 0.0, "PanneauDeparts")
	var lignes: Array = [[0.25, 30], [0.12, 34], [0.0, 30], [-0.12, 30], [-0.23, 30]]
	for l in lignes:
		var lab: Label3D = _etiquette("", _p(-0.55, 0.35, y_haut + 0.42 + l[0]), l[1],
			Color(0.95, 0.97, 1.0), 0.0016, _n)
		_panneau.append(lab)


## Un vantail : cadre marine, vitrage, traverse à 45 %.
func _vantail(v: Node3D, h: float) -> void:
	var l: float = 1.05
	var parts: Array = [
		["marine", Vector3(l, 0.07, 0.06), Vector3(0, h - 0.035, 0)],
		["marine", Vector3(l, 0.10, 0.06), Vector3(0, 0.05, 0)],
		["marine", Vector3(0.07, h, 0.06), Vector3(-l * 0.5 + 0.035, h * 0.5, 0)],
		["marine", Vector3(0.07, h, 0.06), Vector3(l * 0.5 - 0.035, h * 0.5, 0)],
		["marine", Vector3(l, 0.06, 0.06), Vector3(0, h * 0.45, 0)],
		["verre", Vector3(l - 0.1, h - 0.12, 0.012), Vector3(0, h * 0.5, 0)],
	]
	for pt in parts:
		var b: BoxMesh = BoxMesh.new()
		b.size = pt[1]
		b.material = _mats[pt[0]]
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = b
		mi.position = pt[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		v.add_child(mi)


## Balustrade courbe en lames de bois devant la vitrine, côté hall (ajoutée
## en 2018) : corde 4,8 m, flèche 1,5 m, 1,05 m de haut, socle en béton,
## main courante galvanisée.
func _balustrade() -> void:
	var corde: float = 4.8
	var fleche: float = 1.5
	var r: float = (corde * corde / 4.0 + fleche * fleche) / (2.0 * fleche)
	var zc: float = 0.25 + fleche - r                 # centre du cercle
	var a0: float = asin(corde * 0.5 / r)
	var n_lames: int = int(2.0 * a0 * r / 0.065)
	var prec: Vector3 = Vector3.ZERO
	for k in range(n_lames + 1):
		var a: float = lerpf(-a0, a0, float(k) / n_lames)
		var x: float = r * sin(a)
		var z: float = zc + r * cos(a)
		_boite("bois_massif", 0.04, 1.0, 0.025, x, z, 0.62, -a)
		var p: Vector3 = _p(x, z, 1.15)
		if k > 0:
			_barre("galva", prec, p, 0.06)
			_barre("beton", prec - Vector3(0, 1.08, 0), p - Vector3(0, 1.08, 0), 0.14)
		prec = p


# --- salle d'attente : mobilier ------------------------------------------------

func _mobilier() -> void:
	# colonnes rondes en bois clair (≥ 5, Ø 0,55 m) et anneau LED au plafond
	for c in [Vector2(-3.6, 8.0), Vector2(2.6, 8.5), Vector2(-8.4, 10.5),
			Vector2(-3.4, 15.5), Vector2(2.6, 17.0)]:
		_cylindre("colonne", 0.275, H_PLAFOND, _p2(c), 20)
		var anneau: TorusMesh = TorusMesh.new()
		anneau.inner_radius = 0.30
		anneau.outer_radius = 0.36
		anneau.material = _mats["led"]
		var mi: MeshInstance3D = _instance(anneau, "AnneauLED")
		mi.position = _p2(c, 3.55)
	# suspensions lumineuses en étoile (≥ 3 ; deux au-dessus de la balustrade)
	for c in [Vector2(-2.6, 1.9), Vector2(2.6, 1.9), Vector2(-5.5, 11.5)]:
		_etoile(_p2(c, 3.15))
	# bancs : poutre de bois massif sur piètements en tôle galvanisée
	for b in [[Vector2(-9.2, 7.5), 1.45], [Vector2(-9.6, 12.0), 1.45], [Vector2(0.0, 12.5), 0.0],
			[Vector2(-5.0, 17.3), 0.3]]:
		var rot: float = b[1]
		_boite("bois_massif", 1.9, 0.12, 0.36, b[0].x, b[0].y, 0.44, rot)
		for k in [-0.7, 0.7]:
			var ox: float = k * cos(rot)
			var oz: float = -k * sin(rot)
			_boite("galva", 0.05, 0.40, 0.34, b[0].x + ox, b[0].y + oz, 0.20, rot)
	# porte-skis galvanisés contre le mur ouest
	for z in [6.0, 7.2]:
		_boite("galva", 0.12, 1.1, 0.9, _x_mur_ouest(z) + 0.08, z, 0.85, -0.09)
	# trois grands écrans sur le mur ouest (webcam du glacier, signalétique)
	var ecrans: Array = ["ecran_bleu", "ecran_orange", "ecran_orange"]
	for k in range(3):
		var z: float = 8.6 + k * 1.6
		var x: float = _x_mur_ouest(z) + 0.06
		_boite("noir", 0.06, 0.72, 1.24, x, z, 1.85, -0.09)
		_boite(ecrans[k], 0.02, 0.62, 1.12, x + 0.04, z, 1.85, -0.09)
	# comptoir en bois cintré au fond de la salle
	for k in range(7):
		var a: float = -0.6 + k * 0.2
		_boite("bois_massif", 0.48, 1.05, 0.10, -1.5 + 2.2 * sin(a), 24.0 - 1.0 * cos(a), 0.525, -a)
	_boite("verre", 2.6, 0.45, 0.02, -1.5, 22.9, 1.30)


## Abscisse du mur ouest de la salle (arête 4,4 → 13,8 m de l'emprise).
func _x_mur_ouest(z: float) -> float:
	return lerpf(-10.89, -11.74, (z - 4.40) / 9.40)


func _etoile(c: Vector3) -> void:
	_barre("noir", c, c + Vector3(0, 1.0, 0), 0.01)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(c.x * 10.0)
	for k in range(22):
		var d: Vector3 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		_barre("led", c, c + d * rng.randf_range(0.35, 0.55), 0.012)


# --- extérieur : façade, auvent, arches, escalier --------------------------------

## Façade d'entrée (ICM 4994 / 4995) : vitrée en bas sous l'auvent, bardage
## de bois au-dessus jusqu'à 6,6 m, bandeau rouge avec « ECOLES DE SKI /
## SKI SCHOOLS », « ALTITUDE EXPERIENCES... », « SORTIE / EXIT », grandes
## lettres blanches « DESTINATION GLACIER ».
func _facade() -> void:
	var t: Vector2 = (FACADE_B - FACADE_A).normalized()
	var dehors: Vector2 = Vector2(-t.y, t.x)
	if Geometry2D.is_point_in_polygon((FACADE_A + FACADE_B) * 0.5 + dehors, PackedVector2Array(HALL)):
		dehors = -dehors
	var l: float = FACADE_A.distance_to(FACADE_B)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a: Vector2 = FACADE_A + dehors * 0.25
	var b: Vector2 = FACADE_B + dehors * 0.25
	_quad(st, _p2(a, 3.0), _p2(b, 3.0), _p2(b, 6.6), _p2(a, 6.6))
	# trumeaux pleins de part et d'autre de l'entrée
	_quad(st, _p2(a, 0.0), _p2(a + t * 1.6, 0.0), _p2(a + t * 1.6, 3.0), _p2(a, 3.0))
	_quad(st, _p2(b - t * 1.6, 0.0), _p2(b, 0.0), _p2(b, 3.0), _p2(b - t * 1.6, 3.0))
	st.generate_normals()
	st.set_material(_mats["bardage"])
	_instance(st.commit(), "FacadeEntree")
	# entrée vitrée (portes et vitrages fixes)
	var mil: Vector2 = (FACADE_A + FACADE_B) * 0.5 + dehors * 0.2
	var rot: float = -atan2(t.y, t.x)
	_boite("verre_fonce", l - 3.2, 2.9, 0.03, mil.x, mil.y, 1.45, rot, "EntreeVitree")
	for k in range(7):
		var f: float = lerpf(-(l - 3.2) * 0.5, (l - 3.2) * 0.5, k / 6.0)
		_boite("marine", 0.08, 2.9, 0.10, mil.x + t.x * f, mil.y + t.y * f, 1.45, rot)
	# bandeau rouge et inscriptions (vers l'extérieur)
	var m3: Vector2 = (FACADE_A + FACADE_B) * 0.5 + dehors * 0.32
	var nd: Vector3 = (_e * dehors.x + _n * dehors.y).normalized()
	_boite("rouge", l, 0.55, 0.08, m3.x, m3.y, 3.30, rot, "BandeauFacade")
	_etiquette("ALTITUDE EXPERIENCES...", _p2(m3 + dehors * 0.06, 3.30), 96, Color.WHITE, 0.0045, nd)
	_etiquette("ECOLES DE SKI\nSKI SCHOOLS", _p2(m3 - t * (l * 0.5 - 1.2) + dehors * 0.06, 3.30), 48,
		Color.WHITE, 0.0035, nd)
	_etiquette("SORTIE\nEXIT", _p2(m3 + t * (l * 0.5 - 0.7) + dehors * 0.06, 3.30), 48,
		Color.WHITE, 0.0035, nd)
	_etiquette("DESTINATION", _p2(m3 + dehors * 0.06, 5.55), 160, Color.WHITE, 0.0065, nd)
	_etiquette("GLACIER", _p2(m3 + dehors * 0.06, 4.35), 220, Color.WHITE, 0.0072, nd)


## Auvent sous les arches : sous-face en bois à 3 m, deux poteaux ronds gris.
func _auvent() -> void:
	_polygone("bois_massif", AUVENT, 3.0, "SousFaceAuvent", 0.5)
	_polygone("anthracite", AUVENT, 3.25, "DessusAuvent")
	_polygone("anthracite", AUVENT, 0.0, "PalierAuvent")
	var a: Vector2 = AUVENT[2]
	var b: Vector2 = AUVENT[3]
	for f in [0.33, 0.67]:
		var p: Vector2 = a.lerp(b, f) + (FACADE_A - AUVENT[2]).normalized() * 0.4
		_cylindre("gris_poteau", 0.15, 3.0, _p2(p), 16)


## Arches (photo ICM 4995, vue de côté ICM 5074, LiDAR, et Kevin le
## 07/10/2026 : « elles sont rondes et pas ovales, il y a un grand diamètre
## devant et un plus petit derrière, alignés côté droit en regardant dans
## le sens de la montée ») : des CERCLES dont le centre est au-dessus du
## sol, coupés par lui.
##  - groupe avant : l'arche rouge et 3 arches en lamellé-collé, rayon
##    7,76 m (LiDAR : sommet à 2119,75 m, 12,15 m au-dessus de la place, et
##    12,8 m entre les pieds → centre à 4,39 m au-dessus de la place ;
##    largeur 15,5 m, hauteur/largeur 0,78 comme sur la photo) ;
##  - groupe arrière : 3 arches plus petites, rayon 6,2 m (LiDAR : arches
##    arrière à 2117-2118,7 m), au-dessus de l'auvent et du toit ;
##  - toutes tangentes à la même ligne du côté droit en regardant vers la
##    montée (côté ouest-sud-ouest), reliées par des pannes en acier noir ;
##  - de la place (rouge, devant l'escalier) jusqu'à 4 m derrière la façade.
const R_GRAND: float = 7.76
const R_PETIT: float = 6.2
const K_CENTRE: float = 0.566       # hauteur du centre au-dessus de la place, × R
const ECART_ARCHES: float = 2.35


func _arches() -> void:
	var t: Vector2 = (FACADE_B - FACADE_A).normalized()
	var dehors: Vector2 = Vector2(-t.y, t.x)
	if Geometry2D.is_point_in_polygon((FACADE_A + FACADE_B) * 0.5 + dehors, PackedVector2Array(HALL)):
		dehors = -dehors
	# côté droit en regardant vers la montée (vers la façade, −dehors) : −t
	var droite: Vector2 = Vector2(-dehors.y, dehors.x)
	if droite.dot(t) > 0.0:
		droite = -droite
	var mil: Vector2 = (FACADE_A + FACADE_B) * 0.5 + t * ARCHE_DECALAGE
	var bord_droit: Vector2 = mil + droite * R_GRAND          # tangente commune
	var y_place: float = H_PLACE_ABS - _o.y
	var u3: Vector3 = (_e * (-droite.x) + _n * (-droite.y)).normalized()   # vers la gauche
	var n3: Vector3 = (_e * dehors.x + _n * dehors.y).normalized()
	var angles: Array = [0.45, 0.85, 1.25, PI * 0.5, PI - 1.25, PI - 0.85, PI - 0.45]
	var pannes: Array = []
	for k in range(7):
		var r: float = R_GRAND if k < 4 else R_PETIT
		var d: float = ARCHE_D - k * ECART_ARCHES
		var c2: Vector2 = bord_droit - droite * r + dehors * d
		var c: Vector3 = _p2(c2, y_place + K_CENTRE * r)
		var m: String = "rouge" if k == 0 else "lamelle"
		_arche_cercle(m, c, u3, n3, r, 0.34 if k == 0 else 0.24, 0.50 if k == 0 else 0.40)
		var pts: Array = []
		for an in angles:
			pts.append(c + u3 * r * cos(an) + Vector3.UP * r * sin(an))
		pannes.append(pts)
	for j in range(angles.size()):
		for k in range(pannes.size() - 1):
			_barre("noir", pannes[k][j], pannes[k + 1][j], 0.09)


## Sol local sous un point (repère de la gare) : toit dans l'emprise du
## hall, palier et auvent devant la façade, sinon la place.
func _sol_sous(x: float, z: float) -> float:
	var q: Vector2 = Vector2(x, z)
	if Geometry2D.is_point_in_polygon(q, PackedVector2Array(HALL)):
		return H_TOIT
	if Geometry2D.is_point_in_polygon(q, PackedVector2Array(AUVENT)):
		return 3.25
	return H_PLACE_ABS - _o.y


## Cercle de rayon r (plan vertical (u3, haut), épaisseur w le long de n3,
## hauteur de section h) ; seules les parties au-dessus du sol local sont
## dessinées.
func _arche_cercle(m: String, c: Vector3, u3: Vector3, n3: Vector3, r: float,
		w: float, h: float) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg: int = 96
	var prec: Array = []
	var prec_ok: bool = false
	for i in range(seg + 1):
		var th: float = -PI * 0.5 + TAU * float(i) / seg
		var p: Vector3 = c + u3 * r * cos(th) + Vector3.UP * r * sin(th)
		var rad: Vector3 = (u3 * cos(th) + Vector3.UP * sin(th)).normalized()
		var coins: Array = [p + rad * h * 0.5 + n3 * w * 0.5, p + rad * h * 0.5 - n3 * w * 0.5,
			p - rad * h * 0.5 - n3 * w * 0.5, p - rad * h * 0.5 + n3 * w * 0.5]
		var loc: Vector3 = p - _o
		var ok: bool = loc.y > _sol_sous(loc.dot(_e), loc.dot(_n)) - 0.3
		if i > 0 and ok and prec_ok:
			for f in range(4):
				var g: int = (f + 1) % 4
				for v in [prec[f], coins[f], coins[g], prec[f], coins[g], prec[g]]:
					st.add_vertex(v)
		prec = coins
		prec_ok = ok
	st.generate_normals()
	st.set_material(_mats[m])
	_instance(st.commit(), "Arche")


## Escalier métallique devant l'arche rouge jusqu'à la place (LiDAR : place
## à 2107,6 m), garde-corps galvanisés en 5 files, et la place elle-même.
func _escalier() -> void:
	var t: Vector2 = (FACADE_B - FACADE_A).normalized()
	var dehors: Vector2 = Vector2(-t.y, t.x)
	if Geometry2D.is_point_in_polygon((FACADE_A + FACADE_B) * 0.5 + dehors, PackedVector2Array(HALL)):
		dehors = -dehors
	var mil: Vector2 = (FACADE_A + FACADE_B) * 0.5 + t * ARCHE_DECALAGE
	var rot: float = -atan2(t.y, t.x)
	# palier entre l'auvent et l'arche rouge
	var p0: Vector2 = mil + dehors * 7.5
	_boite("anthracite", LARGEUR_ESCALIER + 2.0, 0.8, 6.2, p0.x, p0.y, -0.40, rot, "Palier")
	var h_tot: float = _o.y - H_PLACE_ABS
	var n_marches: int = clampi(int(round(h_tot / 0.17)), 3, 18)
	var haut: float = h_tot / n_marches
	for k in range(n_marches):
		var d: float = ARCHE_D + 0.5 + GIRON * (k + 0.5)
		var p: Vector2 = mil + dehors * d
		var y_dessus: float = -haut * (k + 1)
		# marche massive jusqu'à la place (on ne voit pas dessous)
		var y_bas: float = -h_tot - 0.2
		_boite("anthracite", LARGEUR_ESCALIER, y_dessus - y_bas, GIRON, p.x, p.y, (y_dessus + y_bas) * 0.5, rot)
	var d_pied: float = ARCHE_D + 0.5 + GIRON * n_marches
	# place (enrobé ; front de neige l'hiver)
	var pp: Vector2 = mil + dehors * (d_pied + 6.0)
	_boite("anthracite", 20.0, 1.5, 12.0, pp.x, pp.y, -h_tot - 0.75, rot, "Place")
	# garde-corps : 5 files le long de la volée
	for f in [-5.5, -2.75, 0.0, 2.75, 5.5]:
		var a3: Vector3 = _p2(mil + dehors * (ARCHE_D + 0.5) + t * f, 1.0)
		var b3: Vector3 = _p2(mil + dehors * d_pied + t * f, 1.0 - h_tot)
		_barre("galva", a3, b3, 0.045)
		_barre("galva", a3 - Vector3(0, 0.5, 0), b3 - Vector3(0, 0.5, 0), 0.035)
		var n_p: int = maxi(2, int(GIRON * n_marches / 1.4) + 1)
		for k in range(n_p):
			var q: Vector3 = a3.lerp(b3, float(k) / (n_p - 1))
			_barre("galva", q, q - Vector3(0, 1.0, 0), 0.045)


# --- éclairage, voyageurs, panneau ---------------------------------------------

func _lumieres() -> void:
	for c in [Vector2(0.0, 4.0), Vector2(-6.0, 9.0), Vector2(0.0, 13.0), Vector2(-6.0, 19.0),
			Vector2(1.0, 23.0)]:
		var l: OmniLight3D = OmniLight3D.new()
		l.light_color = Color(1.0, 0.88, 0.70)          # LED blanc chaud
		l.light_energy = 1.6
		l.omni_range = 9.0
		l.shadow_enabled = false
		l.position = _p2(c, 3.1)
		if RenderingServer.get_current_rendering_method() == "gl_compatibility":
			l.light_energy *= 2.0
			l.light_cull_mask = Cabin.MASQUE_GARE_WEB
		add_child(l)


func _voyageurs() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2018
	var m: Dictionary = Cabin._skieurs_maillages()
	for p in [[-9.2, 7.5, true], [-9.6, 12.0, true], [-1.5, 5.0, false], [1.5, 6.5, false],
			[-6.5, 14.0, false], [-4.0, 3.5, false]]:
		var assis: bool = p[2]
		var face: Vector3 = _e if assis else (-_n).rotated(Vector3.UP, rng.randf_range(-1.2, 1.2))
		var zb: Vector3 = (-face).normalized()
		var xb: Vector3 = Vector3.UP.cross(zb).normalized()
		var base: Transform3D = Transform3D(Basis(xb, Vector3.UP, zb), _p(p[0], p[1], 0.0))
		var pose: String = "assis"
		var materiel: String = ""
		if not assis:
			var r: float = rng.randf()
			pose = "skis" if r < 0.6 else ("libre" if r < 0.8 else "telephone")
			if pose == "skis":
				materiel = "surf" if rng.randf() < 0.25 else "skis"
		var coiffe: String = "casque" if rng.randf() < 0.65 else "bonnet"
		var graine: Color = Color(rng.randf(), rng.randf(), rng.randf(), 1.0)
		_skieur(m["p:%s:%s" % [pose, coiffe]], base, graine)
		var g: Color = Color(rng.randf(), rng.randf(), rng.randf(), 1.0)
		if materiel == "skis":
			_skieur(m["g:skis"], base * Transform3D(Basis.IDENTITY, SkieurMesh.ANCRE_SKIS), g)
			_skieur(m["g:batons"], base * Transform3D(Basis.IDENTITY, SkieurMesh.ANCRE_BATONS), g)
		elif materiel == "surf":
			_skieur(m["g:surf"], base * Transform3D(Basis.IDENTITY, SkieurMesh.ANCRE_SURF), g)


func _skieur(mesh: Mesh, xf: Transform3D, graine: Color) -> void:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, xf)
	mm.set_instance_custom_data(0, graine)
	var mi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Aménagement du relief autour de la gare (ReliefBuilder.amenagements) :
## le terrain s'arrête aux murs du hall, s'aplanit sous l'auvent et le
## palier (niveau d'entrée) et sur l'escalier et la place (niveau de la
## place), et recouvre les quais souterrains d'au moins 1,2 m.
func amenagement_relief() -> Dictionary:
	var t: Vector2 = (FACADE_B - FACADE_A).normalized()
	var dehors: Vector2 = Vector2(-t.y, t.x)
	if Geometry2D.is_point_in_polygon((FACADE_A + FACADE_B) * 0.5 + dehors, PackedVector2Array(HALL)):
		dehors = -dehors
	var mil: Vector2 = (FACADE_A + FACADE_B) * 0.5 + t * ARCHE_DECALAGE
	var y_place: float = H_PLACE_ABS - _o.y
	var n_marches: int = clampi(int(round(-y_place / 0.17)), 3, 18)
	var d_pied: float = ARCHE_D + 0.5 + GIRON * n_marches
	var monde := func(pts: Array) -> PackedVector2Array:
		var out: PackedVector2Array = PackedVector2Array()
		for v in pts:
			var w: Vector3 = _p2(v)
			out.append(Vector2(w.x, w.z))
		return out
	var rect_l := func(c: Vector2, demi_t: float, d0: float, d1: float) -> Array:
		return [c + t * demi_t + dehors * d0, c - t * demi_t + dehors * d0,
			c - t * demi_t + dehors * d1, c + t * demi_t + dehors * d1]
	# hall agrandi de 0,15 m : le terrain s'arrête derrière le bardage
	var hall: Array = []
	var centre: Vector2 = Vector2.ZERO
	for v in HALL:
		centre += v
	centre /= HALL.size()
	for v in HALL:
		hall.append(v + (v - centre).normalized() * 0.15)
	var entree: Array = rect_l.call(mil, LARGEUR_ESCALIER * 0.5 + 1.0, 0.0, ARCHE_D + 0.5)
	var place: Array = rect_l.call(mil, 10.0, ARCHE_D + 0.5, d_pied + 12.0)
	var pts: PackedVector2Array = PackedVector2Array()
	for e in [monde.call(hall), monde.call(AUVENT), monde.call(place)]:
		pts.append_array(e)
	var axe0: Vector3 = tunnel.transform_at(0.0).origin
	var axe1: Vector3 = tunnel.transform_at(70.0).origin
	pts.append(Vector2(axe0.x, axe0.z))
	pts.append(Vector2(axe1.x, axe1.z))
	var bb: Rect2 = Rect2(pts[0], Vector2.ZERO)
	for v in pts:
		bb = bb.expand(v)
	return {
		"rect": bb.grow(18.0),
		"trous": [monde.call(hall)],
		# ordre : la place d'abord, l'entrée ensuite (elle l'emporte chez elle)
		"plats": [[monde.call(place), _o.y + y_place - 0.03, 7.0],
			[monde.call(AUVENT), _o.y - 0.03, 2.5],
			[monde.call(entree), _o.y - 0.03, 2.5]],
		"couloirs": [[0.0, 70.0, 6.0, 1.2]],
	}


## Libellé posé à plat sur une surface de normale `normale` (lisible de ce
## côté-là).
func _etiquette(texte: String, pos: Vector3, taille: int, c: Color, px: float,
		normale: Vector3, contour: Color = Color(0, 0, 0, 0)) -> Label3D:
	var l: Label3D = Label3D.new()
	l.text = texte
	l.font_size = taille
	l.pixel_size = px
	l.modulate = c
	l.outline_size = 8 if contour.a > 0.0 else 0
	l.outline_modulate = contour
	l.shaded = false
	l.double_sided = false
	var z: Vector3 = normale.normalized()
	var x: Vector3 = Vector3.UP.cross(z).normalized()
	l.transform = Transform3D(Basis(x, Vector3.UP, z), pos)
	add_child(l)
	return l


## Portes coulissantes ouvertes pendant l'embarquement en gare aval, et
## panneau des départs (date et heure locales, FR / EN en alternance,
## prochain départ estimé).
func mettre_a_jour(dt: float, ph: TrainPhysics) -> void:
	if ph == null:
		return
	var en_gare: bool = ph.s < PNConstants.START_S + 3.0 or PNConstants.miroir(ph.s) < PNConstants.START_S + 3.0
	var embarquement: bool = en_gare and ph.doors_open and not ph.trip_started
	_ouverture = move_toward(_ouverture, 1.0 if embarquement else 0.0, dt / 1.5)
	var course: float = 0.98 * smoothstep(0.0, 1.0, _ouverture)
	for v in _vantaux:
		(v[0] as Node3D).position = _p(float(v[1]) + float(v[2]) * course, 0.0, 0.0)
	_t_panneau -= dt
	if _t_panneau > 0.0:
		return
	_t_panneau = 1.0
	var hl: Dictionary = PNConstants.heure_locale()
	var en: bool = (int(hl.second) / 5) % 2 == 1
	# prochain départ : à quai → départ imminent ; sinon temps pour revenir
	# (distance restante à 12 m/s + une minute) — estimation du simulateur
	var prochain: int = 0
	if not en_gare or ph.trip_started:
		var s_bas: float = minf(ph.s, PNConstants.miroir(ph.s))
		prochain = int(ceil(maxf(s_bas - PNConstants.START_S, 0.0) / 12.0 / 60.0)) + 1
	var suivant: int = prochain + 20
	if en:
		_panneau[0].text = "%02d/%02d/%02d   %d:%02d %s" % [hl.month, hl.day, int(hl.year) % 100,
			(int(hl.hour) + 11) % 12 + 1, hl.minute, "AM" if hl.hour < 12 else "PM"]
		_panneau[1].text = "FUNICULAR-DEPARTURE STATION"
		_panneau[2].text = "Welcome"
		_panneau[3].text = "Coming departure   %d min" % prochain
		_panneau[4].text = "Next departure   %d min" % suivant
	else:
		_panneau[0].text = "%02d/%02d/%02d   %d:%02d" % [hl.day, hl.month, int(hl.year) % 100, hl.hour, hl.minute]
		_panneau[1].text = "FUNICULAIRE-GARE DE DÉPART"
		_panneau[2].text = "Bienvenue"
		_panneau[3].text = "Prochain départ   %d min" % prochain
		_panneau[4].text = "Départ suivant   %d min" % suivant
