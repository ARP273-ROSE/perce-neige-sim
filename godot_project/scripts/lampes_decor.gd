## Lampes du décor (19/11/2026) : le relief est dessiné sans éclairage (nuanceurs « unshaded », ombrage calculé
## par eux) et les vraies lumières du moteur ne l'atteignent pas. La nuit, frontales, phares des dameuses et
## candélabres des gares éclairent pourtant la neige : jusqu'à N lampes (les plus proches de la caméra) sont
## publiées en paramètres globaux, que le nuanceur du sol (ReliefBuilder.SHADER_TERRAIN, lampes_decor) ajoute
## lui-même. Même rendu en Vulkan et en compatibilité (PWA) ; aucun coût de jour (pn_lampes_n = 0 : calcul sauté).
class_name LampesDecor
extends RefCounted

const N: int = 8
static var _publiees: int = -1
## Dernière liste publiée (bancs).
static var derniere: Array = []


## lampes : Array de Dictionary {p: Vector3, r: portée (m), c: Color (énergie comprise), d: Vector3 (axe d'un
## projecteur, absent pour une lampe omnidirectionnelle), cos: cosinus du demi-angle (projecteur)}.
## Les N premières sont publiées (à trier avant, de la plus utile à la moins utile).
static func publier(lampes: Array) -> void:
	var n: int = mini(lampes.size(), N)
	derniere = lampes.slice(0, n)
	for k in range(maxi(n, maxi(_publiees, 0))):
		var sk: String = str(k)
		if k < n:
			var l: Dictionary = lampes[k]
			var p: Vector3 = l["p"]
			var c: Color = l["c"]
			var d: Vector3 = l.get("d", Vector3.DOWN)
			RenderingServer.global_shader_parameter_set("pn_lampe_p" + sk, Vector4(p.x, p.y, p.z, float(l["r"])))
			RenderingServer.global_shader_parameter_set("pn_lampe_c" + sk, Vector4(c.r, c.g, c.b,
				float(l.get("cos", -2.0)) if l.has("d") else -2.0))
			RenderingServer.global_shader_parameter_set("pn_lampe_d" + sk, Vector4(d.x, d.y, d.z, 0.0))
		else:
			RenderingServer.global_shader_parameter_set("pn_lampe_p" + sk, Vector4(0, 0, 0, 0))
	if n != _publiees:
		_publiees = n
		RenderingServer.global_shader_parameter_set("pn_lampes_n", n)


## Projecteur (SpotLight3D) → lampe du décor.
static func depuis_projecteur(sp: SpotLight3D, gain: float = 1.0) -> Dictionary:
	var xf: Transform3D = sp.global_transform
	return {"p": xf.origin, "r": sp.spot_range, "c": sp.light_color * sp.light_energy * gain * 0.22,
		"d": -xf.basis.z.normalized(), "cos": cos(deg_to_rad(sp.spot_angle))}


## Code GLSL des lampes (même texte que dans ReliefBuilder.SHADER_TERRAIN) : lampes_decor(p, n) en monde.
static func code_glsl() -> String:
	var s: String = "global uniform int pn_lampes_n;\n"
	for k in range(N):
		s += "global uniform vec4 pn_lampe_p%d;\nglobal uniform vec4 pn_lampe_c%d;\nglobal uniform vec4 pn_lampe_d%d;\n" % [k, k, k]
	s += """vec3 une_lampe(vec3 p, vec3 n, vec4 lp, vec4 lc, vec4 ld) {
	vec3 v = lp.xyz - p;
	float d = length(v);
	if (lp.w <= 0.0 || d > lp.w) {
		return vec3(0.0);
	}
	vec3 l = v / max(d, 0.01);
	float att = 1.0 - d / lp.w;
	att *= att;
	float cone = lc.w > -1.5 ? smoothstep(lc.w, mix(lc.w, 1.0, 0.6), dot(-l, ld.xyz)) : 1.0;
	return lc.rgb * (att * cone * max(dot(n, l), 0.0));
}
vec3 lampes_decor(vec3 p, vec3 n) {
	vec3 s = vec3(0.0);
	if (pn_lampes_n > 0) {
"""
	for k in range(N):
		s += "\t\t%ss += une_lampe(p, n, pn_lampe_p%d, pn_lampe_c%d, pn_lampe_d%d);\n" % [
			"" if k == 0 else "if (pn_lampes_n > %d) " % k, k, k, k]
	s += "\t}\n\treturn s;\n}\n"
	return s
