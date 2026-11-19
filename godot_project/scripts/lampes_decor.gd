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
