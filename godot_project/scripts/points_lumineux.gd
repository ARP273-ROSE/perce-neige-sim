## Points lumineux lointains (19/11/2026) : fenêtres éclairées des villages et des chalets, phares et gyrophares des
## dameuses vues de loin. Un MultiMesh de petits carrés tournés vers la caméra, de taille constante à l'écran (quelques
## pixels, quelle que soit la distance), additifs, sans lumière ni brouillard, cachés par le relief (test de
## profondeur). Une seule passe de dessin par jeu de points ; aucune vraie lumière.
## Couleur par point dans INSTANCE_CUSTOM : rgb, a = 0 fixe, a > 0 clignotant (phase a, gyrophare).
class_name PointsLumineux
extends MultiMeshInstance3D

const SHADER: String = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform float px = 4.0;              // diamètre à l'écran (pixels)
uniform float niveau = 1.0;          // 0 éteint, 1 allumé
varying vec4 coul;
void vertex() {
	vec4 c = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float d = max(-c.z, 0.5);
	float s = px * d / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	c.xy += VERTEX.xy * s;
	POSITION = PROJECTION_MATRIX * c;
	coul = INSTANCE_CUSTOM;
}
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float a = max(1.0 - dot(q, q), 0.0);
	a *= a;
	if (coul.a > 0.0) {
		a *= 0.15 + 0.85 * pow(max(sin(TIME * 6.5 + coul.a * 6.2832), 0.0), 3.0);
	}
	ALBEDO = coul.rgb * a * niveau;
}
"""

static var _shader: Shader = null
static var _quad: QuadMesh = null
var mat: ShaderMaterial = null


static func materiau() -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
		_quad = QuadMesh.new()
		_quad.size = Vector2(2.0, 2.0)
	var m := ShaderMaterial.new()
	m.shader = _shader
	return m


func _init(nom: String = "PointsLumineux", px: float = 4.0) -> void:
	name = nom
	mat = materiau()
	mat.set_shader_parameter("px", px)
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _quad
	multimesh = mm
	# (les points couvrent tout le domaine : jamais écartés par la caméra)
	custom_aabb = AABB(Vector3(-20000, -1000, -20000), Vector3(40000, 6000, 40000))


## Pose les points (monde) et leurs couleurs (INSTANCE_CUSTOM).
func poser(pts: PackedVector3Array, couleurs: PackedColorArray) -> void:
	var mm: MultiMesh = multimesh
	if mm.instance_count != pts.size():
		mm.instance_count = pts.size()
	var buf := PackedFloat32Array()
	buf.resize(pts.size() * 16)
	for i in range(pts.size()):
		var k: int = i * 16
		var p: Vector3 = pts[i]
		var c: Color = couleurs[i]
		buf[k] = 1.0
		buf[k + 3] = p.x
		buf[k + 5] = 1.0
		buf[k + 7] = p.y
		buf[k + 10] = 1.0
		buf[k + 11] = p.z
		buf[k + 12] = c.r
		buf[k + 13] = c.g
		buf[k + 14] = c.b
		buf[k + 15] = c.a
	if pts.size() > 0:
		mm.buffer = buf
	mm.visible_instance_count = pts.size()


func regler_niveau(n: float) -> void:
	mat.set_shader_parameter("niveau", n)
	visible = n > 0.01 and multimesh.visible_instance_count > 0
