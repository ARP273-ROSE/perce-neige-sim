class_name TunnelLights
extends Node3D
## Néons muraux du tunnel Perce-Neige.
## Un néon tous les 12 m sur le mur latéral, sauf dans les zones sombres
## identifiées dans SlopeProfile.TUNNEL_DARK_ZONES.
##
## Sur un tunnel en montée, les néons sont sur le mur gauche.
## En descente, ils apparaissent sur le mur droit (même physique, vue miroir).

@export var spacing_m: float = 12.0          # espacement néons
@export var wall_offset: float = 1.4         # distance du centre du tunnel
@export var height_offset: float = 0.9       # hauteur (plafond)
@export var light_energy: float = 8.0
@export var light_range: float = 18.0

var tunnel: TunnelBuilder = null


func _ready() -> void:
	pass


func build(t: TunnelBuilder) -> void:
	tunnel = t
	_populate()


func _populate() -> void:
	var neon_color: Color = Color(0.75, 0.85, 1.0)  # blanc-bleuté néon industriel
	var s: float = 30.0  # commence après la station basse
	var max_s: float = PNConstants.LENGTH - 30.0

	# Mesh visible du néon lui-même (bâtonnet émissif)
	var neon_mat: StandardMaterial3D = StandardMaterial3D.new()
	neon_mat.albedo_color = Color(0.9, 0.95, 1.0)
	neon_mat.emission_enabled = true
	neon_mat.emission = neon_color
	neon_mat.emission_energy_multiplier = 4.0
	neon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var neon_mesh: BoxMesh = BoxMesh.new()
	neon_mesh.size = Vector3(0.05, 0.08, 1.6)    # tube horizontal 1.6 m

	while s < max_s:
		if SlopeProfile.tunnel_lit_at(s):
			_add_neon(s, neon_mesh, neon_mat, neon_color)
		s += spacing_m


func _add_neon(s: float, mesh: BoxMesh, neon_mat: StandardMaterial3D, color: Color) -> void:
	var xform: Transform3D = tunnel.transform_at(s)
	var right: Vector3 = xform.basis.x
	var up: Vector3 = xform.basis.y
	# Néon sur le mur gauche (côté -X local)
	var wall_pos: Vector3 = xform.origin - right * wall_offset + up * height_offset

	# Source lumineuse
	var light: OmniLight3D = OmniLight3D.new()
	light.position = wall_pos
	light.light_color = color
	light.light_energy = light_energy
	light.omni_range = light_range
	light.omni_attenuation = 1.2
	light.shadow_enabled = false
	add_child(light)

	# Bâtonnet visible (pour voir la source dans le brouillard volumétrique)
	var neon: MeshInstance3D = MeshInstance3D.new()
	neon.mesh = mesh
	neon.set_surface_override_material(0, neon_mat)
	neon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(neon)
	# Positionner APRÈS add_child (global_transform nécessite d'être dans l'arbre)
	var neon_xform: Transform3D = xform
	neon_xform.origin = wall_pos
	neon.global_transform = neon_xform
