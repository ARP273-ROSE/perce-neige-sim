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
@export var platform_height: float = 0.50      # hauteur quai vs dalle : quai à −1,10 = plancher cabine
@export var tread_depth: float = 0.95          # profondeur d'une marche-palier
@export var tread_thickness: float = 0.55      # épaisseur du bloc (descend sous la marche suivante)
@export var ceiling_height: float = 1.85       # hauteur centre → plafond
@export var bumper_height: float = 1.30
@export var bumper_width: float = 1.60
@export var bumper_thickness: float = 0.35

var tunnel: TunnelBuilder = null
var lang: String = "fr"

# Paramètres plateforme — offsets dans la base locale
const FLOOR_Y_LOCAL: float = -1.60 # top dalle (cohérent avec track_builder : floor_y_local + slab_thickness = -1.85+0.25 = -1.60)
const RAIL_HEAD_Y: float = -1.24   # table de roulement (dalle −1,60 + blochet 0,20 + rail 0,17 − 0,01)
# Fosses (mêmes bornes que track_builder.pit_low_end / pit_high_start)
const PIT_LOW_START: float = -4.0
const PIT_LOW_END: float = 4.5
const PIT_HIGH_START: float = PNConstants.LENGTH - 2.0
const PIT_HIGH_END: float = PNConstants.LENGTH + 4.0
const PIT_DEPTH: float = 1.0


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
	# Fosse sous la voie et le nez de la rame (photos 093522 / 094104) :
	# caillebotis en fond, chaînes, et butoirs bleus à tête bois
	_build_pit(PIT_LOW_START, PIT_LOW_END, false)
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
	# Pas de fosse en haut (retour d'essai 2026-09-26) : butoirs bleus seuls
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

## Repère de pose extrapolé au-delà des bouts de ligne (la spline est bornée).
func _xf_at(s: float) -> Transform3D:
	var sc: float = clampf(s, 0.0, PNConstants.LENGTH)
	var xf: Transform3D = tunnel.transform_at(sc)
	xf.origin += (-xf.basis.z) * (s - sc)
	return xf


func _place(mi: MeshInstance3D, s: float, x: float, y: float) -> void:
	var xf: Transform3D = _xf_at(s)
	xf.origin += xf.basis.x * x + xf.basis.y * y
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _box(size: Vector3, mat: StandardMaterial3D, s: float, x: float, y: float, name: String = "Box") -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.name = name
	_place(mi, s, x, y)
	return mi


## Butoirs BLEUS (photos 095509 / 095443) : deux poutres-caissons bleues le
## long de la voie, tête cylindrique en bois face à la rame, au niveau du
## châssis. À la gare basse la rame a le nez vers −s, en haut vers +s.
func _build_bumper(s: float, is_low: bool) -> void:
	var blue: StandardMaterial3D = StandardMaterial3D.new()
	blue.albedo_color = Color(0.12, 0.32, 0.62)
	blue.roughness = 0.55
	blue.metallic = 0.3
	var wood: StandardMaterial3D = StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.30, 0.18)
	wood.roughness = 0.85
	var dir: float = -1.0 if is_low else 1.0      # sens vers l'extérieur de la ligne
	var y_axis: float = RAIL_HEAD_Y + 0.36
	for sx in [-0.85, 0.85]:
		_box(Vector3(0.30, 0.30, 2.40), blue, s + dir * 1.35, sx, y_axis, "Butoir")
		var head: MeshInstance3D = MeshInstance3D.new()
		var cm: CylinderMesh = CylinderMesh.new()
		cm.top_radius = 0.14
		cm.bottom_radius = 0.14
		cm.height = 0.32
		cm.radial_segments = 16
		cm.material = wood
		head.mesh = cm
		head.name = "TeteButoir"
		_place(head, s + dir * 0.10, sx, y_axis)
		head.rotation = head.rotation + Vector3(PI * 0.5, 0.0, 0.0)
		# pied
		_box(Vector3(0.36, 0.60, 0.30), blue, s + dir * 2.3, sx, y_axis - 0.35, "PiedButoir")


## Fosse sous la voie : fond en caillebotis, parois béton sombre, cornières
## de rive ; en haut, poulies de renvoi du câble (Ø 1,6 m) vers la machinerie.
func _build_pit(s0: float, s1: float, with_sheaves: bool) -> void:
	var grating: StandardMaterial3D = StandardMaterial3D.new()
	grating.albedo_color = Color(0.20, 0.21, 0.22)
	grating.roughness = 0.6
	grating.metallic = 0.5
	var concrete: StandardMaterial3D = StandardMaterial3D.new()
	concrete.albedo_color = Color(0.26, 0.25, 0.24)
	concrete.roughness = 0.95
	var steel: StandardMaterial3D = StandardMaterial3D.new()
	steel.albedo_color = Color(0.60, 0.61, 0.62)
	steel.roughness = 0.45
	steel.metallic = 0.7
	var iron: StandardMaterial3D = StandardMaterial3D.new()
	iron.albedo_color = Color(0.16, 0.16, 0.18)
	iron.roughness = 0.4
	iron.metallic = 0.9
	var length: float = s1 - s0
	var sc: float = (s0 + s1) * 0.5
	var y_bottom: float = FLOOR_Y_LOCAL - PIT_DEPTH
	_box(Vector3(3.0, 0.06, length), grating, sc, 0.0, y_bottom + 0.03, "FondFosse")
	for sx in [-1.5, 1.5]:
		_box(Vector3(0.16, PIT_DEPTH, length), concrete, sc, sx, y_bottom + PIT_DEPTH * 0.5, "ParoiFosse")
		_box(Vector3(0.08, 0.06, length), steel, sc, sx - signf(sx) * 0.04, FLOOR_Y_LOCAL + 0.03, "CorniereFosse")
	# rails sur poutres au-dessus de la fosse : deux longrines acier
	for sx in [-0.60, 0.60]:
		_box(Vector3(0.12, 0.22, length), iron, sc, sx, RAIL_HEAD_Y - 0.28, "LongrineFosse")
	if with_sheaves:
		# deux grandes poulies verticales (une par brin) + une petite
		for k in range(2):
			var sheave: MeshInstance3D = MeshInstance3D.new()
			var cm: CylinderMesh = CylinderMesh.new()
			cm.top_radius = 0.80
			cm.bottom_radius = 0.80
			cm.height = 0.12
			cm.radial_segments = 32
			cm.material = iron
			sheave.mesh = cm
			sheave.name = "PoulieRenvoi"
			var sx: float = -0.14 if k == 0 else 0.14
			_place(sheave, s0 + 2.0 + float(k) * 1.3, sx, y_bottom + 0.85)
			sheave.rotation = sheave.rotation + Vector3(0.0, 0.0, PI * 0.5)
			_box(Vector3(0.6, 0.10, 0.10), iron, s0 + 2.0 + float(k) * 1.3, 0.0, y_bottom + 0.85, "AxePoulie")
		var small: MeshInstance3D = MeshInstance3D.new()
		var sm: CylinderMesh = CylinderMesh.new()
		sm.top_radius = 0.45
		sm.bottom_radius = 0.45
		sm.height = 0.10
		sm.radial_segments = 24
		sm.material = iron
		small.mesh = sm
		_place(small, s0 + 4.6, 0.0, y_bottom + 0.50)
		small.rotation = small.rotation + Vector3(0.0, 0.0, PI * 0.5)
		# ruban « 1000 VOLTS » : petit repère jaune sur un brin
		var tape: StandardMaterial3D = StandardMaterial3D.new()
		tape.albedo_color = Color(0.95, 0.80, 0.10)
		_box(Vector3(0.05, 0.40, 0.05), tape, s0 + 1.2, -0.14, y_bottom + 0.9, "Ruban")
	else:
		# chaîne de sécurité jaune/noire tendue en travers, à hauteur de quai
		var chain: StandardMaterial3D = StandardMaterial3D.new()
		chain.albedo_color = Color(0.85, 0.75, 0.15)
		chain.roughness = 0.6
		for k in range(2):
			_box(Vector3(0.05, 0.80, 0.05), steel, s0 + 1.0, -1.35 + float(k) * 2.7, FLOOR_Y_LOCAL + 0.40, "PoteauChaine")
		_box(Vector3(2.7, 0.03, 0.03), chain, s0 + 1.0, 0.0, FLOOR_Y_LOCAL + 0.70, "Chaine")


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
