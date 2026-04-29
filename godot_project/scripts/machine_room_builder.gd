class_name MachineRoomBuilder
extends Node3D
## Salle des machines Panoramic — gare amont (Grande Motte).
##
## Contient la poulie motrice (∅ 4160 mm, source remontees-mecaniques.net),
## les 3 moteurs DC 800 kW couplés, un arc de câble connectant les 2 brins
## sur la poulie, et l'éclairage industriel. Située juste après la fin du
## tunnel (s > LENGTH), dans un espace plus large et plus haut que le tunnel.
##
## La poulie motrice tourne en temps réel selon physics.v (cf. update_rotation).

@export var room_depth: float = 16.0        # profondeur salle (sens voie)
@export var room_width: float = 16.0        # largeur
@export var room_height: float = 6.5        # hauteur plafond
@export var room_offset_s: float = 4.0      # décalage derrière la fin du tunnel

@export var pulley_diameter: float = 4.16   # ∅ poulie motrice (réel : 4160 mm)
@export var pulley_thickness: float = 1.20  # épaisseur hub
@export var pulley_groove_depth: float = 0.08  # profondeur gorge

@export var motor_count: int = 3
@export var motor_width: float = 1.10       # largeur boîte moteur
@export var motor_height: float = 1.40
@export var motor_length: float = 2.20
@export var motor_spacing: float = 1.60

var tunnel: TunnelBuilder = null

# Noeud racine de la poulie motrice — tourné chaque frame selon v
var _pulley_spin_node: Node3D = null
var _pulley_angle: float = 0.0    # radians accumulés


func build(t: TunnelBuilder) -> void:
	tunnel = t
	_build_room_shell()
	_build_pulley()
	_build_motors()
	_build_cable_wrap()
	_build_lights()


# ---------------------------------------------------------------------------
# Coquille salle : plancher, murs, plafond en béton industriel
# ---------------------------------------------------------------------------

func _build_room_shell() -> void:
	# Repère : s_center = LENGTH + room_offset_s + room_depth/2
	# La salle s'étend de s = LENGTH + room_offset_s jusqu'à LENGTH + room_offset_s + room_depth
	# On utilise la base locale à la fin du tunnel (approximation — la salle est droite)
	var xform: Transform3D = tunnel.transform_at(PNConstants.LENGTH)

	var concrete_mat: StandardMaterial3D = StandardMaterial3D.new()
	concrete_mat.albedo_color = Color(0.42, 0.40, 0.37)
	concrete_mat.roughness = 0.92
	concrete_mat.metallic = 0.0
	concrete_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Plancher, plafond, 3 murs (le 4e côté tunnel est ouvert)
	var floor_mi: MeshInstance3D = _box_mesh(
		Vector3(room_width, 0.3, room_depth), concrete_mat, "Floor",
	)
	var ceil_mi: MeshInstance3D = _box_mesh(
		Vector3(room_width, 0.3, room_depth), concrete_mat, "Ceiling",
	)
	var wall_back_mi: MeshInstance3D = _box_mesh(
		Vector3(room_width, room_height, 0.3), concrete_mat, "WallBack",
	)
	var wall_left_mi: MeshInstance3D = _box_mesh(
		Vector3(0.3, room_height, room_depth), concrete_mat, "WallLeft",
	)
	var wall_right_mi: MeshInstance3D = _box_mesh(
		Vector3(0.3, room_height, room_depth), concrete_mat, "WallRight",
	)

	# Positions locales dans le repère base tunnel (right, up, -tangent)
	# Origine = début de la salle (s = LENGTH + room_offset_s), centrée latéralement
	var s_center_offset: float = room_offset_s + room_depth * 0.5
	var y_floor: float = -1.40                     # plancher salle (légèrement sous celui du tunnel)
	var y_ceil: float = y_floor + room_height

	# Le "devant" (côté tunnel) est à s=LENGTH + room_offset_s
	# Le "derrière" (mur back) est à s=LENGTH + room_offset_s + room_depth

	# Place les meshes via la base locale à la fin du tunnel
	_place_local(floor_mi, xform, 0.0, y_floor, s_center_offset)
	_place_local(ceil_mi, xform, 0.0, y_ceil, s_center_offset)
	_place_local(wall_back_mi, xform, 0.0, (y_floor + y_ceil) * 0.5, room_offset_s + room_depth)
	_place_local(wall_left_mi, xform, -room_width * 0.5, (y_floor + y_ceil) * 0.5, s_center_offset)
	_place_local(wall_right_mi, xform, room_width * 0.5, (y_floor + y_ceil) * 0.5, s_center_offset)

	add_child(floor_mi)
	add_child(ceil_mi)
	add_child(wall_back_mi)
	add_child(wall_left_mi)
	add_child(wall_right_mi)


# ---------------------------------------------------------------------------
# Poulie motrice ∅ 4160 mm + ancrage mural + 2 brins
# ---------------------------------------------------------------------------

func _build_pulley() -> void:
	var xform: Transform3D = tunnel.transform_at(PNConstants.LENGTH)

	# Matériaux
	var hub_mat: StandardMaterial3D = StandardMaterial3D.new()
	hub_mat.albedo_color = Color(0.22, 0.24, 0.27)
	hub_mat.roughness = 0.40
	hub_mat.metallic = 0.75

	var rim_mat: StandardMaterial3D = StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.35, 0.37, 0.42)
	rim_mat.roughness = 0.25
	rim_mat.metallic = 0.90

	var shaft_mat: StandardMaterial3D = StandardMaterial3D.new()
	shaft_mat.albedo_color = Color(0.18, 0.18, 0.20)
	shaft_mat.roughness = 0.35
	shaft_mat.metallic = 0.95

	var support_mat: StandardMaterial3D = StandardMaterial3D.new()
	support_mat.albedo_color = Color(0.30, 0.30, 0.35)
	support_mat.roughness = 0.50
	support_mat.metallic = 0.80

	# Noeud racine pour la rotation
	_pulley_spin_node = Node3D.new()
	_pulley_spin_node.name = "PulleySpin"

	# Hub central
	var hub: MeshInstance3D = MeshInstance3D.new()
	var hub_mesh: CylinderMesh = CylinderMesh.new()
	hub_mesh.top_radius = pulley_diameter * 0.50
	hub_mesh.bottom_radius = pulley_diameter * 0.50
	hub_mesh.height = pulley_thickness
	hub_mesh.radial_segments = 64
	hub_mesh.rings = 2
	hub_mesh.material = hub_mat
	hub.mesh = hub_mesh
	hub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Axe cylindre Y local ; on veut axe horizontal perpendiculaire voie (= X local)
	# Donc rotation 90° autour de Z local
	hub.rotation = Vector3(0.0, 0.0, PI * 0.5)
	_pulley_spin_node.add_child(hub)

	# Jante extérieure + gorge (bande émissive pour distinguer)
	# Simplifiée : 1 cylindre légèrement plus grand autour du hub
	var rim: MeshInstance3D = MeshInstance3D.new()
	var rim_mesh: CylinderMesh = CylinderMesh.new()
	rim_mesh.top_radius = pulley_diameter * 0.50 + 0.04
	rim_mesh.bottom_radius = pulley_diameter * 0.50 + 0.04
	rim_mesh.height = pulley_thickness * 0.25
	rim_mesh.radial_segments = 64
	rim_mesh.rings = 1
	rim_mesh.material = rim_mat
	rim.mesh = rim_mesh
	rim.rotation = Vector3(0.0, 0.0, PI * 0.5)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pulley_spin_node.add_child(rim)

	# 4 rayons décoratifs pour visualiser la rotation
	var spoke_mat: StandardMaterial3D = StandardMaterial3D.new()
	spoke_mat.albedo_color = Color(0.48, 0.48, 0.52)
	spoke_mat.roughness = 0.35
	spoke_mat.metallic = 0.85
	for i in range(6):
		var angle: float = float(i) / 6.0 * TAU
		var spoke: MeshInstance3D = MeshInstance3D.new()
		var spoke_mesh: BoxMesh = BoxMesh.new()
		spoke_mesh.size = Vector3(pulley_diameter * 0.45, 0.15, pulley_thickness * 0.95)
		spoke_mesh.material = spoke_mat
		spoke.mesh = spoke_mesh
		spoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Orientation : rayon dans le plan Y-Z du spin_node (plan de la poulie),
		# après application de rotation du spin_node.
		spoke.rotation = Vector3(0.0, 0.0, angle)
		_pulley_spin_node.add_child(spoke)

	# Positionne le pulley_spin_node sur la scène
	# Centre de la poulie : à room_offset_s + room_depth * 0.5 en s,
	# à hauteur y_pulley_center (au-dessus des brins entrant du tunnel)
	var y_pulley_center: float = 1.55    # axe poulie au-dessus du centre tunnel
	var s_pulley_center: float = room_offset_s + room_depth * 0.5

	add_child(_pulley_spin_node)
	_place_local(_pulley_spin_node, xform, 0.0, y_pulley_center, s_pulley_center)

	# Arbre moteur : cylindre horizontal qui traverse le hub vers les moteurs
	var shaft: MeshInstance3D = MeshInstance3D.new()
	var shaft_mesh: CylinderMesh = CylinderMesh.new()
	shaft_mesh.top_radius = 0.25
	shaft_mesh.bottom_radius = 0.25
	shaft_mesh.height = 5.0
	shaft_mesh.radial_segments = 16
	shaft_mesh.material = shaft_mat
	shaft.mesh = shaft_mesh
	shaft.rotation = Vector3(0.0, 0.0, PI * 0.5)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shaft)
	_place_local(shaft, xform, 3.0, y_pulley_center, s_pulley_center)  # vers la droite (côté moteurs)

	# Supports latéraux (2 paliers massifs qui supportent l'arbre)
	for side in [-1.0, 1.0]:
		var support: MeshInstance3D = MeshInstance3D.new()
		var support_mesh: BoxMesh = BoxMesh.new()
		support_mesh.size = Vector3(0.80, y_pulley_center - (-1.40) + 0.50, 0.80)
		support_mesh.material = support_mat
		support.mesh = support_mesh
		support.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(support)
		var y_center_support: float = (-1.40 + y_pulley_center) * 0.5
		_place_local(support, xform, side * (pulley_thickness * 0.5 + 0.50), y_center_support, s_pulley_center)


# ---------------------------------------------------------------------------
# 3 moteurs DC 800 kW en ligne le long du côté droit
# ---------------------------------------------------------------------------

func _build_motors() -> void:
	var xform: Transform3D = tunnel.transform_at(PNConstants.LENGTH)
	var motor_mat: StandardMaterial3D = StandardMaterial3D.new()
	motor_mat.albedo_color = Color(0.15, 0.40, 0.20)     # vert industriel Von Roll
	motor_mat.roughness = 0.50
	motor_mat.metallic = 0.70

	var cooling_mat: StandardMaterial3D = StandardMaterial3D.new()
	cooling_mat.albedo_color = Color(0.25, 0.25, 0.28)
	cooling_mat.roughness = 0.40
	cooling_mat.metallic = 0.90

	var s_first: float = room_offset_s + room_depth * 0.5 - (float(motor_count) - 1.0) * 0.5 * (motor_length + motor_spacing)
	var x_motor: float = 5.5    # sur le côté droit de la salle
	var y_motor: float = -1.40 + motor_height * 0.5 + 0.05

	for i in range(motor_count):
		var s_pos: float = s_first + float(i) * (motor_length + motor_spacing)
		# Corps moteur
		var body: MeshInstance3D = MeshInstance3D.new()
		var body_mesh: CylinderMesh = CylinderMesh.new()
		body_mesh.top_radius = motor_height * 0.5
		body_mesh.bottom_radius = motor_height * 0.5
		body_mesh.height = motor_length
		body_mesh.radial_segments = 24
		body_mesh.material = motor_mat
		body.mesh = body_mesh
		# Axe cylindre Y → on veut axe X (vers la droite pour que le moteur pointe vers l'arbre poulie)
		# Actually mon moteur est transversal (axe dans le sens de la voie = Z local)
		# Pour que le cylindre s'étende le long de Z local, rotation 90° autour de X local
		body.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(body)
		_place_local(body, xform, x_motor, y_motor, s_pos)

		# Socle / palier
		var base: MeshInstance3D = MeshInstance3D.new()
		var base_mesh: BoxMesh = BoxMesh.new()
		base_mesh.size = Vector3(motor_width * 1.2, 0.15, motor_length * 1.1)
		base_mesh.material = cooling_mat
		base.mesh = base_mesh
		base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(base)
		_place_local(base, xform, x_motor, -1.40 + 0.08, s_pos)


# ---------------------------------------------------------------------------
# Arc de câble qui s'enroule sur la poulie motrice
# Simplification : on dessine un demi-cercle par brin, dans le plan (Y, Z local).
# Brin gauche (x=-0.12) arrive tangentiellement en bas, fait un demi-tour
# par-dessus la poulie, redescend. Idem brin droite à x=+0.12.
# ---------------------------------------------------------------------------

func _build_cable_wrap() -> void:
	var xform: Transform3D = tunnel.transform_at(PNConstants.LENGTH)
	var cable_mat: StandardMaterial3D = StandardMaterial3D.new()
	cable_mat.albedo_color = Color(0.18, 0.18, 0.20)
	cable_mat.roughness = 0.35
	cable_mat.metallic = 0.95
	cable_mat.emission_enabled = true
	cable_mat.emission = Color(0.10, 0.10, 0.12)
	cable_mat.emission_energy_multiplier = 0.3

	# Position de l'axe poulie en base locale
	var y_pulley_center: float = 1.55
	var s_pulley_center: float = room_offset_s + room_depth * 0.5
	var r_pulley: float = pulley_diameter * 0.5
	# Les brins arrivent au tunnel à hauteur y ≈ _cable_top_y + cable_radius ≈ -0.50
	# Sur la poulie, ils sont tangents sur le pourtour. Si le brin arrive du tunnel
	# à la hauteur y_brin ≈ -0.50, il touche la poulie à (s_pulley_center - distance
	# où cercle de rayon r_pulley intersecte y_brin).
	# Simplification : on modélise un arc de 180° du point de tangence tunnel-side
	# (bas gauche de la poulie) au point symétrique (bas droit), faisant un demi-tour
	# par le dessus.
	var y_brin: float = -0.50
	# Distance horizontale (en s) du centre poulie au point de tangence
	var dy: float = y_pulley_center - y_brin
	# Si dy < r_pulley, le point de tangence existe
	var dz: float = sqrt(maxf(0.001, r_pulley * r_pulley - dy * dy))
	# Point tangence tunnel-side : s=s_pulley_center - dz, y=y_brin
	# Point tangence opposite : s=s_pulley_center + dz, y=y_brin
	# Entre les deux, arc de cercle qui monte par-dessus la poulie

	# On dessine l'arc pour chaque brin (x = ±0.12)
	for side in [-1.0, 1.0]:
		var x_offset: float = 0.12 * side
		_build_arc_cable(cable_mat, xform, x_offset, y_pulley_center, s_pulley_center, r_pulley, y_brin)


func _build_arc_cable(
	mat: StandardMaterial3D, xform: Transform3D,
	x_offset: float, y_center: float, s_center: float, r_pulley: float, y_brin: float,
) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)

	var cable_r: float = 0.026
	var cable_segs: int = 8
	var n_arc: int = 32

	# Arc : angle de -theta_max à +theta_max (mesuré depuis la verticale UP)
	# où theta_max = angle du point de tangence avec le tunnel
	# cos(theta_max) = dy/r_pulley
	# sin(theta_max) = dz/r_pulley
	var dy: float = y_center - y_brin
	var theta_max: float = acos(clampf(dy / r_pulley, -1.0, 1.0))

	# Extension droite avant/après l'arc (pour se connecter au tunnel)
	# Le brin vient du tunnel à s=0 local (début de salle, = LENGTH absolu)
	# On ajoute 2 segments droits : entrée tunnel → tangence bas gauche, tangence bas droit → retour tunnel
	# Mais les brins de track_builder s'arrêtent déjà à s=LENGTH. On dessine le segment droit
	# depuis s=0 local (LENGTH absolu) jusqu'au point de tangence.

	var samples: Array = []   # Array of {pos: Vector3, tangent: Vector3}

	# Segment droit d'entrée : du tunnel (s=0 local) au point de tangence gauche
	var p_entry: Vector3 = _local_to_world(xform, Vector3(x_offset, y_brin, 0.0))
	var s_tangent_left: float = s_center - r_pulley * sin(theta_max)
	var p_tangent_left: Vector3 = _local_to_world(xform, Vector3(x_offset, y_brin, s_tangent_left))

	var n_straight: int = 3
	for i in range(n_straight + 1):
		var t: float = float(i) / float(n_straight)
		var p: Vector3 = p_entry.lerp(p_tangent_left, t)
		samples.append(p)

	# Arc sur la poulie
	for i in range(n_arc + 1):
		var t: float = float(i) / float(n_arc)
		# angle va de -theta_max (gauche, tangence tunnel) à +theta_max (droite, tangence retour)
		# en passant par 0 (sommet poulie)
		var angle: float = -theta_max + t * (2.0 * theta_max + (TAU - 2.0 * theta_max))
		# Simplification : on fait un arc de 180° (demi-tour complet), du point de tangence gauche
		# en passant par le haut, au point symétrique
		var arc_angle: float = PI * (1.0 - t)    # de PI (bas gauche horaire) à 0 (bas droit) via haut
		# Position dans le plan (Y, Z local) : centre + rayon * (sin, cos) — mais on veut l'arc par le haut
		# Utilisons (y, z_offset_from_center) = (cos(arc_angle), sin(arc_angle)) × r_pulley
		var dy_arc: float = cos(arc_angle) * r_pulley
		var dz_arc: float = sin(arc_angle) * r_pulley
		var y_arc: float = y_center - dy_arc   # inversion pour que angle=0 → point bas, PI → point haut
		var s_arc: float = s_center - dz_arc   # Actually: on veut t=0 → tangence_left donc s=s_tangent_left
		# Simplification : arc paramétrique entre les deux tangents passant par le haut
		# Param : angle de -PI/2 - theta_max à +PI/2 + theta_max
		# Let me redo this more cleanly
		pass

	# Reset : approche plus simple — 3 segments :
	#   1. Tunnel → tangent_left (droit)
	#   2. Arc tangent_left → tangent_right (demi-cercle par le haut)
	#   3. tangent_right → tunnel (droit retour)
	samples.clear()

	# Segment 1 : p_entry → p_tangent_left
	for i in range(n_straight + 1):
		var t: float = float(i) / float(n_straight)
		samples.append(p_entry.lerp(p_tangent_left, t))

	# Segment 2 : arc. Paramétrons l'angle arc_ang de (PI + theta_max) à (-theta_max),
	# décrit dans le plan (Y, Z) centré sur (y_center, s_center).
	# arc_ang = PI + theta_max → point à y_brin, s=s_center - r*sin(theta_max) (tangence gauche)
	# arc_ang = 0 → point à y_center + r, s=s_center (sommet)
	# arc_ang = -theta_max → point à y_brin, s=s_center + r*sin(theta_max) (tangence droite)
	# Un parcours continu : t ∈ [0, 1] → arc_ang = (PI + theta_max) - t * (PI + 2*theta_max)
	for i in range(1, n_arc):
		var t: float = float(i) / float(n_arc)
		var arc_ang: float = (PI + theta_max) - t * (PI + 2.0 * theta_max)
		var y_pt: float = y_center + cos(arc_ang) * r_pulley
		var s_pt: float = s_center - sin(arc_ang) * r_pulley
		samples.append(_local_to_world(xform, Vector3(x_offset, y_pt, s_pt)))

	# Point tangence droite
	var s_tangent_right: float = s_center + r_pulley * sin(theta_max)
	var p_tangent_right: Vector3 = _local_to_world(xform, Vector3(x_offset, y_brin, s_tangent_right))
	samples.append(p_tangent_right)

	# Segment 3 : tangent_right → p_exit (extension en arrière dans la salle)
	var p_exit: Vector3 = _local_to_world(xform, Vector3(x_offset, y_brin, room_depth + room_offset_s - 0.5))
	for i in range(1, n_straight + 1):
		var t: float = float(i) / float(n_straight)
		samples.append(p_tangent_right.lerp(p_exit, t))

	# Génère le tube autour des samples
	# Base orthonormée : tangent local = différence de positions, up = +Y monde
	for i in range(samples.size() - 1):
		var c0: Vector3 = samples[i]
		var c1: Vector3 = samples[i + 1]
		var tg: Vector3 = (c1 - c0).normalized()
		var up_w: Vector3 = Vector3.UP
		var r_vec: Vector3 = tg.cross(up_w).normalized()
		if r_vec.length() < 0.01:
			r_vec = Vector3.RIGHT
		var u_vec: Vector3 = r_vec.cross(tg).normalized()

		for k in range(cable_segs):
			var a0: float = float(k) / float(cable_segs) * TAU
			var a1: float = float(k + 1) / float(cable_segs) * TAU
			var p00: Vector3 = c0 + r_vec * cos(a0) * cable_r + u_vec * sin(a0) * cable_r
			var p01: Vector3 = c0 + r_vec * cos(a1) * cable_r + u_vec * sin(a1) * cable_r
			var p10: Vector3 = c1 + r_vec * cos(a0) * cable_r + u_vec * sin(a0) * cable_r
			var p11: Vector3 = c1 + r_vec * cos(a1) * cable_r + u_vec * sin(a1) * cable_r

			st.set_uv(Vector2(0, 0)); st.add_vertex(p00)
			st.set_uv(Vector2(0, 1)); st.add_vertex(p10)
			st.set_uv(Vector2(1, 1)); st.add_vertex(p11)
			st.set_uv(Vector2(0, 0)); st.add_vertex(p00)
			st.set_uv(Vector2(1, 1)); st.add_vertex(p11)
			st.set_uv(Vector2(1, 0)); st.add_vertex(p01)

	st.generate_normals()
	st.generate_tangents()

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "CableWrap_%s" % ("L" if x_offset < 0.0 else "R")
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------------------------------------------------------------------------
# Éclairage industriel
# ---------------------------------------------------------------------------

func _build_lights() -> void:
	var xform: Transform3D = tunnel.transform_at(PNConstants.LENGTH)
	var y_ceil_light: float = -1.40 + room_height - 0.4

	var neon_mat: StandardMaterial3D = StandardMaterial3D.new()
	neon_mat.albedo_color = Color(0.98, 0.99, 1.0)
	neon_mat.emission_enabled = true
	neon_mat.emission = Color(0.95, 0.97, 1.0)
	neon_mat.emission_energy_multiplier = 3.0
	neon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for zz in range(3):
		for xx in range(2):
			var s_pos: float = room_offset_s + 3.5 + float(zz) * 4.0
			var x_pos: float = -3.5 + float(xx) * 7.0

			var light: OmniLight3D = OmniLight3D.new()
			light.light_color = Color(0.95, 0.97, 1.0)
			light.light_energy = 6.0
			light.omni_range = 14.0
			light.omni_attenuation = 1.0
			light.shadow_enabled = false
			add_child(light)
			_place_local(light, xform, x_pos, y_ceil_light, s_pos)

			# Bâtonnet visible
			var neon: MeshInstance3D = MeshInstance3D.new()
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(2.4, 0.1, 0.2)
			box.material = neon_mat
			neon.mesh = box
			neon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(neon)
			_place_local(neon, xform, x_pos, y_ceil_light, s_pos)


# ---------------------------------------------------------------------------
# Animation : rotation de la poulie selon physics.v
# Appelée depuis main._process(). v est la vitesse m/s du câble.
# Omega = v / rayon_poulie.
# ---------------------------------------------------------------------------

func update_rotation(v_cable: float, delta: float) -> void:
	if _pulley_spin_node == null:
		return
	var omega: float = v_cable / (pulley_diameter * 0.5)
	_pulley_angle += omega * delta
	# Rotation autour de l'axe X local (= right de la base tunnel)
	# Le _pulley_spin_node est placé par _place_local qui applique la rotation
	# de l'xform base. La rotation locale à appliquer est autour de l'axe de la
	# poulie, qui après _place_local est X local du noeud. On rotate autour de X.
	_pulley_spin_node.rotation = Vector3(_pulley_angle, 0.0, 0.0)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Place un Node3D dans la base locale du repère tunnel à la fin du tunnel.
# offset_x, offset_y, offset_s sont dans le repère local (right, up, -tangent).
func _place_local(node: Node3D, base_xform: Transform3D, ox: float, oy: float, os_s: float) -> void:
	var right: Vector3 = base_xform.basis.x
	var up: Vector3 = base_xform.basis.y
	var tangent: Vector3 = -base_xform.basis.z  # tangent = -basis.z dans notre convention
	var pos: Vector3 = base_xform.origin + right * ox + up * oy + tangent * os_s
	var t: Transform3D = base_xform
	t.origin = pos
	# On garde la basis de la salle alignée avec celle du tunnel à son extrémité
	node.transform = t


func _local_to_world(base_xform: Transform3D, local: Vector3) -> Vector3:
	var right: Vector3 = base_xform.basis.x
	var up: Vector3 = base_xform.basis.y
	var tangent: Vector3 = -base_xform.basis.z
	return base_xform.origin + right * local.x + up * local.y + tangent * local.z


func _box_mesh(size: Vector3, mat: StandardMaterial3D, name: String) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	box.material = mat
	mi.mesh = box
	mi.name = name
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
