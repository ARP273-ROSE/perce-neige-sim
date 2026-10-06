class_name ReliefBuilder
extends Node3D
## Vue extérieure : le VRAI massif autour du funiculaire, ouvert en
## « écorché » devant la caméra pour montrer la rame dans son tunnel.
##
## Refonte du 07/10/2026 — Kevin : « 3 m après le départ du bas, ça passe à
## la vue panoramique du haut, statique, en lévitation totale ; faut tout
## refondre de 0 ». Avant, un puits s'ouvrait autour de la rame et le relief
## n'était affiché que si la caméra était AU-DESSUS de la surface : en orbite
## rapprochée elle est presque toujours sous la montagne, le relief
## disparaissait et il ne restait que la photo panoramique prise de la gare
## du haut, posée à 10 km.
##
## Maintenant, en vue extérieure, le relief est toujours là :
##  - bloc détaillé : IGN RGE ALTI à 25 m + orthophoto IGN, 8,6 × 10,2 km, du
##    sommet de la Grande Motte au lac de Tignes (tools_relief3d.py) ;
##  - anneau lointain jusqu'à l'horizon : 44 × 44 km, maille 200 m, rotondité
##    de la Terre, orthophoto IGN, brume de distance
##    (tools_relief_lointain.py). Plus aucune photo panoramique ici ;
##  - ÉCORCHÉ : du côté de la caméra, la montagne est enlevée dans un
##    demi-disque centré sur la rame, jusqu'au niveau du tunnel. Le fond de
##    l'entaille suit le profil de la voie, juste sous le tube ; ses parois
##    montrent la roche à strates, l'épaisseur de montagne au-dessus du
##    tunnel jusqu'au liseré de la surface, et l'entrée du tunnel dans la
##    roche (trou bordé de béton). Le demi-disque grandit avec le recul de
##    la caméra, qui reste toujours dedans (ou, en très grand recul,
##    au-dessus du relief) : rien ne s'interpose entre elle et la rame ;
##  - le tracé du tunnel en surface (ruban orange) et les lieux nommés.
## N'existe qu'en vue extérieure (main.gd).

const CHUNK: int = 64                 # mailles par côté de tuile (frustum culling)
const GAMMA_WEB: float = 0.625        # rendu Compatibility : voir MachineRoomBuilder
const N_VOIE: int = 1024              # échantillons du profil de la voie (texture)
const R_MIN: float = 45.0             # rayon de l'entaille (m)
const R_MAX: float = 2600.0
const Y_SOCLE: float = 1550.0
const BRUME: Color = Color(0.50, 0.62, 0.78)   # linéaire (≈ 0,73 0,81 0,90 en sRGB)

## Code commun : altitude du terrain (sur les MÊMES triangles que le
## maillage), profil de la voie, fond et zone de l'entaille, brume.
## Les textures sont lues en texelFetch (pas de filtrage des flottants 32
## bits, absent de certains GPU mobiles) et interpolées à la main.
const COMMUN: String = """
uniform sampler2D hauteurs : filter_nearest, repeat_disable;
uniform vec4 emprise;              // x ouest, z nord, x est, z sud
uniform float pas_maille = 1.0;
uniform sampler2D voie : filter_nearest, repeat_disable;   // ligne 0 : axe x, y, z, rayon du trou ; ligne 1 : demi-hauteur
uniform float voie_du = 3.0;
uniform float voie_n = 1024.0;
uniform vec3 coupe_c;
uniform vec2 coupe_n = vec2(0.0, 1.0);
uniform vec2 coupe_t = vec2(0.0, -1.0);
uniform float coupe_u = 0.0;
uniform float coupe_off = 5.0;
uniform float coupe_r = 0.0;
uniform float gamma = 1.0;
uniform vec3 brume = vec3(0.50, 0.62, 0.78);   // linéaire (≈ 0,73 0,81 0,90 en sRGB)
varying vec3 pw;

float terrain(vec2 xz) {
	ivec2 sz = textureSize(hauteurs, 0);
	ivec2 lim = sz - ivec2(1);
	vec2 f = (xz - emprise.xy) / (emprise.zw - emprise.xy) * vec2(lim);
	f = clamp(f, vec2(0.0), vec2(lim) - 0.001);
	int p = int(pas_maille);
	vec2 g = f / pas_maille;
	vec2 i = floor(g);
	vec2 w = g - i;
	ivec2 i0 = ivec2(i) * p;
	ivec2 i1 = min(i0 + ivec2(p), lim);
	float a = texelFetch(hauteurs, i0, 0).r;
	float b = texelFetch(hauteurs, ivec2(i1.x, i0.y), 0).r;
	float c = texelFetch(hauteurs, ivec2(i0.x, i1.y), 0).r;
	float d = texelFetch(hauteurs, i1, 0).r;
	if (w.x + w.y <= 1.0) {
		return a + (b - a) * w.x + (c - a) * w.y;
	}
	return d + (c - d) * (1.0 - w.x) + (b - d) * (1.0 - w.y);
}

vec4 voie_a(float u, int ligne) {
	float f = clamp(u / voie_du, 0.0, voie_n - 1.001);
	int i = int(f);
	return mix(texelFetch(voie, ivec2(i, ligne), 0), texelFetch(voie, ivec2(i + 1, ligne), 0), f - float(i));
}

// abscisse (longueur horizontale) du point de la voie le plus proche
float u_de(vec2 xz) {
	float u = coupe_u + dot(xz - coupe_c.xz, coupe_t);
	for (int k = 0; k < 2; k++) {
		vec4 a = voie_a(u, 0);
		vec2 t = voie_a(u + 4.0, 0).xz - a.xz;
		float lt = length(t);
		if (lt > 0.001) {
			u += dot(xz - a.xz, t / lt);
		}
	}
	return u;
}

// fond de l'entaille : sous le tube, à l'aplomb de la voie
float sol(vec2 xz) {
	float u = u_de(xz);
	return voie_a(u, 0).y - voie_a(u, 1).x - 0.05;
}

bool dans_zone(vec2 xz) {
	vec2 d = xz - coupe_c.xz;
	return coupe_r > 0.0 && dot(d, coupe_n) > -coupe_off && dot(d, d) < coupe_r * coupe_r;
}

vec3 voile(vec3 c, vec3 p, vec3 cam) {
	float d = distance(p, cam);
	return pow(mix(c, brume, clamp(1.0 - exp(-d / 28000.0), 0.0, 0.7)), vec3(gamma));
}

// couleurs données en sRGB (comme une texture) : converties en linéaire
vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
}

// roche de la coupe : strates larges et douces, plus sombre en profondeur ;
// `bord` : épaisseur (m) du liseré clair de la surface
vec3 roche(vec3 p, float prof, float k_teinte, float bord) {
	float s1 = sin(p.y * 0.11 + sin(p.x * 0.019 + p.z * 0.016) * 2.3);
	float s2 = sin(p.y * 0.43 + sin(p.x * 0.05) * 0.8);
	vec3 c = lin(vec3(0.46, 0.42, 0.37) * (1.0 + 0.09 * s1 + 0.035 * s2));
	c *= k_teinte * mix(1.0, 0.55, clamp(prof / 500.0, 0.0, 1.0));
	return mix(c, lin(vec3(0.93, 0.88, 0.70)), 1.0 - smoothstep(bord * 0.6, bord, prof));
}
"""

const SHADER_TERRAIN: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;
uniform sampler2D ortho : source_color, filter_linear_mipmap, repeat_disable;
%s
void vertex() {
	pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	// (seuils croisés avec le fond, qui commence 0,45 m sous sol() : pas
	// de fente entre les deux)
	if (dans_zone(pw.xz) && pw.y > sol(pw.xz) - 0.30) {
		discard;
	}
	ALBEDO = voile(texture(ortho, UV).rgb, pw, CAMERA_POSITION_WORLD);
}
"""
## Flancs du bloc détaillé : prolongent sa bordure (couleur de l'orthophoto
## au bord) jusque sous l'anneau lointain.
const SHADER_FLANC: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform sampler2D ortho : source_color, filter_linear_mipmap, repeat_disable;
%s
void vertex() {
	pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	if (dans_zone(pw.xz)) {
		discard;
	}
	ALBEDO = voile(texture(ortho, UV).rgb * 0.85, pw, CAMERA_POSITION_WORLD);
}
"""
## Parois de l'entaille : plan du fond (face à la caméra) et arc de cercle.
const SHADER_PAROI: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform float teinte = 1.0;
uniform float arc = 0.0;           // 1 : paroi en arc (côté caméra du plan seulement)
%s
void vertex() {
	pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float h = terrain(pw.xz);
	if (pw.y > h + 0.3) {
		discard;
	}
	if (arc > 0.5 && dot(pw.xz - coupe_c.xz, coupe_n) <= -coupe_off) {
		discard;
	}
	float s0 = sol(pw.xz);
	if (pw.y < s0 - 0.6 || h < s0) {
		discard;
	}
	// entrée du tunnel dans la roche
	float u = u_de(pw.xz);
	vec4 a = voie_a(u, 0);
	vec3 t = normalize(voie_a(u + 2.0, 0).xyz - voie_a(u - 2.0, 0).xyz + vec3(0.0, 0.0, 1e-5));
	vec3 v = pw - a.xyz;
	float da = length(v - dot(v, t) * t);
	if (da < a.w) {
		discard;
	}
	// liseré de la surface : au moins 2 pixels, lisible de loin
	float bord = max(1.6, 2.5 * fwidth(pw.y));
	vec3 c = roche(pw, h - pw.y, teinte, bord);
	c *= mix(0.72, 1.0, smoothstep(0.0, 5.0, pw.y - s0));       // pied de paroi
	c = mix(c, lin(vec3(0.66, 0.66, 0.63)), 1.0 - smoothstep(a.w + 0.30, a.w + 0.42, da));
	ALBEDO = voile(c, pw, CAMERA_POSITION_WORLD);
}
"""
## Fond de l'entaille : disque posé sur le profil de la voie (texture lue
## dans le nuanceur de sommets), là où il reste de la roche au-dessus.
const SHADER_FOND: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
%s
void vertex() {
	vec3 m = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y = sol(m.xz) - 0.35;
	pw = vec3(m.x, VERTEX.y, m.z);
}
void fragment() {
	if (!dans_zone(pw.xz)) {
		discard;
	}
	float h = terrain(pw.xz);
	if (h < sol(pw.xz) - 0.45) {
		discard;
	}
	ALBEDO = voile(roche(pw, max(h - pw.y, 0.0), 0.52, 0.01), pw, CAMERA_POSITION_WORLD);
}
"""
const SHADER_TRACE: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform vec4 couleur : source_color = vec4(1.0, 0.55, 0.08, 0.9);
%s
void vertex() {
	pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	if (dans_zone(pw.xz)) {
		discard;
	}
	ALBEDO = couleur.rgb;
	ALPHA = couleur.a;
}
"""
const SHADER_LOINTAIN: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;
uniform sampler2D ortho : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 bloc;                 // emprise du bloc détaillé (trou de l'anneau)
uniform float gamma = 1.0;
uniform vec3 brume = vec3(0.74, 0.81, 0.91);
varying vec3 pw;
void vertex() {
	pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	if (pw.x > bloc.x && pw.x < bloc.z && pw.z > bloc.y && pw.z < bloc.w) {
		discard;
	}
	float d = distance(pw, CAMERA_POSITION_WORLD);
	ALBEDO = pow(mix(texture(ortho, UV).rgb, brume, clamp(1.0 - exp(-d / 28000.0), 0.0, 0.7)),
		vec3(gamma));
}
"""

var tunnel: TunnelBuilder = null
var _h: PackedFloat32Array = PackedFloat32Array()
var _dx: float = 1.0
var _dz: float = 1.0
var _mats: Array[ShaderMaterial] = []      # tous ceux qui ont le code commun
## Prêt à être affiché (construction terminée).
var pret: bool = false

# --- Construction EN TÂCHE DE FOND (optimisation du 06/10/2026 : « un beau
# truc qui ne consomme pas énormément de ressources ») -------------------
# 1. préparation des données (décodage des altitudes, sommets et indices de
#    chaque tuile, bloc détaillé puis anneau lointain) : sur PC dans un fil
#    parallèle (WorkerThreadPool) ; dans la PWA, qui n'a pas de fils, par
#    tranches de 3 ms par image sur le fil principal ;
# 2. création des maillages (appels au moteur de rendu) : fil principal,
#    quelques tuiles par image.
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
var _tex_h: ImageTexture = null
var _tex_voie: ImageTexture = null

# --- profil de la voie (texture « voie » et calculs CPU) ------------------
const DS_VOIE: float = 2.0
var _voie_s_u: PackedFloat32Array = PackedFloat32Array()  # u à s = k·2 m
var _vx: PackedFloat32Array = PackedFloat32Array()        # axe à u = i·du
var _vy: PackedFloat32Array = PackedFloat32Array()
var _vz: PackedFloat32Array = PackedFloat32Array()
var _vprof: PackedFloat32Array = PackedFloat32Array()     # demi-hauteur de la section
var _du: float = 1.0

# --- entaille courante -----------------------------------------------------
var _paroi_plan: MeshInstance3D = null
var _paroi_arc: MeshInstance3D = null
var _fond: MeshInstance3D = null
var _c: Vector3 = Vector3.ZERO
var _n: Vector2 = Vector2(0.0, 1.0)
var _t: Vector2 = Vector2(0.0, -1.0)
var _u: float = 0.0
var _off: float = 5.0
var _r: float = 0.0
var _r_lisse: float = R_MIN
var _t_ms: int = 0


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


## Fil principal : quelques tuiles par image, puis flancs, entaille, tracé,
## lieux.
func _creer_maillages(fin_us: int) -> void:
	if _mat_terrain == null:
		_build_voie()
		_mat_terrain = _shader(SHADER_TERRAIN)
		_mat_terrain.set_shader_parameter("ortho", _texture_ortho("res://textures/relief_ortho.jpg"))
		_mat_loin = ShaderMaterial.new()
		var sh: Shader = Shader.new()
		sh.code = SHADER_LOINTAIN
		_mat_loin.shader = sh
		_mat_loin.set_shader_parameter("ortho", _texture_ortho("res://textures/relief_lointain.jpg"))
		_mat_loin.set_shader_parameter("bloc", Vector4(ReliefDonnees.X_OUEST, ReliefDonnees.Z_NORD,
			ReliefDonnees.X_EST, ReliefDonnees.Z_SUD))
		_mat_loin.set_shader_parameter("gamma", _gamma())
		_mat_loin.set_shader_parameter("brume", Vector3(BRUME.r, BRUME.g, BRUME.b))
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
	_build_entaille()
	_build_trace()
	_build_lieux()
	_tableaux.clear()
	_etape = 3
	pret = true
	print("[Relief] prêt")


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


## Altitude sur les triangles du maillage affiché (comme terrain() des
## nuanceurs) : le ruban du tracé s'y pose sans flotter.
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
	if wx + wz <= 1.0:
		return a + (b - a) * wx + (c - a) * wz
	return d + (c - d) * (1.0 - wx) + (b - d) * (1.0 - wz)


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


## Matériau d'un nuanceur qui inclut le code commun (relief, voie, entaille).
func _shader(code: String) -> ShaderMaterial:
	var sh: Shader = Shader.new()
	sh.code = code % COMMUN
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = sh
	_mats.append(m)
	if _tex_h == null:
		var img: Image = Image.create_from_data(ReliefDonnees.NX, ReliefDonnees.NZ, false,
			Image.FORMAT_RF, _h.to_byte_array())
		_tex_h = ImageTexture.create_from_image(img)
	m.set_shader_parameter("hauteurs", _tex_h)
	m.set_shader_parameter("emprise", Vector4(ReliefDonnees.X_OUEST, ReliefDonnees.Z_NORD,
		ReliefDonnees.X_EST, ReliefDonnees.Z_SUD))
	m.set_shader_parameter("pas_maille", float(_pas))
	m.set_shader_parameter("voie", _tex_voie)
	m.set_shader_parameter("voie_du", _du)
	m.set_shader_parameter("voie_n", float(N_VOIE))
	m.set_shader_parameter("gamma", _gamma())
	m.set_shader_parameter("brume", Vector3(BRUME.r, BRUME.g, BRUME.b))
	m.set_shader_parameter("coupe_r", 0.0)
	return m


# --- profil de la voie ---------------------------------------------------

## Axe du tunnel en fonction de la longueur HORIZONTALE u parcourue depuis
## le pied (texture N_VOIE × 2 : axe x, y, z et rayon du trou ; demi-hauteur
## de la section, qui donne le fond de l'entaille).
func _build_voie() -> void:
	var n_s: int = int(ceil(PNConstants.LENGTH / DS_VOIE)) + 1
	var pts: PackedVector3Array = PackedVector3Array()
	var ss: PackedFloat32Array = PackedFloat32Array()
	_voie_s_u.resize(n_s)
	var u: float = 0.0
	for k in range(n_s):
		var s: float = minf(k * DS_VOIE, PNConstants.LENGTH)
		var p: Vector3 = tunnel.transform_at(s).origin
		if k > 0:
			u += Vector2(p.x - pts[k - 1].x, p.z - pts[k - 1].z).length()
		pts.append(p)
		ss.append(s)
		_voie_s_u[k] = u
	_du = u / float(N_VOIE - 1)
	var img: Image = Image.create(N_VOIE, 2, false, Image.FORMAT_RGBAF)
	_vx.resize(N_VOIE)
	_vy.resize(N_VOIE)
	_vz.resize(N_VOIE)
	_vprof.resize(N_VOIE)
	var k2: int = 0
	for i in range(N_VOIE):
		var ui: float = i * _du
		while k2 < n_s - 2 and _voie_s_u[k2 + 1] < ui:
			k2 += 1
		var du_k: float = maxf(_voie_s_u[k2 + 1] - _voie_s_u[k2], 1e-6)
		var w: float = clampf((ui - _voie_s_u[k2]) / du_k, 0.0, 1.0)
		var p: Vector3 = pts[k2].lerp(pts[k2 + 1], w)
		var s: float = lerpf(ss[k2], ss[k2 + 1], w)
		var blend: float = tunnel._horseshoe_blend_at(s)
		var dims: Vector2 = tunnel._horseshoe_dims_at(s)
		var r_trou: float = lerpf(tunnel.tunnel_radius, dims.length(), blend) \
			+ absf(tunnel.passing_loop_offset(s, 1.0)) + 0.05
		var prof: float = lerpf(tunnel.tunnel_radius, dims.y, blend)
		_vx[i] = p.x
		_vy[i] = p.y
		_vz[i] = p.z
		_vprof[i] = prof
		img.set_pixel(i, 0, Color(p.x, p.y, p.z, r_trou))
		img.set_pixel(i, 1, Color(prof, 0.0, 0.0, 0.0))
	_tex_voie = ImageTexture.create_from_image(img)


func _voie_cpu(u: float) -> Vector4:
	var f: float = clampf(u / _du, 0.0, N_VOIE - 1.001)
	var i: int = int(f)
	var w: float = f - i
	return Vector4(lerpf(_vx[i], _vx[i + 1], w), lerpf(_vy[i], _vy[i + 1], w),
		lerpf(_vz[i], _vz[i + 1], w), lerpf(_vprof[i], _vprof[i + 1], w))


func _u_de_cpu(x: float, z: float) -> float:
	var u: float = _u + (x - _c.x) * _t.x + (z - _c.z) * _t.y
	for k in range(2):
		var a: Vector4 = _voie_cpu(u)
		var b: Vector4 = _voie_cpu(u + 4.0)
		var t: Vector2 = Vector2(b.x - a.x, b.z - a.z)
		if t.length() > 0.001:
			u += Vector2(x - a.x, z - a.z).dot(t.normalized())
	return u


## Fond de l'entaille à l'aplomb de (x, z) — comme le nuanceur.
func sol(x: float, z: float) -> float:
	var a: Vector4 = _voie_cpu(_u_de_cpu(x, z))
	return a.y - a.w - 0.05


## u (longueur horizontale) à l'abscisse s de la voie.
func u_de_s(s: float) -> float:
	var f: float = clampf(s / DS_VOIE, 0.0, _voie_s_u.size() - 1.001)
	var i: int = int(f)
	return lerpf(_voie_s_u[i], _voie_s_u[i + 1], f - i)


# --- entaille --------------------------------------------------------------

func _build_entaille() -> void:
	# plan du fond : carré unité (x ∈ [−1, 1], y ∈ [0, 1]), placé chaque image
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0),
			Vector3(-1, 0, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)]:
		st.add_vertex(v)
	var m_plan: ShaderMaterial = _shader(SHADER_PAROI)
	m_plan.set_shader_parameter("teinte", 1.0)
	st.set_material(m_plan)
	_paroi_plan = _instance(st.commit(), "ParoiFond")
	# arc : cylindre unité (rayon 1, y ∈ [0, 1])
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = 96
	for i in range(n):
		var a0: float = TAU * i / n
		var a1: float = TAU * (i + 1) / n
		var p00: Vector3 = Vector3(cos(a0), 0.0, sin(a0))
		var p10: Vector3 = Vector3(cos(a1), 0.0, sin(a1))
		for v in [p00, p10, p10 + Vector3.UP, p00, p10 + Vector3.UP, p00 + Vector3.UP]:
			st.add_vertex(v)
	var m_arc: ShaderMaterial = _shader(SHADER_PAROI)
	m_arc.set_shader_parameter("teinte", 0.82)
	m_arc.set_shader_parameter("arc", 1.0)
	st.set_material(m_arc)
	_paroi_arc = _instance(st.commit(), "ParoiArc")
	# fond : disque polaire unité, altitude posée par le nuanceur de sommets
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var anneaux: int = 20
	var secteurs: int = 72
	for r in range(anneaux):
		var r0: float = float(r) / anneaux
		var r1: float = float(r + 1) / anneaux
		r0 *= r0
		r1 *= r1                     # plus serré au centre, près de la rame
		for i in range(secteurs):
			var a0: float = TAU * i / secteurs
			var a1: float = TAU * (i + 1) / secteurs
			var q00: Vector3 = Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
			var q10: Vector3 = Vector3(cos(a1) * r0, 0.0, sin(a1) * r0)
			var q01: Vector3 = Vector3(cos(a0) * r1, 0.0, sin(a0) * r1)
			var q11: Vector3 = Vector3(cos(a1) * r1, 0.0, sin(a1) * r1)
			for v in [q00, q01, q11, q00, q11, q10]:
				st.add_vertex(v)
	st.set_material(_shader(SHADER_FOND))
	var mesh: ArrayMesh = st.commit()
	# altitude posée par le nuanceur : boîte englobante sur toute la hauteur
	mesh.custom_aabb = AABB(Vector3(-1.05, 0.0, -1.05), Vector3(2.1, 4200.0, 2.1))
	_fond = _instance(mesh, "FondEntaille")
	couper(false)


func _instance(mesh: Mesh, nom: String) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = nom
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Referme l'entaille (off) ; set_coupe() la rouvre.
func couper(on: bool) -> void:
	if not on:
		_r = 0.0
		for m in _mats:
			m.set_shader_parameter("coupe_r", 0.0)
	for mi in [_paroi_plan, _paroi_arc, _fond]:
		if mi != null:
			mi.visible = on


## Ouvre l'entaille autour de la rame `c` (abscisse `s`), face à la caméra
## `cam`. `longueur` : longueur de la rame.
func set_coupe(c: Vector3, s: float, cam: Vector3, longueur: float) -> void:
	if not pret:
		return
	_c = c
	_u = u_de_s(s)
	var a: Vector4 = _voie_cpu(_u)
	var b: Vector4 = _voie_cpu(_u + 4.0)
	var t: Vector2 = Vector2(b.x - a.x, b.z - a.z)
	if t.length() < 0.001:
		var a0: Vector4 = _voie_cpu(_u - 4.0)
		t = Vector2(a.x - a0.x, a.z - a0.z)
	_t = t.normalized()
	var d: Vector2 = Vector2(cam.x - c.x, cam.z - c.z)
	var hd: float = d.length()
	if hd > 0.5:
		_n = d / hd
	# plan du fond derrière la rame (vue dans l'axe : derrière son nez)
	_off = 3.0 + absf(_t.dot(_n)) * (longueur * 0.5 + 6.0)
	# rayon : jusqu'au point le plus éloigné de la visée rame → caméra qui
	# passe sous le relief (caméra comprise), avec de la marge ; grandit
	# tout de suite, rapetisse en douceur (pas de saut quand une crête
	# passe devant)
	var cible: float = R_MIN
	for k in range(1, 65):
		var f: float = k / 64.0
		var q: Vector3 = c.lerp(cam, f)
		if q.y < hauteur_partout(q.x, q.z) + 4.0:
			cible = maxf(cible, 1.2 * hd * f + 30.0)
	cible = minf(cible, R_MAX)
	var dt: float = clampf(float(Time.get_ticks_msec() - _t_ms) / 1000.0, 0.0, 0.25)
	_t_ms = Time.get_ticks_msec()
	_r_lisse = cible if cible > _r_lisse else lerpf(_r_lisse, cible, 1.0 - exp(-dt * 2.0))
	_r = _r_lisse
	for m in _mats:
		m.set_shader_parameter("coupe_c", c)
		m.set_shader_parameter("coupe_n", _n)
		m.set_shader_parameter("coupe_t", _t)
		m.set_shader_parameter("coupe_u", _u)
		m.set_shader_parameter("coupe_off", _off)
		m.set_shader_parameter("coupe_r", _r)
	# bas des parois : sous la voie au point le plus bas de l'entaille
	var y_bas: float = _voie_cpu(_u - _r * 1.1).y - 8.0
	# plan : corde du disque, du fond au plus haut du relief sur la corde
	var p0: Vector2 = Vector2(c.x, c.z) - _n * _off
	var perp: Vector2 = Vector2(-_n.y, _n.x)
	var demi: float = sqrt(maxf(_r * _r - _off * _off, 1.0))
	var haut: float = y_bas + 10.0
	for k in range(33):
		var q: Vector2 = p0 + perp * demi * (k / 16.0 - 1.0)
		haut = maxf(haut, hauteur(q.x, q.y))
	_paroi_plan.transform = Transform3D(
		Basis(Vector3(perp.x, 0.0, perp.y) * demi, Vector3(0.0, haut + 30.0 - y_bas, 0.0),
			Vector3(_n.x, 0.0, _n.y)),
		Vector3(p0.x, y_bas, p0.y))
	var haut_arc: float = y_bas + 10.0
	for k in range(48):
		var ang: float = TAU * k / 48.0
		haut_arc = maxf(haut_arc, hauteur(c.x + cos(ang) * _r, c.z + sin(ang) * _r))
	_paroi_arc.transform = Transform3D(Basis.from_scale(Vector3(_r, haut_arc + 30.0 - y_bas, _r)),
		Vector3(c.x, y_bas, c.z))
	_fond.transform = Transform3D(Basis.from_scale(Vector3(_r, 1.0, _r)), Vector3(c.x, 0.0, c.z))
	couper(true)


## Altitude minimale de la caméra en vue extérieure : dans l'entaille, au-
## dessus de son fond ; hors de l'entaille (très grand recul), au-dessus du
## relief.
func y_min_camera(p: Vector3) -> float:
	if not pret:
		return -INF
	var d: Vector2 = Vector2(p.x - _c.x, p.z - _c.z)
	if _r > 0.0 and d.dot(_n) > -_off and d.length() < _r - 2.0:
		return sol(p.x, p.z) + 1.5
	return hauteur_partout(p.x, p.z) + 30.0


## Flancs du bloc détaillé (« jupe ») : de sa bordure jusqu'à Y_SOCLE, sous
## l'anneau lointain, colorés comme le bord de l'orthophoto — ils bouchent
## les écarts entre les deux maillages.
func _build_flancs() -> void:
	var mat: ShaderMaterial = _shader(SHADER_FLANC)
	mat.set_shader_parameter("ortho", _mat_terrain.get_shader_parameter("ortho"))
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


## Tracé du tunnel en surface : ruban orange posé sur le relief au-dessus de
## la voie, de portail à portail.
func _build_trace() -> void:
	var mat: ShaderMaterial = _shader(SHADER_TRACE)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_g: Vector3 = Vector3.ZERO
	var prev_d: Vector3 = Vector3.ZERO
	var s: float = 0.0
	var premier: bool = true
	while s <= PNConstants.LENGTH + 0.01:
		var xf: Transform3D = tunnel.transform_at(minf(s, PNConstants.LENGTH))
		var dr: Vector3 = xf.basis.x
		dr.y = 0.0
		dr = dr.normalized() * 3.5
		var p: Vector3 = xf.origin
		var g: Vector3 = p - dr
		var d: Vector3 = p + dr
		# posé sur les triangles du maillage, 2 m au-dessus
		g.y = _hauteur_tri(g.x, g.z) + 2.0
		d.y = _hauteur_tri(d.x, d.z) + 2.0
		if not premier:
			for v in [prev_g, prev_d, d, prev_g, d, g]:
				st.add_vertex(v)
		prev_g = g
		prev_d = d
		premier = false
		s += 5.0
	st.set_material(mat)
	_instance(st.commit(), "TraceTunnel")


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
