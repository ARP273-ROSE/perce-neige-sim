class_name ReliefBuilder
extends Node3D
## Vue extérieure : le VRAI massif autour du funiculaire, et le tunnel vu
## « aux rayons X » à travers la montagne.
##
## Historique : 06/10/2026, un puits autour de la rame (« 3 m après le
## départ, la vue panoramique du haut, statique, en lévitation ») ; 07/10,
## un écorché (« au lieu d'un éclaté, diminue l'opacité du sol autour du
## tunnel pour le voir en entier ») ; puis un couloir de sol translucide —
## mais à travers on voyait le vide sous la surface (« la zone marron qui
## entoure le trajet, c'est moche, et on ne voit pas les sommets juste à
## côté et au-dessus »).
##
## Maintenant le relief est OPAQUE (on voit les sommets) et c'est le tunnel
## qui se dessine à travers lui :
##  - bloc détaillé : IGN RGE ALTI à 25 m + orthophoto IGN, 8,6 × 10,2 km, du
##    sommet de la Grande Motte au lac de Tignes (tools_relief3d.py) ;
##  - anneau lointain jusqu'à l'horizon : 44 × 44 km, maille 200 m, rotondité
##    de la Terre, orthophoto IGN, brume de distance
##    (tools_relief_lointain.py) ;
##  - le tunnel EN ENTIER : un trait ambre suit son axe de bout en bout, de
##    largeur constante à l'écran, en deux passes — plein là où il est à
##    découvert, à 45 % à travers la montagne ; interrompu à la place des
##    rames et effacé près de la caméra, où l'on voit le vrai tube ;
##  - vu de dessous (caméra sous la voie, sous la montagne), le relief est
##    assombri ;
##  - les lieux nommés.
## N'existe qu'en vue extérieure (main.gd). Aucune contrainte sur la caméra.

const CHUNK: int = 64                 # mailles par côté de tuile (frustum culling)
const GAMMA_WEB: float = 0.625        # rendu Compatibility : voir MachineRoomBuilder
const Y_SOCLE: float = 1550.0
const BRUME: Color = Color(0.50, 0.62, 0.78)   # linéaire (≈ 0,73 0,81 0,90 en sRGB)
## Sol du bloc détaillé (opaque ; dessous assombri). Deux usages :
## - les tuiles du bloc (piece = 0) : percées aux emplacements des pièces
##   fines des gares (`pieces`, rectangles x0, z0, x1, z1) ;
## - les pièces fines elles-mêmes (piece = 1) : percées là où se trouvent
##   les bâtiments (masque `trous`, posé sur leur rectangle `emprise`).
const SHADER_TERRAIN: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform sampler2D ortho : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D trous : filter_nearest, repeat_disable;
uniform float gamma = 1.0;
uniform vec3 brume = vec3(0.50, 0.62, 0.78);
uniform vec4 pieces[4];
uniform int n_pieces = 0;
uniform float piece = 0.0;
uniform vec4 emprise = vec4(0.0, 0.0, 1.0, 1.0);
varying vec3 pw;
void vertex() {
	pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	if (piece < 0.5) {
		for (int i = 0; i < n_pieces; i++) {
			vec4 r = pieces[i];
			if (pw.x > r.x && pw.x < r.z && pw.z > r.y && pw.z < r.w) {
				discard;
			}
		}
	} else if (texture(trous, (pw.xz - emprise.xy) / (emprise.zw - emprise.xy)).r > 0.5) {
		discard;
	}
	vec3 c = texture(ortho, UV).rgb;
	if (!FRONT_FACING) {
		c *= 0.45;                     // dessous du relief (caméra sous la surface)
	}
	float d = distance(pw, CAMERA_POSITION_WORLD);
	ALBEDO = pow(mix(c, brume, clamp(1.0 - exp(-d / 28000.0), 0.0, 0.7)), vec3(gamma));
}
"""
## Flancs du bloc détaillé : prolongent sa bordure (couleur de l'orthophoto
## au bord) jusque sous l'anneau lointain.
const SHADER_FLANC: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform sampler2D ortho : source_color, filter_linear_mipmap, repeat_disable;
uniform float gamma = 1.0;
uniform vec3 brume = vec3(0.50, 0.62, 0.78);
varying vec3 pw;
void vertex() {
	pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
uniform vec4 bloc;                 // emprise du bloc détaillé
void fragment() {
	// caméra dans le bloc (sous la montagne) : on les verrait de l'intérieur
	vec3 cam = CAMERA_POSITION_WORLD;
	if (cam.x > bloc.x && cam.x < bloc.z && cam.z > bloc.y && cam.z < bloc.w) {
		discard;
	}
	float d = distance(pw, cam);
	ALBEDO = pow(mix(texture(ortho, UV).rgb * 0.85, brume, clamp(1.0 - exp(-d / 28000.0), 0.0, 0.7)),
		vec3(gamma));
}
"""
const SHADER_LOINTAIN: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform sampler2D ortho : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 bloc;                 // emprise du bloc détaillé (trou de l'anneau)
uniform float gamma = 1.0;
uniform vec3 brume = vec3(0.50, 0.62, 0.78);
varying vec3 pw;
void vertex() {
	pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	if (pw.x > bloc.x && pw.x < bloc.z && pw.z > bloc.y && pw.z < bloc.w) {
		discard;
	}
	vec3 c = texture(ortho, UV).rgb;
	if (!FRONT_FACING) {
		c *= 0.45;
	}
	float d = distance(pw, CAMERA_POSITION_WORLD);
	ALBEDO = pow(mix(c, brume, clamp(1.0 - exp(-d / 28000.0), 0.0, 0.7)), vec3(gamma));
}
"""
## Trait du tunnel : ruban tourné vers la caméra le long de l'axe (sommets
## posés sur l'axe, NORMAL = tangente, UV.x = côté, UV.y = abscisse s),
## ≈ 3 px de large. Deux passes : %s = mode de rendu (la passe « rayons X »
## ignore la profondeur), %s = opacité. Interrompu à la place des deux
## rames (on y voit leur silhouette) et effacé à moins de 40-160 m de la
## caméra (on y voit le vrai tube).
const SHADER_TRAIT: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, world_vertex_coords%s;
uniform vec4 couleur : source_color = vec4(1.0, 0.62, 0.15, 1.0);
uniform float px_rad = 0.0022;     // demi-largeur ≈ distance × px_rad
uniform float s_rame1 = -1000.0;
uniform float s_rame2 = -1000.0;
varying float fondu;
void vertex() {
	vec3 cam = CAMERA_POSITION_WORLD;
	float d = distance(VERTEX, cam);
	vec3 cote = normalize(cross(NORMAL, normalize(cam - VERTEX)));
	VERTEX += cote * UV.x * max(0.12, d * px_rad);
	fondu = smoothstep(40.0, 160.0, d)
		* smoothstep(18.0, 26.0, min(abs(UV.y - s_rame1), abs(UV.y - s_rame2)));
}
void fragment() {
	ALBEDO = couleur.rgb;
	ALPHA = %s * fondu;
}
"""

var tunnel: TunnelBuilder = null
var _h: PackedFloat32Array = PackedFloat32Array()
var _dx: float = 1.0
var _dz: float = 1.0
## Prêt à être affiché (construction terminée).
var pret: bool = false

# --- Construction EN TÂCHE DE FOND (optimisation du 06/10/2026 : « un beau
# truc qui ne consomme pas énormément de ressources ») -------------------
# 1. préparation des données (décodage des altitudes, sommets et indices de
#    chaque tuile, bloc détaillé puis anneau lointain) : sur PC dans un fil
#    parallèle (WorkerThreadPool) ; dans la PWA, qui n'a pas de fils, par
#    tranches de 3 ms par image sur le fil principal ;
# 2. maillages (appels au moteur de rendu) : fil principal, quelques
#    tuiles par image.
# Aucun gel au démarrage ; le relief apparaît en vue extérieure dès qu'il
# est prêt (≈ 1 s).
# Résolution selon la machine (cran du PerfManager) : maille de 25 m et
# orthophotos 2048 px pour une bonne carte graphique ; maille de 50 m
# (4 fois moins de triangles) et orthophotos 1024 px sinon.
const BUDGET_US: int = 3000
var _pas: int = 1                     # 1 = 25 m, 2 = 50 m
var _ortho_l: int = 2048
var _etape: int = 0                   # 0 décodage, 1 tuiles, 2 maillages, 3 fini
var _k: int = 0                       # avancement dans l'étape
var _octets: PackedByteArray = PackedByteArray()
var _octets_loin: PackedByteArray = PackedByteArray()
var _hl: PackedFloat32Array = PackedFloat32Array()   # anneau lointain
var _tuiles: Array = []               # [i0, i1, j0, j1, lointain]
var _tableaux: Array = []             # tableaux de sommets prêts
var _tache: int = -1
var _mat_terrain: ShaderMaterial = null
var _mat_loin: ShaderMaterial = null
var _tex_ortho: ImageTexture = null
var _mat_trait: ShaderMaterial = null

# --- aménagements des gares : pièces de terrain fines -------------------------
## Posé par main.gd avant la fin de la construction : une entrée par gare,
## {"rect": Rect2 (x, z, largeur, profondeur), "trous": [PackedVector2Array]
## (bâtiments : terrain retiré), "plats": [[PackedVector2Array, y, fondu]]
## (place, escalier : terrain aplani à y, raccordé sur `fondu` m),
## "rabots": [[PackedVector2Array, y, fondu]] (terrasse : terrain rasé
## au-dessous de y),
## "couloirs": [[s0, s1, demi_largeur, couverture]] (quais souterrains :
## terrain relevé à au moins `couverture` m au-dessus du plafond de la
## salle)}. Le relief IGN maillé à 25 m traversait les bâtiments et les
## quais (« le relief rentre dans le bâtiment et les quais », 07/10/2026).
var amenagements: Array = []
const PAS_PIECE: float = 2.0
var _rects_pieces: Array = []
var _pieces: Array = []               # [rect, nx, nz, hauteurs, masque] (bancs)


func build(t: TunnelBuilder, cran: int = 0) -> void:
	tunnel = t
	_pas = 1 if cran <= 2 else 2
	_ortho_l = 2048 if cran <= 2 else 1024
	_octets = _octets_png("res://textures/relief_hauteurs.png")
	_octets_loin = _octets_png("res://textures/relief_lointain_hauteurs.png")
	_h.resize(ReliefDonnees.NX * ReliefDonnees.NZ)
	_hl.resize(ReliefLointainDonnees.N * ReliefLointainDonnees.N)
	_dx = (ReliefDonnees.X_EST - ReliefDonnees.X_OUEST) / float(ReliefDonnees.NX - 1)
	_dz = (ReliefDonnees.Z_SUD - ReliefDonnees.Z_NORD) / float(ReliefDonnees.NZ - 1)
	var i0: int = 0
	while i0 < ReliefDonnees.NZ - 1:
		var j0: int = 0
		while j0 < ReliefDonnees.NX - 1:
			_tuiles.append([i0, mini(i0 + CHUNK * _pas, ReliefDonnees.NZ - 1),
				j0, mini(j0 + CHUNK * _pas, ReliefDonnees.NX - 1), false])
			j0 = mini(j0 + CHUNK * _pas, ReliefDonnees.NX - 1)
		i0 = mini(i0 + CHUNK * _pas, ReliefDonnees.NZ - 1)
	# anneau lointain : 4 × 4 tuiles
	var nl: int = ReliefLointainDonnees.N
	var cl: int = int(ceil((nl - 1) / 4.0))
	for a in range(4):
		for b in range(4):
			_tuiles.append([a * cl, mini((a + 1) * cl, nl - 1), b * cl, mini((b + 1) * cl, nl - 1), true])
	_tableaux.resize(_tuiles.size())
	visible = false
	if OS.has_feature("threads"):
		_tache = WorkerThreadPool.add_task(_preparer_tout, false, "relief")
	print("[Relief] maille %d m, orthophoto %d px, %d tuiles, préparation %s" % [
		25 * _pas, _ortho_l, _tuiles.size(),
		"en parallèle" if _tache >= 0 else "par tranches"])


func _octets_png(chemin: String) -> PackedByteArray:
	var img: Image = (load(chemin) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	return img.get_data()


func _process(_delta: float) -> void:
	if _etape >= 3:
		set_process(false)
		return
	if _tache >= 0:
		if not WorkerThreadPool.is_task_completed(_tache):
			return
		WorkerThreadPool.wait_for_task_completion(_tache)
		_tache = -1
	elif _etape < 2:
		_preparer(Time.get_ticks_usec() + BUDGET_US)
		return
	_creer_maillages(Time.get_ticks_usec() + BUDGET_US)


## Fil parallèle : toute la préparation d'un coup.
func _preparer_tout() -> void:
	while _etape < 2:
		_preparer(1 << 62)


## Avance la préparation jusqu'à l'échéance `fin_us` (ou la fin).
func _preparer(fin_us: int) -> void:
	var nx: int = ReliefDonnees.NX
	var nz: int = ReliefDonnees.NZ
	while _etape < 2:
		if _etape == 0:
			# décodage, une ligne de la grille à la fois : bloc détaillé,
			# puis anneau lointain
			if _k < nz:
				var base: int = _k * nx
				for j in range(nx):
					var o: int = 3 * (base + j)
					_h[base + j] = ReliefDonnees.H_BASE \
						+ float(int(_octets[o]) * 256 + int(_octets[o + 1])) * ReliefDonnees.H_ECHELLE
			else:
				_decoder_ligne_lointaine(_k - nz)
			_k += 1
			if _k >= nz + ReliefLointainDonnees.N:
				_etape = 1
				_k = 0
				_octets = PackedByteArray()
				_octets_loin = PackedByteArray()
		else:
			var t: Array = _tuiles[_k]
			_tableaux[_k] = _tableaux_lointain(t) if t[4] else _tableaux_tuile(t)
			_k += 1
			if _k >= _tuiles.size():
				_etape = 2
				_k = 0
		if Time.get_ticks_usec() > fin_us:
			return


## Ligne i de l'anneau lointain ; dans le bloc détaillé et sur une maille
## autour, ses sommets prennent l'altitude du bloc (raccord sans marche).
func _decoder_ligne_lointaine(i: int) -> void:
	var n: int = ReliefLointainDonnees.N
	var pas: float = ReliefLointainDonnees.PAS
	var z: float = ReliefLointainDonnees.Z_NORD + i * pas
	for j in range(n):
		var o: int = 3 * (i * n + j)
		var x: float = ReliefLointainDonnees.X_OUEST + j * pas
		var hh: float = float(int(_octets_loin[o]) * 256 + int(_octets_loin[o + 1])) \
			* ReliefLointainDonnees.H_ECHELLE
		if x > ReliefDonnees.X_OUEST - pas and x < ReliefDonnees.X_EST + pas \
				and z > ReliefDonnees.Z_NORD - pas and z < ReliefDonnees.Z_SUD + pas:
			hh = _hauteur_bloc(x, z)
		_hl[i * n + j] = hh


func _tableaux_tuile(t: Array) -> Array:
	var nx: int = ReliefDonnees.NX
	var nz: int = ReliefDonnees.NZ
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()
	var lignes: Array = []
	var cols: Array = []
	var i: int = t[0]
	while true:
		lignes.append(i)
		if i >= t[1]:
			break
		i = mini(i + _pas, t[1])
	var j: int = t[2]
	while true:
		cols.append(j)
		if j >= t[3]:
			break
		j = mini(j + _pas, t[3])
	var w: int = cols.size()
	for ii in lignes:
		for jj in cols:
			verts.append(Vector3(ReliefDonnees.X_OUEST + jj * _dx, _h[ii * nx + jj],
				ReliefDonnees.Z_NORD + ii * _dz))
			uvs.append(Vector2(float(jj) / (nx - 1), float(ii) / (nz - 1)))
	for a_i in range(lignes.size() - 1):
		for a_j in range(w - 1):
			var a: int = a_i * w + a_j
			idx.append_array(PackedInt32Array([a, a + 1, a + w, a + 1, a + w + 1, a + w]))
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## Tuile de l'anneau lointain : les carrés entièrement dans le bloc détaillé
## sont sautés (le nuanceur découpe exactement le bord).
func _tableaux_lointain(t: Array) -> Array:
	var n: int = ReliefLointainDonnees.N
	var pas: float = ReliefLointainDonnees.PAS
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()
	var w: int = t[3] - t[2] + 1
	for ii in range(t[0], t[1] + 1):
		for jj in range(t[2], t[3] + 1):
			verts.append(Vector3(ReliefLointainDonnees.X_OUEST + jj * pas, _hl[ii * n + jj],
				ReliefLointainDonnees.Z_NORD + ii * pas))
			uvs.append(Vector2(float(jj) / (n - 1), float(ii) / (n - 1)))
	for a_i in range(t[1] - t[0]):
		for a_j in range(w - 1):
			var x0: float = ReliefLointainDonnees.X_OUEST + (t[2] + a_j) * pas
			var z0: float = ReliefLointainDonnees.Z_NORD + (t[0] + a_i) * pas
			if x0 >= ReliefDonnees.X_OUEST and x0 + pas <= ReliefDonnees.X_EST \
					and z0 >= ReliefDonnees.Z_NORD and z0 + pas <= ReliefDonnees.Z_SUD:
				continue
			var a: int = a_i * w + a_j
			idx.append_array(PackedInt32Array([a, a + 1, a + w, a + 1, a + w + 1, a + w]))
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


func _texture_ortho(chemin: String) -> ImageTexture:
	var img: Image = (load(chemin) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	if img.get_width() > _ortho_l:
		img.resize(_ortho_l, int(img.get_height() * float(_ortho_l) / img.get_width()),
			Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Fil principal : quelques tuiles par image, puis flancs, trait du
## tunnel, lieux.
func _creer_maillages(fin_us: int) -> void:
	if _mat_terrain == null:
		_materiaux()
		return
	while _k < _tableaux.size():
		var arr: Array = _tableaux[_k]
		if (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
			var mesh: ArrayMesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			mesh.surface_set_material(0, _mat_loin if _tuiles[_k][4] else _mat_terrain)
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
		_tableaux[_k] = null
		_k += 1
		if Time.get_ticks_usec() > fin_us:
			return
	_build_pieces()
	_build_flancs()
	_build_trait()
	_build_lieux()
	_tableaux.clear()
	_etape = 3
	pret = true
	print("[Relief] prêt")


func _materiaux() -> void:
	_tex_ortho = _texture_ortho("res://textures/relief_ortho.jpg")
	_mat_terrain = _shader(SHADER_TERRAIN)
	_mat_terrain.set_shader_parameter("ortho", _tex_ortho)
	_mat_loin = _shader(SHADER_LOINTAIN)
	_mat_loin.set_shader_parameter("ortho", _texture_ortho("res://textures/relief_lointain.jpg"))
	_mat_loin.set_shader_parameter("bloc", Vector4(ReliefDonnees.X_OUEST, ReliefDonnees.Z_NORD,
		ReliefDonnees.X_EST, ReliefDonnees.Z_SUD))


## Altitude sur les triangles du maillage du bloc (comme les tuiles) : les
## pièces fines s'y raccordent sans marche.
func _hauteur_tri(x: float, z: float) -> float:
	var lim_x: int = ReliefDonnees.NX - 1
	var lim_z: int = ReliefDonnees.NZ - 1
	var fx: float = clampf((x - ReliefDonnees.X_OUEST) / _dx, 0.0, lim_x - 0.001) / _pas
	var fz: float = clampf((z - ReliefDonnees.Z_NORD) / _dz, 0.0, lim_z - 0.001) / _pas
	var j0: int = int(fx) * _pas
	var i0: int = int(fz) * _pas
	var wx: float = fx - int(fx)
	var wz: float = fz - int(fz)
	var j1: int = mini(j0 + _pas, lim_x)
	var i1: int = mini(i0 + _pas, lim_z)
	var n: int = ReliefDonnees.NX
	var a: float = _h[i0 * n + j0]
	var b: float = _h[i0 * n + j1]
	var c: float = _h[i1 * n + j0]
	var d: float = _h[i1 * n + j1]
	# même découpe que les tuiles : (a, a+1, a+w) puis (a+1, a+w+1, a+w)
	if wx + wz <= 1.0:
		return a + (b - a) * wx + (c - a) * wz
	return d + (c - d) * (1.0 - wx) + (b - d) * (1.0 - wz)


## Distance d'un point à un polygone (0 dedans).
static func _dist_poly(q: Vector2, poly: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(q, poly):
		return 0.0
	var d: float = INF
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		d = minf(d, q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)))
	return d


## Pièces de terrain fines (maille de 2 m) autour des gares.
func _build_pieces() -> void:
	_rects_pieces.clear()
	for am in amenagements:
		_build_piece(am)
	var v: Array = []
	for r in _rects_pieces:
		v.append(Vector4(r.position.x, r.position.y, r.end.x, r.end.y))
	while v.size() < 4:
		v.append(Vector4.ZERO)
	_mat_terrain.set_shader_parameter("pieces", v)
	_mat_terrain.set_shader_parameter("n_pieces", mini(_rects_pieces.size(), 4))


func _build_piece(am: Dictionary) -> void:
	var r: Rect2 = am["rect"]
	var nx: int = int(ceil(r.size.x / PAS_PIECE)) + 1
	var nz: int = int(ceil(r.size.y / PAS_PIECE)) + 1
	var lx: float = r.size.x / (nx - 1)
	var lz: float = r.size.y / (nz - 1)
	# axe des couloirs : points de la voie tous les 2 m
	var axes: Array = []
	for c in am.get("couloirs", []):
		var pts: Array = []
		var s: float = c[0] - 12.0
		while s <= c[1] + 12.0:
			var sc: float = clampf(s, 0.0, PNConstants.LENGTH)
			var xf: Transform3D = tunnel.transform_at(sc)
			var t: Vector3 = -xf.basis.z
			var p: Vector3 = xf.origin + t * (s - sc)
			pts.append([s, p])
			s += 2.0
		axes.append([c, pts])
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()
	for i in range(nz):
		for j in range(nx):
			var x: float = r.position.x + j * lx
			var z: float = r.position.y + i * lz
			var q: Vector2 = Vector2(x, z)
			var h: float = _hauteur_tri(x, z)
			# bords de la pièce : exactement le bloc (aucune marche)
			var bord: bool = i == 0 or j == 0 or i == nz - 1 or j == nx - 1
			if not bord:
				# quais souterrains : relevé au-dessus du plafond de la salle
				for ax in axes:
					var c: Array = ax[0]
					var best: float = INF
					var bp: Array = []
					for e in ax[1]:
						var dd: float = q.distance_squared_to(Vector2(e[1].x, e[1].z))
						if dd < best:
							best = dd
							bp = e
					var travers: float = sqrt(best)
					var s_p: float = bp[0]
					var w: float = (1.0 - smoothstep(c[2], c[2] + 10.0, travers)) \
						* (1.0 - smoothstep(0.0, 10.0, maxf(c[0] - s_p, s_p - c[1])))
					var cible: float = (bp[1] as Vector3).y + tunnel.station_room_half_height + c[3]
					h += maxf(cible - h, 0.0) * w
				# place, escalier : aplanis
				for pl in am.get("plats", []):
					var d: float = _dist_poly(q, pl[0])
					var w2: float = 1.0 - smoothstep(0.0, pl[2], d)
					h = lerpf(h, pl[1], w2)
				# terrasse sur pilotis : terrain rasé sous son niveau
				for rb in am.get("rabots", []):
					if h > rb[1]:
						var w3: float = 1.0 - smoothstep(0.0, rb[2], _dist_poly(q, rb[0]))
						h = lerpf(h, rb[1], w3)
			verts.append(Vector3(x, h, z))
			uvs.append(Vector2((x - ReliefDonnees.X_OUEST) / (ReliefDonnees.X_EST - ReliefDonnees.X_OUEST),
				(z - ReliefDonnees.Z_NORD) / (ReliefDonnees.Z_SUD - ReliefDonnees.Z_NORD)))
	for i in range(nz - 1):
		for j in range(nx - 1):
			var a: int = i * nx + j
			idx.append_array(PackedInt32Array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx]))
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# masque des bâtiments (0,25 m par pixel)
	var mw: int = int(ceil(r.size.x * 4.0))
	var mh: int = int(ceil(r.size.y * 4.0))
	var img: Image = Image.create(mw, mh, false, Image.FORMAT_L8)
	for poly in am.get("trous", []):
		var bb: Rect2 = Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			bb = bb.expand(v)
		var i0: int = clampi(int((bb.position.y - r.position.y) * 4.0), 0, mh - 1)
		var i1: int = clampi(int((bb.end.y - r.position.y) * 4.0) + 1, 0, mh - 1)
		var j0: int = clampi(int((bb.position.x - r.position.x) * 4.0), 0, mw - 1)
		var j1: int = clampi(int((bb.end.x - r.position.x) * 4.0) + 1, 0, mw - 1)
		for i in range(i0, i1 + 1):
			for j in range(j0, j1 + 1):
				var q: Vector2 = r.position + Vector2((j + 0.5) / 4.0, (i + 0.5) / 4.0)
				if Geometry2D.is_point_in_polygon(q, poly):
					img.set_pixel(j, i, Color.WHITE)
	var mat: ShaderMaterial = _shader(SHADER_TERRAIN)
	mat.set_shader_parameter("ortho", _tex_ortho)
	mat.set_shader_parameter("piece", 1.0)
	mat.set_shader_parameter("trous", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("emprise", Vector4(r.position.x, r.position.y, r.end.x, r.end.y))
	mesh.surface_set_material(0, mat)
	_instance(mesh, "PieceGare")
	_rects_pieces.append(r)
	var hs: PackedFloat32Array = PackedFloat32Array()
	for v in verts:
		hs.append(v.y)
	_pieces.append([r, nx, nz, hs, img])


## Terrain affiché en (x, z) dans une pièce fine : [altitude, retiré (dans
## un bâtiment)] ; [NAN, false] hors des pièces. Pour les bancs.
func terrain_piece(x: float, z: float) -> Array:
	for pc in _pieces:
		var r: Rect2 = pc[0]
		if not r.has_point(Vector2(x, z)):
			continue
		var nx: int = pc[1]
		var nz: int = pc[2]
		var fx: float = (x - r.position.x) / r.size.x * (nx - 1)
		var fz: float = (z - r.position.y) / r.size.y * (nz - 1)
		var j: int = clampi(int(fx), 0, nx - 2)
		var i: int = clampi(int(fz), 0, nz - 2)
		var u: float = fx - j
		var v: float = fz - i
		var hs: PackedFloat32Array = pc[3]
		var h: float = lerpf(lerpf(hs[i * nx + j], hs[i * nx + j + 1], u),
			lerpf(hs[(i + 1) * nx + j], hs[(i + 1) * nx + j + 1], u), v)
		var img: Image = pc[4]
		var mx: int = clampi(int((x - r.position.x) * 4.0), 0, img.get_width() - 1)
		var mz: int = clampi(int((z - r.position.y) * 4.0), 0, img.get_height() - 1)
		return [h, img.get_pixel(mx, mz).r > 0.5]
	return [NAN, false]


## Abscisses des deux rames : le trait du tunnel s'y interrompt.
func set_rames(s1: float, s2: float) -> void:
	for m in [_mat_trait, _mat_trait.next_pass if _mat_trait != null else null]:
		if m != null:
			m.set_shader_parameter("s_rame1", s1)
			m.set_shader_parameter("s_rame2", s2)


func _shader(code: String) -> ShaderMaterial:
	var sh: Shader = Shader.new()
	sh.code = code
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("gamma", _gamma())
	m.set_shader_parameter("brume", Vector3(BRUME.r, BRUME.g, BRUME.b))
	return m


func _instance(mesh: Mesh, nom: String) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = nom
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Trait du tunnel : l'axe de bout en bout, tous les 10 m.
func _build_trait() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: PackedVector3Array = PackedVector3Array()
	var s: float = 0.0
	while s < PNConstants.LENGTH:
		pts.append(tunnel.transform_at(s).origin)
		s += 10.0
	pts.append(tunnel.transform_at(PNConstants.LENGTH).origin)
	for k in range(pts.size() - 1):
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var sa: float = minf(k * 10.0, PNConstants.LENGTH)
		var sb: float = minf((k + 1) * 10.0, PNConstants.LENGTH)
		var t: Vector3 = (b - a).normalized()
		for e in [[a, -1.0, sa], [b, -1.0, sb], [b, 1.0, sb], [a, -1.0, sa], [b, 1.0, sb], [a, 1.0, sa]]:
			st.set_normal(t)
			st.set_uv(Vector2(e[1], e[2]))
			st.add_vertex(e[0])
	# plein là où il est à découvert, 45 % à travers la montagne
	_mat_trait = _shader(SHADER_TRAIT % ["", "couleur.a"])
	var rx: ShaderMaterial = _shader(SHADER_TRAIT % [", depth_test_disabled", "0.45"])
	_mat_trait.next_pass = rx
	st.set_material(_mat_trait)
	var mi: MeshInstance3D = _instance(st.commit(), "TraitTunnel")
	mi.extra_cull_margin = 50.0


## Flancs du bloc détaillé (« jupe ») : de sa bordure jusqu'à Y_SOCLE, sous
## l'anneau lointain, colorés comme le bord de l'orthophoto — ils bouchent
## les écarts entre les deux maillages.
func _build_flancs() -> void:
	var mat: ShaderMaterial = _shader(SHADER_FLANC)
	mat.set_shader_parameter("ortho", _tex_ortho)
	mat.set_shader_parameter("bloc", Vector4(ReliefDonnees.X_OUEST, ReliefDonnees.Z_NORD,
		ReliefDonnees.X_EST, ReliefDonnees.Z_SUD))
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx: int = ReliefDonnees.NX
	var nz: int = ReliefDonnees.NZ
	var b0: Array = []
	var b1: Array = []
	var b2: Array = []
	var b3: Array = []
	for j in range(nx):
		b0.append(Vector2i(0, j))
		b2.append(Vector2i(nz - 1, nx - 1 - j))
	for i in range(nz):
		b1.append(Vector2i(i, nx - 1))
		b3.append(Vector2i(nz - 1 - i, 0))
	for bord in [b0, b1, b2, b3]:
		for k in range(bord.size() - 1):
			var a: Vector2i = bord[k]
			var b: Vector2i = bord[k + 1]
			var pa: Vector3 = Vector3(ReliefDonnees.X_OUEST + a.y * _dx, _h[a.x * nx + a.y], ReliefDonnees.Z_NORD + a.x * _dz)
			var pb: Vector3 = Vector3(ReliefDonnees.X_OUEST + b.y * _dx, _h[b.x * nx + b.y], ReliefDonnees.Z_NORD + b.x * _dz)
			var ua: Vector2 = Vector2(float(a.y) / (nx - 1), float(a.x) / (nz - 1))
			var ub: Vector2 = Vector2(float(b.y) / (nx - 1), float(b.x) / (nz - 1))
			var qa: Vector3 = Vector3(pa.x, Y_SOCLE, pa.z)
			var qb: Vector3 = Vector3(pb.x, Y_SOCLE, pb.z)
			for e in [[pa, ua], [pb, ub], [qb, ub], [pa, ua], [qb, ub], [qa, ua]]:
				st.set_uv(e[1])
				st.add_vertex(e[0])
	st.set_material(mat)
	_instance(st.commit(), "Flancs")


## Altitude du terrain (m) au point (x, z) du repère du jeu, bilinéaire,
## dans le bloc détaillé (−INF tant qu'il n'est pas décodé).
func hauteur(x: float, z: float) -> float:
	if _etape < 1:
		return -INF
	return _hauteur_bloc(x, z)


func _hauteur_bloc(x: float, z: float) -> float:
	var fx: float = clampf((x - ReliefDonnees.X_OUEST) / _dx, 0.0, ReliefDonnees.NX - 1.001)
	var fz: float = clampf((z - ReliefDonnees.Z_NORD) / _dz, 0.0, ReliefDonnees.NZ - 1.001)
	var i: int = int(fz)
	var j: int = int(fx)
	var u: float = fx - j
	var v: float = fz - i
	var n: int = ReliefDonnees.NX
	return lerpf(lerpf(_h[i * n + j], _h[i * n + j + 1], u),
		lerpf(_h[(i + 1) * n + j], _h[(i + 1) * n + j + 1], u), v)


## Altitude partout : bloc détaillé, sinon anneau lointain.
func hauteur_partout(x: float, z: float) -> float:
	if _etape < 1:
		return -INF
	if x >= ReliefDonnees.X_OUEST and x <= ReliefDonnees.X_EST \
			and z >= ReliefDonnees.Z_NORD and z <= ReliefDonnees.Z_SUD:
		return _hauteur_bloc(x, z)
	var n: int = ReliefLointainDonnees.N
	var pas: float = ReliefLointainDonnees.PAS
	var fx: float = clampf((x - ReliefLointainDonnees.X_OUEST) / pas, 0.0, n - 1.001)
	var fz: float = clampf((z - ReliefLointainDonnees.Z_NORD) / pas, 0.0, n - 1.001)
	var i: int = int(fz)
	var j: int = int(fx)
	var u: float = fx - j
	var v: float = fz - i
	return lerpf(lerpf(_hl[i * n + j], _hl[i * n + j + 1], u),
		lerpf(_hl[(i + 1) * n + j], _hl[(i + 1) * n + j + 1], u), v)


func _gamma() -> float:
	return GAMMA_WEB if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 1.0


func _build_lieux() -> void:
	for l in ReliefDonnees.LIEUX:
		var lab: Label3D = Label3D.new()
		var nom: String = l[0]
		lab.text = nom if int(l[3]) == 0 else "%s\n%d m" % [nom, int(l[3])]
		lab.font_size = 34
		lab.outline_size = 10
		lab.modulate = Color(1.0, 1.0, 1.0)
		lab.outline_modulate = Color(0.05, 0.08, 0.15)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.fixed_size = true
		lab.pixel_size = 0.0009
		lab.no_depth_test = true
		lab.render_priority = 2
		lab.position = Vector3(l[1], hauteur(l[1], l[2]) + 40.0, l[2])
		add_child(lab)
