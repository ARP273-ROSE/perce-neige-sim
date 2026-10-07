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
@export var chunk_length: float = 120.0      # découpage des meshes (frustum culling)

# Horseshoe (tunnel carré cut-and-cover aux portails)
@export var horseshoe_half_width: float = 2.05   # demi-largeur rectangle
@export var horseshoe_half_height: float = 2.05  # demi-hauteur rectangle
@export var horseshoe_transition: float = 20.0   # longueur de blend circular ↔ horseshoe

# Salles de gare (zones de quai) : la section carrée s'élargit pour loger
# les quais-escaliers de 3 m de chaque côté du train (murs parallèles au
# train calés juste derrière le bord extérieur des quais), plafond bas.
# Murs calés sur des quais de 3 m : inner 1,85 + 3,00 + 5 cm de jeu.
@export var station_room_half_width: float = 4.90
@export var station_room_half_height: float = 2.65
@export var station_low_end: float = 52.0        # fin de la salle Val Claret
# Début de la salle Grande Motte : AU PIGNON AVAL du bâtiment de la gare
# (GareAmont, 44,5 m sous le mur de tête), où le tunnel débouche dans un mur
# droit par une bouche rectangulaire — photos FUNI-334 « un petit zoom sur
# la sortie du tunnel » et 095520 (la queue de la rame arrêtée est à la
# bouche) ; Kevin, 07/10/2026 : « le mur aval de la gare ferme l'entrée du
# tunnel ». Avant : 3473,56 et un évasement de 6 m hors du bâtiment.
@export var station_high_start: float = 3478.82
@export var station_room_transition: float = 6.0 # fondu salle ↔ tube carré (gare aval)
@export var station_room_transition_haut: float = 0.5  # gare amont : mur droit

# Passing loop (boucle de croisement au milieu du tunnel)
# Géométrie réelle aiguillage Abt : courbe sinusoïdale continue symétrique
# entre PASSING_START et PASSING_END. Pas de section droite intermédiaire.
# offset(s) = ±MAX × sin(π × (s − PASS_START) / (PASS_END − PASS_START))
@export var passing_offset_max: float = 3.50     # décalage latéral PEAK au milieu du loop (m)
@export var passing_transition: float = 0.0      # plus utilisé (gardé pour compat)

# Câbles électriques de paroi (cf. _build_wall_cables)
@export var wall_cable_radius: float = 0.022
@export var wall_cable_x_local: float = -1.55    # contre la paroi gauche
@export var wall_cable_sample_m: float = 4.0
@export var wall_cable_y1: float = 0.35
@export var wall_cable_y2: float = 0.55

var path_points: Array = []                  # Vector3[] — positions monde
var path_tangents: Array = []                # Vector3[] — direction locale
var path_curve: Curve3D = null               # spline Catmull-Rom pour sampling smooth
# Trajectoire lissée (retour du 01/10/2026 : « tremblements excessifs de la
# rame quand elle roule ») : positions de la courbe tous les SMOOTH_H mètres,
# relues par une B-spline cubique uniforme (C2) — cf. transform_at.
const SMOOTH_H: float = 1.0
var _smooth_nodes: PackedVector3Array = PackedVector3Array()

# Matériau béton partagé par TOUTES les sections de paroi — mémorisé pour
# pouvoir le rendre translucide en vue extérieure (voir set_wall_see_through).
var wall_material: StandardMaterial3D = null


func _ready() -> void:
	_build()


# Rend les parois du tunnel translucides (vue extérieure : on veut voir la
# rame À L'INTÉRIEUR du tube) ou opaques (vue cockpit). Toutes les sections
# partagent wall_material → un seul réglage suffit.
# Matériaux d'habillage (parois, plafonds, poutres des gares, fond de la
# gare haute) qui doivent suivre la paroi du tunnel en vue extérieure :
# les bâtisseurs les y inscrivent (retour d'essai 2026-09-27 : « rends les
# deux gares de nouveau transparentes en vue externe » — l'habillage de la
# v1.15.14 restait opaque et cachait la rame à quai).
var extra_see_through: Array = []


func set_wall_see_through(on: bool) -> void:
	if wall_material == null:
		return
	_apply_see_through(wall_material, on)
	for m in extra_see_through:
		if m is StandardMaterial3D:
			_apply_see_through(m, on)


func _apply_see_through(mat: StandardMaterial3D, on: bool) -> void:
	var c: Color = mat.albedo_color
	if on:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		c.a = 0.22
		# Ne dessiner que les faces arrière : la paroi la plus proche de la
		# caméra disparaît, on voit direct l'intérieur sans double couche
		# translucide qui grisonne tout.
		mat.cull_mode = BaseMaterial3D.CULL_FRONT
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		c.a = 1.0
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = c


func _build() -> void:
	# Génère les points de la spline
	path_points = SlopeProfile.build_path_points(ring_spacing)
	_compute_tangents()
	_build_curve3d()
	_build_smooth_path()

	# Matériau de la paroi — CULL_DISABLED pour voir l'intérieur quel que
	# soit le winding des triangles.
	# Recalé sur la vidéo cabine HD (2026-09-27, « pas des dalles de
	# béton ») : revêtement LISSE, clair, presque blanc sous les néons, avec
	# un léger reflet (les tubes se reflètent en traînées sur la paroi) —
	# pas le béton gris-vert mat d'avant.
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.64, 0.65, 0.64)
	mat.roughness = 0.45
	mat.metallic = 0.10
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wall_material = mat
	# UV plus fin pour densifier les détails de noise procédural si une
	# texture future est branchée (UV_scale=8,4 → environ 1 cycle par
	# 0.5 m de tunnel, échelle réaliste pour des taches d'humidité)
	mat.uv1_scale = Vector3(8.0, 4.0, 1.0)
	# Léger AO ambient pour donner du relief sans texture
	mat.ao_enabled = true
	mat.ao_light_affect = 0.35

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
	# Croisement : DEUX TUBES SÉPARÉS, pas une chambre élargie. Sources :
	# remontees-mecaniques.net (« le croisement se fait ici dans deux tubes
	# séparés », contrairement à Val d'Isère) + chronologie chantier (« tube
	# d'évitement » percé le 02/10/1991). Aux extrémités, les deux tubes
	# fusionnent : tant que l'écartement d < R les deux cercles se
	# chevauchent → profil « binoculaire » (union des deux cercles) qui se
	# pince progressivement ; au-delà (d ≥ R), deux tubes circulaires
	# distincts avec le rocher entre les deux.
	var pinch: float = _loop_pinch_ds()
	var s_pinch_lo: float = PNConstants.PASSING_START + pinch
	var s_pinch_hi: float = PNConstants.PASSING_END - pinch
	_build_tunnel_section(mat, 0.0, PNConstants.PASSING_START, 0.0, "TunnelLow", false)
	_build_tunnel_fusion(mat, PNConstants.PASSING_START, s_pinch_lo, "TunnelFusionLow")
	_build_tunnel_section(mat, s_pinch_lo, s_pinch_hi, -1.0, "TunnelLoopL", false)
	_build_tunnel_section(mat, s_pinch_lo, s_pinch_hi, +1.0, "TunnelLoopR", false)
	_build_tunnel_fusion(mat, s_pinch_hi, PNConstants.PASSING_END, "TunnelFusionHigh")
	_build_tunnel_section(mat, PNConstants.PASSING_END, PNConstants.LENGTH, 0.0, "TunnelHigh", false)

	# Câbles électriques le long du flanc gauche du tunnel (visibles sur
	# toutes les frames intérieures du vrai funiculaire). 2 câbles
	# parallèles, fixés à mi-hauteur, fins (~25 mm) et noirs.
	_build_wall_cables()
	_build_sortie_secours()

	if show_debug_path:
		_draw_debug_path()


# Sortie de secours (fait de Kevin, 06/10/2026, vidéo de montée :
# « l'unique sortie de secours est sur la droite dans le sens montée, au
# niveau du galet 145, à 2 112 m » au compteur, soit s = 2 112 + 38,56).
# Dessin d'après la vidéo 20260426_094649.mp4, 0:54-0:55 : le tube
# s'élargit sur quelques mètres (on voit le REBORD CIRCULAIRE de la
# chambre, un anneau sombre tout autour) ; à droite, une ouverture sombre et
# haute depuis la passerelle, un panneau vert et une étiquette blanche ; en
# face, sur la paroi gauche juste avant l'anneau, sous les câbles : un
# boîtier ORANGE (pas un gyrophare) et un coffret BLANC d'où une gaine
# descend au sol. Rien ne dépasse
# de la paroi : le gabarit de la rame ne laisse que ~15 cm.
const SORTIE_SECOURS_S: float = 2112.0 + 38.56


func _build_sortie_secours() -> void:
	var s_c: float = SORTIE_SECOURS_S
	var blend: float = _horseshoe_blend_at(s_c)
	var dims: Vector2 = _horseshoe_dims_at(s_c)
	# point de la paroi (côté +1 droite, −1 gauche) à la hauteur y, sur le
	# POLYGONE du maillage du tunnel (la corde passe jusqu'à 2,4 cm à
	# l'intérieur du cercle), en retrait vers l'axe
	var paroi := func(y: float, retrait: float, cote: float) -> Vector2:
		for k in range(ring_segments):
			var a: Vector2 = _profile_xy(k, ring_segments, _radius_at(s_c), blend, dims.x, dims.y)
			var b: Vector2 = _profile_xy(k + 1, ring_segments, _radius_at(s_c), blend, dims.x, dims.y)
			if a.x * cote > 0.0 and b.x * cote > 0.0 and (y - a.y) * (y - b.y) <= 0.0 \
					and absf(b.y - a.y) > 1e-6:
				var q: Vector2 = a.lerp(b, (y - a.y) / (b.y - a.y))
				return q * (1.0 - retrait / q.length())
		return Vector2(1.5 * cote, y)
	var pt := func(s_: float, q: Vector2) -> Vector3:
		var xf: Transform3D = transform_at(s_)
		return xf.origin + xf.basis.x * q.x + xf.basis.y * q.y
	var mat := func(c: Color, emis: float = 0.0) -> StandardMaterial3D:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.7
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if emis > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = emis
		return m
	var surfaces: Array = []
	# --- surface balayée sur la paroi : y de ya à yb, s de sa à sb
	var patch := func(sa: float, sb: float, ya: float, yb: float, retrait: float, cote: float,
			m: StandardMaterial3D, nom: String) -> void:
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n_y: int = maxi(2, int(absf(yb - ya) / 0.15))
		for i in range(n_y):
			var qa: Vector2 = paroi.call(lerpf(ya, yb, float(i) / n_y), retrait, cote)
			var qb: Vector2 = paroi.call(lerpf(ya, yb, float(i + 1) / n_y), retrait, cote)
			for v in [[sa, qa], [sb, qa], [sb, qb], [sa, qa], [sb, qb], [sa, qb]]:
				st.add_vertex(pt.call(v[0], v[1]))
		st.set_material(m)
		st.generate_normals()
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = nom
		mi.mesh = st.commit()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	# 1. rebords circulaires de la chambre : anneaux sombres au-dessus de
	#    la dalle, de part et d'autre de l'ouverture
	var sombre: StandardMaterial3D = mat.call(Color(0.08, 0.08, 0.09))
	var st_r: SurfaceTool = SurfaceTool.new()
	st_r.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s_r in [s_c - 2.6, s_c + 2.3]:
		# chaque côté du polygone du tube au-dessus de la passerelle
		for k in range(ring_segments):
			var a: Vector2 = _profile_xy(k, ring_segments, _radius_at(s_c), blend, dims.x, dims.y)
			var b: Vector2 = _profile_xy(k + 1, ring_segments, _radius_at(s_c), blend, dims.x, dims.y)
			if a.y < -1.45 and b.y < -1.45:
				continue
			if a.y < -1.45:
				a = a.lerp(b, (-1.45 - a.y) / (b.y - a.y))
			elif b.y < -1.45:
				b = b.lerp(a, (-1.45 - b.y) / (a.y - b.y))
			a *= 1.0 - 0.012 / a.length()
			b *= 1.0 - 0.012 / b.length()
			for v in [[s_r, a], [s_r + 0.12, a], [s_r + 0.12, b], [s_r, a], [s_r + 0.12, b], [s_r, b]]:
				st_r.add_vertex(pt.call(v[0], v[1]))
	st_r.set_material(sombre)
	st_r.generate_normals()
	var mi_r: MeshInstance3D = MeshInstance3D.new()
	mi_r.name = "SortieSecoursRebord"
	mi_r.mesh = st_r.commit()
	mi_r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi_r)
	# 2. ouverture à droite, haute, depuis la passerelle : fond sombre et
	#    bord clair de béton coffré
	patch.call(s_c - 0.75, s_c + 0.75, -1.25, 1.35, 0.012, 1.0,
		mat.call(Color(0.035, 0.035, 0.04)), "SortieSecours")
	var bord: StandardMaterial3D = mat.call(Color(0.70, 0.70, 0.67))
	patch.call(s_c - 0.85, s_c - 0.75, -1.25, 1.45, 0.016, 1.0, bord, "SortieSecoursCadre")
	patch.call(s_c + 0.75, s_c + 0.85, -1.25, 1.45, 0.016, 1.0, bord, "SortieSecoursCadre")
	patch.call(s_c - 0.85, s_c + 0.85, 1.35, 1.45, 0.016, 1.0, bord, "SortieSecoursCadre")
	# 3. panneau vert (bonhomme qui court : silhouette simplifiée) et
	#    étiquette blanche, sur la paroi droite au-delà de l'ouverture
	var xf_p: Transform3D = transform_at(s_c + 1.35)
	var qs: Vector2 = paroi.call(0.15, 0.03, 1.0)
	var normale: Vector3 = -(xf_p.basis.x * qs.x + xf_p.basis.y * qs.y).normalized()
	var avant: Vector3 = -xf_p.basis.z
	var haut: Vector3 = avant.cross(normale).normalized()
	if haut.dot(xf_p.basis.y) < 0.0:
		haut = -haut
	# repère direct : x vers l'aval (lecture de gauche à droite depuis la
	# voie), y le long de la paroi, z vers l'axe
	var b_p: Basis = Basis(-avant, haut, normale)
	var boite := func(taille: Vector3, m: Material, b: Basis, o: Vector3, nom: String) -> void:
		var mi: MeshInstance3D = MeshInstance3D.new()
		var bm: BoxMesh = BoxMesh.new()
		bm.size = taille
		bm.material = m
		mi.mesh = bm
		mi.name = nom
		mi.transform = Transform3D(b, o)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	var o_p: Vector3 = pt.call(s_c + 1.35, qs)
	boite.call(Vector3(0.42, 0.22, 0.03), mat.call(Color(0.0, 0.42, 0.17), 1.2), b_p, o_p, "SortieSecoursPanneau")
	var txt: Label3D = Label3D.new()
	txt.text = "SORTIE"
	txt.font_size = 40
	txt.pixel_size = 0.0028
	txt.modulate = Color(1, 1, 1)
	txt.outline_size = 0
	txt.shaded = false
	txt.visibility_range_end = 150.0
	txt.transform = Transform3D(b_p, o_p + normale * 0.02)
	add_child(txt)
	var qe: Vector2 = paroi.call(0.75, 0.02, 1.0)
	boite.call(Vector3(0.14, 0.22, 0.01), mat.call(Color(0.92, 0.92, 0.90), 0.3), b_p,
		pt.call(s_c + 1.05, qe), "SortieSecoursEtiquette")
	# 4. en face, paroi gauche, avant l'anneau : boîtier orange et coffret blanc
	#    sous les câbles muraux, gaine jusqu'au sol
	var xf_g: Transform3D = transform_at(s_c - 3.2)
	var qg: Vector2 = paroi.call(0.05, 0.08, -1.0)
	var n_g: Vector3 = -(xf_g.basis.x * qg.x + xf_g.basis.y * qg.y).normalized()
	var h_g: Vector3 = n_g.cross(-xf_g.basis.z).normalized()
	if h_g.dot(xf_g.basis.y) < 0.0:
		h_g = -h_g
	var b_g: Basis = Basis(-xf_g.basis.z, h_g, n_g).orthonormalized()
	boite.call(Vector3(0.26, 0.36, 0.13), mat.call(Color(0.90, 0.90, 0.88)), b_g,
		pt.call(s_c - 3.2, qg), "SortieSecoursCoffret")
	# boîtier orange à côté du coffret (pas un gyrophare : retour de Kevin)
	var qo: Vector2 = paroi.call(0.10, 0.07, -1.0)
	boite.call(Vector3(0.14, 0.22, 0.11), mat.call(Color(0.95, 0.40, 0.08)), b_g,
		pt.call(s_c - 3.55, qo), "SortieSecoursBoitierOrange")
	var gaine: StandardMaterial3D = mat.call(Color(0.10, 0.10, 0.11))
	var q_bas: Vector2 = paroi.call(-1.30, 0.03, -1.0)
	var p_haut: Vector3 = pt.call(s_c - 3.15, paroi.call(-0.13, 0.04, -1.0))
	var p_bas: Vector3 = pt.call(s_c - 3.05, q_bas)
	var mi_g: MeshInstance3D = MeshInstance3D.new()
	var cg: CylinderMesh = CylinderMesh.new()
	cg.top_radius = 0.012
	cg.bottom_radius = 0.012
	cg.height = p_haut.distance_to(p_bas)
	cg.radial_segments = 6
	cg.material = gaine
	mi_g.mesh = cg
	var axe: Vector3 = (p_haut - p_bas).normalized()
	var perp: Vector3 = axe.cross(xf_g.basis.z).normalized()
	mi_g.transform = Transform3D(Basis(perp, axe, perp.cross(axe)).orthonormalized(), (p_haut + p_bas) * 0.5)
	mi_g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi_g)


# Câbles électriques posés sur le flanc gauche du tunnel.
# Deux conduits parallèles épais de ~25 mm, fixés à mi-hauteur, qu'on voit
# défiler dans toutes les frames intérieures du vrai funiculaire (v1_07,
# v1_11, v1_15…). Mesh continu via SurfaceTool, suit la spline avec un
# sample tous les 4 m → ~870 segments × 2 câbles × 8 faces = peu de
# vertices au total.
func _build_wall_cables() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.09)
	mat.roughness = 0.55
	mat.metallic = 0.10

	var radial: int = 8
	for which in [0, 1]:
		var y_off: float = wall_cable_y1 if which == 0 else wall_cable_y2
		# Découpé en tronçons de chunk_length (même raison que le tunnel :
		# un tube continu de 3,4 km ne se fait jamais culler).
		# Seulement dans le TUBE : dans les salles des gares la paroi du
		# tube n'existe plus et les câbles flottaient en l'air au milieu
		# de la gare (retour de Kevin du 06/10/2026, gare du bas).
		var c_start: float = station_low_end
		var chunk_i: int = 0
		while c_start < station_high_start - 0.001:
			var c_end: float = minf(c_start + chunk_length, station_high_start)
			_build_wall_cable_chunk(mat, y_off, radial, c_start, c_end,
				"WallCable_%d_%d" % [which, chunk_i])
			c_start = c_end
			chunk_i += 1


func _build_wall_cable_chunk(
	mat: StandardMaterial3D, y_off: float, radial: int,
	s_start: float, s_end: float, name: String,
) -> void:
	var n_steps: int = maxi(2, int((s_end - s_start) / wall_cable_sample_m))
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)

	var prev_s: float = s_start
	var prev_xform: Transform3D = transform_at(s_start)
	for i in range(1, n_steps + 1):
		var s_cur: float = s_start + float(i) / float(n_steps) * (s_end - s_start)
		var cur_xform: Transform3D = transform_at(s_cur)

		var p0: Vector3 = prev_xform.origin \
			+ prev_xform.basis.x * _wall_cable_x_at(prev_s) \
			+ prev_xform.basis.y * y_off
		var p1: Vector3 = cur_xform.origin \
			+ cur_xform.basis.x * _wall_cable_x_at(s_cur) \
			+ cur_xform.basis.y * y_off

		for k in range(radial):
			var a0: float = float(k) / float(radial) * TAU
			var a1: float = float(k + 1) / float(radial) * TAU
			var c0: float = cos(a0)
			var s0: float = sin(a0)
			var c1: float = cos(a1)
			var s1: float = sin(a1)
			var off0_prev: Vector3 = prev_xform.basis.x * (c0 * wall_cable_radius) \
				+ prev_xform.basis.y * (s0 * wall_cable_radius)
			var off1_prev: Vector3 = prev_xform.basis.x * (c1 * wall_cable_radius) \
				+ prev_xform.basis.y * (s1 * wall_cable_radius)
			var off0_cur: Vector3 = cur_xform.basis.x * (c0 * wall_cable_radius) \
				+ cur_xform.basis.y * (s0 * wall_cable_radius)
			var off1_cur: Vector3 = cur_xform.basis.x * (c1 * wall_cable_radius) \
				+ cur_xform.basis.y * (s1 * wall_cable_radius)

			var v00: Vector3 = p0 + off0_prev
			var v01: Vector3 = p0 + off1_prev
			var v10: Vector3 = p1 + off0_cur
			var v11: Vector3 = p1 + off1_cur

			st.set_uv(Vector2(0, 0)); st.add_vertex(v00)
			st.set_uv(Vector2(0, 1)); st.add_vertex(v10)
			st.set_uv(Vector2(1, 1)); st.add_vertex(v11)
			st.set_uv(Vector2(0, 0)); st.add_vertex(v00)
			st.set_uv(Vector2(1, 1)); st.add_vertex(v11)
			st.set_uv(Vector2(1, 0)); st.add_vertex(v01)

		prev_s = s_cur
		prev_xform = cur_xform

	st.generate_normals()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# X local du câble mural à la distance s : suit la paroi GAUCHE du tunnel,
# y compris dans la chambre de croisement où la paroi s'écarte de
# |passing_loop_offset|, et dans les salles de gare élargies. Sans ça, le
# câble resterait à x constant en plein milieu et la rame le traverserait.
func _wall_cable_x_at(s: float) -> float:
	var room_extra: float = _horseshoe_dims_at(s).x - horseshoe_half_width
	return wall_cable_x_local - absf(passing_loop_offset(s, 1.0)) - room_extra


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
	# Indices de rings encadrants (on prend le ring juste avant s_start et juste
	# après s_end pour assurer une fermeture visuelle aux extrémités)
	var n_rings_total: int = path_points.size()
	var idx_start: int = clampi(int(s_start / ring_spacing), 0, n_rings_total - 1)
	var idx_end: int = clampi(int(ceil(s_end / ring_spacing)), idx_start + 1, n_rings_total - 1)

	# Découpage en tronçons de ~chunk_length pour que le frustum culling
	# fonctionne (une section continue de 1,6 km a une AABB toujours dans
	# le champ → dessinée en entier à chaque frame).
	var rings_per_chunk: int = maxi(2, int(chunk_length / ring_spacing))
	var c_start: int = idx_start
	var chunk_i: int = 0
	while c_start < idx_end:
		var c_end: int = mini(c_start + rings_per_chunk, idx_end)
		_build_tunnel_chunk(mat, c_start, c_end, side,
			"%s_%d" % [name, chunk_i], is_chamber)
		c_start = c_end
		chunk_i += 1


# Dessus de la dalle de voie (TrackBuilder.floor_y_local + slab_thickness) et
# demi-largeur de la dalle : dessous, la paroi est cachée — sauf dans la
# fosse centrale de la voie (retour du 03/10/2026, fond 70 cm sous la
# dalle), que le bas du tube traversait comme un faux plancher. On ne
# dessine donc pas la paroi sous la dalle, là où la dalle existe.
const FLOOR_CUT_Y: float = -1.60
const SLAB_HALF_W: float = 1.60
const SLAB_S0: float = 4.5          # TrackBuilder.pit_low_end


func _sous_dalle(s: float, x: float, y: float) -> bool:
	if y >= FLOOR_CUT_Y or s < SLAB_S0 + ring_spacing \
			or s > PNConstants.LENGTH + MachineRoomBuilder.PIT_S0 - ring_spacing:
		return false
	var hw: float = SLAB_HALF_W - 0.05
	if s > PNConstants.PASSING_START and s < PNConstants.PASSING_END:
		hw += absf(passing_loop_offset(s, 1.0))
	return absf(x) < hw


func _build_tunnel_chunk(
	mat: StandardMaterial3D, idx_start: int, idx_end: int,
	side: float, name: String, is_chamber: bool,
) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)

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

		# Dimensions horseshoe locales (élargies dans les salles de gare)
		var prev_dims: Vector2 = _horseshoe_dims_at(s_prev)
		var cur_dims: Vector2 = _horseshoe_dims_at(s_cur)
		# Fin de ligne : la salle des machines s'étend sous les derniers
		# mètres de la gare haute. Le caisson de la gare (sol à −2,65) la
		# traversait et coupait la roue aval à plat (retour du 30/09) : dans
		# les anneaux qui la couvrent, rien sous le dessous de dalle.
		var cut_s: float = PNConstants.LENGTH + MachineRoomBuilder.ROOM_S0 - ring_spacing
		var prev_cut: bool = s_prev >= cut_s
		var cur_cut: bool = s_cur >= cut_s
		var y_cut: float = MachineRoomBuilder.Y_SLAB_BOTTOM

		for k in range(ring_segments):
			var prev_0: Vector2 = _profile_xy(k, ring_segments, prev_radius, prev_blend, prev_dims.x, prev_dims.y)
			var prev_1: Vector2 = _profile_xy(k + 1, ring_segments, prev_radius, prev_blend, prev_dims.x, prev_dims.y)
			var cur_0: Vector2 = _profile_xy(k, ring_segments, cur_radius, cur_blend, cur_dims.x, cur_dims.y)
			var cur_1: Vector2 = _profile_xy(k + 1, ring_segments, cur_radius, cur_blend, cur_dims.x, cur_dims.y)
			if _sous_dalle(s_prev, prev_off + prev_0.x, prev_0.y) and _sous_dalle(s_prev, prev_off + prev_1.x, prev_1.y) \
					and _sous_dalle(s_cur, cur_off + cur_0.x, cur_0.y) and _sous_dalle(s_cur, cur_off + cur_1.x, cur_1.y):
				continue
			if prev_cut and cur_cut and maxf(maxf(prev_0.y, prev_1.y), maxf(cur_0.y, cur_1.y)) <= y_cut + 0.01:
				continue
			if prev_cut:
				prev_0.y = maxf(prev_0.y, y_cut)
				prev_1.y = maxf(prev_1.y, y_cut)
			if cur_cut:
				cur_0.y = maxf(cur_0.y, y_cut)
				cur_1.y = maxf(cur_1.y, y_cut)

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


# Distance (depuis PASSING_START) à laquelle l'écartement des voies atteint
# le rayon du tube → point de pincement : avant, les deux cercles se
# chevauchent (profil binoculaire) ; après, deux tubes disjoints.
func _loop_pinch_ds() -> float:
	var ds: float = 0.0
	while ds < 120.0:
		if absf(passing_loop_offset(PNConstants.PASSING_START + ds, 1.0)) >= tunnel_radius:
			return ds
		ds += 0.5
	return 60.0  # fallback théorique


# Contour « binoculaire » : union de deux cercles de rayon tunnel_radius
# centrés à x = ±d (d ≤ R). n points, boucle fermée CCW. Départ au point
# extrême droit (angle 0 du cercle droit) → à d=0 le contour est EXACTEMENT
# le cercle échantillonné comme _profile_xy (jonction sans couture avec le
# tube unique). À d=R les deux lobes se touchent à l'origine (pincement).
func _fusion_outline(d: float, n: int) -> PackedVector2Array:
	var R: float = tunnel_radius
	d = clampf(d, 0.0, R)
	var h: float = sqrt(maxf(R * R - d * d, 0.0))
	var beta: float = atan2(h, -d)   # intersection HAUTE vue du centre droit
	var gamma: float = atan2(h, d)   # idem vue du centre gauche
	var n4: int = int(n / 4.0)
	var n2: int = int(n / 2.0)
	var n_c: int = n - n4 - n2
	var pts: PackedVector2Array = PackedVector2Array()
	# Arc A : cercle droit, 0 → beta (quart supérieur droit du contour)
	for j in range(n4):
		var a: float = beta * float(j) / float(n4)
		pts.append(Vector2(d + R * cos(a), R * sin(a)))
	# Arc B : cercle gauche, gamma → 2π−gamma (tout le lobe gauche)
	for j in range(n2):
		var a2: float = gamma + (TAU - 2.0 * gamma) * float(j) / float(n2)
		pts.append(Vector2(-d + R * cos(a2), R * sin(a2)))
	# Arc C : cercle droit, 2π−beta → 2π (quart inférieur droit)
	for j in range(n_c):
		var a3: float = (TAU - beta) + beta * float(j) / float(n_c)
		pts.append(Vector2(d + R * cos(a3), R * sin(a3)))
	return pts


# Tronçon de fusion des deux tubes (extrémités de l'évitement) : anneaux au
# profil binoculaire, écartement d(s) = |passing_loop_offset|. Chunké comme
# le reste du tunnel.
func _build_tunnel_fusion(
	mat: StandardMaterial3D, s_start: float, s_end: float, name: String,
) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)

	var n_rings_total: int = path_points.size()
	var idx_start: int = clampi(int(s_start / ring_spacing), 0, n_rings_total - 1)
	var idx_end: int = clampi(int(ceil(s_end / ring_spacing)), idx_start + 1, n_rings_total - 1)

	for i in range(idx_start + 1, idx_end + 1):
		var prev_idx: int = i - 1
		var s_cur: float = float(i) * ring_spacing
		var s_prev: float = float(prev_idx) * ring_spacing

		var cur_xform: Transform3D = tunnel_xform_raw(float(i))
		var prev_xform: Transform3D = tunnel_xform_raw(float(prev_idx))

		var prev_pts: PackedVector2Array = _fusion_outline(
			absf(passing_loop_offset(s_prev, 1.0)), ring_segments)
		var cur_pts: PackedVector2Array = _fusion_outline(
			absf(passing_loop_offset(s_cur, 1.0)), ring_segments)

		for k in range(ring_segments):
			var k1: int = (k + 1) % ring_segments
			if _sous_dalle(s_prev, prev_pts[k].x, prev_pts[k].y) and _sous_dalle(s_prev, prev_pts[k1].x, prev_pts[k1].y) \
					and _sous_dalle(s_cur, cur_pts[k].x, cur_pts[k].y) and _sous_dalle(s_cur, cur_pts[k1].x, cur_pts[k1].y):
				continue
			var p_prev_0: Vector3 = prev_xform.origin \
				+ prev_xform.basis.x * prev_pts[k].x + prev_xform.basis.y * prev_pts[k].y
			var p_prev_1: Vector3 = prev_xform.origin \
				+ prev_xform.basis.x * prev_pts[k1].x + prev_xform.basis.y * prev_pts[k1].y
			var p_cur_0: Vector3 = cur_xform.origin \
				+ cur_xform.basis.x * cur_pts[k].x + cur_xform.basis.y * cur_pts[k].y
			var p_cur_1: Vector3 = cur_xform.origin \
				+ cur_xform.basis.x * cur_pts[k1].x + cur_xform.basis.y * cur_pts[k1].y

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


# 1.0 = pleine salle de gare (section élargie), 0.0 = tube carré standard.
# Fondu linéaire sur station_room_transition à la jonction salle/tube.
func _station_room_blend_at(s: float) -> float:
	if s <= station_low_end - station_room_transition:
		return 1.0
	if s < station_low_end:
		return (station_low_end - s) / station_room_transition
	if s >= station_high_start + station_room_transition_haut:
		return 1.0
	if s > station_high_start:
		return (s - station_high_start) / station_room_transition_haut
	return 0.0


# Demi-largeur / demi-hauteur du profil horseshoe à la distance s
# (élargi en salle de gare, standard ailleurs).
func _horseshoe_dims_at(s: float) -> Vector2:
	var k: float = _station_room_blend_at(s)
	if k <= 0.0:
		return Vector2(horseshoe_half_width, horseshoe_half_height)
	return Vector2(
		lerpf(horseshoe_half_width, station_room_half_width, k),
		lerpf(horseshoe_half_height, station_room_half_height, k))


func _horseshoe_blend_at(s: float) -> float:
	# Retourne 0.0 = full circular, 1.0 = full horseshoe.
	# Transitions smooth autour de s=257 (portail bas) et s=3443 (portail haut).
	var lo_end: float = PNConstants.SQUARE_SECTION_LOW_END      # 257
	var hi_start: float = PNConstants.SQUARE_SECTION_HIGH_START # 3443
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
func _profile_xy(k: int, n: int, radius: float, blend: float,
		hs_w: float = -1.0, hs_h: float = -1.0) -> Vector2:
	var u: float = float(k) / float(n)
	var angle: float = u * TAU
	# Profil circulaire
	var circ: Vector2 = Vector2(cos(angle) * radius, sin(angle) * radius)
	if blend <= 0.001:
		return circ
	# Profil horseshoe rectangulaire (largeur 2W, hauteur 2H) parcouru
	# anti-horaire. W/H surchargables (salles de gare élargies).
	var W: float = hs_w if hs_w > 0.0 else horseshoe_half_width
	var H: float = hs_h if hs_h > 0.0 else horseshoe_half_height
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
	# Position et tangente lues sur la B-spline cubique uniforme de
	# _build_smooth_path (C2 : vitesse et accélération continues).
	#
	# Avant (jusqu'à la 1.15.37) : Curve3D.sample_baked(cubic) directement.
	# Ses points précuits (tous les 0,5 m, espacement retouché à chaque
	# segment) laissaient une ondulation de quelques millimètres : mesurée
	# image par image à 12 m/s, l'accélération de la trajectoire valait
	# 18 m/s² en médiane au lieu de ~0,1 (v²/R), avec des pics de tangage
	# entre 14 et 30 Hz. La caméra, à 15 m du point de référence, amplifiait
	# le tangage : la rame « tremblait » en roulant.
	s = clampf(s, 0.0, PNConstants.LENGTH)
	if _smooth_nodes.size() < 4:
		return Transform3D.IDENTITY
	var u: float = s / SMOOTH_H + 1.0
	var i: int = mini(int(u), _smooth_nodes.size() - 3)
	var t: float = u - float(i)
	var p1: Vector3 = _smooth_nodes[i]
	var d0: Vector3 = _smooth_nodes[i - 1] - p1
	var d2: Vector3 = _smooth_nodes[i + 1] - p1
	var d3: Vector3 = _smooth_nodes[i + 2] - p1
	var t2: float = t * t
	var t3: float = t2 * t
	var mt: float = 1.0 - t
	# poids B-spline (somme 6) appliqués aux écarts à p1 : moins d'erreur
	# d'arrondi qu'avec les coordonnées absolues (~3 km)
	var pos: Vector3 = p1 + (d0 * (mt * mt * mt) + d2 * (-3.0 * t3 + 3.0 * t2 + 3.0 * t + 1.0)
		+ d3 * t3) / 6.0
	var tangent: Vector3 = (d0 * (-mt * mt) + d2 * (-3.0 * t2 + 2.0 * t + 1.0)
		+ d3 * t2).normalized()

	var world_up: Vector3 = Vector3.UP
	var right: Vector3 = tangent.cross(world_up).normalized()
	if right.length() < 0.01:
		right = Vector3.RIGHT
	var up: Vector3 = right.cross(tangent).normalized()

	var tf: Transform3D = Transform3D()
	tf.basis = Basis(right, up, -tangent)  # -tangent car Godot forward = -Z
	tf.origin = pos
	return tf


## Point de la courbe précuite à l'abscisse s, moyenné sur 0,4 m pour
## gommer l'ondulation des points précuits (0,5 m).
func _baked_at(s: float) -> Vector3:
	var baked_len: float = path_curve.get_baked_length()
	var acc: Vector3 = Vector3.ZERO
	for k in range(-2, 3):
		var off: float = clampf((s + 0.1 * float(k)) / PNConstants.LENGTH * baked_len, 0.0, baked_len)
		acc += path_curve.sample_baked(off, true)
	return acc / 5.0


## Nœuds de la B-spline : un point tous les SMOOTH_H mètres, plus un nœud
## prolongé en ligne droite de chaque côté (bouts de ligne).
func _build_smooth_path() -> void:
	var L: float = PNConstants.LENGTH
	var n: int = int(ceil(L / SMOOTH_H))
	var a: Vector3 = path_curve.sample_baked(0.0, true)
	var ta: Vector3 = (_baked_at(SMOOTH_H) - a).normalized()
	var b: Vector3 = path_curve.sample_baked(path_curve.get_baked_length(), true)
	var tb: Vector3 = (b - _baked_at(L - SMOOTH_H)).normalized()
	_smooth_nodes.resize(n + 4)
	for j in range(n + 4):
		var s: float = float(j - 1) * SMOOTH_H
		if s <= 0.0:
			_smooth_nodes[j] = a + ta * s
		elif s >= L:
			_smooth_nodes[j] = b + tb * (s - L)
		else:
			_smooth_nodes[j] = _baked_at(s)
