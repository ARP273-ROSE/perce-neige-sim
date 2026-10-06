class_name StationHalls
extends Node3D
## Bâtiment de gare au portail bas du tunnel.
##
## - Val Claret (s=0) : hall béton avec escaliers/escalator menant vers la
##   surface (village Val Claret 2111m). Lumière du jour visible au sommet.
## - Grande Motte (s=LENGTH) : plus de hall depuis le 06/10/2026 — la gare
##   se termine sur le mur vitré de la salle des machines, qui donne sur le
##   glacier (MachineRoomBuilder).
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
	# Plus de hall en gare amont (06/10/2026) : la gare se termine sur le
	# mur vitré de la salle des machines, qui donne sur le glacier
	# (MachineRoomBuilder._build_mur_vitre / _build_exterieur).


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
		"ALTITUDE EXPERIENCE",
		_t("FUNICULAR — DEPARTURE STATION  ·  Val Claret 2111 m",
		   "FUNICULAIRE — GARE DE DÉPART  ·  Val Claret 2111 m"),
		_t("EXIT TO VILLAGE ↑", "SORTIE VILLAGE ↑"),
		Color(0.85, 0.92, 1.00),  # teinte bleue (lumière jour)
		"hall_low",
		Color(1.00, 0.95, 0.92),  # branding blanc cassé (panneau lumineux sur fond rouge)
	)


# ---------------------------------------------------------------------------
# Grande Motte — hall haut
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Construction d'un hall générique
# direction = +1 → hall s'étend en +basis.z (arrière)
# direction = -1 → hall s'étend en -basis.z (avant)
# ---------------------------------------------------------------------------

func _build_hall(
	anchor: Transform3D, direction: float, name_txt: String, alt_txt: String,
	exit_txt: String, sky_tint: Color, name: String,
	sign_color: Color = Color(1.0, 0.85, 0.25),
) -> void:
	var origin: Vector3 = anchor.origin
	var right: Vector3 = anchor.basis.x
	var up: Vector3 = anchor.basis.y
	var fwd: Vector3 = anchor.basis.z * direction   # direction d'extension du hall

	# Matériaux
	var concrete_mat: StandardMaterial3D = StandardMaterial3D.new()
	concrete_mat.albedo_color = Color(0.52, 0.38, 0.22)   # bardage bois des halls (photos 093457 / 093505)
	concrete_mat.roughness = 0.92
	concrete_mat.metallic = 0.0
	concrete_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var floor_mat: StandardMaterial3D = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.32, 0.30, 0.28)
	floor_mat.roughness = 0.65
	floor_mat.metallic = 0.0
	floor_mat.uv1_scale = Vector3(4.0, 4.0, 1.0)

	var ceiling_mat: StandardMaterial3D = StandardMaterial3D.new()
	ceiling_mat.albedo_color = Color(0.86, 0.86, 0.84)   # panneaux clairs suspendus
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
	# Reproduit la signalétique du vrai funiculaire :
	#   - aval (Val Claret) : "ALTITUDE EXPERIENCE" en blanc cassé sur
	#     fond mural (style panneau lumineux rouge)
	#   - amont (Grande Motte) : "DESTINATION GLACIER" en orange ampoules
	#     vintage (caisson noir + lettres formées d'ampoules)
	var sign_pos: Vector3 = origin + up * (y_ceil - 1.5) + fwd * (L - 0.05)
	_emit_label3d(sign_pos, name_txt, 240, sign_color, 14)
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
	# 6 skieurs en attente (SkieurMesh, 06/10/2026), certains assis sur les
	# bancs (assise à 0,45 m), d'autres debout avec leur matériel
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(absf(origin.y) * 10.0) + 11
	# [x_local, z_local, assis]
	var people: Array = [
		[-5.5, L * 0.28, true],
		[-5.5, L * 0.50, true],
		[ 0.0, L * 0.30, false],
		[ 2.5, L * 0.45, false],
		[-2.0, L * 0.62, false],
		[ 4.0, L * 0.75, false],
	]
	var m: Dictionary = Cabin._skieurs_maillages()     # maillages partagés avec les rames
	for p in people:
		var assis: bool = p[2]
		var face: Vector3
		if assis:
			face = right      # le banc longe le mur gauche : on regarde le hall
		else:
			face = fwd.rotated(up.normalized(), rng.randf_range(-PI, PI))
		var zb: Vector3 = (-face).normalized()
		var xb: Vector3 = up.normalized().cross(zb).normalized()
		var base: Transform3D = Transform3D(Basis(xb, up.normalized(), zb),
			origin + right * float(p[0]) + up * y_floor + fwd * float(p[1]))
		var pose: String = "assis"
		var materiel: String = ""
		if not assis:
			var r: float = rng.randf()
			pose = "skis" if r < 0.6 else ("libre" if r < 0.8 else "telephone")
			if pose == "skis":
				materiel = "surf" if rng.randf() < 0.25 else "skis"
		var coiffe: String = "casque" if rng.randf() < 0.65 else "bonnet"
		var graine: Color = Color(rng.randf(), rng.randf(), rng.randf(), 1.0)
		_skieur_mm(m["p:%s:%s" % [pose, coiffe]], base, graine)
		if rng.randf() < 0.3:
			_skieur_mm(m["s:" + pose], base, graine)
		var g: Color = Color(rng.randf(), rng.randf(), rng.randf(), 1.0)
		if materiel == "skis":
			_skieur_mm(m["g:skis"], base * Transform3D(Basis.IDENTITY, SkieurMesh.ANCRE_SKIS), g)
			_skieur_mm(m["g:batons"], base * Transform3D(Basis.IDENTITY, SkieurMesh.ANCRE_BATONS), g)
		elif materiel == "surf":
			_skieur_mm(m["g:surf"], base * Transform3D(Basis.IDENTITY, SkieurMesh.ANCRE_SURF), g)


## Un skieur (ou son matériel) : MultiMesh d'une instance, pour que le
## shader lise ses graines de couleur (INSTANCE_CUSTOM).
func _skieur_mm(mesh: Mesh, xf: Transform3D, graine: Color) -> void:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, xf)
	mm.set_instance_custom_data(0, graine)
	var mi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


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
