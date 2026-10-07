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
const PIT_LOW_END: float = 43.0       # toute la longueur des quais (TrackBuilder.pit_low_end)
const PIT_HIGH_START: float = PNConstants.LENGTH - 2.0
const PIT_HIGH_END: float = PNConstants.LENGTH + 4.0
# fond à 2,31 m sous le champignon des rails : un adulte passe sous les
# longrines qui portent les rails (Kevin, 07/10/2026 : « la fosse doit être
# plus profonde pour que la tête soit sous les rails »)
const PIT_DEPTH: float = 1.95


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
	# Le train occupe s ∈ [6,56, 38,56] (centre à START_S = 22,56) : arrière
	# à 4,5 m de la tête du butoir (PNConstants.BUTOIR_BAS_S = 2,0 − 0,10 +
	# 0,16 : socle à 2,0, tête de 0,32 centrée à 0,10 côté ligne).
	var s_bumper: float = 2.0
	var s_plat_start: float = PNConstants.QUAI_BAS_DEBUT_S
	var s_plat_end: float = PNConstants.QUAI_BAS_FIN_S

	# 2 quais : un de chaque côté de la voie pour symétrie (une cabine peut
	# ouvrir ses portes des 2 côtés, ou 2 cabines successives utilisent l'un
	# ou l'autre selon le sens d'arrivée).
	_build_platform(s_plat_start, s_plat_end, true, +1.0)
	_build_platform(s_plat_start, s_plat_end, true, -1.0)
	# palier de plain-pied entre les portes de la salle d'attente (s = 0)
	# et la première marche du quai : on y passait dans le vide (skieur
	# jouable, 07/10/2026)
	for sd0 in [-1.0, 1.0]:
		_build_palier(0.0, s_plat_start, sd0)
	# le garde-corps descend jusqu'au point le plus bas du nez : rame
	# pleine, câble allongé (retour du 06/10/2026 : « la barrière doit
	# descendre jusqu'au point bas de l'allongement du câble cabine pleine »)
	var nez_bas: float = PNConstants.START_S + PNConstants.TRAIN_HALF \
		- TrainPhysics.recul_embarquement_max(PNConstants.START_S)
	for sd in [-1.0, 1.0]:
		_build_platform_barrier(s_plat_start, s_plat_end, nez_bas, sd, true)
	# Fosse sous la voie et le nez de la rame (photos 093522 / 094104) :
	# caillebotis en fond, chaînes, et butoirs bleus à tête bois
	_build_pit(PIT_LOW_START, PIT_LOW_END, false)
	_build_bumper(s_bumper, true)
	_build_room_dressing(1.0, tunnel.station_low_end - tunnel.station_room_transition, true)
	_build_ceiling_lights(s_plat_start, s_plat_end)


# ---------------------------------------------------------------------------
# Grande Motte : portail haut, s ∈ [3434, 3474]
# ---------------------------------------------------------------------------

func _build_station_high() -> void:
	# collé contre la fin du tunnel ; tête à PNConstants.BUTOIR_HAUT_S,
	# nez de la rame arrêtée à 1,5 m
	var s_bumper: float = PNConstants.LENGTH - 0.4
	# les marches commencent au mur aval de la salle (bouche du tunnel)
	var s_plat_start: float = maxf(PNConstants.QUAI_HAUT_DEBUT_S,
		tunnel.station_high_start + tunnel.station_room_transition_haut + 0.05)
	# La sortie est vers le HAUT (Kevin, 06/10/2026) : les marches du quai
	# se prolongent dans le hall de la salle des machines jusqu'à un palier
	# plat, de chaque côté de la fosse, devant les baies vitrées et les
	# portes coulissantes du mur du fond (MachineRoomBuilder). Le garde-corps
	# ne ferme plus le quai : il le longe depuis un peu sous le nez de la
	# rame arrêtée (pas de vide entre la rame et la barrière) et continue le
	# long du palier jusqu'au mur, pour qu'on ne tombe pas dans la fosse.
	var s_palier: float = PNConstants.LENGTH + MachineRoomBuilder.PALIER_S0
	var s_fond: float = PNConstants.LENGTH + MachineRoomBuilder.HALL_DEPTH
	var s_debut_barriere: float = PNConstants.STOP_S + PNConstants.TRAIN_HALF - 1.0
	for sd in [-1.0, 1.0]:
		_build_platform(s_plat_start, s_palier, false, sd)
		_build_palier(s_palier, s_fond, sd)
		_build_platform_barrier(s_plat_start, s_palier, s_debut_barriere, sd, false, s_fond - 0.08)
	# Pas de fosse en haut (retour d'essai 2026-09-26) : butoirs bleus seuls
	_build_bumper(s_bumper, false)
	_build_room_dressing(tunnel.station_high_start + tunnel.station_room_transition_haut,
		PNConstants.LENGTH - 0.3, false)
	_build_ceiling_lights(s_plat_start, PNConstants.QUAI_HAUT_FIN_S)


## Palier plat en haut des marches (dessus = dessus de la dernière marche),
## jusqu'au mur du fond du hall.
func _build_palier(s0: float, s1: float, side: float) -> void:
	var y_quai: float = FLOOR_Y_LOCAL + platform_height
	var xf0: Transform3D = _xf_at(s0)
	var y_top: float = (xf0.origin + xf0.basis.y * y_quai).y
	var xm: Transform3D = _xf_at((s0 + s1) * 0.5)
	var dr: Vector3 = xm.basis.x
	var lb: Basis = Basis(dr, Vector3.UP, dr.cross(Vector3.UP)).orthonormalized()
	var lat: float = side * (platform_inner_x + platform_width * 0.5)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.13, 0.14)
	mat.roughness = 0.9
	mat.metallic = 0.15
	var nez: StandardMaterial3D = StandardMaterial3D.new()
	nez.albedo_color = Color(0.78, 0.79, 0.82)
	nez.roughness = 0.35
	nez.metallic = 0.85
	var c: Vector3 = xm.origin + dr * lat
	c.y = y_top - tread_thickness * 0.5
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(platform_width, tread_thickness, s1 - s0)
	bm.material = mat
	mi.mesh = bm
	mi.name = "Palier_%s" % ("R" if side > 0.0 else "L")
	mi.transform = Transform3D(lb, c)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var xn: Transform3D = _xf_at(s0 + 0.06)
	var cn: Vector3 = xn.origin + xn.basis.x * lat
	cn.y = y_top - 0.017
	var mn: MeshInstance3D = MeshInstance3D.new()
	var bn: BoxMesh = BoxMesh.new()
	bn.size = Vector3(platform_width, 0.035, 0.11)
	bn.material = nez
	mn.mesh = bn
	mn.transform = Transform3D(lb, cn)
	mn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mn)


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

	# Marches en CAILLEBOTIS NOIR antidérapant (photos 095433 / 095511 :
	# le dessus des paliers est sombre), nez en tôle damier alu ; en gare
	# haute une BANDE ROUGE court derrière le nez (photo 095438).
	var tread_mat: StandardMaterial3D = StandardMaterial3D.new()
	tread_mat.albedo_color = Color(0.13, 0.13, 0.14)
	tread_mat.roughness = 0.9
	tread_mat.metallic = 0.15

	var nose_mat: StandardMaterial3D = StandardMaterial3D.new()
	nose_mat.albedo_color = Color(0.78, 0.79, 0.82)
	nose_mat.roughness = 0.35
	nose_mat.metallic = 0.85
	var band_mat: StandardMaterial3D = StandardMaterial3D.new()
	band_mat.albedo_color = Color(0.62, 0.12, 0.10)
	band_mat.roughness = 0.7

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
	var band_mesh: BoxMesh = BoxMesh.new()
	band_mesh.size = Vector3(platform_width, 0.012, 0.26)
	band_mesh.material = band_mat
	var mm_bands: MultiMesh = MultiMesh.new()
	mm_bands.transform_format = MultiMesh.TRANSFORM_3D
	mm_bands.mesh = band_mesh
	mm_bands.instance_count = n_treads if not is_low else 0

	var xf_marches: Array = []       # pour les collisions (CollisionsJeu)
	for i in range(n_treads):
		var s_dn: float = s_start + float(i) * tread_depth          # bord aval
		var s_up: float = minf(s_dn + tread_depth, s_end)           # bord amont
		var s_mid: float = (s_dn + s_up) * 0.5
		var xf_up: Transform3D = _xf_at(s_up)
		var xf_mid: Transform3D = _xf_at(s_mid)
		# Élévation MONDE du dessus de marche = niveau du quai au bord amont
		var top_y: float = (xf_up.origin + xf_up.basis.y * y_top_local).y
		# Base nivelée : right local (déjà horizontal), up = UP monde
		var right_h: Vector3 = xf_mid.basis.x
		var level_basis: Basis = Basis(
			right_h, Vector3.UP, right_h.cross(Vector3.UP)).orthonormalized()
		var center: Vector3 = xf_mid.origin + xf_mid.basis.x * lat_center
		center.y = top_y - tread_thickness * 0.5
		mm_treads.set_instance_transform(i, Transform3D(level_basis, center))
		xf_marches.append(Transform3D(level_basis, center))
		# Nez : au bord AVAL de la marche, affleurant le dessus
		var xf_dn: Transform3D = _xf_at(s_dn + 0.06)
		var nose_c: Vector3 = xf_dn.origin + xf_dn.basis.x * lat_center
		nose_c.y = top_y - 0.017
		mm_noses.set_instance_transform(i, Transform3D(level_basis, nose_c))
		if not is_low:
			var xf_bd: Transform3D = _xf_at(s_dn + 0.25)
			var band_c: Vector3 = xf_bd.origin + xf_bd.basis.x * lat_center
			band_c.y = top_y - 0.004
			mm_bands.set_instance_transform(i, Transform3D(level_basis, band_c))

	var mi_treads: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mi_treads.name = "PlatformSteps_%s_%s" % [sta, side_name]
	mi_treads.multimesh = mm_treads
	mi_treads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi_treads.set_meta("instances", xf_marches)
	add_child(mi_treads)

	var mi_noses: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mi_noses.name = "PlatformNoses_%s_%s" % [sta, side_name]
	mi_noses.multimesh = mm_noses
	mi_noses.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi_noses)
	if not is_low:
		var mi_bands: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mi_bands.name = "PlatformBands_%s_%s" % [sta, side_name]
		mi_bands.multimesh = mm_bands
		mi_bands.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi_bands)



## Garde-corps du haut de quai (faits de Kevin, 06/10/2026, vidéo
## d'arrivée en gare haute et photos 095443 / 095511) : en haut de la rame,
## dans les deux gares, une barrière longe la voie depuis le nez de la rame
## arrêtée. En BAS elle tourne ensuite à angle droit pour fermer le quai,
## avec une porte réservée au personnel ; en HAUT la sortie est vers le haut,
## elle continue le long du palier jusqu'au mur du fond. Structure en TUBE
## ROND BLEU, angles arrondis (tube cintré) : main courante d'un seul tenant
## qui descend en coude dans les montants d'extrémité, montants
## intermédiaires verticaux, lisses parallèles à la pente.
const BARRIERE_H: float = 1.05          # main courante au-dessus du quai
const BARRIERE_LISSES: Array = [0.38, 0.70]
const BARRIERE_PAS: float = 1.25        # entre montants
const PORTE_LARGEUR: float = 0.90
const BARRIERE_R: float = 0.024         # tube ∅ 48,3 (main courante, montants)
const BARRIERE_R_LISSE: float = 0.017   # tube ∅ 33,7 (lisses)
const BARRIERE_COUDE: float = 0.16      # rayon de cintrage des angles


func _build_platform_barrier(s_start: float, s_end: float, s_nez: float, side: float,
		is_low: bool, s_fin: float = -1.0) -> void:
	var bleu: StandardMaterial3D = StandardMaterial3D.new()
	bleu.albedo_color = Color(0.10, 0.30, 0.64)
	bleu.roughness = 0.4
	bleu.metallic = 0.35
	bleu.cull_mode = BaseMaterial3D.CULL_DISABLED
	var galva: StandardMaterial3D = StandardMaterial3D.new()
	galva.albedo_color = Color(0.72, 0.74, 0.76)
	galva.roughness = 0.4
	galva.metallic = 0.8
	var nom: String = "Barriere_%s_%s" % ["low" if is_low else "high", "R" if side > 0.0 else "L"]
	var racine: Node3D = Node3D.new()
	racine.name = nom
	add_child(racine)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y_quai: float = FLOOR_Y_LOCAL + platform_height
	var x_voie: float = side * (platform_inner_x + 0.06)
	var x_mur: float = side * (platform_inner_x + platform_width - 0.05)
	# en haut : la barrière continue à plat sur le palier jusqu'à s_fin
	var palier: bool = s_fin > s_end
	var s_a: float = clampf(s_nez, s_start, s_end - 0.2)
	var s_b: float = s_fin if palier else s_end - 0.04
	var xf_e: Transform3D = _xf_at(s_end)
	var y_palier: float = (xf_e.origin + xf_e.basis.y * y_quai).y
	# dessus de la marche qui contient s (élévation MONDE, cf. _build_platform)
	var dessus := func(s_: float) -> float:
		if palier and s_ >= s_end:
			return y_palier
		var i: int = clampi(int(floor((s_ - s_start) / tread_depth)), 0, 100000)
		var s_up: float = minf(s_start + float(i + 1) * tread_depth, s_end)
		var xf_up: Transform3D = _xf_at(s_up)
		return (xf_up.origin + xf_up.basis.y * y_quai).y
	# point à la hauteur h au-dessus de la ligne des marches (ou du palier)
	var pt := func(s_: float, x_: float, h_: float) -> Vector3:
		var xf: Transform3D = _xf_at(s_)
		if palier and s_ >= s_end:
			var q: Vector3 = xf.origin + xf.basis.x * x_
			q.y = y_palier + h_
			return q
		return xf.origin + xf.basis.x * x_ + xf.basis.y * (y_quai + h_)
	var pied := func(s_: float, x_: float) -> Vector3:
		var xf: Transform3D = _xf_at(s_)
		var q: Vector3 = xf.origin + xf.basis.x * x_
		q.y = dessus.call(s_)
		return q
	# abscisses du tracé le long de la voie (tous les ~2 m, + la cassure
	# marches → palier)
	var ss: Array = []
	var n_s: int = maxi(1, int(ceil((s_b - s_a) / 2.0)))
	for i in range(n_s + 1):
		ss.append(lerpf(s_a, s_b, float(i) / float(n_s)))
	if palier and s_end > s_a + 0.3 and s_end < s_b - 0.3:
		ss.append(s_end)
		ss.sort()

	# en bas : retour en travers du haut du quai, porte au milieu
	var xf_b: Transform3D = _xf_at(s_b)
	var dr_b: Vector3 = xf_b.basis.x
	var pied_b: float = dessus.call(s_b - 0.1)
	var x_porte0: float = (x_voie + x_mur) * 0.5 - side * PORTE_LARGEUR * 0.5
	var x_porte1: float = x_porte0 + side * PORTE_LARGEUR
	var travers := func(x_: float, h_: float) -> Vector3:
		var q: Vector3 = xf_b.origin + dr_b * x_
		q.y = pied_b + h_
		return q

	# 1. main courante d'un seul tenant : montant de départ, le long de la
	#    voie, puis (bas) le retour jusqu'à la porte, ou (haut) le montant
	#    final contre le mur du fond — tous les angles cintrés
	var main: Array = [pied.call(s_a, x_voie)]
	for s_ in ss:
		main.append(pt.call(s_, x_voie, BARRIERE_H))
	if is_low:
		main.append(travers.call(x_porte0, BARRIERE_H))
		main.append(travers.call(x_porte0, 0.0))
	else:
		main.append(pied.call(s_b, x_voie))
	_tube(st, main, BARRIERE_R, BARRIERE_COUDE)
	# lisses
	for h in BARRIERE_LISSES:
		var l: Array = []
		for s_ in ss:
			l.append(pt.call(s_, x_voie, h))
		if is_low:
			l.append(travers.call(x_porte0, h))
		_tube(st, l, BARRIERE_R_LISSE, BARRIERE_COUDE)
	# montants intermédiaires
	var n_m: int = maxi(1, int(ceil((s_b - s_a) / BARRIERE_PAS)))
	for i in range(1, n_m):
		var s_m: float = lerpf(s_a, s_b, float(i) / float(n_m))
		_tube(st, [pied.call(s_m, x_voie), pt.call(s_m, x_voie, BARRIERE_H - BARRIERE_R)], BARRIERE_R, 0.0)

	if is_low:
		# 2. de l'autre côté de la porte jusqu'au mur : cadre en U renversé
		var c2: Array = [travers.call(x_porte1, 0.0), travers.call(x_porte1, BARRIERE_H),
			travers.call(x_mur, BARRIERE_H), travers.call(x_mur, 0.0)]
		_tube(st, c2, BARRIERE_R, BARRIERE_COUDE)
		for h in BARRIERE_LISSES:
			_tube(st, [travers.call(x_porte1, h), travers.call(x_mur, h)], BARRIERE_R_LISSE, 0.0)
		# 3. la porte : cadre en tube cintré, traverse, plaque « réservé
		#    au personnel »
		var xg0: float = x_porte0 + side * 0.06
		var xg1: float = x_porte1 - side * 0.06
		_tube(st, [travers.call(xg0, 0.06), travers.call(xg0, BARRIERE_H - 0.04),
			travers.call(xg1, BARRIERE_H - 0.04), travers.call(xg1, 0.06), travers.call(xg0, 0.06)],
			BARRIERE_R_LISSE, 0.10)
		_tube(st, [travers.call(xg0, 0.52), travers.call(xg1, 0.52)], BARRIERE_R_LISSE, 0.0)
		var lb: Basis = Basis(dr_b, Vector3.UP, dr_b.cross(Vector3.UP)).orthonormalized()
		var cp: Vector3 = xf_b.origin + dr_b * ((x_porte0 + x_porte1) * 0.5)
		var face: Vector3 = xf_b.basis.z      # vers le quai (l'aval)
		var plaque_m: MeshInstance3D = MeshInstance3D.new()
		var pm: BoxMesh = BoxMesh.new()
		pm.size = Vector3(0.36, 0.17, 0.006)
		pm.material = galva
		plaque_m.mesh = pm
		plaque_m.transform = Transform3D(lb, Vector3(cp.x, pied_b + 0.80, cp.z) + face * 0.025)
		plaque_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		racine.add_child(plaque_m)
		var plaque: Label3D = Label3D.new()
		plaque.text = "RÉSERVÉ AU\nPERSONNEL"
		plaque.font_size = 40
		plaque.pixel_size = 0.0028
		plaque.modulate = Color(0.75, 0.08, 0.06)
		plaque.outline_size = 0
		var pb: Basis = Basis(dr_b, Vector3.UP, Vector3.ZERO)
		pb.z = pb.x.cross(Vector3.UP).normalized()
		if pb.z.dot(face) < 0.0:
			pb.x = -pb.x
			pb.z = -pb.z
		plaque.transform = Transform3D(pb.orthonormalized(), Vector3(cp.x, pied_b + 0.80, cp.z) + face * 0.03)
		racine.add_child(plaque)

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Tubes"
	st.set_material(bleu)
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	racine.add_child(mi)


## Arrondit les angles d'une polyligne : chaque sommet intérieur devient un
## arc (Bézier quadratique ≈ cintrage de rayon `coude`), limité à 45 % des
## segments adjacents.
static func _cintrer(pts: Array, coude: float) -> Array:
	var out: Array = [pts[0]]
	for i in range(1, pts.size() - 1):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var c: Vector3 = pts[i + 1]
		var l0: float = a.distance_to(b)
		var l1: float = b.distance_to(c)
		if l0 < 1e-4 or l1 < 1e-4:
			continue
		var d0: Vector3 = (b - a) / l0
		var d1: Vector3 = (c - b) / l1
		var ang: float = acos(clampf(d0.dot(d1), -1.0, 1.0))
		if coude <= 0.0 or ang < deg_to_rad(2.0):
			out.append(b)
			continue
		var tl: float = minf(coude * tan(ang * 0.5), 0.45 * minf(l0, l1))
		var p0: Vector3 = b - d0 * tl
		var p2: Vector3 = b + d1 * tl
		var m: int = maxi(3, int(ceil(ang / deg_to_rad(11.0))))
		for k in range(m + 1):
			var t: float = float(k) / float(m)
			out.append(p0.lerp(b, t).lerp(b.lerp(p2, t), t))
	out.append(pts[pts.size() - 1])
	return out


## Tube rond balayé le long d'une polyligne MONDE (repères transportés
## parallèlement, normales radiales lisses), angles cintrés.
static func _tube(st: SurfaceTool, pts_in: Array, r: float, coude: float, n: int = 10) -> void:
	var pts: Array = _cintrer(pts_in, coude)
	var p: Array = [pts[0]]
	for q in pts:
		if (q as Vector3).distance_to(p[p.size() - 1]) > 0.002:
			p.append(q)
	if p.size() < 2:
		return
	var t0: Vector3 = ((p[1] as Vector3) - (p[0] as Vector3)).normalized()
	var u: Vector3 = (Vector3.UP if absf(t0.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).cross(t0).normalized()
	var reperes: Array = []
	for i in range(p.size()):
		var t: Vector3
		if i == 0:
			t = t0
		elif i == p.size() - 1:
			t = ((p[i] as Vector3) - (p[i - 1] as Vector3)).normalized()
		else:
			t = (((p[i] as Vector3) - (p[i - 1] as Vector3)).normalized()
				+ ((p[i + 1] as Vector3) - (p[i] as Vector3)).normalized()).normalized()
		u = (u - t * u.dot(t)).normalized()
		reperes.append([u, t.cross(u)])
	for i in range(p.size() - 1):
		for k in range(n):
			var a0: float = TAU * float(k) / float(n)
			var a1: float = TAU * float(k + 1) / float(n)
			var n00: Vector3 = reperes[i][0] * cos(a0) + reperes[i][1] * sin(a0)
			var n01: Vector3 = reperes[i][0] * cos(a1) + reperes[i][1] * sin(a1)
			var n10: Vector3 = reperes[i + 1][0] * cos(a0) + reperes[i + 1][1] * sin(a0)
			var n11: Vector3 = reperes[i + 1][0] * cos(a1) + reperes[i + 1][1] * sin(a1)
			for v in [[n00, i], [n10, i + 1], [n11, i + 1], [n00, i], [n11, i + 1], [n01, i]]:
				st.set_normal(v[0])
				st.add_vertex((p[v[1]] as Vector3) + (v[0] as Vector3) * r)
	# bouchons
	for e in [0, p.size() - 1]:
		var c: Vector3 = p[e]
		var nt: Vector3 = reperes[e][0].cross(reperes[e][1]) * (-1.0 if e == 0 else 1.0)
		for k in range(n):
			var a0: float = TAU * float(k) / float(n)
			var a1: float = TAU * float(k + 1) / float(n)
			st.set_normal(nt)
			st.add_vertex(c)
			st.set_normal(nt)
			st.add_vertex(c + (reperes[e][0] * cos(a0) + reperes[e][1] * sin(a0)) * r)
			st.set_normal(nt)
			st.add_vertex(c + (reperes[e][0] * cos(a1) + reperes[e][1] * sin(a1)) * r)


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
	# fosse longue (gare basse) : escalier côté salle, contre la paroi droite,
	# en dehors des butoirs (x 0,70-1,00) ; paroi et rebord coupés à son droit
	var esc_x0: float = 1.055
	var esc_x1: float = 1.805
	var esc_s0: float = 0.6
	var esc_n: int = int(ceil(((FLOOR_Y_LOCAL + platform_height) - y_bottom) / 0.17))
	var esc_giron: float = 0.29
	var esc_s1: float = esc_s0 + esc_giron * esc_n
	var longue: bool = length > 10.0
	for sx in [-1.5, 1.5]:
		var morceaux: Array = [[s0, s1]]
		if longue and sx > 0.0:
			morceaux = [[s0, esc_s0 - 0.05], [esc_s1 + 0.05, s1]]
		for mo in morceaux:
			var lm: float = float(mo[1]) - float(mo[0])
			if lm <= 0.01:
				continue
			var cm_s: float = (float(mo[0]) + float(mo[1])) * 0.5
			_box(Vector3(0.16, PIT_DEPTH, lm), concrete, cm_s, sx, y_bottom + PIT_DEPTH * 0.5, "ParoiFosse")
			_box(Vector3(0.08, 0.06, lm), steel, cm_s, sx - signf(sx) * 0.04, FLOOR_Y_LOCAL + 0.03, "CorniereFosse")
			if longue:
				# rebord jusqu'au quai, de la paroi au bord du quai, au niveau du quai
				_box(Vector3(platform_inner_x - 1.42, (FLOOR_Y_LOCAL + platform_height) - y_bottom, lm),
					concrete, cm_s, signf(sx) * (1.42 + platform_inner_x) * 0.5,
					(y_bottom + FLOOR_Y_LOCAL + platform_height) * 0.5, "RebordFosse")
	# rails sur poutres au-dessus de la fosse : deux longrines acier,
	# portées par des poteaux tous les 2,5 m
	for sx in [-0.60, 0.60]:
		_box(Vector3(0.12, 0.22, length), iron, sc, sx, RAIL_HEAD_Y - 0.28, "LongrineFosse")
	if length > 10.0:
		var h_pot: float = (RAIL_HEAD_Y - 0.39) - y_bottom
		var sp: float = s0 + 1.25
		while sp < s1 - 0.5:
			for sx2 in [-0.60, 0.60]:
				_box(Vector3(0.14, h_pot, 0.14), iron, sp, sx2, y_bottom + h_pot * 0.5, "PoteauFosse")
			sp += 2.5
		# escalier pour remonter : marches de 17 cm, montant vers la cloison
		# jusqu'au niveau du quai (on en sort de côté, sur le palier)
		var y_quai: float = FLOOR_Y_LOCAL + platform_height
		var haut_m: float = (y_quai - y_bottom) / esc_n
		for k in range(esc_n):
			var y_d: float = y_bottom + haut_m * (k + 1)
			var s_m: float = esc_s1 - esc_giron * (k + 0.5)
			_box(Vector3(esc_x1 - esc_x0, y_d - y_bottom, esc_giron), concrete, s_m, (esc_x0 + esc_x1) * 0.5,
				y_bottom + (y_d - y_bottom) * 0.5, "EscalierFosse")
			_box(Vector3(esc_x1 - esc_x0, 0.03, 0.05), steel, s_m + esc_giron * 0.5 - 0.025,
				(esc_x0 + esc_x1) * 0.5, y_d - 0.013, "NezMarcheFosse")
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


## Habillage des salles de gare d'après les photos (2026-09-27, les deux
## gares se ressemblent) : parois BLEU NUIT, plafond CLAIR porté par des
## poutres acier sombres en travers tous les 2,8 m et deux pannes en long,
## poteaux sombres le long des murs tous les 4,2 m, appliques bleues. Les
## boîtes sont posées juste en dedans de la section rectangulaire de la
## salle (elles masquent la paroi lisse du tunnel).
const NAVY: Color = Color(0.13, 0.16, 0.25)
const CEIL_COL: Color = Color(0.84, 0.85, 0.87)
const BEAM_COL: Color = Color(0.09, 0.10, 0.13)


func _mkmat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _build_room_dressing(s0: float, s1: float, _is_low: bool) -> void:
	var navy: StandardMaterial3D = _mkmat(NAVY, 0.85, 0.0)
	var ceil_m: StandardMaterial3D = _mkmat(CEIL_COL, 0.75, 0.0)
	var beam: StandardMaterial3D = _mkmat(BEAM_COL, 0.45, 0.5)
	# en vue extérieure, l'habillage devient translucide comme le tunnel
	for m in [navy, ceil_m, beam]:
		tunnel.extra_see_through.append(m)
	var blue_lamp: StandardMaterial3D = StandardMaterial3D.new()
	blue_lamp.albedo_color = Color(0.45, 0.65, 1.0)
	blue_lamp.emission_enabled = true
	blue_lamp.emission = Color(0.30, 0.55, 1.0)
	blue_lamp.emission_energy_multiplier = 3.0
	blue_lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var hw: float = tunnel.station_room_half_width
	var hh: float = tunnel.station_room_half_height
	var length: float = s1 - s0
	var sc: float = (s0 + s1) * 0.5
	var wall_h: float = hh - FLOOR_Y_LOCAL
	var y_wall: float = FLOOR_Y_LOCAL + wall_h * 0.5
	for sx in [-1.0, 1.0]:
		var pg: Vector2 = PORTE_GENEPY
		if _is_low or sx > 0.0 or pg.y < s0 or pg.x > s1:
			_box(Vector3(0.06, wall_h, length), navy, sc, sx * (hw - 0.04), y_wall, "ParoiGare")
			continue
		# mur gauche de la gare haute : percé de la porte Génépy
		var y_seuil: float = FLOOR_Y_LOCAL + platform_height
		_box(Vector3(0.06, wall_h, pg.x - s0), navy, (s0 + pg.x) * 0.5, sx * (hw - 0.04), y_wall, "ParoiGare")
		_box(Vector3(0.06, wall_h, s1 - pg.y), navy, (pg.y + s1) * 0.5, sx * (hw - 0.04), y_wall, "ParoiGare")
		var y_linteau: float = y_seuil + PORTE_GENEPY_H
		_box(Vector3(0.06, hh - y_linteau, pg.y - pg.x), navy, (pg.x + pg.y) * 0.5, sx * (hw - 0.04),
			(hh + y_linteau) * 0.5, "ParoiGare")
		_box(Vector3(0.06, y_seuil - FLOOR_Y_LOCAL, pg.y - pg.x), navy, (pg.x + pg.y) * 0.5,
			sx * (hw - 0.04), (FLOOR_Y_LOCAL + y_seuil) * 0.5, "ParoiGare")
		# encadrement : montants et linteau bleu marine foncé
		for sp in [pg.x, pg.y]:
			_box(Vector3(0.14, PORTE_GENEPY_H, 0.10), beam, sp, sx * (hw - 0.02), y_seuil + PORTE_GENEPY_H * 0.5, "CadrePorte")
		_box(Vector3(0.14, 0.12, pg.y - pg.x + 0.10), beam, (pg.x + pg.y) * 0.5, sx * (hw - 0.02),
			y_linteau + 0.06, "CadrePorte")
	_box(Vector3(hw * 2.0, 0.06, length), ceil_m, sc, 0.0, hh - 0.04, "PlafondGare")
	# poutres en travers (IPN sombres) et deux pannes en long
	var s: float = s0 + 1.4
	while s < s1 - 0.5:
		_box(Vector3(hw * 2.0 - 0.1, 0.32, 0.16), beam, s, 0.0, hh - 0.24, "PoutreGare")
		s += 2.8
	for sx in [-2.6, 2.6]:
		_box(Vector3(0.14, 0.14, length), beam, sc, sx, hh - 0.47, "PanneGare")
	# poteaux le long des murs
	s = s0 + 2.0
	while s < s1 - 1.0:
		for sx in [-1.0, 1.0]:
			_box(Vector3(0.26, wall_h, 0.26), beam, s, sx * (hw - 0.2), y_wall, "PoteauGare")
		s += 4.2
	# appliques bleues (photos 095511 / 095520 : halo bleu sur les murs)
	s = s0 + 4.0
	while s < s1 - 2.0:
		for sx in [-1.0, 1.0]:
			_box(Vector3(0.10, 0.28, 0.10), blue_lamp, s, sx * (hw - 0.12), 1.25, "AppliqueBleue")
			var l: OmniLight3D = OmniLight3D.new()
			l.light_color = Color(0.35, 0.55, 1.0)
			l.light_energy = 1.4
			l.omni_range = 7.0
			l.shadow_enabled = false
			var xf: Transform3D = _xf_at(s)
			l.position = xf.origin + xf.basis.x * (sx * (hw - 0.4)) + xf.basis.y * 1.25
			add_child(l)
		s += 8.4


const KOMPAT: float = 2.5
# Porte de la piste Génépy (Kevin, 07/10/2026 : « au bout en bas du quai
# gauche en regardant vers le haut, il y a une porte pour sortir et faire
# la piste Génépy ») : abscisses du passage dans le mur gauche de la salle
# du quai haut (entre deux poteaux), hauteur depuis le dessus du quai.
const PORTE_GENEPY: Vector2 = Vector2(3481.62, 3483.0)
const PORTE_GENEPY_H: float = 2.25


func _compat() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


func _build_ceiling_lights(s_start: float, s_end: float) -> void:
	# entre les poutres (tous les 2,8 m), tubes plus fins
	var spacing: float = 2.8
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
		# rendu Compatibility (PWA) : ni éclairage indirect ni plus de 8
		# lampes par objet → néons 2,5 fois plus forts (« la gare du haut
		# semble dans le noir », iPad 07/10/2026), sauf sur l'intérieur de
		# la cabine (Cabin.MASQUE_GARE_WEB)
		light.light_energy = 4.5 * (KOMPAT if _compat() else 1.0)
		if _compat():
			light.light_cull_mask = Cabin.MASQUE_GARE_WEB   # pas l'intérieur de la cabine
		light.omni_range = 16.0
		light.omni_attenuation = 1.4
		light.shadow_enabled = false
		add_child(light)

		# Bâtonnet émissif visible (source lumineuse visible dans le brouillard)
		var neon_mesh: BoxMesh = BoxMesh.new()
		neon_mesh.size = Vector3(2.4, 0.06, 0.12)
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
