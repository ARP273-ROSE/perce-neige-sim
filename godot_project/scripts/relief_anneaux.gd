class_name ReliefAnneaux
extends Node3D
## Affichage du sol au mètre (pack haute définition, PC) : anneaux emboîtés autour de la caméra,
## un nœud sur 1, 2, 4, 8 puis 16. Le maillage ne change jamais : le nuanceur de sommets lit les
## altitudes d'une texture par anneau, recalculée sur un fil de travail quand la caméra a fait
## 32 m ; plus de construction de maillage ni de reconstruction visible. Chaque anneau rejoint
## le suivant à son bord (morphing selon la distance), le dernier se pose sur les tuiles à 25 m.
## L'ombrage vient d'un tableau de textures de normales au mètre, valable à toute distance.

const M: int = 512                     # mailles par côté d'un anneau, multiple de 4
const NIVEAUX: int = 5
const SAUT: int = 1 << NIVEAUX         # les anneaux se déplacent ensemble, de 32 nœuds
const TUILE: int = 2000                # nœuds par couche du tableau de textures
const TAILLE: int = 2048               # texels par couche, dont
const MARGE: int = 24                  # la marge prise aux voisines (filtrage, niveaux)

## Ce qui remplace, dans le nuanceur du relief, la normale du sommet et les UV du maillage.
const _ENTETE_HD: String = """varying vec3 nw;
uniform sampler2DArray normal_hd : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 hd_xf;                 // x0, z0, px, pz
uniform vec4 hd_tex;                // nœuds par couche, texels, marge, couches par ligne
uniform vec2 hd_nb;                 // dernier nœud (j, i)
uniform sampler2DArray ortho_hd : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float a_ortho = 0.0;        // 1 : orthophoto au mètre présente
// Photo au mètre ; au-delà de 16 m par texel, la photo d'ensemble (la marge entre couches ne suffit plus)
vec3 photo_hd(vec2 p, vec3 c_loin) {
	if (a_ortho < 0.5) {
		return c_loin;
	}
	vec2 nn = (p - hd_xf.xy) / hd_xf.zw;
	vec2 dx_n = dFdx(nn);
	vec2 dy_n = dFdy(nn);
	float lod = 0.5 * log2(max(max(dot(dx_n, dx_n), dot(dy_n, dy_n)), 1e-6));
	float k = smoothstep(4.0, 5.0, lod);
	if (k >= 1.0) {
		return c_loin;
	}
	vec2 t = clamp(floor(nn / hd_tex.x), vec2(0.0), floor((hd_nb - vec2(0.5)) / hd_tex.x));
	vec2 uv = (nn - t * hd_tex.x + hd_tex.z + 0.5) / hd_tex.y;
	vec3 c = textureGrad(ortho_hd, vec3(uv, t.y * hd_tex.w + t.x), dx_n / hd_tex.y, dy_n / hd_tex.y).rgb;
	return mix(c, c_loin, k);
}
vec3 normale_hd(vec2 p) {
	vec2 nn = (p - hd_xf.xy) / hd_xf.zw;
	vec2 t = clamp(floor(nn / hd_tex.x), vec2(0.0), floor((hd_nb - vec2(0.5)) / hd_tex.x));
	vec2 uv = (nn - t * hd_tex.x + hd_tex.z + 0.5) / hd_tex.y;
	vec2 g = textureGrad(normal_hd, vec3(uv, t.y * hd_tex.w + t.x), dFdx(nn) / hd_tex.y, dFdy(nn) / hd_tex.y).rg * 2.0 - 1.0;
	return vec3(g.x, sqrt(max(1.0 - dot(g, g), 0.0)), g.y);
}
"""
## Sommets d'un anneau : position et altitude lues de sa texture.
const _SOMMETS_ANNEAU: String = """uniform sampler2D anneau : filter_nearest, repeat_disable;
uniform vec4 a_o;                   // premier nœud (j, i), pas en nœuds, 1 : dernier anneau
uniform vec2 a_m;                   // début et fin du morphing (m de la caméra)
void vertex() {
	ivec2 g = ivec2(VERTEX.xz);
	vec2 nn = clamp(a_o.xy + vec2(g) * a_o.z, vec2(0.0), hd_nb);
	vec2 w = hd_xf.xy + nn * hd_xf.zw;
	vec4 t0 = texelFetch(anneau, g, 0);
	float d = max(abs(w.x - CAMERA_POSITION_WORLD.x), abs(w.y - CAMERA_POSITION_WORLD.z));
	float al = clamp((d - a_m.x) / (a_m.y - a_m.x), 0.0, 1.0);
	float hp = t0.g;
	if (a_o.w < 0.5) {
		// nœud absent de l'anneau suivant : le milieu de son arête (même diagonale que le maillage)
		ivec2 o = g % 2;
		ivec2 o2 = ivec2(o.x, -o.y);
		hp = 0.5 * (texelFetch(anneau, g - o2, 0).r + texelFetch(anneau, g + o2, 0).r);
	}
	VERTEX = vec3(w.x, mix(t0.r, hp, al), w.y);
	NORMAL = vec3(0.0, 1.0, 0.0);
	pw = VERTEX;
	nw = NORMAL;
}
"""

var _fin: ReliefFin = null
var _rel: ReliefBuilder = null
var _hd: RefCounted = null
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
static func code_hd(code: String) -> String:
	return code.replace("varying vec3 nw;", _ENTETE_HD) \
		.replace("vec3 n = normalize(nw);", "vec3 n = normale_hd(pw.xz);") \
		.replace("vec3 c = texture(ortho, UV).rgb;", "vec2 uv_hd = (pw.xz - hd_xf.xy) / (hd_xf.zw * hd_nb);\n\tvec3 c = photo_hd(pw.xz, texture(ortho, uv_hd).rgb);") \
		.replace("c = en_hiver(c, UV, CAMERA_POSITION_WORLD);", "c = en_hiver(c, uv_hd, CAMERA_POSITION_WORLD);")


static func regler_hd(m: ShaderMaterial, normales: Texture2DArray, ortho: Texture2DArray = null) -> void:
	m.set_shader_parameter("normal_hd", normales)
	if ortho != null:
		m.set_shader_parameter("ortho_hd", ortho)
		m.set_shader_parameter("a_ortho", 1.0)
	m.set_shader_parameter("hd_xf", Vector4(ReliefFin.X0, ReliefFin.Z0, ReliefFin.PX, ReliefFin.PZ))
	m.set_shader_parameter("hd_tex", Vector4(TUILE, TAILLE, MARGE, (ReliefFin.NJ - 1 + TUILE - 1) / TUILE))
	m.set_shader_parameter("hd_nb", Vector2(ReliefFin.NJ - 1, ReliefFin.NI - 1))


func demarrer(fin: ReliefFin, rel: ReliefBuilder) -> void:
	name = "ReliefAnneaux"
	_fin = fin
	_rel = rel
	_hd = ClassDB.instantiate("ReliefHD")
	var code: String = code_hd(ReliefBuilder.SHADER_TERRAIN)
	# les sommets du relief (tuiles) laissent place à ceux de l'anneau
	var deb: int = code.find("void vertex() {")
	var fin_v: int = code.find("}", deb) + 1
	code = code.substr(0, deb) + _SOMMETS_ANNEAU + code.substr(fin_v)
	# même découpe en quatre pour tous : la caméra n'en voit souvent que deux
	var q: Array = [_maillages(false), _maillages(true)]
	var centre: Vector2i = _noeud_vue()
	_cj = centre.x
	_ci = centre.y
	var couches: Array = _hd.call("anneaux", fin.noeuds_grille(), ReliefFin.NJ, ReliefFin.NI, rel._h, ReliefDonnees.NX, ReliefDonnees.NZ, ReliefFin.K, _cj, _ci, M, NIVEAUX)
	for n in range(NIVEAUX):
		var img: Image = Image.create_from_data(M + 1, M + 1, false, Image.FORMAT_RGF if n == NIVEAUX - 1 else Image.FORMAT_RF, couches[n])
		_images.append(img)
		_textures.append(ImageTexture.create_from_image(img))
		var mat: ShaderMaterial = rel._shader(code)
		mat.set_shader_parameter("ortho", rel._tex_ortho)
		regler_hd(mat, rel._tex_normales, rel._tex_ortho_hd)
		mat.set_shader_parameter("anneau", _textures[n])
		mat.set_shader_parameter("piece", 0.0)
		rel._hiver_mat(mat, true)
		_mats.append(mat)
		for k in range(4):
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.name = "Anneau%d_%d" % [n, k]
			mi.mesh = q[0 if n == 0 else 1][k]
			mi.material_override = mat
			mi.layers = 1 | Cabin.LAYER_RELIEF
			mi.set_meta("sans_collision", true)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_instances.append([n, k, mi])
	_regler_uniformes()
	rel._poser_trous()


## Les quatre quarts d'un anneau, avec ou sans le trou de l'anneau précédent.
func _maillages(avec_trou: bool) -> Array:
	var r: Array = []
	var d: int = M / 2
	for k in range(4):
		var j0: int = d if k & 1 else 0
		var i0: int = d if k & 2 else 0
		var nb: int = d + 1
		var v: PackedVector3Array = PackedVector3Array()
		v.resize(nb * nb)
		var o: int = 0
		for i in range(nb):
			for j in range(nb):
				v[o] = Vector3(j0 + j, 0.0, i0 + i)
				o += 1
		var idx: PackedInt32Array = PackedInt32Array()
		idx.resize(d * d * 6)
		o = 0
		for i in range(d):
			var gi: int = i0 + i
			for j in range(d):
				var gj: int = j0 + j
				# (une maille de recouvrement : au bord, l'anneau précédent est sur la même surface,
				# et sans lui les jonctions en T laissaient passer des points de ciel)
				if avec_trou and gi >= M / 4 + 1 and gi < 3 * M / 4 - 1 and gj >= M / 4 + 1 and gj < 3 * M / 4 - 1:
					continue
				var a: int = i * nb + j
				idx[o] = a
				idx[o + 1] = a + 1
				idx[o + 2] = a + nb
				idx[o + 3] = a + 1
				idx[o + 4] = a + nb + 1
				idx[o + 5] = a + nb
				o += 6
		idx.resize(o)
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_INDEX] = idx
		var m: ArrayMesh = ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		r.append(m)
	return r


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
		m.set_shader_parameter("a_o", Vector4(_cj - (M / 2) * s, _ci - (M / 2) * s, s, 1.0 if n == NIVEAUX - 1 else 0.0))
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
	_resultat = _hd.call("anneaux", _fin.noeuds_grille(), ReliefFin.NJ, ReliefFin.NI, _rel._h, ReliefDonnees.NX, ReliefDonnees.NZ, ReliefFin.K, _demande.x, _demande.y, M, NIVEAUX)
	dernier_calcul_us = Time.get_ticks_usec() - t0


func _poser() -> void:
	var t0: int = Time.get_ticks_usec()
	_cj = _demande.x
	_ci = _demande.y
	for n in range(NIVEAUX):
		var img: Image = _images[n]
		img.set_data(M + 1, M + 1, false, Image.FORMAT_RGF if n == NIVEAUX - 1 else Image.FORMAT_RF, _resultat[n])
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
