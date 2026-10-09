class_name GareAmont
extends Node3D
## EXTÉRIEUR de la gare AMONT (Grande Motte, 3032 m) et de ses abords —
## demande d'un utilisateur du 07/10/2026 (« maintenant tu fais pareil pour le
## haut », après la refonte de la gare aval). L'intérieur (quais, hall,
## salle des machines) reste MachineRoomBuilder.
##
## Sources (relevé du 07/10/2026, détail dans SOURCES.md, ligne 24h) :
##  - IGN BD TOPO V3 (hall 527643 : 14 × 44,5 m dans l'axe de la voie ;
##    terrasse « Gare funiculaire » 49699 ; gare aval du téléphérique
##    527642) ; LiDAR HD du 11/09/2022 (toit monopente 3036,2 → 3030,1 m,
##    terrasse à 3030,7 m, annexes à 3034,7 m, restaurant à 3035-3037,7 m) ;
##    orthophoto IGN du 23/08/2024 ;
##  - photos d'un utilisateur du 26/04/2026 (hall, mur de tête) ;
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
const LONG_HALL_IGN: float = 44.5   # BD TOPO ; recalculé sur la salle du jeu (_long)
const DEMI_HALL: float = 7.0
const H_ANNEXES: float = 4.0          # 3034,7 m
const H_BAS: float = -14.0            # bas des façades (sous le terrain)
const TERRASSE: Array = [Vector2(-7.7, 0.8), Vector2(-4.4, 5.1), Vector2(0.8, 44.2),
	Vector2(23.0, 54.5), Vector2(27.1, 50.6), Vector2(14.3, 44.8), Vector2(13.4, 34.4),
	Vector2(21.9, 28.6), Vector2(20.0, 8.8), Vector2(10.8, 4.8), Vector2(9.8, 0.7)]
## Escalier du bout de la terrasse (retour d'utilisateur, 07/10/2026 : « au bout de la
## terrasse au sud en haut, faut un escalier pour rejoindre le sol ») : sur
## le petit côté de la pointe sud-ouest (sommets 3 → 4 de TERRASSE), là où
## la neige est la plus proche du plancher (2,85 m dessous sur le relief IGN,
## 4 à 11 m le long du grand côté sud). Largeur, marches, giron : valeurs du
## simulateur.
const ESC_COTE: int = 3                 # côté TERRASSE[3] → TERRASSE[4]
const ESC_LARG: float = 1.4
const ESC_HAUT: float = 2.85
const ESC_MARCHES: int = 16             # contremarches de 17,8 cm
const ESC_GIRON: float = 0.29
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
## longueur du hall : du mur de tête au pignon aval, où commence la salle
## des quais du jeu (TunnelBuilder.station_high_start) — 44,5 m sur l'IGN
var _long: float = LONG_HALL_IGN
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
	_long = PNConstants.LENGTH + MachineRoomBuilder.HALL_DEPTH + 0.30 \
		- (tunnel.station_high_start + tunnel.station_room_transition_haut)
	# toit au bout aval : au moins 0,5 m au-dessus du plafond de la salle
	# des quais du jeu
	var s_aval: float = PNConstants.LENGTH + MachineRoomBuilder.HALL_DEPTH + 0.30 - _long
	var top_quai: float = tunnel.transform_at(s_aval).origin.y + tunnel.station_room_half_height
	_y_quai_toit = maxf(top_quai - _o.y + 0.5, 0.0)
	_materiaux()
	_calcul_porte_genepy()
	_hall()
	_porte_genepy()
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
	return lerpf(H_TOIT_TETE, _y_quai_toit, clampf(-d / _long, 0.0, 1.0))


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
	_mat("assiette", Color("f2f0ea"))
	_mat("frites", Color("e3b04b"))
	_mat("vitre", Color("3b4a5c"))
	_mat("bleu_nuit", Color("232838"))
	_mat("acier_bleu", Color("30426f"))
	_mat("bleu_nuit_clair", Color("2c3248"))
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
		if arr[Mesh.ARRAY_VERTEX] == null or (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue                     # matériau inutilisé
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(0, _mats[nom])
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "GareAmont_" + nom
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


# --- porte de la piste Génépy ------------------------------------------------------
# Retour d'utilisateur, 07/10/2026 : « au niveau du bout en bas du quai gauche en regardant
# vers le haut, il y a une porte pour sortir et faire la piste Génépy ; tu
# me montes le terrain jusque-là et tu fais une ouverture de porte
# automatique si quelqu'un se présente devant ». Le mur de la salle du quai
# (StationsBuilder.PORTE_GENEPY) et le mur sud-est du bâtiment sont percés ;
# un court passage en béton les relie ; dehors, une porte vitrée
# automatique et la neige remontée au niveau du seuil (amenagement_relief).

var _pg_d: Vector2 = Vector2.ZERO        # d des deux bords de la porte
var _pg_y: float = 0.0                   # seuil, dans le repère du hall
var porte_genepy: PorteAuto = null


func _calcul_porte_genepy() -> void:
	var pg: Vector2 = StationsBuilder.PORTE_GENEPY
	var a: float = (tunnel.transform_at(pg.x).origin - _o).dot(_d)
	var b: float = (tunnel.transform_at(pg.y).origin - _o).dot(_d)
	_pg_d = Vector2(minf(a, b), maxf(a, b))
	# seuil = dessus du quai (−1,10 sous l'axe de la voie)
	var xc: Transform3D = tunnel.transform_at((pg.x + pg.y) * 0.5)
	_pg_y = (xc.origin + xc.basis.y * -1.10).y - _o.y


## Mur le long de d (x fixe), percé de la porte Génépy s'il la croise.
func _mur_perce(m: String, x: float, d0: float, d1: float, y0: float, y1a: float, y1b: float) -> void:
	var da: float = minf(d0, d1)
	var db: float = maxf(d0, d1)
	var ya: float = y1a if d0 < d1 else y1b      # haut du mur en da
	var yb: float = y1b if d0 < d1 else y1a      # haut du mur en db
	var haut := func(d: float) -> float: return lerpf(ya, yb, (d - da) / maxf(db - da, 0.001))
	var t0: float = _pg_y
	var t1: float = _pg_y + StationsBuilder.PORTE_GENEPY_H
	if x > 0.0 or _pg_d.y <= da or _pg_d.x >= db or t1 <= y0 or t0 >= minf(ya, yb):
		_mur(m, Vector2(x, d0), Vector2(x, d1), y0, y1a, y1b)
		return
	var pa: float = maxf(_pg_d.x, da)
	var pb: float = minf(_pg_d.y, db)
	if pa > da:
		_mur(m, Vector2(x, da), Vector2(x, pa), y0, ya, haut.call(pa))
	if pb < db:
		_mur(m, Vector2(x, pb), Vector2(x, db), y0, haut.call(pb), yb)
	if t0 > y0:
		_mur(m, Vector2(x, pa), Vector2(x, pb), y0, t0, t0)
	if t1 < minf(haut.call(pa), haut.call(pb)):
		_quad(m, _p(x, pa, t1), _p(x, pb, t1), _p(x, pb, haut.call(pb)), _p(x, pa, haut.call(pa)))


## Passage entre le mur de la salle (x = −4,9) et la façade (x = −7), et
## la porte de la façade d'après les photos d'un retour d'utilisateur
## (09/10/2026) : VOLET ROULANT bleu à lames horizontales et trois hublots
## ovales cerclés de noir, qui monte en s'enroulant au sommet de l'ouverture ; posée en retrait dans un
## encadrement de tôle blanche ; dehors, un palier en caillebotis (des
## marches d'un bon mètre dessous, enfouies l'hiver sous la neige), à droite
## un boîtier à bouton « appuyer pour ouvrir », au-dessus un projecteur.
func _porte_genepy() -> void:
	var dl: float = _pg_d.y - _pg_d.x
	var dc: float = (_pg_d.x + _pg_d.y) * 0.5
	var x_in: float = -tunnel.station_room_half_width
	var x_out: float = -DEMI_HALL
	var lx: float = absf(x_out - x_in) + 0.2
	var xm: float = (x_in + x_out) * 0.5
	var h: float = StationsBuilder.PORTE_GENEPY_H
	_boite("beton", xm, dc, _pg_y - 0.15, lx, dl + 0.4, 0.30)                # sol du passage
	_boite("beton", xm, dc, _pg_y + h + 0.15, lx, dl + 0.4, 0.30)            # plafond
	for dd in [_pg_d.x - 0.1, _pg_d.y + 0.1]:
		_boite("beton", xm, dd, _pg_y + h * 0.5, lx, 0.2, h + 0.6)           # joues
	# encadrement blanc en retrait (tableau de 0,30 m)
	for dd2 in [_pg_d.x - 0.06, _pg_d.y + 0.06]:
		_boite("tole_blanche", x_out - 0.02, dd2, _pg_y + h * 0.5, 0.34, 0.12, h + 0.10)
	_boite("tole_blanche", x_out - 0.02, dc, _pg_y + h + 0.06, 0.34, dl + 0.24, 0.12)
	# palier en caillebotis devant la porte, au niveau du seuil
	_boite("caillebotis", x_out - 0.95, dc, _pg_y - 0.04, 1.7, dl + 0.9, 0.08)
	# boîtier à bouton (à droite en regardant la porte) et projecteur au-dessus
	var d_bt: float = _pg_d.x - 0.45
	_boite("galva", x_out - 0.04, d_bt, _pg_y + 1.30, 0.06, 0.12, 0.16)
	_boite("rouge", x_out - 0.075, d_bt, _pg_y + 1.30, 0.02, 0.05, 0.05)
	_boite("blanc", x_out - 0.035, d_bt, _pg_y + 1.62, 0.02, 0.22, 0.26)
	_texte("APPUYER SUR LE BOUTON\nPOUR OUVRIR LA PORTE\nPRESS THE BUTTON\nTO OPEN THE DOOR",
		_p(x_out - 0.05, d_bt, _pg_y + 1.62), 18, Color(0.75, 0.10, 0.12), 0.0016, -_x)
	_boite("noir", x_out - 0.12, _pg_d.x - 0.3, _pg_y + h + 0.95, 0.18, 0.34, 0.24)
	_boite("galva", x_out - 0.06, _pg_d.x - 0.3, _pg_y + h + 1.1, 0.12, 0.06, 0.06)
	# coffre du volet roulant, en haut de l'ouverture côté passage : le
	# tablier s'y enroule (retour d'utilisateur, 09/10/2026 : « elle s'ouvre
	# verticalement comme un volet roulant, en s'enroulant au sommet de
	# l'ouverture ») — vu du dehors, il disparaît derrière le linteau
	_boite("galva", x_out + 0.42, dc, _pg_y + h - 0.12, 0.50, dl + 0.30, 0.42)
	# la porte : le tablier, qui monte et s'enroule dans le coffre
	porte_genepy = PorteAuto.new()
	porte_genepy.name = "PorteGenepy"
	add_child(porte_genepy)
	porte_genepy.transform = Transform3D(Basis(_d, Vector3.UP, -_x), _p(x_out + 0.18, dc, _pg_y))
	var v: Node3D = Node3D.new()
	v.name = "VantailGenepy"
	porte_genepy.add_child(v)
	var bleu: StandardMaterial3D = StandardMaterial3D.new()
	bleu.albedo_color = Color(0.09, 0.43, 0.82)
	bleu.roughness = 0.45
	var rainure: StandardMaterial3D = StandardMaterial3D.new()
	rainure.albedo_color = Color(0.05, 0.28, 0.58)
	var noir: StandardMaterial3D = StandardMaterial3D.new()
	noir.albedo_color = Color(0.05, 0.05, 0.06)
	noir.roughness = 0.6
	var verre: StandardMaterial3D = StandardMaterial3D.new()
	verre.albedo_color = Color(0.32, 0.36, 0.40)
	verre.roughness = 0.15
	verre.metallic = 0.3
	var pieces: Array = [[bleu, Vector3(dl, h, 0.045), Vector3(0.0, h * 0.5, 0.0), Vector3.ONE]]
	var y: float = 0.11
	while y < h - 0.05:                              # rainures horizontales
		pieces.append([rainure, Vector3(dl - 0.02, 0.008, 0.004), Vector3(0.0, y, 0.025), Vector3.ONE])
		y += 0.11
	# hublots ovales (cerclage noir, vitre sombre)
	for k in [-1.0, 0.0, 1.0]:
		var xo: float = k * dl * 0.30
		var yo: float = h * 0.78
		pieces.append([noir, Vector3(1, 1, 1), Vector3(xo, yo, 0.030), Vector3(0.40, 0.21, 0.022)])
		pieces.append([verre, Vector3(1, 1, 1), Vector3(xo, yo, 0.036), Vector3(0.33, 0.15, 0.022)])
	# poignée verticale et fente basse
	pieces.append([noir, Vector3(0.03, 0.16, 0.02), Vector3(-dl * 0.40, h * 0.42, 0.035), Vector3.ONE])
	pieces.append([noir, Vector3(0.12, 0.035, 0.015), Vector3(-dl * 0.40, 0.18, 0.03), Vector3.ONE])
	for pt in pieces:
		var mi: MeshInstance3D = MeshInstance3D.new()
		if (pt[3] as Vector3) != Vector3.ONE:
			# disque (cylindre couché face à la porte) étiré en ovale
			var cy: CylinderMesh = CylinderMesh.new()
			cy.top_radius = 0.5
			cy.bottom_radius = 0.5
			cy.height = 1.0
			cy.radial_segments = 24
			cy.material = pt[0]
			mi.mesh = cy
			mi.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(pt[3]), pt[2])
		else:
			var bm: BoxMesh = BoxMesh.new()
			bm.size = pt[1]
			bm.material = pt[0]
			mi.mesh = bm
			mi.position = pt[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		v.add_child(mi)
	porte_genepy.ajouter_vantail(v, Vector3(0.0, h * 0.86, 0.0))


# --- hall des quais --------------------------------------------------------------

## Volume du hall (14 × 44,5 m dans l'axe de la voie) : toit monopente blanc
## qui descend vers l'aval ; côté sud-est (x < 0) socle en béton, tôle
## nervurée blanche et bande de baies bleues ; bout aval en pignon blanc
## à deux fenêtres bleues ; côté nord-ouest blanc (annexes accolées).
func _hall() -> void:
	var n: int = 12
	for i in range(n):
		var d0: float = -_long * i / n
		var d1: float = -_long * (i + 1) / n
		var y0: float = _y_toit(d0)
		var y1: float = _y_toit(d1)
		# toit (léger débord)
		_quad("toit_blanc", _p(-DEMI_HALL - 0.3, d0, y0), _p(DEMI_HALL + 0.3, d0, y0),
			_p(DEMI_HALL + 0.3, d1, y1), _p(-DEMI_HALL - 0.3, d1, y1))
		# côté sud-est : béton jusqu'à −0,6 m, tôle blanche au-dessus
		_mur_perce("beton", -DEMI_HALL, d0, d1, H_BAS, -0.6, -0.6)
		_mur_perce("tole_blanche", -DEMI_HALL, d0, d1, -0.6, y0, y1)
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
	# bout aval : pignon blanc à deux fenêtres bleues, PERCÉ de la bouche
	# du tunnel (retour d'utilisateur, 07/10/2026 : « le mur aval de la gare ferme
	# l'entrée du tunnel » ; photos 095520 et 095051 : le hall finit sur
	# un mur bleu nuit, la bouche rectangulaire du tunnel encadrée d'un
	# portique d'acier bleu, dans l'axe de la voie)
	var y_av: float = _y_toit(-_long)
	var b: Rect2 = _bouche()
	var dg: float = -_long
	var morceaux: Array = [
		[Vector2(-DEMI_HALL, dg), Vector2(b.position.x, dg), H_BAS, y_av],          # à gauche
		[Vector2(b.end.x, dg), Vector2(DEMI_HALL, dg), H_BAS, y_av],                 # à droite
		[Vector2(b.position.x, dg), Vector2(b.end.x, dg), H_BAS, b.position.y],      # dessous
		[Vector2(b.position.x, dg), Vector2(b.end.x, dg), b.end.y, y_av]]            # dessus
	for mc in morceaux:
		_mur("tole_blanche", mc[0], mc[1], mc[2], mc[3], mc[3])
		# face côté quai, bleu nuit (photos)
		_mur("bleu_nuit", mc[0] + Vector2(0, 0.35), mc[1] + Vector2(0, 0.35), maxf(mc[2], b.position.y - 0.5),
			mc[3] - 0.05, mc[3] - 0.05)
	# bouche du tunnel côté quai (photos du reportage FUNI-334, « un petit
	# zoom sur la sortie du tunnel », envoyées par un utilisateur le 07/10/2026) :
	#  - cornières galvanisées sur les deux tableaux de l'ouverture ;
	#  - au-dessus, un gros caisson de béton en saillie (≈ 1,1 m de haut,
	#    0,6 m de saillie), plus large que l'ouverture, portant deux
	#    MIROIRS convexes qui surveillent chacun un quai (retour d'utilisateur) ;
	#  - un pilier en saillie à gauche (vu du quai, vers l'aval : côté
	#    nord-ouest) jusqu'au caisson ;
	#  - un portillon blanc au pied de chaque quai, celui de droite (sud-
	#    est) avec un panneau sens interdit.
	var dq: float = dg + 0.35
	for xx in [b.position.x, b.end.x]:
		_boite("galva", xx, dq + 0.06, (b.position.y + b.end.y) * 0.5, 0.08, 0.12, b.size.y)
	# (vu du quai vers l'aval, la gauche est le nord-ouest : x > 0)
	var cx0: float = b.position.x - 0.85
	var cx1: float = b.end.x + 1.25
	# caisson jusqu'au plafond de la salle (axe + 2,65 m)
	var h_cais: float = tunnel.station_room_half_height - LINTEAU - 0.05
	_boite("bleu_nuit_clair", (cx0 + cx1) * 0.5, dq + 0.30, b.end.y + h_cais * 0.5, cx1 - cx0, 0.60, h_cais)
	for k in [-1.0, 1.0]:
		var xx: float = b.position.x + 0.9 if k < 0.0 else b.end.x - 0.9
		_miroir(_p(xx, dq + 0.62, b.end.y + h_cais * 0.5), k)
	_boite("bleu_nuit_clair", cx1 - 0.55, dq + 0.25, (b.position.y - 0.3 + b.end.y) * 0.5,
		1.1, 0.50, b.end.y - b.position.y + 0.3)
	# portillons blancs au pied des quais (de part et d'autre de la bouche)
	var y_q: float = b.end.y - LINTEAU - 0.6   # dessus de la première marche (axe − 0,6 m)
	for cote in [-1.0, 1.0]:
		var xg: float = (b.end.x + 0.55) if cote > 0.0 else (b.position.x - 1.9)
		for xx in [xg, xg + 0.9]:
			_boite("blanc", xx, dq + 0.9, y_q + 0.55, 0.05, 0.05, 1.1)
		_boite("blanc", xg + 0.45, dq + 0.9, y_q + 1.08, 0.9, 0.05, 0.05)
		_boite("blanc", xg + 0.45, dq + 0.9, y_q + 0.15, 0.9, 0.05, 0.05)
		if cote < 0.0:                  # à droite vu du quai vers l'aval
			_sens_interdit(_p(xg + 0.45, dq + 0.93, y_q + 0.62), _d, 0.16)
	for x in [-5.2, 5.2]:
		_boite("bleu", x, dg - 0.04, y_av - 1.9, 1.3, 0.06, 1.1)
		_boite("vitre", x, dg - 0.07, y_av - 1.9, 1.1, 0.04, 0.9)
	# rive de toit blanche le long de la tête
	_boite("blanc", 1.05, 0.15, H_TOIT_TETE + 0.15, 17.9, 0.35, 0.35)


## Bouche du tunnel dans le pignon aval (repère local : x, y) : la largeur
## du tube carré (+ 5 cm), du dessous de la dalle jusqu'au linteau. Photo
## « un petit zoom sur la sortie du tunnel » : ouverture ≈ 0,8 fois aussi
## haute que large au-dessus de la dalle, caisson ≈ 1,1 m au-dessus, qui
## monte jusqu'au plafond de la salle → linteau à l'axe + 1,55 m.
const LINTEAU: float = 1.55


func _bouche() -> Rect2:
	var s_p: float = tunnel.station_high_start - 0.01          # encore le tube carré
	var y_axe: float = tunnel.transform_at(s_p).origin.y - _o.y
	var dims: Vector2 = tunnel._horseshoe_dims_at(s_p)
	var r: float = maxf(tunnel.tunnel_radius, dims.x) + 0.05
	var h: float = maxf(tunnel.tunnel_radius, dims.y) + 0.05
	return Rect2(-r, y_axe - h, 2.0 * r, h + LINTEAU)


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
	# (les portes vitrées automatiques sont juste derrière, dans le mur de
	# la salle : MachineRoomBuilder ; plus de barre en travers du passage)
	for ov in ouvertures:
		_mur("bois_tete", Vector2(ov.x, 0.05), Vector2(ov.y, 0.05), h_ouv, 3.1, 3.1)
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
		_sens_interdit(_p(x, 0.12, 1.55), _d, 0.22)


## Miroir convexe de surveillance (dôme chromé, cerclage noir), tourné vers
## le quai de son côté et vers le bas.
static var _mat_miroir: StandardMaterial3D = null


func _miroir(c: Vector3, cote: float) -> void:
	if _mat_miroir == null:
		_mat_miroir = StandardMaterial3D.new()
		_mat_miroir.albedo_color = Color(0.82, 0.84, 0.86)
		_mat_miroir.metallic = 1.0
		_mat_miroir.roughness = 0.06
	var pivot: Node3D = Node3D.new()
	pivot.name = "Miroir"
	add_child(pivot)
	# regarde vers l'amont (le quai), penché vers le bas et vers son quai
	var vers: Vector3 = (_d + _x * (-cote) * 0.55 + Vector3.DOWN * 0.45).normalized()
	pivot.transform = Transform3D(Basis.looking_at(-vers, Vector3.UP), c)
	var dome: MeshInstance3D = MeshInstance3D.new()
	var sp: SphereMesh = SphereMesh.new()
	sp.radius = 0.24
	sp.height = 0.16
	sp.is_hemisphere = true
	sp.material = _mat_miroir
	dome.mesh = sp
	dome.rotation = Vector3(PI * 0.5, 0.0, 0.0)      # bombé vers l'avant (+Z local)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(dome)
	var cercle: MeshInstance3D = MeshInstance3D.new()
	var to: TorusMesh = TorusMesh.new()
	to.inner_radius = 0.235
	to.outer_radius = 0.27
	var noir: StandardMaterial3D = StandardMaterial3D.new()
	noir.albedo_color = Color(0.05, 0.05, 0.06)
	to.material = noir
	cercle.mesh = to
	cercle.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	pivot.add_child(cercle)


## Panneau rond « sens interdit » (disque rouge, barre blanche) tourné vers
## `normale`.
static var _mat_rouge: StandardMaterial3D = null
static var _mat_blanc: StandardMaterial3D = null


func _sens_interdit(c: Vector3, normale: Vector3, r: float) -> void:
	if _mat_rouge == null:
		_mat_rouge = StandardMaterial3D.new()
		_mat_rouge.albedo_color = Color(0.80, 0.08, 0.10)
		_mat_rouge.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_blanc = StandardMaterial3D.new()
		_mat_blanc.albedo_color = Color(0.97, 0.97, 0.97)
		_mat_blanc.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pivot: Node3D = Node3D.new()
	add_child(pivot)
	var z: Vector3 = normale.normalized()
	var x: Vector3 = Vector3.UP.cross(z).normalized()
	pivot.transform = Transform3D(Basis(x, Vector3.UP, z), c)
	var disque: MeshInstance3D = MeshInstance3D.new()
	var cy: CylinderMesh = CylinderMesh.new()
	cy.top_radius = r
	cy.bottom_radius = r
	cy.height = 0.02
	cy.radial_segments = 24
	cy.material = _mat_rouge
	disque.mesh = cy
	disque.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	pivot.add_child(disque)
	var barre: MeshInstance3D = MeshInstance3D.new()
	var bx: BoxMesh = BoxMesh.new()
	bx.size = Vector3(r * 1.3, r * 0.32, 0.01)
	bx.material = _mat_blanc
	barre.mesh = bx
	barre.position = Vector3(0.0, 0.0, 0.012)
	pivot.add_child(barre)


func _texte(t: String, pos: Vector3, taille: int, c: Color, px: float, normale: Vector3 = Vector3.ZERO) -> void:
	var l: Label3D = Label3D.new()
	l.text = t
	l.font_size = taille
	l.pixel_size = px
	l.modulate = c
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	var z: Vector3 = _d if normale == Vector3.ZERO else normale
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
	# garde-corps noir (sauf le long de la façade et du restaurant), ouvert
	# en haut de l'escalier
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		if a.y < 1.5 and b.y < 1.5:
			continue                     # le long de la façade de tête
		if a.x > 9.5 and b.x > 9.5 and i != ESC_COTE:
			continue                     # le long du restaurant
		if i == ESC_COTE:
			var e: Array = _escalier_repere()
			var demi: Vector2 = (e[1] as Vector2) * (ESC_LARG * 0.5 + 0.05)
			_garde_corps(a, (e[0] as Vector2) - demi)
			_garde_corps((e[0] as Vector2) + demi, b)
		else:
			_garde_corps(a, b)
	_escalier()
	# tables et bancs, transats, porte-skis, parasols
	_assiette_frites(TABLE_SKIEUR + Vector2(0.0, 0.55))
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


func _garde_corps(a: Vector2, b: Vector2) -> void:
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


## Repère de l'escalier (local 2D) : [milieu du côté, le long du côté,
## vers l'extérieur (où il descend)].
func _escalier_repere() -> Array:
	var a: Vector2 = TERRASSE[ESC_COTE]
	var b: Vector2 = TERRASSE[(ESC_COTE + 1) % TERRASSE.size()]
	var t: Vector2 = (b - a).normalized()
	return [(a + b) * 0.5, t, Vector2(-t.y, t.x)]


## Longueur au sol de la volée (du bord de la terrasse au pied).
func escalier_course() -> float:
	return (ESC_MARCHES - 1) * ESC_GIRON


## Haut et pied de l'escalier de la terrasse (monde), pour le banc.
func escalier_points() -> Array:
	var e: Array = _escalier_repere()
	var m: Vector2 = e[0]
	var n: Vector2 = e[2]
	return [_p2(m - n * 1.5, 0.05), _p2(m + n * (escalier_course() + 1.5), -ESC_HAUT + 0.05)]


func _escalier() -> void:
	var e: Array = _escalier_repere()
	var m: Vector2 = e[0]
	var t: Vector2 = e[1]
	var n: Vector2 = e[2]
	var rot: float = atan2(t.y, t.x)
	var h: float = ESC_HAUT / ESC_MARCHES
	# marches de caillebotis : la k-ième à k contremarches sous le plancher
	for k in range(1, ESC_MARCHES):
		var c: Vector2 = m + n * ((k - 0.5) * ESC_GIRON)
		_boite("caillebotis", c.x, c.y, -k * h - 0.025, ESC_LARG, ESC_GIRON + 0.01, 0.05, rot)
	var course: float = escalier_course()
	for cote in [-1.0, 1.0]:
		var lat: Vector2 = t * cote * (ESC_LARG * 0.5 + 0.03)
		# limon galvanisé, du bord de la terrasse à la neige
		_barre("galva", _p2(m + lat - n * 0.05, -0.17), _p2(m + lat + n * (course + 0.10), -ESC_HAUT + 0.10), 0.03, 0.30)
		# main courante noire à 0,95 m au-dessus des nez de marche, poteaux
		var lat_r: Vector2 = t * cote * (ESC_LARG * 0.5 + 0.06)
		_barre("noir", _p2(m + lat_r, 0.95), _p2(m + lat_r + n * course, -ESC_HAUT + 0.95), 0.05, 0.05)
		for k in [1, 6, 11, ESC_MARCHES - 1]:
			var q: Vector2 = m + lat_r + n * ((k - 0.5) * ESC_GIRON)
			var y_k: float = -k * h
			_boite("noir", q.x, q.y, y_k + 0.47, 0.05, 0.05, 0.95)


## Barre droite de section larg × haut entre deux points du monde (limons,
## mains courantes inclinés) ; « haut » dans le plan vertical de la barre.
func _barre(m: String, p0: Vector3, p1: Vector3, larg: float, haut: float) -> void:
	var u: Vector3 = (p1 - p0).normalized()
	var v: Vector3 = u.cross(Vector3.UP).normalized() * larg * 0.5
	var w: Vector3 = v.cross(u).normalized() * haut * 0.5
	var k: Array = []
	for p in [p0, p1]:
		for sv in [-1, 1]:
			for sw in [-1, 1]:
				k.append(p + v * sv + w * sw)
	# k[i] : i = 4 bout + 2 sv' + sw'
	var faces: Array = [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for f in faces:
		_quad(m, k[f[0]], k[f[1]], k[f[2]], k[f[3]])


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
## Table du skieur jouable sur la terrasse (retour d'utilisateur, 07/10/2026 : au départ
## d'en haut, « il devrait être en haut sur la terrasse avec une assiette de
## frites »).
const TABLE_SKIEUR: Vector2 = Vector2(4.0, 12.0)


func _assiette_frites(c: Vector2) -> void:
	_cylindre("assiette", c.x, c.y, 0.78, 0.795, 0.13, 16)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3032
	for i in range(16):
		var a: float = rng.randf() * TAU
		var r: float = rng.randf() * 0.07
		_boite("frites", c.x + cos(a) * r, c.y + sin(a) * r, 0.81 + rng.randf() * 0.025,
			0.012, 0.075, 0.012, rng.randf() * PI)


## Départ du skieur jouable en partant d'en haut : à table, sur la terrasse,
## devant son assiette de frites. [position monde, cap].
func point_depart() -> Array:
	var p: Vector3 = _p(TABLE_SKIEUR.x - 1.15, TABLE_SKIEUR.y + 0.55, 0.05)
	var vers: Vector3 = _p(TABLE_SKIEUR.x, TABLE_SKIEUR.y + 0.55, 0.0) - p
	return [p, atan2(-vers.x, -vers.z)]


func _pied_escalier() -> Array:
	var e: Array = _escalier_repere()
	var m: Vector2 = e[0]
	var t: Vector2 = e[1] * (ESC_LARG * 0.5 + 0.5)
	var n: Vector2 = e[2]
	var c0: Vector2 = m + n * (escalier_course() - 0.2)
	var c1: Vector2 = m + n * (escalier_course() + 2.2)
	return [c0 - t, c0 + t, c1 + t, c1 - t]


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
		Vector2(DEMI_HALL + 0.2, -_long - 0.2), Vector2(-DEMI_HALL - 0.2, -_long - 0.2)]
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
		# pied de l'escalier du bout de la terrasse : neige à la dernière
		# contremarche
		"plats": [[monde.call(_pied_escalier()), _o.y - ESC_HAUT, 2.0]],
		# neige au niveau du seuil de la porte Génépy (retour d'utilisateur : « tu me montes
		# le terrain jusque-là »)
		"remblais": [[monde.call(rect.call(Rect2(-DEMI_HALL - 9.0, _pg_d.x - 4.0, 8.8, _pg_d.y - _pg_d.x + 8.0))),
			_o.y + _pg_y - 0.03, 14.0]],
		# tunnel seulement, jusqu'au pignon aval, raccord court (retour d'utilisateur,
		# 07/10/2026 : « enlève le tas de neige côté est du bâtiment »)
		"couloirs": [[3430.0, tunnel.station_high_start - 0.3, 3.0, 0.8, 4.0]],
	}
