class_name StationsBuilder
extends Node3D
## Plateformes Val Claret (bas) et Grande Motte (haut).
##
## Pour chaque station :
##   - quai latéral béton (35 m) avec bande jaune de sécurité
##   - éclairage station renforcé (néons plafond + spots)
##   - signalétique Label3D bilingue (nom + altitude)
##   - tampons de fin de voie (rouge-blanc rayé)
##   - cabine de commande / panneau technique (volume simple)
##
## Les coordonnées s sont relatives au portail bas (0) / haut (LENGTH).

@export var platform_length: float = 48.0      # allongé pour contenir tout le train
@export var platform_width: float = 1.20       # largeur quai latéral
@export var platform_inner_x: float = 1.85     # distance depuis centre tunnel au bord intérieur (hors gabarit cabine ∅3.6m)
@export var platform_height: float = 0.40      # hauteur quai vs plancher voie (plancher cabine bas)
@export var yellow_band_width: float = 0.12    # bande jaune
@export var yellow_band_height: float = 0.020  # saillie de la bande
@export var ceiling_height: float = 1.85       # hauteur centre → plafond
@export var bumper_height: float = 1.30
@export var bumper_width: float = 1.60
@export var bumper_thickness: float = 0.35

var tunnel: TunnelBuilder = null
var lang: String = "fr"

# Paramètres plateforme — offsets dans la base locale
const FLOOR_Y_LOCAL: float = -1.10 # top dalle (cohérent avec track_builder : floor_y_local + slab_thickness = -1.35+0.25 = -1.10)


func build(t: TunnelBuilder) -> void:
	tunnel = t
	_detect_lang()
	_build_station_low()
	_build_station_high()


func _detect_lang() -> void:
	var loc: String = OS.get_locale().to_lower()
	lang = "fr" if loc.begins_with("fr") else "en"


func _t(en: String, fr: String) -> String:
	return fr if lang == "fr" else en


# ---------------------------------------------------------------------------
# Val Claret : portail bas, s ∈ [0, 45] en gros
# ---------------------------------------------------------------------------

func _build_station_low() -> void:
	var name_txt: String = "VAL CLARET"
	var alt_txt: String = _t("ALT. 2111 m", "ALT. 2111 m")
	var direction_txt: String = _t("→ GLACIER 3032 m", "→ GLACIER 3032 m")

	# Le train occupe s ∈ [10, 42] (centre à START_S=26, half_length=16).
	# Plateforme déborde de chaque côté : [3, 51] — 8m en arrière, 9m devant le nez.
	var s_bumper: float = 2.0
	var s_plat_start: float = 3.0
	var s_plat_end: float = s_plat_start + platform_length

	# 2 quais : un de chaque côté de la voie pour symétrie (une cabine peut
	# ouvrir ses portes des 2 côtés, ou 2 cabines successives utilisent l'un
	# ou l'autre selon le sens d'arrivée).
	_build_platform(s_plat_start, s_plat_end, true, +1.0)
	_build_platform(s_plat_start, s_plat_end, true, -1.0)
	_build_bumper(s_bumper, true)
	_build_ceiling_lights(s_plat_start, s_plat_end)
	_build_station_signage(
		s_plat_start + platform_length * 0.5,
		name_txt, alt_txt, direction_txt,
		true
	)


# ---------------------------------------------------------------------------
# Grande Motte : portail haut, s ∈ [3434, 3474]
# ---------------------------------------------------------------------------

func _build_station_high() -> void:
	var name_txt: String = "GRANDE MOTTE"
	var alt_txt: String = "ALT. 3032 m"
	var direction_txt: String = _t("VAL CLARET 2111 m ←", "VAL CLARET 2111 m ←")

	var s_bumper: float = PNConstants.LENGTH - 0.4   # collé contre la fin du tunnel
	var s_plat_end: float = PNConstants.LENGTH - 1.0
	var s_plat_start: float = s_plat_end - platform_length

	_build_platform(s_plat_start, s_plat_end, false, +1.0)
	_build_platform(s_plat_start, s_plat_end, false, -1.0)
	_build_bumper(s_bumper, false)
	_build_ceiling_lights(s_plat_start, s_plat_end)
	_build_station_signage(
		s_plat_start + platform_length * 0.5,
		name_txt, alt_txt, direction_txt,
		false
	)


# ---------------------------------------------------------------------------
# Plateforme béton + bande jaune
# ---------------------------------------------------------------------------

func _build_platform(s_start: float, s_end: float, is_low: bool, side: float = 1.0) -> void:
	# Matériaux
	var concrete_mat: StandardMaterial3D = StandardMaterial3D.new()
	concrete_mat.albedo_color = Color(0.42, 0.40, 0.37)
	concrete_mat.roughness = 0.92
	concrete_mat.metallic = 0.0
	concrete_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var yellow_mat: StandardMaterial3D = StandardMaterial3D.new()
	yellow_mat.albedo_color = Color(0.92, 0.70, 0.08)
	yellow_mat.emission_enabled = true
	yellow_mat.emission = Color(0.92, 0.70, 0.08)
	yellow_mat.emission_energy_multiplier = 0.12
	yellow_mat.roughness = 0.6
	yellow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Construction du quai via SurfaceTool — ruban continu 3 faces
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(concrete_mat)

	var st_yellow: SurfaceTool = SurfaceTool.new()
	st_yellow.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_yellow.set_material(yellow_mat)

	var step: float = 0.5
	var s_cur: float = s_start
	var prev_xform: Transform3D = tunnel.transform_at(s_cur)
	while s_cur < s_end:
		var s_next: float = minf(s_cur + step, s_end)
		var cur_xform: Transform3D = tunnel.transform_at(s_next)

		var p0: Vector3 = prev_xform.origin
		var p1: Vector3 = cur_xform.origin
		var r0: Vector3 = prev_xform.basis.x
		var r1: Vector3 = cur_xform.basis.x
		var u0: Vector3 = prev_xform.basis.y
		var u1: Vector3 = cur_xform.basis.y

		# Positions : x_inner = coin intérieur (côté voie), x_outer = coin extérieur
		# side = +1 → quai à droite (+X local), -1 → quai à gauche.
		# Hors gabarit cabine ∅3.6m (radius 1.80m) : platform_inner_x ≥ 1.85m.
		var x_inner: float = side * platform_inner_x
		var x_outer: float = side * (platform_inner_x + platform_width)
		var y_top: float = FLOOR_Y_LOCAL + platform_height
		var y_bot: float = FLOOR_Y_LOCAL

		# Top de quai
		var a_in: Vector3 = _pt(p0, r0, u0, x_inner, y_top)
		var a_out: Vector3 = _pt(p0, r0, u0, x_outer, y_top)
		var b_in: Vector3 = _pt(p1, r1, u1, x_inner, y_top)
		var b_out: Vector3 = _pt(p1, r1, u1, x_outer, y_top)
		_quad(st, a_in, a_out, b_in, b_out)

		# Face frontale (coté voie)
		var a_in_bot: Vector3 = _pt(p0, r0, u0, x_inner, y_bot)
		var b_in_bot: Vector3 = _pt(p1, r1, u1, x_inner, y_bot)
		_quad(st, a_in_bot, a_in, b_in_bot, b_in)

		# Face bout (si on est au début / fin)
		if s_cur == s_start:
			var a_out_bot: Vector3 = _pt(p0, r0, u0, x_outer, y_bot)
			_quad(st, a_in_bot, a_out_bot, a_in, a_out)
		if s_next >= s_end:
			var b_out_bot: Vector3 = _pt(p1, r1, u1, x_outer, y_bot)
			_quad(st, b_in, b_out, b_in_bot, b_out_bot)

		# Bande jaune de sécurité : peinte SUR le quai, côté voie, 12 cm de large,
		# très légère saillie pour la visibilité.
		var xb_in: float = x_inner
		var xb_out: float = x_inner + yellow_band_width * side
		var yb_lo: float = y_top
		var yb_hi: float = y_top + yellow_band_height
		var ya_in: Vector3 = _pt(p0, r0, u0, xb_in, yb_lo)
		var ya_out: Vector3 = _pt(p0, r0, u0, xb_out, yb_lo)
		var yb_in_v: Vector3 = _pt(p1, r1, u1, xb_in, yb_lo)
		var yb_out_v: Vector3 = _pt(p1, r1, u1, xb_out, yb_lo)
		var ya_in_t: Vector3 = _pt(p0, r0, u0, xb_in, yb_hi)
		var ya_out_t: Vector3 = _pt(p0, r0, u0, xb_out, yb_hi)
		var yb_in_t: Vector3 = _pt(p1, r1, u1, xb_in, yb_hi)
		var yb_out_t: Vector3 = _pt(p1, r1, u1, xb_out, yb_hi)
		_quad(st_yellow, ya_in_t, ya_out_t, yb_in_t, yb_out_t)  # top
		_quad(st_yellow, ya_in, ya_in_t, yb_in_v, yb_in_t)       # côté voie
		_quad(st_yellow, ya_out_t, ya_out, yb_out_t, yb_out_v)   # côté intérieur quai

		s_cur = s_next
		prev_xform = cur_xform

	st.generate_normals()
	st.generate_tangents()
	var mi: MeshInstance3D = MeshInstance3D.new()
	var side_name: String = "R" if side > 0.0 else "L"
	mi.name = "Platform_%s_%s" % [("low" if is_low else "high"), side_name]
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	st_yellow.generate_normals()
	var my: MeshInstance3D = MeshInstance3D.new()
	my.name = "PlatformYellow_%s_%s" % [("low" if is_low else "high"), side_name]
	my.mesh = st_yellow.commit()
	my.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(my)


# ---------------------------------------------------------------------------
# Tampon de fin de voie — box rouge avec bandes jaunes-noires
# ---------------------------------------------------------------------------

func _build_bumper(s: float, _is_low: bool) -> void:
	var xform: Transform3D = tunnel.transform_at(s)
	# Corps rouge
	var red_mat: StandardMaterial3D = StandardMaterial3D.new()
	red_mat.albedo_color = Color(0.75, 0.18, 0.15)
	red_mat.emission_enabled = true
	red_mat.emission = Color(0.75, 0.18, 0.15)
	red_mat.emission_energy_multiplier = 0.25
	red_mat.roughness = 0.5

	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(bumper_width, bumper_height, bumper_thickness)
	box.material = red_mat

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Bumper"
	mi.mesh = box
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tr: Transform3D = xform
	tr.origin += xform.basis.y * (FLOOR_Y_LOCAL + bumper_height * 0.5 + 0.02)
	mi.transform = tr
	add_child(mi)

	# Bandes réfléchissantes noires (visuel signal)
	var stripe_mat: StandardMaterial3D = StandardMaterial3D.new()
	stripe_mat.albedo_color = Color(0.98, 0.82, 0.12)
	stripe_mat.emission_enabled = true
	stripe_mat.emission = Color(0.98, 0.82, 0.12)
	stripe_mat.emission_energy_multiplier = 0.6
	for i in range(3):
		var stripe_box: BoxMesh = BoxMesh.new()
		stripe_box.size = Vector3(bumper_width * 1.01, 0.10, bumper_thickness * 1.01)
		stripe_box.material = stripe_mat
		var si: MeshInstance3D = MeshInstance3D.new()
		si.mesh = stripe_box
		si.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var y_stripe: float = FLOOR_Y_LOCAL + 0.15 + float(i) * 0.42
		var trs: Transform3D = xform
		trs.origin += xform.basis.y * y_stripe
		si.transform = trs
		add_child(si)


# ---------------------------------------------------------------------------
# Éclairage station — néons plafond + spots
# ---------------------------------------------------------------------------

func _build_ceiling_lights(s_start: float, s_end: float) -> void:
	var spacing: float = 4.0
	var s: float = s_start
	while s < s_end:
		var xform: Transform3D = tunnel.transform_at(s)
		var pos: Vector3 = xform.origin + xform.basis.y * (ceiling_height - 0.2)

		var light: OmniLight3D = OmniLight3D.new()
		light.position = pos
		light.light_color = Color(0.95, 0.97, 1.0)
		light.light_energy = 4.5
		light.omni_range = 16.0
		light.omni_attenuation = 1.4
		light.shadow_enabled = false
		add_child(light)

		# Bâtonnet émissif visible (source lumineuse visible dans le brouillard)
		var neon_mesh: BoxMesh = BoxMesh.new()
		neon_mesh.size = Vector3(1.8, 0.08, 0.15)
		var neon_mat: StandardMaterial3D = StandardMaterial3D.new()
		neon_mat.albedo_color = Color(0.98, 0.99, 1.0)
		neon_mat.emission_enabled = true
		neon_mat.emission = Color(0.95, 0.97, 1.0)
		neon_mat.emission_energy_multiplier = 2.0
		neon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		neon_mesh.material = neon_mat

		var neon: MeshInstance3D = MeshInstance3D.new()
		neon.mesh = neon_mesh
		neon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tr: Transform3D = xform
		tr.origin = pos
		neon.transform = tr
		add_child(neon)

		s += spacing


# ---------------------------------------------------------------------------
# Signalétique — Label3D suspendu + fond cadre
# ---------------------------------------------------------------------------

func _build_station_signage(
	s: float, name_txt: String, alt_txt: String, direction_txt: String, is_low: bool,
) -> void:
	var xform: Transform3D = tunnel.transform_at(s)
	var y_sign: float = ceiling_height - 0.8

	# Cadre panneau : fond sombre
	var frame_mat: StandardMaterial3D = StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.08, 0.10, 0.14)
	frame_mat.roughness = 0.3
	frame_mat.metallic = 0.6

	var frame: MeshInstance3D = MeshInstance3D.new()
	var frame_mesh: BoxMesh = BoxMesh.new()
	frame_mesh.size = Vector3(3.2, 0.70, 0.08)
	frame_mesh.material = frame_mat
	frame.mesh = frame_mesh
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tr_frame: Transform3D = xform
	tr_frame.origin += xform.basis.y * y_sign
	# Signage perpendiculaire à l'axe voyage : on garde l'orientation du ring
	# (right = X local, face visible vers +Z local — le train arrive depuis ±Z)
	frame.transform = tr_frame
	add_child(frame)

	# Nom station — grand. Billboard enabled : toujours face caméra, lisible quel
	# que soit l'angle (signalétique lumineuse, pas un vrai panneau texturé).
	var name_label: Label3D = Label3D.new()
	name_label.text = name_txt
	name_label.font_size = 140
	name_label.pixel_size = 0.008
	name_label.modulate = Color(1.0, 0.85, 0.25)
	name_label.outline_size = 10
	name_label.outline_modulate = Color(0.0, 0.0, 0.0)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.shaded = false
	name_label.double_sided = true
	var tr_name: Transform3D = xform
	tr_name.origin += xform.basis.y * (y_sign + 0.20)
	name_label.transform = tr_name
	add_child(name_label)

	# Altitude — petit
	var alt_label: Label3D = Label3D.new()
	alt_label.text = alt_txt
	alt_label.font_size = 90
	alt_label.pixel_size = 0.007
	alt_label.modulate = Color(0.95, 0.95, 0.95)
	alt_label.outline_size = 7
	alt_label.outline_modulate = Color(0.0, 0.0, 0.0)
	alt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	alt_label.shaded = false
	alt_label.double_sided = true
	var tr_alt: Transform3D = xform
	tr_alt.origin += xform.basis.y * (y_sign - 0.25)
	alt_label.transform = tr_alt
	add_child(alt_label)

	# Direction — plus petit, décalé le long du quai
	var dir_label: Label3D = Label3D.new()
	dir_label.text = direction_txt
	dir_label.font_size = 60
	dir_label.pixel_size = 0.006
	dir_label.modulate = Color(0.60, 0.90, 1.0)
	dir_label.outline_size = 6
	dir_label.outline_modulate = Color(0.0, 0.0, 0.0)
	dir_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dir_label.shaded = false
	dir_label.double_sided = true
	var s_dir: float = s + (12.0 if is_low else -12.0)
	var xform_dir: Transform3D = tunnel.transform_at(s_dir)
	var tr_dir: Transform3D = xform_dir
	tr_dir.origin += xform_dir.basis.y * (ceiling_height - 0.9)
	dir_label.transform = tr_dir
	add_child(dir_label)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _pt(origin: Vector3, right: Vector3, up: Vector3, dx: float, dy: float) -> Vector3:
	return origin + right * dx + up * dy


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# Ordre CCW : triangles (a, c, d) et (a, d, b) — à ajuster pour que le front-face
	# soit visible depuis le train (intérieur du tunnel).
	st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(a)
	st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(c)
	st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(d)
	st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(a)
	st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(d)
	st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(b)
