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

# Entraxe des plots MESURÉ sur la vidéo de montée du 26/04/2026 : ils
# défilent à 5,25 Hz à 7,95 m/s (vitesse lue sur l'écran du pupitre :
# 1 910 → 2 387 m en 60 s) → 1,51 m (0,95 m estimé auparavant).
@export var sleeper_spacing: float = 1.51
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

@export var guide_spacing: float = 13.57     # ancienne grille (3474 m / 256 paires, CFD) : gare haute seulement
# Fosse centrale (vidéo de Kevin du 26/04/2026, vue plongeante depuis le nez,
# et retour d'essai du 03/10 : « le plancher entre les traverses au milieu
# de la voie, faudrait le baisser de 70 cm ») : les rails sont sur de hauts
# plots béton, le fond entre et autour des deux rangées de plots est 70 cm
# sous l'ancienne dalle ; les supports de galets enjambent la fosse.
@export var trench_depth: float = 0.70
# Supports numérotés (faits de Kevin, 03/10) : AUCUN support en gare aval,
# le n° 1 est au bout du quai aval, le n° 238 (dernier numéroté) au début du
# quai amont, là où la pente de la gare haute est atteinte (SlopeProfile).
# Quais raccourcis le 06/10 (PNConstants.QUAI_*) : [3, 42,56] et
# [3437,04, 3473] → n° 1 à 29 traverses (43,79 m, 1,23 m après le quai),
# n° 238 à 2 276 traverses (3 436,76 m, 0,28 m avant le quai).
const SUPPORT_S1: float = 43.79
const SUPPORT_S_LAST: float = 3436.76
const SUPPORT_N: int = 238
# Galet de ligne (RollerMesh, photo du reportage remontees-mecaniques.net,
# audit_physique/galets_ligne.sage) : bande de roulement Ø 500 — le câble
# repose au fond de la gorge —, joues Ø 640, 200 mm de joue à joue.
@export var pulley_radius: float = RollerMesh.R_BANDE
@export var pulley_thickness: float = RollerMesh.LARGEUR
@export var pulley_pair_offset: float = 0.12 # décalage latéral de chaque poulie (entraxe 0.24m)
@export var base_plate_width: float = 0.56   # emprise d'une paire : fourches et paliers compris
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
# Réglettes de l'évitement : coupées avec l'éclairage du tunnel (touche J)
var _loop_lamp_mat: StandardMaterial3D = null


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
	_build_abt_plates()
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
# Stations équipées d'un galet de déviation incliné. Pas à +4,5 ni +11 m :
# la langue et le tronçon décalé occupent la place.
const ABT_SHEAVE_STATIONS: Array = [22.0, 31.0, 40.0]
const ABT_ZONE: float = 45.0              # étendue de l'aiguillage depuis la fourche (m)
@export var abt_flangeway: float = 0.060  # boudin 30 mm + jeu
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


# Abscisses des galets. Entre le bout du quai aval (n° 1) et le début du
# quai amont (n° 238) : grille régulière hors aiguillages + stations
# dessinées des aiguillages, le pas étant choisi pour qu'il y ait EXACTEMENT
# 238 supports (14,54 m). Aucun en gare aval. En gare amont, les galets non
# numérotés de l'ancienne grille (le dernier raccorde la salle des
# machines, MachineRoomBuilder.S_LAST_TUNNEL_ROLLER).
func _station_list() -> Array:
	var out: Array = []
	var span: float = SUPPORT_S_LAST - SUPPORT_S1
	var grid: Array = []
	var best_dp: float = INF
	for g in range(SUPPORT_N - 40, SUPPORT_N + 10):
		var sp: float = span / float(g - 1)
		var pts: Array = []
		for i in range(g):
			var s: float = SUPPORT_S1 + float(i) * sp
			if not _in_abt_zone(s):
				pts.append(s)
		if pts.size() + 2 * ABT_STATIONS.size() == SUPPORT_N and absf(sp - guide_spacing) < best_dp:
			best_dp = absf(sp - guide_spacing)
			grid = pts
	for s in grid:
		out.append({"s": s, "sheave": false})
	for o in ABT_STATIONS:
		var sh: bool = ABT_SHEAVE_STATIONS.has(o)
		out.append({"s": PNConstants.PASSING_START + o, "sheave": sh})
		out.append({"s": PNConstants.PASSING_END - o, "sheave": sh})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.s < b.s)
	for i in range(out.size()):
		out[i]["num"] = i + 1
	# gare amont : galets non numérotés
	var n_total: int = int(PNConstants.LENGTH / guide_spacing)
	for i in range(n_total):
		var s: float = (float(i) + 0.5) * guide_spacing
		if s > SUPPORT_S_LAST + 5.0:
			out.append({"s": s, "sheave": false, "num": 0})
	for st in out:
		# Entre deux traverses, pas au droit d'une (retour du 05/10/2026 :
		# « tu auras plus de place en largeur ») : les plots sont en
		# (i + ½) × sleeper_spacing, le support au milieu de l'intervalle.
		st["s"] = snappedf(float(st.s), sleeper_spacing)
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
	_support_s = {}
	_pa_cache = {}
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
			# Le galet est incliné AUTOUR DU CÂBLE : il le reçoit sur sa ligne
			# de tracé (05/10/2026 — avec des galets Ø 500, pivoter autour de
			# leur centre déportait le câble de 15 cm en courbe).
			var p: Vector3 = xf.origin + xf.basis.y * y_nom + xf.basis.x * x_nom
			var center: Vector3 = p - rb.y.normalized() * (pulley_radius + cable_radius)
			var rel: Vector3 = p - xf.origin
			pts.append({"s": s, "p": p, "x": rel.dot(xf.basis.x), "y": rel.dot(xf.basis.y),
				"tilt": tilt, "center": center, "basis": rb})
		pts.append(_strand_free_point(PNConstants.LENGTH, side, y_nom))
		for i in range(1, pts.size() - 1):
			if _stations[i - 1].sheave:
				pts[i]["poulie"] = _poulie_deviation(pts, i, side_i)
		_strand[side_i] = pts
	_compute_abt()


func _strand_free_point(s: float, side: float, y_nom: float) -> Dictionary:
	var xf: Transform3D = tunnel.transform_at(s)
	var x: float = _track_center_x(s, side) + side * pulley_pair_offset
	# brin de la rame 2 : il remonte vers les galets qui le font passer
	# au-dessus du sommet de la roue aval (machine_room_builder)
	if side > 0.0 and s >= PNConstants.LENGTH - 1e-6:
		y_nom = MachineRoomBuilder.EXIT_Y_END
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


# Rails intérieurs de l'aiguillage Abt, en TRONÇONS (retour d'essai du
# 30/09 : « il manque des bouts de rail », photos d'Hakone, de la Polybahn
# et schéma Wikipédia « Abtsche Weiche »). Pour la roue PLATE d'une rame
# (voie rail_i, ligne x_f = inner_rail_x) :
#   A. LANGUE : naît en pointe recourbée dans la voie unique, 4 m avant la
#      fourche, parallèle au rail extérieur opposé à l'ornière près (le
#      boudin intérieur de l'autre rame passe entre les deux) ; elle
#      rejoint ensuite la ligne de la roue x_f et finit en LAME (tête +
#      âme, sans patin) là où le câble de l'autre rame la traverse ;
#   B. le tronçon suivant croise l'autre rail intérieur sur le cœur en X,
#      court tout l'évitement et finit de même à l'autre bout.
# À la lacune (retour d'essai du 30/09, gros plans d'Hakone et de la photo
# de Kevin) : les deux bouts sont PLIÉS pour courir PARALLÈLEMENT AU CÂBLE,
# côte à côte, à ±8 cm de lui, sur 1 m de chevauchement ; chacun y arrive
# par un coude franc depuis la ligne de la roue. Le câble file droit dans le
# couloir, sur une tôle de glissement ; les bouts reposent sur des plaques.
# La roue plate (24 cm) porte sur l'un puis sur l'autre.
const ABT_TONGUE_BACK: float = 4.0     # la langue commence 4 m avant la fourche
const ABT_TONGUE_OFFSET: float = 0.135 # entraxe rail extérieur / langue : tête 75 + ornière 60 mm
const ABT_CHANNEL: float = 0.08        # entraxe bout de rail / câble dans la lacune
const ABT_OVERLAP_HALF: float = 0.5    # chaque bout dépasse le point de croisement de 0,5 m
const FLAT_TREAD_HALF: float = 0.12    # roue plate de 24 cm (train_body_builder)


func _cable_x(rail_i: int, s: float) -> float:
	# brin de la rame OPPOSÉE, celui qui traverse ce rail intérieur
	return strand_local_at(-rail_i, s).x


# Écart orienté roue / câble : < 0 côté fourche, > 0 côté évitement.
func _wheel_cable_gap(rail_i: int, s: float) -> float:
	return float(rail_i) * (inner_rail_x(rail_i, s) - _cable_x(rail_i, s))


func _compute_abt() -> void:
	var hg: float = gauge_m * 0.5
	var s0: float = PNConstants.PASSING_START
	var s1: float = PNConstants.PASSING_END
	var ds_x: float = _loop_ds_for_offset(hg)
	var ds_sw: float = _loop_ds_for_offset(abt_switch_d)
	_abt = {
		"frog": [s0 + ds_x, s1 - ds_x],
		"switch_lo": s0 + ds_sw, "switch_hi": s1 - ds_sw,
		"gaps": [], "pieces": [],
	}
	var clr: float = 0.008
	var foot_need: float = cable_radius + rail_foot_width * 0.5 + clr
	for rail_i in [-1, 1]:
		var gap: Dictionary = {"rail": rail_i, "cable": -rail_i}
		for zone in [["lo", s0 + 2.0, s0 + ABT_ZONE, 1.0], ["hi", s1 - 2.0, s1 - ABT_ZONE, -1.0]]:
			var z: String = zone[0]
			var dirn: float = zone[3]
			# croisement roue / câble, puis les deux coudes (écart = ±canal)
			var sc: float = _scan_gap(rail_i, zone[1], zone[2], dirn, 0.0)
			var sb_a: float = _scan_gap(rail_i, sc, sc - 8.0 * dirn, -dirn, -ABT_CHANNEL)
			var sb_b: float = _scan_gap(rail_i, sc, sc + 8.0 * dirn, dirn, ABT_CHANNEL)
			gap["sc_" + z] = sc
			gap["bend_a_" + z] = sb_a
			gap["bend_b_" + z] = sb_b
			gap["a_end_" + z] = sc + ABT_OVERLAP_HALF * dirn
			gap["b_start_" + z] = sc - ABT_OVERLAP_HALF * dirn
			gap["dirn_" + z] = dirn
		_abt.gaps.append(gap)
	# lames (sans patin) là où le câble passe à moins d'un demi-patin
	for gap in _abt.gaps:
		var rail_i: int = gap.rail
		for z in ["lo", "hi"]:
			var dirn: float = gap["dirn_" + z]
			var sc: float = gap["sc_" + z]
			var s: float = sc
			while absf(_wheel_cable_gap(rail_i, s)) < foot_need and absf(s - sc) < 8.0:
				s -= 0.01 * dirn
			gap["a_blade_" + z] = s
			s = sc
			while absf(_wheel_cable_gap(rail_i, s)) < foot_need and absf(s - sc) < 8.0:
				s += 0.01 * dirn
			gap["b_blade_" + z] = s
	for gap in _abt.gaps:
		var rail_i: int = gap.rail
		var nm: String = "RailInnerLeft" if rail_i < 0 else "RailInnerRight"
		# A bas : de la pointe de langue au bout plié le long du câble
		_abt.pieces.append({"kind": "A", "zone": "lo", "rail": rail_i, "name": nm + "LangueBas",
			"s_a": s0 - ABT_TONGUE_BACK, "s_b": gap.a_end_lo,
			"blade_a": s0 - ABT_TONGUE_BACK - 1.0, "blade_b": gap.a_blade_lo,
			"tip_a": true, "tip_b": false})
		# B : d'une lacune à l'autre, à travers les deux cœurs et l'évitement
		_abt.pieces.append({"kind": "B", "rail": rail_i, "name": nm,
			"s_a": gap.b_start_lo, "s_b": gap.b_start_hi,
			"blade_a": gap.b_blade_lo, "blade_b": gap.b_blade_hi,
			"tip_a": false, "tip_b": false})
		# A haut : du bout plié à la pointe de langue
		_abt.pieces.append({"kind": "A", "zone": "hi", "rail": rail_i, "name": nm + "LangueHaut",
			"s_a": gap.a_end_hi, "s_b": s1 + ABT_TONGUE_BACK,
			"blade_a": gap.a_blade_hi, "blade_b": s1 + ABT_TONGUE_BACK + 1.0,
			"tip_a": false, "tip_b": true})


# Premier s (en partant de s_from dans le sens dirn) où l'écart roue/câble
# franchit la valeur target ; affiné par dichotomie.
func _scan_gap(rail_i: int, s_from: float, s_to: float, dirn: float, target: float) -> float:
	var s: float = s_from
	var prev: float = _wheel_cable_gap(rail_i, s) - target
	while (s_to - s) * dirn > 0.0:
		var sn: float = s + 0.02 * dirn
		var cur: float = _wheel_cable_gap(rail_i, sn) - target
		if signf(cur) != signf(prev) or cur == 0.0:
			var a: float = s
			var b: float = sn
			for _it in range(30):
				var m: float = 0.5 * (a + b)
				if signf(_wheel_cable_gap(rail_i, m) - target) == signf(prev):
					a = m
				else:
					b = m
			return 0.5 * (a + b)
		prev = cur
		s = sn
	return s


func _gap_zone(piece: Dictionary, s: float) -> String:
	if piece.kind == "A":
		return piece.get("zone", "lo")
	return "lo" if s < 0.5 * (PNConstants.PASSING_START + PNConstants.PASSING_END) else "hi"


func _gap_of(rail_i: int) -> Dictionary:
	for g in _abt.get("gaps", []):
		if g.rail == rail_i:
			return g
	return {}


## Axe latéral d'un tronçon de rail intérieur à l'abscisse s.
func _piece_x(piece: Dictionary, s: float) -> float:
	var ri: float = float(piece.rail)
	var xf: float = inner_rail_x(piece.rail, s)
	var g: Dictionary = _gap_of(piece.rail)
	var z: String = _gap_zone(piece, s)
	if piece.kind == "A":
		# bout plié parallèle au câble, côté fourche du câble
		if not g.is_empty():
			var t: float = (s - g["bend_a_" + z]) * g["dirn_" + z]
			if t >= 0.0:
				return _cable_x(piece.rail, s) - ri * ABT_CHANNEL
		var d: float = absf(tunnel.passing_loop_offset(s, 1.0))
		# langue le long du rail extérieur opposé, puis ligne de la roue ;
		# « le plus éloigné du rail extérieur » des deux, raccord adouci
		var tongue: float = ri * (ABT_TONGUE_OFFSET - d - gauge_m * 0.5)
		var a: float = ri * tongue
		var b: float = ri * xf
		var k: float = 0.012
		var x: float = ri * 0.5 * (a + b + sqrt((a - b) * (a - b) + k * k))
		# pointe de langue recourbée vers l'axe de la voie
		var s_tip: float = PNConstants.PASSING_START - ABT_TONGUE_BACK
		if z == "hi":
			s_tip = PNConstants.PASSING_END + ABT_TONGUE_BACK
		var tt: float = clampf(1.0 - absf(s - s_tip) / 0.9, 0.0, 1.0)
		return x + ri * 0.04 * tt * tt
	# B : bout plié parallèle au câble côté évitement, puis ligne de la roue
	if not g.is_empty():
		var t2: float = (s - g["bend_b_" + z]) * g["dirn_" + z]
		if t2 <= 0.0:
			return _cable_x(piece.rail, s) + ri * ABT_CHANNEL
	return xf


## Tronçons de rail intérieur présents à l'abscisse s : [[x, demi-patin]].
func inner_rails_at(s: float) -> Array:
	var out: Array = []
	for p in _abt.get("pieces", []):
		if s >= p.s_a and s <= p.s_b:
			var half: float = rail_foot_width * 0.5
			if s < p.blade_a or s > p.blade_b:
				half = rail_web_width * 0.5    # lame : tête et âme seulement
			out.append([_piece_x(p, s), half, p])
	return out


func abt_info() -> Dictionary:
	return _abt


func strand_vertices(side_i: int) -> Array:
	return _strand[side_i]


func station_list() -> Array:
	return _stations


func _build_rail_piece(
	rail_mat: StandardMaterial3D, rail_top_mat: StandardMaterial3D, piece: Dictionary,
) -> void:
	var a: float = piece.s_a
	var b: float = piece.s_b
	var cuts: Array = [piece.blade_a, piece.blade_b, a + 0.9, b - 0.9, a + 0.12, b - 0.12]
	var g: Dictionary = _gap_of(piece.rail)
	for z in ["lo", "hi"]:
		if g.has("bend_a_" + z):
			cuts.append(g["bend_a_" + z])    # coudes : sommets exacts
			cuts.append(g["bend_b_" + z])
	for sx in _abt.frog:
		cuts.append(sx - abt_frog_half)
		cuts.append(sx + abt_frog_half)
	var s_list: Array = _adaptive_s_list(a, b, float(piece.rail))
	for c in cuts:
		s_list.append(c)
	# échantillonnage fin là où le tronçon se déforme (pointes, lacunes)
	var k: float = a
	while k < b:
		if k < a + 2.0 or k > b - 2.0 or absf(k - piece.blade_a) < 8.0 or absf(k - piece.blade_b) < 8.0:
			s_list.append(k)
		k += 0.1
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
	var top_y: float = rail_base_y + rail_height - (0.0004 if piece.rail > 0 else 0.0)

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
		var key: String = _piece_key(piece, 0.5 * (s0_ + s1_))
		var xf0: Transform3D = tunnel.transform_at(s0_)
		var xf1: Transform3D = tunnel.transform_at(s1_)
		var p0: Vector3 = xf0.origin
		var p1: Vector3 = xf1.origin
		var r0: Vector3 = xf0.basis.x
		var r1: Vector3 = xf1.basis.x
		var u0: Vector3 = xf0.basis.y
		var u1: Vector3 = xf1.basis.y
		var cx0: float = _piece_x(piece, s0_)
		var cx1: float = _piece_x(piece, s1_)
		# bouts abaissés : pointe de langue sur 0,9 m, bout de lame sur 0,3 m
		var top0: float = top_y - rail_height * (1.0 - _piece_height(piece, s0_))
		var top1: float = top_y - rail_height * (1.0 - _piece_height(piece, s1_))
		var parts: Array = []
		match key:
			"frog":
				parts.append([rail_base_y, top0 - 0.012, rail_base_y, top1 - 0.012, hw])
			"blade":
				# lame : âme et tête seulement, le câble passe à côté
				parts.append([foot_y1, minf(web_y1, top0 - 0.012), foot_y1, minf(web_y1, top1 - 0.012), rail_web_width * 0.5])
				parts.append([minf(web_y1, top0 - 0.012), top0 - 0.012, minf(web_y1, top1 - 0.012), top1 - 0.012, hw])
			"tip":
				parts.append([rail_base_y, top0 - 0.012, rail_base_y, top1 - 0.012, hw])
			_:
				parts.append([rail_base_y, foot_y1, rail_base_y, foot_y1, rail_foot_width * 0.5])
				parts.append([foot_y1, web_y1, foot_y1, web_y1, rail_web_width * 0.5])
				parts.append([web_y1, top0 - 0.012, web_y1, top1 - 0.012, hw])
		for pt in parts:
			_emit_box_step(st_rail, p0, r0, u0, p1, r1, u1, cx0, cx1,
				pt[0], pt[1], pt[2], pt[3], pt[4], s0_, s1_)
		_emit_box_step(st_top, p0, r0, u0, p1, r1, u1, cx0, cx1,
			top0 - 0.012, top0, top1 - 0.012, top1, hw, s0_, s1_)
		if key != prev_key:
			for pt in parts:
				_emit_cap(st_rail, p0, r0, u0, cx0, pt[0], pt[1], pt[4])
		var next_key: String = _piece_key(piece, s1_ + 0.001) if i + 2 < clean.size() else ""
		if next_key != key:
			for pt in parts:
				_emit_cap(st_rail, p1, r1, u1, cx1, pt[2], pt[3], pt[4])
			_emit_cap(st_top, p1, r1, u1, cx1, top1 - 0.012, top1, hw)
		if i == 0:
			_emit_cap(st_top, p0, r0, u0, cx0, top0 - 0.012, top0, hw)
		prev_key = key
		if s1_ - chunk_start >= chunk_length or i == clean.size() - 2:
			_commit_rail_chunk(st_rail, st_top, "%s_%d" % [piece.name, chunk_i])
			st_rail = null
			st_top = null
			chunk_i += 1


func _piece_key(piece: Dictionary, m: float) -> String:
	for sx in _abt.frog:
		if absf(m - sx) < abt_frog_half:
			return "frog"
	if (piece.tip_a and m < piece.s_a + 0.9) or (piece.tip_b and m > piece.s_b - 0.9):
		return "tip"
	if m < piece.blade_a or m > piece.blade_b:
		return "blade"
	return "full"


# Hauteur relative d'un tronçon : pointe de langue en rampe (35 % → 100 %
# sur 0,9 m) ; bout coupé franc à la lacune, simple chanfrein (88 % → 100 %
# sur 12 cm), comme sur les photos.
func _piece_height(piece: Dictionary, s: float) -> float:
	var h: float = 1.0
	if piece.tip_a:
		h = minf(h, lerpf(0.35, 1.0, smoothstep(0.0, 1.0, clampf((s - piece.s_a) / 0.9, 0.0, 1.0))))
	else:
		h = minf(h, lerpf(0.88, 1.0, clampf((s - piece.s_a) / 0.12, 0.0, 1.0)))
	if piece.tip_b:
		h = minf(h, lerpf(0.35, 1.0, smoothstep(0.0, 1.0, clampf((piece.s_b - s) / 0.9, 0.0, 1.0))))
	else:
		h = minf(h, lerpf(0.88, 1.0, clampf((piece.s_b - s) / 0.12, 0.0, 1.0)))
	return h


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
	# en haut, la dalle s'arrête au bord de la fosse où émerge la roue aval
	# de la salle des machines (elle la traversait : « un mur en béton dans
	# la roue », retour du 30/09)
	_build_slab_section(slab_mat, PNConstants.PASSING_END,
		minf(pit_high_start, PNConstants.LENGTH + MachineRoomBuilder.PIT_S0), 0.0, "SlabHigh", false)


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

		# Dessus, creusé de la fosse centrale (une par voie dans
		# l'évitement, confondues tant que les voies se chevauchent)
		var e0: Array = _trench_edges(prev_s, is_chamber, side)
		var e1: Array = _trench_edges(s_cur, is_chamber, side)
		var y_f0: float = slab_top_y - _trench_depth_at(prev_s)
		var y_f1: float = slab_top_y - _trench_depth_at(s_cur)
		var m0: Array = _trench_ledge(e0, slab_top_y, y_f0)
		var m1: Array = _trench_ledge(e1, slab_top_y, y_f1)
		# bandes hautes extérieures
		_emit_quad_strip(st,
			_pt(p0, r0, u0, prev_off - prev_half_w, slab_top_y), _pt(p0, r0, u0, e0[0], slab_top_y),
			_pt(p1, r1, u1, cur_off - cur_half_w, slab_top_y), _pt(p1, r1, u1, e1[0], slab_top_y),
			Vector2(0.0, v0), Vector2(0.3, v0), Vector2(0.0, v1), Vector2(0.3, v1))
		_emit_quad_strip(st,
			_pt(p0, r0, u0, e0[3], slab_top_y), _pt(p0, r0, u0, prev_off + prev_half_w, slab_top_y),
			_pt(p1, r1, u1, e1[3], slab_top_y), _pt(p1, r1, u1, cur_off + cur_half_w, slab_top_y),
			Vector2(0.7, v0), Vector2(1.0, v0), Vector2(0.7, v1), Vector2(1.0, v1))
		# fonds de fosse
		_emit_quad_strip(st,
			_pt(p0, r0, u0, e0[0], y_f0), _pt(p0, r0, u0, m0[0], y_f0),
			_pt(p1, r1, u1, e1[0], y_f1), _pt(p1, r1, u1, m1[0], y_f1),
			Vector2(0.3, v0), Vector2(0.5, v0), Vector2(0.3, v1), Vector2(0.5, v1))
		_emit_quad_strip(st,
			_pt(p0, r0, u0, m0[1], y_f0), _pt(p0, r0, u0, e0[3], y_f0),
			_pt(p1, r1, u1, m1[1], y_f1), _pt(p1, r1, u1, e1[3], y_f1),
			Vector2(0.5, v0), Vector2(0.7, v0), Vector2(0.5, v1), Vector2(0.7, v1))
		# parois extérieures de la fosse (vers l'intérieur)
		_emit_quad_strip(st,
			_pt(p0, r0, u0, e0[0], slab_top_y), _pt(p0, r0, u0, e0[0], y_f0),
			_pt(p1, r1, u1, e1[0], slab_top_y), _pt(p1, r1, u1, e1[0], y_f1),
			Vector2(0.3, v0), Vector2(0.4, v0), Vector2(0.3, v1), Vector2(0.4, v1))
		_emit_quad_strip(st,
			_pt(p0, r0, u0, e0[3], y_f0), _pt(p0, r0, u0, e0[3], slab_top_y),
			_pt(p1, r1, u1, e1[3], y_f1), _pt(p1, r1, u1, e1[3], slab_top_y),
			Vector2(0.6, v0), Vector2(0.7, v0), Vector2(0.6, v1), Vector2(0.7, v1))
		# merlon entre les deux fosses de l'évitement
		if is_chamber and (m0[1] - m0[0] > 0.001 or m1[1] - m1[0] > 0.001):
			_emit_quad_strip(st,
				_pt(p0, r0, u0, m0[0], m0[2]), _pt(p0, r0, u0, m0[1], m0[2]),
				_pt(p1, r1, u1, m1[0], m1[2]), _pt(p1, r1, u1, m1[1], m1[2]),
				Vector2(0.45, v0), Vector2(0.55, v0), Vector2(0.45, v1), Vector2(0.55, v1))
			_emit_quad_strip(st,
				_pt(p0, r0, u0, m0[0], y_f0), _pt(p0, r0, u0, m0[0], m0[2]),
				_pt(p1, r1, u1, m1[0], y_f1), _pt(p1, r1, u1, m1[0], m1[2]),
				Vector2(0.45, v0), Vector2(0.5, v0), Vector2(0.45, v1), Vector2(0.5, v1))
			_emit_quad_strip(st,
				_pt(p0, r0, u0, m0[1], m0[2]), _pt(p0, r0, u0, m0[1], y_f0),
				_pt(p1, r1, u1, m1[1], m1[2]), _pt(p1, r1, u1, m1[1], y_f1),
				Vector2(0.5, v0), Vector2(0.55, v0), Vector2(0.5, v1), Vector2(0.55, v1))
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


# Bords de la fosse centrale à l'abscisse s (x local) : [g0, g1, d0, d1],
# fosse de la voie gauche puis de la voie droite — la même hors
# évitement. Elle va de la face extérieure d'une rangée de plots à celle
# de l'autre (vidéo : fond profond entre les plots aussi).
func _trench_edges(s: float, is_chamber: bool, side: float) -> Array:
	var tw: float = gauge_m * 0.5 + block_width * 0.5
	if is_chamber:
		var cl: float = _track_center_x(s, -1.0)
		var cr: float = _track_center_x(s, 1.0)
		return [cl - tw, cl + tw, cr - tw, cr + tw]
	var c: float = _track_center_x(s, side)
	return [c - tw, c + tw, c - tw, c + tw]


# Merlon entre les deux fosses : [x0, x1, y_dessus]. Nul (et au fond) tant
# que les fosses se chevauchent ; il monte à la dalle sur 40 cm de large.
func _trench_ledge(e: Array, y_top: float, y_floor: float) -> Array:
	var lo: float = e[1]
	var hi: float = e[2]
	if hi <= lo:
		var m: float = 0.5 * (lo + hi)
		return [m, m, y_floor]
	return [lo, hi, lerpf(y_floor, y_top, clampf((hi - lo) / 0.4, 0.0, 1.0))]


# Profondeur de la fosse à l'abscisse s : pleine sur la ligne, elle remonte
# au niveau de la dalle sur les derniers mètres avant la fosse de la roue
# aval (gare haute), sinon son fond traverserait la roue.
func _trench_depth_at(s: float) -> float:
	var s_fin: float = PNConstants.LENGTH + MachineRoomBuilder.PIT_S0
	return trench_depth * clampf((s_fin - 1.5 - s) / 2.5, 0.0, 1.0)


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
	# Rails intérieurs de l'évitement en tronçons : langues, lames,
	# lacunes où passe le câble opposé, cœur en X (cf. _compute_abt).
	for piece in _abt.pieces:
		_build_rail_piece(rail_mat, rail_top_mat, piece)


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

	# Plots : du fond de la fosse jusque sous le rail (vidéo du 26/04)
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(block_width, sleeper_height + trench_depth, sleeper_width)
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
		if s < PNConstants.PASSING_START - ABT_TONGUE_BACK or s > PNConstants.PASSING_END + ABT_TONGUE_BACK:
			positions.append({"s": s, "off": -hg, "w": block_width})
			positions.append({"s": s, "off": hg, "w": block_width})
			continue
		# Évitement : blochets sous les rails extérieurs. Tronçons intérieurs
		# (langues, lames, rails de l'évitement) : sur le blochet du rail
		# extérieur quand ils le longent, socles étroits dans l'aiguillage
		# (un seul là où deux tronçons se touchent), blochets pleins une
		# fois les voies bien écartées.
		var d: float = absf(tunnel.passing_loop_offset(s, 1.0))
		positions.append({"s": s, "off": -d - hg, "w": block_width})
		positions.append({"s": s, "off": d + hg, "w": block_width})
		var xs: Array = []
		for r in inner_rails_at(s):
			var xr: float = r[0]
			if absf(xr - (-d - hg)) < 0.30 or absf(xr - (d + hg)) < 0.30:
				continue
			var merged: bool = false
			for j in range(xs.size()):
				if absf(xs[j] - xr) < 0.22:
					xs[j] = 0.5 * (xs[j] + xr)
					merged = true
			if not merged:
				xs.append(xr)
		for xr in xs:
			if d >= abt_switch_d:
				positions.append({"s": s, "off": xr, "w": block_width})
			else:
				positions.append({"s": s, "off": xr, "w": 0.24, "low": true})
	var xforms: Array = []
	var y_center: float = floor_y_local + slab_thickness - trench_depth \
		+ (sleeper_height + trench_depth) * 0.5 - 0.01
	for entry in positions:
		var xform: Transform3D = tunnel.transform_at(entry.s)
		var tr: Transform3D = xform
		# socle étroit : 2 mm plus bas que le blochet voisin (pas de
		# scintillement des dessus coplanaires qui se chevauchent)
		var low: float = 0.002 if entry.get("low", false) else 0.0
		tr.basis = xform.basis * Basis.from_scale(Vector3(entry.w / block_width, 1.0, 1.0))
		tr.origin += xform.basis.y * (y_center - low) + xform.basis.x * entry.off
		xforms.append(tr)
	_mm_instance(box, xforms, "Sleepers", 500.0)


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


# Instances répétées le long de la ligne (blochets, joints, marches,
# galets…) : découpées en TRONÇONS de ~100 m, un MultiMeshInstance3D par
# tronçon, posé à l'origine du tronçon. Retour d'essai du 30/09 (« le
# défilement du tunnel saccade », vidéo d'écran iPad : une image sur neuf
# en retard) : chaque groupe était UN seul bloc couvrant 3,5 km, que Godot
# ne peut pas écarter du champ — la carte dessinait à chaque image 1,4 M de
# triangles cachés (936 000 pour les seuls joints annulaires). `range_end`
# (m) efface en plus les tronçons lointains des petits détails.
const MM_CHUNK_M: float = 100.0


func _mm_instance(mesh: Mesh, xforms: Array, name: String, range_end: float = 0.0) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = name
	add_child(holder)
	var chunks: Array = []
	var cur: Array = []
	var o0: Vector3 = Vector3.ZERO
	for xf in xforms:
		if cur.is_empty():
			o0 = (xf as Transform3D).origin
		elif ((xf as Transform3D).origin - o0).length() > MM_CHUNK_M:
			chunks.append(cur)
			cur = []
			o0 = (xf as Transform3D).origin
		cur.append(xf)
	if not cur.is_empty():
		chunks.append(cur)
	for ci in range(chunks.size()):
		var part: Array = chunks[ci]
		var base: Vector3 = (part[0] as Transform3D).origin
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = part.size()
		for i in range(part.size()):
			var local: Transform3D = part[i]
			local.origin -= base
			mm.set_instance_transform(i, local)
		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [name, ci]
		mmi.multimesh = mm
		mmi.position = base
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if range_end > 0.0:
			mmi.visibility_range_end = range_end
			mmi.visibility_range_end_margin = 20.0
		# bancs sans GPU : le serveur de rendu factice ne garde pas les
		# transformées des instances ; copie ABSOLUE (repère de la voie)
		if keep_instance_xforms:
			mmi.set_meta("xforms", part)
		holder.add_child(mmi)


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
	_mm_instance(tread, treads, "WalkwayTreads", 300.0)
	_mm_instance(stringer, stringers, "WalkwayStringers", 400.0)
	# Pas de rambarde (retour d'essai 2026-09-26) : potelets et câble
	# main-courante calculés mais non posés, gardés pour un éventuel retour.
	if walkway_handrail:
		_mm_instance(post, posts, "WalkwayPosts", 300.0)
		_mm_instance(cable, cables, "WalkwayHandCable", 300.0)
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
	_mm_instance(boxm, boxes, "WallBoxes", 400.0)


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


## Dans l'évitement (deux tubes) : les joints et la canalisation y suivent
## chacun leur tube (_build_loop_lining) au lieu de l'axe unique.
func _in_loop_zone(s: float) -> bool:
	return s > PNConstants.PASSING_START and s < PNConstants.PASSING_END


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
	_loop_lamp_mat = lamp_mat

	# --- fines lignes circulaires (section circulaire, hors évitement) :
	# arc qui s'arrête à la dalle (un tore complet traversait la fosse
	# centrale de la voie sous le niveau de la dalle)
	var ring: ArrayMesh = _ring_arc_mesh(joint_mat)
	var rings: Array = []
	var s: float = PNConstants.SQUARE_SECTION_LOW_END + 0.7
	while s < PNConstants.SQUARE_SECTION_HIGH_START:
		if not _in_loop_zone(s):
			var xf: Transform3D = tunnel.transform_at(s)
			rings.append(Transform3D(xf.basis, xf.origin))
		s += ring_joint_spacing
	_mm_instance(ring, rings, "SegmentRings", 250.0)

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
		else:
			# évitement : la canalisation suit la voûte droite du tube DROIT
			# (continue avec celle du tube unique, où d = 0) — chaque
			# tronçon orienté d'un bout à l'autre, le tube s'écartant de
			# l'axe jusqu'à 3°
			var p0: Vector3 = _loop_crown_point(s - 2.0)
			var p1: Vector3 = _loop_crown_point(s + 2.0)
			var up2: Vector3 = tunnel.transform_at(s).basis.y
			pipes.append(Transform3D(Basis.looking_at(p1 - p0, up2), (p0 + p1) * 0.5))
		s += 4.0
	_mm_instance(pipe, pipes, "CrownPipe", 400.0)
	_build_loop_rings(joint_mat)

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
	_mm_instance(hj, hjs, "GalleryJoints", 300.0)

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


## Joint annulaire du tube unique : bourrelet de 1,5 cm (comme l'ancien
## tore) sur l'arc AU-DESSUS de la dalle, repère local du tunnel (X droite,
## Y haut, Z le long de la voie).
const RING_Y_MIN: float = -1.62   # 2 cm sous le dessus de la dalle


func _ring_arc_mesh(joint_mat: StandardMaterial3D) -> ArrayMesh:
	var R: float = tunnel.tunnel_radius
	var w: float = 0.010
	var h: float = 0.015
	var a0: float = asin(clampf(RING_Y_MIN / R, -1.0, 1.0))
	var a1: float = PI - a0
	var n: int = 24
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(n):
		var ta: float = a0 + (a1 - a0) * float(j) / float(n)
		var tb: float = a0 + (a1 - a0) * float(j + 1) / float(n)
		var ra: Vector3 = Vector3(cos(ta), sin(ta), 0.0)
		var rb: Vector3 = Vector3(cos(tb), sin(tb), 0.0)
		var z: Vector3 = Vector3(0.0, 0.0, 1.0)
		for tri in [[ra * R - z * w, rb * R - z * w, rb * (R - h)], [ra * R - z * w, rb * (R - h), ra * (R - h)],
				[ra * (R - h), rb * (R - h), rb * R + z * w], [ra * (R - h), rb * R + z * w, ra * R + z * w]]:
			for v in tri:
				st.set_normal(-Vector3(v.x, v.y, 0.0).normalized())
				st.add_vertex(v)
	var mat: StandardMaterial3D = joint_mat.duplicate()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	return st.commit()


## Point de la canalisation de voûte dans le tube DROIT de l'évitement.
func _loop_crown_point(s: float) -> Vector3:
	var xf: Transform3D = tunnel.transform_at(s)
	var d: float = absf(tunnel.passing_loop_offset(s, 1.0))
	var rr: float = tunnel.tunnel_radius - 0.06
	return xf.origin + xf.basis.x * (d + rr * sin(deg_to_rad(42.0))) \
		+ xf.basis.y * (rr * cos(deg_to_rad(42.0)))


## Joints annulaires DANS l'évitement (retour d'essai du 03/10 : « la section
## de l'évitement, l'habillage du tunnel est différent » — ni joints ni
## canalisation sur 320 m). Les tores du tube unique n'y vont pas : deux
## tubes de rayon R centrés à ±d, qui se rejoignent aux extrémités (profil
## « binoculaire » tant que d < R). Chaque joint est l'arc de SON cercle qui
## borde le vide — la partie qui serait dans l'autre tube n'existe pas :
## côté +1, cos θ ≥ −d/R ; côté −1, cos θ ≤ d/R. Même bourrelet que le tore
## (1,5 cm de saillie), même pas de 1,4 m, en phase avec la ligne.
func _build_loop_rings(joint_mat: StandardMaterial3D) -> void:
	var R: float = tunnel.tunnel_radius
	var w: float = 0.010          # demi-largeur du joint le long de la voie
	var h: float = 0.015          # saillie vers l'intérieur
	var mat: StandardMaterial3D = joint_mat.duplicate()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var s0: float = PNConstants.SQUARE_SECTION_LOW_END + 0.7
	var s: float = s0 + ceil((PNConstants.PASSING_START - s0) / ring_joint_spacing) * ring_joint_spacing
	var st: SurfaceTool = null
	var s_chunk: float = s
	var n_chunk: int = 0
	while s < PNConstants.PASSING_END:
		if st == null:
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			s_chunk = s
		var xf: Transform3D = tunnel.transform_at(s)
		var t: Vector3 = -xf.basis.z
		var d: float = absf(tunnel.passing_loop_offset(s, 1.0))
		var q: float = clampf(d / R, 0.0, 1.0)
		for side in [-1.0, 1.0]:
			var a0: float
			var a1: float
			var bas: float = asin(clampf(RING_Y_MIN / R, -1.0, 1.0))   # rien sous la dalle
			if side > 0.0:
				var ac: float = acos(-q)          # |θ| ≤ acos(−d/R)
				a0 = maxf(-ac, bas)
				a1 = ac
			else:
				a0 = acos(q)                      # θ ∈ [acos(d/R), 2π − acos(d/R)]
				a1 = minf(TAU - a0, PI - bas)
			var n: int = maxi(4, int(ceil((a1 - a0) / TAU * 32.0)))
			for j in range(n):
				var ta: float = a0 + (a1 - a0) * float(j) / float(n)
				var tb: float = a0 + (a1 - a0) * float(j + 1) / float(n)
				var ra: Vector3 = xf.basis.x * cos(ta) + xf.basis.y * sin(ta)
				var rb: Vector3 = xf.basis.x * cos(tb) + xf.basis.y * sin(tb)
				var c: Vector3 = xf.origin + xf.basis.x * (side * d)
				var wa_lo: Vector3 = c + ra * R - t * w
				var wb_lo: Vector3 = c + rb * R - t * w
				var wa_hi: Vector3 = c + ra * R + t * w
				var wb_hi: Vector3 = c + rb * R + t * w
				var aa: Vector3 = c + ra * (R - h)
				var ab: Vector3 = c + rb * (R - h)
				for tri in [[wa_lo, wb_lo, ab], [wa_lo, ab, aa], [aa, ab, wb_hi], [aa, wb_hi, wa_hi]]:
					for v in tri:
						# normale = vers l'axe du tube (comme la paroi)
						var nr: Vector3 = -(v - c - t * t.dot(v - c)).normalized()
						st.set_normal(nr)
						st.add_vertex(v)
		s += ring_joint_spacing
		if s - s_chunk > 40.0 or s >= PNConstants.PASSING_END:
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.name = "LoopRings_%d" % n_chunk
			mi.mesh = st.commit()
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 250.0
			add_child(mi)
			n_chunk += 1
			st = null


## Coupe ou rallume les réglettes de l'évitement avec l'éclairage du tunnel
## (retour du 03/10 : « une deuxième rangée de néons qui font une lumière
## fantomatique dans le noir »).
func set_loop_lamps(on: bool) -> void:
	if _loop_lamp_mat == null:
		return
	_loop_lamp_mat.emission_enabled = on
	_loop_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if on \
		else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_loop_lamp_mat.albedo_color = Color(0.9, 0.95, 1.0) if on else Color(0.45, 0.47, 0.50)


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
	_build_cable_beam_section(mat, s_fork_hi, PNConstants.LENGTH + MachineRoomBuilder.PIT_S0,
		0.0, "CableBeamHigh")


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
	var y_lo: float = floor_y_local + slab_thickness - 0.01   # + fond de fosse (par abscisse)

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
		# au fond de la fosse
		var lo0: float = y_lo - _trench_depth_at(prev_s)
		var lo1: float = y_lo - _trench_depth_at(s_cur)
		var hi0: float = lo0 + cable_beam_height
		var hi1: float = lo1 + cable_beam_height

		# Dessus
		_emit_quad_strip(
			st,
			_pt(p0, r0, u0, prev_off - half_w, hi0),
			_pt(p0, r0, u0, prev_off + half_w, hi0),
			_pt(p1, r1, u1, cur_off - half_w, hi1),
			_pt(p1, r1, u1, cur_off + half_w, hi1),
			Vector2(0.0, v0), Vector2(1.0, v0),
			Vector2(0.0, v1), Vector2(1.0, v1),
		)
		# Flanc gauche
		_emit_quad_strip(
			st,
			_pt(p0, r0, u0, prev_off - half_w, lo0),
			_pt(p0, r0, u0, prev_off - half_w, hi0),
			_pt(p1, r1, u1, cur_off - half_w, lo1),
			_pt(p1, r1, u1, cur_off - half_w, hi1),
			Vector2(0.0, v0), Vector2(0.2, v0),
			Vector2(0.0, v1), Vector2(0.2, v1),
		)
		# Flanc droite
		_emit_quad_strip(
			st,
			_pt(p0, r0, u0, prev_off + half_w, hi0),
			_pt(p0, r0, u0, prev_off + half_w, lo0),
			_pt(p1, r1, u1, cur_off + half_w, hi1),
			_pt(p1, r1, u1, cur_off + half_w, lo1),
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
	# Supports et galets, refaits le 05/10/2026 d'après la photo d'un galet
	# du reportage remontees-mecaniques.net (O. Lakatos, 2015) et la vidéo
	# cabine du 26/04 (vue plongeante depuis le nez) :
	#   - chaque galet (RollerMesh : joues évasées Ø 640, bande caoutchouc
	#     Ø 500) tourne dans une FOURCHE (flasques galvanisées, semelle,
	#     paliers) inclinée avec lui dans les courbes ;
	#   - la fourche repose par un pied sur une TRAVERSE en U qui enjambe la
	#     fosse, tenue par deux cornières jusqu'à la longrine.
	# Positions et inclinaisons : _compute_cable_geometry (le câble tendu
	# passe exactement dans la gorge de chaque galet).
	var y_axis: float = _roller_axis_y()
	var y_fond: float = floor_y_local + slab_thickness - trench_depth - 0.01 + cable_beam_height
	var y_tr_haut: float = y_axis - RollerMesh.FOURCHE_BAS - 0.02 - SUPPORT_PIED_MIN
	var y_tr: float = y_tr_haut - SUPPORT_BAR_H * 0.5          # centre de la traverse
	var leg_h: float = maxf(y_tr - SUPPORT_BAR_H * 0.5 - y_fond, 0.02)
	var y_leg: float = y_fond + leg_h * 0.5

	var tr_pair: ArrayMesh = RollerMesh.build_traverse(SUPPORT_BAR_W)
	var tr_single: ArrayMesh = RollerMesh.build_traverse(SUPPORT_BAR_W_SINGLE)
	var pied: ArrayMesh = RollerMesh.build_pied()
	var fourches: Dictionary = {
		0: RollerMesh.build_fourche(0.0), -1: RollerMesh.build_fourche(-1.0),
		1: RollerMesh.build_fourche(1.0)}
	var socle: BoxMesh = BoxMesh.new()
	socle.size = Vector3(0.08, 1.0, 0.10)
	socle.material = RollerMesh.materiaux()["galva"]

	# Repère des galets : axe du mesh (Y) → travers de la voie ; +X local =
	# haut, +Y = gauche, +Z = arrière.
	var rot90: Basis = Basis(Vector3(0, 0, 1), PI * 0.5)
	var l_tr_p: Array = []
	var l_tr_s: Array = []
	var l_pied: Array = []
	var l_socle: Array = []
	var l_fourche: Dictionary = {0: [], -1: [], 1: []}
	var plaques: Array = []    # [Transform3D de la plaque, numéro, base du lecteur]
	_galets.clear()
	for k in range(_stations.size()):
		var st: Dictionary = _stations[k]
		var xf: Transform3D = tunnel.transform_at(st.s)
		var up: Vector3 = xf.basis.y
		var right: Vector3 = xf.basis.x
		var num: int = int(st.get("num", 0))
		if st.paired:
			l_tr_p.append(Transform3D(xf.basis, xf.origin + up * y_tr))
			for lx in [-SUPPORT_LEG_X, SUPPORT_LEG_X]:
				l_pied.append(Transform3D(xf.basis * Basis.from_scale(Vector3(1.0, leg_h, 1.0)),
					xf.origin + up * y_leg + right * lx))
			if num > 0:
				plaques.append(_support_plate(st.s, num, 0.0, SUPPORT_PLATE_X, y_tr))
		else:
			for side_i in [-1, 1]:
				var x_voie: float = _track_center_x(st.s, float(side_i))
				l_tr_s.append(Transform3D(xf.basis, xf.origin + up * y_tr + right * x_voie))
				for lx in [-SUPPORT_LEG_X_SINGLE, SUPPORT_LEG_X_SINGLE]:
					l_pied.append(Transform3D(xf.basis * Basis.from_scale(Vector3(1.0, leg_h, 1.0)),
						xf.origin + up * y_leg + right * (x_voie + lx)))
				if num > 0:
					plaques.append(_support_plate(st.s, num, _track_center_x(st.s, float(side_i)),
						SUPPORT_PLATE_X, y_tr))
		# galet de chaque brin, sa fourche et le pied de la fourche
		for side_i in [-1, 1]:
			var v: Dictionary = _strand[side_i][k + 1]   # [0] = point libre à s = 0
			var rb: Basis = (v.basis as Basis) * rot90
			var xg: Transform3D = Transform3D(rb, v.center)
			# côté intérieur d'une paire (+Y local = gauche) : pas de palier
			var variante: int = 0
			if st.paired:
				variante = -1 if side_i < 0 else 1
			l_fourche[variante].append(xg)
			var p_sem: Vector3 = (v.center as Vector3) - rb.x.normalized() * (RollerMesh.FOURCHE_BAS + 0.02)
			var h: float = maxf((p_sem - xf.origin).dot(up) - y_tr_haut, 0.02)
			l_socle.append(Transform3D(xf.basis * Basis.from_scale(Vector3(1.0, h, 1.0)), p_sem - up * (h * 0.5)))
			_galets.append({"s": st.s, "side": side_i, "xf": xg,
				"sgn": signf((rb.y.normalized().cross(rb.x.normalized())).dot(-xf.basis.z))})
	_mm_instance(tr_pair, l_tr_p, "GuideBases", 400.0)
	_mm_instance(tr_single, l_tr_s, "GuideBasesSingle", 400.0)
	_mm_instance(pied, l_pied, "GuideLegs", 300.0)
	_mm_instance(socle, l_socle, "GuidePedestals", 300.0)
	for variante in [0, -1, 1]:
		_mm_instance(fourches[variante], l_fourche[variante], "GuideForks%d" % (variante + 1), 400.0)
	_build_galets()
	_build_support_numbers(plaques)
	_cable_top_y = y_axis + pulley_radius


# --- Galets qui tournent ------------------------------------------------
# Chaque galet tourne à v/R (R = rayon de la bande, le câble y roule) tant
# que le câble est posé dessus, c'est-à-dire en amont du culot de SA rame
# (le câble s'accroche au milieu de la voiture amont ; il n'y a pas de
# câble lest sous les rames). Quand le culot le dépasse, le galet est
# libéré et ralentit sous le couple des joints et des roulements :
# I·ω' = −(M_c + c·ω), soit ω(t) = (ω0 + a)·e^(−t/τ) − a, a = M_c/c,
# τ = I/c (audit_physique/galets_ligne.sage : arrêt en ~111 s depuis
# 12 m/s). Seuls les galets proches de la caméra sont mis à jour ; les
# autres ne retiennent que l'instant et la vitesse de leur libération.
const GALET_I: float = 0.941             # kg·m²
const GALET_MC: float = 0.3777           # N·m
const GALET_C: float = 0.001216          # N·m·s
const GALET_PORTEE: float = 70.0         # m : galets détaillés et animés autour de la caméra
var _galets: Array = []                  # [{s, side, xf, sgn}] dans l'ordre des stations
var _gal_mm: Array = []                  # MultiMesh détaillé de chaque galet
var _gal_idx: PackedInt32Array = PackedInt32Array()
var _gal_local: Array = []               # transformée dans son tronçon
var _gal_theta: PackedFloat32Array = PackedFloat32Array()
var _gal_w: PackedFloat32Array = PackedFloat32Array()      # rad/s signé (repère du galet)
var _gal_cable: PackedByteArray = PackedByteArray()        # 1 = câble posé
var _gal_t0: PackedFloat32Array = PackedFloat32Array()     # instant de libération
var _gal_w0: PackedFloat32Array = PackedFloat32Array()
var _gal_th0: PackedFloat32Array = PackedFloat32Array()
var _gal_par_brin: Dictionary = {-1: PackedInt32Array(), 1: PackedInt32Array()}
var _gal_s_brin: Dictionary = {-1: PackedFloat64Array(), 1: PackedFloat64Array()}
var _gal_horloge: float = 0.0
var _gal_att_prec: Dictionary = {}       # brin → abscisse du culot à l'appel précédent
var _gal_pose_prec: Dictionary = {}      # brin → abscisse du décollage à l'appel précédent
var _gal_u: Dictionary = {-1: 0.0, 1: 0.0}   # vitesse du câble de chaque brin (m/s, +s)


func _build_galets() -> void:
	var proche: ArrayMesh = RollerMesh.build_galet(true)
	var loin: ArrayMesh = RollerMesh.build_galet(false)
	# Tronçons de 30 m, chacun en deux exemplaires : détaillé (animé) en
	# deçà de GALET_PORTEE, allégé et immobile (de révolution) au-delà —
	# mêmes tronçons, donc mêmes distances : la relève se fait sans trou.
	var holder: Node3D = Node3D.new()
	holder.name = "GuidePulleys"
	add_child(holder)
	var n: int = _galets.size()
	_gal_mm.resize(n)
	_gal_idx.resize(n)
	_gal_local.resize(n)
	_gal_theta.resize(n)
	_gal_w.resize(n)
	_gal_cable.resize(n)
	_gal_t0.resize(n)
	_gal_w0.resize(n)
	_gal_th0.resize(n)
	var i: int = 0
	var chunk: int = 0
	while i < n:
		var base: Vector3 = (_galets[i].xf as Transform3D).origin
		var j: int = i
		while j < n and ((_galets[j].xf as Transform3D).origin - base).length() < 30.0:
			j += 1
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = proche
		mm.instance_count = j - i
		for q in range(i, j):
			var loc: Transform3D = _galets[q].xf
			loc.origin -= base
			mm.set_instance_transform(q - i, loc)
			_gal_mm[q] = mm
			_gal_idx[q] = q - i
			_gal_local[q] = loc
			_gal_theta[q] = randf() * TAU
			_gal_w[q] = 0.0
			_gal_cable[q] = 1
			_gal_t0[q] = -1e9
		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mmi.name = "GuidePulleys_%d" % chunk
		mmi.multimesh = mm
		mmi.position = base
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = GALET_PORTEE
		mmi.visibility_range_end_margin = 10.0
		holder.add_child(mmi)
		var mm_loin: MultiMesh = MultiMesh.new()
		mm_loin.transform_format = MultiMesh.TRANSFORM_3D
		mm_loin.mesh = loin
		mm_loin.instance_count = j - i
		for q in range(i, j):
			mm_loin.set_instance_transform(q - i, _gal_local[q])
		var mmf: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mmf.name = "GuidePulleysFar_%d" % chunk
		mmf.multimesh = mm_loin
		mmf.position = base
		mmf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmf.visibility_range_begin = GALET_PORTEE
		mmf.visibility_range_begin_margin = 10.0
		mmf.visibility_range_end = 450.0
		mmf.visibility_range_end_margin = 20.0
		holder.add_child(mmf)
		chunk += 1
		i = j
	for side_i in [-1, 1]:
		var idx: PackedInt32Array = PackedInt32Array()
		var ss: PackedFloat64Array = PackedFloat64Array()
		for q in range(n):
			if int(_galets[q].side) == side_i:
				idx.append(q)
				ss.append(float(_galets[q].s))
		_gal_par_brin[side_i] = idx
		_gal_s_brin[side_i] = ss


## Vitesse angulaire d'un galet libéré depuis t secondes (ω0 ≥ 0).
static func galet_w_libre(w0: float, t: float) -> float:
	var a: float = GALET_MC / GALET_C
	var tau: float = GALET_I / GALET_C
	return maxf((w0 + a) * exp(-t / tau) - a, 0.0)


## Angle parcouru depuis la libération (jusqu'à l'arrêt).
static func galet_theta_libre(w0: float, t: float) -> float:
	var a: float = GALET_MC / GALET_C
	var tau: float = GALET_I / GALET_C
	var t_arret: float = tau * log((w0 + a) / a)
	var tt: float = minf(t, t_arret)
	return (w0 + a) * tau * (1.0 - exp(-tt / tau)) - a * tt


## Appelé à chaque image : culot de chaque brin (abscisse), centre de la
## zone animée (caméra), pas de temps. Le câble d'un brin avance à la
## vitesse de son culot (sa rame) ; un brin rompu ne porte plus.
func update_galets(att_g: float, att_d: float, s_cam: float, delta: float,
		rompu_brin: int = 0, pose_g: float = -1.0, pose_d: float = -1.0) -> void:
	if _galets.is_empty() or delta <= 0.0:
		return
	_gal_horloge += delta
	var atts: Dictionary = {-1: att_g, 1: att_d}
	# où le câble se pose sur les galets (décollage de la chaînette) ; à
	# défaut, au culot
	var poses: Dictionary = {-1: pose_g if pose_g >= 0.0 else att_g, 1: pose_d if pose_d >= 0.0 else att_d}
	for side_i in [-1, 1]:
		var att: float = atts[side_i]
		var prec: float = _gal_att_prec.get(side_i, att)
		var u_inst: float = (att - prec) / delta
		if absf(att - prec) > maxf(2.0, 40.0 * delta):
			# rame replacée (R, scénario) : pas un mouvement du câble
			_gal_u[side_i] = 0.0
		else:
			_gal_u[side_i] = lerpf(_gal_u[side_i], u_inst, minf(1.0, delta / 0.1))
		_gal_att_prec[side_i] = att
		var pose: float = poses[side_i]
		var pose_prec: float = _gal_pose_prec.get(side_i, pose)
		_gal_pose_prec[side_i] = pose
		var idx: PackedInt32Array = _gal_par_brin[side_i]
		var ss: PackedFloat64Array = _gal_s_brin[side_i]
		# galets dont l'état (câble posé ou non) a pu changer
		var lo: float = minf(pose_prec, pose)
		var hi: float = maxf(pose_prec, pose)
		var k0: int = ss.bsearch(lo)
		while k0 < ss.size() and ss[k0] <= hi + 1e-6:
			_galet_etat(idx[k0], side_i, pose, rompu_brin == side_i)
			k0 += 1
		# zone animée
		var a0: int = ss.bsearch(s_cam - GALET_PORTEE - 30.0)
		var a1: int = ss.bsearch(s_cam + GALET_PORTEE + 30.0)
		for k in range(a0, mini(a1, ss.size())):
			var q: int = idx[k]
			_galet_etat(q, side_i, pose, rompu_brin == side_i)
			if _gal_cable[q] == 1:
				_gal_w[q] = float(_galets[q].sgn) * _gal_u[side_i] / pulley_radius
				_gal_theta[q] = fposmod(_gal_theta[q] + _gal_w[q] * delta, TAU)
			else:
				var t: float = _gal_horloge - _gal_t0[q]
				var w0: float = _gal_w0[q]
				var sg: float = signf(w0)
				_gal_w[q] = sg * galet_w_libre(absf(w0), t)
				_gal_theta[q] = fposmod(_gal_th0[q] + sg * galet_theta_libre(absf(w0), t), TAU)
			var loc: Transform3D = _gal_local[q]
			(_gal_mm[q] as MultiMesh).set_instance_transform(_gal_idx[q],
				Transform3D(loc.basis * Basis(Vector3.UP, _gal_theta[q]), loc.origin))


func _galet_etat(q: int, side_i: int, pose: float, rompu: bool) -> void:
	var porte: int = 1 if (float(_galets[q].s) > pose and not rompu) else 0
	if porte == _gal_cable[q]:
		return
	if porte == 0:
		# libéré : il garde la vitesse du câble et ralentit seul
		var w: float = float(_galets[q].sgn) * _gal_u[side_i] / pulley_radius
		_gal_w0[q] = w
		_gal_t0[q] = _gal_horloge
		_gal_th0[q] = _gal_theta[q]
	_gal_cable[q] = porte


## État d'un galet pour les bancs : {s, side, cable, w}.
func galet_etat(q: int) -> Dictionary:
	if q < 0 or q >= _galets.size():
		return {}
	# sous le câble : v / R, même hors de la zone animée
	var w: float = float(_galets[q].sgn) * float(_gal_u[int(_galets[q].side)]) / pulley_radius
	if _gal_cable[q] == 0:
		w = signf(_gal_w0[q]) * galet_w_libre(absf(_gal_w0[q]), _gal_horloge - _gal_t0[q])
	return {"s": float(_galets[q].s), "side": int(_galets[q].side),
		"cable": _gal_cable[q] == 1, "w": w}


func galets_count() -> int:
	return _galets.size()


# --- Numéros des supports (faits de Kevin, 03/10/2026) ----------------
# Peints en BLANC rétroréfléchissant : invisibles dans le noir, ils
# s'allument dans les phares. En montant, un support sur deux porte un
# numéro PAIR (2 → 238), sur la face tournée vers la rame montante, à
# DROITE juste avant le bout de la traverse — à GAUCHE dans les virages à
# droite. En descendant, les autres portent les numéros IMPAIRS (237 → 1),
# même règle vue de la rame descendante. Le n° 1 (bout du quai aval) n'a
# donc pas de numéro en montant, ni le n° 238 en descendant.
const SUPPORT_BAR_W: float = 1.40        # traverse : entre deux plots, elle prend la largeur de la fosse
const SUPPORT_BAR_W_SINGLE: float = 1.10 # évitement : fosse d'une seule voie
const SUPPORT_LEG_X_SINGLE: float = 0.48
const SUPPORT_PIED_MIN: float = 0.06     # pied de fourche sur la traverse (galet droit)
const SUPPORT_BAR_H: float = 0.10
const SUPPORT_BAR_D: float = 0.10
const SUPPORT_LEG_X: float = 0.62
# Plaque au bout droit de la traverse (« juste avant le bord »), à droite
# du brin et de son galet, SURÉLEVÉE sur un potelet : son bas au-dessus du
# dessus des plots, son haut sous le champignon du rail. Retours des 03 et
# 04/10 : au ras de la traverse, les plots la masquaient vue du poste ;
# rentrée à 19 cm de l'axe, c'est le second brin du câble qui passait devant.
# 05/10 : galets Ø 640 et leurs paliers → plaque à 36 cm de l'axe et 15 cm
# en avant du support, son potelet hors des paliers.
const SUPPORT_PLATE_X: float = 0.36
const SUPPORT_PLATE_Z: float = 0.15      # en avant du support : hors des paliers et des joues
const SUPPORT_PLATE: Vector2 = Vector2(0.25, 0.14)
const SUPPORT_DIGIT_H: float = 0.10      # hauteur des chiffres (m)
const VIRAGE_SEUIL: float = 0.01         # Δ de tangente sur ±10 m (R ≲ 2 km)

const RETRO_SHADER: String = """
shader_type spatial;
render_mode cull_back;
uniform vec3 couleur : source_color = vec3(0.93, 0.93, 0.90);
uniform float phares = 0.0;     // 0..1 : phares de la cabine (vue cabine seulement)
uniform float gain = 1.0;
uniform float plafond = 20.0;   // reflet maximal (de près) : le fond bleu reste bleu
uniform float portee = 80.0;    // m : reflet égal à la couleur à cette distance
// Rétroréflexion : la lumière des phares revient vers la cabine — luminance
// en 1/d² (éclairement reçu), plafonnée de près ; « pas franchement
// réfléchissants » à 30 m / ×3 (retour du 03/10).
void fragment() {
	ALBEDO = couleur;
	ROUGHNESS = 0.7;
	float d = max(length(VERTEX), 0.5);
	float face = clamp(dot(NORMAL, normalize(-VERTEX)), 0.0, 1.0);
	EMISSION = couleur * phares * gain * face * min(portee * portee / (d * d), plafond);
}
"""
var _retro_mats: Array[ShaderMaterial] = []
var _retro_level: float = -1.0


func _retro_material(col: Color, gain: float, plafond: float = 20.0) -> ShaderMaterial:
	var sh: Shader = Shader.new()
	sh.code = RETRO_SHADER
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("couleur", col)
	m.set_shader_parameter("gain", gain)
	m.set_shader_parameter("plafond", plafond)
	_retro_mats.append(m)
	return m


## Rétroréflexion des numéros : `level` = phares de la cabine (0..1), en vue
## cabine seulement (ailleurs la caméra n'est pas à côté des phares).
func set_retro(level: float) -> void:
	if absf(level - _retro_level) < 0.002:
		return
	_retro_level = level
	for m in _retro_mats:
		m.set_shader_parameter("phares", level)


## Δ de tangente horizontale sur ±10 m : > 0 = virage à droite en montant.
func _virage(s: float) -> float:
	var a: Vector3 = -tunnel.transform_at(s - 10.0).basis.z
	var b: Vector3 = -tunnel.transform_at(s + 10.0).basis.z
	return (b - a).dot(tunnel.transform_at(s).basis.x)


## Plaque du support n° `num` : face tournée vers le lecteur (pair = rame
## montante, impair = rame descendante), sur la traverse centrée en
## `x_centre` ; `x_bord` = décalage vers la droite du lecteur (0 = centrée).
func _support_plate(s: float, num: int, x_centre: float, x_bord: float, y_cb: float) -> Array:
	var xf: Transform3D = tunnel.transform_at(s)
	var montant: bool = num % 2 == 0
	var lecteur: Basis = xf.basis if montant else Basis(-xf.basis.x, xf.basis.y, -xf.basis.z)
	var v: float = _virage(s)
	var virage_droite: bool = (v > VIRAGE_SEUIL) if montant else (v < -VIRAGE_SEUIL)
	var cote: float = -1.0 if virage_droite else 1.0
	var y_pl: float = floor_y_local + slab_thickness + sleeper_height + 0.02 + SUPPORT_PLATE.y * 0.5
	var pos: Vector3 = xf.origin + xf.basis.y * y_pl + xf.basis.x * x_centre \
		+ lecteur.x * (x_bord * cote) + lecteur.z * SUPPORT_PLATE_Z
	return [Transform3D(lecteur, pos), num, lecteur]


func _build_support_numbers(plaques: Array) -> void:
	var blanc: ShaderMaterial = _retro_material(Color(0.93, 0.93, 0.90), 1.0)
	var bleu: ShaderMaterial = _retro_material(Color(0.06, 0.20, 0.55), 1.0, 2.5)
	# face réfléchissante (vers le lecteur seulement) + dos en métal nu :
	# le dos des plaques de l'autre sens ne doit pas paraître bleu
	var plate: QuadMesh = QuadMesh.new()
	plate.size = SUPPORT_PLATE
	plate.material = bleu
	var font: Font = ThemeDB.fallback_font
	var fs: int = 64
	var px: float = SUPPORT_DIGIT_H / (0.72 * float(fs))   # hauteur de capitale ≈ 0,72 em
	var adv: float = font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * px
	var chiffres: Array = []
	for d in range(10):
		var tm: TextMesh = TextMesh.new()
		tm.text = str(d)
		tm.font_size = fs
		tm.pixel_size = px
		# plat et contours grossiers : 59 triangles par chiffre au lieu de
		# 1 864 (44 000 triangles par image avec les réglages par défaut)
		tm.depth = 0.0
		tm.curve_step = 4.0
		tm.material = blanc
		chiffres.append(tm)
	# potelet sous la plaque, depuis le fond de la fosse
	var y_fond: float = floor_y_local + slab_thickness - trench_depth - 0.01 + cable_beam_height
	var y_bas: float = floor_y_local + slab_thickness + sleeper_height + 0.02
	var post: BoxMesh = BoxMesh.new()
	post.size = Vector3(0.025, y_bas - y_fond, 0.025)
	var galva: StandardMaterial3D = StandardMaterial3D.new()
	galva.albedo_color = Color(0.80, 0.81, 0.79)
	galva.roughness = 0.5
	galva.metallic = 0.3
	post.material = galva
	var dos: BoxMesh = BoxMesh.new()
	dos.size = Vector3(SUPPORT_PLATE.x + 0.01, SUPPORT_PLATE.y + 0.01, 0.004)
	dos.material = galva
	var l_dos: Array = []
	var l_post: Array = []
	var l_plate: Array = []
	var l_dig: Array = []
	for d in range(10):
		l_dig.append([])
	for pl in plaques:
		var tr: Transform3D = pl[0]
		var txt: String = str(pl[1])
		var lb: Basis = pl[2]
		l_plate.append(tr)
		l_dos.append(Transform3D(lb, tr.origin - lb.z * 0.0025))
		var pied: Vector3 = tr.origin - lb.y * (SUPPORT_PLATE.y * 0.5 + (y_bas - y_fond) * 0.5) - lb.z * 0.02
		l_post.append(Transform3D(lb, pied))
		for i in range(txt.length()):
			var o: float = (float(i) - 0.5 * float(txt.length() - 1)) * adv
			var p: Vector3 = tr.origin + lb.x * o + lb.z * 0.003
			(l_dig[int(txt[i])] as Array).append(Transform3D(lb, p))
	# plaques visibles loin : au fond du tunnel, une file de points qui brillent
	_mm_instance(plate, l_plate, "SupportPlates", 300.0)
	_mm_instance(post, l_post, "SupportPlatePosts", 200.0)
	_mm_instance(dos, l_dos, "SupportPlateBacks", 200.0)
	for d in range(10):
		_mm_instance(chiffres[d], l_dig[d], "SupportDigits%d" % d, 120.0)


# Lacunes de l'aiguillage : plaques d'appui sombres sous les bouts de rail
# (photo de Kevin : une plaque boulonnée sous chaque extrémité) et tôle de
# glissement sous le câble dans le couloir (photo d'Hakone). La tôle
# affleure à 12 mm sous le câble : il y glisse s'il décolle des galets.
func _build_abt_plates() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.17, 0.15, 0.14)
	mat.roughness = 0.65
	mat.metallic = 0.55
	var bolt_mat: StandardMaterial3D = StandardMaterial3D.new()
	bolt_mat.albedo_color = Color(0.30, 0.29, 0.28)
	bolt_mat.roughness = 0.5
	bolt_mat.metallic = 0.8
	var y_base: float = floor_y_local + slab_thickness + sleeper_height - 0.01
	var plate: BoxMesh = BoxMesh.new()
	plate.size = Vector3(0.24, 0.014, 0.55)
	plate.material = mat
	var slide: BoxMesh = BoxMesh.new()
	slide.size = Vector3(0.11, 0.010, 1.0)   # étirée en longueur par instance
	slide.material = mat
	var bolt: BoxMesh = BoxMesh.new()
	bolt.size = Vector3(0.035, 0.022, 0.035)
	bolt.material = bolt_mat
	var l_plate: Array = []
	var l_slide: Array = []
	var l_bolt: Array = []
	for g in _abt.gaps:
		var ri: float = float(g.rail)
		for z in ["lo", "hi"]:
			var dirn: float = g["dirn_" + z]
			var sc: float = g["sc_" + z]
			# bout A (fin côté évitement) et bout B (début côté fourche)
			for e in [[g["a_end_" + z], "A", -1.0], [g["b_start_" + z], "B", 1.0]]:
				var s_end: float = e[0]
				var piece: Dictionary = {"kind": e[1], "rail": g.rail, "zone": z}
				var toward: float = -dirn if e[1] == "A" else dirn   # vers l'intérieur du bout
				var s_mid: float = s_end + toward * 0.25
				# côté opposé au câble : A est du côté −ri, B du côté +ri
				var away: float = ri * e[2]
				var xf: Transform3D = _abt_frame(piece, s_mid)
				var tr: Transform3D = xf
				tr.origin += xf.basis.x * (away * 0.075) + xf.basis.y * (y_base + 0.007)
				l_plate.append(tr)
				for db in [-0.17, 0.17]:
					var tb: Transform3D = xf
					tb.origin += xf.basis.x * (away * 0.15) - xf.basis.z * db \
						+ xf.basis.y * (y_base + 0.018)
					l_bolt.append(tb)
			# tôle de glissement le long du câble, du coude A au coude B
			var sa: float = g["bend_a_" + z]
			var sb: float = g["bend_b_" + z]
			var pa: Vector3 = strand_point(-g.rail, sa)
			var pb: Vector3 = strand_point(-g.rail, sb)
			var xa: Transform3D = tunnel.transform_at(0.5 * (sa + sb))
			var fwd: Vector3 = (pb - pa).normalized()
			var up: Vector3 = (xa.basis.y - fwd * xa.basis.y.dot(fwd)).normalized()
			var right: Vector3 = fwd.cross(up)
			var bs: Basis = Basis(right, up, -fwd).scaled_local(Vector3(1.0, 1.0, pa.distance_to(pb)))
			var mid: Vector3 = (pa + pb) * 0.5
			var y_mid: float = (mid - xa.origin).dot(xa.basis.y)
			mid += xa.basis.y * (y_base + 0.005 - y_mid)
			l_slide.append(Transform3D(bs, mid))
	_mm_instance(plate, l_plate, "AbtPlaquesAppui")
	_mm_instance(bolt, l_bolt, "AbtBoulons", 150.0)
	_mm_instance(slide, l_slide, "AbtToleGlissement")


# Repère posé sur un bout de rail : origine sur l'axe de la voie à s, axe
# −z le long du bout (parallèle au câble dans la lacune).
func _abt_frame(piece: Dictionary, s: float) -> Transform3D:
	var xf: Transform3D = tunnel.transform_at(s)
	var xa: Transform3D = tunnel.transform_at(s - 0.05)
	var xb: Transform3D = tunnel.transform_at(s + 0.05)
	var p0: Vector3 = xa.origin + xa.basis.x * _piece_x(piece, s - 0.05)
	var p1: Vector3 = xb.origin + xb.basis.x * _piece_x(piece, s + 0.05)
	var fwd: Vector3 = (p1 - p0).normalized()
	var up: Vector3 = (xf.basis.y - fwd * xf.basis.y.dot(fwd)).normalized()
	var right: Vector3 = fwd.cross(up)
	return Transform3D(Basis(right, up, -fwd), xf.origin + xf.basis.x * _piece_x(piece, s))


## Galet de déviation au sommet i du brin : n, du câble vers le centre de
## la poulie (côté intérieur du coude, là où la tension tire le câble,
## 30° sous l'horizontale), et axe de la poulie.
func _poulie_deviation(pts: Array, i: int, side_i: int) -> Dictionary:
	var xf: Transform3D = tunnel.transform_at(pts[i].s)
	var a: Vector3 = pts[i - 1].p
	var v: Vector3 = pts[i].p
	var b: Vector3 = pts[i + 1].p
	var pull: Vector3 = (b - v).normalized() - (v - a).normalized()
	var lat: float = pull.dot(xf.basis.x)
	var inside: float = signf(lat) if absf(lat) > 1e-7 else -float(side_i)
	var beta: float = deg_to_rad(sheave_incline_deg)
	var n: Vector3 = (xf.basis.x * inside * cos(beta) - xf.basis.y * sin(beta)).normalized()
	var u: Vector3 = (b - a).normalized()
	return {"n": n, "axe": u.cross(n).normalized()}


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
	var y_floor: float = floor_y_local + slab_thickness - trench_depth - 0.01
	for k in range(_stations.size()):
		var st: Dictionary = _stations[k]
		if not st.sheave:
			continue
		var xf: Transform3D = tunnel.transform_at(st.s)
		for side_i in [-1, 1]:
			var pts: Array = _strand[side_i]
			var v: Vector3 = pts[k + 1].p
			var n: Vector3 = pts[k + 1].poulie.n
			var axis: Vector3 = pts[k + 1].poulie.axe
			var inside: float = signf(n.dot(xf.basis.x))
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


# Rupture : pas des anneaux du tube et posé du câble détendu.
const CABLE_SUBDIV_M: float = 2.0
# Tension du brin pour la flèche des portées (maillage fixe) : celle d'une
# rame en bas de ligne (≈ 140 kN, jauge du pupitre au départ), plus le
# poids du câble au-dessus (w·Δz) : ≈ 240 kN en haut.
const TENSION_BAS_N: float = 140000.0
var _alt_bas: float = NAN


## Flèche du câble (m, sous la corde) à l'abscisse s : chaînette de la
## portée entre les deux galets qui l'encadrent. Nulle sur les galets et
## dans les portées des gares (le brin y file vers la salle des machines).
func fleche(side_i: int, s: float) -> float:
	var sup: PackedFloat64Array = _appuis(side_i)
	var k: int = sup.bsearch(s)
	if k <= 1 or k >= sup.size() - 1:
		return 0.0          # avant le 1er galet ou après le dernier
	var s_a: float = sup[k - 1]
	var s_b: float = sup[k]
	var l: float = s_b - s_a
	if l <= 0.0:
		return 0.0
	var a: float = a_chainette(s)
	return maxf(a * (cosh(l / (2.0 * a)) - cosh((s - s_a - l * 0.5) / a)), 0.0)


## Paramètre de chaînette a = T / (w cos α) du câble à l'abscisse s (m),
## avec T = TENSION_BAS_N + w·Δz. Le même pour les portées et pour le
## tronçon libre du culot : la tension est continue le long du câble (un
## galet la dévie, il ne la change pas) — avec la tension de la jauge pour
## le tronçon libre et celle-ci pour les portées (jusqu'à 239 kN en haut),
## le câble pliait vers le haut sur certains premiers galets (jusqu'à
## 0,16°). audit_physique/decollage_galet.sage.
func a_chainette(s: float) -> float:
	if is_nan(_alt_bas):
		_alt_bas = tunnel.transform_at(0.0).origin.y
	var w: float = PNConstants.CABLE_KG_M * 9.80665
	var t: float = TENSION_BAS_N + w * maxf(tunnel.transform_at(s).origin.y - _alt_bas, 0.0)
	return t / (w * cos(SlopeProfile.slope_angle_at(s)))
const SLACK_TOUCHDOWN_M: float = 1.5   # du sommet du galet à la longrine
var _support_s: Dictionary = {}       # côté → abscisses des appuis (galets)


## Descente du câble détendu à l'abscisse s : il quitte le sommet du galet
## et se pose sur la longrine en SLACK_TOUCHDOWN_M (rigidité du câble de
## 52 mm), axe à cable_radius au-dessus de la longrine. Nulle sur les
## galets et près des gares (le brin y remonte vers la salle des machines).
func _slack_drop_max() -> float:
	var y_nom: float = _roller_axis_y() + pulley_radius + cable_radius
	var y_pose: float = floor_y_local + slab_thickness - trench_depth - 0.01 + cable_beam_height + cable_radius
	return maxf(y_nom - y_pose, 0.0)


func _slack_drop(side_i: int, s: float) -> float:
	var sup: PackedFloat64Array = _appuis(side_i)
	var k: int = sup.bsearch(s)
	var d_appui: float = INF
	if k < sup.size():
		d_appui = minf(d_appui, sup[k] - s)
	if k > 0:
		d_appui = minf(d_appui, s - sup[k - 1])
	var bouts: float = smoothstep(15.0, 30.0, minf(s, PNConstants.LENGTH - s))
	return _slack_drop_max() * smoothstep(0.0, SLACK_TOUCHDOWN_M, d_appui) * bouts


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

	# Anneaux intermédiaires tous les ~2 m entre deux galets : le tube était
	# droit d'un galet à l'autre (rien à courber). Détendu après une
	# rupture, le câble doit pouvoir retomber sur la longrine entre les
	# galets ; chaque anneau porte en UV2.x sa descente à « détente
	# totale » (cf. _slack_drop et cable_shader.gdshader).
	# Flèche de chaque portée (retour du 06/10/2026 : « fais le cosh dans
	# chaque section de câble entre ses points d'appui ») : le câble pend
	# en chaînette entre deux galets, perpendiculairement à la corde, de
	# a(cosh(L/2a) − cosh((x − L/2)/a)) — 1,2 à 2 cm sur 14,5 m.
	var rings: Array = []
	for i in range(chain.size() - 1):
		var n_sub: int = maxi(1, int(ceil((chain[i + 1].s - chain[i].s) / CABLE_SUBDIV_M)))
		for j in range(n_sub):
			var f: float = float(j) / float(n_sub)
			var s_r: float = lerpf(chain[i].s, chain[i + 1].s, f)
			var u_r: Vector3 = ups[i].lerp(ups[i + 1], f).normalized()
			var fl: float = fleche(side_i, s_r)
			rings.append({"s": s_r, "p": chain[i].p.lerp(chain[i + 1].p, f) - u_r * fl,
				"r": rights[i].lerp(rights[i + 1], f).normalized(),
				"u": u_r,
				"d": maxf(_slack_drop(side_i, s_r) - fl, 0.0)})
	var last: int = chain.size() - 1
	var fl_l: float = fleche(side_i, chain[last].s)
	rings.append({"s": chain[last].s, "p": chain[last].p - ups[last] * fl_l, "r": rights[last], "u": ups[last],
		"d": maxf(_slack_drop(side_i, chain[last].s) - fl_l, 0.0)})

	for i in range(rings.size() - 1):
		var c0: Vector3 = rings[i].p
		var c1: Vector3 = rings[i + 1].p
		var r0: Vector3 = rings[i].r
		var r1: Vector3 = rings[i + 1].r
		var u0: Vector3 = rings[i].u
		var u1: Vector3 = rings[i + 1].u
		var v0_uv: float = float(rings[i].s) * 2.0
		var v1_uv: float = float(rings[i + 1].s) * 2.0
		# UV2 = (descente sur la longrine, poids 0 au galet → 1 posé) ;
		# COLOR = direction « droite » de la voie, pour l'ondulation latérale
		# du câble lâche (cable_shader.gdshader)
		var d0: Vector2 = Vector2(rings[i].d, rings[i].d / maxf(_slack_drop_max(), 1e-3))
		var d1: Vector2 = Vector2(rings[i + 1].d, rings[i + 1].d / maxf(_slack_drop_max(), 1e-3))
		var col0: Color = Color(0.5 + 0.5 * r0.x, 0.5 + 0.5 * r0.y, 0.5 + 0.5 * r0.z)
		var col1: Color = Color(0.5 + 0.5 * r1.x, 0.5 + 0.5 * r1.y, 0.5 + 0.5 * r1.z)
		for k in range(cable_segments):
			var a0: float = float(k) / float(cable_segments) * TAU
			var a1: float = float(k + 1) / float(cable_segments) * TAU
			var p00: Vector3 = c0 + r0 * cos(a0) * cable_radius + u0 * sin(a0) * cable_radius
			var p01: Vector3 = c0 + r0 * cos(a1) * cable_radius + u0 * sin(a1) * cable_radius
			var p10: Vector3 = c1 + r1 * cos(a0) * cable_radius + u1 * sin(a0) * cable_radius
			var p11: Vector3 = c1 + r1 * cos(a1) * cable_radius + u1 * sin(a1) * cable_radius
			var u0_uv: float = float(k) / float(cable_segments)
			var u1_uv: float = float(k + 1) / float(cable_segments)
			st.set_color(col0); st.set_uv(Vector2(u0_uv, v0_uv)); st.set_uv2(d0); st.add_vertex(p00)
			st.set_color(col1); st.set_uv(Vector2(u0_uv, v1_uv)); st.set_uv2(d1); st.add_vertex(p10)
			st.set_color(col1); st.set_uv(Vector2(u1_uv, v1_uv)); st.set_uv2(d1); st.add_vertex(p11)
			st.set_color(col0); st.set_uv(Vector2(u0_uv, v0_uv)); st.set_uv2(d0); st.add_vertex(p00)
			st.set_color(col1); st.set_uv(Vector2(u1_uv, v1_uv)); st.set_uv2(d1); st.add_vertex(p11)
			st.set_color(col0); st.set_uv(Vector2(u1_uv, v0_uv)); st.set_uv2(d0); st.add_vertex(p01)

	# (pas de tangentes : le shader du câble n'a pas de carte de normales)
	st.generate_normals()
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


func update_cable_visibility(s_driver: float, s_other: float = -1.0) -> void:
	# `s_other` : position de l'autre rame — LENGTH − s_driver en marche,
	# figée quand le câble a rompu (TrainPhysics.ghost_s_render).
	if s_other < 0.0:
		s_other = PNConstants.miroir(s_driver)
	# Où commence chaque brin visible (premier galet que touche le câble de
	# LA rame qu'il tire) :
	#   - rame 1 pilotée : brin gauche = sa rame, brin droit = la rame opposée.
	#   - rame 2 pilotée : c'est l'inverse (la cabine est sur la voie droite).
	var s_left: float = coupe_brin(-1, s_other if driver_is_rame2 else s_driver)
	var s_right: float = coupe_brin(1, s_driver if driver_is_rame2 else s_other)
	# La visibilité d'un segment (15 m) ne change que quand la coupe d'un
	# brin franchit une frontière de segment : inutile d'itérer ~460
	# segments à 60 Hz entre-temps. Clé = segments des deux COUPES (et non
	# des rames) : la coupe est au premier galet touché, qui avance par
	# sauts et recule d'une rame à l'autre — avec une clé sur les rames,
	# le segment juste après ce galet restait masqué jusqu'au franchissement
	# suivant (retour du 06/10/2026 : « au point de contact avec le galet le
	# câble semble s'interrompre », jusqu'à 15 m de câble manquant une fois
	# sur quatre). On force aussi le recalcul si le choix de rame a changé
	# (sélecteur de scénario, retour d'essai PWA 2026-07-12).
	var seg_idx: int = int(floor(s_left / cable_segment_length)) * 1000 \
		+ int(floor(s_right / cable_segment_length))
	if seg_idx == _last_vis_seg_idx and driver_is_rame2 == _last_vis_rame2:
		return
	_last_vis_seg_idx = seg_idx
	_last_vis_rame2 = driver_is_rame2
	for seg in cable_left_segments:
		# Segment visible si une partie est en amont de la coupe
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
func update_cable_phase(s_driver: float, s_other: float = -1.0) -> void:
	if cable_left_material == null or cable_right_material == null:
		return
	# `s_other` : position de l'autre rame (figée si le câble a rompu).
	if s_other < 0.0:
		s_other = PNConstants.miroir(s_driver)
	# Le brin de LA rame pilotée doit apparaître FIXE dans le référentiel de
	# la cabine (phase = s_driver) ; l'autre brin suit l'autre rame (phase =
	# s_other − LENGTH, soit −s_driver en marche : il défile ; immobile
	# quand l'autre rame est clouée par son parachute).
	# Selon rame 1 / rame 2, ce n'est pas le même brin qui est « le sien ».
	var own_phase: float = s_driver
	var other_phase: float = s_other - PNConstants.LENGTH
	cable_left_material.set_shader_parameter("cable_phase",
		other_phase if driver_is_rame2 else own_phase)
	cable_right_material.set_shader_parameter("cable_phase",
		own_phase if driver_is_rame2 else other_phase)
	# Coupe au fragment près : chaque brin n'existe qu'entre SA rame et la
	# poulie en haut. Complète le masquage par segments (grossier, 15 m) —
	# sans ça, en descente on voyait des bouts de son propre câble
	# apparaître devant la cabine puis disparaître d'un coup.
	var s_left: float = coupe_brin(-1, s_other if driver_is_rame2 else s_driver)
	var s_right: float = coupe_brin(1, s_driver if driver_is_rame2 else s_other)
	cable_left_material.set_shader_parameter("cut_below_s", s_left)
	cable_right_material.set_shader_parameter("cut_below_s", s_right)
	_update_culots(s_other if driver_is_rame2 else s_driver,
		s_driver if driver_is_rame2 else s_other)


# ---------------------------------------------------------------------------
# Attache du câble (05/10/2026, fait de Kevin) : le câble s'accroche au
# MILIEU DE LA VOITURE AMONT de chaque rame, par un culot (cône coulé sur
# son extrémité, « attaches culot » de la fiche technique) tenu sous la
# caisse par une chape. Le culot est au-dessus des joues des galets — sinon
# il les heurterait en passant — et le câble descend de lui jusqu'au
# premier galet en amont, d'où il repart posé de galet en galet.
# ---------------------------------------------------------------------------
const ATTACHE_DS: float = PNConstants.CAR_LEN_M * 0.5   # centre de la voiture amont
const CULOT_DY: float = 0.12        # axe du culot au-dessus de l'axe du câble posé
const CAISSE_Y: float = -1.16       # fond plat des voitures (TrainBodyBuilder.Y_CUT, monde)
const CULOT_LONG: float = 0.27      # le câble sort par la pointe
const AMORCE_ANNEAUX: int = 22
var _culots: Dictionary = {}        # brin → {culot, tirant, amorce, mat}


## Paramètre de la chaînette a = T / (w cos α) au culot (m), et distance
## x0 = a·acosh(1 + h/a) à laquelle le câble quitterait une ligne d'appui
## continue, tangentiellement, pour monter de h = CULOT_DY jusqu'au culot
## (retour du 06/10/2026 : « respecter la courbure du câble en cosh, qu'il
## se décolle du galet un peu avant l'attache et sans angle »). Même
## tension que les portées (a_chainette) : audit_physique/chainette_attache.sage.
func chainette(s_att: float) -> Vector2:
	var a: float = a_chainette(s_att)
	return Vector2(a, a * acosh(1.0 + CULOT_DY / a))


## Premier galet que le câble touche en amont du culot. Les appuis sont
## discrets : du culot, le câble décrit UNE chaînette jusqu'au galet R1 et
## survole ceux d'avant. Le galet k porte le câble si la chaînette qui
## irait plus loin (jusqu'au galet k + 1) passerait SOUS lui ; sinon le
## câble, tiré vers l'avant, le survole. C'est le même critère que « le
## câble plie vers le bas sur R1 » (coude_appui ≤ 0 : un galet porte, il ne
## retient pas), mais posé sur la forme même du tronçon libre dessiné : au
## changement de R1, le câble passe à 0 mm du galet qu'il quitte, et le
## quitte tangentiellement — sans angle ni saut (retour du 06/10/2026 :
## « le décollement est toujours brusque avec un angle » ; l'ancien critère
## D·(D + L) ≥ 2ah supposait une voie droite et la tension de la jauge :
## 15 % des positions pliaient vers le haut, jusqu'à 0,8°). Si la chaînette
## passe sous un galet intermédiaire (bosse du profil en long), le câble
## repose sur lui. Renvoie l'indice dans les sommets du brin, ou −1 (gare
## amont : plus de galet).
var _pa_cache: Dictionary = {}      # brin → [s_att, a, résultat]


func _appuis(side_i: int) -> PackedFloat64Array:
	if not _support_s.has(side_i):
		var arr: PackedFloat64Array = PackedFloat64Array()
		for v in _strand[side_i]:
			arr.append(v.s)
		_support_s[side_i] = arr
	return _support_s[side_i]


func premier_appui(side_i: int, s_att: float, a: float) -> int:
	var pts: Array = _strand.get(side_i, [])
	if pts.size() < 3:
		return -1
	# appelé plusieurs fois par image avec les mêmes arguments
	var memo: Array = _pa_cache.get(side_i, [])
	if not memo.is_empty() and memo[0] == s_att and memo[1] == a:
		return memo[2]
	var res: int = _premier_appui(side_i, s_att, a, pts)
	_pa_cache[side_i] = [s_att, a, res]
	return res


func _premier_appui(side_i: int, s_att: float, a: float, pts: Array) -> int:
	var p_att: Vector3 = strand_point(side_i, s_att)
	var premier: int = maxi(_appuis(side_i).bsearch(s_att + 0.5, false), 1)
	var dernier: int = pts.size() - 2          # dernier galet ([fin] = point libre)
	var s_fin: float = PNConstants.LENGTH - 0.3
	for k in range(premier, dernier + 1):
		var d: float = float(pts[k].s) - s_att
		# un galet intermédiaire plus haut que la chaînette : le câble
		# repose dessus
		for j in range(premier, k):
			if hauteur_sur_galet(side_i, s_att, p_att, pts[k].p, d, a, j) < 0.0:
				return j
		# la chaînette vers l'appui suivant (au dernier galet : la sortie
		# vers la salle des machines) passerait-elle sous k ?
		var s2: float = float(pts[k + 1].s) if k < dernier else s_fin
		var p2: Vector3 = pts[k + 1].p if k < dernier else strand_point(side_i, s_fin)
		if s2 - s_att > 0.5 and hauteur_sur_galet(side_i, s_att, p_att, p2, s2 - s_att, a, k) <= 0.0:
			return k
	return -1


## Coude vertical (rad) du câble sur le galet k s'il y repose : il arrive
## du culot en chaînette (corde p_att → galet, hauteur chainette_y) et
## repart dans la portée suivante telle qu'elle est dessinée (corde vers le
## galet suivant, flèche). Négatif : le câble plie vers le bas, le galet le
## porte. Positif : il faudrait le tirer vers le bas — en vrai il passe
## au-dessus du galet. Calculé sur les dérivées (chainette_y, fleche) et
## non par différences de positions : en float 32 à 2 km de l'origine,
## 5 cm d'écart portent 0,3° de bruit.
func coude_appui(side_i: int, s_att: float, p_att: Vector3, a: float, k: int) -> float:
	var pts: Array = _strand[side_i]
	var s_k: float = pts[k].s
	var p_k: Vector3 = pts[k].p
	var d: float = s_k - s_att
	var up: Vector3 = tunnel.transform_at(s_k).basis.y
	var x_m: float = d * 0.5 + a * asinh(CULOT_DY / (2.0 * a * maxf(sinh(d / (2.0 * a)), 1e-9)))
	var t_in: Vector3 = ((p_k - p_att) / d + up * sinh((d - x_m) / a)).normalized()
	var t_out: Vector3 = Vector3.ZERO
	if k + 1 < pts.size():
		var l: float = float(pts[k + 1].s) - s_k
		var e: float = 0.01
		t_out = ((pts[k + 1].p - p_k) / l - up * ((fleche(side_i, s_k + e) - fleche(side_i, s_k)) / e)).normalized()
	else:
		t_out = (p_k - p_att).normalized()
	return asin(clampf(t_out.dot(up), -1.0, 1.0)) - asin(clampf(t_in.dot(up), -1.0, 1.0))


## Hauteur du câble au-dessus du sommet de la gorge du galet j, pour la
## chaînette du culot (corde p_att → p_k de longueur d) : chaînette plus
## écart vertical entre la corde et ce galet (profil en long courbe).
func hauteur_sur_galet(side_i: int, s_att: float, p_att: Vector3, p_k: Vector3, d: float,
		a: float, j: int) -> float:
	var sj: float = _strand[side_i][j].s
	var xj: float = sj - s_att
	var base: Vector3 = p_att.lerp(p_k, xj / d)
	return chainette_y(xj, d, CULOT_DY, a) \
		+ (base - (_strand[side_i][j].p as Vector3)).dot(tunnel.transform_at(sj).basis.y)


## Tronçon libre du culot au premier appui (retour du 06/10/2026 :
## « vérifie la pose du câble dans les virages et l'évitement »). En
## hauteur : la chaînette. Sur le côté : la corde du culot au premier appui
## coupe l'intérieur des virages (jusqu'à 18 cm) — or le câble qui survole
## bas un galet est entre ses joues : elles ne lui laissent que le jeu de
## la gorge (jeu_gorge), et le galet, incliné en courbe, le pousse par sa
## joue. Le câble suit donc une ligne brisée : tendu en ligne droite, il
## ne s'écarte de la corde qu'au contact d'une joue, juste au bord de ce
## jeu. Galets de déviation de l'aiguillage compris. Plus haut que les
## lèvres des joues, il passe au-dessus du galet sans le toucher.
## Renvoie {att, s1, a, x: [], lat: [], y: []} (lat : écart à la corde).
const Y_HORS_GORGE: float = RollerMesh.R_JOUE - RollerMesh.R_BANDE   # 7 cm
func amorce_profil(side_i: int, s_rame: float, n: int = AMORCE_ANNEAUX) -> Dictionary:
	var att: float = attache_s(s_rame)
	var a: float = chainette(att).x
	var k1: int = premier_appui(side_i, att, a)
	var s1: float = float(_strand[side_i][k1].s) if k1 > 0 else PNConstants.LENGTH - 0.3
	var d: float = maxf(s1 - att, 0.5)
	var p_att: Vector3 = strand_point(side_i, att)
	var p_r1: Vector3 = strand_point(side_i, s1)
	# galets survolés : la gorge est dans le repère du galet, incliné en
	# courbe (il reçoit le câble dans l'axe de l'effort) — au décollage, le
	# câble part dans cet axe, pas à la verticale de la voie
	var gal: Array = []
	if k1 > 0:
		for j in range(1, k1):
			var sj: float = _strand[side_i][j].s
			var xj: float = sj - att
			if xj <= 0.3:
				continue
			var bv: Basis = tunnel.transform_at(sj).basis
			var rb: Basis = _strand[side_i][j].get("basis", bv)
			# câble sur la corde (écart latéral nul), à sa hauteur de chaînette
			var c0: Vector3 = p_att.lerp(p_r1, xj / d) + bv.y * chainette_y(xj, d, CULOT_DY, a) \
				- (_strand[side_i][j].p as Vector3)
			var g: Dictionary = {"x": xj, "c0": c0, "bx": bv.x, "rx": rb.x.normalized(), "ry": rb.y.normalized()}
			if _strand[side_i][j].has("poulie"):
				g["pn"] = _strand[side_i][j].poulie.n
				g["pa"] = _strand[side_i][j].poulie.axe
			gal.append(g)
	# ligne tendue (la plus courte) du culot à R1, à travers le jeu de
	# chaque galet survolé : relaxation — chaque galet se place au plus
	# près de la droite qui joint ses voisins, sans sortir de sa gorge.
	# Solution unique, qui varie continûment quand la rame avance (un
	# algorithme glouton laissait des appuis inutiles, et le câble sautait
	# de 3 cm de côté quand R1 changeait).
	var gx: Array = [0.0]
	var gl: Array = [0.0]
	for c in gal:
		gx.append(float(c.x))
		gl.append(_dans_gorge(c, 0.0, _centre_gorge(c)))
	gx.append(d)
	gl.append(0.0)
	for _it in range(60):
		var ecart: float = 0.0
		for i in range(1, gx.size() - 1):
			var u: float = (float(gx[i]) - float(gx[i - 1])) / maxf(float(gx[i + 1]) - float(gx[i - 1]), 1e-6)
			var c: Dictionary = gal[i - 1]
			var v: float = _dans_gorge(c, lerpf(float(gl[i - 1]), float(gl[i + 1]), u), _centre_gorge(c))
			ecart = maxf(ecart, absf(v - float(gl[i])))
			gl[i] = v
		if ecart < 1e-6:
			break
	# anneaux réguliers, plus un à chaque appui latéral (sinon le tube
	# couperait les angles de la ligne brisée, à travers la joue)
	var xs: Array = []
	for i in range(n + 1):
		xs.append(d * float(i) / float(n))
	for i in range(1, gx.size() - 1):
		var i_ins: int = xs.bsearch(float(gx[i]))
		if absf(float(xs[i_ins]) - float(gx[i])) > 1e-3 and absf(float(xs[i_ins - 1]) - float(gx[i])) > 1e-3:
			xs.insert(i_ins, float(gx[i]))
	var lats: Array = []
	var ys: Array = []
	for x in xs:
		lats.append(_ligne_brisee(gx, gl, x))
		ys.append(chainette_y(x, d, CULOT_DY, a))
	return {"att": att, "s1": s1, "a": a, "x": xs, "lat": lats, "y": ys, "p_att": p_att, "p_r1": p_r1}


## Écart latéral (le long de la voie) qui met le câble au centre de la
## gorge du galet c (amorce_profil).
static func _centre_gorge(c: Dictionary) -> float:
	return -(c.c0 as Vector3).dot(c.rx) / maxf((c.bx as Vector3).dot(c.rx), 1e-3)


## Pénétration (m) du câble, décalé de dp de sa place sur le galet j,
## dans la gorge de ce galet ou dans sa poulie de déviation : > 0 = il
## traverse une joue ou la jante. marge_h : marge sur la hauteur (le jeu
## croît en √h au décollage).
func penetration_galet(side_i: int, j: int, dp: Vector3, marge_h: float = 0.0) -> float:
	var v: Dictionary = _strand[side_i][j]
	var rb: Basis = v.get("basis", tunnel.transform_at(v.s).basis)
	var c: Dictionary = {"c0": dp, "bx": Vector3.ZERO, "rx": rb.x.normalized(), "ry": rb.y.normalized()}
	if v.has("poulie"):
		c["pn"] = v.poulie.n
		c["pa"] = v.poulie.axe
	return _penetration(c, 0.0, marge_h)


## Pénétration du câble dans le galet c (amorce_profil) pour l'écart
## latéral l : joues de la gorge (dans le repère du galet), et jante de la
## poulie de déviation s'il y en a une. En coupe, la jante (épaisseur
## sheave_thickness) est contre le flanc du câble, côté intérieur du
## coude : le câble ne peut aller vers elle (a > 0, le long de n) que
## soulevé au-delà de son arête, qu'il franchit sur un chanfrein de pente
## POULIE_CHANFREIN. Une arête vive le faisait sauter de 3,6 cm vers
## l'intérieur en passant par-dessus ; il faut une pente bien inférieure à
## cotan 30° = 1,73 (poulie inclinée de 30°) : la position reste alors
## unique et suit la levée sans à-coup (1,5 cm d'écart par cm de levée à
## 0,5 ; 15,5 cm par cm à 1,5 : audit_physique/decollage_galet.sage).
const POULIE_CHANFREIN: float = 0.5
func _penetration(c: Dictionary, l: float, marge_h: float = 0.0) -> float:
	var dp: Vector3 = (c.c0 as Vector3) + (c.bx as Vector3) * l
	var p: float = absf(dp.dot(c.rx)) - jeu_gorge(dp.dot(c.ry) + marge_h)
	if c.has("pn"):
		var a: float = dp.dot(c.pn)
		var b: float = absf(dp.dot(c.pa)) - sheave_thickness * 0.5
		p = maxf(p, a - POULIE_CHANFREIN * maxf(b, 0.0))
	return p


## L'écart l le plus proche de l_voulu qui garde le câble dans la gorge
## du galet c et hors de sa poulie de déviation ; l_centre l'y met au
## centre (câble à sa place, soulevé : toujours libre). Les contraintes
## laissent un intervalle (joues : √ concave ; jante : chanfrein moins
## pentu que la poulie) : dichotomie entre le centre et la cible.
func _dans_gorge(c: Dictionary, l_voulu: float, l_centre: float) -> float:
	if _penetration(c, l_voulu) <= 0.0:
		return l_voulu
	var lo: float = l_centre       # dedans
	var hi: float = l_voulu        # dehors
	for _i in range(28):
		var m: float = 0.5 * (lo + hi)
		if _penetration(c, m) <= 0.0:
			lo = m
		else:
			hi = m
	return lo


static func _ligne_brisee(gx: Array, gl: Array, x: float) -> float:
	var g: int = clampi(gx.bsearch(x) - 1, 0, gx.size() - 2)
	var u: float = clampf((x - float(gx[g])) / maxf(float(gx[g + 1]) - float(gx[g]), 1e-6), 0.0, 1.0)
	return lerpf(float(gl[g]), float(gl[g + 1]), u)


## Jeu latéral (m, de part et d'autre du centre de la gorge) du câble qui
## survole un galet, son dessous à h au-dessus du fond de la gorge
## (hauteur_sur_galet), d'après le profil du galet (RollerMesh) :
##   - fond de gorge creusé de 6 mm sur ±3,2 cm (parabole) : à peine
##     décollé, le câble y reste centré — e = 3,2 cm·√(h / 6 mm). Le jeu
##     part de zéro : au décollage de R1, le câble ne saute pas de côté ;
##   - flancs des joues évasés (de la bande, ±5 cm, jusqu'aux lèvres,
##     ±10 cm et 6,4 cm plus haut) : contact du câble (rayon r) sur le flanc
##     de pente k, e = B/2 + (r + h − épaulement − r·√(1 + k²)) / k, soit
##     3,3 cm + 0,78·h ;
##   - au-delà des lèvres (h > 7 cm), il passe par-dessus : le jeu s'ouvre
##     vite, sans saut (pressé contre le flanc, le câble y remonte).
const GORGE_DEMI: float = 0.032     # RollerMesh._profil_bande
func jeu_gorge(h: float) -> float:
	h = maxf(h, 0.0)
	var k: float = (RollerMesh.R_JOUE - RollerMesh.R_BANDE - RollerMesh.EPAULE) \
		/ ((RollerMesh.LARGEUR - RollerMesh.BANDE) * 0.5)
	var flanc: float = RollerMesh.BANDE * 0.5 + (cable_radius + h - RollerMesh.EPAULE
		- cable_radius * sqrt(1.0 + k * k)) / k
	var fond: float = GORGE_DEMI * sqrt(h / RollerMesh.EPAULE)
	return minf(fond, flanc) + maxf(h - Y_HORS_GORGE, 0.0) * 8.0


## Chaînette entre deux appuis de hauteurs différentes : hauteur y(x) au-
## dessus de la corde, de (0, h) à (D, 0), paramètre a (forme exacte en
## cosh, sommet en x_m).
static func chainette_y(x: float, d: float, h: float, a: float) -> float:
	var sh: float = sinh(d / (2.0 * a))
	var x_m: float = d * 0.5 + a * asinh(h / (2.0 * a * maxf(sh, 1e-9)))
	return a * (cosh((x - x_m) / a) - cosh(x_m / a)) + h


static func attache_s(s_rame: float) -> float:
	return minf(s_rame + ATTACHE_DS, PNConstants.LENGTH - 0.5)


## Abscisse où le câble se pose sur les galets : le premier galet touché
## (premier_appui). En deçà, il est en l'air (tronçon libre dessiné par
## _update_culots) et ne touche pas les galets qu'il survole.
func coupe_brin(side_i: int, s_rame: float) -> float:
	var att: float = attache_s(s_rame)
	var k: int = premier_appui(side_i, att, chainette(att).x)
	if k < 0:
		return PNConstants.LENGTH - 0.3
	return float(_strand[side_i][k].s)


func _build_culots() -> void:
	var mats: Dictionary = RollerMesh.materiaux()
	var culot_mesh: ArrayMesh = RollerMesh.build_culot()
	var tirant: BoxMesh = BoxMesh.new()
	tirant.size = Vector3(0.05, 1.0, 0.02)
	tirant.material = mats["culot"]
	for side_i in [-1, 1]:
		var d: Dictionary = {}
		# tronçon libre : même shader que le câble (toronnage continu),
		# matériau à part (pas de coupe), maillage refait à chaque image
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = load("res://scripts/cable_shader.gdshader")
		mat.set_shader_parameter("cut_below_s", -1.0e6)
		d["mat"] = mat
		for nom in ["culot", "tirant", "amorce"]:
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.name = "Culot%s_%s" % ["G" if side_i < 0 else "D", nom]
			mi.mesh = {"culot": culot_mesh, "tirant": tirant, "amorce": ImmediateMesh.new()}[nom]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			d[nom] = mi
		_culots[side_i] = d


const CULOT_PORTEE: float = 250.0   # m de la caméra au-delà desquels un culot n'est pas redessiné
var _s_cam_culots: float = NAN      # abscisse de la caméra (update_galets_rames)


func _update_culots(s_rame_g: float, s_rame_d: float) -> void:
	if _culots.is_empty():
		_build_culots()
	var y_cable: float = _roller_axis_y() + pulley_radius + cable_radius
	for side_i in [-1, 1]:
		var s_r: float = s_rame_g if side_i < 0 else s_rame_d
		var d: Dictionary = _culots[side_i]
		# culot de l'autre rame loin de la caméra (moins d'un pixel) : on ne
		# refait pas son tronçon libre (0,5 ms par image et par brin)
		var loin: bool = not is_nan(_s_cam_culots) \
			and absf(attache_s(s_r) - _s_cam_culots) > CULOT_PORTEE
		for nom in ["culot", "tirant", "amorce"]:
			(d[nom] as MeshInstance3D).visible = not loin
		if loin:
			continue
		var prof: Dictionary = amorce_profil(side_i, s_r)
		var att: float = prof.att
		var x0: float = maxf(float(prof.s1) - att, 0.5)
		var p_r1: Vector3 = prof.p_r1
		var p_att: Vector3 = prof.p_att
		var own: ShaderMaterial = cable_right_material if side_i > 0 else cable_left_material
		var mat: ShaderMaterial = d["mat"]
		if own != null:
			mat.set_shader_parameter("cable_phase", own.get_shader_parameter("cable_phase"))
		# points : corde culot → R1, écart latéral (guidage par les gorges),
		# hauteur de la chaînette
		var pts: Array = []
		var xs: Array = []
		for i in range((prof.x as Array).size()):
			var x: float = prof.x[i]
			var s_x: float = att + x
			var bx: Basis = tunnel.transform_at(s_x).basis
			var p: Vector3 = p_att.lerp(p_r1, x / x0) + bx.x * float(prof.lat[i]) + bx.y * float(prof.y[i])
			if _slack > 0.0 and not _rupture.is_empty():
				p -= bx.y * (_slack_drop(side_i, s_x) * _slack)
			pts.append(p)
			xs.append(x)
		var xf: Transform3D = tunnel.transform_at(att)
		var up: Vector3 = xf.basis.y
		var pos: Vector3 = pts[0]
		# culot dans l'axe du câble (tangente de la chaînette à son bout)
		var dirv: Vector3 = ((pts[1] as Vector3) - pos).normalized()
		var z: Vector3 = -dirv
		var xb: Vector3 = up.cross(z).normalized()
		var yb: Vector3 = z.cross(xb).normalized()
		(d.culot as MeshInstance3D).transform = Transform3D(Basis(xb, yb, z), pos)
		# chape d'attelage : de l'axe de la chape au fond de la caisse
		var p_chape: Vector3 = pos - z * 0.085
		var h: float = maxf(CAISSE_Y - (y_cable + CULOT_DY), 0.02)
		(d.tirant as MeshInstance3D).transform = Transform3D(
			Basis(xb, up, xb.cross(up).normalized()) * Basis.from_scale(Vector3(1.0, h, 1.0)),
			p_chape + up * (h * 0.5))
		# tronçon libre : de la pointe du culot au décollage
		var pointe_x: float = CULOT_LONG * 0.95
		var debut: int = 0
		while debut < xs.size() - 2 and float(xs[debut + 1]) < pointe_x:
			debut += 1
		pts[debut] = pos + dirv * pointe_x
		xs[debut] = pointe_x
		_tube_amorce(d.amorce as MeshInstance3D, mat, pts.slice(debut), xs.slice(debut), att)


## Tube du tronçon libre (ImmediateMesh refait à chaque image) : UV comme
## les tronçons du câble (UV.x autour, UV.y = 2 × abscisse) pour que les
## torons défilent sans raccord au décollage.
func _tube_amorce(mi: MeshInstance3D, mat: Material, pts: Array, xs: Array, att: float) -> void:
	var im: ImmediateMesh = mi.mesh
	im.clear_surfaces()
	if pts.size() < 2:
		return
	var ns: int = cable_segments
	var anneaux: Array = []
	for i in range(pts.size()):
		var p0: Vector3 = pts[maxi(i - 1, 0)]
		var p1: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var t: Vector3 = (p1 - p0).normalized()
		# même repère que les anneaux du câble posé (_build_cable_segment) :
		# angle compté de la DROITE de la voie vers le haut. Compté de la
		# gauche, l'hélice des torons tournait à l'envers et faisait une
		# couture au premier galet (retour du 06/10/2026).
		var bv: Basis = tunnel.transform_at(att + float(xs[i])).basis
		var bx: Vector3 = (bv.x - t * bv.x.dot(t)).normalized()
		var by: Vector3 = bv.y - t * bv.y.dot(t)
		by = (by - bx * by.dot(bx)).normalized()
		var anneau: Array = []
		for j in range(ns + 1):
			var ph: float = TAU * float(j) / float(ns)
			var n: Vector3 = bx * cos(ph) + by * sin(ph)
			anneau.append([(pts[i] as Vector3) + n * cable_radius, n,
				Vector2(float(j) / float(ns), 2.0 * (att + float(xs[i])))])
		anneaux.append(anneau)
	# faces avant dans le sens horaire (convention Godot) : tous les anneaux
	# ont le même repère (droite de la voie, haut) et la même orientation —
	# le sens se décide une fois, sur le premier triangle
	var t0: Array = [anneaux[0][0], anneaux[1][0], anneaux[1][1]]
	var g: float = ((t0[1][0] as Vector3) - (t0[0][0] as Vector3)).cross(
		(t0[2][0] as Vector3) - (t0[0][0] as Vector3)).dot((t0[0][1] as Vector3) + (t0[1][1] as Vector3) + (t0[2][1] as Vector3))
	var direct: bool = g < 0.0
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for i in range(anneaux.size() - 1):
		var r0: Array = anneaux[i]
		var r1: Array = anneaux[i + 1]
		for j in range(ns):
			var tris: Array = [r0[j], r1[j], r1[j + 1], r0[j], r1[j + 1], r0[j + 1]] if direct \
				else [r0[j], r1[j + 1], r1[j], r0[j], r0[j + 1], r1[j + 1]]
			for v in tris:
				im.surface_set_normal(v[1])
				im.surface_set_uv(v[2])
				im.surface_add_vertex(v[0])
	im.surface_end()


## Galets : abscisses des rames → culots de chaque brin, caméra, pas de
## temps ; câble rompu = le brin de la rame pilotée ne porte plus.
func update_galets_rames(s_driver: float, s_other: float, s_cam: float,
		delta: float, rupture: bool = false) -> void:
	if s_other < 0.0:
		s_other = PNConstants.miroir(s_driver)
	var s_g: float = s_other if driver_is_rame2 else s_driver
	var s_d: float = s_driver if driver_is_rame2 else s_other
	_s_cam_culots = s_cam
	var rompu: int = 0
	if rupture:
		rompu = 1 if driver_is_rame2 else -1
	update_galets(attache_s(s_g), attache_s(s_d), s_cam, delta, rompu,
		coupe_brin(-1, s_g) - 1e-3, coupe_brin(1, s_d) - 1e-3)


# ---------------------------------------------------------------------------
# Rupture du câble (retour du 01/10/2026 : « quand le câble casse, il doit se
# détendre, casser quelque part »). La rupture a lieu sur le brin de la rame
# pilotée — c'est elle que la physique découple et laisse dévaler — entre
# elle et la salle des machines, en vue du conducteur quand il monte (25 à
# 60 m au-delà de l'endroit où son élan l'arrêtera), juste derrière lui
# quand il descend (20 à 50 m, visible en vue extérieure). Au moment de la
# rupture :
#   - les deux bouts se rétractent de leur allongement élastique T·L/(EA)
#     (le haut vers la salle des machines, le bas vers sa rame) ;
#   - toute la longueur se détend et retombe des galets sur la longrine
#     (chute libre de ~16 cm, cf. audit_physique/rupture_cable.sage) ;
#   - le bout bas est accroché à sa rame et la suit dans les deux sens ;
#     le bout haut reste sur les roues, immobiles (TrainPhysics.
#     update_machine) — et le câble de la salle des machines se détend lui
#     aussi (MachineRoomBuilder.set_cable_slack).
# ---------------------------------------------------------------------------

const RUPTURE_T_MIN_N: float = 50000.0   # tension retenue si la jauge est basse
const RUPTURE_FALL_S: float = 0.18       # s, chute du câble sur la longrine
const RUPTURE_GAP_MIN_M: float = 0.6     # écart mini entre les bouts poussés
var _rupture: Dictionary = {}            # vide = câble intact
var _last_tension_dan: float = 0.0


func update_cable_rupture(rupture: bool, s_driver: float, direction: int,
		tension_dan: float, delta: float, v_driver: float = 0.0) -> void:
	if cable_left_material == null or cable_right_material == null:
		return
	if not rupture:
		_last_tension_dan = tension_dan   # tension juste AVANT la rupture
		if not _rupture.is_empty():
			_rupture = {}
			for m in [cable_left_material, cable_right_material]:
				(m as ShaderMaterial).set_shader_parameter("slack", 0.0)
				(m as ShaderMaterial).set_shader_parameter("gap_lo", -1.0)
				(m as ShaderMaterial).set_shader_parameter("gap_hi", -1.0)
		return
	var own: ShaderMaterial = cable_right_material if driver_is_rame2 else cable_left_material
	if _rupture.is_empty():
		var ecart: float = randf_range(25.0, 80.0) if direction > 0 \
			else randf_range(20.0, 50.0)
		var s_b: float = minf(s_driver + ecart, PNConstants.LENGTH - 15.0)
		s_b = maxf(s_b, s_driver + 1.0)
		var t_n: float = maxf(maxf(tension_dan, _last_tension_dan) * 10.0, RUPTURE_T_MIN_N)
		_rupture = {
			"t": 0.0, "s_b": s_b, "s0": s_driver, "ph0": s_driver,
			"r_up": minf(t_n * (PNConstants.LENGTH - s_b) / TrainPhysics.CABLE_EA_N, 8.0),
			"r_lo": minf(t_n * (s_b - s_driver) / TrainPhysics.CABLE_EA_N, 2.0),
		}
		print("[Câble] rupture à s = %.1f m (rame à %.1f m), rétraction %.2f m / %.2f m" % [
			s_b, s_driver, _rupture.r_up, _rupture.r_lo])
	_rupture.t = float(_rupture.t) + delta
	var t: float = _rupture.t
	# Chaque bout recule à vitesse constante u = ε·c (onde de détente,
	# c = √(EA/ρ) ≈ 3 400 m/s) jusqu'à avoir rendu tout son allongement
	# ε·L : la durée vaut L/c, le temps que l'onde parcoure le tronçon.
	var c_onde: float = sqrt(TrainPhysics.CABLE_EA_N / PNConstants.CABLE_KG_M)
	var l_up: float = maxf(PNConstants.LENGTH - float(_rupture.s_b), 1.0)
	var l_lo: float = maxf(float(_rupture.s_b) - float(_rupture.s0), 1.0)
	var k_up: float = minf(1.0, c_onde * t / l_up)
	var k_lo: float = minf(1.0, c_onde * t / l_lo)
	var chute: float = clampf(t / RUPTURE_FALL_S, 0.0, 1.0)
	var hi: float = float(_rupture.s_b) + float(_rupture.r_up) * k_up
	# Le tronçon bas est accroché à sa rame : il la suit dans les deux sens
	# (retour du 01/10 : « le bout cassé attaché à la rame emballée devrait
	# avancer avec elle »), glissant sur les galets. Poussé par une rame qui
	# file encore sur son élan, il bute sur le bout haut au bout de quelques
	# mètres (le reste s'entasserait devant la rame) : arrêt à
	# RUPTURE_GAP_MIN_M, les deux bouts à vif restent visibles, et la brèche
	# se rouvre dès que la rame repart en arrière.
	var lo: float = float(_rupture.s_b) - float(_rupture.r_lo) * k_lo \
		+ (s_driver - float(_rupture.s0))
	lo = minf(maxf(lo, s_driver), hi - RUPTURE_GAP_MIN_M)
	own.set_shader_parameter("gap_lo", lo)
	own.set_shader_parameter("gap_hi", hi)
	own.set_shader_parameter("phase_upper", float(_rupture.ph0) + float(_rupture.r_up) * k_up)
	_slack = chute * chute
	for m in [cable_left_material, cable_right_material]:
		(m as ShaderMaterial).set_shader_parameter("slack", _slack)


var _slack: float = 0.0


## État de la rupture pour les bancs : {} si le câble est intact.
func cable_rupture_state() -> Dictionary:
	return _rupture


## Détente du câble (0 tendu → 1 retombé) : la salle des machines suit.
func cable_slack() -> float:
	return _slack if not _rupture.is_empty() else 0.0
