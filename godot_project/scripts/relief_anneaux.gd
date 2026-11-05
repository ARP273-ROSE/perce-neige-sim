class_name ReliefAnneaux
extends Node3D
## Affichage du sol au mètre (pack haute définition, PC) : anneaux emboîtés autour de la caméra,
## un nœud sur 1, 2, 4, 8 puis 16. Le maillage ne change jamais : le nuanceur de sommets lit les
## altitudes d'une texture par anneau, recalculée sur un fil de travail quand la caméra a fait
## 32 m ; plus de construction de maillage ni de reconstruction visible. Chaque anneau rejoint
## le suivant à son bord (morphing selon la distance), le dernier se pose sur les tuiles à 25 m.
## Altitudes des anneaux filtrées d'un niveau à l'autre : sans crénelage sur les barres rocheuses.
## L'ombrage vient d'un tableau de textures de normales au mètre, valable à toute distance.

const M: int = 512                     # mailles par côté d'un anneau, multiple de 4
static var NIVEAUX: int = 5
static var SAUT: int = 32              # les anneaux se déplacent ensemble, de 2^NIVEAUX nœuds
const TUILE: int = 2000                # nœuds par couche du tableau de textures
const TAILLE: int = 2048               # texels par couche, dont
const MARGE: int = 24                  # la marge prise aux voisines (filtrage, niveaux)

const _ENTETE_DETAIL: String = """uniform sampler2D detail_hd : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float a_detail = 0.0;
// Neige de près : pente de bosses à plusieurs échelles et sillons de vent ; xyz normale, w fondu.
vec4 neige_detail(vec3 p, vec3 n, float d_cam) {
	float pres = (1.0 - smoothstep(100.0, 200.0, d_cam)) * a_detail;
	if (pres <= 0.0) {
		return vec4(n, 0.0);
	}
	vec2 q = p.xz;
	vec2 g = (texture(detail_hd, q / 41.0).rg - vec2(0.5)) * 0.30
		+ (texture(detail_hd, q / 9.3 + vec2(0.37, 0.11)).rg - vec2(0.5)) * 0.22
		+ (texture(detail_hd, q / 2.3 + vec2(0.71, 0.53)).rg - vec2(0.5)) * 0.10;
	// sillons de vent : étirés suivant une direction fixe
	const vec2 V = vec2(0.82, 0.57);
	vec2 qv = vec2(dot(q, V), dot(q, vec2(-V.y, V.x)));
	vec2 gv = texture(detail_hd, qv * vec2(1.0 / 37.0, 1.0 / 2.9)).rg - vec2(0.5);
	g += vec2(-V.y, V.x) * gv.g * 0.22;
	return vec4(normalize(n + vec3(g.x, 0.0, g.y) * pres), pres);
}
// Paillettes : un grain fin qui change avec le regard, au soleil, discret, à moins de 50 m.
float paillettes(vec3 p, vec3 n, vec3 cam, float d_cam) {
	if (a_detail < 0.5 || d_cam > 50.0) {
		return 0.0;
	}
	vec3 v = (cam - p) / max(d_cam, 0.01);
	vec2 s = p.xz * 0.37 + v.xz * 0.17;
	float b = texture(detail_hd, s).b;
	float soleil_vu = max(dot(normalize(v + normalize(soleil)), n), 0.0);
	return smoothstep(0.965, 0.995, b) * (1.0 - smoothstep(12.0, 50.0, d_cam)) * smoothstep(0.75, 0.97, soleil_vu);
}
"""

## Ce qui remplace, dans le nuanceur du relief, la normale du sommet et les UV du maillage.
const _ENTETE_HD: String = """varying vec3 nw;
uniform sampler2DArray normal_hd : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 hd_xf;                 // x0, z0, px, pz
uniform vec4 hd_tex;                // nœuds par couche, texels, marge, couches par ligne
uniform vec4 o_xf;                  // photo : x0, z0, pas des nœuds au mètre
uniform vec4 o_tex;                 // nœuds par couche, marge en nœuds, couches par ligne, dernière ligne
uniform vec2 hd_nb;                 // dernier nœud (j, i)
""" + _ENTETE_DETAIL + """uniform sampler2DArray ortho_hd : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float a_ortho = 0.0;        // 1 : orthophoto au mètre présente
const float PAROI_BAS = 0.50;
const float PAROI_HAUT = 0.72;
vec3 normale_hd(vec2 p) {
	vec2 nn = (p - hd_xf.xy) / hd_xf.zw;
	vec2 t = clamp(floor(nn / hd_tex.x), vec2(0.0), floor((hd_nb - vec2(0.5)) / hd_tex.x));
	vec2 uv = (nn - t * hd_tex.x + hd_tex.z + 0.5) / hd_tex.y;
	vec2 g = textureGrad(normal_hd, vec3(uv, t.y * hd_tex.w + t.x), dFdx(nn) / hd_tex.y, dFdy(nn) / hd_tex.y).rg * 2.0 - 1.0;
	return vec3(g.x, sqrt(max(1.0 - dot(g, g), 0.0)), g.y);
}
// Photo au mètre ; au-delà de 16 m par texel, la photo d'ensemble (la marge entre couches ne suffit plus)
vec3 photo_hd(vec2 p, vec3 c_loin) {
	if (a_ortho < 0.5) {
		return c_loin;
	}
	vec2 nn = (p - o_xf.xy) / o_xf.zw;
	vec2 dx_n = dFdx(nn);
	vec2 dy_n = dFdy(nn);
	float lod = 0.5 * log2(max(max(dot(dx_n, dx_n), dot(dy_n, dy_n)), 1e-6));
	float k = smoothstep(4.0, 5.0, lod);
	if (k >= 1.0) {
		return c_loin;
	}
	vec2 t = clamp(floor(nn / o_tex.x), vec2(0.0), vec2(o_tex.z - 1.0, o_tex.w));
	float couverts = o_tex.x + 2.0 * o_tex.y;
	vec2 uv = (nn - t * o_tex.x + o_tex.y + 0.5) / couverts;
	vec3 c = textureGrad(ortho_hd, vec3(uv, t.y * o_tex.z + t.x), dx_n / couverts, dy_n / couverts).rgb;
	// paroi raide : la photo, prise d'en haut, s'y étire en traînées. Sa couleur moyenne et un grain
	// projeté sur les plans verticaux la remplacent ; rien ne change sur les pentes ordinaires.
	vec3 nf = normale_hd(p);
	float raide = (1.0 - smoothstep(PAROI_BAS, PAROI_HAUT, nf.y)) * a_detail;
	if (raide > 0.0) {
		vec3 fond = textureGrad(ortho_hd, vec3(uv, t.y * o_tex.z + t.x), dx_n * 32.0 / couverts, dy_n * 32.0 / couverts).rgb;
		float ax = abs(nf.x) / max(abs(nf.x) + abs(nf.z), 0.001);
		float g = mix(texture(detail_hd, pw.xy / 9.0).a, texture(detail_hd, pw.zy / 9.0).a, ax) - 0.5;
		g += (mix(texture(detail_hd, pw.xy / 2.3).a, texture(detail_hd, pw.zy / 2.3).a, ax) - 0.5) * 0.5;
		c = mix(c, fond * (1.0 + g * 1.3), raide);
	}
	return mix(c, c_loin, k);
}
"""
## Sommets d'un anneau : position et altitude lues de sa texture.
const _SOMMETS_ANNEAU: String = """uniform sampler2D anneau : filter_nearest, repeat_disable;
uniform vec4 a_o;                   // premier nœud (j, i), pas en nœuds
uniform vec2 a_m;                   // début et fin du morphing (m de la caméra)
void vertex() {
	ivec2 g = ivec2(VERTEX.xz);
	vec2 nn = clamp(a_o.xy + vec2(g) * a_o.z, vec2(0.0), hd_nb);
	vec2 w = hd_xf.xy + nn * hd_xf.zw;
	vec4 t0 = texelFetch(anneau, g, 0);
	float d = max(abs(w.x - CAMERA_POSITION_WORLD.x), abs(w.y - CAMERA_POSITION_WORLD.z));
	float al = clamp((d - a_m.x) / (a_m.y - a_m.x), 0.0, 1.0);
	VERTEX = vec3(w.x, mix(t0.r, t0.g, al), w.y);
	NORMAL = vec3(0.0, 1.0, 0.0);
	pw = VERTEX;
	nw = NORMAL;
}
"""

var _fin: ReliefFin = null
var _rel: ReliefBuilder = null
var _hd: RefCounted = null
var _a_mailler: Array = []
var _quarts: Array = []
var _installe: bool = false
var _images: Array = []
var _textures: Array = []
var _mats: Array = []
var _instances: Array = []             # [niveau, quart, MeshInstance3D]
var _cj: int = 0
var _ci: int = 0
var _demande: Vector2i = Vector2i.ZERO
var _resultat: Array = []
var _tache: int = -1
## Banc : durée des mises à jour sur le fil principal et sur le fil de travail (µs)
var dernier_calcul_us: int = 0
var dernier_envoi_us: int = 0
var nb_recentrages: int = 0


## Le nuanceur du relief, avec les normales du pack et sans les UV du maillage.
const _L_DETAIL: String = "float l = 0.36 + 0.74 * max(dot(n_fin.xyz, normalize(soleil)), 0.0);"
const _FIN_DETAIL: String = "blanc += vec3(0.5) * paillettes(pw, n_fin.xyz, cam, d_cam) * neige;\n\t// grain de la roche, sur la photo sombre, près de l'œil\n\tfloat roche = n_fin.w * (1.0 - neige) * (1.0 - smoothstep(0.25, 0.6, grain));\n\tvec3 c_roc = c * (1.0 + roche * ((texture(detail_hd, pw.xz / 5.3).a - 0.5) * 1.1 + (texture(detail_hd, pw.xz / 1.3).a - 0.5) * 0.3));\n\treturn mix(c, mix(c_roc * 0.80, blanc, neige) * l, hiver);"


## Sans le pack (PC) : le même détail de neige et de roche, sur la normale du maillage.
static func code_detail(code: String) -> String:
	return code.replace("varying vec3 nw;", "varying vec3 nw;\n" + _ENTETE_DETAIL) \
		.replace("vec3 n = normalize(nw);", "vec3 n = normalize(nw);\n\tfloat d_cam = distance(pw, cam);\n\tvec4 n_fin = neige_detail(pw, n, d_cam);") \
		.replace("float l = 0.36 + 0.74 * max(dot(n, normalize(soleil)), 0.0);", _L_DETAIL) \
		.replace("return mix(c, mix(c * 0.80, blanc, neige) * l, hiver);", _FIN_DETAIL)


static func code_hd(code: String) -> String:
	return code.replace("varying vec3 nw;", _ENTETE_HD) \
		.replace("vec3 n = normalize(nw);", "vec3 n = normale_hd(pw.xz);\n\tfloat d_cam = distance(pw, cam);\n\tvec4 n_fin = neige_detail(pw, n, d_cam);") \
		.replace("float l = 0.36 + 0.74 * max(dot(n, normalize(soleil)), 0.0);", _L_DETAIL) \
		.replace("return mix(c, mix(c * 0.80, blanc, neige) * l, hiver);", _FIN_DETAIL) \
		.replace("vec3 c = texture(ortho, UV).rgb;", "vec2 uv_hd = (pw.xz - hd_xf.xy) / (hd_xf.zw * hd_nb);\n\tvec3 c = photo_hd(pw.xz, texture(ortho, uv_hd).rgb);") \
		.replace("c = en_hiver(c, UV, CAMERA_POSITION_WORLD);", "c = en_hiver(c, uv_hd, CAMERA_POSITION_WORLD);")


## Voie moyenne : un anneau de moins, la grille est déjà 2,5 fois plus grosse.
static func regler_niveaux(niveau: int) -> void:
	NIVEAUX = 5 if niveau >= 2 else 4
	SAUT = 1 << NIVEAUX


static var _tex_detail: ImageTexture = null


## Texture de détail, une fois pour toutes (« --sans-detail » : pour en mesurer le coût).
static func preparer_detail() -> void:
	if _tex_detail != null or "--sans-detail" in OS.get_cmdline_user_args():
		return
	var octets: PackedByteArray = ClassDB.instantiate("ReliefHD").call("texture_detail", 512)
	var img: Image = Image.create_from_data(512, 512, false, Image.FORMAT_RGBA8, octets)
	img.generate_mipmaps()
	_tex_detail = ImageTexture.create_from_image(img)


static func regler_detail_seul(m: ShaderMaterial) -> void:
	if _tex_detail != null:
		m.set_shader_parameter("detail_hd", _tex_detail)
		m.set_shader_parameter("a_detail", 1.0)


static func regler_hd(m: ShaderMaterial, normales: Texture2DArrayRD, ortho: Texture2DArrayRD = null) -> void:
	m.set_shader_parameter("normal_hd", normales)
	if _tex_detail != null:
		m.set_shader_parameter("detail_hd", _tex_detail)
		m.set_shader_parameter("a_detail", 1.0)
	if ortho != null:
		m.set_shader_parameter("ortho_hd", ortho)
		m.set_shader_parameter("a_ortho", 1.0)
		m.set_shader_parameter("o_xf", Vector4(ReliefFin.X0, ReliefFin.Z0, ReliefFin.L_X / ReliefFin.KHD, ReliefFin.L_Z / ReliefFin.KHD))
		m.set_shader_parameter("o_tex", Vector4(TUILE, MARGE, (ReliefFin.NCX * ReliefFin.KHD + TUILE - 1) / TUILE, (ReliefFin.NCZ * ReliefFin.KHD + TUILE - 1) / TUILE - 1))
	m.set_shader_parameter("hd_xf", Vector4(ReliefFin.X0, ReliefFin.Z0, ReliefFin.PX, ReliefFin.PZ))
	m.set_shader_parameter("hd_tex", Vector4(TUILE, TAILLE, MARGE, (ReliefFin.NJ - 1 + TUILE - 1) / TUILE))
	m.set_shader_parameter("hd_nb", Vector2(ReliefFin.NJ - 1, ReliefFin.NI - 1))


## Fil de préparation : les tableaux des quarts d'anneaux, sans trou puis avec le trou de l'anneau
## précédent (une maille de recouvrement : au bord, l'anneau précédent est sur la même surface, et
## sans lui les jonctions en T laissaient passer des points de ciel).
static func preparer_quarts() -> Array:
	var hd: RefCounted = ClassDB.instantiate("ReliefHD")
	var r: Array = []
	var d: int = M / 2
	for avec_trou in [false, true]:
		for k in range(4):
			r.append(hd.call("quart_anneau", d if k & 1 else 0, d if k & 2 else 0, d,
				M / 4 + 1 if avec_trou else 0, 3 * M / 4 - 1 if avec_trou else 0))
	return r


func demarrer(fin: ReliefFin, rel: ReliefBuilder) -> void:
	name = "ReliefAnneaux"
	_fin = fin
	_rel = rel
	_hd = ClassDB.instantiate("ReliefHD")
	_a_mailler = fin.quarts_anneaux
	fin.quarts_anneaux = []


## Une surface par image : 66 000 sommets chacune, envoyées une par une.
func _mailler_un() -> void:
	var t: Array = _a_mailler.pop_front()
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = t[0]
	arr[Mesh.ARRAY_INDEX] = t[1]
	var m: ArrayMesh = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_quarts.append(m)
	_a_installer = _a_mailler.is_empty()


var _a_installer: bool = false
var _n_installe: int = -1
var _code_anneau: String = ""


## Une étape par image (ensemble : 110 ms en fin de chargement) : hauteurs calculées sur un autre
## fil, puis un anneau à la fois.
func _installer_pas() -> void:
	if _tache >= 0:
		if not WorkerThreadPool.is_task_completed(_tache):
			return
		WorkerThreadPool.wait_for_task_completion(_tache)
		_tache = -1
	if _n_installe < 0:
		_code_anneau = _code_des_anneaux()
		_demande = _noeud_vue()
		_tache = WorkerThreadPool.add_task(_calculer, false, "anneaux du relief")
		_n_installe = 0
	elif _n_installe < NIVEAUX:
		_installer_niveau(_n_installe)
		_n_installe += 1
	else:
		_cj = _demande.x
		_ci = _demande.y
		_resultat = []
		_code_anneau = ""
		_regler_uniformes()
		_rel._poser_trous()
		_installe = true


func _code_des_anneaux() -> String:
	var code: String = code_hd(ReliefBuilder.SHADER_TERRAIN)
	# les sommets du relief (tuiles) laissent place à ceux de l'anneau
	var deb: int = code.find("void vertex() {")
	var fin_v: int = code.find("}", deb) + 1
	return code.substr(0, deb) + _SOMMETS_ANNEAU + code.substr(fin_v)


func _installer_niveau(n: int) -> void:
	var rel: ReliefBuilder = _rel
	var img: Image = Image.create_from_data(M + 1, M + 1, false, Image.FORMAT_RGF, _resultat[n])
	_images.append(img)
	_textures.append(ImageTexture.create_from_image(img))
	# (un seul nuanceur pour les cinq anneaux : compilé cinq fois, il gelait l'image 0,5 s)
	var mat: ShaderMaterial = rel._shader(_code_anneau) if _mats.is_empty() else (_mats[0] as ShaderMaterial).duplicate()
	mat.set_shader_parameter("ortho", rel._tex_ortho)
	regler_hd(mat, rel._tex_normales, rel._tex_ortho_hd)
	mat.set_shader_parameter("anneau", _textures[n])
	mat.set_shader_parameter("piece", 0.0)
	rel._hiver_mat(mat, true)
	_mats.append(mat)
	for k in range(4):
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Anneau%d_%d" % [n, k]
		mi.mesh = _quarts[(0 if n == 0 else 4) + k]
		mi.material_override = mat
		mi.layers = 1 | Cabin.LAYER_RELIEF
		mi.set_meta("sans_collision", true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_instances.append([n, k, mi])
## Repli en jeu : sans le détail de la neige. Les anneaux restent posés.
func regler_detail(actif: bool) -> void:
	var v: float = 1.0 if actif and _tex_detail != null else 0.0
	for m in _mats:
		(m as ShaderMaterial).set_shader_parameter("a_detail", v)
	_rel._mat_terrain.set_shader_parameter("a_detail", v)


func _noeud_vue() -> Vector2i:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var p: Vector3 = cam.global_position if cam != null else Vector3.ZERO
	var j: int = int(round((p.x - ReliefFin.X0) / ReliefFin.PX / SAUT)) * SAUT
	var i: int = int(round((p.z - ReliefFin.Z0) / ReliefFin.PZ / SAUT)) * SAUT
	return Vector2i(clampi(j, 0, (ReliefFin.NJ - 1) / SAUT * SAUT), clampi(i, 0, (ReliefFin.NI - 1) / SAUT * SAUT))


func _regler_uniformes() -> void:
	for n in range(NIVEAUX):
		var s: int = 1 << n
		var m: ShaderMaterial = _mats[n]
		m.set_shader_parameter("a_o", Vector4(_cj - (M / 2) * s, _ci - (M / 2) * s, s, 0.0))
		var demi: float = (M / 2) * s
		# plein morphing avant le bord le plus proche possible de la caméra (décalée de SAUT / 2 au plus)
		var m1: float = demi - float(SAUT) * 0.5 - 2.0 * s
		m.set_shader_parameter("a_m", Vector2(m1 - 0.25 * demi, m1))
	for e in _instances:
		var n: int = e[0]
		var k: int = e[1]
		var s: int = 1 << n
		var d: int = M / 2 * s
		var j0: int = _cj - d + (d if k & 1 else 0)
		var i0: int = _ci - d + (d if k & 2 else 0)
		var mi: MeshInstance3D = e[2]
		mi.custom_aabb = AABB(Vector3(ReliefFin.X0 + j0 * ReliefFin.PX, 0.0, ReliefFin.Z0 + i0 * ReliefFin.PZ),
			Vector3(d * ReliefFin.PX, 6000.0, d * ReliefFin.PZ))
	# le relief à 25 m s'efface sous le dernier anneau
	var dn: int = (M / 2) << (NIVEAUX - 1)
	var ja: int = maxi(_cj - dn, 0)
	var ia: int = maxi(_ci - dn, 0)
	var jb: int = mini(_cj + dn, ReliefFin.NJ - 1)
	var ib: int = mini(_ci + dn, ReliefFin.NI - 1)
	_rel.percer("relief_fin", Rect2(ReliefFin.X0 + ja * ReliefFin.PX, ReliefFin.Z0 + ia * ReliefFin.PZ, (jb - ja) * ReliefFin.PX, (ib - ia) * ReliefFin.PZ))


func _process(_dt: float) -> void:
	if not _installe:
		if not _a_mailler.is_empty():
			_mailler_un()
		elif _a_installer:
			_installer_pas()
		return
	if _tache >= 0:
		if not WorkerThreadPool.is_task_completed(_tache):
			return
		WorkerThreadPool.wait_for_task_completion(_tache)
		_tache = -1
		_poser()
	var c: Vector2i = _noeud_vue()
	if c.x != _cj or c.y != _ci:
		_demande = c
		_tache = WorkerThreadPool.add_task(_calculer, false, "anneaux du relief")


func _calculer() -> void:
	var t0: int = Time.get_ticks_usec()
	_resultat = _hd.call("anneaux", _fin.noeuds_grille(), _fin.pyramide, ReliefFin.NJ, ReliefFin.NI, _rel._h, ReliefDonnees.NX, ReliefDonnees.NZ, ReliefFin.K, _demande.x, _demande.y, M, NIVEAUX)
	dernier_calcul_us = Time.get_ticks_usec() - t0


func _poser() -> void:
	var t0: int = Time.get_ticks_usec()
	_cj = _demande.x
	_ci = _demande.y
	for n in range(NIVEAUX):
		var img: Image = _images[n]
		img.set_data(M + 1, M + 1, false, Image.FORMAT_RGF, _resultat[n])
		(_textures[n] as ImageTexture).update(img)
	_regler_uniformes()
	_resultat = []
	nb_recentrages += 1
	dernier_envoi_us = Time.get_ticks_usec() - t0


## Mêmes trous que les tuiles (pièces fines des gares, fosses), sans celui du relief à 25 m.
func poser_trous(rects: Array) -> void:
	var v: Array = []
	for r in rects:
		v.append(Vector4((r as Rect2).position.x, (r as Rect2).position.y, (r as Rect2).end.x, (r as Rect2).end.y))
	var n: int = mini(v.size(), 8)
	while v.size() < 8:
		v.append(Vector4.ZERO)
	for m in _mats:
		(m as ShaderMaterial).set_shader_parameter("pieces", v.slice(0, 8))
		(m as ShaderMaterial).set_shader_parameter("n_pieces", n)


func _exit_tree() -> void:
	if _tache >= 0:
		WorkerThreadPool.wait_for_task_completion(_tache)
		_tache = -1
