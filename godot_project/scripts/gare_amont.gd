class_name GareAmont
extends Node3D
## EXTÉRIEUR de la gare AMONT (Grande Motte, 3032 m) et de ses abords —
## demande de Kevin du 07/10/2026 (« maintenant tu fais pareil pour le
## haut », après la refonte de la gare aval). L'intérieur (quais, hall,
## salle des machines) reste MachineRoomBuilder.
##
## Sources (relevé du 07/10/2026, détail dans SOURCES.md, ligne 24h) :
##  - IGN BD TOPO V3 (hall 527643 : 14 × 44,5 m dans l'axe de la voie ;
##    terrasse « Gare funiculaire » 49699 ; gare aval du téléphérique
##    527642) ; LiDAR HD du 11/09/2022 (toit monopente 3036,2 → 3030,1 m,
##    terrasse à 3030,7 m, annexes à 3034,7 m, restaurant à 3035-3037,7 m) ;
##    orthophoto IGN du 23/08/2024 ;
##  - photos de Kevin du 26/04/2026 (hall, mur de tête) ;
##  - reportage FUNI-334 de remontees-mecaniques.net (≤ 2017 : façade de
##    tête « TIGNES · ALT 3032 M · FUNICULAIRE / Glacier de la Grande
##    Motte · DESCENTE », côté sud-est blanc à baies bleues, terrasse sur
##    pilotis) ; Wikimedia Commons 2023 (terrasse, gare du téléphérique).
##
## Repère local : origine au milieu du mur de tête (face extérieure), au
## niveau du palier ; x vers la droite en regardant vers l'amont (nord-
## ouest), d vers l'amont (sud-ouest, cap 214,2°), y vers le haut. Les
## objets IGN sont recalés sur la fin de voie du jeu (le mur de tête réel
## est 13 m en aval et 5,5 m au nord-ouest de la fin de voie du jeu ; la
## voie BD TOPO n'est précise qu'à 10 m) ; ils tombent alors à 1,2 m près
## sur le hall.
##
## INCONNUS (valeurs du simulateur) : l'état de la façade de tête après
## les travaux de 2018 (aucune photo extérieure : on garde celui de 2017) ;
## la forme exacte du restaurant (deux volumes de chalet) et des annexes ;
## la pente du toit au bout aval (relevée pour couvrir la salle des quais
## du jeu, ≈ 1,2 m plus haute que le toit réel) ; le sens de la pente du
## toit du téléphérique.

const H_TOIT_TETE: float = 5.5        # toit au mur de tête au-dessus du palier (LiDAR)
const LONG_HALL: float = 44.5
const DEMI_HALL: float = 7.0
const H_ANNEXES: float = 4.0          # 3034,7 m
const H_BAS: float = -14.0            # bas des façades (sous le terrain)
const TERRASSE: Array = [Vector2(-7.7, 0.8), Vector2(-4.4, 5.1), Vector2(0.8, 44.2),
	Vector2(23.0, 54.5), Vector2(27.1, 50.6), Vector2(14.3, 44.8), Vector2(13.4, 34.4),
	Vector2(21.9, 28.6), Vector2(20.0, 8.8), Vector2(10.8, 4.8), Vector2(9.8, 0.7)]
const TPH: Array = [Vector2(60.3, 102.0), Vector2(48.2, 106.5), Vector2(44.5, 87.8),
	Vector2(56.0, 83.5)]
const H_TPH_SOL: float = -5.4         # 3025,3 m (+ 0,6 m de recalage)
const H_TPH_TOIT: float = 10.9        # 3041,6 m
const ANNEXES: Array = [Vector2(7.5, -13.0), Vector2(35.0, -13.0), Vector2(35.0, -45.0),
	Vector2(7.5, -45.0)]
# restaurant Le Panoramic : deux volumes de chalet le long du côté nord-
# ouest de la terrasse (emprise LiDAR x 10-42, d −17 à +47)
const RESTO_A: Rect2 = Rect2(11.0, -15.0, 25.0, 23.0)      # x, d, largeur, profondeur
const RESTO_B: Rect2 = Rect2(22.5, 8.0, 14.0, 34.0)
const SOLEIL: Vector3 = Vector3(0.40, 0.78, 0.48)          # vers le soleil (monde)

var tunnel: TunnelBuilder = null
var _o: Vector3 = Vector3.ZERO
var _x: Vector3 = Vector3.RIGHT     # droite en regardant vers l'amont
var _d: Vector3 = Vector3.FORWARD   # vers l'amont
var _y_quai_toit: float = 1.1       # toit au bout aval (au-dessus de la salle des quais)
var _st: Dictionary = {}            # matériau → SurfaceTool
var _mats: Dictionary = {}


func construire(t: TunnelBuilder, mr: MachineRoomBuilder) -> void:
	tunnel = t
	var xf: Transform3D = mr._xf
	_x = xf.basis.x
	_x.y = 0.0
	_x = _x.normalized()
	_d = -xf.basis.z
	_d.y = 0.0
	_d = _d.normalized()
	_o = mr._to_world(Vector3(0.0, 0.0, MachineRoomBuilder.HALL_DEPTH + 0.30))
	_o.y = mr._y_palier_monde()
	# toit au bout aval : au moins 0,5 m au-dessus du plafond de la salle
	# des quais du jeu
	var s_aval: float = PNConstants.LENGTH + MachineRoomBuilder.HALL_DEPTH + 0.30 - LONG_HALL
	var top_quai: float = tunnel.transform_at(s_aval).origin.y + tunnel.station_room_half_height
	_y_quai_toit = maxf(top_quai - _o.y + 0.5, 0.0)
	_materiaux()
	_hall()
	_facade_tete()
	_terrasse()
	_annexes()
	_restaurant()
	_telepherique()
	_valider()
	Cabin.tag_layer(self, Cabin.LAYER_VOIE)


func _p(x: float, d: float, y: float = 0.0) -> Vector3:
	return _o + _x * x + _d * d + Vector3(0.0, y, 0.0)


func _p2(v: Vector2, y: float = 0.0) -> Vector3:
	return _p(v.x, v.y, y)


func _y_toit(d: float) -> float:
	return lerpf(H_TOIT_TETE, _y_quai_toit, clampf(-d / LONG_HALL, 0.0, 1.0))


# --- matériaux : soleil fixe propre à chaque matériau (le jeu n'a pas de
# soleil : la gare reste en plein jour, vue de dehors ou par les baies) ----

const SHADER_EXT: String = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 couleur : source_color = vec4(1.0);
uniform sampler2D motif : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float avec_motif = 0.0;
uniform vec2 periode = vec2(1.0, 1.0);
uniform vec3 soleil = vec3(0.40, 0.78, 0.48);
uniform float gamma = 1.0;
varying vec3 pw;
varying vec3 nw;
void vertex() {
	pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	nw = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}
void fragment() {
	vec3 n = normalize(nw);
	if (!FRONT_FACING) {
		n = -n;
	}
	vec3 c = couleur.rgb;
	if (avec_motif > 0.5) {
		// motif en coordonnées monde : lames et nervures verticales
		vec2 uv = abs(n.y) < 0.6 ? vec2(dot(pw.xz, normalize(vec2(-n.z, n.x))), pw.y) : pw.xz;
		c *= texture(motif, uv / periode).rgb;
	}
	float l = 0.58 + 0.42 * max(dot(n, normalize(soleil)), 0.0) + 0.06 * n.y;
	ALBEDO = pow(c * l, vec3(gamma));
}
"""


func _mat(nom: String, c: Color, motif: Image = null, periode: Vector2 = Vector2.ONE) -> void:
	var sh: Shader = Shader.new()
	sh.code = SHADER_EXT
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("couleur", c)
	m.set_shader_parameter("soleil", SOLEIL)
	m.set_shader_parameter("gamma", 0.625 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 1.0)
	if motif != null:
		motif.generate_mipmaps()
		m.set_shader_parameter("motif", ImageTexture.create_from_image(motif))
		m.set_shader_parameter("avec_motif", 1.0)
		m.set_shader_parameter("periode", periode)
	_mats[nom] = m
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_st[nom] = st


## Motif à bandes verticales : `n` pixels, `clair` sur `k` pixels.
func _bandes(n: int, k: int, clair: Color, sombre: Color) -> Image:
	var img: Image = Image.create(n, 2, false, Image.FORMAT_RGB8)
	for i in range(n):
		var c: Color = clair if i < k else sombre
		img.set_pixel(i, 0, c)
		img.set_pixel(i, 1, c)
	return img


## Moellons de pierre grise (mur entre les deux portes de la façade de tête).
func _pierre() -> Image:
	var img: Image = Image.create(32, 32, false, Image.FORMAT_RGB8)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3032
	for by in range(4):
		var dec: int = (by % 2) * 4
		for bx in range(4):
			var v: float = rng.randf_range(0.82, 1.12)
			for y in range(by * 8, by * 8 + 8):
				for x in range(bx * 8, bx * 8 + 8):
					var xx: int = (x + dec) % 32
					var joint: bool = y % 8 == 0 or (x % 8) == 0
					img.set_pixel(xx, y, Color(0.45, 0.45, 0.44) if joint else Color(v, v, v * 0.98))
	return img


func _materiaux() -> void:
	_mat("beton", Color("94958f"))
	_mat("tole_blanche", Color("eceef0"), _bandes(16, 13, Color(1, 1, 1), Color(0.80, 0.82, 0.84)),
		Vector2(0.25, 1.0))
	_mat("bois_tete", Color("b1896c"), _bandes(16, 12, Color(1, 1, 1), Color(0.55, 0.50, 0.46)),
		Vector2(0.16, 1.0))
	_mat("bois_resto", Color("4a3122"), _bandes(16, 13, Color(1, 1, 1), Color(0.62, 0.60, 0.58)),
		Vector2(0.20, 1.0))
	_mat("pierre", Color("a3a19c"), _pierre(), Vector2(1.6, 1.0))
	_mat("bleu", Color("2a4f8f"))
	_mat("vitre", Color("3b4a5c"))
	_mat("bleu_nuit", Color("232838"))
	_mat("toit_blanc", Color("e6e8ea"))
	_mat("toit_gris", Color("6f7377"))
	_mat("brun", Color("3a2a1e"))
	_mat("galva", Color("a8acaf"))
	_mat("noir", Color("1e1f22"))
	_mat("caillebotis", Color("555f67"), _bandes(8, 6, Color(1, 1, 1), Color(0.45, 0.45, 0.45)),
		Vector2(0.04, 1.0))
	_mat("tph_gris", Color("aab3ba"), _bandes(16, 13, Color(1, 1, 1), Color(0.78, 0.80, 0.82)),
		Vector2(0.30, 1.0))
	_mat("blanc", Color("f4f4f2"))
	_mat("rouge", Color("c8202a"))
	_mat("vert", Color("2f7d47"))
	_mat("toile", Color("e9e3d6"))


# --- géométrie par lots (un maillage par matériau) -----------------------------

func _tri(m: String, a: Vector3, b: Vector3, c: Vector3) -> void:
	var st: SurfaceTool = _st[m]
	# (face avant de Godot = sens horaire vue de la caméra : normale vers
	# elle ; le nuanceur la retourne sur les faces arrière)
	var n: Vector3 = (c - a).cross(b - a).normalized()
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)


func _quad(m: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(m, a, b, c)
	_tri(m, a, c, d)


## Boîte (local) : centre (x, d, y), tailles (lx le long de x, ld le long
## de d, ly), tournée de `rot` autour de la verticale.
func _boite(m: String, x: float, d: float, y: float, lx: float, ld: float, ly: float, rot: float = 0.0) -> void:
	var ax: Vector3 = (_x * cos(rot) + _d * sin(rot)) * lx * 0.5
	var ad: Vector3 = (_d * cos(rot) - _x * sin(rot)) * ld * 0.5
	var ay: Vector3 = Vector3.UP * ly * 0.5
	var c: Vector3 = _p(x, d, y)
	var k: Array = []
	for sx in [-1, 1]:
		for sd in [-1, 1]:
			for sy in [-1, 1]:
				k.append(c + ax * sx + ad * sd + ay * sy)
	# k[i] : i = 4 sx' + 2 sd' + sy'
	var faces: Array = [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for f in faces:
		_quad(m, k[f[0]], k[f[1]], k[f[2]], k[f[3]])


## Mur vertical de a à b (local 2D), de y0 à y1(a)/y1b(b).
func _mur(m: String, a: Vector2, b: Vector2, y0: float, y1a: float, y1b: float) -> void:
	_quad(m, _p2(a, y0), _p2(b, y0), _p2(b, y1b), _p2(a, y1a))


func _poly_plat(m: String, pts: Array, y: float) -> void:
	var poly: PackedVector2Array = PackedVector2Array(pts)
	var idx: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size(), 3):
		_tri(m, _p2(poly[idx[i]], y), _p2(poly[idx[i + 1]], y), _p2(poly[idx[i + 2]], y))


func _cylindre(m: String, x: float, d: float, y0: float, y1: float, r: float, seg: int = 8) -> void:
	for i in range(seg):
		var a0: float = TAU * i / seg
		var a1: float = TAU * (i + 1) / seg
		var p0: Vector2 = Vector2(x + r * cos(a0), d + r * sin(a0))
		var p1: Vector2 = Vector2(x + r * cos(a1), d + r * sin(a1))
		_mur(m, p0, p1, y0, y1, y1)


func _valider() -> void:
	for nom in _st:
		var st: SurfaceTool = _st[nom]
		var arr: Array = st.commit_to_arrays()
		if (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(0, _mats[nom])
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "GareAmont_" + nom
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


# --- hall des quais --------------------------------------------------------------

## Volume du hall (14 × 44,5 m dans l'axe de la voie) : toit monopente blanc
## qui descend vers l'aval ; côté sud-est (x < 0) socle en béton, tôle
## nervurée blanche et bande de baies bleues ; bout aval en pignon blanc
## à deux fenêtres bleues ; côté nord-ouest blanc (annexes accolées).
func _hall() -> void:
	var n: int = 12
	for i in range(n):
		var d0: float = -LONG_HALL * i / n
		var d1: float = -LONG_HALL * (i + 1) / n
		var y0: float = _y_toit(d0)
		var y1: float = _y_toit(d1)
		# toit (léger débord)
		_quad("toit_blanc", _p(-DEMI_HALL - 0.3, d0, y0), _p(DEMI_HALL + 0.3, d0, y0),
			_p(DEMI_HALL + 0.3, d1, y1), _p(-DEMI_HALL - 0.3, d1, y1))
		# côté sud-est : béton jusqu'à −0,6 m, tôle blanche au-dessus
		_mur("beton", Vector2(-DEMI_HALL, d0), Vector2(-DEMI_HALL, d1), H_BAS, -0.6, -0.6)
		_mur("tole_blanche", Vector2(-DEMI_HALL, d0), Vector2(-DEMI_HALL, d1), -0.6, y0, y1)
		# côté nord-ouest
		_mur("tole_blanche", Vector2(DEMI_HALL, d0), Vector2(DEMI_HALL, d1), H_BAS, y0, y1)
	# bande de baies bleues sur deux rangs, côté sud-est, sous le toit
	var d_b: float = -1.0
	while d_b > -30.0:
		var yt: float = _y_toit(d_b - 1.2) - 0.55
		if yt < 1.6:
			break
		for rang in [0, 1]:
			var ya: float = yt - 0.85 * (rang + 1)
			_boite("vitre", -DEMI_HALL - 0.03, d_b - 1.2, ya + 0.4, 0.04, 2.2, 0.72)
			_boite("bleu", -DEMI_HALL - 0.06, d_b - 1.2, ya + 0.8, 0.06, 2.3, 0.08)
		_boite("bleu", -DEMI_HALL - 0.06, d_b - 2.35, yt - 0.85, 0.06, 0.10, 1.75)
		_boite("bleu", -DEMI_HALL - 0.06, d_b - 1.2, yt - 1.75, 0.06, 2.3, 0.08)
		d_b -= 2.4
	# bout aval : pignon blanc, deux fenêtres bleues
	var y_av: float = _y_toit(-LONG_HALL)
	_mur("tole_blanche", Vector2(-DEMI_HALL, -LONG_HALL), Vector2(DEMI_HALL, -LONG_HALL), H_BAS, y_av, y_av)
	for x in [-3.0, 3.0]:
		_boite("bleu", x, -LONG_HALL - 0.04, y_av - 2.6, 1.3, 0.06, 1.1)
		_boite("vitre", x, -LONG_HALL - 0.07, y_av - 2.6, 1.1, 0.04, 0.9)
	# rive de toit blanche le long de la tête
	_boite("blanc", 1.05, 0.15, H_TOIT_TETE + 0.15, 17.9, 0.35, 0.35)


# --- façade de tête (état 2017) ------------------------------------------------

## Façade sur la terrasse : bardage de bois clair en deux registres séparés
## par un petit auvent à 3,1 m ; de gauche à droite vue de la terrasse (x
## décroissant) : panneau « TIGNES », « ALT 3032 M », « FUNICULAIRE /
## Glacier de la Grande Motte » ; en bas, porte « DESCENTE » (x = +3, face à
## la baie droite du hall), mur en pierre, sortie (x = −3, entre deux
## panneaux sens interdit) et fenêtre bleue à l'angle sud-est.
func _facade_tete() -> void:
	var x0: float = -7.7
	var x1: float = 9.8
	var ouvertures: Array = [Vector2(-4.1, -1.9), Vector2(1.9, 4.1)]   # sortie, DESCENTE
	var h_ouv: float = 2.4
	# registre bas, autour des ouvertures et de la fenêtre d'angle
	var morceaux: Array = [Vector2(x0, -7.0), Vector2(-4.9, -4.1), Vector2(4.1, x1)]
	for mc in morceaux:
		_mur("bois_tete", Vector2(mc.x, 0.05), Vector2(mc.y, 0.05), -0.4, 3.1, 3.1)
	# fenêtre d'angle bleue
	_boite("bleu", -5.95, 0.07, 1.75, 2.2, 0.08, 1.7)
	_boite("vitre", -5.95, 0.10, 1.75, 1.95, 0.04, 1.45)
	# pierre entre les deux ouvertures
	_mur("pierre", Vector2(-1.9, 0.05), Vector2(1.9, 0.05), -0.4, 3.1, 3.1)
	# au-dessus des ouvertures
	for ov in ouvertures:
		_mur("bois_tete", Vector2(ov.x, 0.05), Vector2(ov.y, 0.05), h_ouv, 3.1, 3.1)
		_boite("noir", (ov.x + ov.y) * 0.5, 0.02, h_ouv * 0.5, ov.y - ov.x, 0.06, 0.05)
	# petit auvent entre les deux registres
	_boite("brun", (x0 + x1) * 0.5, 0.45, 3.12, x1 - x0, 0.9, 0.08)
	# registre haut
	_mur("bois_tete", Vector2(x0, 0.05), Vector2(x1, 0.05), 3.1, H_TOIT_TETE, H_TOIT_TETE)
	# retour de la façade sur le côté du restaurant (x 7 → 9,8)
	_mur("bois_tete", Vector2(x1, 0.05), Vector2(x1, -3.0), -0.4, H_TOIT_TETE, H_TOIT_TETE)
	# enseignes (panneaux en relief et textes)
	_boite("blanc", 7.6, 0.12, 4.3, 1.5, 0.08, 1.5)
	_boite("bleu", 7.6, 0.17, 4.42, 1.2, 0.02, 0.65)
	_boite("brun", 3.9, 0.12, 4.3, 3.4, 0.08, 0.8)
	_boite("brun", -1.6, 0.12, 4.3, 5.2, 0.08, 0.9)
	_boite("brun", 3.0, 0.12, 2.75, 2.4, 0.08, 0.42)
	_texte("TIGNES", _p(7.6, 0.18, 3.85), 40, Color("c8202a"), 0.0075)
	_texte("ALT 3032 M", _p(3.9, 0.18, 4.3), 72, Color.WHITE, 0.0085)
	_texte("FUNICULAIRE", _p(-1.6, 0.18, 4.42), 96, Color.WHITE, 0.0080)
	_texte("Glacier de la Grande Motte", _p(-0.2, 0.18, 4.0), 30, Color.WHITE, 0.0060)
	_texte("DESCENTE", _p(3.0, 0.18, 2.80), 48, Color.WHITE, 0.0060)
	# panneaux sens interdit de part et d'autre de la sortie
	for x in [-4.5, -1.5]:
		_cylindre("rouge", x, 0.25, 1.45, 1.47, 0.22, 16)
		_boite("blanc", x, 0.30, 1.46, 0.30, 0.02, 0.07)


func _texte(t: String, pos: Vector3, taille: int, c: Color, px: float) -> void:
	var l: Label3D = Label3D.new()
	l.text = t
	l.font_size = taille
	l.pixel_size = px
	l.modulate = c
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	var z: Vector3 = _d
	var x: Vector3 = Vector3.UP.cross(z).normalized()
	l.transform = Transform3D(Basis(x, Vector3.UP, z), pos)
	add_child(l)


# --- terrasse --------------------------------------------------------------------

## Terrasse « Gare funiculaire » de l'IGN, au niveau du palier (3030,7 m) :
## caillebotis gris foncé sur pilotis galvanisés, garde-corps noir, tables,
## transats, porte-skis et parasols.
func _terrasse() -> void:
	_poly_plat("caillebotis", TERRASSE, -0.02)
	_poly_plat("noir", TERRASSE, -0.25)
	var poly: PackedVector2Array = PackedVector2Array(TERRASSE)
	# pilotis tous les 5 m
	var bb: Rect2 = Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		bb = bb.expand(v)
	var x: float = bb.position.x + 2.0
	while x < bb.end.x:
		var d: float = bb.position.y + 2.0
		while d < bb.end.y:
			if Geometry2D.is_point_in_polygon(Vector2(x, d), poly):
				_boite("galva", x, d, -6.3, 0.22, 0.22, 12.0)
			d += 5.0
		x += 5.0
	# garde-corps noir (sauf le long de la façade et du restaurant)
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		if a.y < 1.5 and b.y < 1.5:
			continue                     # le long de la façade de tête
		if a.x > 9.5 and b.x > 9.5:
			continue                     # le long du restaurant
		var l: float = a.distance_to(b)
		var n_p: int = maxi(1, int(l / 2.0))
		for k in range(n_p + 1):
			var q: Vector2 = a.lerp(b, float(k) / n_p)
			_boite("noir", q.x, q.y, 0.55, 0.06, 0.06, 1.1)
		var mid: Vector2 = (a + b) * 0.5
		var rot: float = atan2((b - a).y, (b - a).x)
		_boite("noir", mid.x, mid.y, 1.08, l, 0.06, 0.06, rot)
		_boite("noir", mid.x, mid.y, 0.12, l, 0.05, 0.05, rot)
		_boite("galva", mid.x, mid.y, 0.6, l, 0.015, 0.9, rot)
	# tables et bancs, transats, porte-skis, parasols
	for t in [Vector2(4.0, 12.0), Vector2(4.0, 18.0), Vector2(9.0, 15.0), Vector2(6.0, 26.0),
			Vector2(10.0, 32.0), Vector2(8.0, 39.0)]:
		_boite("bois_resto", t.x, t.y, 0.75, 0.8, 2.0, 0.06)
		for s in [-0.65, 0.65]:
			_boite("bois_resto", t.x + s, t.y, 0.45, 0.30, 2.0, 0.05)
		_boite("galva", t.x, t.y, 1.25, 0.05, 0.05, 2.5)
		_parasol(t.x, t.y)
	for k in range(6):
		var d: float = 8.0 + k * 1.2
		_boite("toile", -2.6, d, 0.35, 0.65, 1.5, 0.05, 0.25)
		_boite("galva", -2.6, d + 0.6, 0.6, 0.6, 0.05, 0.5, 0.25)
	for k in range(3):
		_boite("blanc", 7.0, 2.5 + k * 2.2, 0.75, 0.10, 1.8, 1.5)


func _parasol(x: float, d: float) -> void:
	var c: Vector3 = _p(x, d, 2.5)
	var r: float = 1.6
	for i in range(8):
		var a0: float = TAU * i / 8
		var a1: float = TAU * (i + 1) / 8
		_tri("vert", c, _p(x + r * cos(a0), d + r * sin(a0), 2.05), _p(x + r * cos(a1), d + r * sin(a1), 2.05))


# --- annexes, restaurant, téléphérique -------------------------------------

## Annexes au nord-est du restaurant (LiDAR : toit plat à 3034,7 m) :
## bardage bleu nuit, porte de garage bleue au bout aval.
func _annexes() -> void:
	var p: Array = ANNEXES
	for i in range(4):
		_mur("bleu_nuit", p[i], p[(i + 1) % 4], H_BAS, H_ANNEXES, H_ANNEXES)
	_poly_plat("toit_gris", p, H_ANNEXES)
	_boite("bleu", 24.0, -45.06, 1.5, 4.0, 0.06, 3.4)


## Restaurant Le Panoramic : chalet de bois brun foncé, toits à deux pans
## en métal gris (LiDAR : 3035 à 3037,7 m), baies sur la terrasse.
func _restaurant() -> void:
	for r in [RESTO_A, RESTO_B]:
		var a: Vector2 = r.position
		var b: Vector2 = Vector2(r.end.x, r.position.y)
		var c: Vector2 = r.end
		var d: Vector2 = Vector2(r.position.x, r.end.y)
		var h_mur: float = 3.4
		var h_faite: float = 6.4
		for e in [[a, b], [b, c], [c, d], [d, a]]:
			_mur("bois_resto", e[0], e[1], H_BAS * 0.5, h_mur, h_mur)
		# toit à deux pans, faîtage le long du grand côté
		var long_d: bool = r.size.y >= r.size.x
		var deb: float = 0.6
		if long_d:
			var xm: float = r.position.x + r.size.x * 0.5
			for sx in [r.position.x - deb, r.end.x + deb]:
				_quad("toit_gris", _p(sx, r.position.y - deb, h_mur - 0.2), _p(sx, r.end.y + deb, h_mur - 0.2),
					_p(xm, r.end.y + deb, h_faite), _p(xm, r.position.y - deb, h_faite))
			for dd in [r.position.y, r.end.y]:
				_tri("bois_resto", _p(r.position.x, dd, h_mur), _p(r.end.x, dd, h_mur), _p(xm, dd, h_faite))
		else:
			var dm: float = r.position.y + r.size.y * 0.5
			for sd in [r.position.y - deb, r.end.y + deb]:
				_quad("toit_gris", _p(r.position.x - deb, sd, h_mur - 0.2), _p(r.end.x + deb, sd, h_mur - 0.2),
					_p(r.end.x + deb, dm, h_faite), _p(r.position.x - deb, dm, h_faite))
			for xx in [r.position.x, r.end.x]:
				_tri("bois_resto", _p(xx, r.position.y, h_mur), _p(xx, r.end.y, h_mur), _p(xx, dm, h_faite))
	# baies sur la terrasse (côté sud-est du volume B, côté sud-ouest du A)
	var d_b: float = RESTO_B.position.y + 2.0
	while d_b < RESTO_B.end.y - 2.0:
		_boite("vitre", RESTO_B.position.x - 0.04, d_b, 1.6, 0.04, 2.2, 1.9)
		d_b += 3.0
	var x_b: float = RESTO_A.position.x + 2.0
	while x_b < RESTO_A.end.x - 2.0:
		_boite("vitre", x_b, RESTO_A.end.y + 0.04, 1.6, 2.2, 0.04, 1.9)
		x_b += 3.0


## Gare aval du téléphérique de la Grande Motte (BD TOPO 527642, 107 m à
## l'ouest-sud-ouest) : bardage nervuré gris clair, étage vitré, toit
## monopente, socle en pierre, « TELEPHERIQUE DE LA GRANDE MOTTE ».
func _telepherique() -> void:
	var p: Array = TPH
	var h_bas: float = H_TPH_TOIT - 3.5
	for i in range(4):
		var a: Vector2 = p[i]
		var b: Vector2 = p[(i + 1) % 4]
		var ya: float = H_TPH_TOIT if i < 2 else h_bas
		var yb: float = H_TPH_TOIT if (i + 1) % 4 < 2 else h_bas
		_mur("pierre", a, b, H_TPH_SOL - 2.0, H_TPH_SOL + 1.5, H_TPH_SOL + 1.5)
		_mur("tph_gris", a, b, H_TPH_SOL + 1.5, ya, yb)
	_quad("toit_gris", _p2(p[0], H_TPH_TOIT), _p2(p[1], H_TPH_TOIT), _p2(p[2], h_bas), _p2(p[3], h_bas))
	# étage vitré (façades longues)
	for e in [[p[1], p[2]], [p[3], p[0]]]:
		var a2: Vector2 = e[0]
		var b2: Vector2 = e[1]
		for k in range(6):
			var q: Vector2 = a2.lerp(b2, (k + 0.5) / 6.0)
			var t: Vector2 = (b2 - a2).normalized()
			var rot: float = atan2(t.y, t.x)
			_boite("vitre", q.x, q.y, H_TPH_SOL + 8.0, 2.4, 0.08, 1.6, rot)
	# inscriptions sur la façade tournée vers la gare du funiculaire
	var a3: Vector2 = p[2]
	var b3: Vector2 = p[3]
	var m3: Vector2 = (a3 + b3) * 0.5
	var t3: Vector2 = (b3 - a3).normalized()
	var n3: Vector2 = Vector2(-t3.y, t3.x)
	if n3.dot(-m3) < 0.0:
		n3 = -n3
	var nrm: Vector3 = (_x * n3.x + _d * n3.y).normalized()
	_texte_n("TELEPHERIQUE DE LA GRANDE MOTTE", _p2(m3 + n3 * 0.1, H_TPH_SOL + 10.3), 72, Color("2a3550"), 0.012, nrm)
	_boite("bleu_nuit", m3.x + n3.x * 0.08, m3.y + n3.y * 0.08, H_TPH_SOL + 4.2, 8.0, 0.08, 0.9, atan2(t3.y, t3.x))
	_texte_n("GRANDE MOTTE", _p2(m3 + n3 * 0.15, H_TPH_SOL + 4.2), 72, Color.WHITE, 0.010, nrm)


func _texte_n(t: String, pos: Vector3, taille: int, c: Color, px: float, normale: Vector3) -> void:
	var l: Label3D = Label3D.new()
	l.text = t
	l.font_size = taille
	l.pixel_size = px
	l.modulate = c
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	var x: Vector3 = Vector3.UP.cross(normale).normalized()
	l.transform = Transform3D(Basis(x, Vector3.UP, normale), pos)
	add_child(l)


# --- relief ------------------------------------------------------------------

## Aménagement du relief (ReliefBuilder.amenagements) : terrain retiré dans
## le hall, les annexes, le restaurant et la gare du téléphérique ; rasé
## sous la terrasse ; relevé au-dessus de la salle des quais et du tunnel
## qui y entre.
func amenagement_relief() -> Dictionary:
	var monde := func(pts: Array) -> PackedVector2Array:
		var out: PackedVector2Array = PackedVector2Array()
		for v in pts:
			var w: Vector3 = _p2(v)
			out.append(Vector2(w.x, w.z))
		return out
	var rect := func(r: Rect2) -> Array:
		return [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var hall: Array = [Vector2(-DEMI_HALL - 0.2, 0.3), Vector2(DEMI_HALL + 0.2, 0.3),
		Vector2(DEMI_HALL + 0.2, -LONG_HALL - 0.2), Vector2(-DEMI_HALL - 0.2, -LONG_HALL - 0.2)]
	var pts: PackedVector2Array = PackedVector2Array()
	for e in [hall, TERRASSE, ANNEXES, TPH, rect.call(RESTO_A), rect.call(RESTO_B)]:
		pts.append_array(monde.call(e))
	var bb: Rect2 = Rect2(pts[0], Vector2.ZERO)
	for v in pts:
		bb = bb.expand(v)
	var a3440: Vector3 = tunnel.transform_at(3440.0).origin
	bb = bb.expand(Vector2(a3440.x, a3440.z))
	return {
		"rect": bb.grow(18.0),
		"trous": [monde.call(hall), monde.call(ANNEXES), monde.call(TPH),
			monde.call(rect.call(RESTO_A)), monde.call(rect.call(RESTO_B))],
		"rabots": [[monde.call(TERRASSE), _o.y - 0.4, 3.0]],
		"couloirs": [[3440.0, PNConstants.LENGTH + MachineRoomBuilder.HALL_DEPTH, 6.0, 1.2]],
	}
