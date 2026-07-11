class_name StationsBuilder
extends Node3D
## Plateformes Val Claret (bas) et Grande Motte (haut).
##
## Pour chaque station :
##   - quais en escalier SANS garde-corps (on embarque par là)
##   - éclairage station renforcé (néons plafond + spots)
##   - tampons de fin de voie (rouge-blanc rayé)
##   - cabine de commande / panneau technique (volume simple)
##
## Les coordonnées s sont relatives au portail bas (0) / haut (LENGTH).

@export var platform_length: float = 48.0      # allongé pour contenir tout le train
# Quais EN ESCALIER (photos du 2026-04-26) : pas de quai-rampe lisse —
# une volée de marches-paliers horizontales de 3 m de large longe le train
# de chaque côté, la contremarche de chaque marche découlant de la pente
# locale de la voie. Nez de marche contrastés (alu en bas, rouges en haut).
@export var platform_width: float = 3.00       # largeur quai latéral (bord extérieur ≈ au mur de salle)
@export var platform_inner_x: float = 1.85     # distance depuis centre tunnel au bord intérieur (hors gabarit cabine ∅3.6m)
@export var platform_height: float = 0.40      # hauteur quai vs plancher voie (plancher cabine bas)
@export var tread_depth: float = 0.95          # profondeur d'une marche-palier
@export var tread_thickness: float = 0.55      # épaisseur du bloc (descend sous la marche suivante)
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


# ---------------------------------------------------------------------------
# Grande Motte : portail haut, s ∈ [3434, 3474]
# ---------------------------------------------------------------------------

func _build_station_high() -> void:
	var s_bumper: float = PNConstants.LENGTH - 0.4   # collé contre la fin du tunnel
	var s_plat_end: float = PNConstants.LENGTH - 1.0
	var s_plat_start: float = s_plat_end - platform_length

	_build_platform(s_plat_start, s_plat_end, false, +1.0)
	_build_platform(s_plat_start, s_plat_end, false, -1.0)
	_build_bumper(s_bumper, false)
	_build_ceiling_lights(s_plat_start, s_plat_end)


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
