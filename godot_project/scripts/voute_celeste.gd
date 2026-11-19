## Ciel étoilé réel et Lune (19/11/2026) : les 5 080 étoiles du catalogue BSC5 jusqu'à la magnitude 6
## (EtoilesDonnees), placées par le temps sidéral local de l'heure de jeu, et la Lune à sa position, avec sa phase.
## Un seul maillage de points pour les étoiles (une seule passe de dessin), un carré pour la Lune ; sphère centrée
## sur la caméra, juste en deçà de son plan lointain, sans brouillard : le relief les cache normalement. La
## rotation du ciel est celle du nœud (aucun sommet recalculé). Caché de jour (aucun coût) ; marche en rendu de
## compatibilité (PWA). Les étoiles pâlissent près de l'horizon (extinction) et avec le crépuscule.
class_name VouteCeleste
extends Node3D

const SHADER_ETOILES: String = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform float nuit = 0.0;           // 0 jour, 1 nuit noire
uniform float echelle_px = 1.0;     // taille des points selon la définition de l'écran
uniform float sat = 1.0;            // saturation en plus (Vulkan : la courbe de tons ACES pâlit les points brillants)
varying float eclat;
void vertex() {
	vec3 w = normalize((MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz);
	float m = UV.x;                 // magnitude visuelle
	// extinction : masse d'air près de l'horizon (≈ 0,25 mag par masse d'air en altitude)
	float h = max(w.y, 0.0);
	float masse = 1.0 / (h + 0.15 * pow(max(h * 57.3 + 3.885, 0.1), -1.253));
	float m_vue = m + 0.25 * (masse - 1.0) + (1.0 - nuit) * 5.0;
	eclat = clamp(pow(10.0, -0.4 * (m_vue - 3.2)), 0.0, 4.0) * smoothstep(-0.02, 0.03, w.y);
	// les plus brillantes plus grosses (cœur de 2 à 4 px et un halo), pour que leur couleur se voie
	POINT_SIZE = echelle_px * clamp(2.4 + 1.3 * (3.0 - m_vue), 1.8, 9.0);
}
void fragment() {
	vec2 q = POINT_COORD * 2.0 - 1.0;
	float r2 = dot(q, q);
	if (r2 > 1.0) {
		discard;
	}
	// cœur (couleur pleine, jamais blanchie) et halo coloré qui s'éteint vers le bord
	float coeur = 1.0 - smoothstep(0.10, 0.35, r2);
	float halo = (1.0 - r2) * (1.0 - r2) * 0.45;
	float a = (eclat >= 1.0 ? max(coeur, halo) : (1.0 - smoothstep(0.15, 1.0, r2))) * min(eclat, 1.0) * nuit;
	float lum = dot(COLOR.rgb, vec3(0.3, 0.59, 0.11));
	ALBEDO = clamp(mix(vec3(lum), COLOR.rgb, sat), 0.0, 1.0) * a;
}
"""

const SHADER_LUNE: String = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform vec3 soleil_local = vec3(0.0, 0.0, 1.0);   // direction du Soleil dans le repère du carré
uniform float visibilite = 1.0;
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	q.y = -q.y;
	float r2 = dot(q, q);
	if (r2 > 1.0) {
		discard;
	}
	vec3 n = vec3(q, -sqrt(1.0 - r2));     // face visible : tournée vers le centre (axe local −z)
	float jour = smoothstep(-0.04, 0.06, dot(n, normalize(soleil_local)));
	// mers (taches sombres fixes, grossières) et lumière cendrée
	float mers = 0.82 + 0.18 * sin(q.x * 5.1 + 1.3) * sin(q.y * 4.3 - 0.7);
	vec3 c = vec3(1.0, 0.98, 0.92) * mers * (jour * 1.6 + 0.035);
	ALBEDO = c;
	// face non éclairée : presque aussi sombre que le ciel (elle cache à peine les étoiles qui passent derrière)
	ALPHA = visibilite * smoothstep(1.0, 0.94, r2) * (0.15 + 0.85 * jour);
}
"""

var _etoiles: MeshInstance3D = null
var _lune: MeshInstance3D = null
var _mat_e: ShaderMaterial = null
var _mat_l: ShaderMaterial = null
## Fraction éclairée de la Lune et sa direction (repère du jeu), relevées à la dernière mise à jour.
var phase_lune: float = 0.0
var dir_lune: Vector3 = Vector3.DOWN
var n_etoiles: int = 0


func _init() -> void:
	name = "VouteCeleste"
	top_level = true


static func couleur_bv(bv: float) -> Color:
	# B−V → température (Ballesteros 2012) → couleur (approximation du corps noir)
	var t: float = 4600.0 * (1.0 / (0.92 * bv + 1.7) + 1.0 / (0.92 * bv + 0.62))
	var k: float = t / 100.0
	var r: float = 1.0 if k <= 66.0 else clampf(1.292936 * pow(k - 60.0, -0.1332047592), 0.0, 1.0)
	var g: float = clampf(0.39008 * log(k) - 0.63184, 0.0, 1.0) if k <= 66.0 \
		else clampf(1.129890 * pow(k - 60.0, -0.0755148492), 0.0, 1.0)
	var b: float = 1.0 if k >= 66.0 else (0.0 if k <= 19.0 else clampf(0.543207 * log(k - 10.0) - 1.19625, 0.0, 1.0))
	# saturation accentuée (19/11/2026, retour d'essai PWA : « étoiles toutes blanches ») : l'écart à la luminance
	# grossi de 1,6 ; Bételgeuse, Antarès, Aldébaran, Arcturus orangées, Rigel, Véga, Sirius, Spica bleutées ; la
	# couleur est ramenée à 1 sur sa composante la plus forte, l'éclat est porté à part (pas de blanc par saturation)
	var c0: Color = Color(r, g, b)
	var l: float = c0.r * 0.3 + c0.g * 0.59 + c0.b * 0.11
	var c: Color = Color(l + (c0.r - l) * 1.6, l + (c0.g - l) * 1.6, l + (c0.b - l) * 1.6)
	c = Color(maxf(c.r, 0.05), maxf(c.g, 0.05), maxf(c.b, 0.05))
	var m: float = maxf(c.r, maxf(c.g, c.b))
	return Color(c.r / m, c.g / m, c.b / m)


func construire() -> void:
	if _etoiles != null:
		return
	var octets: PackedByteArray = Marshalls.base64_to_raw(EtoilesDonnees.DONNEES)
	var n: int = octets.size() / 8
	var pts: PackedVector3Array = PackedVector3Array()
	var cols: PackedColorArray = PackedColorArray()
	var uvs: PackedVector2Array = PackedVector2Array()
	pts.resize(n)
	cols.resize(n)
	uvs.resize(n)
	for i in range(n):
		var ra: float = float(octets.decode_u16(i * 8)) / 65535.0 * TAU
		var de: float = float(octets.decode_u16(i * 8 + 2)) / 65535.0 * PI - PI * 0.5
		var m: float = float(octets.decode_u16(i * 8 + 4)) / 1000.0 - 2.0
		var bv: float = float(octets.decode_u16(i * 8 + 6)) / 10000.0 - 0.5
		pts[i] = Vector3(cos(de) * cos(ra), cos(de) * sin(ra), sin(de))
		cols[i] = couleur_bv(bv)
		uvs[i] = Vector2(m, 0.0)
	n_etoiles = n
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arr)
	var sh := Shader.new()
	sh.code = SHADER_ETOILES
	_mat_e = ShaderMaterial.new()
	_mat_e.shader = sh
	_mat_e.set_shader_parameter("sat", 1.0 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 1.9)
	_mat_e.set_shader_parameter("echelle_px", clampf(float(DisplayServer.screen_get_scale()), 1.0, 2.0) \
		if not OS.has_feature("web") else 1.5)
	_etoiles = MeshInstance3D.new()
	_etoiles.name = "Etoiles"
	_etoiles.mesh = am
	_etoiles.material_override = _mat_e
	_etoiles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_etoiles.custom_aabb = AABB(Vector3(-1.1, -1.1, -1.1), Vector3(2.2, 2.2, 2.2))
	_etoiles.extra_cull_margin = 16384.0
	add_child(_etoiles)
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var sh2 := Shader.new()
	sh2.code = SHADER_LUNE
	_mat_l = ShaderMaterial.new()
	_mat_l.shader = sh2
	_mat_l.render_priority = 1
	_lune = MeshInstance3D.new()
	_lune.name = "Lune"
	_lune.mesh = q
	_lune.material_override = _mat_l
	_lune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lune.extra_cull_margin = 16384.0
	add_child(_lune)


## Ciel de l'instant t (UTC, s) : rotation des étoiles, position et phase de la Lune, fondu `nuit` (0..1).
func regler(t_unix: float, nuit: float, dir_soleil: Vector3) -> void:
	construire()
	var b: Basis = AstroCiel.base_equateur(t_unix) * AstroCiel.precession(t_unix)
	_etoiles.basis = b
	_mat_e.set_shader_parameter("nuit", nuit)
	dir_lune = AstroCiel.dir_lune(t_unix)
	phase_lune = AstroCiel.phase_lune(t_unix)
	# carré de la Lune tourné vers le centre (la caméra), à 98 % du rayon ; diamètre apparent ≈ 1,1° (2× le vrai)
	var z: Vector3 = -dir_lune
	var x: Vector3 = Vector3.UP.cross(z)
	if x.length() < 1e-4:
		x = Vector3.RIGHT
	x = x.normalized()
	var y: Vector3 = z.cross(x).normalized()
	var taille: float = 2.0 * tan(deg_to_rad(0.55)) * 0.98
	var bl: Basis = Basis(x * taille, y * taille, -z)
	_lune.transform = Transform3D(bl, dir_lune * 0.98)
	var s_loc: Vector3 = Basis(x, y, -z).inverse() * dir_soleil
	_mat_l.set_shader_parameter("soleil_local", s_loc)
	_mat_l.set_shader_parameter("visibilite", clampf(nuit * 1.4, 0.0, 1.0) * smoothstep(-0.03, 0.02, dir_lune.y))


## Suit la caméra (chaque image), rayon juste en deçà de son plan lointain.
func suivre(cam: Camera3D) -> void:
	if cam == null:
		return
	var r: float = minf(cam.far * 0.92, 50000.0)
	global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(r, r, r)), cam.global_position)
