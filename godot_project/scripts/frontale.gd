## Lampe frontale (19/11/2026) : une SpotLight3D sur le casque, inclinée vers la neige devant les skis, et sa
## lentille (petite pastille émissive, visible de loin). Allumée la nuit et au crépuscule seulement ; sans ombres.
## Repère du porteur : −Z vers l'avant, Y vers le haut, pieds en 0.
class_name Frontale
extends Node3D

const HAUTEUR: float = 1.72
const PORTEE: float = 38.0

static var _mat_lentille: StandardMaterial3D = null
static var _maillage_lentille: SphereMesh = null

var lampe: SpotLight3D = null
var lentille: MeshInstance3D = null
## Faux : la pastille seule (skieurs lointains, petites machines) ; vrai : la lumière aussi.
var avec_lumiere: bool = true
## Éclaire la neige (lampe du décor publiée par main) : la frontale du joueur, celle du skieur nocturne le plus proche.
var eclaire: bool = true


## Vraie lumière du moteur ? Pas en rendu de compatibilité (PWA) : une SpotLight y fait compiler une variante de
## nuanceur pour tout ce qu'elle touche (gels de plusieurs secondes sur iPad) ; la neige reste éclairée par le
## nuanceur du sol (LampesDecor), qui lit la position et l'axe de la lampe, même cachée.
static func lumiere_reelle() -> bool:
	return not OS.has_feature("web") and RenderingServer.get_current_rendering_method() != "gl_compatibility"


static func materiau_lentille() -> StandardMaterial3D:
	if _mat_lentille == null:
		_mat_lentille = StandardMaterial3D.new()
		_mat_lentille.resource_name = "frontale_lentille"
		_mat_lentille.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_lentille.albedo_color = Color(1.0, 0.97, 0.88)
		_maillage_lentille = SphereMesh.new()
		_maillage_lentille.radius = 0.045
		_maillage_lentille.height = 0.09
		_maillage_lentille.radial_segments = 8
		_maillage_lentille.rings = 4
	return _mat_lentille


func _init(lumiere: bool = true) -> void:
	name = "Frontale"
	avec_lumiere = lumiere
	position = Vector3(0.0, HAUTEUR, -0.13)
	materiau_lentille()
	lentille = MeshInstance3D.new()
	lentille.name = "Lentille"
	lentille.mesh = _maillage_lentille
	lentille.material_override = _mat_lentille
	lentille.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lentille)
	if lumiere:
		lampe = SpotLight3D.new()
		lampe.name = "Faisceau"
		lampe.light_color = Color(1.0, 0.95, 0.86)
		lampe.light_energy = 4.0
		lampe.spot_range = PORTEE
		lampe.spot_angle = 26.0
		lampe.spot_angle_attenuation = 0.8
		lampe.spot_attenuation = 0.9
		lampe.shadow_enabled = false
		lampe.light_specular = 0.2
		# vers la neige devant les skis (≈ 15 m devant)
		lampe.rotation = Vector3(deg_to_rad(-9.0), 0.0, 0.0)
		lampe.visible = lumiere_reelle()
		add_child(lampe)
	visible = false


func allumer(on: bool) -> void:
	if visible != on:
		visible = on
