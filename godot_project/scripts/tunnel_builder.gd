class_name TunnelBuilder
extends Node3D
## Génère le mesh 3D du tunnel Perce-Neige via SurfaceTool.
##
## Le tunnel suit la spline calculée par SlopeProfile.build_path_points()
## (gradient + courbes horizontales). Section circulaire sur toute la
## longueur pour le MVP ; extrémités horseshoe à ajouter en v2.
##
## Un ring tous les 3 m × 20 vertices = ~23k vertices, très léger.

@export var ring_spacing: float = 3.0       # distance entre rings (m)
@export var ring_segments: int = 20          # vertices par ring
@export var tunnel_radius: float = 1.95      # rayon intérieur (m)
@export var show_debug_path: bool = false    # afficher la spline en wireframe

# Horseshoe (tunnel carré cut-and-cover aux portails)
@export var horseshoe_half_width: float = 2.05   # demi-largeur rectangle
@export var horseshoe_half_height: float = 2.05  # demi-hauteur rectangle
@export var horseshoe_transition: float = 20.0   # longueur de blend circular ↔ horseshoe

# Passing loop (boucle de croisement au milieu du tunnel)
# Géométrie réelle aiguillage Abt : courbe sinusoïdale continue symétrique
# entre PASSING_START et PASSING_END. Pas de section droite intermédiaire.
# offset(s) = ±MAX × sin(π × (s − PASS_START) / (PASS_END − PASS_START))
@export var passing_offset_max: float = 3.50     # décalage latéral PEAK au milieu du loop (m)
@export var passing_transition: float = 0.0      # plus utilisé (gardé pour compat)

var path_points: Array = []                  # Vector3[] — positions monde
var path_tangents: Array = []                # Vector3[] — direction locale
var path_curve: Curve3D = null               # spline Catmull-Rom pour sampling smooth


func _ready() -> void:
	_build()


func _build() -> void:
	# Génère les points de la spline
	path_points = SlopeProfile.build_path_points(ring_spacing)
	_compute_tangents()
	_build_curve3d()

	# Matériau béton tunnel — CULL_DISABLED pour voir l'intérieur
	# quel que soit le winding des triangles
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.42, 0.38)
	mat.roughness = 0.88
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.uv1_scale = Vector3(4.0, 2.0, 1.0)

	# 3 sections — aiguillage Abt en CHAMBRE CONTINUE.
	# Schéma vu de dessus (lentille / vesica) :
	#
	#                          ___________________
	#                       _-                     -_
	#  ____________________/                         \____________________
	#  TunnelLow             TunnelPassingChamber             TunnelHigh
	#  ____________________\                         /____________________
	#                       -_                     _-
	#                          ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
	#                       ↑                       ↑
	#                  PASSING_START            PASSING_END
	#
	# La chambre s'élargit sinusoïdalement (rayon = tunnel_radius + |offset(s)|),
	# atteint son rayon max au milieu (1.95 + 3.50 = 5.45m), et se referme
	# proprement aux extrémités (jonction continue avec la voie unique).
	# Les 2 voies sont des courbes continues à l'intérieur de cette chambre.
	_build_tunnel_section(mat, 0.0, PNConstants.PASSING_START, 0.0, "TunnelLow", false)
	_build_tunnel_section(mat, PNConstants.PASSING_START, PNConstants.PASSING_END, 0.0, "TunnelPassingChamber", true)
	_build_tunnel_section(mat, PNConstants.PASSING_END, PNConstants.LENGTH, 0.0, "TunnelHigh", false)

	if show_debug_path:
		_draw_debug_path()


# Construit un tronçon de tunnel entre s_start et s_end.
# `side` : 0 = pas de divergence (tube unique centré),
#          -1 ou +1 = utilise passing_loop_offset(s, side) qui smoothstep
#          de 0 jusqu'à ±passing_offset_max dans le passing loop.
# `is_chamber` : true → la section est une chambre élargie (entrée/sortie passing
#   loop). side doit valoir 0 (centré). Le rayon est augmenté de
#   abs(passing_loop_offset(s, 1.0)), ce qui fait croître la chambre du rayon
#   standard à `tunnel_radius + passing_offset_max` au bord du loop plat.
func _build_tunnel_section(
	mat: StandardMaterial3D, s_start: float, s_end: float,
	side: float, name: String, is_chamber: bool = false,
) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)

	# Indices de rings encadrants (on prend le ring juste avant s_start et juste
	# après s_end pour assurer une fermeture visuelle aux extrémités)
	var n_rings_total: int = path_points.size()
	var idx_start: int = clampi(int(s_start / ring_spacing), 0, n_rings_total - 1)
	var idx_end: int = clampi(int(ceil(s_end / ring_spacing)), idx_start + 1, n_rings_total - 1)

	for i in range(idx_start + 1, idx_end + 1):
		var prev_idx: int = i - 1
		var s_cur: float = float(i) * ring_spacing
		var s_prev: float = float(prev_idx) * ring_spacing

		# Clamp aux bornes de la section (pour les rings au bord)
		var cur_xform: Transform3D = tunnel_xform_raw(float(i))
		var prev_xform: Transform3D = tunnel_xform_raw(float(prev_idx))

		# Applique l'offset latéral (divergence des tubes du passing loop)
		var cur_off: float = 0.0
		var prev_off: float = 0.0
		if side != 0.0:
			cur_off = passing_loop_offset(s_cur, side)
			prev_off = passing_loop_offset(s_prev, side)
		var cur_center: Vector3 = cur_xform.origin + cur_xform.basis.x * cur_off
		var prev_center: Vector3 = prev_xform.origin + prev_xform.basis.x * prev_off
		var cur_right: Vector3 = cur_xform.basis.x
		var cur_up: Vector3 = cur_xform.basis.y
		var prev_right: Vector3 = prev_xform.basis.x
		var prev_up: Vector3 = prev_xform.basis.y

		var cur_radius: float = _radius_at(s_cur)
		var prev_radius: float = _radius_at(s_prev)
		var cur_blend: float = _horseshoe_blend_at(s_cur)
		var prev_blend: float = _horseshoe_blend_at(s_prev)
		# En mode chambre élargie : le rayon s'augmente de |passing_loop_offset(s)|,
		# qui croît smoothement de 0 (bord externe de la transition) à 2.20m
		# (bord interne, jonction avec le loop plat). Le horseshoe est désactivé
		# dans la chambre (uniquement circular pour avoir une jonction propre).
		if is_chamber:
			cur_radius += absf(passing_loop_offset(s_cur, 1.0))
			prev_radius += absf(passing_loop_offset(s_prev, 1.0))
			cur_blend = 0.0
			prev_blend = 0.0

		for k in range(ring_segments):
			var prev_0: Vector2 = _profile_xy(k, ring_segments, prev_radius, prev_blend)
			var prev_1: Vector2 = _profile_xy(k + 1, ring_segments, prev_radius, prev_blend)
			var cur_0: Vector2 = _profile_xy(k, ring_segments, cur_radius, cur_blend)
			var cur_1: Vector2 = _profile_xy(k + 1, ring_segments, cur_radius, cur_blend)

			var p_prev_0: Vector3 = prev_center + prev_right * prev_0.x + prev_up * prev_0.y
			var p_prev_1: Vector3 = prev_center + prev_right * prev_1.x + prev_up * prev_1.y
			var p_cur_0: Vector3 = cur_center + cur_right * cur_0.x + cur_up * cur_0.y
			var p_cur_1: Vector3 = cur_center + cur_right * cur_1.x + cur_up * cur_1.y

			var u0: float = float(k) / float(ring_segments)
			var u1: float = float(k + 1) / float(ring_segments)
			var v0: float = s_prev / 10.0
			var v1: float = s_cur / 10.0

			st.set_uv(Vector2(u0, v0)); st.add_vertex(p_prev_0)
			st.set_uv(Vector2(u0, v1)); st.add_vertex(p_cur_0)
			st.set_uv(Vector2(u1, v1)); st.add_vertex(p_cur_1)

			st.set_uv(Vector2(u0, v0)); st.add_vertex(p_prev_0)
			st.set_uv(Vector2(u1, v1)); st.add_vertex(p_cur_1)
			st.set_uv(Vector2(u1, v0)); st.add_vertex(p_prev_1)

	st.generate_normals()
	st.generate_tangents()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# Récupère la base locale (right, up, -tangent) au ring d'index idx (float
# accepté pour sampling intermédiaire).
func tunnel_xform_raw(idx_f: float) -> Transform3D:
	var n: int = path_points.size()
	var idx: int = clampi(int(idx_f), 0, n - 2)
	var k: float = idx_f - float(idx)
	var p0: Vector3 = path_points[idx]
	var p1: Vector3 = path_points[idx + 1]
	var pos: Vector3 = p0.lerp(p1, k)
	var tangent: Vector3 = (p1 - p0).normalized()
	var world_up: Vector3 = Vector3.UP
	var right: Vector3 = tangent.cross(world_up).normalized()
	if right.length() < 0.01:
		right = Vector3.RIGHT
	var up: Vector3 = right.cross(tangent).normalized()
	var t: Transform3D = Transform3D()
	t.basis = Basis(right, up, -tangent)
	t.origin = pos
	return t


func _compute_tangents() -> void:
	path_tangents.clear()
	var n: int = path_points.size()
	for i in range(n):
		var t: Vector3
		if i == 0:
			t = (path_points[1] - path_points[0]).normalized()
		elif i == n - 1:
			t = (path_points[n - 1] - path_points[n - 2]).normalized()
		else:
			t = (path_points[i + 1] - path_points[i - 1]).normalized()
		path_tangents.append(t)


func _build_curve3d() -> void:
	# Construit un Curve3D Catmull-Rom à partir de path_points.
	#
	# IMPORTANT : Curve3D.add_point(pos) par défaut fixe les handles in/out à
	# (0,0,0), ce qui transforme la spline en segments rectilignes — ce qui
	# donne exactement le tressautement de caméra observé dans les virages.
	# On doit explicitement fournir les tangentes Catmull-Rom (moyennée sur
	# les voisins) pour obtenir une vraie courbe C1 continue.
	path_curve = Curve3D.new()
	path_curve.bake_interval = 0.5
	var n: int = path_points.size()
	for i in range(n):
		var p: Vector3 = path_points[i]
		var p_prev: Vector3 = path_points[maxi(i - 1, 0)]
		var p_next: Vector3 = path_points[mini(i + 1, n - 1)]
		# Tangente Catmull-Rom (facteur 0.33 pour adoucir la courbure,
		# Catmull-Rom pur = 0.5 mais sur-réactif aux points non-uniformes).
		var tangent: Vector3 = (p_next - p_prev) * 0.33
		path_curve.add_point(p, -tangent, tangent)


func _radius_at(s: float) -> float:
	# Rayon de référence — utilisé pour le profil circular.
	# Le profil horseshoe a sa propre demi-largeur/hauteur, indépendante.
	return tunnel_radius


func _horseshoe_blend_at(s: float) -> float:
	# Retourne 0.0 = full circular, 1.0 = full horseshoe.
	# Transitions smooth autour de s=257 (portail bas) et s=3420 (portail haut).
	var lo_end: float = PNConstants.SQUARE_SECTION_LOW_END      # 257
	var hi_start: float = PNConstants.SQUARE_SECTION_HIGH_START # 3420
	var t: float = horseshoe_transition
	if s <= lo_end - t:
		return 1.0
	if s <= lo_end:
		var k: float = (lo_end - s) / t
		return smoothstep(0.0, 1.0, k)
	if s >= hi_start + t:
		return 1.0
	if s >= hi_start:
		var k2: float = (s - hi_start) / t
		return smoothstep(0.0, 1.0, k2)
	return 0.0


# Point du profil à u ∈ [0, 1] (progression le long du contour de la section).
# u=0 → (R, 0) à droite, parcours anti-horaire (haut → gauche → bas → retour).
# Blend linéaire entre profil circulaire et profil horseshoe rectangulaire.
func _profile_xy(k: int, n: int, radius: float, blend: float) -> Vector2:
	var u: float = float(k) / float(n)
	var angle: float = u * TAU
	# Profil circulaire
	var circ: Vector2 = Vector2(cos(angle) * radius, sin(angle) * radius)
	if blend <= 0.001:
		return circ
	# Profil horseshoe rectangulaire (largeur 2W, hauteur 2H) parcouru anti-horaire.
	var W: float = horseshoe_half_width
	var H: float = horseshoe_half_height
	var perim: float = 4.0 * (W + H)
	var s_ct: float = u * perim
	var hs: Vector2
	# Segment 1: mur droit haut (W, 0) → (W, H), longueur H
	if s_ct < H:
		hs = Vector2(W, s_ct)
	elif s_ct < H + 2.0 * W:
		# Segment 2: plafond (W, H) → (-W, H), longueur 2W
		hs = Vector2(W - (s_ct - H), H)
	elif s_ct < 3.0 * H + 2.0 * W:
		# Segment 3: mur gauche (-W, H) → (-W, -H), longueur 2H
		hs = Vector2(-W, H - (s_ct - H - 2.0 * W))
	elif s_ct < 3.0 * H + 4.0 * W:
		# Segment 4: sol (-W, -H) → (W, -H), longueur 2W
		hs = Vector2(-W + (s_ct - 3.0 * H - 2.0 * W), -H)
	else:
		# Segment 5: mur droit bas (W, -H) → (W, 0), longueur H
		hs = Vector2(W, -H + (s_ct - 3.0 * H - 4.0 * W))
	if blend >= 0.999:
		return hs
	return circ.lerp(hs, blend)


func _emit_ring(
	st: SurfaceTool,
	center: Vector3,
	tangent: Vector3,
	radius: float,
	ring_idx: float,
) -> void:
	# Crée deux rings consécutifs et triangule les quads entre eux.
	# Comme on appelle _emit_ring par ring, il faudrait plutôt accumuler
	# les rings puis triangulation globale. Implémentation directe avec
	# add_vertex pour chaque triangle d'un quad [i, i+1, j, j+1].
	#
	# Cette approche génère n_rings-1 × n_segments × 2 triangles.
	# On doit donc émettre les triangles en regardant le ring précédent.
	var idx: int = int(ring_idx)
	if idx == 0:
		return  # pas de ring précédent

	var prev_center: Vector3 = path_points[idx - 1]
	var prev_tangent: Vector3 = path_tangents[idx - 1]
	var prev_s: float = float(idx - 1) * ring_spacing
	var prev_radius: float = _radius_at(prev_s)

	# Base orthonormée pour chaque ring — up-vector monde (0,1,0)
	# puis right = tangent × up, fresh up = right × tangent
	var world_up: Vector3 = Vector3.UP
	var prev_right: Vector3 = prev_tangent.cross(world_up).normalized()
	if prev_right.length() < 0.01:
		prev_right = Vector3.RIGHT
	var prev_up: Vector3 = prev_right.cross(prev_tangent).normalized()

	var cur_right: Vector3 = tangent.cross(world_up).normalized()
	if cur_right.length() < 0.01:
		cur_right = Vector3.RIGHT
	var cur_up: Vector3 = cur_right.cross(tangent).normalized()

	var prev_blend: float = _horseshoe_blend_at(prev_s)
	var cur_blend: float = _horseshoe_blend_at(float(idx) * ring_spacing)

	for k in range(ring_segments):
		var prev_0: Vector2 = _profile_xy(k, ring_segments, prev_radius, prev_blend)
		var prev_1: Vector2 = _profile_xy(k + 1, ring_segments, prev_radius, prev_blend)
		var cur_0: Vector2 = _profile_xy(k, ring_segments, radius, cur_blend)
		var cur_1: Vector2 = _profile_xy(k + 1, ring_segments, radius, cur_blend)

		var p_prev_0: Vector3 = prev_center + prev_right * prev_0.x + prev_up * prev_0.y
		var p_prev_1: Vector3 = prev_center + prev_right * prev_1.x + prev_up * prev_1.y
		var p_cur_0: Vector3 = center + cur_right * cur_0.x + cur_up * cur_0.y
		var p_cur_1: Vector3 = center + cur_right * cur_1.x + cur_up * cur_1.y

		# UV : U = angle normalisé, V = distance parcourue
		var u0: float = float(k) / float(ring_segments)
		var u1: float = float(k + 1) / float(ring_segments)
		var v0: float = (ring_idx - 1.0) * ring_spacing / 10.0
		var v1: float = ring_idx * ring_spacing / 10.0

		# Triangle 1 : prev_0, cur_0, cur_1  (CCW vu de l'intérieur)
		st.set_uv(Vector2(u0, v0))
		st.add_vertex(p_prev_0)
		st.set_uv(Vector2(u0, v1))
		st.add_vertex(p_cur_0)
		st.set_uv(Vector2(u1, v1))
		st.add_vertex(p_cur_1)

		# Triangle 2 : prev_0, cur_1, prev_1
		st.set_uv(Vector2(u0, v0))
		st.add_vertex(p_prev_0)
		st.set_uv(Vector2(u1, v1))
		st.add_vertex(p_cur_1)
		st.set_uv(Vector2(u1, v0))
		st.add_vertex(p_prev_1)


func _draw_debug_path() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.3)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINE_STRIP)
	st.set_material(mat)
	for p in path_points:
		st.add_vertex(p)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.name = "DebugPath"
	add_child(mi)


# ---------------------------------------------------------------------------
# Passing loop — décalage latéral d'une rame dans la boucle de croisement
#
# Géométrie aiguillage Abt RÉELLE : courbe sinusoïdale CONTINUE et symétrique
# entre PASSING_START et PASSING_END. Pas de section droite intermédiaire.
# Les 2 voies divergent doucement depuis le point de jonction unique, atteignent
# l'écart max au milieu, puis reconvergent symétriquement.
#
# side = −1 pour voie gauche (rame 1 qui monte), +1 pour voie droite (rame 2).
# Hors boucle : 0. À l'entrée/sortie exactement : 0 (jonction propre voie unique).
# Au milieu : ±passing_offset_max (peak).
# ---------------------------------------------------------------------------

func passing_loop_offset(s: float, side: float) -> float:
	if s <= PNConstants.PASSING_START or s >= PNConstants.PASSING_END:
		return 0.0
	var loop_len: float = PNConstants.PASSING_END - PNConstants.PASSING_START
	var k: float = (s - PNConstants.PASSING_START) / loop_len   # 0 → 1
	# Forme : MAX · sin²(π·k) = MAX · (1 − cos(2π·k)) / 2.
	# C¹ continu PARTOUT (y compris à la séparation et à la réunion des voies) :
	# - À k=0 (PASSING_START) : amt=0 et pente=0 → jonction LISSE avec voie unique
	# - À k=0.5 (milieu) : peak MAX, pente=0 → peak arrondi
	# - À k=1 (PASSING_END) : amt=0 et pente=0 → jonction LISSE avec voie unique
	# - Divergence max à k=0.25 et k=0.75 (~3°) — quart et trois-quart du loop
	var s_pi: float = sin(PI * k)
	var amt: float = s_pi * s_pi   # = sin²(π·k)
	return side * passing_offset_max * amt


# ---------------------------------------------------------------------------
# Position + orientation du train à la distance s
# ---------------------------------------------------------------------------

func transform_at(s: float) -> Transform3D:
	# Position smooth via Curve3D.sample_baked(cubic=true) — la Curve3D est
	# construite avec les tangentes Catmull-Rom explicites dans _build_curve3d(),
	# ce qui suffit à éliminer le tressautement (la spline devient vraiment C1).
	# Orientation reconstruite manuellement (convention basis.z = -tangent) —
	# sample_baked_with_rotation() retournait une basis incompatible avec
	# la convention forward=-Z du reste du code.
	s = clampf(s, 0.0, PNConstants.LENGTH)
	var baked_len: float = path_curve.get_baked_length() if path_curve else 0.0
	if baked_len <= 0.0:
		return Transform3D.IDENTITY
	var path_len: float = PNConstants.LENGTH
	var offset: float = s / path_len * baked_len

	var pos: Vector3 = path_curve.sample_baked(offset, true)
	# Tangente par finite-difference sur la courbe baked (maintenant smooth grâce
	# aux Catmull-Rom tangents set explicitement via add_point(p, in, out))
	var eps: float = minf(0.5, baked_len * 0.5 - 0.001)
	var pos_next: Vector3 = path_curve.sample_baked(minf(offset + eps, baked_len), true)
	var pos_prev: Vector3 = path_curve.sample_baked(maxf(offset - eps, 0.0), true)
	var tangent: Vector3 = (pos_next - pos_prev).normalized()

	var world_up: Vector3 = Vector3.UP
	var right: Vector3 = tangent.cross(world_up).normalized()
	if right.length() < 0.01:
		right = Vector3.RIGHT
	var up: Vector3 = right.cross(tangent).normalized()

	var t: Transform3D = Transform3D()
	t.basis = Basis(right, up, -tangent)  # -tangent car Godot forward = -Z
	t.origin = pos
	return t
