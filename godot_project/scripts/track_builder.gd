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

# Voie DESCENDUE de 0,50 m le 2026-09-26 : en réalité les rails sont au
# fond de l'alésage (cabines Ø 3,60 dans un tube Ø 3,90, plancher bas) ;
# à −1,35 la table de roulement n'était qu'à 0,73 m sous l'axe et la rame
# ne pouvait pas y tenir sans passer sous les rails. Dalle −1,85 → table de
# roulement à −1,23. Quais (stations_builder), brins en salle des machines
# (machine_room_builder) et carrosserie (train_body_builder) recalés.
@export var floor_y_local: float = -1.85     # plancher dalle vs centre tunnel
@export var slab_thickness: float = 0.25     # épaisseur dalle béton
@export var slab_width: float = 3.20         # largeur dalle (déborde sous banquettes)

@export var sleeper_spacing: float = 0.95    # entraxe blocs (≈ 950 mm, gaps visibles)
# Blochets INDÉPENDANTS sous chaque rail (photos du 2026-04-26 : les
# traverses ne sont PAS continues entre les deux rails comme en voie
# ferrée classique — chaque rail repose sur sa propre rangée de plots
# béton, et l'espace central est occupé par la longrine des galets).
@export var block_width: float = 0.55        # largeur transverse d'un blochet
@export var sleeper_width: float = 0.42      # longueur (sens voie) d'un blochet
@export var sleeper_height: float = 0.20     # épaisseur (profil béton apparent)

# Longrine CONTINUE entre les deux rails : c'est elle qui porte les
# supports de galets du câble tracteur (photos : canal central avec le
# câble posé sur ses galets tout du long, y compris dans le loop).
@export var cable_beam_width: float = 0.50
@export var cable_beam_height: float = 0.06   # longrine basse : le câble doit rester au niveau des blochets

@export var guide_spacing: float = 13.57     # entraxe RÉEL : 3474 m / 256 paires (source CFD)
@export var pulley_radius: float = 0.15      # rayon poulie/galet (300 mm)
@export var pulley_thickness: float = 0.08   # épaisseur galet
@export var pulley_pair_offset: float = 0.12 # décalage latéral de chaque poulie (entraxe 0.24m)
@export var bracket_width: float = 0.04      # épaisseur équerres
@export var bracket_span: float = 0.42       # écart entre équerres (contient les 2 poulies)
@export var bracket_height: float = 0.12     # hauteur MAX des équerres (raccourcies pour tenir l'axe)
@export var base_plate_width: float = 0.52   # largeur socle béton (plus large pour la paire)
@export var base_plate_length: float = 0.16  # longueur socle (dans sens voie)
@export var base_plate_height: float = 0.02  # épaisseur socle (plaque)

@export var cable_radius: float = 0.026      # rayon câble 52 mm
@export var cable_segments: int = 8          # segments radiaux
@export var cable_sample_spacing: float = 2.0  # spline sampling

@export var sampling_step: float = 0.5       # pas MIN échantillonnage rails/dalle
@export var max_step: float = 3.0            # pas MAX (lignes droites)
@export var chord_tolerance: float = 0.004   # déviation de corde max tolérée (m)
@export var chunk_length: float = 120.0      # découpage des meshes continus (m)
# Pourquoi : les rails/dalle étaient des meshes continus de 3 474 m échantillonnés
# uniformément à 0,5 m → ~1 M de vertices TOUJOURS dans le frustum (AABB de
# 3,4 km dans l'axe de la vue = culling inopérant). Le chunking rend le frustum
# culling efficace (~5-10 % des tronçons visibles), et l'échantillonnage
# adaptatif (bisection sur la déviation de corde) garde 0,5 m dans les
# transitions du loop / virages mais monte à 3 m en ligne droite — même
# fidélité visuelle (déviation < 4 mm), ~6× moins de vertices.

var tunnel: TunnelBuilder = null
var keep_instance_xforms: bool = false   # bancs headless (cf. _mm_instance)

# Segments des 2 brins de câble (1 câble unique en boucle, 2 brins visibles).
# Structure : [{s_start: float, s_end: float, mesh: MeshInstance3D}, ...]
var cable_left_segments: Array = []    # brin aller — attaché à rame 1
var cable_right_segments: Array = []   # brin retour — attaché à rame 2
@export var cable_segment_length: float = 15.0  # longueur d'un segment mesh (m)

# Matériaux shader partagés entre tous les segments — on modifie les uniforms
# "cable_phase" directement dessus pour animer tous les segments simultanément.
var cable_left_material: ShaderMaterial = null
var cable_right_material: ShaderMaterial = null

# La rame PILOTÉE prend la voie GAUCHE (brin gauche) par défaut. Si le
# scénario « rame 2 » est choisi, la cabine pilotée passe sur la voie
# DROITE : c'est alors le brin DROIT qui est « le sien ». On échange donc
# quel brin suit la cabine pilotée pour la visibilité, l'animation des
# torons et la coupe fragment. Sans ça, le câble restait accroché à la
# rame 1 quel que soit le choix (retour d'essai 2026-07-12).
var driver_is_rame2: bool = false

# Phase accumulée du câble (en mètres). Croît avec le temps selon la vitesse
# de la rame. Pour le brin gauche (qui tient rame 1), cette phase compense le
# mouvement de rame 1 de sorte que les torons apparaissent FIXES dans le
# référentiel de la cabine. Pour le brin droite, la phase est opposée →
# les torons défilent à 2×v relative.
var _cable_phase_meters: float = 0.0


func build(t: TunnelBuilder) -> void:
	tunnel = t
	# Galets et câble d'abord : les fenêtres des rails intérieurs de
	# l'aiguillage Abt se placent là où le câble tendu les traverse.
	_compute_cable_geometry()
	_build_slab()
	_build_rails()
	_build_sleepers()
	_build_walkway()
	_build_tunnel_details()
	_build_cable_beam()
	_build_guides()
	_build_abt_sheaves()
	_build_cable()


# ---------------------------------------------------------------------------
# Câble tendu entre les galets + aiguillage Abt (2026-09-30)
#
# Retour d'essai : « en courbe, le câble va en ligne droite entre les
# galets ». Le câble n'épouse plus la courbe de la voie : tendu à
# 22 500 daN (11 kg/m → 11 mm de flèche sous son poids sur 13,57 m,
# négligée), il ne change de direction QU'AUX galets. En courbe
# (R ≈ 460 m), la corde passe jusqu'à 5 cm à l'intérieur de l'arc
# (audit_physique/aiguillage_abt_cable.sage).
#
# Aiguillage Abt (principe d'après une photo d'aiguillage de funiculaire
# à ciel ouvert envoyée par Kevin + dossier remontees-mecaniques.net) :
#   - rails extérieurs continus (roues à double boudin) ;
#   - chaque rail intérieur naît contre le rail extérieur opposé, après la
#     lacune du boudin de l'autre rame : nez en rampe 9 m après la fourche ;
#   - les deux rails intérieurs se croisent en X à 27,5 m (cœur coulé sans
#     ornière : les roues intérieures sont plates et larges) ;
#   - le câble de la rame opposée traverse le rail intérieur à 17 m par une
#     fenêtre (« trou ménagé dans la voie intérieure ») : âme et patin
#     découpés, tête renforcée qui porte la roue plate au-dessus du câble ;
#   - galets de déviation inclinés du côté intérieur du coude du câble.
# ---------------------------------------------------------------------------

# Galets de l'aiguillage : décalages depuis la fourche (1611 m en bas,
# 1813 m en haut, en miroir). La traversée du rail est à +17 m : aucun
# galet à moins de 3,6 m (audit).
const ABT_STATIONS: Array = [-3.4, 4.5, 11.0, 22.0, 31.0, 40.0]
# Stations équipées d'un galet de déviation incliné. Pas à +11 m : le rail
# intérieur opposé arrive contre le câble, il n'y a pas la place.
const ABT_SHEAVE_STATIONS: Array = [4.5, 22.0, 31.0, 40.0]
const ABT_ZONE: float = 45.0              # étendue de l'aiguillage depuis la fourche (m)
@export var abt_flangeway: float = 0.060  # boudin 30 mm + jeu
@export var abt_nose_len: float = 1.2     # rampe du nez du rail intérieur
@export var abt_nose_flare: float = 0.03  # nez écarté du rail extérieur voisin
@export var abt_frog_half: float = 2.0    # demi-longueur du cœur en X
@export var abt_cable_clear: float = 0.015  # jeu câble / acier dans les fenêtres
@export var abt_switch_d: float = 0.95    # écart de voie en deçà duquel les rails intérieurs sont sur socles étroits
@export var sheave_radius: float = 0.16
@export var sheave_thickness: float = 0.05
@export var sheave_incline_deg: float = 30.0
@export var roller_tilt_max: float = 0.56   # 32° : au-delà, les deux galets d'une paire se touchent

var _stations: Array = []       # [{s, paired, sheave}]
var _strand: Dictionary = {}    # −1 / +1 → [{s, p, x, y, tilt, center, basis}]
var _abt: Dictionary = {}       # nez, cœurs en X, fenêtres (cf. _compute_abt)


func _in_abt_zone(s: float) -> bool:
	return (s > PNConstants.PASSING_START - 5.0 and s < PNConstants.PASSING_START + ABT_ZONE) \
		or (s > PNConstants.PASSING_END - ABT_ZONE and s < PNConstants.PASSING_END + 5.0)


# Abscisses des galets : grille réelle (3474 m / 256 paires) hors
# aiguillages, stations dessinées dans les aiguillages.
func _station_list() -> Array:
	var out: Array = []
	var n_total: int = int(PNConstants.LENGTH / guide_spacing)
	for i in range(n_total):
		var s: float = (float(i) + 0.5) * guide_spacing
		if not _in_abt_zone(s):
			out.append({"s": s, "sheave": false})
	for o in ABT_STATIONS:
		var sh: bool = ABT_SHEAVE_STATIONS.has(o)
		out.append({"s": PNConstants.PASSING_START + o, "sheave": sh})
		out.append({"s": PNConstants.PASSING_END - o, "sheave": sh})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.s < b.s)
	for st in out:
		# support commun aux deux brins tant qu'ils sont côte à côte
		st["paired"] = absf(tunnel.passing_loop_offset(st.s, 1.0)) < 0.05
	return out


func _roller_axis_y() -> float:
	# 🔴 Retour d'essai 2026-09-27 : le câble au niveau des blochets (4 cm
	# au-dessus de leur dessus), pas du sommet du rail. On part de la
	# hauteur voulue du câble et on en déduit l'axe des galets.
	var y_cable_center: float = floor_y_local + slab_thickness + sleeper_height + 0.04
	return y_cable_center - cable_radius - pulley_radius


# Inclinaison de CHAQUE galet dans son support (le support reste
# horizontal, les deux galets d'une paire à la même hauteur — retour
# d'essai 2026-09-26). Le câble tendu appuie sur le galet avec T·Δθ vers
# l'intérieur de la courbe et son poids w·L vers le bas : le galet
# s'incline dans le sens de la résultante (73 à 78° dans les courbes,
# audit). Plafond 32° : au-delà les deux galets d'une paire se touchent,
# le reste passe par le flanc de la gorge. Le signe suit l'ancienne
# convention (virage à droite → rotation négative autour de l'avant).
func _roller_tilt(s: float, side: float, span: float) -> float:
	var ds: float = 5.0
	var kh: float = deg_to_rad(SlopeProfile.heading_at(s + ds) - SlopeProfile.heading_at(s - ds)) / (2.0 * ds)
	if side != 0.0:
		var x_m: float = tunnel.passing_loop_offset(s - ds, side)
		var x_0: float = tunnel.passing_loop_offset(s, side)
		var x_p: float = tunnel.passing_loop_offset(s + ds, side)
		kh += (x_p - 2.0 * x_0 + x_m) / (ds * ds)
	var t_n: float = PNConstants.T_NOMINAL_DAN * 10.0
	var w: float = PNConstants.CABLE_KG_M * 9.80665
	var lat: float = t_n * kh * span
	var ver: float = w * span * cos(SlopeProfile.slope_angle_at(s)) \
		- t_n * SlopeProfile.slope_curvature_at(s) * span
	var phi: float = atan2(lat, maxf(ver, 1.0))
	return clampf(-phi, -roller_tilt_max, roller_tilt_max)


# Galets puis câble : chaque brin est une ligne brisée dont les sommets
# sont les points de contact dans la gorge des galets.
func _compute_cable_geometry() -> void:
	_stations = _station_list()
	var y_axis: float = _roller_axis_y()
	var y_nom: float = y_axis + pulley_radius + cable_radius
	_strand = {}
	for side_i in [-1, 1]:
		var side: float = float(side_i)
		var pts: Array = [_strand_free_point(0.0, side, y_nom)]
		for k in range(_stations.size()):
			var st: Dictionary = _stations[k]
			var s: float = st.s
			var s_prev: float = _stations[k - 1].s if k > 0 else 0.0
			var s_next: float = _stations[k + 1].s if k + 1 < _stations.size() else PNConstants.LENGTH
			var xf: Transform3D = tunnel.transform_at(s)
			var x_nom: float = _track_center_x(s, side) + side * pulley_pair_offset
			# galet de déviation présent → il prend l'effort latéral, le
			# galet porteur reste droit
			var tilt: float = 0.0 if st.sheave else _roller_tilt(s, side, 0.5 * (s_next - s_prev))
			var fwd: Vector3 = (-xf.basis.z).normalized()
			var rb: Basis = xf.basis.rotated(fwd, tilt)
			var center: Vector3 = xf.origin + xf.basis.y * y_axis + xf.basis.x * x_nom
			var p: Vector3 = center + rb.y.normalized() * (pulley_radius + cable_radius)
			var rel: Vector3 = p - xf.origin
			pts.append({"s": s, "p": p, "x": rel.dot(xf.basis.x), "y": rel.dot(xf.basis.y),
				"tilt": tilt, "center": center, "basis": rb})
		pts.append(_strand_free_point(PNConstants.LENGTH, side, y_nom))
		_strand[side_i] = pts
	_compute_abt()


func _strand_free_point(s: float, side: float, y_nom: float) -> Dictionary:
	var xf: Transform3D = tunnel.transform_at(s)
	var x: float = _track_center_x(s, side) + side * pulley_pair_offset
	return {"s": s, "p": xf.origin + xf.basis.x * x + xf.basis.y * y_nom, "x": x, "y": y_nom,
		"tilt": 0.0}


# Point 3D du brin à l'abscisse s : sur la corde droite entre les deux
# galets qui l'encadrent.
func strand_point(side_i: int, s: float) -> Vector3:
	var pts: Array = _strand[side_i]
	var lo: int = 0
	var hi: int = pts.size() - 1
	while hi - lo > 1:
		var mid: int = (lo + hi) / 2
		if pts[mid].s <= s:
			lo = mid
		else:
			hi = mid
	var a: Dictionary = pts[lo]
	var b: Dictionary = pts[hi]
	var t: float = clampf((s - a.s) / maxf(b.s - a.s, 1e-6), 0.0, 1.0)
	return (a.p as Vector3).lerp(b.p, t)


# Position du brin dans le repère local de la voie à s (x latéral, y haut).
func strand_local_at(side_i: int, s: float) -> Vector2:
	var xf: Transform3D = tunnel.transform_at(s)
	var rel: Vector3 = strand_point(side_i, s) - xf.origin
	return Vector2(rel.dot(xf.basis.x), rel.dot(xf.basis.y))


# Axe latéral du rail intérieur de la voie rail_i (−1 gauche, +1 droite).
func inner_rail_x(rail_i: int, s: float) -> float:
	return _track_center_x(s, float(rail_i)) - float(rail_i) * gauge_m * 0.5


func _strand_rail_gap(cable_i: int, rail_i: int, s: float) -> float:
	return strand_local_at(cable_i, s).x - inner_rail_x(rail_i, s)


# Abscisse (depuis la fourche basse) où l'écart de voie vaut dv.
func _loop_ds_for_offset(dv: float) -> float:
	var a: float = 0.0
	var b: float = (PNConstants.PASSING_END - PNConstants.PASSING_START) * 0.5
	for _it in range(50):
		var m: float = 0.5 * (a + b)
		if absf(tunnel.passing_loop_offset(PNConstants.PASSING_START + m, 1.0)) < dv:
			a = m
		else:
			b = m
	return 0.5 * (a + b)


func _compute_abt() -> void:
	var hg: float = gauge_m * 0.5
	var s0: float = PNConstants.PASSING_START
	var s1: float = PNConstants.PASSING_END
	# nez : la tête du rail intérieur laisse l'ornière du boudin de l'autre
	# rame contre le rail extérieur opposé (2d − tête ≥ ornière)
	var ds_nose: float = _loop_ds_for_offset((rail_head_width + abt_flangeway) * 0.5)
	var ds_x: float = _loop_ds_for_offset(hg)
	var ds_sw: float = _loop_ds_for_offset(abt_switch_d)
	_abt = {
		"nose_lo": s0 + ds_nose, "nose_hi": s1 - ds_nose,
		"frog": [s0 + ds_x, s1 - ds_x],
		"switch_lo": s0 + ds_sw, "switch_hi": s1 - ds_sw,
		"windows": [],
	}
	# Fenêtres : le brin OPPOSÉ traverse chaque rail intérieur (rail de la
	# voie gauche traversé par le brin droit, et réciproquement).
	for rail_i in [-1, 1]:
		var cable_i: int = -rail_i
		for zone in [[_abt.nose_lo, s0 + ABT_ZONE], [s1 - ABT_ZONE, _abt.nose_hi]]:
			var s: float = zone[0]
			var f_prev: float = _strand_rail_gap(cable_i, rail_i, s)
			while s < zone[1] - 1e-6:
				var s_n: float = minf(s + 0.1, zone[1])
				var f_n: float = _strand_rail_gap(cable_i, rail_i, s_n)
				if signf(f_n) != signf(f_prev):
					var a: float = s
					var b: float = s_n
					for _it in range(30):
						var m: float = 0.5 * (a + b)
						if signf(_strand_rail_gap(cable_i, rail_i, m)) == signf(f_prev):
							a = m
						else:
							b = m
					var sc: float = 0.5 * (a + b)
					var rel: float = absf(_strand_rail_gap(cable_i, rail_i, sc + 0.5)
						- _strand_rail_gap(cable_i, rail_i, sc - 0.5))
					rel = maxf(rel, 1e-3)
					var l_web: float = 2.0 * (cable_radius + rail_web_width * 0.5 + abt_cable_clear) / rel
					var l_foot: float = 2.0 * (cable_radius + rail_foot_width * 0.5 + abt_cable_clear) / rel
					_abt.windows.append({"rail": rail_i, "cable": cable_i, "s": sc,
						"web": Vector2(sc - l_web * 0.5, sc + l_web * 0.5),
						"foot": Vector2(sc - l_foot * 0.5, sc + l_foot * 0.5)})
				f_prev = f_n
				s = s_n


func abt_info() -> Dictionary:
	return _abt


func strand_vertices(side_i: int) -> Array:
	return _strand[side_i]


func station_list() -> Array:
	return _stations


# Rail intérieur de l'évitement, du nez bas au nez haut : nez en rampe,
# fenêtres de câble, cœur en X. Profil par tronçon (patin/âme/tête).
func _build_inner_rail(
	rail_mat: StandardMaterial3D, rail_top_mat: StandardMaterial3D,
	rail_i: int, name: String,
) -> void:
	var a: float = _abt.nose_lo
	var b: float = _abt.nose_hi
	var cuts: Array = [a + abt_nose_len, b - abt_nose_len]
	for sx in _abt.frog:
		cuts.append(sx - abt_frog_half)
		cuts.append(sx + abt_frog_half)
	var wins: Array = []
	for w in _abt.windows:
		if w.rail == rail_i:
			wins.append(w)
			for v in [w.web.x, w.web.y, w.foot.x, w.foot.y]:
				cuts.append(v)
	var s_list: Array = _adaptive_s_list(a, b, float(rail_i))
	for c in cuts:
		s_list.append(c)
	var k: float = a
	while k < a + abt_nose_len:
		s_list.append(k)
		k += 0.15
	k = b - abt_nose_len
	while k < b:
		s_list.append(k)
		k += 0.15
	s_list.sort()
	var clean: Array = []
	for s in s_list:
		if s < a - 1e-6 or s > b + 1e-6:
			continue
		if clean.is_empty() or s - clean[-1] > 0.002:
			clean.append(s)

	var rail_base_y: float = floor_y_local + slab_thickness + sleeper_height - 0.01
	var hw: float = rail_head_width * 0.5
	var foot_y1: float = rail_base_y + 0.035
	var web_y1: float = rail_base_y + 0.140
	var top_y: float = rail_base_y + rail_height - (0.0004 if rail_i > 0 else 0.0)

	var st_rail: SurfaceTool = null
	var st_top: SurfaceTool = null
	var chunk_start: float = a
	var chunk_i: int = 0
	var prev_key: String = ""
	for i in range(clean.size() - 1):
		var s0_: float = clean[i]
		var s1_: float = clean[i + 1]
		if st_rail == null:
			st_rail = SurfaceTool.new()
			st_rail.begin(Mesh.PRIMITIVE_TRIANGLES)
			st_rail.set_material(rail_mat)
			st_top = SurfaceTool.new()
			st_top.begin(Mesh.PRIMITIVE_TRIANGLES)
			st_top.set_material(rail_top_mat)
			chunk_start = s0_
		var m: float = 0.5 * (s0_ + s1_)
		var key: String = "full"
		for sx in _abt.frog:
			if absf(m - sx) < abt_frog_half:
				key = "frog"
		if key == "full":
			for w in wins:
				if m > w.web.x and m < w.web.y:
					key = "deep"
				elif key == "full" and m > w.foot.x and m < w.foot.y:
					key = "nofoot"
		var nose: bool = m < a + abt_nose_len or m > b - abt_nose_len
		if nose:
			key = "nose"
		var xf0: Transform3D = tunnel.transform_at(s0_)
		var xf1: Transform3D = tunnel.transform_at(s1_)
		var p0: Vector3 = xf0.origin
		var p1: Vector3 = xf1.origin
		var r0: Vector3 = xf0.basis.x
		var r1: Vector3 = xf1.basis.x
		var u0: Vector3 = xf0.basis.y
		var u1: Vector3 = xf1.basis.y
		var cx0: float = inner_rail_x(rail_i, s0_) + _nose_flare(rail_i, s0_)
		var cx1: float = inner_rail_x(rail_i, s1_) + _nose_flare(rail_i, s1_)
		# pièces du profil : [y_bas, y_haut, demi-largeur] aux deux bouts
		var parts: Array = []
		var top0: float = top_y
		var top1: float = top_y
		match key:
			"nose":
				top0 = rail_base_y + rail_height * _nose_height(s0_)
				top1 = rail_base_y + rail_height * _nose_height(s1_)
				parts.append([rail_base_y, top0 - 0.012, rail_base_y, top1 - 0.012, hw])
			"frog":
				parts.append([rail_base_y, top_y - 0.012, rail_base_y, top_y - 0.012, hw])
			"deep":
				# tête renforcée seule : le câble passe dessous (jeu 3 cm)
				parts.append([web_y1 - 0.030, top_y - 0.012, web_y1 - 0.030, top_y - 0.012, hw])
			"nofoot":
				parts.append([foot_y1, web_y1, foot_y1, web_y1, rail_web_width * 0.5])
				parts.append([web_y1, top_y - 0.012, web_y1, top_y - 0.012, hw])
			_:
				parts.append([rail_base_y, foot_y1, rail_base_y, foot_y1, rail_foot_width * 0.5])
				parts.append([foot_y1, web_y1, foot_y1, web_y1, rail_web_width * 0.5])
				parts.append([web_y1, top_y - 0.012, web_y1, top_y - 0.012, hw])
		for pt in parts:
			_emit_box_step(st_rail, p0, r0, u0, p1, r1, u1, cx0, cx1,
				pt[0], pt[1], pt[2], pt[3], pt[4], s0_, s1_)
		_emit_box_step(st_top, p0, r0, u0, p1, r1, u1, cx0, cx1,
			top0 - 0.012, top0, top1 - 0.012, top1, hw, s0_, s1_)
		# faces d'about là où le profil change (et aux deux nez)
		if key != prev_key:
			for pt in parts:
				_emit_cap(st_rail, p0, r0, u0, cx0, pt[0], pt[1], pt[4])
		var next_key: String = _inner_key_at(rail_i, 0.5 * (s1_ + (clean[i + 2] if i + 2 < clean.size() else s1_ + 0.01)), wins, a, b)
		if next_key != key or i == clean.size() - 2:
			for pt in parts:
				_emit_cap(st_rail, p1, r1, u1, cx1, pt[2], pt[3], pt[4])
		prev_key = key
		if s1_ - chunk_start >= chunk_length or i == clean.size() - 2:
			_commit_rail_chunk(st_rail, st_top, "%s_%d" % [name, chunk_i])
			st_rail = null
			st_top = null
			chunk_i += 1


func _inner_key_at(rail_i: int, m: float, wins: Array, a: float, b: float) -> String:
	if m < a + abt_nose_len or m > b - abt_nose_len:
		return "nose"
	for sx in _abt.frog:
		if absf(m - sx) < abt_frog_half:
			return "frog"
	var key: String = "full"
	for w in wins:
		if m > w.web.x and m < w.web.y:
			return "deep"
		if m > w.foot.x and m < w.foot.y:
			key = "nofoot"
	return key


# Rampe du nez : 35 % de la hauteur à la pointe, pleine hauteur après
# abt_nose_len (la roue plate monte dessus sans choc).
func _nose_height(s: float) -> float:
	var t: float = minf((s - _abt.nose_lo) / abt_nose_len, (_abt.nose_hi - s) / abt_nose_len)
	return lerpf(0.35, 1.0, smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0)))


# Pointe écartée du rail extérieur voisin (rail gauche vers −x, droit vers +x).
func _nose_flare(rail_i: int, s: float) -> float:
	var t: float = minf((s - _abt.nose_lo) / abt_nose_len, (_abt.nose_hi - s) / abt_nose_len)
	t = clampf(t, 0.0, 1.0)
	return float(rail_i) * abt_nose_flare * (1.0 - t) * (1.0 - t)


func _commit_rail_chunk(st_rail: SurfaceTool, st_top: SurfaceTool, name: String) -> void:
	st_rail.generate_normals()
	st_rail.generate_tangents()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = name
	mi.mesh = st_rail.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	st_top.generate_normals()
	st_top.generate_tangents()
	var mt: MeshInstance3D = MeshInstance3D.new()
	mt.name = name + "Top"
	mt.mesh = st_top.commit()
	mt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mt)


# Tronçon de profil rectangulaire dont les hauteurs peuvent différer aux
# deux bouts (nez en rampe) : faces gauche, droite, dessus et dessous.
func _emit_box_step(
	st: SurfaceTool,
	p0: Vector3, r0: Vector3, u0: Vector3,
	p1: Vector3, r1: Vector3, u1: Vector3,
	cx0: float, cx1: float,
	ya0: float, yb0: float, ya1: float, yb1: float, w: float,
	v0: float, v1: float,
) -> void:
	var a00: Vector3 = _pt(p0, r0, u0, cx0 - w, ya0)
	var a01: Vector3 = _pt(p0, r0, u0, cx0 + w, ya0)
	var a10: Vector3 = _pt(p0, r0, u0, cx0 + w, yb0)
	var a11: Vector3 = _pt(p0, r0, u0, cx0 - w, yb0)
	var b00: Vector3 = _pt(p1, r1, u1, cx1 - w, ya1)
	var b01: Vector3 = _pt(p1, r1, u1, cx1 + w, ya1)
	var b10: Vector3 = _pt(p1, r1, u1, cx1 + w, yb1)
	var b11: Vector3 = _pt(p1, r1, u1, cx1 - w, yb1)
	_emit_quad_strip(st, a00, a11, b00, b11,
		Vector2(0.0, v0), Vector2(0.1, v0), Vector2(0.0, v1), Vector2(0.1, v1))
	_emit_quad_strip(st, a01, b01, a10, b10,
		Vector2(0.0, v0), Vector2(0.0, v1), Vector2(0.1, v0), Vector2(0.1, v1))
	_emit_quad_strip(st, a11, a10, b11, b10,
		Vector2(0.0, v0), Vector2(1.0, v0), Vector2(0.0, v1), Vector2(1.0, v1))
	# dessous (visible dans les fenêtres, sous la tête renforcée)
	_emit_quad_strip(st, a01, a00, b01, b00,
		Vector2(0.0, v0), Vector2(1.0, v0), Vector2(0.0, v1), Vector2(1.0, v1))


# Face d'about d'une pièce de rail, émise des deux côtés.
func _emit_cap(st: SurfaceTool, p: Vector3, r: Vector3, u: Vector3,
		cx: float, y0: float, y1: float, w: float) -> void:
	var q0: Vector3 = _pt(p, r, u, cx - w, y0)
	var q1: Vector3 = _pt(p, r, u, cx + w, y0)
	var q2: Vector3 = _pt(p, r, u, cx + w, y1)
	var q3: Vector3 = _pt(p, r, u, cx - w, y1)
	for tri in [[q0, q1, q2], [q0, q2, q3], [q0, q2, q1], [q0, q3, q2]]:
		for q in tri:
			st.set_uv(Vector2(0.0, 0.0))
			st.add_vertex(q)


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
	_build_slab_section(slab_mat, pit_low_end, PNConstants.PASSING_START, 0.0, "SlabLow", false)
	_build_slab_section(slab_mat, PNConstants.PASSING_START, PNConstants.PASSING_END, 0.0, "SlabPassingChamber", true)
	_build_slab_section(slab_mat, PNConstants.PASSING_END, pit_high_start, 0.0, "SlabHigh", false)


# Construit un tronçon de dalle entre s_start et s_end avec un offset latéral.
# `side` : 0 = pas de divergence (centré), -1/+1 = suit passing_loop_offset(s, side).
# `is_chamber` : true → la dalle s'élargit symétriquement (centrée) pour couvrir
# toute la largeur de la chambre tunnel ; demi-largeur croît de slab_width/2
# à slab_width/2 + abs(passing_loop_offset(s, 1.0)).
func _build_slab_section(
	mat: StandardMaterial3D, s_start: float, s_end: float,
	side: float, name: String, is_chamber: bool = false,
) -> void:
	# Découpage en tronçons de chunk_length pour un frustum culling efficace.
	var c_start: float = s_start
	var chunk_i: int = 0
	while c_start < s_end - 0.001:
		var c_end: float = minf(c_start + chunk_length, s_end)
		_build_slab_chunk(mat, c_start, c_end, side,
			"%s_%d" % [name, chunk_i], is_chamber)
		c_start = c_end
		chunk_i += 1


func _build_slab_chunk(
	mat: StandardMaterial3D, s_start: float, s_end: float,
	side: float, name: String, is_chamber: bool,
) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)

	var base_half_w: float = slab_width * 0.5
	var slab_top_y: float = floor_y_local + slab_thickness
	var slab_bot_y: float = floor_y_local

	# Référence d'adaptativité : en chambre, l'élargissement sinusoïdal des
	# bords suit passing_loop_offset(s, 1) → on échantillonne sur ce chemin.
	var ref_side: float = 1.0 if is_chamber else side
	var s_list: Array = _adaptive_s_list(s_start, s_end, ref_side)

	var prev_s: float = s_list[0]
	var prev_xform: Transform3D = tunnel.transform_at(prev_s)
	var prev_off: float = _track_center_x(prev_s, side)
	var prev_half_w: float = base_half_w
	if is_chamber:
		prev_half_w += absf(tunnel.passing_loop_offset(prev_s, 1.0))
	for i in range(1, s_list.size()):
		var s_cur: float = s_list[i]
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

		var v0: float = prev_s
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

		prev_s = s_cur
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


# Point 3D du chemin de référence (spline + offset latéral de voie) à s.
func _path_point(s: float, side: float) -> Vector3:
	var xf: Transform3D = tunnel.transform_at(s)
	return xf.origin + xf.basis.x * _track_center_x(s, side)


# Échantillonnage adaptatif : liste de s croissants entre s_start et s_end
# tels que la corde entre 2 échantillons consécutifs dévie de moins de
# chord_tolerance du chemin réel (test au point milieu, pas divisé par 2
# jusqu'à sampling_step si besoin). Ligne droite → pas de max_step.
func _adaptive_s_list(s_start: float, s_end: float, side: float) -> Array:
	var out: Array = [s_start]
	var s: float = s_start
	while s < s_end - 0.001:
		var step: float = minf(max_step, s_end - s)
		while step > sampling_step + 0.001:
			var pa: Vector3 = _path_point(s, side)
			var pb: Vector3 = _path_point(s + step, side)
			var pm: Vector3 = _path_point(s + step * 0.5, side)
			if pm.distance_to((pa + pb) * 0.5) <= chord_tolerance:
				break
			step *= 0.5
		step = maxf(step, minf(sampling_step, s_end - s))
		s = minf(s + step, s_end)
		out.append(s)
	return out


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
	# Rails intérieurs de l'évitement, d'un nez à l'autre : nez en rampe,
	# fenêtres où passe le câble opposé, cœur en X (cf. _compute_abt).
	_build_inner_rail(rail_mat, rail_top_mat, -1, "RailInnerLeft")
	_build_inner_rail(rail_mat, rail_top_mat, 1, "RailInnerRight")


# Construit un rail entre s_start et s_end, x_local = passing_loop_offset(s, side) + hg_signed.
# (Si side==0, x_local = hg_signed → rail à x constant pour voie unique centrée.)
func _build_rail_strip(
	rail_mat: StandardMaterial3D, rail_top_mat: StandardMaterial3D,
	s_start: float, s_end: float, side: float, hg_signed: float, name: String,
) -> void:
	# Découpage en tronçons de chunk_length pour un frustum culling efficace.
	var c_start: float = s_start
	var chunk_i: int = 0
	while c_start < s_end - 0.001:
		var c_end: float = minf(c_start + chunk_length, s_end)
		_build_rail_chunk(rail_mat, rail_top_mat, c_start, c_end, side,
			hg_signed, "%s_%d" % [name, chunk_i])
		c_start = c_end
		chunk_i += 1


func _build_rail_chunk(
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

	var s_list: Array = _adaptive_s_list(s_start, s_end, side)

	var prev_s: float = s_list[0]
	var prev_xform: Transform3D = tunnel.transform_at(prev_s)
	var prev_cx: float = _track_center_x(prev_s, side) + hg_signed
	for i in range(1, s_list.size()):
		var s_cur: float = s_list[i]
		var cur_xform: Transform3D = tunnel.transform_at(s_cur)
		var cur_cx: float = _track_center_x(s_cur, side) + hg_signed

		var p0: Vector3 = prev_xform.origin
		var p1: Vector3 = cur_xform.origin
		var r0: Vector3 = prev_xform.basis.x
		var r1: Vector3 = cur_xform.basis.x
		var u0: Vector3 = prev_xform.basis.y
		var u1: Vector3 = cur_xform.basis.y

		var v0: float = prev_s
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

		prev_s = s_cur
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
	# Blochets béton un peu plus sombres que la dalle pour les rendre
	# clairement visibles depuis loin (avant le tuning : delta de 0.06
	# seulement avec la dalle → indistinguables au-delà de 5 m).
	#
	# Fidèle aux photos du vrai Perce-Neige (2026-04-26) : PAS de traverse
	# continue entre les rails — chaque rail repose sur sa propre rangée
	# de blochets indépendants, le canal central restant libre pour la
	# longrine des galets du câble (cf. _build_cable_beam).
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.21, 0.19)
	mat.roughness = 0.95
	mat.metallic = 0.0

	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(block_width, sleeper_height, sleeper_width)
	box.material = mat

	# Construit la liste des positions : un blochet SOUS CHAQUE RAIL
	# (x = centre de voie ± demi-écartement).
	# - Hors loop plat : 1 voie centrée → 2 blochets
	# - Dans loop plat [PASSING_START, PASSING_END] : 2 voies décalées par
	#   tunnel.passing_loop_offset(s, ±1) → 4 blochets
	var hg: float = gauge_m * 0.5
	var positions: Array = []  # [{s: float, off: float}, ...] — off = centre du blochet
	var n_total: int = int(PNConstants.LENGTH / sleeper_spacing)
	for i in range(n_total):
		var s: float = (float(i) + 0.5) * sleeper_spacing
		if s < pit_low_end or s > pit_high_start:
			continue   # au-dessus des fosses de gare, les rails sont sur poutres
		if s < PNConstants.PASSING_START or s > PNConstants.PASSING_END:
			positions.append({"s": s, "off": -hg, "w": block_width})
			positions.append({"s": s, "off": hg, "w": block_width})
			continue
		# Évitement : blochets sous les rails extérieurs ; rails intérieurs
		# du nez au nez seulement. Dans l'aiguillage (écart < 0,95 m), socles
		# étroits sous les rails intérieurs (un seul là où ils se croisent,
		# aucun là où ils touchent le blochet du rail extérieur voisin) —
		# avant, les blochets des deux voies se superposaient.
		var d: float = absf(tunnel.passing_loop_offset(s, 1.0))
		positions.append({"s": s, "off": -d - hg, "w": block_width})
		positions.append({"s": s, "off": d + hg, "w": block_width})
		if s < _abt.nose_lo or s > _abt.nose_hi:
			continue
		var xl: float = hg - d        # rail intérieur de la voie gauche
		var xr: float = d - hg        # rail intérieur de la voie droite
		if d >= abt_switch_d:
			positions.append({"s": s, "off": xl, "w": block_width})
			positions.append({"s": s, "off": xr, "w": block_width})
		elif absf(xl - xr) < 0.22:
			positions.append({"s": s, "off": 0.5 * (xl + xr), "w": 0.30, "low": true})
		elif 2.0 * d >= 0.30:
			positions.append({"s": s, "off": xl, "w": 0.20, "low": true})
			positions.append({"s": s, "off": xr, "w": 0.20, "low": true})

	var xforms: Array = []
	var y_center: float = floor_y_local + slab_thickness + sleeper_height * 0.5 - 0.01
	for entry in positions:
		var xform: Transform3D = tunnel.transform_at(entry.s)
		var tr: Transform3D = xform
		# socle étroit : 2 mm plus bas que le blochet voisin (pas de
		# scintillement des dessus coplanaires qui se chevauchent)
		var low: float = 0.002 if entry.get("low", false) else 0.0
		tr.basis = xform.basis * Basis.from_scale(Vector3(entry.w / block_width, 1.0, 1.0))
		tr.origin += xform.basis.y * (y_center - low) + xform.basis.x * entry.off
		xforms.append(tr)
	_mm_instance(box, xforms, "Sleepers")


# ---------------------------------------------------------------------------
# Escalier métallique de service le long de la voie (vidéo cabine du
# 2026-04-26 : échelle à marches à DROITE en montant, câble main-courante
# sur potelets ; les gros câbles noirs et les boîtiers sont à gauche).
# Marches horizontales tous les 0,45 m d'abscisse (à 30 % : 13 cm de
# dénivelé par marche), deux limons, potelets tous les 3 m + câble.
# Boîtiers gris sur le mur gauche tous les 24 m. Tout en MultiMesh.
# ---------------------------------------------------------------------------

# Fosses de gare (photos 093522 / 094104 en bas, 095509 / 095443 en haut) :
# la dalle et les blochets s'arrêtent, les rails passent sur la fosse.
# Mêmes bornes dans stations_builder (PIT_LOW_END / PIT_HIGH_START).
@export var pit_low_end: float = 4.5
@export var pit_high_start: float = PNConstants.LENGTH   # pas de fosse en haut
@export var walkway_side: float = 1.0        # +1 = droite en montant (vidéo)
@export var walkway_x: float = 1.02          # décalage latéral du milieu de l'escalier
@export var walkway_step_s: float = 0.45     # espacement des marches le long de s
@export var walkway_post_s: float = 3.0      # espacement des potelets
@export var walkway_handrail: bool = false   # pas de rambarde sur le vrai escalier


func _walkway_frame(s: float) -> Transform3D:
	# repère de pose : origine sur le bord, X = travers, Y = monde haut
	var xf: Transform3D = tunnel.transform_at(s)
	var off: float = _track_center_x(s, walkway_side) if (
		s >= PNConstants.PASSING_START - 60.0 and s <= PNConstants.PASSING_END + 60.0) else 0.0
	var origin: Vector3 = xf.origin + xf.basis.x * (off + walkway_side * walkway_x) \
		+ xf.basis.y * (floor_y_local + slab_thickness + 0.08)
	var fwd: Vector3 = -xf.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	return Transform3D(Basis(right, Vector3.UP, -fwd), origin)


func _mm_instance(mesh: Mesh, xforms: Array, name: String) -> void:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# bancs sans GPU : le serveur de rendu factice ne garde pas les
	# transformées des instances, on en garde une copie à la demande
	if keep_instance_xforms:
		mmi.set_meta("xforms", xforms)
	add_child(mmi)


func _build_walkway() -> void:
	var galva: StandardMaterial3D = StandardMaterial3D.new()
	galva.albedo_color = Color(0.52, 0.53, 0.52)
	galva.roughness = 0.6
	galva.metallic = 0.6
	var tread: BoxMesh = BoxMesh.new()
	tread.size = Vector3(0.44, 0.035, 0.24)
	tread.material = galva
	var stringer: BoxMesh = BoxMesh.new()
	stringer.size = Vector3(0.03, 0.09, walkway_step_s + 0.02)
	stringer.material = galva
	var post: CylinderMesh = CylinderMesh.new()
	post.top_radius = 0.018
	post.bottom_radius = 0.018
	post.height = 1.0
	post.radial_segments = 8
	post.material = galva
	var cable: BoxMesh = BoxMesh.new()
	cable.size = Vector3(0.014, 0.014, walkway_post_s + 0.05)
	cable.material = galva
	var treads: Array = []
	var stringers: Array = []
	var posts: Array = []
	var cables: Array = []
	var s: float = pit_low_end + 0.3
	while s < pit_high_start - 0.3:
		var fr: Transform3D = _walkway_frame(s)
		treads.append(fr)
		# limons alignés sur la pente (repère spline)
		var xf: Transform3D = tunnel.transform_at(s)
		var off: float = _track_center_x(s, walkway_side) if (
			s >= PNConstants.PASSING_START - 60.0 and s <= PNConstants.PASSING_END + 60.0) else 0.0
		for dx in [-0.24, 0.24]:
			var st_xf: Transform3D = xf
			st_xf.origin += xf.basis.x * (off + walkway_side * walkway_x + dx) \
				+ xf.basis.y * (floor_y_local + slab_thickness + 0.06)
			stringers.append(st_xf)
		s += walkway_step_s
	s = 1.5
	while s < PNConstants.LENGTH - 1.5:
		var fr2: Transform3D = _walkway_frame(s)
		var p: Transform3D = fr2
		p.origin += Vector3.UP * 0.5 + fr2.basis.x * (walkway_side * 0.24)
		posts.append(p)
		var xf2: Transform3D = tunnel.transform_at(s + walkway_post_s * 0.5)
		var off2: float = _track_center_x(s + walkway_post_s * 0.5, walkway_side) if (
			s >= PNConstants.PASSING_START - 60.0 and s <= PNConstants.PASSING_END + 60.0) else 0.0
		var cx: Transform3D = xf2
		cx.origin += xf2.basis.x * (off2 + walkway_side * (walkway_x + 0.24)) \
			+ xf2.basis.y * (floor_y_local + slab_thickness + 0.08 + 1.0)
		cables.append(cx)
		s += walkway_post_s
	_mm_instance(tread, treads, "WalkwayTreads")
	_mm_instance(stringer, stringers, "WalkwayStringers")
	# Pas de rambarde (retour d'essai 2026-09-26) : potelets et câble
	# main-courante calculés mais non posés, gardés pour un éventuel retour.
	if walkway_handrail:
		_mm_instance(post, posts, "WalkwayPosts")
		_mm_instance(cable, cables, "WalkwayHandCable")
	# boîtiers sur le mur gauche (côté des câbles), tous les 24 m
	var boxm: BoxMesh = BoxMesh.new()
	boxm.size = Vector3(0.12, 0.20, 0.26)
	var boxmat: StandardMaterial3D = StandardMaterial3D.new()
	boxmat.albedo_color = Color(0.58, 0.58, 0.56)
	boxmat.roughness = 0.7
	boxm.material = boxmat
	var boxes: Array = []
	s = 12.0
	while s < PNConstants.LENGTH - 12.0:
		var xf3: Transform3D = tunnel.transform_at(s)
		var off3: float = _track_center_x(s, -walkway_side) if (
			s >= PNConstants.PASSING_START - 60.0 and s <= PNConstants.PASSING_END + 60.0) else 0.0
		var bx: Transform3D = xf3
		bx.origin += xf3.basis.x * (off3 - walkway_side * 1.48) + xf3.basis.y * 0.42
		boxes.append(bx)
		s += 24.0
	_mm_instance(boxm, boxes, "WallBoxes")


# ---------------------------------------------------------------------------
# Détails du tunnel d'après les vidéos cabine (2026-04-26 et HD) :
#  - section au tunnelier (257 → 3 420 m) : revêtement LISSE et clair, un
#    peu brillant (retour d'essai 2026-09-27 : « pas des dalles de béton »
#    — les joints en quinconce de la v1.15.0 sont partis), seules de fines
#    lignes circulaires tous les 1,4 m ; canalisation grise en voûte, côté
#    droit ;
#  - galeries carrées (tranchée couverte) : joints horizontaux des banches ;
#  - évitement Abt : plaques de cœur de croisement (les roues
#    extérieures à double boudin guident, les intérieures sont plates et
#    passent le cœur ; « le câble du véhicule opposé passe dans un trou
#    ménagé dans la voie intérieure », dossier remontees-mecaniques.net),
#    réglettes lumineuses supplémentaires (la chambre est bien éclairée).
# Tout en MultiMesh.
# ---------------------------------------------------------------------------

@export var ring_joint_spacing: float = 1.4


func _in_loop_zone(s: float) -> bool:
	return s >= PNConstants.PASSING_START - 60.0 and s <= PNConstants.PASSING_END + 60.0


func _build_tunnel_details() -> void:
	var joint_mat: StandardMaterial3D = StandardMaterial3D.new()
	joint_mat.albedo_color = Color(0.50, 0.50, 0.49)   # à peine plus sombre que la paroi
	joint_mat.roughness = 0.6
	var pipe_mat: StandardMaterial3D = StandardMaterial3D.new()
	pipe_mat.albedo_color = Color(0.55, 0.56, 0.55)
	pipe_mat.roughness = 0.5
	pipe_mat.metallic = 0.4
	var frog_mat: StandardMaterial3D = StandardMaterial3D.new()
	frog_mat.albedo_color = Color(0.20, 0.20, 0.22)
	frog_mat.roughness = 0.45
	frog_mat.metallic = 0.8
	var lamp_mat: StandardMaterial3D = StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(0.9, 0.95, 1.0)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(0.75, 0.85, 1.0)
	lamp_mat.emission_energy_multiplier = 3.0
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# --- fines lignes circulaires (section circulaire, hors évitement)
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = tunnel.tunnel_radius - 0.015
	ring.outer_radius = tunnel.tunnel_radius + 0.005
	ring.rings = 40
	ring.ring_segments = 6
	ring.material = joint_mat
	var rings: Array = []
	var s: float = PNConstants.SQUARE_SECTION_LOW_END + 0.7
	while s < PNConstants.SQUARE_SECTION_HIGH_START:
		if not _in_loop_zone(s):
			var xf: Transform3D = tunnel.transform_at(s)
			var tangent: Vector3 = -xf.basis.z
			# TorusMesh a son axe en Y → axe le long de la voie
			var rb: Basis = Basis(xf.basis.x, tangent, -xf.basis.y)
			rings.append(Transform3D(rb, xf.origin))
		s += ring_joint_spacing
	_mm_instance(ring, rings, "SegmentRings")

	# --- canalisation en voûte à droite (section circulaire, hors évitement)
	var pipe: BoxMesh = BoxMesh.new()
	pipe.size = Vector3(0.07, 0.07, 4.06)
	pipe.material = pipe_mat
	var pipes: Array = []
	s = PNConstants.SQUARE_SECTION_LOW_END + 2.0
	while s < PNConstants.SQUARE_SECTION_HIGH_START - 2.0:
		if not _in_loop_zone(s):
			var xf2: Transform3D = tunnel.transform_at(s)
			var tr2: Transform3D = xf2
			var rr: float = tunnel.tunnel_radius - 0.06
			tr2.origin += xf2.basis.x * (rr * sin(deg_to_rad(42.0))) + xf2.basis.y * (rr * cos(deg_to_rad(42.0)))
			pipes.append(tr2)
		s += 4.0
	_mm_instance(pipe, pipes, "CrownPipe")

	# --- joints horizontaux des galeries carrées (banches), hors salles de gare
	var hj: BoxMesh = BoxMesh.new()
	hj.size = Vector3(0.025, 0.025, 3.02)
	hj.material = joint_mat
	var hjs: Array = []
	for rng in [[tunnel.station_low_end + 3.0, PNConstants.SQUARE_SECTION_LOW_END - 1.0]]:
		s = rng[0]
		while s < rng[1]:
			var xf3: Transform3D = tunnel.transform_at(s)
			for sx in [-1.0, 1.0]:
				for yy in [-0.9, 0.1, 1.1]:
					var tr3: Transform3D = xf3
					tr3.origin += xf3.basis.x * (sx * (tunnel.horseshoe_half_width - 0.02)) + xf3.basis.y * yy
					hjs.append(tr3)
			s += 3.0
	_mm_instance(hj, hjs, "GalleryJoints")

	# --- évitement Abt : cœurs de croisement, réglettes (les « poulies
	# orange » de la v1.15.0 aux fourchements n'existent pas — retour
	# d'essai 2026-09-27)
	# semelle du cœur en X, SOUS les rails intérieurs qui s'y croisent
	# (le cœur était 8 m trop tôt et posé à mi-hauteur des rails)
	var frog: BoxMesh = BoxMesh.new()
	frog.size = Vector3(0.50, 0.03, 2.0 * abt_frog_half + 0.4)
	frog.material = frog_mat
	var frogs: Array = []
	for sf in _abt.frog:
		var xf5: Transform3D = tunnel.transform_at(sf)
		var tr5: Transform3D = xf5
		tr5.origin += xf5.basis.y * (floor_y_local + slab_thickness + sleeper_height - 0.01 - 0.015)
		frogs.append(tr5)
	_mm_instance(frog, frogs, "AbtFrogs")
	var lamp: BoxMesh = BoxMesh.new()
	lamp.size = Vector3(0.09, 0.09, 1.25)
	lamp.material = lamp_mat
	var lamps: Array = []
	s = PNConstants.PASSING_START - 40.0
	while s < PNConstants.PASSING_END + 40.0:
		var xf6: Transform3D = tunnel.transform_at(s)
		for side in [-1.0, 1.0]:
			var off: float = _track_center_x(s, side)
			var tr6: Transform3D = xf6
			tr6.origin += xf6.basis.x * (off + side * 1.45) + xf6.basis.y * 1.15
			lamps.append(tr6)
		s += 8.0
	_mm_instance(lamp, lamps, "LoopLamps")


# ---------------------------------------------------------------------------
# Longrine centrale continue — support des galets du câble tracteur.
# Sur les photos du vrai funiculaire, l'espace entre les deux rails est
# occupé par un support béton/acier CONTINU sur lequel sont fixés les
# supports de galets (256 paires sur la ligne). Les socles ponctuels de
# _build_guides posent dessus.
# ---------------------------------------------------------------------------

func _build_cable_beam() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.33, 0.31)   # béton, plus sombre que la dalle
	mat.roughness = 0.90
	mat.metallic = 0.05

	# Hors loop : UNE longrine centrale porte les deux câbles (2 galets côte
	# à côte sur chaque socle). Dans le loop : chaque voie a la sienne.
	# La fourche se fait au point où les voies se sont écartées d'une
	# demi-largeur de longrine — avant ce point, les deux longrines de voie
	# se superposeraient au centre (z-fighting) ; après, elles sont
	# disjointes et prolongent proprement la face de fin de la centrale.
	var fork_ds: float = _beam_fork_ds()
	var s_fork_lo: float = PNConstants.PASSING_START + fork_ds
	var s_fork_hi: float = PNConstants.PASSING_END - fork_ds
	_build_cable_beam_section(mat, 0.0, s_fork_lo, 0.0, "CableBeamLow")
	_build_cable_beam_section(mat, s_fork_lo, s_fork_hi, -1.0, "CableBeamLoopL")
	_build_cable_beam_section(mat, s_fork_lo, s_fork_hi, +1.0, "CableBeamLoopR")
	_build_cable_beam_section(mat, s_fork_hi, PNConstants.LENGTH, 0.0, "CableBeamHigh")


# Distance (depuis PASSING_START) à laquelle l'écartement des voies
# atteint une demi-largeur de longrine + marge → point de fourche.
func _beam_fork_ds() -> float:
	var target: float = cable_beam_width * 0.5 + 0.02
	var ds: float = 0.0
	while ds < 100.0:
		if absf(tunnel.passing_loop_offset(PNConstants.PASSING_START + ds, 1.0)) >= target:
			return ds
		ds += 0.5
	return 20.0  # fallback théorique (jamais atteint avec l'offset sin²)


func _build_cable_beam_section(
	mat: StandardMaterial3D, s_start: float, s_end: float,
	side: float, name: String,
) -> void:
	var c_start: float = s_start
	var chunk_i: int = 0
	while c_start < s_end - 0.001:
		var c_end: float = minf(c_start + chunk_length, s_end)
		_build_cable_beam_chunk(mat, c_start, c_end, side,
			"%s_%d" % [name, chunk_i])
		c_start = c_end
		chunk_i += 1


func _build_cable_beam_chunk(
	mat: StandardMaterial3D, s_start: float, s_end: float,
	side: float, name: String,
) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)

	var half_w: float = cable_beam_width * 0.5
	var y_lo: float = floor_y_local + slab_thickness - 0.01
	var y_hi: float = y_lo + cable_beam_height

	var s_list: Array = _adaptive_s_list(s_start, s_end, side)
	var prev_s: float = s_list[0]
	var prev_xform: Transform3D = tunnel.transform_at(prev_s)
	var prev_off: float = _track_center_x(prev_s, side)
	for i in range(1, s_list.size()):
		var s_cur: float = s_list[i]
		var cur_xform: Transform3D = tunnel.transform_at(s_cur)
		var cur_off: float = _track_center_x(s_cur, side)

		var p0: Vector3 = prev_xform.origin
		var p1: Vector3 = cur_xform.origin
		var r0: Vector3 = prev_xform.basis.x
		var r1: Vector3 = cur_xform.basis.x
		var u0: Vector3 = prev_xform.basis.y
		var u1: Vector3 = cur_xform.basis.y

		var v0: float = prev_s
		var v1: float = s_cur

		# Dessus
		_emit_quad_strip(
			st,
			_pt(p0, r0, u0, prev_off - half_w, y_hi),
			_pt(p0, r0, u0, prev_off + half_w, y_hi),
			_pt(p1, r1, u1, cur_off - half_w, y_hi),
			_pt(p1, r1, u1, cur_off + half_w, y_hi),
			Vector2(0.0, v0), Vector2(1.0, v0),
			Vector2(0.0, v1), Vector2(1.0, v1),
		)
		# Flanc gauche
		_emit_quad_strip(
			st,
			_pt(p0, r0, u0, prev_off - half_w, y_lo),
			_pt(p0, r0, u0, prev_off - half_w, y_hi),
			_pt(p1, r1, u1, cur_off - half_w, y_lo),
			_pt(p1, r1, u1, cur_off - half_w, y_hi),
			Vector2(0.0, v0), Vector2(0.2, v0),
			Vector2(0.0, v1), Vector2(0.2, v1),
		)
		# Flanc droite
		_emit_quad_strip(
			st,
			_pt(p0, r0, u0, prev_off + half_w, y_hi),
			_pt(p0, r0, u0, prev_off + half_w, y_lo),
			_pt(p1, r1, u1, cur_off + half_w, y_hi),
			_pt(p1, r1, u1, cur_off + half_w, y_lo),
			Vector2(0.8, v0), Vector2(1.0, v0),
			Vector2(0.8, v1), Vector2(1.0, v1),
		)

		prev_s = s_cur
		prev_xform = cur_xform
		prev_off = cur_off

	st.generate_normals()
	st.generate_tangents()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


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
	# Les socles posent sur la LONGRINE continue (cf. _build_cable_beam).
	# Positions et inclinaisons : _compute_cable_geometry (le câble tendu
	# passe exactement dans la gorge de chaque galet).
	var y_axis: float = _roller_axis_y()
	var top_slab: float = floor_y_local + slab_thickness - 0.01 + cable_beam_height
	var y_base_lo: float = top_slab
	var y_base_hi: float = top_slab + base_plate_height
	var br_h: float = clampf(y_axis + 0.06 - y_base_hi, 0.06, bracket_height)
	var y_base_center: float = (y_base_lo + y_base_hi) * 0.5
	var y_bracket_center: float = y_base_hi + br_h * 0.5

	var concrete_mat: StandardMaterial3D = StandardMaterial3D.new()
	concrete_mat.albedo_color = Color(0.42, 0.40, 0.37)
	concrete_mat.roughness = 0.92
	var steel_mat: StandardMaterial3D = StandardMaterial3D.new()
	steel_mat.albedo_color = Color(0.28, 0.28, 0.30)
	steel_mat.roughness = 0.45
	steel_mat.metallic = 0.85
	var iron_mat: StandardMaterial3D = StandardMaterial3D.new()
	iron_mat.albedo_color = Color(0.18, 0.18, 0.20)
	iron_mat.roughness = 0.35
	iron_mat.metallic = 0.95
	# Galets en polymère BLANC (vidéo cabine du 2026-04-26 : la chose la
	# plus claire du tunnel), pas en fonte sombre.
	var poly_mat: StandardMaterial3D = StandardMaterial3D.new()
	poly_mat.albedo_color = Color(0.86, 0.86, 0.82)
	poly_mat.roughness = 0.55
	poly_mat.metallic = 0.05

	var single_span: float = pulley_thickness + 0.05
	var base_pair: BoxMesh = BoxMesh.new()
	base_pair.size = Vector3(base_plate_width, base_plate_height, base_plate_length)
	base_pair.material = concrete_mat
	var base_single: BoxMesh = BoxMesh.new()
	base_single.size = Vector3(single_span + 2.0 * bracket_width + 0.06, base_plate_height, base_plate_length)
	base_single.material = concrete_mat
	var br_pair: ArrayMesh = _build_bracket_pair_mesh(
		bracket_width, br_h, bracket_span, pulley_thickness * 1.3, steel_mat)
	var br_single: ArrayMesh = _build_bracket_pair_mesh(
		bracket_width, br_h, single_span, pulley_thickness * 1.3, steel_mat)
	var pulley_mesh: CylinderMesh = CylinderMesh.new()
	pulley_mesh.top_radius = pulley_radius
	pulley_mesh.bottom_radius = pulley_radius
	pulley_mesh.height = pulley_thickness
	pulley_mesh.radial_segments = 20
	pulley_mesh.rings = 1
	pulley_mesh.material = poly_mat
	var axle_pair: CylinderMesh = CylinderMesh.new()
	axle_pair.top_radius = 0.020
	axle_pair.bottom_radius = 0.020
	axle_pair.height = bracket_span
	axle_pair.radial_segments = 10
	axle_pair.rings = 1
	axle_pair.material = iron_mat
	var axle_single: CylinderMesh = axle_pair.duplicate()
	axle_single.height = single_span

	# Rotation 90° autour de Z local : axe cylindre Y → axe perpendiculaire voie
	var rot90: Basis = Basis(Vector3(0, 0, 1), PI * 0.5)
	var l_base_p: Array = []
	var l_base_s: Array = []
	var l_br_p: Array = []
	var l_br_s: Array = []
	var l_ax_p: Array = []
	var l_ax_s: Array = []
	var l_pa: Array = []
	var l_pb: Array = []
	for k in range(_stations.size()):
		var st: Dictionary = _stations[k]
		var xf: Transform3D = tunnel.transform_at(st.s)
		var up: Vector3 = xf.basis.y
		var right: Vector3 = xf.basis.x
		if st.paired:
			l_base_p.append(Transform3D(xf.basis, xf.origin + up * y_base_center))
			l_br_p.append(Transform3D(xf.basis, xf.origin + up * y_bracket_center))
			l_ax_p.append(Transform3D(xf.basis * rot90, xf.origin + up * y_axis))
		else:
			for side_i in [-1, 1]:
				var x_nom: float = _track_center_x(st.s, float(side_i)) + float(side_i) * pulley_pair_offset
				var lat: Vector3 = right * x_nom
				l_base_s.append(Transform3D(xf.basis, xf.origin + up * y_base_center + lat))
				l_br_s.append(Transform3D(xf.basis, xf.origin + up * y_bracket_center + lat))
				l_ax_s.append(Transform3D(xf.basis * rot90, xf.origin + up * y_axis + lat))
		# galet de chaque brin : incliné dans son support autour de son centre
		for side_i in [-1, 1]:
			var v: Dictionary = _strand[side_i][k + 1]   # [0] = point libre à s = 0
			var trp: Transform3D = Transform3D((v.basis as Basis) * rot90, v.center)
			if side_i < 0:
				l_pa.append(trp)
			else:
				l_pb.append(trp)
	_mm_instance(base_pair, l_base_p, "GuideBases")
	_mm_instance(base_single, l_base_s, "GuideBasesSingle")
	_mm_instance(br_pair, l_br_p, "GuideBrackets")
	_mm_instance(br_single, l_br_s, "GuideBracketsSingle")
	_mm_instance(axle_pair, l_ax_p, "GuideAxles")
	_mm_instance(axle_single, l_ax_s, "GuideAxlesSingle")
	_mm_instance(pulley_mesh, l_pa, "GuidePulleysA")
	_mm_instance(pulley_mesh, l_pb, "GuidePulleysB")
	_cable_top_y = y_axis + pulley_radius


# Galets de déviation de l'aiguillage Abt (photo d'aiguillage : grandes
# poulies inclinées à moyeu rouge de part et d'autre du câble). Ici un seul
# galet par brin, du côté INTÉRIEUR du coude, là où la tension tire le
# câble ; incliné de 30° sous l'horizontale, jante contre le flanc du câble.
func _build_abt_sheaves() -> void:
	var disc_mat: StandardMaterial3D = StandardMaterial3D.new()
	disc_mat.albedo_color = Color(0.20, 0.20, 0.22)
	disc_mat.roughness = 0.40
	disc_mat.metallic = 0.85
	var hub_mat: StandardMaterial3D = StandardMaterial3D.new()
	hub_mat.albedo_color = Color(0.62, 0.13, 0.10)
	hub_mat.roughness = 0.55
	hub_mat.metallic = 0.4
	var chape_mat: StandardMaterial3D = StandardMaterial3D.new()
	chape_mat.albedo_color = Color(0.36, 0.34, 0.32)
	chape_mat.roughness = 0.7
	chape_mat.metallic = 0.5
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = sheave_radius
	disc.bottom_radius = sheave_radius * 0.92
	disc.height = sheave_thickness
	disc.radial_segments = 28
	disc.rings = 1
	disc.material = disc_mat
	var hub: CylinderMesh = CylinderMesh.new()
	hub.top_radius = 0.045
	hub.bottom_radius = 0.045
	hub.height = sheave_thickness + 0.06
	hub.radial_segments = 12
	hub.rings = 1
	hub.material = hub_mat
	var chape: BoxMesh = BoxMesh.new()
	chape.size = Vector3(0.05, 1.0, 0.12)
	chape.material = chape_mat

	var l_disc: Array = []
	var l_hub: Array = []
	var l_chape: Array = []
	var beta: float = deg_to_rad(sheave_incline_deg)
	var y_floor: float = floor_y_local + slab_thickness - 0.01
	for k in range(_stations.size()):
		var st: Dictionary = _stations[k]
		if not st.sheave:
			continue
		var xf: Transform3D = tunnel.transform_at(st.s)
		for side_i in [-1, 1]:
			var pts: Array = _strand[side_i]
			var a: Vector3 = pts[k].p
			var v: Vector3 = pts[k + 1].p
			var b: Vector3 = pts[k + 2].p
			var pull: Vector3 = (b - v).normalized() - (v - a).normalized()
			var lat: float = pull.dot(xf.basis.x)
			var inside: float = signf(lat) if absf(lat) > 1e-7 else -float(side_i)
			var n: Vector3 = (xf.basis.x * inside * cos(beta) - xf.basis.y * sin(beta)).normalized()
			var u: Vector3 = (b - a).normalized()
			var axis: Vector3 = u.cross(n).normalized()
			var bz: Vector3 = n.cross(axis).normalized()
			var basis: Basis = Basis(n, axis, bz)
			var center: Vector3 = v + n * (sheave_radius + cable_radius)
			l_disc.append(Transform3D(basis, center))
			l_hub.append(Transform3D(basis, center))
			# chape : patte du moyeu jusqu'à la dalle, côté extérieur du galet
			var hub_y: float = (center - xf.origin).dot(xf.basis.y)
			var h: float = maxf(hub_y - y_floor, 0.05)
			var cpos: Vector3 = center + xf.basis.x * (inside * 0.07) - xf.basis.y * (h * 0.5)
			l_chape.append(Transform3D(xf.basis * Basis.from_scale(Vector3(1.0, h, 1.0)), cpos))
	_mm_instance(disc, l_disc, "AbtSheaves")
	_mm_instance(hub, l_hub, "AbtSheaveHubs")
	_mm_instance(chape, l_chape, "AbtSheaveChapes")


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
# entre les rails, TENDUS en ligne droite d'un galet au suivant. Le brin
# gauche part de l'attache culot de rame 1 vers la poulie motrice en haut ; le brin droit repart de la poulie vers l'attache
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

	cable_left_segments.clear()
	cable_right_segments.clear()
	var total_len: float = PNConstants.LENGTH
	var n_seg: int = int(ceil(total_len / cable_segment_length))
	for i in range(n_seg):
		var s_start: float = float(i) * cable_segment_length
		var s_end: float = minf(s_start + cable_segment_length, total_len)
		var mi_left: MeshInstance3D = _build_cable_segment(
			cable_left_material, -1, s_start, s_end, "CableLeft_%d" % i)
		cable_left_segments.append({"s_start": s_start, "s_end": s_end, "mesh": mi_left})
		var mi_right: MeshInstance3D = _build_cable_segment(
			cable_right_material, 1, s_start, s_end, "CableRight_%d" % i)
		cable_right_segments.append({"s_start": s_start, "s_end": s_end, "mesh": mi_right})


# Tronçon [s_start, s_end] d'un brin : tube droit d'un galet au suivant
# (sommets = contacts dans la gorge, cf. _compute_cable_geometry). UV.y =
# 2 × s : le shader y lit l'abscisse pour la coupe à la rame et l'hélice.
func _build_cable_segment(
	mat: Material, side_i: int, s_start: float, s_end: float, name: String,
) -> MeshInstance3D:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)

	var chain: Array = [{"s": s_start, "p": strand_point(side_i, s_start)}]
	for v in _strand[side_i]:
		if v.s > s_start + 1e-4 and v.s < s_end - 1e-4:
			chain.append({"s": v.s, "p": v.p})
	chain.append({"s": s_end, "p": strand_point(side_i, s_end)})

	# repère de chaque anneau : tangente = moyenne des cordes voisines,
	# droite/haut de la voie redressés perpendiculairement (Gram-Schmidt)
	var rights: Array = []
	var ups: Array = []
	for j in range(chain.size()):
		var pa: Vector3 = chain[maxi(j - 1, 0)].p
		var pb: Vector3 = chain[mini(j + 1, chain.size() - 1)].p
		var tg: Vector3 = (pb - pa).normalized()
		var xf: Transform3D = tunnel.transform_at(chain[j].s)
		var r: Vector3 = (xf.basis.x - tg * xf.basis.x.dot(tg)).normalized()
		var u: Vector3 = xf.basis.y - tg * xf.basis.y.dot(tg)
		u = (u - r * u.dot(r)).normalized()
		rights.append(r)
		ups.append(u)

	for i in range(chain.size() - 1):
		var c0: Vector3 = chain[i].p
		var c1: Vector3 = chain[i + 1].p
		var r0: Vector3 = rights[i]
		var r1: Vector3 = rights[i + 1]
		var u0: Vector3 = ups[i]
		var u1: Vector3 = ups[i + 1]
		var v0_uv: float = float(chain[i].s) * 2.0
		var v1_uv: float = float(chain[i + 1].s) * 2.0
		for k in range(cable_segments):
			var a0: float = float(k) / float(cable_segments) * TAU
			var a1: float = float(k + 1) / float(cable_segments) * TAU
			var p00: Vector3 = c0 + r0 * cos(a0) * cable_radius + u0 * sin(a0) * cable_radius
			var p01: Vector3 = c0 + r0 * cos(a1) * cable_radius + u0 * sin(a1) * cable_radius
			var p10: Vector3 = c1 + r1 * cos(a0) * cable_radius + u1 * sin(a0) * cable_radius
			var p11: Vector3 = c1 + r1 * cos(a1) * cable_radius + u1 * sin(a1) * cable_radius
			var u0_uv: float = float(k) / float(cable_segments)
			var u1_uv: float = float(k + 1) / float(cable_segments)
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

var _last_vis_seg_idx: int = -1
var _last_vis_rame2: bool = false


func update_cable_visibility(s_driver: float) -> void:
	# La visibilité ne change que quand la rame franchit une frontière de
	# segment (15 m) — inutile d'itérer ~460 segments à 60 Hz entre-temps.
	# MAIS on force le recalcul si le choix de rame a changé : sinon, après
	# le sélecteur de scénario (rame 2), la config visible restait figée sur
	# rame 1 tant que la cabine ne bougeait pas de 15 m → le brin droit
	# (celui de la rame pilotée) restait masqué et « le câble disparaissait »
	# à quai et en début de montée (retour d'essai PWA 2026-07-12).
	var seg_idx: int = int(s_driver / cable_segment_length)
	if seg_idx == _last_vis_seg_idx and driver_is_rame2 == _last_vis_rame2:
		return
	_last_vis_seg_idx = seg_idx
	_last_vis_rame2 = driver_is_rame2
	# Où commence chaque brin visible (position de LA rame qu'il tire) :
	#   - rame 1 pilotée : brin gauche part de la cabine (s_driver),
	#                      brin droit part de la rame opposée (LENGTH−s).
	#   - rame 2 pilotée : c'est l'inverse (la cabine est sur la voie droite).
	var s_left: float = (PNConstants.LENGTH - s_driver) if driver_is_rame2 else s_driver
	var s_right: float = PNConstants.LENGTH - s_left
	for seg in cable_left_segments:
		# Segment visible si une partie est en amont (au-dessus) de sa rame
		seg.mesh.visible = seg.s_end >= s_left
	for seg in cable_right_segments:
		seg.mesh.visible = seg.s_end >= s_right


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
func update_cable_phase(s_driver: float, _v_driver: float, _delta: float) -> void:
	if cable_left_material == null or cable_right_material == null:
		return
	# Le brin de LA rame pilotée doit apparaître FIXE dans le référentiel de
	# la cabine (phase = s_driver) ; l'autre brin défile (phase = −s_driver).
	# Selon rame 1 / rame 2, ce n'est pas le même brin qui est « le sien ».
	var left_phase: float = (-s_driver) if driver_is_rame2 else s_driver
	var right_phase: float = s_driver if driver_is_rame2 else (-s_driver)
	cable_left_material.set_shader_parameter("cable_phase", left_phase)
	cable_right_material.set_shader_parameter("cable_phase", right_phase)
	# Coupe au fragment près : chaque brin n'existe qu'entre SA rame et la
	# poulie en haut. Complète le masquage par segments (grossier, 15 m) —
	# sans ça, en descente on voyait des bouts de son propre câble
	# apparaître devant la cabine puis disparaître d'un coup.
	var s_left: float = (PNConstants.LENGTH - s_driver) if driver_is_rame2 else s_driver
	cable_left_material.set_shader_parameter("cut_below_s", s_left)
	cable_right_material.set_shader_parameter(
		"cut_below_s", PNConstants.LENGTH - s_left)
