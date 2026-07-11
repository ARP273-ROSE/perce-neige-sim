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
@export var light_range: float = 26.0   # recouvre l'entraxe de 24 m des
                                        # néons ALLUMÉS (un sur deux) →
                                        # éclairage uniforme, sans creux

# Culling par distance : ~225 néons + signaux = autant d'OmniLight3D qui
# participent toutes au clustering Forward+ et au fog volumétrique chaque
# frame si on les laisse actives. Au-delà de LIGHT_CULL_DIST des deux rames,
# la lumière est éteinte (le bâtonnet émissif, lui, reste visible de loin).
const LIGHT_CULL_DIST: float = 450.0

var tunnel: TunnelBuilder = null
var _lights: Array = []   # paires [OmniLight3D, s_m] pour le culling


func _ready() -> void:
	pass


func build(t: TunnelBuilder) -> void:
	tunnel = t
	_populate()


func _populate() -> void:
	var neon_color: Color = Color(0.75, 0.85, 1.0)  # blanc-bleuté néon industriel
	# Commence APRÈS la salle de gare basse et s'arrête AVANT la haute :
	# dans les salles élargies, un néon à wall_offset du centre flotterait
	# loin du mur (les gares ont leur propre éclairage plafond).
	var s: float = tunnel.station_low_end + 4.0
	var max_s: float = tunnel.station_high_start - 4.0

	# Mesh visible du néon lui-même (bâtonnet émissif)
	var neon_mat: StandardMaterial3D = StandardMaterial3D.new()
	neon_mat.albedo_color = Color(0.9, 0.95, 1.0)
	neon_mat.emission_enabled = true
	neon_mat.emission = neon_color
	neon_mat.emission_energy_multiplier = 4.0
	neon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Tube ÉTEINT : un néon sur deux — retour d'exploitation 2026-07 : le
	# tunnel est éclairé uniformément TOUT DU LONG (pas de zones sombres),
	# mais seul un néon sur deux est allumé. Le tube éteint reste visible
	# (gris, sans émission ni lumière).
	var neon_mat_off: StandardMaterial3D = StandardMaterial3D.new()
	neon_mat_off.albedo_color = Color(0.45, 0.47, 0.50)
	neon_mat_off.roughness = 0.55
	neon_mat_off.metallic = 0.2

	var neon_mesh: BoxMesh = BoxMesh.new()
	neon_mesh.size = Vector3(0.05, 0.08, 1.6)    # tube horizontal 1.6 m

	var idx: int = 0
	while s < max_s:
		var lit: bool = (idx % 2) == 0
		_add_neon(s, neon_mesh, neon_mat if lit else neon_mat_off,
			neon_color, lit)
		idx += 1
		s += spacing_m
	# (Signaux LED verts du croisement SUPPRIMÉS — retour d'essai 2026-07 :
	# ils teintaient le tunnel en vert/rouge à l'entrée, au milieu et à la
	# sortie de l'évitement ; l'éclairage doit rester uniforme comme ailleurs.)



# Éteint les OmniLight3D loin des deux rames (rame 1 à s_cabin, rame 2 à
# LENGTH - s_cabin). À appeler à basse fréquence (~2 Hz) depuis main.gd —
# inutile de le faire à 60 Hz, une rame parcourt < 7 m entre deux appels.
func update_light_culling(s_cabin: float) -> void:
	var s_ghost: float = PNConstants.LENGTH - s_cabin
	for entry in _lights:
		var light: OmniLight3D = entry[0]
		var ls: float = entry[1]
		var d: float = minf(absf(ls - s_cabin), absf(ls - s_ghost))
		light.visible = d < LIGHT_CULL_DIST


func _add_neon(s: float, mesh: BoxMesh, neon_mat: StandardMaterial3D,
		color: Color, lit: bool = true) -> void:
	var xform: Transform3D = tunnel.transform_at(s)
	var right: Vector3 = xform.basis.x
	var up: Vector3 = xform.basis.y
	# Néon sur le mur gauche (côté -X local). Dans la chambre de croisement,
	# la paroi s'écarte de |passing_loop_offset| → le néon suit le mur au
	# lieu de rester suspendu au milieu (la rame le traverserait).
	var wall_x: float = wall_offset + absf(tunnel.passing_loop_offset(s, 1.0))
	var wall_pos: Vector3 = xform.origin - right * wall_x + up * height_offset

	# Source lumineuse — seulement pour les tubes ALLUMÉS (un sur deux)
	if lit:
		var light: OmniLight3D = OmniLight3D.new()
		light.position = wall_pos
		light.light_color = color
		light.light_energy = light_energy
		light.omni_range = light_range
		light.omni_attenuation = 1.2
		light.shadow_enabled = false
		add_child(light)
		_lights.append([light, s])

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
