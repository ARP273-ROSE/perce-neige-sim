class_name TrackBuilder
extends Node3D
## Voie ferrée du funiculaire Perce-Neige : dalle béton, traverses,
## rails, sabot guide-câble central, câble Fatzer 52 mm.
##
## Le tout suit la spline générée par TunnelBuilder, posé sur le plancher
## local du tunnel (Y_local = floor_y_local par rapport au centre du ring).
##
## Performance :
##   - Rails + dalle + câble : mesh continu via SurfaceTool
##   - Traverses + sabots guide-câble : MultiMeshInstance3D
## Résultat : < 30 k vertices statiques + ~8 k instances légères.

# --- Paramètres géométriques ---------------------------------------------

@export var gauge_m: float = 1.20            # écartement rails (1200 mm réel)
@export var rail_head_width: float = 0.075   # largeur tête de rail (75 mm)
@export var rail_height: float = 0.172       # hauteur profil UIC-60 simplifié
@export var rail_web_width: float = 0.020    # âme rail
@export var rail_foot_width: float = 0.150   # patin

@export var floor_y_local: float = -1.35     # plancher dalle vs centre tunnel
@export var slab_thickness: float = 0.25     # épaisseur dalle béton
@export var slab_width: float = 3.20         # largeur dalle (déborde sous banquettes)

@export var sleeper_spacing: float = 0.60    # entraxe traverses (600 mm)
@export var sleeper_length: float = 1.80     # longueur traverse
@export var sleeper_width: float = 0.24      # largeur traverse
@export var sleeper_height: float = 0.16     # épaisseur traverse

@export var guide_spacing: float = 13.57     # entraxe RÉEL : 3474 m / 256 paires (source CFD)
@export var pulley_radius: float = 0.15      # rayon poulie/galet (300 mm)
@export var pulley_thickness: float = 0.08   # épaisseur galet
@export var pulley_pair_offset: float = 0.12 # décalage latéral de chaque poulie (entraxe 0.24m)
@export var bracket_width: float = 0.04      # épaisseur équerres
@export var bracket_span: float = 0.42       # écart entre équerres (contient les 2 poulies)
@export var bracket_height: float = 0.32     # hauteur équerres depuis socle
@export var base_plate_width: float = 0.52   # largeur socle béton (plus large pour la paire)
@export var base_plate_length: float = 0.16  # longueur socle (dans sens voie)
@export var base_plate_height: float = 0.08  # épaisseur socle

@export var cable_radius: float = 0.026      # rayon câble 52 mm
@export var cable_segments: int = 8          # segments radiaux
@export var cable_sample_spacing: float = 2.0  # spline sampling

@export var sampling_step: float = 0.5       # pas échantillonnage rails/dalle

var tunnel: TunnelBuilder = null

# Segments des 2 brins de câble (1 câble unique en boucle, 2 brins visibles).
# Structure : [{s_start: float, s_end: float, mesh: MeshInstance3D}, ...]
var cable_left_segments: Array = []    # brin aller — attaché à rame 1
var cable_right_segments: Array = []   # brin retour — attaché à rame 2
@export var cable_segment_length: float = 15.0  # longueur d'un segment mesh (m)

# Matériaux shader partagés entre tous les segments — on modifie les uniforms
# "cable_phase" directement dessus pour animer tous les segments simultanément.
var cable_left_material: ShaderMaterial = null
var cable_right_material: ShaderMaterial = null

# Phase accumulée du câble (en mètres). Croît avec le temps selon la vitesse
# de la rame. Pour le brin gauche (qui tient rame 1), cette phase compense le
# mouvement de rame 1 de sorte que les torons apparaissent FIXES dans le
# référentiel de la cabine. Pour le brin droite, la phase est opposée →
# les torons défilent à 2×v relative.
var _cable_phase_meters: float = 0.0


func build(t: TunnelBuilder) -> void:
	tunnel = t
	_build_slab()
	_build_rails()
	_build_sleepers()
	_build_guides()
	_build_cable()


# ---------------------------------------------------------------------------
# Dalle béton — découpée en 4 sections pour suivre les 2 tubes du passing loop
# ---------------------------------------------------------------------------

func _build_slab() -> void:
	var slab_mat: StandardMaterial3D = StandardMaterial3D.new()
	slab_mat.albedo_color = Color(0.38, 0.36, 0.33)
	slab_mat.roughness = 0.92
	slab_mat.metallic = 0.0
	slab_mat.uv1_scale = Vector3(6.0, 1.0, 1.0)

	# 3 sections, alignées avec les sections de tunnel.
	# La section "PassingChamber" est CENTRÉE et s'élargit sinusoïdalement
	# pour couvrir toute la largeur de la chambre, supportant la cabine
	# pendant qu'elle suit sa courbe latérale.
	_build_slab_section(slab_mat, 0.0, PNConstants.PASSING_START, 0.0, "SlabLow", false)
	_build_slab_section(slab_mat, PNConstants.PASSING_START, PNConstants.PASSING_END, 0.0, "SlabPassingChamber", true)
	_build_slab_section(slab_mat, PNConstants.PASSING_END, PNConstants.LENGTH, 0.0, "SlabHigh", false)


# Construit un tronçon de dalle entre s_start et s_end avec un offset latéral.
# `side` : 0 = pas de divergence (centré), -1/+1 = suit passing_loop_offset(s, side).
# `is_chamber` : true → la dalle s'élargit symétriquement (centrée) pour couvrir
# toute la largeur de la chambre tunnel ; demi-largeur croît de slab_width/2
# à slab_width/2 + abs(passing_loop_offset(s, 1.0)).
func _build_slab_section(
	mat: StandardMaterial3D, s_start: float, s_end: float,
	side: float, name: String, is_chamber: bool = false,
) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)

	var base_half_w: float = slab_width * 0.5
	var slab_top_y: float = floor_y_local + slab_thickness
	var slab_bot_y: float = floor_y_local

	var n_steps: int = maxi(1, int((s_end - s_start) / sampling_step))
	var step: float = (s_end - s_start) / float(n_steps)

	var prev_xform: Transform3D = tunnel.transform_at(s_start)
	var prev_off: float = _track_center_x(s_start, side)
	var prev_half_w: float = base_half_w
	if is_chamber:
		prev_half_w += absf(tunnel.passing_loop_offset(s_start, 1.0))
	for i in range(1, n_steps + 1):
		var s_cur: float = s_start + float(i) * step
		var cur_xform: Transform3D = tunnel.transform_at(s_cur)
		var cur_off: float = _track_center_x(s_cur, side)
		var cur_half_w: float = base_half_w
		if is_chamber:
			cur_half_w += absf(tunnel.passing_loop_offset(s_cur, 1.0))

		var p0: Vector3 = prev_xform.origin
		var p1: Vector3 = cur_xform.origin
		var r0: Vector3 = prev_xform.basis.x
		var r1: Vector3 = cur_xform.basis.x
		var u0: Vector3 = prev_xform.basis.y
		var u1: Vector3 = cur_xform.basis.y

		var v0: float = (s_cur - step)
		var v1: float = s_cur

		# Dessus
		_emit_quad_strip(
			st,
			_pt(p0, r0, u0, prev_off - prev_half_w, slab_top_y),
			_pt(p0, r0, u0, prev_off + prev_half_w, slab_top_y),
			_pt(p1, r1, u1, cur_off - cur_half_w, slab_top_y),
			_pt(p1, r1, u1, cur_off + cur_half_w, slab_top_y),
			Vector2(0.0, v0), Vector2(1.0, v0),
			Vector2(0.0, v1), Vector2(1.0, v1),
		)
		# Flanc gauche
		_emit_quad_strip(
			st,
			_pt(p0, r0, u0, prev_off - prev_half_w, slab_bot_y),
			_pt(p0, r0, u0, prev_off - prev_half_w, slab_top_y),
			_pt(p1, r1, u1, cur_off - cur_half_w, slab_bot_y),
			_pt(p1, r1, u1, cur_off - cur_half_w, slab_top_y),
			Vector2(0.0, v0), Vector2(0.25, v0),
			Vector2(0.0, v1), Vector2(0.25, v1),
		)
		# Flanc droite
		_emit_quad_strip(
			st,
			_pt(p0, r0, u0, prev_off + prev_half_w, slab_top_y),
			_pt(p0, r0, u0, prev_off + prev_half_w, slab_bot_y),
			_pt(p1, r1, u1, cur_off + cur_half_w, slab_top_y),
			_pt(p1, r1, u1, cur_off + cur_half_w, slab_bot_y),
			Vector2(0.75, v0), Vector2(1.0, v0),
			Vector2(0.75, v1), Vector2(1.0, v1),
		)

		prev_xform = cur_xform
		prev_off = cur_off
		prev_half_w = cur_half_w

	st.generate_normals()
	st.generate_tangents()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# Centre latéral d'une voie ferrée à la distance s.
# side = 0 → axe central (voie unique). side = ±1 → suit le tube correspondant.
func _track_center_x(s: float, side: float) -> float:
	if side == 0.0:
		return 0.0
	return tunnel.passing_loop_offset(s, side)


# ---------------------------------------------------------------------------
# Rails — aiguillage Abt :
#   - 2 rails extérieurs CONTINUS (s=[0, LENGTH]) qui s'écartent dans le loop
#     pour devenir les rails extérieurs des 2 voies.
#   - 2 rails intérieurs APPARAISSENT seulement dans le passing loop plat
#     [PASSING_START, PASSING_END]. Bouts francs (la rame outboard a des roues
#     à double flasque qui passent par-dessus les coupures).
# ---------------------------------------------------------------------------

func _build_rails() -> void:
	var rail_mat: StandardMaterial3D = StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.48, 0.46, 0.44)
	rail_mat.roughness = 0.45
	rail_mat.metallic = 0.85
	rail_mat.metallic_specular = 0.9

	var rail_top_mat: StandardMaterial3D = StandardMaterial3D.new()
	rail_top_mat.albedo_color = Color(0.78, 0.76, 0.72)
	rail_top_mat.roughness = 0.20
	rail_top_mat.metallic = 0.95
	rail_top_mat.metallic_specular = 1.0

	var hg: float = gauge_m * 0.5
	# Les 2 rails extérieurs (continus) suivent le tube correspondant ±hg
	_build_rail_strip(
		rail_mat, rail_top_mat, 0.0, PNConstants.LENGTH, -1.0, -hg, "RailFarLeft",
	)
	_build_rail_strip(
		rail_mat, rail_top_mat, 0.0, PNConstants.LENGTH, +1.0, +hg, "RailFarRight",
	)
	# Les 2 rails intérieurs s'étendent sur tout le passing loop incluant les
	# transitions [s_lo, s_hi] pour soutenir la roue intérieure de chaque cabine
	# pendant la transition (Abt switch frog : ces rails croisent les rails
	# extérieurs au milieu de la transition, à x=0).
	var s_lo: float = PNConstants.PASSING_START - tunnel.passing_transition
	var s_hi: float = PNConstants.PASSING_END + tunnel.passing_transition
	_build_rail_strip(
		rail_mat, rail_top_mat, s_lo, s_hi,
		-1.0, +hg, "RailInnerLeft",
	)
	_build_rail_strip(
		rail_mat, rail_top_mat, s_lo, s_hi,
		+1.0, -hg, "RailInnerRight",
	)


# Construit un rail entre s_start et s_end, x_local = passing_loop_offset(s, side) + hg_signed.
# (Si side==0, x_local = hg_signed → rail à x constant pour voie unique centrée.)
func _build_rail_strip(
	rail_mat: StandardMaterial3D, rail_top_mat: StandardMaterial3D,
	s_start: float, s_end: float, side: float, hg_signed: float, name: String,
) -> void:
	var st_rail: SurfaceTool = SurfaceTool.new()
	st_rail.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_rail.set_material(rail_mat)

	var st_top: SurfaceTool = SurfaceTool.new()
	st_top.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_top.set_material(rail_top_mat)

	# Offsets verticaux profil UIC-60 simplifié.
	# Le patin du rail repose sur le HAUT des traverses, pas dans la dalle.
	# Sleeper top = floor_y_local + slab_thickness + sleeper_height − 0.01
	# (le -0.01 = enfoncement de la traverse dans la dalle, cf _build_sleepers).
	var rail_base_y: float = floor_y_local + slab_thickness + sleeper_height - 0.01
	var rail_top_y: float = rail_base_y + rail_height

	var foot_y0: float = rail_base_y
	var foot_y1: float = rail_base_y + 0.035
	var foot_w: float = rail_foot_width * 0.5
	var web_y0: float = foot_y1
	var web_y1: float = rail_base_y + 0.140
	var web_w: float = rail_web_width * 0.5
	var head_y0: float = web_y1
	var head_y1: float = rail_top_y
	var head_w: float = rail_head_width * 0.5

	var n_steps: int = maxi(1, int((s_end - s_start) / sampling_step))
	var step: float = (s_end - s_start) / float(n_steps)

	var prev_xform: Transform3D = tunnel.transform_at(s_start)
	var prev_cx: float = _track_center_x(s_start, side) + hg_signed
	for i in range(1, n_steps + 1):
		var s_cur: float = s_start + float(i) * step
		var cur_xform: Transform3D = tunnel.transform_at(s_cur)
		var cur_cx: float = _track_center_x(s_cur, side) + hg_signed

		var p0: Vector3 = prev_xform.origin
		var p1: Vector3 = cur_xform.origin
		var r0: Vector3 = prev_xform.basis.x
		var r1: Vector3 = cur_xform.basis.x
		var u0: Vector3 = prev_xform.basis.y
		var u1: Vector3 = cur_xform.basis.y

		var v0: float = (s_cur - step)
		var v1: float = s_cur

		# Foot
		_emit_rail_step_xv(
			st_rail, p0, r0, u0, p1, r1, u1,
			prev_cx, cur_cx, foot_y0, foot_y1, foot_w, foot_w, v0, v1,
		)
		# Web
		_emit_rail_step_xv(
			st_rail, p0, r0, u0, p1, r1, u1,
			prev_cx, cur_cx, web_y0, web_y1, web_w, web_w, v0, v1,
		)
		# Head base
		_emit_rail_step_xv(
			st_rail, p0, r0, u0, p1, r1, u1,
			prev_cx, cur_cx, head_y0, head_y1 - 0.012, head_w, head_w, v0, v1,
		)
		# Head top (brillant)
		_emit_rail_step_xv(
			st_top, p0, r0, u0, p1, r1, u1,
			prev_cx, cur_cx, head_y1 - 0.012, head_y1, head_w, head_w, v0, v1,
		)

		prev_xform = cur_xform
		prev_cx = cur_cx

	st_rail.generate_normals()
	st_rail.generate_tangents()
	var mi_rail: MeshInstance3D = MeshInstance3D.new()
	mi_rail.name = name
	mi_rail.mesh = st_rail.commit()
	mi_rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi_rail)

	st_top.generate_normals()
	st_top.generate_tangents()
	var mi_top: MeshInstance3D = MeshInstance3D.new()
	mi_top.name = name + "Top"
	mi_top.mesh = st_top.commit()
	mi_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi_top)


# Variante de _emit_rail_step où prev_cx et cur_cx peuvent différer
# (rail qui dérive latéralement entre 2 cross-sections).
func _emit_rail_step_xv(
	st: SurfaceTool,
	p0: Vector3, r0: Vector3, u0: Vector3,
	p1: Vector3, r1: Vector3, u1: Vector3,
	cx_prev: float, cx_cur: float, y_lo: float, y_hi: float,
	w_lo: float, w_hi: float, v0: float, v1: float,
) -> void:
	var a00: Vector3 = _pt(p0, r0, u0, cx_prev - w_lo, y_lo)
	var a01: Vector3 = _pt(p0, r0, u0, cx_prev + w_lo, y_lo)
	var a10: Vector3 = _pt(p0, r0, u0, cx_prev + w_hi, y_hi)
	var a11: Vector3 = _pt(p0, r0, u0, cx_prev - w_hi, y_hi)
	var b00: Vector3 = _pt(p1, r1, u1, cx_cur - w_lo, y_lo)
	var b01: Vector3 = _pt(p1, r1, u1, cx_cur + w_lo, y_lo)
	var b10: Vector3 = _pt(p1, r1, u1, cx_cur + w_hi, y_hi)
	var b11: Vector3 = _pt(p1, r1, u1, cx_cur - w_hi, y_hi)
	# Face gauche
	_emit_quad_strip(
		st, a00, a11, b00, b11,
		Vector2(0.0, v0), Vector2(0.1, v0),
		Vector2(0.0, v1), Vector2(0.1, v1),
	)
	# Face droite
	_emit_quad_strip(
		st, a01, b01, a10, b10,
		Vector2(0.0, v0), Vector2(0.0, v1),
		Vector2(0.1, v0), Vector2(0.1, v1),
	)
	# Top
	_emit_quad_strip(
		st, a11, a10, b11, b10,
		Vector2(0.0, v0), Vector2(1.0, v0),
		Vector2(0.0, v1), Vector2(1.0, v1),
	)


# Aide : point monde à partir d'une base locale et d'offsets (right, up)
func _pt(origin: Vector3, right: Vector3, up: Vector3, dx: float, dy: float) -> Vector3:
	return origin + right * dx + up * dy


# Émet deux triangles CCW pour un quad (vu du dessus)
func _emit_quad_strip(
	st: SurfaceTool,
	p00: Vector3, p01: Vector3,
	p10: Vector3, p11: Vector3,
	uv00: Vector2, uv01: Vector2,
	uv10: Vector2, uv11: Vector2,
) -> void:
	st.set_uv(uv00); st.add_vertex(p00)
	st.set_uv(uv10); st.add_vertex(p10)
	st.set_uv(uv11); st.add_vertex(p11)

	st.set_uv(uv00); st.add_vertex(p00)
	st.set_uv(uv11); st.add_vertex(p11)
	st.set_uv(uv01); st.add_vertex(p01)


# Émet un "étage" de rail : extrusion rectangulaire simple (4 faces + top visible)
func _emit_rail_step(
	st: SurfaceTool,
	p0: Vector3, r0: Vector3, u0: Vector3,
	p1: Vector3, r1: Vector3, u1: Vector3,
	cx: float, y_lo: float, y_hi: float, w_lo: float, w_hi: float,
	v0: float, v1: float,
) -> void:
	# Coins des deux sections
	var a00: Vector3 = _pt(p0, r0, u0, cx - w_lo, y_lo)
	var a01: Vector3 = _pt(p0, r0, u0, cx + w_lo, y_lo)
	var a10: Vector3 = _pt(p0, r0, u0, cx + w_hi, y_hi)
	var a11: Vector3 = _pt(p0, r0, u0, cx - w_hi, y_hi)
	var b00: Vector3 = _pt(p1, r1, u1, cx - w_lo, y_lo)
	var b01: Vector3 = _pt(p1, r1, u1, cx + w_lo, y_lo)
	var b10: Vector3 = _pt(p1, r1, u1, cx + w_hi, y_hi)
	var b11: Vector3 = _pt(p1, r1, u1, cx - w_hi, y_hi)

	# Face gauche (cx - w)
	_emit_quad_strip(
		st, a00, a11, b00, b11,
		Vector2(0.0, v0), Vector2(0.1, v0),
		Vector2(0.0, v1), Vector2(0.1, v1),
	)
	# Face droite (cx + w)
	_emit_quad_strip(
		st, a01, b01, a10, b10,
		Vector2(0.0, v0), Vector2(0.0, v1),
		Vector2(0.1, v0), Vector2(0.1, v1),
	)
	# Face top (y_hi)
	_emit_quad_strip(
		st, a11, a10, b11, b10,
		Vector2(0.0, v0), Vector2(1.0, v0),
		Vector2(0.0, v1), Vector2(1.0, v1),
	)


# ---------------------------------------------------------------------------
# Traverses béton — MultiMeshInstance3D
# ---------------------------------------------------------------------------

func _build_sleepers() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.30, 0.28)
	mat.roughness = 0.95
	mat.metallic = 0.0

	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(sleeper_length, sleeper_height, sleeper_width)
	box.material = mat

	# Construit la liste des positions :
	# - Hors loop plat : 1 traverse centrée (x=0)
	# - Dans loop plat [PASSING_START, PASSING_END] : 2 traverses, une par voie,
	#   décalées par tunnel.passing_loop_offset(s, ±1) (qui vaut ±2.20m au cœur du loop).
	# Les zones de transition (15m de chaque côté) gardent une seule traverse centrée,
	# acceptable visuellement vu qu'on est en mouvement à 10 m/s.
	var positions: Array = []  # [{s: float, off: float}, ...]
	var n_total: int = int(PNConstants.LENGTH / sleeper_spacing)
	for i in range(n_total):
		var s: float = (float(i) + 0.5) * sleeper_spacing
		if s >= PNConstants.PASSING_START and s <= PNConstants.PASSING_END:
			positions.append({"s": s, "off": tunnel.passing_loop_offset(s, -1.0)})
			positions.append({"s": s, "off": tunnel.passing_loop_offset(s, +1.0)})
		else:
			positions.append({"s": s, "off": 0.0})

	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = positions.size()

	var y_center: float = floor_y_local + slab_thickness + sleeper_height * 0.5 - 0.01
	for i in range(positions.size()):
		var entry: Dictionary = positions[i]
		var xform: Transform3D = tunnel.transform_at(entry.s)
		var tr: Transform3D = xform
		tr.origin += xform.basis.y * y_center + xform.basis.x * entry.off
		mm.set_instance_transform(i, tr)

	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "Sleepers"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


# ---------------------------------------------------------------------------
# Guides câble réalistes — socle + équerres + poulie/galet rotatif
#
# Structure Von Roll : socle béton fixé au sol entre les rails, deux équerres
# acier qui remontent de part et d'autre, axe horizontal perpendiculaire à la
# voie entre les équerres, galet (poulie en fonte à gorge profilée) monté sur
# l'axe. Le câble passe PAR-DESSUS et repose en contact tangent sur le galet.
# Entraxe typique 3 à 5 m, galets ∅ 250-400 mm.
# ---------------------------------------------------------------------------

func _build_guides() -> void:
	var top_slab: float = floor_y_local + slab_thickness  # top de dalle

	# Hauteurs dans la base locale
	var y_base_lo: float = top_slab
	var y_base_hi: float = top_slab + base_plate_height
	var y_bracket_hi: float = y_base_hi + bracket_height
	# Axe poulie légèrement en-dessous du haut des équerres
	var y_pulley_axis: float = y_bracket_hi - pulley_radius * 0.35

	# Matériaux
	var concrete_mat: StandardMaterial3D = StandardMaterial3D.new()
	concrete_mat.albedo_color = Color(0.42, 0.40, 0.37)
	concrete_mat.roughness = 0.92
	concrete_mat.metallic = 0.0

	var steel_mat: StandardMaterial3D = StandardMaterial3D.new()
	steel_mat.albedo_color = Color(0.28, 0.28, 0.30)
	steel_mat.roughness = 0.45
	steel_mat.metallic = 0.85

	var iron_mat: StandardMaterial3D = StandardMaterial3D.new()
	iron_mat.albedo_color = Color(0.18, 0.18, 0.20)
	iron_mat.roughness = 0.35
	iron_mat.metallic = 0.95

	# --- Socle béton -----------------------------------------------------
	var base_mesh: BoxMesh = BoxMesh.new()
	base_mesh.size = Vector3(base_plate_width, base_plate_height, base_plate_length)
	base_mesh.material = concrete_mat

	# --- Paire d'équerres : ArrayMesh composite (2 boxes) -----------------
	var bracket_mesh: ArrayMesh = _build_bracket_pair_mesh(
		bracket_width, bracket_height, bracket_span, pulley_thickness * 1.3, steel_mat,
	)

	# --- Galet/poulie : CylinderMesh (tourné axe horizontal perpendiculaire voie) ---
	# Gorge profilée approximée par un mesh simple ; l'épaisseur réelle du galet
	# est plus importante que la gorge qui est à peine visible à cette échelle.
	var pulley_mesh: CylinderMesh = CylinderMesh.new()
	pulley_mesh.top_radius = pulley_radius
	pulley_mesh.bottom_radius = pulley_radius
	pulley_mesh.height = pulley_thickness
	pulley_mesh.radial_segments = 20
	pulley_mesh.rings = 1
	pulley_mesh.material = iron_mat

	# --- Axe central visible entre les 2 poulies (petit cylindre) --------
	var axle_mesh: CylinderMesh = CylinderMesh.new()
	axle_mesh.top_radius = 0.020
	axle_mesh.bottom_radius = 0.020
	axle_mesh.height = bracket_span
	axle_mesh.radial_segments = 10
	axle_mesh.rings = 1
	axle_mesh.material = iron_mat

	# Construit la liste des positions des guides :
	# - Hors loop : 1 guide centré (axe x=0) avec 2 poulies (1 par brin de câble)
	# - Dans loop [PASSING_START, PASSING_END] : 2 guides séparés (1 par voie),
	#   chacun avec UNE SEULE poulie (la rame opposée ne passe jamais par cette voie)
	#
	# Format entry : {s, off, has_pulley_a, has_pulley_b}
	#   pulley A = côté -pulley_pair_offset (cable_left brin)
	#   pulley B = côté +pulley_pair_offset (cable_right brin)
	var positions: Array = []
	var n_total: int = int(PNConstants.LENGTH / guide_spacing)
	for i in range(n_total):
		var s: float = (float(i) + 0.5) * guide_spacing
		if s >= PNConstants.PASSING_START and s <= PNConstants.PASSING_END:
			# Voie gauche (rame 1) : seul le brin gauche (cable_left) passe → poulie A
			positions.append({
				"s": s, "off": tunnel.passing_loop_offset(s, -1.0),
				"has_pulley_a": true, "has_pulley_b": false,
			})
			# Voie droite (rame 2) : seul le brin droite (cable_right) passe → poulie B
			positions.append({
				"s": s, "off": tunnel.passing_loop_offset(s, +1.0),
				"has_pulley_a": false, "has_pulley_b": true,
			})
		else:
			# Hors loop : voie unique, les 2 brins passent → 2 poulies
			positions.append({
				"s": s, "off": 0.0,
				"has_pulley_a": true, "has_pulley_b": true,
			})

	var n: int = positions.size()
	# Compte combien de poulies A et B il y a en tout
	var n_pa: int = 0
	var n_pb: int = 0
	for entry in positions:
		if entry.has_pulley_a:
			n_pa += 1
		if entry.has_pulley_b:
			n_pb += 1

	# --- Instances : 5 MultiMesh (socle, équerres, axe : tous; pulley A et B filtrés) ---
	var mm_base: MultiMesh = MultiMesh.new()
	mm_base.transform_format = MultiMesh.TRANSFORM_3D
	mm_base.mesh = base_mesh
	mm_base.instance_count = n

	var mm_brackets: MultiMesh = MultiMesh.new()
	mm_brackets.transform_format = MultiMesh.TRANSFORM_3D
	mm_brackets.mesh = bracket_mesh
	mm_brackets.instance_count = n

	var mm_pulley_a: MultiMesh = MultiMesh.new()
	mm_pulley_a.transform_format = MultiMesh.TRANSFORM_3D
	mm_pulley_a.mesh = pulley_mesh
	mm_pulley_a.instance_count = n_pa

	var mm_pulley_b: MultiMesh = MultiMesh.new()
	mm_pulley_b.transform_format = MultiMesh.TRANSFORM_3D
	mm_pulley_b.mesh = pulley_mesh
	mm_pulley_b.instance_count = n_pb

	var mm_axle: MultiMesh = MultiMesh.new()
	mm_axle.transform_format = MultiMesh.TRANSFORM_3D
	mm_axle.mesh = axle_mesh
	mm_axle.instance_count = n

	var y_base_center: float = (y_base_lo + y_base_hi) * 0.5
	var y_bracket_center: float = y_base_hi + bracket_height * 0.5

	# Rotation 90° autour de Z local : axe cylindre Y → axe monde perpendiculaire voie
	var rot90: Basis = Basis(Vector3(0, 0, 1), PI * 0.5)

	var idx_pa: int = 0
	var idx_pb: int = 0
	for i in range(n):
		var entry: Dictionary = positions[i]
		var xform: Transform3D = tunnel.transform_at(entry.s)
		var right: Vector3 = xform.basis.x
		var up: Vector3 = xform.basis.y
		var lat_offset: Vector3 = right * entry.off

		# Bank (cant) : incline tout l'ensemble autour de l'axe forward selon
		# la courbure horizontale locale. C'est ce qui permet au câble de
		# "tourner" en horizontal — sans bank, les poulies restent strictement
		# horizontales et le câble rentrerait dans le flanc des poulies.
		var bank_rad: float = _heading_bank_at(entry.s)
		var forward_world: Vector3 = -xform.basis.z   # = +tangent en monde
		var banked_basis: Basis = xform.basis.rotated(forward_world.normalized(), bank_rad)
		var banked_right: Vector3 = banked_basis.x
		var banked_up: Vector3 = banked_basis.y
		var banked_lat: Vector3 = banked_right * entry.off

		# Socle + équerres : centrés sur axe voie, avec bank
		var tr_base: Transform3D = Transform3D(banked_basis, xform.origin)
		tr_base.origin += banked_up * y_base_center + banked_lat
		mm_base.set_instance_transform(i, tr_base)

		var tr_br: Transform3D = Transform3D(banked_basis, xform.origin)
		tr_br.origin += banked_up * y_bracket_center + banked_lat
		mm_brackets.set_instance_transform(i, tr_br)

		# Poulie A (côté gauche du guide) — uniquement si has_pulley_a
		if entry.has_pulley_a:
			var tr_pa: Transform3D = Transform3D(banked_basis, xform.origin)
			tr_pa.origin += banked_up * y_pulley_axis - banked_right * pulley_pair_offset + banked_lat
			tr_pa.basis = tr_pa.basis * rot90
			mm_pulley_a.set_instance_transform(idx_pa, tr_pa)
			idx_pa += 1

		# Poulie B (côté droite du guide) — uniquement si has_pulley_b
		if entry.has_pulley_b:
			var tr_pb: Transform3D = Transform3D(banked_basis, xform.origin)
			tr_pb.origin += banked_up * y_pulley_axis + banked_right * pulley_pair_offset + banked_lat
			tr_pb.basis = tr_pb.basis * rot90
			mm_pulley_b.set_instance_transform(idx_pb, tr_pb)
			idx_pb += 1

		# Axe central horizontal entre les équerres
		var tr_ax: Transform3D = Transform3D(banked_basis, xform.origin)
		tr_ax.origin += banked_up * y_pulley_axis + banked_lat
		tr_ax.basis = tr_ax.basis * rot90
		mm_axle.set_instance_transform(i, tr_ax)

	var n_base: MultiMeshInstance3D = MultiMeshInstance3D.new()
	n_base.name = "GuideBases"
	n_base.multimesh = mm_base
	n_base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n_base)

	var n_br: MultiMeshInstance3D = MultiMeshInstance3D.new()
	n_br.name = "GuideBrackets"
	n_br.multimesh = mm_brackets
	n_br.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n_br)

	var node_pa: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node_pa.name = "GuidePulleysA"
	node_pa.multimesh = mm_pulley_a
	node_pa.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node_pa)

	var node_pb: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node_pb.name = "GuidePulleysB"
	node_pb.multimesh = mm_pulley_b
	node_pb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node_pb)

	var n_ax: MultiMeshInstance3D = MultiMeshInstance3D.new()
	n_ax.name = "GuideAxles"
	n_ax.multimesh = mm_axle
	n_ax.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n_ax)

	# Expose la hauteur de câble pour _build_cable()
	_cable_top_y = y_pulley_axis + pulley_radius


# Bank (cant) angle pour un support de poulie à la distance s.
# Calculé depuis la courbure horizontale locale (taux de changement du heading).
# Permet aux poulies d'incliner DANS LE BON SENS dans les virages :
#   - virage à droite (heading augmente vers est/sud) → côté droit BAS, gauche HAUT
#   - le câble glisse vers l'intérieur (côté droit) du virage → centripète
#   - rotation autour de forward : signe NÉGATIF pour heading_rate positif
# Approximation centrifuge : bank = atan(v² · κ / g), amplifié pour visibilité.
func _heading_bank_at(s: float) -> float:
	var ds: float = 5.0
	var h_prev: float = SlopeProfile.heading_at(s - ds)
	var h_next: float = SlopeProfile.heading_at(s + ds)
	var heading_rate_rad_m: float = deg_to_rad(h_next - h_prev) / (2.0 * ds)
	var v_assumed: float = 12.0   # m/s — vitesse plafond pour calcul du bank
	var bank_natural: float = atan(v_assumed * v_assumed * heading_rate_rad_m / 9.80665)
	# Signe inversé : la rotation positive autour de forward lève le côté droit,
	# mais pour un virage à droite (heading_rate>0) on veut lever le côté GAUCHE
	# (banking centripète : la roue extérieure plus haut que l'intérieure).
	# Amplifié × 4 pour rendre visible (~3° physique → ~12° visuel)
	var bank_visual: float = -bank_natural * 4.0
	# Sécurité : limite à ±15°
	return clampf(bank_visual, -0.262, 0.262)


# Construit un ArrayMesh composite de 2 équerres verticales séparées par
# bracket_span (espace pour l'axe/galet). Thickness = largeur dans le sens voie.
func _build_bracket_pair_mesh(
	w: float, h: float, span: float, thickness: float, mat: StandardMaterial3D,
) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)

	# Demi-entre-équerres : bracket centrés à ±(span/2 + w/2) en X local
	var dx_center: float = span * 0.5 + w * 0.5
	for side in [-1.0, 1.0]:
		var cx: float = side * dx_center
		var x0: float = cx - w * 0.5
		var x1: float = cx + w * 0.5
		var y0: float = -h * 0.5
		var y1: float = h * 0.5
		var z0: float = -thickness * 0.5
		var z1: float = thickness * 0.5
		_box_faces(st, x0, y0, z0, x1, y1, z1)

	st.generate_normals()
	st.generate_tangents()
	return st.commit()


# Émet les 6 faces d'une box avec UVs triviaux
func _box_faces(
	st: SurfaceTool,
	x0: float, y0: float, z0: float, x1: float, y1: float, z1: float,
) -> void:
	# 8 coins
	var p000: Vector3 = Vector3(x0, y0, z0)
	var p100: Vector3 = Vector3(x1, y0, z0)
	var p010: Vector3 = Vector3(x0, y1, z0)
	var p110: Vector3 = Vector3(x1, y1, z0)
	var p001: Vector3 = Vector3(x0, y0, z1)
	var p101: Vector3 = Vector3(x1, y0, z1)
	var p011: Vector3 = Vector3(x0, y1, z1)
	var p111: Vector3 = Vector3(x1, y1, z1)
	# 6 faces (CCW vu de l'extérieur)
	_face(st, p000, p010, p110, p100)   # front (z=z0)
	_face(st, p101, p111, p011, p001)   # back  (z=z1)
	_face(st, p001, p011, p010, p000)   # left  (x=x0)
	_face(st, p100, p110, p111, p101)   # right (x=x1)
	_face(st, p010, p011, p111, p110)   # top   (y=y1)
	_face(st, p000, p100, p101, p001)   # bot   (y=y0)


func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 0)); st.add_vertex(b)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_uv(Vector2(0, 1)); st.add_vertex(d)


var _cable_top_y: float = -0.6  # fixé par _build_guides(), utilisé par _build_cable()


# ---------------------------------------------------------------------------
# Câble Fatzer 52 mm unique en boucle continue — 2 brins visibles côte à côte
# entre les rails. Le brin gauche part de l'attache culot de rame 1 vers la
# poulie motrice en haut ; le brin droit repart de la poulie vers l'attache
# culot de rame 2. Chaque brin est découpé en segments pour permettre un
# masquage dynamique selon la position des rames (le brin n'existe que entre
# la rame qu'il tire et la poulie en haut).
# ---------------------------------------------------------------------------

func _build_cable() -> void:
	# ShaderMaterial pour chaque brin — bandes hélicoïdales animées via
	# l'uniform cable_phase. Les 2 matériaux sont distincts pour pouvoir
	# animer les 2 brins avec des phases opposées (brin gauche fixe vs
	# brin droite défilant à 2×v).
	var shader: Shader = load("res://scripts/cable_shader.gdshader")

	cable_left_material = ShaderMaterial.new()
	cable_left_material.shader = shader
	cable_left_material.set_shader_parameter("cable_phase", 0.0)

	cable_right_material = ShaderMaterial.new()
	cable_right_material.shader = shader
	cable_right_material.set_shader_parameter("cable_phase", 0.0)

	# Hauteur câble : tangent au sommet des poulies
	var y_center: float = _cable_top_y + cable_radius

	cable_left_segments.clear()
	cable_right_segments.clear()

	var total_len: float = PNConstants.LENGTH
	var n_seg: int = int(ceil(total_len / cable_segment_length))
	for i in range(n_seg):
		var s_start: float = float(i) * cable_segment_length
		var s_end: float = minf(s_start + cable_segment_length, total_len)
		var mi_left: MeshInstance3D = _build_cable_segment(
			cable_left_material, y_center, -1.0, -pulley_pair_offset, s_start, s_end,
			"CableLeft_%d" % i,
		)
		cable_left_segments.append({"s_start": s_start, "s_end": s_end, "mesh": mi_left})
		var mi_right: MeshInstance3D = _build_cable_segment(
			cable_right_material, y_center, +1.0, +pulley_pair_offset, s_start, s_end,
			"CableRight_%d" % i,
		)
		cable_right_segments.append({"s_start": s_start, "s_end": s_end, "mesh": mi_right})


# Génère un segment de câble (tube) entre s_start et s_end, décalé latéralement.
# `side` : -1 pour brin gauche (suit voie 1 dans le passing loop, x = pl_offset + base_x),
#          +1 pour brin droite (suit voie 2). 0 pour rester centré (test).
# `base_offset_x` : offset additionnel par rapport au centre de la voie suivie
#  (typiquement ∓pulley_pair_offset pour rester contre le bord intérieur).
func _build_cable_segment(
	mat: Material, y_center: float, side: float, base_offset_x: float,
	s_start: float, s_end: float, name: String,
) -> MeshInstance3D:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)

	var seg_len: float = s_end - s_start
	var n_steps: int = maxi(1, int(seg_len / cable_sample_spacing))
	var samples: Array = []
	var bases_r: Array = []
	var bases_u: Array = []
	for i in range(n_steps + 1):
		var s: float = s_start + float(i) / float(n_steps) * seg_len
		var xform: Transform3D = tunnel.transform_at(s)
		var x_off: float = base_offset_x
		if side != 0.0:
			x_off += tunnel.passing_loop_offset(s, side)
		samples.append(xform.origin + xform.basis.y * y_center + xform.basis.x * x_off)
		bases_r.append(xform.basis.x)
		bases_u.append(xform.basis.y)

	for i in range(n_steps):
		var c0: Vector3 = samples[i]
		var c1: Vector3 = samples[i + 1]
		var r0: Vector3 = bases_r[i]
		var r1: Vector3 = bases_r[i + 1]
		var u0: Vector3 = bases_u[i]
		var u1: Vector3 = bases_u[i + 1]

		for k in range(cable_segments):
			var a0: float = float(k) / float(cable_segments) * TAU
			var a1: float = float(k + 1) / float(cable_segments) * TAU
			var cos0: float = cos(a0)
			var sin0: float = sin(a0)
			var cos1: float = cos(a1)
			var sin1: float = sin(a1)

			var p00: Vector3 = c0 + r0 * cos0 * cable_radius + u0 * sin0 * cable_radius
			var p01: Vector3 = c0 + r0 * cos1 * cable_radius + u0 * sin1 * cable_radius
			var p10: Vector3 = c1 + r1 * cos0 * cable_radius + u1 * sin0 * cable_radius
			var p11: Vector3 = c1 + r1 * cos1 * cable_radius + u1 * sin1 * cable_radius

			var u0_uv: float = float(k) / float(cable_segments)
			var u1_uv: float = float(k + 1) / float(cable_segments)
			# UV.y = distance absolue le long du câble × 2 (facteur 0.5 = uv_y_to_meters
			# côté shader). On se base sur s_start pour garder la continuité entre
			# segments : le shader voit une phase d'hélice continue.
			var v0_uv: float = (s_start + float(i) * seg_len / float(n_steps)) * 2.0
			var v1_uv: float = (s_start + float(i + 1) * seg_len / float(n_steps)) * 2.0

			st.set_uv(Vector2(u0_uv, v0_uv)); st.add_vertex(p00)
			st.set_uv(Vector2(u0_uv, v1_uv)); st.add_vertex(p10)
			st.set_uv(Vector2(u1_uv, v1_uv)); st.add_vertex(p11)

			st.set_uv(Vector2(u0_uv, v0_uv)); st.add_vertex(p00)
			st.set_uv(Vector2(u1_uv, v1_uv)); st.add_vertex(p11)
			st.set_uv(Vector2(u1_uv, v0_uv)); st.add_vertex(p01)

	st.generate_normals()
	st.generate_tangents()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# ---------------------------------------------------------------------------
# Masquage dynamique des brins de câble.
# Brin gauche (aller, tire rame 1) visible entre s_rame1 et LENGTH.
# Brin droit (retour, tire rame 2) visible entre s_rame2 et LENGTH,
# avec s_rame2 = LENGTH - s_rame1 (positions symétriques des 2 cabines).
# ---------------------------------------------------------------------------

func update_cable_visibility(s_rame1: float) -> void:
	var s_rame2: float = PNConstants.LENGTH - s_rame1
	for seg in cable_left_segments:
		# Segment visible si une partie est au-dessus (en amont) de rame 1
		seg.mesh.visible = seg.s_end >= s_rame1
	for seg in cable_right_segments:
		seg.mesh.visible = seg.s_end >= s_rame2


# Animation des torons. `v_rame1` est la vitesse SIGNÉE de rame 1 (m/s) dans
# le sens du trajet (+ = montée, − = descente). `delta` = intervalle temps.
#
# Principe : le câble est tiré à la vitesse v_rame1 par la poulie motrice en
# haut. Dans le référentiel du sol, les points du brin gauche se déplacent
# à +v_rame1 le long du câble (vers la poulie). Ceux du brin droite se
# déplacent à −v_rame1 (depuis la poulie vers rame 2 qui descend à −v_rame1).
#
# En référentiel rame 1 (qui se déplace à +v_rame1) :
#   - Brin gauche : mouvement relatif = +v_rame1 − (+v_rame1) = 0 → toronnage fixe
#   - Brin droite : mouvement relatif = −v_rame1 − (+v_rame1) = −2×v_rame1 → défile
#
# Pour le shader : `cable_phase` représente un offset absolu qu'on soustrait à
# UV.y. Pour que le brin gauche apparaisse fixe par rapport à rame 1 (qui est
# elle-même à la position s_rame1), on fixe cable_phase(gauche) = s_rame1.
# Pour le brin droite, on fait l'opposé : cable_phase(droite) = −s_rame1.
# (La phase absolue s'annule pour rame 1 sur le brin gauche, et le brin droite
# défile au double du s_rame1 relatif.)
func update_cable_phase(s_rame1: float, _v_rame1: float, _delta: float) -> void:
	if cable_left_material == null or cable_right_material == null:
		return
	cable_left_material.set_shader_parameter("cable_phase", s_rame1)
	cable_right_material.set_shader_parameter("cable_phase", -s_rame1)
