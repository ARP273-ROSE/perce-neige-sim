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
## Sol du bloc détaillé (opaque ; dessous assombri).
const SHADER_TERRAIN: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform sampler2D ortho : source_color, filter_linear_mipmap, repeat_disable;
uniform float gamma = 1.0;
uniform vec3 brume = vec3(0.50, 0.62, 0.78);
varying vec3 pw;
void vertex() {
	pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
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
