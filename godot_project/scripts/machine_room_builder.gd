class_name MachineRoomBuilder
extends Node3D
## Machinerie de la gare amont (Grande Motte).
##
## Retour d'essai 2026-09-27 : « le mécanisme à l'arrivée est sous terre en
## haut, on ne voit que la grosse roue aval dont le sommet dépasse au début de
## la voie, et c'est tout ». La salle (poulie motrice ∅ 4160 mm, source
## remontees-mecaniques.net, 3 moteurs DC 800 kW, éclairage) est donc
## construite SOUS la dalle de la gare : invisible, mais le câble y descend
## réellement par la roue aval, dont seul le sommet émerge d'une fente du sol
## au bout de la voie. Au-dessus : la dalle qui prolonge la gare jusqu'au mur
## du fond (bardage bois « DESTINATION GLACIER », photo 095119).
##
## Les deux roues tournent en temps réel selon physics.v (cf. update_rotation).

const Y_HALL_FLOOR: float = -1.60     # dessus de la dalle de gare (stations_builder.FLOOR_Y_LOCAL)
const Y_HALL_CEIL: float = 2.65       # plafond de la salle de gare (tunnel.station_room_half_height)
const HALL_HALF_W: float = 4.90       # tunnel.station_room_half_width
const HALL_DEPTH: float = 9.0         # de la fin de voie au mur du fond
const Y_BRIN: float = -1.36           # brins sur la voie : 4 cm au-dessus des blochets (track_builder, 2026-09-27)
const SHEAVE_R: float = 2.00          # roue aval ∅ 4,0 m
const SHEAVE_S: float = 4.5           # axe de la roue aval, après la fin de voie
const SHEAVE_W: float = 0.90          # épaisseur (2 gorges)
const SLOT_HALF_W: float = 0.90       # demi-largeur de la fente dans la dalle

@export var room_depth: float = 16.0        # profondeur salle (sens voie)
@export var room_width: float = 9.8         # largeur (= la salle de gare)
@export var room_height: float = 6.5        # hauteur sous dalle
@export var room_offset_s: float = 1.0      # début de la salle après la fin de voie
@export var pulley_diameter: float = 4.16   # ∅ poulie motrice (réel : 4160 mm)
@export var pulley_thickness: float = 1.20  # épaisseur hub
@export var pulley_s: float = 11.5          # axe de la poulie motrice
@export var motor_count: int = 3
@export var motor_width: float = 1.10       # largeur boîte moteur
@export var motor_height: float = 1.40
@export var motor_length: float = 2.20
@export var motor_spacing: float = 1.60

var tunnel: TunnelBuilder = null
var _pulley_spin_node: Node3D = null   # poulie motrice (sous terre)
var _sheave_spin_node: Node3D = null   # roue aval (sommet visible)
var _pulley_angle: float = 0.0         # radians accumulés


func _y_ceil() -> float:
	return Y_HALL_FLOOR - 0.30


func _y_floor() -> float:
	return _y_ceil() - room_height


func _y_pulley_center() -> float:
	return _y_floor() + pulley_diameter * 0.5 + 0.60


func build(t: TunnelBuilder) -> void:
	tunnel = t
	_build_hall_end()
	_build_room_shell()
	_build_sheave()
	_build_pulley()
	_build_motors()
	_build_cable()
	_build_lights()


# ---------------------------------------------------------------------------
# Fin de la salle de gare : dalle (avec la fente de la roue aval), parois,
# plafond, néons, et le mur du fond en bardage bois « DESTINATION GLACIER »
# ---------------------------------------------------------------------------

func _build_hall_end() -> void:
	var xform: Transform3D = tunnel.transform_at(PNConstants.LENGTH)
	var slab: StandardMaterial3D = StandardMaterial3D.new()
	slab.albedo_color = Color(0.46, 0.46, 0.45)
	slab.roughness = 0.9
	slab.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dark: StandardMaterial3D = StandardMaterial3D.new()
	dark.albedo_color = Color(0.20, 0.21, 0.23)
	dark.roughness = 0.9
	dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wood: StandardMaterial3D = StandardMaterial3D.new()
	wood.albedo_color = Color(0.58, 0.42, 0.24)
	wood.roughness = 0.75
	wood.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glow: StandardMaterial3D = StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.98, 0.92)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.97, 0.90)
	glow.emission_energy_multiplier = 2.5
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# dalle : deux bandes latérales pleines + bande centrale coupée par la
	# fente de la roue aval
	var y_slab: float = Y_HALL_FLOOR - 0.15
	var side_w: float = HALL_HALF_W - SLOT_HALF_W
	for sx in [-1.0, 1.0]:
		_add_box(Vector3(side_w, 0.30, HALL_DEPTH), slab, xform,
			sx * (SLOT_HALF_W + side_w * 0.5), y_slab, HALL_DEPTH * 0.5, "DalleCote")
	var slot0: float = SHEAVE_S - SHEAVE_R - 0.30
	var slot1: float = SHEAVE_S + SHEAVE_R + 0.30
	_add_box(Vector3(SLOT_HALF_W * 2.0, 0.30, slot0), slab, xform, 0.0, y_slab, slot0 * 0.5, "DalleAvant")
	_add_box(Vector3(SLOT_HALF_W * 2.0, 0.30, HALL_DEPTH - slot1), slab, xform,
		0.0, y_slab, (slot1 + HALL_DEPTH) * 0.5, "DalleArriere")
	# parois de la fente (on voit la roue plonger dans le noir)
	var slot_len: float = slot1 - slot0
	var slot_depth: float = 1.20
	for sx in [-1.0, 1.0]:
		_add_box(Vector3(0.10, slot_depth, slot_len), dark, xform,
			sx * SLOT_HALF_W, Y_HALL_FLOOR - slot_depth * 0.5, (slot0 + slot1) * 0.5, "ParoiFente")
	for ss in [slot0, slot1]:
		_add_box(Vector3(SLOT_HALF_W * 2.0, slot_depth, 0.10), dark, xform,
			0.0, Y_HALL_FLOOR - slot_depth * 0.5, ss, "BoutFente")
	# cornières jaunes de rive
	var yellow: StandardMaterial3D = StandardMaterial3D.new()
	yellow.albedo_color = Color(0.92, 0.78, 0.12)
	yellow.roughness = 0.6
	for sx in [-1.0, 1.0]:
		_add_box(Vector3(0.10, 0.04, slot_len + 0.2), yellow, xform,
			sx * (SLOT_HALF_W + 0.05), Y_HALL_FLOOR + 0.02, (slot0 + slot1) * 0.5, "RiveFente")

	# parois et plafond de la salle de gare, prolongés jusqu'au mur du fond
	var hall_h: float = Y_HALL_CEIL - Y_HALL_FLOOR
	var y_mid: float = (Y_HALL_CEIL + Y_HALL_FLOOR) * 0.5
	for sx in [-1.0, 1.0]:
		_add_box(Vector3(0.30, hall_h, HALL_DEPTH), dark, xform,
			sx * (HALL_HALF_W + 0.15), y_mid, HALL_DEPTH * 0.5, "ParoiSalle")
	_add_box(Vector3(HALL_HALF_W * 2.0 + 0.6, 0.30, HALL_DEPTH), dark, xform,
		0.0, Y_HALL_CEIL + 0.15, HALL_DEPTH * 0.5, "PlafondSalle")
	# mur du fond : bardage bois, deux baies lumineuses vers le hall, enseigne
	_add_box(Vector3(HALL_HALF_W * 2.0 + 0.6, hall_h, 0.30), wood, xform,
		0.0, y_mid, HALL_DEPTH + 0.15, "MurFond")
	for sx in [-1.0, 1.0]:
		_add_box(Vector3(2.0, 1.4, 0.06), glow, xform,
			sx * 3.0, Y_HALL_FLOOR + 1.0, HALL_DEPTH - 0.04, "BaieHall")
	var sign_l: Label3D = Label3D.new()
	sign_l.text = "DESTINATION\nGLACIER"
	sign_l.font_size = 96
	sign_l.pixel_size = 0.006
	sign_l.modulate = Color(1.0, 0.62, 0.12)
	sign_l.outline_modulate = Color(0.5, 0.25, 0.02)
	sign_l.outline_size = 8
	sign_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign_l.shaded = false
	sign_l.double_sided = true
	add_child(sign_l)
	_place_local(sign_l, xform, 0.0, Y_HALL_FLOOR + 3.0, HALL_DEPTH - 0.05)

	# néons sous le plafond de la salle
	var neon_mat: StandardMaterial3D = StandardMaterial3D.new()
	neon_mat.albedo_color = Color(0.98, 0.99, 1.0)
	neon_mat.emission_enabled = true
	neon_mat.emission = Color(0.95, 0.97, 1.0)
	neon_mat.emission_energy_multiplier = 3.0
	neon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for s_pos in [3.0, 7.0]:
		var light: OmniLight3D = OmniLight3D.new()
		light.light_color = Color(0.95, 0.97, 1.0)
		light.light_energy = 3.0
		light.omni_range = 10.0
		light.shadow_enabled = false
		add_child(light)
		_place_local(light, xform, 0.0, Y_HALL_CEIL - 0.4, s_pos)
		_add_box(Vector3(2.4, 0.08, 0.16), neon_mat, xform, 0.0, Y_HALL_CEIL - 0.25, s_pos, "NeonSalle")


# ---------------------------------------------------------------------------
# Coquille de la salle des machines, sous la dalle
# ---------------------------------------------------------------------------

func _build_room_shell() -> void:
	var xform: Transform3D = tunnel.transform_at(PNConstants.LENGTH)
	var concrete_mat: StandardMaterial3D = StandardMaterial3D.new()
	concrete_mat.albedo_color = Color(0.42, 0.40, 0.37)
	concrete_mat.roughness = 0.92
	concrete_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var y_floor: float = _y_floor()
	var y_mid: float = (y_floor + _y_ceil()) * 0.5
	var s_center: float = room_offset_s + room_depth * 0.5
	_add_box(Vector3(room_width, 0.3, room_depth), concrete_mat, xform, 0.0, y_floor, s_center, "Floor")
	_add_box(Vector3(room_width, room_height, 0.3), concrete_mat, xform,
		0.0, y_mid, room_offset_s + room_depth, "WallBack")
	_add_box(Vector3(room_width, room_height, 0.3), concrete_mat, xform,
		0.0, y_mid, room_offset_s, "WallFront")
	for sx in [-1.0, 1.0]:
		_add_box(Vector3(0.3, room_height, room_depth), concrete_mat, xform,
			sx * room_width * 0.5, y_mid, s_center, "WallSide")


# ---------------------------------------------------------------------------
# Roue aval : les deux brins passent sur son sommet et plongent sous la dalle
# ---------------------------------------------------------------------------

func _build_sheave() -> void:
	var xform: Transform3D = tunnel.transform_at(PNConstants.LENGTH)
	var rim_mat: StandardMaterial3D = StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.30, 0.32, 0.36)
	rim_mat.roughness = 0.35
	rim_mat.metallic = 0.85
	var web_mat: StandardMaterial3D = StandardMaterial3D.new()
	web_mat.albedo_color = Color(0.55, 0.16, 0.12)     # flasques rouge minium
	web_mat.roughness = 0.55
	web_mat.metallic = 0.4
	_sheave_spin_node = Node3D.new()
	_sheave_spin_node.name = "SheaveSpin"
	# flasque pleine
	var web: MeshInstance3D = MeshInstance3D.new()
	var wm: CylinderMesh = CylinderMesh.new()
	wm.top_radius = SHEAVE_R - 0.10
	wm.bottom_radius = SHEAVE_R - 0.10
	wm.height = SHEAVE_W * 0.5
	wm.radial_segments = 64
	wm.material = web_mat
	web.mesh = wm
	web.rotation = Vector3(0.0, 0.0, PI * 0.5)
	web.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sheave_spin_node.add_child(web)
	# jante à deux gorges : trois anneaux, un brin entre chaque paire
	for k in range(3):
		var ring: MeshInstance3D = MeshInstance3D.new()
		var rm: CylinderMesh = CylinderMesh.new()
		rm.top_radius = SHEAVE_R
		rm.bottom_radius = SHEAVE_R
		rm.height = 0.10
		rm.radial_segments = 64
		rm.material = rim_mat
		ring.mesh = rm
		ring.position = Vector3(-0.24 + 0.24 * float(k), 0.0, 0.0)
		ring.rotation = Vector3(0.0, 0.0, PI * 0.5)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sheave_spin_node.add_child(ring)
	# rayons, pour voir tourner la roue
	for i in range(8):
		var spoke: MeshInstance3D = MeshInstance3D.new()
		var sm: BoxMesh = BoxMesh.new()
		sm.size = Vector3(SHEAVE_R * 0.9, 0.12, 0.10)
		sm.material = rim_mat
		spoke.mesh = sm
		spoke.rotation = Vector3(0.0, 0.0, float(i) / 8.0 * TAU)
		spoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sheave_spin_node.add_child(spoke)
	add_child(_sheave_spin_node)
	_place_local(_sheave_spin_node, xform, 0.0, Y_BRIN - SHEAVE_R, SHEAVE_S)


# ---------------------------------------------------------------------------
# Poulie motrice ∅ 4160 mm, sous terre
# ---------------------------------------------------------------------------

func _build_pulley() -> void:
	var xform: Transform3D = tunnel.transform_at(PNConstants.LENGTH)
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

	_pulley_spin_node = Node3D.new()
	_pulley_spin_node.name = "PulleySpin"
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
	hub.rotation = Vector3(0.0, 0.0, PI * 0.5)
	_pulley_spin_node.add_child(hub)
	var rim: MeshInstance3D = MeshInstance3D.new()
	var rim_mesh: CylinderMesh = CylinderMesh.new()
	rim_mesh.top_radius = pulley_diameter * 0.50 + 0.04
	rim_mesh.bottom_radius = pulley_diameter * 0.50 + 0.04
	rim_mesh.height = pulley_thickness * 0.25
	rim_mesh.radial_segments = 64
	rim_mesh.material = rim_mat
	rim.mesh = rim_mesh
	rim.rotation = Vector3(0.0, 0.0, PI * 0.5)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pulley_spin_node.add_child(rim)
	var spoke_mat: StandardMaterial3D = StandardMaterial3D.new()
	spoke_mat.albedo_color = Color(0.48, 0.48, 0.52)
	spoke_mat.roughness = 0.35
	spoke_mat.metallic = 0.85
	for i in range(6):
		var spoke: MeshInstance3D = MeshInstance3D.new()
		var spoke_mesh: BoxMesh = BoxMesh.new()
		spoke_mesh.size = Vector3(pulley_diameter * 0.45, 0.15, pulley_thickness * 0.95)
		spoke_mesh.material = spoke_mat
		spoke.mesh = spoke_mesh
		spoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spoke.rotation = Vector3(0.0, 0.0, float(i) / 6.0 * TAU)
		_pulley_spin_node.add_child(spoke)
	var y_c: float = _y_pulley_center()
	add_child(_pulley_spin_node)
	_place_local(_pulley_spin_node, xform, 0.0, y_c, pulley_s)

	# arbre vers les moteurs (à droite) et paliers
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
	_place_local(shaft, xform, 3.0, y_c, pulley_s)
	var y_floor: float = _y_floor()
	for side in [-1.0, 1.0]:
		_add_box(Vector3(0.80, y_c - y_floor + 0.50, 0.80), support_mat, xform,
			side * (pulley_thickness * 0.5 + 0.50), (y_floor + y_c) * 0.5, pulley_s, "Palier")


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
	var y_floor: float = _y_floor()
	var s_first: float = pulley_s - (float(motor_count) - 1.0) * 0.5 * (motor_length + motor_spacing)
	var x_motor: float = 3.5
	var y_motor: float = y_floor + motor_height * 0.5 + 0.05
	for i in range(motor_count):
		var s_pos: float = s_first + float(i) * (motor_length + motor_spacing)
		var body: MeshInstance3D = MeshInstance3D.new()
		var body_mesh: CylinderMesh = CylinderMesh.new()
		body_mesh.top_radius = motor_height * 0.5
		body_mesh.bottom_radius = motor_height * 0.5
		body_mesh.height = motor_length
		body_mesh.radial_segments = 24
		body_mesh.material = motor_mat
		body.mesh = body_mesh
		body.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(body)
		_place_local(body, xform, x_motor, y_motor, s_pos)
		_add_box(Vector3(motor_width * 1.2, 0.15, motor_length * 1.1), cooling_mat, xform,
			x_motor, y_floor + 0.08, s_pos, "SocleMoteur")


# ---------------------------------------------------------------------------
# Câble : voie → sommet de la roue aval → plongée sous la dalle → poulie
# motrice (demi-tour par le dessus) → fond de salle. Un tube par brin.
# ---------------------------------------------------------------------------

func _build_cable() -> void:
	var xform: Transform3D = tunnel.transform_at(PNConstants.LENGTH)
	var cable_mat: StandardMaterial3D = StandardMaterial3D.new()
	cable_mat.albedo_color = Color(0.18, 0.18, 0.20)
	cable_mat.roughness = 0.35
	cable_mat.metallic = 0.95
	cable_mat.emission_enabled = true
	cable_mat.emission = Color(0.10, 0.10, 0.12)
	cable_mat.emission_energy_multiplier = 0.3
	for side in [-1.0, 1.0]:
		_build_strand(cable_mat, xform, 0.12 * side)


func _build_strand(mat: StandardMaterial3D, xform: Transform3D, x: float) -> void:
	var pts: Array = []           # points locaux (x, y, s)
	# 1. voie → sommet de la roue aval
	pts.append(Vector3(x, Y_BRIN, 0.0))
	# 2. quart de tour sur la roue aval, du sommet au flanc arrière
	var y_sc: float = Y_BRIN - SHEAVE_R
	for i in range(1, 13):
		var a: float = float(i) / 12.0 * PI * 0.5
		pts.append(Vector3(x, y_sc + SHEAVE_R * cos(a), SHEAVE_S + SHEAVE_R * sin(a)))
	# 3. plongée verticale jusqu'au niveau des brins de la salle
	var y_c: float = _y_pulley_center()
	var y_room: float = y_c - 1.0
	var r_p: float = pulley_diameter * 0.5
	pts.append(Vector3(x, y_room, SHEAVE_S + SHEAVE_R))
	# 4. vers le point de tangence de la poulie motrice, demi-tour par le
	#    dessus, retour au niveau des brins, fond de salle
	# angle φ compté depuis le sommet : les tangences (y = y_room) sont à
	# φ = ∓(π − θ), côté voie d'abord (s < pulley_s), puis par le sommet
	var theta: float = acos(clampf((y_c - y_room) / r_p, -1.0, 1.0))
	var n_arc: int = 32
	for i in range(0, n_arc + 1):
		var t: float = float(i) / float(n_arc)
		var ang: float = -(PI - theta) + t * 2.0 * (PI - theta)
		pts.append(Vector3(x, y_c + cos(ang) * r_p, pulley_s + sin(ang) * r_p))
	pts.append(Vector3(x, y_room, room_offset_s + room_depth - 0.5))

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	var cable_r: float = 0.026
	var cable_segs: int = 8
	for i in range(pts.size() - 1):
		var c0: Vector3 = _local_to_world(xform, pts[i])
		var c1: Vector3 = _local_to_world(xform, pts[i + 1])
		var tg: Vector3 = (c1 - c0).normalized()
		var r_vec: Vector3 = tg.cross(Vector3.UP).normalized()
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
	mi.name = "CableWrap_%s" % ("L" if x < 0.0 else "R")
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------------------------------------------------------------------------
# Éclairage industriel de la salle (sous terre)
# ---------------------------------------------------------------------------

func _build_lights() -> void:
	var xform: Transform3D = tunnel.transform_at(PNConstants.LENGTH)
	var y_light: float = _y_ceil() - 0.4
	var neon_mat: StandardMaterial3D = StandardMaterial3D.new()
	neon_mat.albedo_color = Color(0.98, 0.99, 1.0)
	neon_mat.emission_enabled = true
	neon_mat.emission = Color(0.95, 0.97, 1.0)
	neon_mat.emission_energy_multiplier = 3.0
	neon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for zz in range(3):
		for xx in range(2):
			var s_pos: float = room_offset_s + 3.5 + float(zz) * 4.0
			var x_pos: float = -3.0 + float(xx) * 6.0
			var light: OmniLight3D = OmniLight3D.new()
			light.light_color = Color(0.95, 0.97, 1.0)
			light.light_energy = 4.0
			light.omni_range = 10.0
			light.shadow_enabled = false
			add_child(light)
			_place_local(light, xform, x_pos, y_light, s_pos)
			_add_box(Vector3(2.4, 0.1, 0.2), neon_mat, xform, x_pos, y_light, s_pos, "NeonSalleMachines")


# ---------------------------------------------------------------------------
# Animation : rotation des roues selon physics.v (appelée depuis main)
# ---------------------------------------------------------------------------

func update_rotation(v_cable: float, delta: float) -> void:
	if _pulley_spin_node == null:
		return
	_pulley_angle += v_cable / (pulley_diameter * 0.5) * delta
	_pulley_spin_node.rotation = Vector3(_pulley_angle, 0.0, 0.0)
	if _sheave_spin_node != null:
		_sheave_spin_node.rotation = Vector3(_pulley_angle * (pulley_diameter * 0.5) / SHEAVE_R, 0.0, 0.0)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _add_box(size: Vector3, mat: StandardMaterial3D, xform: Transform3D,
		ox: float, oy: float, os_s: float, nom: String) -> MeshInstance3D:
	var mi: MeshInstance3D = _box_mesh(size, mat, nom)
	add_child(mi)
	_place_local(mi, xform, ox, oy, os_s)
	return mi


func _box_mesh(size: Vector3, mat: StandardMaterial3D, nom: String) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.name = nom
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# Place un Node3D dans la base locale du repère tunnel à la fin du tunnel.
# ox, oy, os_s sont dans le repère local (right, up, -tangent).
func _place_local(node: Node3D, base_xform: Transform3D, ox: float, oy: float, os_s: float) -> void:
	var right: Vector3 = base_xform.basis.x
	var up: Vector3 = base_xform.basis.y
	var tangent: Vector3 = -base_xform.basis.z
	var t: Transform3D = base_xform
	t.origin = base_xform.origin + right * ox + up * oy + tangent * os_s
	node.transform = t


func _local_to_world(base_xform: Transform3D, local: Vector3) -> Vector3:
	var right: Vector3 = base_xform.basis.x
	var up: Vector3 = base_xform.basis.y
	var tangent: Vector3 = -base_xform.basis.z
	return base_xform.origin + right * local.x + up * local.y + tangent * local.z
