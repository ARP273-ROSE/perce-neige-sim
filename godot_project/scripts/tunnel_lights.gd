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

# Culling par distance : ~225 néons + signaux = autant d'OmniLight3D qui
# participent toutes au clustering Forward+ et au fog volumétrique chaque
# frame si on les laisse actives. Au-delà de LIGHT_CULL_DIST des deux rames,
# la lumière est éteinte (le bâtonnet émissif, lui, reste visible de loin).
const LIGHT_CULL_DIST: float = 250.0

var tunnel: TunnelBuilder = null
var _lights: Array = []   # paires [OmniLight3D, s_m] pour le culling


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

	# Signaux LED vertes au plafond de chaque entrée du croisement Abt
	# (les positions s des signaux sont enregistrées dans _lights aussi)
	# (cf. photos v1_17 et frames V2 d'entrée du loop : on voit 2 LED
	# vertes brillantes côte à côte au-dessus du tunnel à chaque bout
	# de la chambre).
	_add_crossing_signals()


func _add_crossing_signals() -> void:
	var green: Color = Color(0.3, 1.0, 0.4)
	var led_mat: StandardMaterial3D = StandardMaterial3D.new()
	led_mat.albedo_color = Color(0.8, 1.0, 0.85)
	led_mat.emission_enabled = true
	led_mat.emission = green
	led_mat.emission_energy_multiplier = 8.0
	led_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var led_mesh: SphereMesh = SphereMesh.new()
	led_mesh.radius = 0.06
	led_mesh.height = 0.12
	led_mesh.radial_segments = 10
	led_mesh.rings = 6

	# Placer une paire (côte à côte) à chaque bord du loop + une au milieu.
	# ceiling_y suit le plafond local : dans la chambre, le rayon croît de
	# |passing_loop_offset| → la LED du milieu reste collée au plafond au
	# lieu de flotter à 1,55 m dans une chambre de 5,45 m de rayon.
	var pair_dx: float = 0.18    # écart entre les 2 LED de la paire
	var positions: Array = [
		PNConstants.PASSING_START + 4.0,
		(PNConstants.PASSING_START + PNConstants.PASSING_END) * 0.5,
		PNConstants.PASSING_END - 4.0,
	]
	for s_led in positions:
		var xform: Transform3D = tunnel.transform_at(s_led)
		var right: Vector3 = xform.basis.x
		var up: Vector3 = xform.basis.y
		var r_local: float = (tunnel.tunnel_radius if tunnel else 1.95) \
			+ absf(tunnel.passing_loop_offset(s_led, 1.0))
		var ceiling_y: float = r_local - 0.40
		var base_pos: Vector3 = xform.origin + up * ceiling_y
		for side in [-1.0, 1.0]:
			var pos: Vector3 = base_pos + right * (pair_dx * side)
			# Lumière diffuse omnidirectionnelle
			var light: OmniLight3D = OmniLight3D.new()
			light.position = pos
			light.light_color = green
			light.light_energy = 3.0
			light.omni_range = 6.0
			light.shadow_enabled = false
			add_child(light)
			_lights.append([light, s_led])
			# Mesh visible (sphère émissive)
			var led: MeshInstance3D = MeshInstance3D.new()
			led.mesh = led_mesh
			led.set_surface_override_material(0, led_mat)
			led.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(led)
			led.global_position = pos


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


func _add_neon(s: float, mesh: BoxMesh, neon_mat: StandardMaterial3D, color: Color) -> void:
	var xform: Transform3D = tunnel.transform_at(s)
	var right: Vector3 = xform.basis.x
	var up: Vector3 = xform.basis.y
	# Néon sur le mur gauche (côté -X local). Dans la chambre de croisement,
	# la paroi s'écarte de |passing_loop_offset| → le néon suit le mur au
	# lieu de rester suspendu au milieu (la rame le traverserait).
	var wall_x: float = wall_offset + absf(tunnel.passing_loop_offset(s, 1.0))
	var wall_pos: Vector3 = xform.origin - right * wall_x + up * height_offset

	# Source lumineuse
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
