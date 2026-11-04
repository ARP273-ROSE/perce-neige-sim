class_name ReliefForet
extends Node3D
## Forêt du pack haute définition (PC) : les arbres relevés sur la hauteur de végétation de l'IGN.
## Trois niveaux, en MultiMesh, sans texture ni transparence : conifère en étages de près, cône à
## six pans jusqu'à 2,5 km, un triangle tourné vers la caméra au-delà. Posés étalés sur plusieurs
## images, pour ne pas prolonger le chargement. Ombres portées du seul premier niveau.

const PORTEE_PRES: float = 400.0
const PORTEE_MOYEN: float = 2500.0
const PORTEE_LOIN: float = 12000.0
const BLOC: int = 4                    # cases de 250 m par bloc lointain, par côté
const BUDGET_US: int = 2000

const _SHADER: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform float gamma = 1.0;
uniform vec3 brume = vec3(0.50, 0.62, 0.78);
uniform float hiver = 0.0;
uniform vec3 soleil = vec3(0.40, 0.78, 0.48);
uniform float billboard = 0.0;
varying float lum;
varying float neige;
varying vec3 pw;
void vertex() {
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (billboard > 0.5) {
		vec3 o = MODEL_MATRIX[3].xyz;
		float r = length(MODEL_MATRIX[0].xyz);
		float h = length(MODEL_MATRIX[1].xyz);
		vec3 versCam = CAMERA_POSITION_WORLD - o;
		vec3 droite = normalize(vec3(versCam.z, 0.0, -versCam.x));
		vec3 w = o + droite * VERTEX.x * r + vec3(0.0, VERTEX.y * h, 0.0);
		VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
		n = vec3(0.0, 1.0, 0.0);
	}
	pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lum = (0.42 + 0.68 * max(dot(n, normalize(soleil)), 0.0)) * UV.y;
	neige = UV.x;
}
void fragment() {
	vec3 vert = vec3(0.045, 0.085, 0.060) * COLOR.rgb;
	vec3 tronc = vec3(0.09, 0.07, 0.05);
	vec3 base = mix(tronc, vert, smoothstep(-0.5, 0.0, neige));
	vec3 c = mix(base, vec3(0.72, 0.76, 0.82), clamp(neige, 0.0, 1.0) * 0.55 * hiver);
	c *= lum;
	float d = distance(pw, CAMERA_POSITION_WORLD);
	ALBEDO = pow(max(mix(c, brume, clamp(1.0 - exp(-d / 28000.0), 0.0, 0.7)), vec3(0.0)), vec3(gamma));
}
"""

var _mats: Array = []
var _meshes: Array = []
var _a_poser: Array = []
var _rel: ReliefBuilder = null
var nb_arbres: int = 0


func demarrer(rel: ReliefBuilder, cases: Array) -> void:
	name = "ReliefForet"
	_rel = rel
	_meshes = [_conifere(9, 9, true), _conifere(3, 6, false), _triangle()]
	for k in range(3):
		var m: ShaderMaterial = rel._shader(_SHADER)
		m.set_shader_parameter("billboard", 1.0 if k == 2 else 0.0)
		m.set_shader_parameter("hiver", rel._hiver)
		rel._mats_hiver.append(m)
		_mats.append(m)
	# blocs lointains : un seul appel de dessin par kilomètre carré
	var blocs: Dictionary = {}
	for c in cases:
		nb_arbres += int(c[2])
		var cx: int = c[0]
		var cz: int = c[1]
		_a_poser.append([1, c[3], c[2], 0.0, PORTEE_PRES])                  # près
		_a_poser.append([2, c[3], c[2], PORTEE_PRES, PORTEE_MOYEN])          # moyen
		var cle: Vector2i = Vector2i(cx / BLOC, cz / BLOC)
		if not blocs.has(cle):
			blocs[cle] = [PackedFloat32Array(), 0]
		var tb: PackedFloat32Array = blocs[cle][0]
		tb.append_array(c[3])
		blocs[cle][0] = tb
		blocs[cle][1] += int(c[2])
	for cle in blocs:
		_a_poser.append([3, blocs[cle][0], blocs[cle][1], PORTEE_MOYEN - 200.0, PORTEE_LOIN])
	print("[ReliefForet] %d arbres, %d cases, %d blocs" % [nb_arbres, cases.size(), blocs.size()])


func _process(_dt: float) -> void:
	if _a_poser.is_empty():
		set_process(false)
		return
	var fin: int = Time.get_ticks_usec() + BUDGET_US
	while not _a_poser.is_empty() and Time.get_ticks_usec() < fin:
		var e: Array = _a_poser.pop_back()
		_poser(int(e[0]) - 1, e[1], e[2], e[3], e[4])


func _poser(niveau: int, tampon: PackedFloat32Array, nb: int, debut: float, fin_portee: float) -> void:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _meshes[niveau]
	mm.instance_count = nb
	mm.buffer = tampon
	var mi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _mats[niveau]
	mi.layers = 1 | Cabin.LAYER_RELIEF
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if niveau == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_begin = debut
	mi.visibility_range_end = fin_portee
	mi.set_meta("sans_collision", true)
	add_child(mi)


## Hauteur 1, rayon 1 : `etages` couronnes de `pans` pans, irrégulières, normales adoucies
## (UV : x neige, y ombre).
func _conifere(etages: int, pans: int, avec_tronc: bool) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var alea: RandomNumberGenerator = RandomNumberGenerator.new()
	alea.seed = 2747
	for e in range(etages):
		var t0: float = float(e) / etages
		var bas: float = 0.06 + 0.84 * t0
		var haut: float = minf(bas + 2.1 / etages, 1.0)
		var rayon: float = 0.62 * pow(1.0 - t0 * 0.93, 0.9)
		var pointes: Array = []
		for p in range(pans):
			var a: float = TAU * (p + 0.41 * e) / pans
			var rr: float = rayon * alea.randf_range(0.78, 1.15)
			pointes.append(Vector3(cos(a) * rr, bas - alea.randf_range(0.0, 0.03), sin(a) * rr))
		var s: Vector3 = Vector3(0.0, haut, 0.0)
		for p in range(pans):
			var v0: Vector3 = pointes[p]
			var v1: Vector3 = pointes[(p + 1) % pans]
			# la moitié du cône seulement reçoit la neige : le dessus de la branche
			for q in [[v0, 0.05, 0.55], [s, 0.70, 1.0], [v1, 0.05, 0.55]]:
				var pt: Vector3 = q[0]
				var nm: Vector3 = (Vector3(pt.x, 0.0, pt.z).normalized() + Vector3.UP * 0.9).normalized() if pt != s else Vector3.UP
				st.set_normal(nm)
				st.set_uv(Vector2(q[1], q[2]))
				st.add_vertex(pt)
	if avec_tronc:
		for p in range(4):
			var a0: float = TAU * p / 4.0
			var a1: float = TAU * (p + 1) / 4.0
			var b0: Vector3 = Vector3(cos(a0) * 0.035, 0.0, sin(a0) * 0.035)
			var b1: Vector3 = Vector3(cos(a1) * 0.035, 0.0, sin(a1) * 0.035)
			var h0: Vector3 = b0 + Vector3.UP * 0.12
			var h1: Vector3 = b1 + Vector3.UP * 0.12
			for q in [b0, h0, b1, b1, h0, h1]:
				st.set_normal(Vector3(cos(a0), 0.0, sin(a0)))
				st.set_uv(Vector2(-1.0, 0.6))
				st.add_vertex(q)
	return st.commit()


func _triangle() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in [[Vector3(-0.6, 0.06, 0.0), 0.25, 0.75], [Vector3(0.0, 1.0, 0.0), 0.8, 1.0], [Vector3(0.6, 0.06, 0.0), 0.25, 0.75]]:
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(q[1], q[2]))
		st.add_vertex(q[0])
	var m: ArrayMesh = st.commit()
	return m
