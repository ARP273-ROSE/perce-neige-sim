class_name StationHalls
extends Node3D
## Bâtiments de gare aux 2 portails du tunnel.
##
## - Val Claret (s=0) : hall béton avec escaliers/escalator menant vers la
##   surface (village Val Claret 2111m). Lumière du jour visible au sommet.
## - Grande Motte (s=LENGTH) : hall similaire avec sortie vers le glacier
##   (3032m, sommet du téléphérique de la Grande Motte).
##
## Construit en boîtes (SurfaceTool) ancrées au transform du portail tunnel,
## avec éclairage, signalétique, bancs et quelques passagers en attente.

# Dimensions du hall (en mètres)
@export var hall_width: float = 14.0          # largeur (perpendiculaire à la voie)
@export var hall_length: float = 28.0         # longueur (parallèle à la voie, partant du portail)
@export var hall_height: float = 5.5          # hauteur sous plafond
@export var hall_floor_offset: float = -1.10  # niveau du sol par rapport à l'axe tunnel
@export var exit_shaft_radius: float = 2.5    # rayon de la cage d'escalier vers la surface
@export var exit_shaft_height: float = 12.0   # hauteur escalier vers surface

var tunnel: TunnelBuilder = null
var lang: String = "fr"


func build(t: TunnelBuilder) -> void:
	tunnel = t
	_detect_lang()
	_build_hall_low()
	_build_hall_high()


func _detect_lang() -> void:
	var loc: String = OS.get_locale().to_lower()
	lang = "fr" if loc.begins_with("fr") else "en"


func _t(en: String, fr: String) -> String:
	return fr if lang == "fr" else en


# ---------------------------------------------------------------------------
# Val Claret — hall bas
# ---------------------------------------------------------------------------

func _build_hall_low() -> void:
	# Anchor : portail bas (s=0). Le hall s'étend dans la direction opposée
	# au tangent (= +basis.z, "derrière" le sens de marche).
	var anchor: Transform3D = tunnel.transform_at(0.0)
	# basis.z dans notre convention = -tangent → +basis.z pointe vers s négatif
	# (= vers l'arrière du portail bas, où se trouve l'entrée Val Claret)
	_build_hall(
		anchor, +1.0,
		"VAL CLARET",
		_t("ALTITUDE 2111 m", "ALTITUDE 2111 m"),
		_t("EXIT TO VILLAGE ↑", "SORTIE VILLAGE ↑"),
		Color(0.85, 0.92, 1.00),  # teinte bleue (lumière jour)
		"hall_low",
	)


# ---------------------------------------------------------------------------
# Grande Motte — hall haut
# ---------------------------------------------------------------------------

func _build_hall_high() -> void:
	# Anchor : portail haut (s=LENGTH). Le hall s'étend dans la direction du
	# tangent (= -basis.z), "devant" le sens de marche.
	var anchor: Transform3D = tunnel.transform_at(PNConstants.LENGTH)
	_build_hall(
		anchor, -1.0,
		"GRANDE MOTTE",
		_t("GLACIER 3032 m", "GLACIER 3032 m"),
		_t("EXIT TO GLACIER ↑", "SORTIE GLACIER ↑"),
		Color(0.95, 0.97, 1.00),  # teinte plus blanche (neige glacier)
		"hall_high",
	)


# ---------------------------------------------------------------------------
# Construction d'un hall générique
# direction = +1 → hall s'étend en +basis.z (arrière)
# direction = -1 → hall s'étend en -basis.z (avant)
# ---------------------------------------------------------------------------

func _build_hall(
	anchor: Transform3D, direction: float, name_txt: String, alt_txt: String,
	exit_txt: String, sky_tint: Color, name: String,
) -> void:
	var origin: Vector3 = anchor.origin
	var right: Vector3 = anchor.basis.x
	var up: Vector3 = anchor.basis.y
	var fwd: Vector3 = anchor.basis.z * direction   # direction d'extension du hall

	# Matériaux
	var concrete_mat: StandardMaterial3D = StandardMaterial3D.new()
	concrete_mat.albedo_color = Color(0.45, 0.43, 0.40)
	concrete_mat.roughness = 0.92
	concrete_mat.metallic = 0.0
	concrete_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var floor_mat: StandardMaterial3D = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.32, 0.30, 0.28)
	floor_mat.roughness = 0.65
	floor_mat.metallic = 0.0
	floor_mat.uv1_scale = Vector3(4.0, 4.0, 1.0)

	var ceiling_mat: StandardMaterial3D = StandardMaterial3D.new()
	ceiling_mat.albedo_color = Color(0.55, 0.53, 0.50)
	ceiling_mat.roughness = 0.90
	ceiling_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# --- Sol, plafond, 3 murs (le 4ème = ouverture vers le tunnel) -------
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(concrete_mat)

	var hw: float = hall_width * 0.5      # demi-largeur
	var hh: float = hall_height           # hauteur totale
	var L: float = hall_length            # longueur

	# Coordonnées en repère LOCAL hall (sol_y_local = hall_floor_offset)
	# x_local : ±hw (largeur)
	# y_local : hall_floor_offset (sol) → hall_floor_offset + hh (plafond)
	# z_local : 0 (côté tunnel) → L (fond du hall, vers la sortie)

	# Helper local : convertit (x, y, z) local → monde
	# Les fonctions locales ne sont pas supportées en GDScript ; on inline.

	# Coins du hall
	var y_floor: float = hall_floor_offset
	var y_ceil: float = hall_floor_offset + hh

	# Sol — émettre à part avec floor_mat
	var st_floor: SurfaceTool = SurfaceTool.new()
	st_floor.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_floor.set_material(floor_mat)

	var p000: Vector3 = origin + right * (-hw) + up * y_floor + fwd * 0.0
	var p100: Vector3 = origin + right * (+hw) + up * y_floor + fwd * 0.0
	var p010: Vector3 = origin + right * (-hw) + up * y_ceil + fwd * 0.0
	var p110: Vector3 = origin + right * (+hw) + up * y_ceil + fwd * 0.0
	var p001: Vector3 = origin + right * (-hw) + up * y_floor + fwd * L
	var p101: Vector3 = origin + right * (+hw) + up * y_floor + fwd * L
	var p011: Vector3 = origin + right * (-hw) + up * y_ceil + fwd * L
	var p111: Vector3 = origin + right * (+hw) + up * y_ceil + fwd * L

	# Sol (Y = y_floor)
	_quad(st_floor, p000, p100, p101, p001)
	# Plafond (Y = y_ceil)
	var st_ceil: SurfaceTool = SurfaceTool.new()
	st_ceil.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_ceil.set_material(ceiling_mat)
	_quad(st_ceil, p010, p011, p111, p110)
	# Mur gauche (X = -hw)
	_quad(st, p000, p001, p011, p010)
	# Mur droite (X = +hw)
	_quad(st, p100, p110, p111, p101)
	# Mur du fond (Z = L)
	_quad(st, p001, p101, p111, p011)
	# Le mur côté tunnel (Z = 0) reste OUVERT — la cabine entre par là

	st.generate_normals(); st.generate_tangents()
	st_floor.generate_normals(); st_floor.generate_tangents()
	st_ceil.generate_normals(); st_ceil.generate_tangents()

	var mi_walls: MeshInstance3D = MeshInstance3D.new()
	mi_walls.name = name + "_walls"
	mi_walls.mesh = st.commit()
	mi_walls.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi_walls)

	var mi_floor: MeshInstance3D = MeshInstance3D.new()
	mi_floor.name = name + "_floor"
	mi_floor.mesh = st_floor.commit()
	mi_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi_floor)

	var mi_ceil: MeshInstance3D = MeshInstance3D.new()
	mi_ceil.name = name + "_ceiling"
	mi_ceil.mesh = st_ceil.commit()
	mi_ceil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi_ceil)

	# --- Cage d'escalier vers la surface (au fond du hall) ---------------
	# Trou rectangulaire dans le plafond, cage qui monte avec lumière du jour
	_build_exit_shaft(origin, right, up, fwd, L, y_ceil, sky_tint, name)

	# --- Éclairage hall : 6 néons plafond -------------------------------
	for i in range(6):
		var t: float = (float(i) + 0.5) / 6.0
		var pos_light: Vector3 = origin + up * (y_ceil - 0.4) + fwd * (t * L)
		var light: OmniLight3D = OmniLight3D.new()
		light.position = pos_light
		light.light_color = Color(0.95, 0.97, 1.0)
		light.light_energy = 5.5
		light.omni_range = 14.0
		light.omni_attenuation = 1.4
		light.shadow_enabled = false
		add_child(light)
		# Bâtonnet émissif visible
		var neon_mesh: BoxMesh = BoxMesh.new()
		neon_mesh.size = Vector3(2.0, 0.10, 0.20)
		var neon_mat: StandardMaterial3D = StandardMaterial3D.new()
		neon_mat.albedo_color = Color(0.98, 0.99, 1.0)
		neon_mat.emission_enabled = true
		neon_mat.emission = Color(0.95, 0.97, 1.0)
		neon_mat.emission_energy_multiplier = 2.5
		neon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		neon_mesh.material = neon_mat
		var neon: MeshInstance3D = MeshInstance3D.new()
		neon.mesh = neon_mesh
		neon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		neon.position = pos_light
		neon.basis = anchor.basis   # alignement avec le tunnel
		add_child(neon)

	# --- Panneau "STATION" géant au fond ---------------------------------
	var sign_pos: Vector3 = origin + up * (y_ceil - 1.5) + fwd * (L - 0.05)
	_emit_label3d(sign_pos, name_txt, 240, Color(1.0, 0.85, 0.25), 14)
	var alt_pos: Vector3 = origin + up * (y_ceil - 2.5) + fwd * (L - 0.05)
	_emit_label3d(alt_pos, alt_txt, 100, Color(0.95, 0.95, 0.95), 8)

	# --- Panneau "EXIT" sous la cage d'escalier --------------------------
	var exit_pos: Vector3 = origin + up * (y_ceil - 4.5) + fwd * (L * 0.78)
	_emit_label3d(exit_pos, exit_txt, 120, Color(0.20, 0.95, 0.30), 10)

	# --- Bancs en attente (3 le long du mur gauche) ----------------------
	var bench_mat: StandardMaterial3D = StandardMaterial3D.new()
	bench_mat.albedo_color = Color(0.55, 0.40, 0.20)
	bench_mat.roughness = 0.85
	for i in range(3):
		var z_b: float = L * (0.25 + float(i) * 0.20)
		var bench_pos: Vector3 = origin + right * (-hw + 0.85) + up * (y_floor + 0.40) + fwd * z_b
		var bench_mesh: BoxMesh = BoxMesh.new()
		bench_mesh.size = Vector3(0.50, 0.10, 1.80)
		bench_mesh.material = bench_mat
		var bench: MeshInstance3D = MeshInstance3D.new()
		bench.mesh = bench_mesh
		bench.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bench.position = bench_pos
		bench.basis = anchor.basis
		add_child(bench)

	# --- Quelques passagers en attente -----------------------------------
	_build_waiting_passengers(origin, right, up, fwd, L, y_floor, anchor.basis)


func _build_exit_shaft(
	origin: Vector3, right: Vector3, up: Vector3, fwd: Vector3,
	L: float, y_ceil: float, sky_tint: Color, name: String,
) -> void:
	# Cage rectangulaire qui monte à travers le plafond, avec lumière du jour
	# au sommet pour suggérer la sortie vers la surface
	var shaft_w: float = exit_shaft_radius * 2.0   # largeur
	var shaft_z_center: float = L * 0.78            # position dans le hall
	var shaft_y_top: float = y_ceil + exit_shaft_height

	var concrete_mat: StandardMaterial3D = StandardMaterial3D.new()
	concrete_mat.albedo_color = Color(0.50, 0.48, 0.45)
	concrete_mat.roughness = 0.92
	concrete_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(concrete_mat)

	# 4 murs de la cage (la base est un trou dans le plafond, le sommet est ouvert)
	var z_lo: float = shaft_z_center - exit_shaft_radius
	var z_hi: float = shaft_z_center + exit_shaft_radius
	var x_lo: float = -exit_shaft_radius
	var x_hi: float = +exit_shaft_radius

	# 8 coins
	var c000: Vector3 = origin + right * x_lo + up * y_ceil + fwd * z_lo
	var c100: Vector3 = origin + right * x_hi + up * y_ceil + fwd * z_lo
	var c010: Vector3 = origin + right * x_lo + up * shaft_y_top + fwd * z_lo
	var c110: Vector3 = origin + right * x_hi + up * shaft_y_top + fwd * z_lo
	var c001: Vector3 = origin + right * x_lo + up * y_ceil + fwd * z_hi
	var c101: Vector3 = origin + right * x_hi + up * y_ceil + fwd * z_hi
	var c011: Vector3 = origin + right * x_lo + up * shaft_y_top + fwd * z_hi
	var c111: Vector3 = origin + right * x_hi + up * shaft_y_top + fwd * z_hi

	# 4 murs
	_quad(st, c000, c010, c011, c001)   # gauche (X = x_lo)
	_quad(st, c100, c101, c111, c110)   # droite (X = x_hi)
	_quad(st, c000, c100, c110, c010)   # avant (Z = z_lo)
	_quad(st, c001, c011, c111, c101)   # arrière (Z = z_hi)

	st.generate_normals(); st.generate_tangents()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = name + "_shaft"
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	# Lumière du jour au sommet de la cage (rectangle émissif + omni light)
	var sky_mat: StandardMaterial3D = StandardMaterial3D.new()
	sky_mat.albedo_color = sky_tint
	sky_mat.emission_enabled = true
	sky_mat.emission = sky_tint
	sky_mat.emission_energy_multiplier = 4.5
	sky_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var sky_st: SurfaceTool = SurfaceTool.new()
	sky_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	sky_st.set_material(sky_mat)
	# Quad horizontal au sommet de la cage
	_quad(sky_st,
		c010, c011, c111, c110,
	)
	sky_st.generate_normals(); sky_st.generate_tangents()
	var mi_sky: MeshInstance3D = MeshInstance3D.new()
	mi_sky.name = name + "_skylight"
	mi_sky.mesh = sky_st.commit()
	mi_sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi_sky)

	# Lumière directionnelle "naturelle" depuis le haut
	var sun: OmniLight3D = OmniLight3D.new()
	sun.position = origin + up * (shaft_y_top - 0.5) + fwd * shaft_z_center
	sun.light_color = sky_tint
	sun.light_energy = 8.0
	sun.omni_range = 18.0
	sun.shadow_enabled = false
	add_child(sun)

	# Escaliers stylisés à l'intérieur de la cage (8 marches)
	var steps_mat: StandardMaterial3D = StandardMaterial3D.new()
	steps_mat.albedo_color = Color(0.40, 0.40, 0.42)
	steps_mat.roughness = 0.85
	for i in range(8):
		var t: float = float(i) / 8.0
		var step_y: float = lerpf(y_ceil + 0.20, shaft_y_top - 0.20, t)
		var step_z: float = lerpf(z_lo + 0.20, z_hi - 0.20, t)
		var step_mesh: BoxMesh = BoxMesh.new()
		step_mesh.size = Vector3(shaft_w * 0.85, 0.10, 0.40)
		step_mesh.material = steps_mat
		var step: MeshInstance3D = MeshInstance3D.new()
		step.mesh = step_mesh
		step.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		step.position = origin + up * step_y + fwd * step_z
		step.basis = Basis(right, up, fwd.normalized() * -1.0).orthonormalized()
		add_child(step)


func _build_waiting_passengers(
	origin: Vector3, right: Vector3, up: Vector3, fwd: Vector3,
	L: float, y_floor: float, basis: Basis,
) -> void:
	# 6 silhouettes en attente, certaines près des bancs (assises),
	# d'autres debout dans le hall
	var skin_mat: StandardMaterial3D = StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.85, 0.70, 0.55)
	skin_mat.roughness = 0.85

	var coats: Array = [
		Color(0.20, 0.30, 0.55),
		Color(0.55, 0.20, 0.20),
		Color(0.15, 0.40, 0.25),
		Color(0.30, 0.30, 0.35),
		Color(0.55, 0.40, 0.10),
		Color(0.45, 0.10, 0.40),
	]
	# [x_local, z_local, sitting, color_idx]
	var people: Array = [
		[-5.5, L * 0.28, true,  0],   # assis sur le 1er banc
		[-5.5, L * 0.50, true,  1],   # assis sur le 2ème banc
		[ 0.0, L * 0.30, false, 2],   # debout milieu
		[ 2.5, L * 0.45, false, 3],   # debout milieu droite
		[-2.0, L * 0.62, false, 4],   # debout milieu gauche
		[ 4.0, L * 0.75, false, 5],   # debout sous la cage d'escalier
	]
	for p in people:
		var x: float = p[0]
		var z: float = p[1]
		var sitting: bool = p[2]
		var color: Color = coats[p[3]]
		_emit_hall_passenger(origin, right, up, fwd, basis, skin_mat, color, x, z, y_floor, sitting)


func _emit_hall_passenger(
	origin: Vector3, right: Vector3, up: Vector3, fwd: Vector3, basis: Basis,
	skin_mat: StandardMaterial3D, coat_color: Color,
	x_local: float, z_local: float, y_floor: float, sitting: bool,
) -> void:
	var coat_mat: StandardMaterial3D = StandardMaterial3D.new()
	coat_mat.albedo_color = coat_color
	coat_mat.roughness = 0.92

	var torso_h: float = 0.55 if sitting else 0.78
	var y_torso: float = (y_floor + 0.85) if sitting else (y_floor + 1.05)

	var torso: MeshInstance3D = MeshInstance3D.new()
	var torso_mesh: BoxMesh = BoxMesh.new()
	torso_mesh.size = Vector3(0.45, torso_h, 0.30)
	torso_mesh.material = coat_mat
	torso.mesh = torso_mesh
	torso.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	torso.position = origin + right * x_local + up * y_torso + fwd * z_local
	torso.basis = basis
	add_child(torso)

	var head: MeshInstance3D = MeshInstance3D.new()
	var head_mesh: SphereMesh = SphereMesh.new()
	head_mesh.radius = 0.115
	head_mesh.height = 0.23
	head_mesh.material = skin_mat
	head.mesh = head_mesh
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.position = origin + right * x_local + up * (y_torso + torso_h * 0.5 + 0.13) + fwd * z_local
	add_child(head)


func _emit_label3d(pos: Vector3, text: String, font_size: int, color: Color, outline: int) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.008
	label.modulate = color
	label.outline_size = outline
	label.outline_modulate = Color(0.0, 0.0, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	label.double_sided = true
	label.position = pos
	add_child(label)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(0, 1)); st.add_vertex(b)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_uv(Vector2(1, 0)); st.add_vertex(d)
