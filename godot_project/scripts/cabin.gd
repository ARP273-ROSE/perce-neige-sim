class_name Cabin
extends Node3D
## Cabine du funiculaire — cylindre jaune MVP, deux voitures couplées.
## Se positionne sur la spline via TunnelBuilder.transform_at(s).

@export var train_length: float = 32.0      # 2 × 16 m
@export var train_radius: float = 1.70      # ∅ 3.60 m - clearance
@export var car_count: int = 2

var tunnel: TunnelBuilder = null
var physics: TrainPhysics = null

# Noeuds internes
var mesh_root: Node3D = null         # coque extérieure (masquée en FPV)
var interior_root: Node3D = null     # cockpit + sièges + passagers (toujours visibles)
var headlight_front: SpotLight3D = null
var headlight_rear: SpotLight3D = null
var camera_fpv: Camera3D = null
var camera_ext: Camera3D = null
var interior_light: OmniLight3D = null

# Labels dynamiques affichés sur les écrans du dashboard (mis à jour chaque frame)
var _label_speed: Label3D = null
var _label_tension: Label3D = null
var _label_power: Label3D = null

# Passagers — références pour animer les têtes selon l'accel/courbure
var _passenger_heads: Array = []   # Array[MeshInstance3D]
var _passenger_torsos: Array = []  # Array[MeshInstance3D]
var _prev_v_for_acc: float = 0.0   # vitesse à la frame précédente pour calcul accel

enum ViewMode { FPV, EXTERIOR }
var view_mode: int = ViewMode.FPV

# Mode ghost : rame 2 (pas de caméra, mesh visible, offset latéral passing loop)
# side = -1 pour rame 1 (voie gauche au passing loop), +1 pour rame 2 ghost
@export var is_ghost: bool = false
@export var passing_side: float = -1.0


func _ready() -> void:
	_build_mesh()
	if not is_ghost:
		_build_lights()
		_build_camera()
		# En vue FPV, masquer la cabine elle-même — on est DEDANS.
		# En vue extérieure, on la montre.
		_apply_view_mode()
	else:
		# Ghost : mesh toujours visible, pas de caméra ni phares
		mesh_root.visible = true
		# Petit feu arrière rouge pour que le ghost soit identifiable de loin
		var rear: OmniLight3D = OmniLight3D.new()
		rear.light_color = Color(1.0, 0.25, 0.15)
		rear.light_energy = 1.8
		rear.omni_range = 12.0
		rear.shadow_enabled = false
		rear.position = Vector3(0.0, 0.25, 0.0)
		add_child(rear)


func _build_mesh() -> void:
	mesh_root = Node3D.new()
	mesh_root.name = "MeshRoot"
	add_child(mesh_root)

	# Cabines : 2 cylindres couplés, jaune Perce-Neige
	var cabin_mat: StandardMaterial3D = StandardMaterial3D.new()
	cabin_mat.albedo_color = Color(0.95, 0.75, 0.10)
	cabin_mat.roughness = 0.35
	cabin_mat.metallic = 0.3
	cabin_mat.metallic_specular = 0.6

	var window_mat: StandardMaterial3D = StandardMaterial3D.new()
	window_mat.albedo_color = Color(0.08, 0.12, 0.18, 0.7)
	window_mat.roughness = 0.05
	window_mat.metallic = 0.0
	window_mat.emission_enabled = true
	window_mat.emission = Color(0.15, 0.20, 0.30)
	window_mat.emission_energy_multiplier = 0.5
	window_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var car_length: float = train_length / float(car_count)
	for i in range(car_count):
		var car: MeshInstance3D = MeshInstance3D.new()
		car.name = "Car%d" % (i + 1)
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = train_radius
		cyl.bottom_radius = train_radius
		cyl.height = car_length * 0.96
		cyl.radial_segments = 24
		cyl.rings = 1
		car.mesh = cyl
		car.set_surface_override_material(0, cabin_mat)
		# Positionner le long de -Z (forward Godot)
		var center_offset: float = (float(i) - (car_count - 1) * 0.5) * car_length
		car.position = Vector3(0.0, 0.0, center_offset)
		# Orientation : cylindre axe Y → on veut axe Z (forward)
		car.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		mesh_root.add_child(car)

		# Fenêtres — bande latérale à mi-hauteur
		for side in [-1.0, 1.0]:
			var window_strip: MeshInstance3D = MeshInstance3D.new()
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(0.05, 1.1, car_length * 0.75)
			window_strip.mesh = box
			window_strip.set_surface_override_material(0, window_mat)
			window_strip.position = Vector3(side * (train_radius + 0.01), 0.3, center_offset)
			mesh_root.add_child(window_strip)

	# --- Intérieur cockpit + sièges + passagers — toujours visible ---------
	if not is_ghost:
		_build_interior()


# ---------------------------------------------------------------------------
# Intérieur cabine — dashboard cockpit, sièges, passagers
# Toujours visible (en FPV on regarde l'intérieur, en EXT la coque cache)
# ---------------------------------------------------------------------------

func _build_interior() -> void:
	interior_root = Node3D.new()
	interior_root.name = "Interior"
	add_child(interior_root)
	_build_floor_ceiling()
	# Pas de dashboard 3D (était moche et obstruait la vue) → tout passe en HUD
	_build_driver_seat()
	_build_passenger_seats()
	_build_passengers()
	_build_handrails()


func _build_floor_ceiling() -> void:
	# Sol cabine — visible depuis FPV (sous les sièges, dans l'aisle)
	var floor_mat: StandardMaterial3D = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.22, 0.22, 0.25)
	floor_mat.roughness = 0.65
	floor_mat.uv1_scale = Vector3(8.0, 16.0, 1.0)

	var floor_mesh: BoxMesh = BoxMesh.new()
	floor_mesh.size = Vector3(2.40, 0.05, train_length * 0.97)
	floor_mesh.material = floor_mat
	var floor_node: MeshInstance3D = MeshInstance3D.new()
	floor_node.name = "InteriorFloor"
	floor_node.mesh = floor_mesh
	floor_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	floor_node.position = Vector3(0.0, -1.05, 0.0)   # juste au-dessus du slab
	interior_root.add_child(floor_node)

	# Plafond cabine — surface plate visible quand on lève les yeux
	var ceil_mat: StandardMaterial3D = StandardMaterial3D.new()
	ceil_mat.albedo_color = Color(0.92, 0.90, 0.85)
	ceil_mat.roughness = 0.70
	ceil_mat.metallic = 0.15

	var ceil_mesh: BoxMesh = BoxMesh.new()
	ceil_mesh.size = Vector3(2.40, 0.04, train_length * 0.97)
	ceil_mesh.material = ceil_mat
	var ceil_node: MeshInstance3D = MeshInstance3D.new()
	ceil_node.name = "InteriorCeiling"
	ceil_node.mesh = ceil_mesh
	ceil_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ceil_node.position = Vector3(0.0, 1.45, 0.0)
	interior_root.add_child(ceil_node)

	# Bandeau LED plafond (lumineux) le long du milieu, donne le côté "métro moderne"
	var led_mat: StandardMaterial3D = StandardMaterial3D.new()
	led_mat.albedo_color = Color(0.98, 0.99, 1.0)
	led_mat.emission_enabled = true
	led_mat.emission = Color(0.92, 0.96, 1.0)
	led_mat.emission_energy_multiplier = 1.6
	led_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var led_mesh: BoxMesh = BoxMesh.new()
	led_mesh.size = Vector3(0.25, 0.04, train_length * 0.92)
	led_mesh.material = led_mat
	var led_node: MeshInstance3D = MeshInstance3D.new()
	led_node.name = "InteriorLEDStrip"
	led_node.mesh = led_mesh
	led_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	led_node.position = Vector3(0.0, 1.42, 0.0)
	interior_root.add_child(led_node)


func _build_handrails() -> void:
	# Mains courantes verticales (poteaux entre les rangées) + horizontales (au plafond)
	var rail_mat: StandardMaterial3D = StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.85, 0.85, 0.88)
	rail_mat.roughness = 0.25
	rail_mat.metallic = 0.85
	rail_mat.metallic_specular = 0.95

	# 2 mains courantes horizontales le long du plafond, à x=±0.35 (au-dessus de l'aisle)
	for side in [-1.0, 1.0]:
		var rail: MeshInstance3D = MeshInstance3D.new()
		var rail_mesh: CylinderMesh = CylinderMesh.new()
		rail_mesh.top_radius = 0.025
		rail_mesh.bottom_radius = 0.025
		rail_mesh.height = train_length * 0.85
		rail_mesh.radial_segments = 10
		rail_mesh.material = rail_mat
		rail.mesh = rail_mesh
		rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rail.position = Vector3(side * 0.35, 1.30, 0.0)
		# Cylindre axe Y → on veut axe Z (le long de la voie)
		rail.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		interior_root.add_child(rail)

	# Poteaux verticaux : 6 dans chaque car (1 entre chaque paire de rangées)
	# Positionnés au milieu de l'aisle (x=0)
	var car_length: float = train_length / float(car_count)
	for car_idx in range(car_count):
		var car_center: float = (float(car_idx) - (car_count - 1) * 0.5) * car_length
		var z_start: float = car_center - car_length * 0.5 + (5.5 if car_idx == 0 else 1.8)
		var z_end: float = car_center + car_length * 0.5 - 1.8
		var n_poles: int = 5
		for pole_idx in range(n_poles):
			var t: float = float(pole_idx) / float(n_poles - 1)
			var z_pole: float = lerpf(z_start, z_end, t)
			var pole: MeshInstance3D = MeshInstance3D.new()
			var pole_mesh: CylinderMesh = CylinderMesh.new()
			pole_mesh.top_radius = 0.020
			pole_mesh.bottom_radius = 0.020
			pole_mesh.height = 2.40
			pole_mesh.radial_segments = 10
			pole_mesh.material = rail_mat
			pole.mesh = pole_mesh
			pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pole.position = Vector3(0.0, 0.20, z_pole)
			interior_root.add_child(pole)


func _build_dashboard() -> void:
	# Cockpit du conducteur, à l'AVANT du car 1 (caméra FPV à z=-12, y=0.85).
	# IMPORTANT : le dashboard doit rester SOUS l'horizon du regard pour ne
	# pas masquer la vue du tunnel devant. Top du dashboard à y≈0.55, bien
	# en dessous des yeux du conducteur.
	var z_dash: float = -train_length * 0.5 + 2.5   # = -13.5 (1.5m devant caméra)

	var dash_mat: StandardMaterial3D = StandardMaterial3D.new()
	dash_mat.albedo_color = Color(0.10, 0.10, 0.12)
	dash_mat.roughness = 0.45
	dash_mat.metallic = 0.4

	var screen_mat: StandardMaterial3D = StandardMaterial3D.new()
	screen_mat.albedo_color = Color(0.05, 0.25, 0.10)
	screen_mat.emission_enabled = true
	screen_mat.emission = Color(0.15, 0.65, 0.25)
	screen_mat.emission_energy_multiplier = 1.0
	screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var amber_mat: StandardMaterial3D = StandardMaterial3D.new()
	amber_mat.albedo_color = Color(0.25, 0.15, 0.05)
	amber_mat.emission_enabled = true
	amber_mat.emission = Color(0.85, 0.50, 0.10)
	amber_mat.emission_energy_multiplier = 0.9
	amber_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var red_mat: StandardMaterial3D = StandardMaterial3D.new()
	red_mat.albedo_color = Color(0.30, 0.05, 0.05)
	red_mat.emission_enabled = true
	red_mat.emission = Color(0.95, 0.20, 0.18)
	red_mat.emission_energy_multiplier = 1.4
	red_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Corps dashboard (caisson) — top à y=0.55 (bien sous l'horizon du regard à 0.85)
	var dash_body: MeshInstance3D = MeshInstance3D.new()
	dash_body.name = "DashboardBody"
	var dash_mesh: BoxMesh = BoxMesh.new()
	dash_mesh.size = Vector3(1.80, 0.45, 0.40)
	dash_mesh.material = dash_mat
	dash_body.mesh = dash_mesh
	dash_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dash_body.position = Vector3(0.0, 0.30, z_dash)   # centre y=0.30 → top y=0.525
	interior_root.add_child(dash_body)

	# Tableau de bord supérieur incliné vers le conducteur (lecture en regardant en bas)
	var dash_top: MeshInstance3D = MeshInstance3D.new()
	dash_top.name = "DashboardTop"
	var top_mesh: BoxMesh = BoxMesh.new()
	top_mesh.size = Vector3(1.80, 0.03, 0.42)
	top_mesh.material = dash_mat
	dash_top.mesh = top_mesh
	dash_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dash_top.position = Vector3(0.0, 0.53, z_dash + 0.05)
	dash_top.rotation = Vector3(-0.30, 0.0, 0.0)
	interior_root.add_child(dash_top)

	# Vitesse (écran vert, à gauche) — sur le top incliné
	var s_h: float = 0.13   # demi-hauteur écran
	var screen_y: float = 0.55
	var screen_z: float = z_dash + 0.22
	var speedo: MeshInstance3D = MeshInstance3D.new()
	speedo.name = "Speedometer"
	var s_mesh: BoxMesh = BoxMesh.new()
	s_mesh.size = Vector3(0.26, s_h, 0.005)
	s_mesh.material = screen_mat
	speedo.mesh = s_mesh
	speedo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	speedo.position = Vector3(-0.45, screen_y, screen_z)
	speedo.rotation = Vector3(-0.30, 0.0, 0.0)
	interior_root.add_child(speedo)

	# Tension câble (jauge ambre, milieu)
	var tension: MeshInstance3D = MeshInstance3D.new()
	tension.name = "TensionGauge"
	var t_mesh: BoxMesh = BoxMesh.new()
	t_mesh.size = Vector3(0.20, s_h, 0.005)
	t_mesh.material = amber_mat
	tension.mesh = t_mesh
	tension.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tension.position = Vector3(0.0, screen_y, screen_z)
	tension.rotation = Vector3(-0.30, 0.0, 0.0)
	interior_root.add_child(tension)

	# Puissance moteur (écran vert, à droite)
	var power: MeshInstance3D = MeshInstance3D.new()
	power.name = "PowerGauge"
	var p_mesh: BoxMesh = BoxMesh.new()
	p_mesh.size = Vector3(0.26, s_h, 0.005)
	p_mesh.material = screen_mat
	power.mesh = p_mesh
	power.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	power.position = Vector3(+0.45, screen_y, screen_z)
	power.rotation = Vector3(-0.30, 0.0, 0.0)
	interior_root.add_child(power)

	# Labels dynamiques sur les écrans (depth-test ON, taille petite, lecture
	# en baissant les yeux comme un vrai cockpit)
	_label_speed = _make_dash_label(Vector3(-0.45, screen_y + 0.005, screen_z + 0.005), "0", Color(0.55, 1.0, 0.65))
	_label_tension = _make_dash_label(Vector3(0.0, screen_y + 0.005, screen_z + 0.005), "0", Color(1.0, 0.80, 0.45))
	_label_power = _make_dash_label(Vector3(+0.45, screen_y + 0.005, screen_z + 0.005), "0", Color(0.55, 1.0, 0.65))

	# Voyants alarme (rangée de 4 LED rouges sur la face avant du dashboard)
	for i in range(4):
		var led: MeshInstance3D = MeshInstance3D.new()
		var led_mesh: SphereMesh = SphereMesh.new()
		led_mesh.radius = 0.020
		led_mesh.height = 0.04
		led_mesh.material = red_mat
		led.mesh = led_mesh
		led.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		led.position = Vector3(-0.6 + float(i) * 0.4, 0.18, z_dash + 0.21)
		interior_root.add_child(led)

	# Volant / poignée de commande, plus bas pour ne pas obstruer
	var wheel: MeshInstance3D = MeshInstance3D.new()
	wheel.name = "ControlWheel"
	var wheel_mesh: TorusMesh = TorusMesh.new()
	wheel_mesh.inner_radius = 0.13
	wheel_mesh.outer_radius = 0.16
	wheel_mesh.material = dash_mat
	wheel.mesh = wheel_mesh
	wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wheel.position = Vector3(0.0, 0.20, z_dash + 0.28)
	wheel.rotation = Vector3(PI * 0.5 - 0.30, 0.0, 0.0)
	interior_root.add_child(wheel)


func _make_dash_label(pos: Vector3, txt: String, col: Color) -> Label3D:
	var lbl: Label3D = Label3D.new()
	lbl.text = txt
	lbl.font_size = 80
	lbl.pixel_size = 0.0025
	lbl.modulate = col
	lbl.outline_size = 0
	lbl.shaded = false
	lbl.double_sided = true
	lbl.no_depth_test = true
	lbl.position = pos
	lbl.rotation = Vector3(-0.25, 0.0, 0.0)
	interior_root.add_child(lbl)
	return lbl


func _build_driver_seat() -> void:
	# Siège du conducteur, derrière le dashboard
	var z_seat: float = -train_length * 0.5 + 4.5   # = -11.5

	var seat_mat: StandardMaterial3D = StandardMaterial3D.new()
	seat_mat.albedo_color = Color(0.18, 0.18, 0.22)
	seat_mat.roughness = 0.85
	seat_mat.metallic = 0.0

	# Assise
	var base: MeshInstance3D = MeshInstance3D.new()
	base.name = "DriverSeatBase"
	var base_mesh: BoxMesh = BoxMesh.new()
	base_mesh.size = Vector3(0.55, 0.10, 0.55)
	base_mesh.material = seat_mat
	base.mesh = base_mesh
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	base.position = Vector3(0.0, 0.50, z_seat)
	interior_root.add_child(base)

	# Dossier
	var back: MeshInstance3D = MeshInstance3D.new()
	back.name = "DriverSeatBack"
	var back_mesh: BoxMesh = BoxMesh.new()
	back_mesh.size = Vector3(0.55, 0.85, 0.10)
	back_mesh.material = seat_mat
	back.mesh = back_mesh
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	back.position = Vector3(0.0, 0.95, z_seat + 0.30)
	interior_root.add_child(back)


func _build_passenger_seats() -> void:
	# Sièges passagers : rangées de 2 sièges (1 par côté), aisle au milieu.
	# 8 rangées par car, espacées de ~1.6m → couvre la zone passagers
	var seat_mat: StandardMaterial3D = StandardMaterial3D.new()
	seat_mat.albedo_color = Color(0.55, 0.10, 0.10)   # rouge sombre pour contraste
	seat_mat.roughness = 0.90
	seat_mat.metallic = 0.0

	var car_length: float = train_length / float(car_count)
	for car_idx in range(car_count):
		var car_center: float = (float(car_idx) - (car_count - 1) * 0.5) * car_length
		# Zone passagers : skip les 4m près du nez (cockpit) pour le car avant
		var z_start: float = car_center - car_length * 0.5 + (4.5 if car_idx == 0 else 1.0)
		var z_end: float = car_center + car_length * 0.5 - 1.0
		var n_rows: int = 8
		for row_idx in range(n_rows):
			var t: float = float(row_idx) / float(n_rows - 1)
			var z_row: float = lerpf(z_start, z_end, t)
			for side in [-1.0, 1.0]:
				_emit_seat(seat_mat, side * 0.85, z_row)


func _emit_seat(mat: StandardMaterial3D, x: float, z: float) -> void:
	# 1 siège : assise + dossier
	var base: MeshInstance3D = MeshInstance3D.new()
	var base_mesh: BoxMesh = BoxMesh.new()
	base_mesh.size = Vector3(0.50, 0.08, 0.45)
	base_mesh.material = mat
	base.mesh = base_mesh
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	base.position = Vector3(x, 0.45, z)
	interior_root.add_child(base)

	var back: MeshInstance3D = MeshInstance3D.new()
	var back_mesh: BoxMesh = BoxMesh.new()
	back_mesh.size = Vector3(0.50, 0.70, 0.08)
	back_mesh.material = mat
	back.mesh = back_mesh
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	back.position = Vector3(x, 0.85, z + 0.20)
	interior_root.add_child(back)


func _build_passengers() -> void:
	# Quelques passagers stylisés (boxes torse + cylindre tête).
	# Distribution clairsemée pour ne pas surcharger la scène.
	var skin_mat: StandardMaterial3D = StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.85, 0.70, 0.55)
	skin_mat.roughness = 0.85

	# Manteaux d'hiver — couleurs variées (pour qu'on les distingue)
	var coat_colors: Array = [
		Color(0.20, 0.30, 0.55),  # bleu
		Color(0.55, 0.20, 0.20),  # rouge
		Color(0.15, 0.40, 0.25),  # vert
		Color(0.45, 0.30, 0.15),  # marron
		Color(0.30, 0.30, 0.35),  # gris
		Color(0.55, 0.40, 0.10),  # ocre
	]

	# 12 passagers répartis dans les 2 voitures, certains assis certains debout
	# Format : [x, z, sitting (true) ou standing (false), color_index]
	var passengers: Array = [
		[-0.85, -7.0, true,  0],  # car avant : 4 assis
		[+0.85, -7.0, true,  1],
		[-0.85, -3.5, true,  2],
		[+0.85, -3.5, true,  3],
		[-0.6,  -1.0, false, 4],  # debout dans aisle
		[+0.5,   2.0, false, 5],
		[-0.85,  4.0, true,  0],  # car arrière : assis
		[+0.85,  4.0, true,  1],
		[-0.85,  7.5, true,  2],
		[+0.85,  7.5, true,  3],
		[+0.4,  10.5, false, 4],  # debout
		[-0.6,  13.0, false, 5],
	]

	for p in passengers:
		var x: float = p[0]
		var z: float = p[1]
		var sitting: bool = p[2]
		var color: Color = coat_colors[p[3]]
		_emit_passenger(skin_mat, color, x, z, sitting)


func _emit_passenger(skin_mat: StandardMaterial3D, coat_color: Color, x: float, z: float, sitting: bool) -> void:
	var coat_mat: StandardMaterial3D = StandardMaterial3D.new()
	coat_mat.albedo_color = coat_color
	coat_mat.roughness = 0.92

	var y_torso: float
	var torso_h: float
	if sitting:
		y_torso = 0.95   # assis sur le siège (siège à y=0.45 + 0.50 jusqu'aux épaules)
		torso_h = 0.55
	else:
		y_torso = 1.05   # debout
		torso_h = 0.75

	# Torse
	var torso: MeshInstance3D = MeshInstance3D.new()
	var torso_mesh: BoxMesh = BoxMesh.new()
	torso_mesh.size = Vector3(0.45, torso_h, 0.30)
	torso_mesh.material = coat_mat
	torso.mesh = torso_mesh
	torso.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	torso.position = Vector3(x, y_torso, z)
	interior_root.add_child(torso)
	_passenger_torsos.append(torso)

	# Tête
	var head: MeshInstance3D = MeshInstance3D.new()
	var head_mesh: SphereMesh = SphereMesh.new()
	head_mesh.radius = 0.115
	head_mesh.height = 0.23
	head_mesh.material = skin_mat
	head.mesh = head_mesh
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.position = Vector3(x, y_torso + torso_h * 0.5 + 0.13, z)
	interior_root.add_child(head)
	_passenger_heads.append(head)


func _build_lights() -> void:
	# Phares frontaux (forward = -Z dans Godot) — placés DEVANT la caméra
	# pour que le cône soit visible dans le brouillard volumétrique
	headlight_front = SpotLight3D.new()
	headlight_front.name = "HeadlightFront"
	headlight_front.position = Vector3(0.0, 0.70, -train_length * 0.5 + 0.3)
	headlight_front.rotation = Vector3(0.0, 0.0, 0.0)
	headlight_front.light_color = Color(1.0, 0.95, 0.80)
	headlight_front.light_energy = 14.0
	headlight_front.spot_range = 280.0
	headlight_front.spot_angle = 38.0
	headlight_front.spot_angle_attenuation = 0.5
	headlight_front.spot_attenuation = 0.4
	headlight_front.shadow_enabled = false
	headlight_front.visible = true  # allumés par défaut
	add_child(headlight_front)

	# Phares arrière (positon = +Z, look toward +Z)
	headlight_rear = SpotLight3D.new()
	headlight_rear.name = "HeadlightRear"
	headlight_rear.position = Vector3(0.0, 0.2, train_length * 0.5 + 0.2)
	headlight_rear.rotation = Vector3(0.0, PI, 0.0)
	headlight_rear.light_color = Color(1.0, 0.30, 0.20)
	headlight_rear.light_energy = 3.0
	headlight_rear.spot_range = 80.0
	headlight_rear.spot_angle = 45.0
	headlight_rear.shadow_enabled = false
	headlight_rear.visible = true
	add_child(headlight_rear)

	# Lumière cabine intérieure (ambient jaune chaud)
	interior_light = OmniLight3D.new()
	interior_light.name = "InteriorLight"
	interior_light.position = Vector3(0.0, 0.3, 0.0)
	interior_light.light_color = Color(1.0, 0.88, 0.65)
	interior_light.light_energy = 1.2
	interior_light.omni_range = 15.0
	interior_light.shadow_enabled = false
	interior_light.visible = true
	add_child(interior_light)


func _build_camera() -> void:
	# Caméra 1ère personne — position driver dans la zone cockpit
	camera_fpv = Camera3D.new()
	camera_fpv.name = "CameraFPV"
	camera_fpv.fov = 72.0
	camera_fpv.near = 0.05
	camera_fpv.far = 800.0
	camera_fpv.position = Vector3(0.0, 0.85, -train_length * 0.5 + 4.0)
	camera_fpv.rotation = Vector3(0.0, 0.0, 0.0)
	add_child(camera_fpv)

	# Caméra extérieure — orbitale derrière et au-dessus du train
	camera_ext = Camera3D.new()
	camera_ext.name = "CameraExt"
	camera_ext.fov = 60.0
	camera_ext.near = 0.1
	camera_ext.far = 1500.0
	# 25m derrière le train (en montée = vers Val Claret) + 10m au-dessus
	camera_ext.position = Vector3(3.0, 10.0, 25.0)
	camera_ext.look_at_from_position(
		Vector3(3.0, 10.0, 25.0),
		Vector3(0.0, 0.0, 0.0),
		Vector3.UP
	)
	add_child(camera_ext)

	camera_fpv.make_current()


func _apply_view_mode() -> void:
	if view_mode == ViewMode.FPV:
		mesh_root.visible = false
		camera_fpv.make_current()
	else:
		mesh_root.visible = true
		camera_ext.make_current()


func toggle_view() -> void:
	view_mode = (view_mode + 1) % 2
	_apply_view_mode()
	print("[View] %s" % ["FPV cockpit" if view_mode == ViewMode.FPV else "EXTERIOR orbital"])


func set_tunnel(t: TunnelBuilder) -> void:
	tunnel = t


func set_physics(p: TrainPhysics) -> void:
	physics = p


func _process(_delta: float) -> void:
	if tunnel == null or physics == null:
		return
	# Position le long de la spline : rame 1 à physics.s, rame 2 (ghost) à LENGTH - physics.s
	var s_pos: float
	if is_ghost:
		s_pos = PNConstants.LENGTH - physics.s
	else:
		s_pos = physics.s

	# IMPORTANT : la cabine doit suivre l'orientation de SA trajectoire, pas celle
	# de l'axe central du tunnel. Dans le passing loop, le déport latéral ajoute
	# une composante tangentielle qui fait tourner la trajectoire. Si on utilisait
	# tunnel.transform_at(s).basis, le nez de la cabine resterait pointé selon la
	# centerline et taperait dans le mur du tube en transition.
	#
	# On échantillonne donc la position MONDE de la cabine à s, s+eps et s-eps
	# (en incluant l'offset latéral à chaque échantillon) pour calculer la
	# tangente réelle de sa trajectoire.
	var eps: float = 1.5
	var s_prev: float = maxf(s_pos - eps, 0.0)
	var s_next: float = minf(s_pos + eps, PNConstants.LENGTH)
	var pos_cur: Vector3 = _cabin_world_pos(s_pos)
	var pos_prev: Vector3 = _cabin_world_pos(s_prev)
	var pos_next: Vector3 = _cabin_world_pos(s_next)
	var trajectory_tangent: Vector3 = (pos_next - pos_prev).normalized()
	if trajectory_tangent.length() < 0.5:
		trajectory_tangent = Vector3.FORWARD

	var world_up: Vector3 = Vector3.UP
	var right: Vector3 = trajectory_tangent.cross(world_up).normalized()
	if right.length() < 0.01:
		right = Vector3.RIGHT
	var up: Vector3 = right.cross(trajectory_tangent).normalized()

	var xform: Transform3D = Transform3D()
	# Convention du projet : forward = -Z, donc basis.z = -tangent
	xform.basis = Basis(right, up, -trajectory_tangent)
	xform.origin = pos_cur

	# Cabine reste centrée verticalement (rails au fond, plancher au-dessus)
	xform.origin += xform.basis.y * (-0.15)

	# Ghost : orientation opposée (rame 2 va dans le sens -tangent quand rame 1 monte)
	# Rame 1 : orientation suivant physics.direction
	if is_ghost:
		if physics.direction > 0:
			xform.basis = xform.basis.rotated(xform.basis.y, PI)
	else:
		if physics.direction < 0:
			xform.basis = xform.basis.rotated(xform.basis.y, PI)
	global_transform = xform

	# Update des écrans dashboard (FPV)
	_update_dashboard_screens()
	# Animation des passagers selon dynamique
	_animate_passengers(_delta)
	# Sync des lumières depuis physics (drives by Python sim in client mode)
	if not is_ghost:
		if headlight_front != null:
			headlight_front.visible = physics.lights_head
		if headlight_rear != null:
			# Feu arrière toujours allumé en marche, éteint à l'arrêt complet
			headlight_rear.visible = absf(physics.v) > 0.1
		if interior_light != null:
			interior_light.visible = physics.lights_cabin


func _animate_passengers(delta: float) -> void:
	if is_ghost or _passenger_heads.is_empty():
		return
	# Accel longitudinale (m/s²) — freinage = négatif, accel = positif
	var dv: float = physics.v - _prev_v_for_acc
	var acc_long: float = 0.0
	if delta > 0.001:
		acc_long = dv / delta
	_prev_v_for_acc = physics.v

	# Accel latérale dans le passing loop ou virages : approx via courbure horizontale
	var heading_rate_rad_m: float = deg_to_rad(
		SlopeProfile.heading_at(physics.s + 5.0) - SlopeProfile.heading_at(physics.s - 5.0)
	) / 10.0
	var v2: float = physics.v * physics.v
	var acc_lat: float = v2 * heading_rate_rad_m   # m/s², signed

	# Conversion en angles d'inclinaison (proportionnels, plafonnés)
	# Forward accel positive → tête PAR-DEVANT plus inclinée (passagers ballotés vers l'arrière)
	#   en cabine local, "vers arrière" = +Z ; pour pencher la tête vers l'arrière : rotation autour de X positif
	var pitch: float = clampf(-acc_long * 0.06, -0.20, 0.20)
	# Lateral acc positive (right turn) → tête tilte vers la GAUCHE (extérieur du virage)
	# rotation autour de Z négative
	var roll: float = clampf(-acc_lat * 0.05, -0.18, 0.18)

	for head in _passenger_heads:
		if head != null:
			head.rotation = Vector3(pitch, 0.0, roll)
	# Léger sway des torses (moins amplitude que la tête)
	for torso in _passenger_torsos:
		if torso != null:
			torso.rotation = Vector3(pitch * 0.4, 0.0, roll * 0.4)


func _update_dashboard_screens() -> void:
	if _label_speed == null or physics == null or is_ghost:
		return
	var v_kmh: float = absf(physics.v) * 3.6
	_label_speed.text = "%.0f" % v_kmh
	_label_tension.text = "%.0f" % physics.tension_dan_disp
	_label_power.text = "%.0f" % physics.power_kw_disp


# Position monde de la cabine à la distance s, en tenant compte du déport
# latéral du passing loop (passing_side fixe la voie gauche/droite).
func _cabin_world_pos(s: float) -> Vector3:
	var xf: Transform3D = tunnel.transform_at(s)
	var lat: float = tunnel.passing_loop_offset(s, passing_side)
	return xf.origin + xf.basis.x * lat


func set_headlights(on: bool) -> void:
	if headlight_front:
		headlight_front.visible = on


func set_interior_lights(on: bool) -> void:
	if interior_light:
		interior_light.visible = on
