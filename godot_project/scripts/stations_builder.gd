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
# Quais EN ESCALIER (photos du 2026-04-26) : pas de quai-rampe lisse —
# une volée de marches-paliers horizontales longe le train de chaque côté,
# étroite (~1,5 m), la contremarche de chaque marche découlant de la pente
# locale de la voie. Nez de marche contrastés (alu en bas, rouges en haut).
@export var platform_width: float = 1.62       # largeur quai latéral (étroit, cf. photos ; bord extérieur ≈ au mur de salle)
@export var platform_inner_x: float = 1.85     # distance depuis centre tunnel au bord intérieur (hors gabarit cabine ∅3.6m)
@export var platform_height: float = 0.40      # hauteur quai vs plancher voie (plancher cabine bas)
@export var tread_depth: float = 0.95          # profondeur d'une marche-palier
@export var tread_thickness: float = 0.55      # épaisseur du bloc (descend sous la marche suivante)
@export var railing_height: float = 0.95       # garde-corps côté voie
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
	# Quai EN ESCALIER (photos 20260426_094104 / 095119) : volée de
	# marches-paliers HORIZONTALES le long du train. Le dessus de chaque
	# marche est calé sur l'élévation de la voie à son bord AMONT — la
	# contremarche qui en résulte est exactement pente_locale × profondeur
	# (géométrie honnête, pas de marches inventées).
	var side_name: String = "R" if side > 0.0 else "L"
	var sta: String = "low" if is_low else "high"

	# Tôle damier alu (marches métalliques des photos)
	var tread_mat: StandardMaterial3D = StandardMaterial3D.new()
	tread_mat.albedo_color = Color(0.58, 0.59, 0.62)
	tread_mat.roughness = 0.45
	tread_mat.metallic = 0.75
	tread_mat.metallic_specular = 0.6

	# Nez de marche : alu brut en gare basse, ROUGES en gare haute (photos)
	var nose_mat: StandardMaterial3D = StandardMaterial3D.new()
	if is_low:
		nose_mat.albedo_color = Color(0.80, 0.81, 0.84)
		nose_mat.roughness = 0.35
		nose_mat.metallic = 0.85
	else:
		nose_mat.albedo_color = Color(0.72, 0.14, 0.12)
		nose_mat.roughness = 0.65
		nose_mat.metallic = 0.10

	var rail_mat: StandardMaterial3D = StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.75, 0.76, 0.78)
	rail_mat.roughness = 0.35
	rail_mat.metallic = 0.85

	var lat_center: float = side * (platform_inner_x + platform_width * 0.5)
	var y_top_local: float = FLOOR_Y_LOCAL + platform_height

	# --- Marches (MultiMesh) ---------------------------------------------
	var n_treads: int = maxi(1, int(ceil((s_end - s_start) / tread_depth)))
	var tread_mesh: BoxMesh = BoxMesh.new()
	tread_mesh.size = Vector3(platform_width, tread_thickness, tread_depth)
	tread_mesh.material = tread_mat

	var nose_mesh: BoxMesh = BoxMesh.new()
	nose_mesh.size = Vector3(platform_width, 0.035, 0.11)
	nose_mesh.material = nose_mat

	var mm_treads: MultiMesh = MultiMesh.new()
	mm_treads.transform_format = MultiMesh.TRANSFORM_3D
	mm_treads.mesh = tread_mesh
	mm_treads.instance_count = n_treads

	var mm_noses: MultiMesh = MultiMesh.new()
	mm_noses.transform_format = MultiMesh.TRANSFORM_3D
	mm_noses.mesh = nose_mesh
	mm_noses.instance_count = n_treads

	for i in range(n_treads):
		var s_dn: float = s_start + float(i) * tread_depth          # bord aval
		var s_up: float = minf(s_dn + tread_depth, s_end)           # bord amont
		var s_mid: float = (s_dn + s_up) * 0.5
		var xf_up: Transform3D = tunnel.transform_at(s_up)
		var xf_mid: Transform3D = tunnel.transform_at(s_mid)
		# Élévation MONDE du dessus de marche = niveau du quai au bord amont
		var top_y: float = (xf_up.origin + xf_up.basis.y * y_top_local).y
		# Base nivelée : right local (déjà horizontal), up = UP monde
		var right_h: Vector3 = xf_mid.basis.x
		var level_basis: Basis = Basis(
			right_h, Vector3.UP, right_h.cross(Vector3.UP)).orthonormalized()
		var center: Vector3 = xf_mid.origin + xf_mid.basis.x * lat_center
		center.y = top_y - tread_thickness * 0.5
		mm_treads.set_instance_transform(i, Transform3D(level_basis, center))
		# Nez : au bord AVAL de la marche, affleurant le dessus
		var xf_dn: Transform3D = tunnel.transform_at(s_dn + 0.06)
		var nose_c: Vector3 = xf_dn.origin + xf_dn.basis.x * lat_center
		nose_c.y = top_y - 0.017
		mm_noses.set_instance_transform(i, Transform3D(level_basis, nose_c))

	var mi_treads: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mi_treads.name = "PlatformSteps_%s_%s" % [sta, side_name]
	mi_treads.multimesh = mm_treads
	mi_treads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi_treads)

	var mi_noses: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mi_noses.name = "PlatformNoses_%s_%s" % [sta, side_name]
	mi_noses.multimesh = mm_noses
	mi_noses.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi_noses)

	# --- Garde-corps côté voie (poteaux + main courante inclinée) ---------
	var post_spacing: float = 1.9
	var n_posts: int = maxi(2, int((s_end - s_start) / post_spacing) + 1)
	var lat_rail: float = side * (platform_inner_x + 0.06)

	var post_mesh: CylinderMesh = CylinderMesh.new()
	post_mesh.top_radius = 0.022
	post_mesh.bottom_radius = 0.022
	post_mesh.height = railing_height
	post_mesh.radial_segments = 8
	post_mesh.material = rail_mat

	var mm_posts: MultiMesh = MultiMesh.new()
	mm_posts.transform_format = MultiMesh.TRANSFORM_3D
	mm_posts.mesh = post_mesh
	mm_posts.instance_count = n_posts

	var rail_seg_mesh: CylinderMesh = CylinderMesh.new()
	rail_seg_mesh.top_radius = 0.028
	rail_seg_mesh.bottom_radius = 0.028
	rail_seg_mesh.height = post_spacing + 0.15
	rail_seg_mesh.radial_segments = 8
	rail_seg_mesh.material = rail_mat

	var mm_rails: MultiMesh = MultiMesh.new()
	mm_rails.transform_format = MultiMesh.TRANSFORM_3D
	mm_rails.mesh = rail_seg_mesh
	mm_rails.instance_count = n_posts

	var rot_along: Basis = Basis(Vector3(1, 0, 0), PI * 0.5)
	for i in range(n_posts):
		var s_p: float = minf(s_start + float(i) * post_spacing, s_end)
		var xf: Transform3D = tunnel.transform_at(s_p)
		var base: Vector3 = xf.origin + xf.basis.x * lat_rail \
			+ xf.basis.y * y_top_local
		# Poteau vertical monde
		var post_c: Vector3 = base + Vector3.UP * (railing_height * 0.5)
		mm_posts.set_instance_transform(i, Transform3D(Basis(), post_c))
		# Main courante : segment INCLINÉ le long de la pente (cylindre Y →
		# Z local du ring via rotation X 90° dans la base du ring)
		var rail_c: Vector3 = base + Vector3.UP * railing_height
		mm_rails.set_instance_transform(
			i, Transform3D(xf.basis * rot_along, rail_c))

	var mi_posts: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mi_posts.name = "PlatformPosts_%s_%s" % [sta, side_name]
	mi_posts.multimesh = mm_posts
	mi_posts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi_posts)

	var mi_rails: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mi_rails.name = "PlatformRails_%s_%s" % [sta, side_name]
	mi_rails.multimesh = mm_rails
	mi_rails.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi_rails)


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
	# Néons collés au plafond de la SALLE élargie (2,65 m), pas à l'ancienne
	# hauteur de tube (1,85 m) où ils flotteraient en plein milieu.
	var y_neon: float = tunnel.station_room_half_height - 0.25
	var s: float = s_start
	while s < s_end:
		var xform: Transform3D = tunnel.transform_at(s)
		var pos: Vector3 = xform.origin + xform.basis.y * y_neon

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
