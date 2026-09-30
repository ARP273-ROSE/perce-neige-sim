class_name MachineRoomBuilder
extends Node3D
## Machinerie de la gare amont (Grande Motte) — refonte du 2026-09-29.
##
## Faits retenus :
##   - DEUX roues d'entraînement ∅ 4160 mm (remontees-mecaniques.net), jaunes,
##     gorges garnies de rouge, freins à étriers sur bâti vert (photos du
##     reportage RM.net, « Freins sur la poulie motrice ») ;
##   - la roue AVAL affleure au niveau de la voie, entre les deux bras bleus des
##     butoirs de la gare amont (Kevin, 2026-09-29) ; tout le reste est sous
##     terre (« on ne voit que le sommet de la grosse roue aval », 2026-09-27) ;
##   - 3 moteurs à courant continu 800 kW BLEUS (Sicme Motori), chacun par un
##     arbre sous carter grillagé jaune vers un réducteur JAUNE ; centrale
##     hydraulique des freins jaune ; murs carrelés blancs (photos RM.net) ;
##   - principe classique d'entraînement de funiculaire (Wikipedia
##     « Funicular ») : roue à deux gorges, demi-tour, retour par une seconde
##     roue, second tour dans l'autre gorge — adhérence doublée.
##
## Tracé du câble (déduit, aucun plan publié) — vérifié par SageMath dans
## audit_physique/salle_machines_cable.sage :
##   brin gauche de la voie → sommet de la roue aval A (gorge 1) → HUIT entre A
##   (sens horaire) et la roue amont B (sens anti-horaire), deux passes par
##   roue → B gorge 2 → le brin quitte B par son SOMMET, au niveau de la voie,
##   et file droit jusqu'au brin droit de la voie. Les sommets des deux roues
##   sont alignés sur la pente de la voie en gare amont (Kevin, 30/09/2026) :
##   B a été remontée d'1 m et dépasse de 30 cm du sol du hall derrière les
##   butoirs, dans la fosse. Enroulement total 774°, désaxements ≤ 2,7°.
##
## Repère local : celui de tunnel.transform_at(LENGTH) — x à droite, y en haut,
## s le long de la voie (0 = fin du tunnel, > 0 vers la salle).

# --- Géométrie (mêmes valeurs que salle_machines_cable.sage) ---------------
const Y_BRIN: float = -1.36          # axe des brins sur la voie (track_builder)
const R: float = 2.08                # rayon primitif (axe du câble) : ∅ 4160 mm
const RF: float = 2.14               # rayon extérieur des joues
const R_CABLE: float = 0.026         # câble Fatzer 52 mm
const A_S: float = 0.95              # roue aval : entre les bras des butoirs
const A_Y: float = Y_BRIN - R        # son sommet affleure au niveau des brins
const B_S: float = 7.55              # roue amont, derrière les butoirs
const B_Y: float = A_Y               # sommets alignés sur la pente de la voie
const A_GROOVES: Array = [-0.12, -0.36]
const B_GROOVES: Array = [-0.24, -0.12]
const LANE_L: float = -0.12          # brin qui arrive sur la roue aval
const LANE_R: float = 0.12           # brin qui repart du sommet de la roue amont
const S0: float = 0.20               # où le brin de sortie rejoint la voie droite

# --- Gare et salle ---------------------------------------------------------
const Y_HALL_FLOOR: float = -1.60    # dessus de dalle (stations_builder.FLOOR_Y_LOCAL)
const Y_SLAB_BOTTOM: float = -1.90
const Y_HALL_CEIL: float = 2.65
const HALL_HALF_W: float = 4.90
const HALL_DEPTH: float = 9.0
const PIT_S0: float = -0.85          # fosse ouverte autour des deux roues et des brins
const PIT_S1: float = 8.95
const PIT_X0: float = -0.58
const PIT_X1: float = 0.34
const ROOM_S0: float = -2.6
const ROOM_S1: float = 14.0
const ROOM_HALF_W: float = 5.2
const ROOM_FLOOR: float = B_Y - RF - 0.9

var tunnel: TunnelBuilder = null
var _xf: Transform3D
# Vue « salle des machines » (2026-09-30) : caméra libre autour des roues.
# Écorché : chaque paroi (mur, plafond, dalle, sol) qui se trouve entre la
# caméra et la machinerie s'efface, selon le côté où est la caméra.
const _CUT_RULES: Dictionary = {
	"MurMachines": "side", "JointCarrelage": "side", "ParoiSalle": "side",
	"PlafondMachines": "top", "PlafondMachinesAval": "top",
	"DalleG": "top", "DalleD": "top", "DalleArriere": "top", "DalleAvant": "top",
	"RiveFosse": "top", "RiveFosseFond": "top", "Caillebotis": "top",
	"BarreCaillebotis": "top",
	"PlafondSalle": "hall_top", "PoutreSalle": "hall_top", "NeonSalle": "hall_top",
	"MurMachinesAval": "s0", "MurMachinesAmont": "s1",
	"MurFond": "hall_s1", "BaieHall": "hall_s1", "Enseigne": "hall_s1",
	"SolMachines": "floor",
}
var _cut_nodes: Array = []
var cutaway_enabled: bool = false
var _obstacles: Array = []     # AABB monde des machines (caméra de la salle)
var _spin_a: Node3D = null
var _spin_b: Node3D = null
var _angle: float = 0.0
var _mats: Dictionary = {}


func build(t: TunnelBuilder) -> void:
	tunnel = t
	_xf = tunnel.transform_at(PNConstants.LENGTH)
	_make_materials()
	_build_hall_end()
	_build_room()
	_spin_a = _build_wheel(A_S, A_Y, A_GROOVES, "RoueAval")
	_spin_b = _build_wheel(B_S, B_Y, B_GROOVES, "RoueAmont")
	var geo: Dictionary = _geometry()
	# carter rouge fixe, ouvert là où le câble entre et sort : autour de
	# chaque point de tangence, jusqu'à ce que le brin ait quitté le rayon
	# du carter (sa tangente l'atteint à ≈ 22° du point de contact)
	var ouv: float = atan(sqrt(GUARD_R * GUARD_R - R * R) / R) + deg_to_rad(5.0)
	# roue aval (horaire) : dessus ouvert entre les butoirs (arrivée au
	# sommet + départs vers la roue amont), et retour de la roue amont
	_build_guard(A_S, A_Y, A_GROOVES, [
		Vector2(geo["tA_out"] - ouv, PI * 0.5 + ouv),
		Vector2(geo["tA_in"] - deg_to_rad(5.0), geo["tA_in"] + ouv)], "CarterAval")
	# roue amont (anti-horaire) : arrivées de la roue aval, départ vers la
	# roue aval et sortie par le sommet, vers la voie
	_build_guard(B_S, B_Y, B_GROOVES, [
		Vector2(geo["tB_in"] - ouv, geo["tB_in"] + deg_to_rad(5.0)),
		Vector2(geo["tB_exit"] - deg_to_rad(5.0), geo["tB_out"] + ouv)], "CarterAmont")
	_build_bearings(A_S, A_Y, A_GROOVES)
	_build_bearings(B_S, B_Y, B_GROOVES)
	_build_brake(A_S, A_Y, A_GROOVES, "FreinAval")
	_build_brake(B_S, B_Y, B_GROOVES, "FreinAmont")
	# 3 moteurs : un sur la roue aval, deux sur la roue amont (un par côté)
	_build_drive(A_S, A_Y, A_GROOVES, +1.0, "Aval")
	_build_drive(B_S, B_Y, B_GROOVES, +1.0, "AmontD")
	_build_drive(B_S, B_Y, B_GROOVES, -1.0, "AmontG")
	_build_hydraulics()
	_build_cabinets()
	_build_battery()
	_build_cable()
	_build_lights()
	_register_cutaway()


# ---------------------------------------------------------------------------
# Matériaux
# ---------------------------------------------------------------------------

func _mat(nom: String, c: Color, rough: float, metal: float, see_through: bool = false) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[nom] = m
	if see_through:
		tunnel.extra_see_through.append(m)
	return m


func _make_materials() -> void:
	_mat("dalle", Color(0.40, 0.41, 0.42), 0.9, 0.0, true)
	_mat("paroi_gare", Color(0.13, 0.16, 0.25), 0.9, 0.0, true)   # bleu nuit (photos)
	_mat("bois", Color(0.58, 0.42, 0.24), 0.75, 0.0, true)
	_mat("plafond", Color(0.84, 0.85, 0.87), 0.75, 0.0, true)
	_mat("poutre", Color(0.09, 0.10, 0.13), 0.45, 0.5, true)
	_mat("fosse", Color(0.10, 0.11, 0.13), 0.9, 0.0, true)
	_mat("carrelage", Color(0.88, 0.89, 0.88), 0.35, 0.0, true)   # murs carrelés blancs
	_mat("sol", Color(0.20, 0.22, 0.27), 0.8, 0.1, true)
	_mat("plafond_salle", Color(0.55, 0.56, 0.57), 0.9, 0.0, true)
	_mat("jaune", Color(0.95, 0.78, 0.08), 0.45, 0.25)           # voiles, réducteurs
	_mat("jante", Color(0.74, 0.13, 0.09), 0.5, 0.2)             # jante rouge (photos 2011)
	_mat("garniture", Color(0.45, 0.08, 0.06), 0.8, 0.0)         # fond des gorges
	_mat("acier", Color(0.42, 0.44, 0.47), 0.35, 0.85)
	_mat("sombre", Color(0.07, 0.07, 0.08), 0.8, 0.2)
	_mat("vert", Color(0.10, 0.52, 0.28), 0.55, 0.3)             # bâti des freins
	_mat("rouge", Color(0.80, 0.16, 0.10), 0.5, 0.3)
	_mat("turquoise", Color(0.40, 0.72, 0.62), 0.5, 0.3)
	_mat("bleu_moteur", Color(0.10, 0.34, 0.72), 0.55, 0.25)     # moteurs Sicme Motori
	_mat("gris_armoire", Color(0.62, 0.64, 0.66), 0.5, 0.3)
	_mat("cable", Color(0.24, 0.24, 0.26), 0.35, 0.95)
	var grille: StandardMaterial3D = _mat("grille_jaune", Color(0.95, 0.80, 0.10, 0.45), 0.6, 0.2)
	grille.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var neon: StandardMaterial3D = _mat("neon", Color(0.98, 0.99, 1.0), 0.5, 0.0)
	neon.emission_enabled = true
	neon.emission = Color(0.95, 0.97, 1.0)
	neon.emission_energy_multiplier = 3.0
	neon.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var glow: StandardMaterial3D = _mat("baie", Color(1.0, 0.98, 0.92), 0.5, 0.0)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.97, 0.90)
	glow.emission_energy_multiplier = 2.5
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


# ---------------------------------------------------------------------------
# Fin de la salle de gare : dalle percée de la fosse de la roue aval, parois,
# plafond, poutres, néons, mur du fond « DESTINATION GLACIER »
# ---------------------------------------------------------------------------

func _build_hall_end() -> void:
	var y_slab: float = (Y_HALL_FLOOR + Y_SLAB_BOTTOM) * 0.5
	var t_slab: float = Y_HALL_FLOOR - Y_SLAB_BOTTOM
	var dalle: StandardMaterial3D = _mats["dalle"]
	# dalle en quatre morceaux autour de la fosse
	var w_l: float = PIT_X0 + HALL_HALF_W
	var w_r: float = HALL_HALF_W - PIT_X1
	_box(Vector3(w_l, t_slab, HALL_DEPTH), dalle, -HALL_HALF_W + w_l * 0.5, y_slab, HALL_DEPTH * 0.5, "DalleG")
	_box(Vector3(w_r, t_slab, HALL_DEPTH), dalle, PIT_X1 + w_r * 0.5, y_slab, HALL_DEPTH * 0.5, "DalleD")
	var pit_w: float = PIT_X1 - PIT_X0
	var pit_xc: float = (PIT_X0 + PIT_X1) * 0.5
	_box(Vector3(pit_w, t_slab, HALL_DEPTH - PIT_S1), dalle, pit_xc, y_slab, (PIT_S1 + HALL_DEPTH) * 0.5, "DalleArriere")
	if PIT_S0 > 0.0:
		_box(Vector3(pit_w, t_slab, PIT_S0), dalle, pit_xc, y_slab, PIT_S0 * 0.5, "DalleAvant")
	# rebords de la fosse : cornières jaunes (photos : rives peintes)
	var jaune: StandardMaterial3D = _mats["jaune"]
	var rive0: float = maxf(PIT_S0, 0.0)
	for xx in [PIT_X0, PIT_X1]:
		_box(Vector3(0.06, 0.04, PIT_S1 - rive0), jaune, xx, Y_HALL_FLOOR + 0.02, (rive0 + PIT_S1) * 0.5, "RiveFosse")
	_box(Vector3(pit_w, 0.04, 0.06), jaune, pit_xc, Y_HALL_FLOOR + 0.02, PIT_S1, "RiveFosseFond")
	# caillebotis (photo RM.net) sur la partie de la fosse où rien ne sort :
	# côté gauche, entre la roue aval et la roue amont ; restent ouverts le
	# couloir du brin de sortie (au niveau de la voie, sur ses galets) et
	# l'emprise de la roue amont, qui dépasse du sol
	var cail: StandardMaterial3D = _mat("caillebotis", Color(0.16, 0.17, 0.19), 0.55, 0.6, true)
	var cs0: float = A_S + 1.20
	var cs1: float = B_S - 1.45          # la roue amont sort de la fosse après
	var cx1: float = -0.12               # galets du brin de sortie à droite
	_box(Vector3(cx1 - PIT_X0, 0.03, cs1 - cs0), cail, (PIT_X0 + cx1) * 0.5,
		Y_HALL_FLOOR - 0.015, (cs0 + cs1) * 0.5, "Caillebotis")
	for k in range(int((cs1 - cs0) / 0.12)):
		_box(Vector3(cx1 - PIT_X0, 0.012, 0.02), _mats["sombre"], (PIT_X0 + cx1) * 0.5,
			Y_HALL_FLOOR + 0.003, cs0 + 0.06 + 0.12 * float(k), "BarreCaillebotis")
	# garde-corps jaune autour de la roue amont, qui dépasse de 30 cm du sol
	var gc0: float = cs1 - 0.1
	for xx in [PIT_X0 - 0.10, PIT_X1 + 0.10]:
		_box(Vector3(0.05, 0.05, PIT_S1 - gc0), jaune, xx, Y_HALL_FLOOR + 1.0, (gc0 + PIT_S1) * 0.5, "GardeCorps")
		_box(Vector3(0.04, 0.04, PIT_S1 - gc0), jaune, xx, Y_HALL_FLOOR + 0.5, (gc0 + PIT_S1) * 0.5, "GardeCorps")
		for sp in [gc0, (gc0 + PIT_S1) * 0.5, PIT_S1 - 0.05]:
			_box(Vector3(0.05, 1.0, 0.05), jaune, xx, Y_HALL_FLOOR + 0.5, sp, "GardeCorps")
	_box(Vector3(PIT_X1 - PIT_X0 + 0.25, 0.05, 0.05), jaune, pit_xc, Y_HALL_FLOOR + 1.0, gc0, "GardeCorps")

	# parois, plafond, poutres de la salle de gare prolongés jusqu'au fond
	var hall_h: float = Y_HALL_CEIL - Y_HALL_FLOOR
	var y_mid: float = (Y_HALL_CEIL + Y_HALL_FLOOR) * 0.5
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.30, hall_h, HALL_DEPTH), _mats["paroi_gare"],
			sx * (HALL_HALF_W + 0.15), y_mid, HALL_DEPTH * 0.5, "ParoiSalle")
	_box(Vector3(HALL_HALF_W * 2.0 + 0.6, 0.30, HALL_DEPTH), _mats["plafond"],
		0.0, Y_HALL_CEIL + 0.15, HALL_DEPTH * 0.5, "PlafondSalle")
	for sb in [1.4, 4.2, 7.0]:
		_box(Vector3(HALL_HALF_W * 2.0, 0.32, 0.16), _mats["poutre"], 0.0, Y_HALL_CEIL - 0.24, sb, "PoutreSalle")
	# mur du fond : bardage bois, deux baies lumineuses, enseigne
	_box(Vector3(HALL_HALF_W * 2.0 + 0.6, hall_h, 0.30), _mats["bois"],
		0.0, y_mid, HALL_DEPTH + 0.15, "MurFond")
	for sx in [-1.0, 1.0]:
		_box(Vector3(2.0, 1.4, 0.06), _mats["baie"], sx * 3.0, Y_HALL_FLOOR + 1.0, HALL_DEPTH - 0.04, "BaieHall")
	var sign_l: Label3D = Label3D.new()
	sign_l.text = "DESTINATION\nGLACIER"
	sign_l.font_size = 96
	sign_l.pixel_size = 0.006
	sign_l.modulate = Color(1.0, 0.62, 0.12)
	sign_l.outline_modulate = Color(0.5, 0.25, 0.02)
	sign_l.outline_size = 8
	sign_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign_l.shaded = false
	sign_l.double_sided = true
	sign_l.set_meta("nom", "Enseigne")
	add_child(sign_l)
	_place(sign_l, 0.0, Y_HALL_FLOOR + 3.0, HALL_DEPTH - 0.05)
	for s_pos in [3.0, 7.0]:
		var light: OmniLight3D = OmniLight3D.new()
		light.light_color = Color(0.95, 0.97, 1.0)
		light.light_energy = 3.0
		light.omni_range = 10.0
		light.shadow_enabled = false
		add_child(light)
		_place(light, 0.0, Y_HALL_CEIL - 0.4, s_pos)
		_box(Vector3(2.4, 0.08, 0.16), _mats["neon"], 0.0, Y_HALL_CEIL - 0.25, s_pos, "NeonSalle")


# ---------------------------------------------------------------------------
# Salle des machines sous la dalle : murs carrelés blancs, sol sombre
# ---------------------------------------------------------------------------

func _build_room() -> void:
	var h: float = Y_SLAB_BOTTOM - ROOM_FLOOR
	var y_mid: float = (Y_SLAB_BOTTOM + ROOM_FLOOR) * 0.5
	var s_c: float = (ROOM_S0 + ROOM_S1) * 0.5
	var long: float = ROOM_S1 - ROOM_S0
	_box(Vector3(ROOM_HALF_W * 2.0, 0.30, long), _mats["sol"], 0.0, ROOM_FLOOR - 0.15, s_c, "SolMachines")
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.30, h, long), _mats["carrelage"], sx * (ROOM_HALF_W + 0.15), y_mid, s_c, "MurMachines")
	_box(Vector3(ROOM_HALF_W * 2.0, h, 0.30), _mats["carrelage"], 0.0, y_mid, ROOM_S0 - 0.15, "MurMachinesAval")
	_box(Vector3(ROOM_HALF_W * 2.0, h, 0.30), _mats["carrelage"], 0.0, y_mid, ROOM_S1 + 0.15, "MurMachinesAmont")
	# plafond sous la fin du tunnel (côté voie) et au-delà de la dalle de gare
	_box(Vector3(ROOM_HALF_W * 2.0, 0.15, -ROOM_S0), _mats["plafond_salle"],
		0.0, Y_SLAB_BOTTOM - 0.075, ROOM_S0 * 0.5, "PlafondMachinesAval")
	var s_p0: float = HALL_DEPTH
	_box(Vector3(ROOM_HALF_W * 2.0, 0.30, ROOM_S1 - s_p0), _mats["plafond_salle"],
		0.0, Y_SLAB_BOTTOM + 0.15, (s_p0 + ROOM_S1) * 0.5, "PlafondMachines")
	# joints du carrelage (lignes sombres horizontales) pour lire l'échelle
	for k in range(1, int(h / 0.6)):
		for sx in [-1.0, 1.0]:
			_box(Vector3(0.01, 0.012, long), _mats["sombre"], sx * (ROOM_HALF_W - 0.005),
				ROOM_FLOOR + float(k) * 0.6, s_c, "JointCarrelage")


# ---------------------------------------------------------------------------
# Roue d'entraînement : voile jaune plein, jante à gorges garnies de rouge,
# joues jaunes, piste de frein, moyeu, lumières (on les voit tourner)
# ---------------------------------------------------------------------------

func _wheel_x_range(grooves: Array) -> Vector2:
	var x0: float = 1e9
	var x1: float = -1e9
	for g in grooves:
		x0 = minf(x0, float(g))
		x1 = maxf(x1, float(g))
	return Vector2(x0 - 0.10, x1 + 0.10)


## Roue d'entraînement, d'après les photos de la visite du 20/06/2011
## (forum remontees-mecaniques.net, « Une poulie », « Une des deux poulies
## motrices », « Les freins de poulie ») et la vidéo qui l'accompagne : roue
## JAUNE (voile évidé d'une couronne de douze ouvertures en pétales aux coins
## très arrondis, étroites au moyeu, larges côté jante), piste de frein en
## acier sombre sous la jante. Le ROUGE est un CARTER FIXE qui coiffe la
## jante et protège le câble : il ne tourne pas, le câble court dedans, et il
## est ouvert là où le câble entre et sort (Kevin, 2026-09-29).
const WEB_T: float = 0.10            # épaisseur du voile
const RIM_IN: float = R - 0.30       # intérieur de la jante rouge
const N_OPEN: int = 12               # ouvertures du voile
const GUARD_R: float = RF + 0.10     # carter rouge fixe : rayon de la tôle extérieure
const GUARD_IN: float = R - 0.22     # bord intérieur de ses flasques
const GUARD_SIDE: float = 0.08       # jeu latéral entre roue et flasques
const OPEN_R1: float = 0.40          # extrémité intérieure (× RIM_IN)
const OPEN_R2: float = 0.86          # extrémité extérieure (× RIM_IN)
const SPOKE_W: float = 0.28          # largeur des bras entre ouvertures
const OPEN_FILLET: float = 0.22      # rayon des arrondis


func _build_wheel(s_c: float, y_c: float, grooves: Array, nom: String) -> Node3D:
	var xr: Vector2 = _wheel_x_range(grooves)
	var x_c: float = (xr.x + xr.y) * 0.5
	var spin: Node3D = Node3D.new()
	spin.name = nom
	add_child(spin)
	_place(spin, x_c, y_c, s_c)
	var jaune: StandardMaterial3D = _mats["jaune"]
	# jante jaune sous les gorges (elle tourne), fond des gorges plus sombre
	_ring(spin, RIM_IN, R - R_CABLE - 0.01, xr.x - x_c, xr.y - x_c, jaune)
	_ring(spin, R - R_CABLE - 0.01, R - R_CABLE, xr.x - x_c, xr.y - x_c, _mats["garniture"])
	# joues jaunes : de part et d'autre, et entre les gorges
	var joues: Array = [xr.x, xr.y]
	for i in range(grooves.size() - 1):
		joues.append((float(grooves[i]) + float(grooves[i + 1])) * 0.5)
	for xj in joues:
		_ring(spin, RIM_IN, RF, float(xj) - x_c - 0.018, float(xj) - x_c + 0.018, jaune)
	# voile jaune évidé
	var web: MeshInstance3D = MeshInstance3D.new()
	web.name = "Voile"
	web.mesh = _web_mesh(0.40, RIM_IN + 0.02, WEB_T, _mats["jaune"])
	web.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spin.add_child(web)
	# piste de frein côté +x, juste sous la jante (photo « Les freins de poulie »)
	_ring(spin, RIM_IN - 0.14, RIM_IN, xr.y - x_c - 0.02, xr.y - x_c + 0.03, _mats["acier"])
	# moyeu et bossages
	_disc(spin, 0.42, 0.62, 0.0, _mats["acier"])
	for i in range(8):
		var a: float = float(i) / 8.0 * TAU
		var bos: MeshInstance3D = _cyl_x(0.045, 0.66, _mats["sombre"])
		bos.position = Vector3(0.0, cos(a) * 0.31, sin(a) * 0.31)
		spin.add_child(bos)
	return spin


## Contour de la moitié droite d'une ouverture (repère du secteur : ouverture
## centrée sur l'axe +u, bras à ±π/N_OPEN), du bout extérieur au bout
## intérieur, coins arrondis par des courbes de Bézier.
func _opening_half(rw: float) -> PackedVector2Array:
	var alpha: float = PI / float(N_OPEN)
	var r1: float = OPEN_R1 * rw
	var r2: float = OPEN_R2 * rw
	var hw: float = SPOKE_W * 0.5
	var d: Vector2 = Vector2(cos(alpha), sin(alpha))          # axe du bras
	var off: Vector2 = Vector2(sin(alpha), -cos(alpha)) * hw  # vers l'ouverture
	var c2: Vector2 = d * sqrt(r2 * r2 - hw * hw) + off        # coin extérieur
	var c1: Vector2 = d * sqrt(r1 * r1 - hw * hw) + off        # coin intérieur
	var a2: float = c2.angle()
	var a1: float = c1.angle()
	var rc: float = minf(OPEN_FILLET, 0.9 * a2 * r2)
	var pts: PackedVector2Array = PackedVector2Array()
	# arc extérieur, de l'axe jusqu'avant le coin
	var a2s: float = a2 - rc / r2
	for k in range(7):
		var a: float = a2s * float(k) / 6.0
		pts.append(Vector2(cos(a), sin(a)) * r2)
	# arrondi extérieur
	var p_a: Vector2 = Vector2(cos(a2s), sin(a2s)) * r2
	var p_b: Vector2 = c2 - d * rc
	for k in range(1, 6):
		var t: float = float(k) / 6.0
		pts.append(p_a.lerp(c2, t).lerp(c2.lerp(p_b, t), t))
	pts.append(p_b)
	# le long du bras, jusqu'avant le coin intérieur (arrondi borné par la
	# demi-largeur du bout intérieur : bout en ogive)
	var rc_in: float = minf(rc, 0.9 * a1 * r1)
	var q_a: Vector2 = c1 + d * rc_in
	pts.append(q_a)
	var a1s: float = a1 - rc_in / r1
	var q_b: Vector2 = Vector2(cos(a1s), sin(a1s)) * r1
	for k in range(1, 6):
		var t2: float = float(k) / 6.0
		pts.append(q_a.lerp(c1, t2).lerp(c1.lerp(q_b, t2), t2))
	# arc intérieur, du coin vers l'axe
	for k in range(0, 5):
		var a3: float = a1s * (1.0 - float(k) / 4.0)
		pts.append(Vector2(cos(a3), sin(a3)) * r1)
	return pts


## Voile plein de rayon r_hub..r_out, épaisseur t, évidé de N_OPEN ouvertures.
## Chaque secteur est coupé en deux moitiés sans trou (triangulées par
## Geometry2D), puis tourné ; parois des ouvertures extrudées.
func _web_mesh(r_hub: float, r_out: float, t: float, mat: StandardMaterial3D) -> ArrayMesh:
	var alpha: float = PI / float(N_OPEN)
	var half: PackedVector2Array = _opening_half(RIM_IN)
	# polygone du demi-secteur plein (côté +v)
	var poly: PackedVector2Array = PackedVector2Array()
	for k in range(5):
		var a: float = alpha * float(k) / 4.0
		poly.append(Vector2(cos(a), sin(a)) * r_hub)
	for k in range(9):
		var a2: float = alpha * (1.0 - float(k) / 8.0)
		poly.append(Vector2(cos(a2), sin(a2)) * r_out)
	for q in half:
		poly.append(q)
	var idx: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		push_warning("[MachineRoom] triangulation du voile impossible")
	# contour complet d'une ouverture (moitié droite puis gauche en miroir)
	var loop: PackedVector2Array = half.duplicate()
	for k in range(half.size() - 1, -1, -1):
		loop.append(Vector2(half[k].x, -half[k].y))
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	for sec in range(N_OPEN):
		var rot: float = TAU * float(sec) / float(N_OPEN)
		for side in [1.0, -1.0]:
			for face in [t * 0.5, -t * 0.5]:
				for k in range(0, idx.size(), 3):
					var tri: Array = [idx[k], idx[k + 1], idx[k + 2]]
					if (side < 0.0) != (face < 0.0):
						tri = [idx[k], idx[k + 2], idx[k + 1]]
					for vi in tri:
						var p: Vector2 = poly[vi]
						p = Vector2(p.x, p.y * side).rotated(rot)
						st.add_vertex(Vector3(face, p.y, p.x))
		# parois de l'ouverture
		for k in range(loop.size()):
			var p0: Vector2 = loop[k].rotated(rot)
			var p1: Vector2 = loop[(k + 1) % loop.size()].rotated(rot)
			var v00: Vector3 = Vector3(-t * 0.5, p0.y, p0.x)
			var v01: Vector3 = Vector3(t * 0.5, p0.y, p0.x)
			var v10: Vector3 = Vector3(-t * 0.5, p1.y, p1.x)
			var v11: Vector3 = Vector3(t * 0.5, p1.y, p1.x)
			st.add_vertex(v00); st.add_vertex(v10); st.add_vertex(v11)
			st.add_vertex(v00); st.add_vertex(v11); st.add_vertex(v01)
	st.generate_normals()
	return st.commit()


## Carter fixe rouge : tôle extérieure cylindrique + deux flasques, coiffant
## la jante sur tout le tour SAUF dans les ouvertures (angles en radians,
## même convention que _geometry : s = cos t, y = sin t). Deux pieds rouges
## le portent jusqu'au sol.
func _build_guard(s_c: float, y_c: float, grooves: Array, ouvertures: Array, nom: String) -> void:
	var xr: Vector2 = _wheel_x_range(grooves)
	var x_c: float = (xr.x + xr.y) * 0.5
	var node: Node3D = Node3D.new()
	node.name = nom
	add_child(node)
	_place(node, x_c, y_c, s_c)
	var rouge: StandardMaterial3D = _mats["jante"]
	var x0: float = xr.x - x_c - GUARD_SIDE
	var x1: float = xr.y - x_c + GUARD_SIDE
	# segments fermés = complément des ouvertures sur [0, 2π)
	var ouv: Array = []
	for o in ouvertures:
		var a0: float = fposmod(o.x, TAU)
		var a1: float = a0 + fposmod(o.y - o.x, TAU)
		ouv.append(Vector2(a0, a1))
	ouv.sort_custom(func(p, q): return p.x < q.x)
	var fermes: Array = []
	for i in range(ouv.size()):
		var debut: float = ouv[i].y
		var fin: float = ouv[(i + 1) % ouv.size()].x
		if i == ouv.size() - 1:
			fin += TAU
		if fin > debut + 0.01:
			fermes.append(Vector2(debut, fin))
	for f in fermes:
		_ring_arc(node, GUARD_R - 0.02, GUARD_R, x0, x1, f.x, f.y, rouge)
		for xx in [x0, x1 - 0.02]:
			_ring_arc(node, GUARD_IN, GUARD_R, xx, xx + 0.02, f.x, f.y, rouge)
	# pieds
	for ds in [-1.3, 1.3]:
		var h: float = y_c - sqrt(GUARD_R * GUARD_R - ds * ds) - ROOM_FLOOR
		if h > 0.1:
			_box(Vector3(0.20, h, 0.20), rouge, x0 + 0.1, ROOM_FLOOR + h * 0.5, s_c + ds, nom + "Pied")


## Portion de couronne d'axe x : rayons r_in..r_out, de x0 à x1, angles
## a0 → a1 (convention _geometry : s = r cos a, y = r sin a ; dans le repère
## du nœud, z = −s).
func _ring_arc(parent: Node3D, r_in: float, r_out: float, x0: float, x1: float,
		a0: float, a1: float, mat: StandardMaterial3D) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	var n: int = maxi(2, int(ceil((a1 - a0) / deg_to_rad(3.0))))
	for i in range(n):
		var t0: float = lerpf(a0, a1, float(i) / float(n))
		var t1: float = lerpf(a0, a1, float(i + 1) / float(n))
		for q in [[r_out, x0, x1], [r_in, x1, x0]]:
			var rr: float = q[0]
			var p0: Vector3 = Vector3(q[1], sin(t0) * rr, -cos(t0) * rr)
			var p1: Vector3 = Vector3(q[2], sin(t0) * rr, -cos(t0) * rr)
			var p2: Vector3 = Vector3(q[2], sin(t1) * rr, -cos(t1) * rr)
			var p3: Vector3 = Vector3(q[1], sin(t1) * rr, -cos(t1) * rr)
			st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p2)
			st.add_vertex(p0); st.add_vertex(p2); st.add_vertex(p3)
		for xx in [x0, x1]:
			var q0: Vector3 = Vector3(xx, sin(t0) * r_in, -cos(t0) * r_in)
			var q1: Vector3 = Vector3(xx, sin(t0) * r_out, -cos(t0) * r_out)
			var q2: Vector3 = Vector3(xx, sin(t1) * r_out, -cos(t1) * r_out)
			var q3: Vector3 = Vector3(xx, sin(t1) * r_in, -cos(t1) * r_in)
			st.add_vertex(q0); st.add_vertex(q1); st.add_vertex(q2)
			st.add_vertex(q0); st.add_vertex(q2); st.add_vertex(q3)
	# bouts du segment
	for tt in [a0, a1]:
		var e0: Vector3 = Vector3(x0, sin(tt) * r_in, -cos(tt) * r_in)
		var e1: Vector3 = Vector3(x1, sin(tt) * r_in, -cos(tt) * r_in)
		var e2: Vector3 = Vector3(x1, sin(tt) * r_out, -cos(tt) * r_out)
		var e3: Vector3 = Vector3(x0, sin(tt) * r_out, -cos(tt) * r_out)
		st.add_vertex(e0); st.add_vertex(e1); st.add_vertex(e2)
		st.add_vertex(e0); st.add_vertex(e2); st.add_vertex(e3)
	st.generate_normals()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Paliers : deux chaises d'acier sombre sur massifs, arbre gris.
func _build_bearings(s_c: float, y_c: float, grooves: Array) -> void:
	var xr: Vector2 = _wheel_x_range(grooves)
	var x_c: float = (xr.x + xr.y) * 0.5
	var arbre: MeshInstance3D = _cyl_x(0.20, 3.4, _mats["acier"])
	add_child(arbre)
	_place(arbre, x_c, y_c, s_c)
	for side in [-1.0, 1.0]:
		var xp: float = x_c + side * 1.20
		var hh: float = y_c - ROOM_FLOOR
		_box(Vector3(0.55, hh, 0.9), _mats["sombre"], xp, ROOM_FLOOR + hh * 0.5, s_c, "Palier")
		_box(Vector3(0.75, 0.45, 1.1), _mats["acier"], xp, y_c, s_c, "Chaise")


## Frein à étriers sur la piste de frein, sur un bâti vert (photo RM.net) :
## un étrier rouge et un turquoise, cloches inox.
func _build_brake(s_c: float, y_c: float, grooves: Array, nom: String) -> void:
	var xr: Vector2 = _wheel_x_range(grooves)
	var x_track: float = xr.y + 0.025
	var a: float = -PI * 0.62            # sous la roue, côté voie
	var r_t: float = RIM_IN - 0.07
	var y_b: float = y_c + sin(a) * r_t
	var s_b: float = s_c + cos(a) * r_t
	var bati_h: float = y_b - ROOM_FLOOR
	_box(Vector3(0.50, bati_h, 1.6), _mats["vert"], x_track + 0.35, ROOM_FLOOR + bati_h * 0.5, s_b, nom + "Bati")
	for k in range(2):
		var ds: float = -0.38 + 0.76 * float(k)
		var m: StandardMaterial3D = _mats["rouge"] if k == 0 else _mats["turquoise"]
		_box(Vector3(0.42, 0.46, 0.40), m, x_track + 0.12, y_b + 0.05, s_b + ds, nom + "Etrier")
		var cloche: MeshInstance3D = _cyl_x(0.16, 0.14, _mats["acier"])
		add_child(cloche)
		_place(cloche, x_track + 0.40, y_b + 0.05, s_b + ds)


## Chaîne cinématique : arbre sous carter grillagé jaune → réducteur jaune à
## couvercles ronds → accouplement → moteur CC bleu avec son ventilateur.
func _build_drive(s_c: float, y_c: float, grooves: Array, side: float, nom: String) -> void:
	var xr: Vector2 = _wheel_x_range(grooves)
	var x_edge: float = xr.y if side > 0.0 else xr.x
	var x_red: float = x_edge + side * 2.10
	var red_h: float = 2.2
	var y_red: float = maxf(ROOM_FLOOR + red_h * 0.5, y_c - 0.3)
	_box(Vector3(1.20, red_h, 2.6), _mats["jaune"], x_red, y_red, s_c, "Reducteur" + nom)
	# couvercles ronds des paliers de réducteur (photo)
	for k in range(3):
		var cov: MeshInstance3D = _cyl_x(0.30 - 0.06 * float(k), 1.26, _mats["jaune"])
		add_child(cov)
		_place(cov, x_red, y_red + 0.35 - 0.30 * float(k), s_c - 0.75 + 0.75 * float(k))
	_box(Vector3(1.24, 0.10, 2.64), _mats["sombre"], x_red, ROOM_FLOOR + 0.05, s_c, "SocleReducteur")
	# arbre lent roue → réducteur, sous carter
	var arbre: MeshInstance3D = _cyl_x(0.20, absf(x_red - x_edge), _mats["acier"])
	add_child(arbre)
	_place(arbre, (x_red + x_edge) * 0.5, y_c, s_c)
	# moteur : en ligne, derrière le réducteur, arbre rapide en bas
	var s_mot: float = s_c + 2.6
	var x_mot: float = x_red
	var y_axe: float = ROOM_FLOOR + 0.75
	_box(Vector3(1.40, 1.30, 2.0), _mats["bleu_moteur"], x_mot, y_axe + 0.10, s_mot + 0.9, "Moteur" + nom)
	_box(Vector3(0.90, 0.55, 0.90), _mats["bleu_moteur"], x_mot, y_axe + 1.05, s_mot + 0.5, "Ventilateur" + nom)
	for k in range(6):
		_box(Vector3(0.02, 0.60, 0.05), _mats["sombre"], x_mot + side * 0.71, y_axe + 0.1, s_mot + 1.3 + 0.09 * float(k), "Ouies")
	_box(Vector3(1.50, 0.10, 2.2), _mats["sombre"], x_mot, ROOM_FLOOR + 0.05, s_mot + 0.9, "SocleMoteur")
	# accouplement sous carter grillagé jaune
	_box(Vector3(0.80, 0.80, 0.9), _mats["grille_jaune"], x_mot, y_axe, s_c + 1.65, "Carter" + nom)
	var acc: MeshInstance3D = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.12
	cm.height = 1.2
	cm.material = _mats["acier"]
	acc.mesh = cm
	add_child(acc)
	_place(acc, x_mot, y_axe, s_c + 1.9)
	acc.rotate_object_local(Vector3.RIGHT, PI * 0.5)


## Centrale hydraulique des freins de sécurité (jaune) et deux pompes.
func _build_hydraulics() -> void:
	var s_h: float = 11.6
	var x_h: float = -3.6
	_box(Vector3(1.6, 1.2, 2.2), _mats["jaune"], x_h, ROOM_FLOOR + 0.6, s_h, "CentraleHydraulique")
	for k in range(2):
		var pompe: MeshInstance3D = MeshInstance3D.new()
		var cm: CylinderMesh = CylinderMesh.new()
		cm.top_radius = 0.25
		cm.bottom_radius = 0.25
		cm.height = 0.6
		cm.material = _mats["jaune"]
		pompe.mesh = cm
		add_child(pompe)
		_place(pompe, x_h + 0.3, ROOM_FLOOR + 1.5, s_h - 0.6 + 1.2 * float(k))


## Armoires électriques sur tout un pan de mur (photo RM.net).
func _build_cabinets() -> void:
	for k in range(7):
		var s_k: float = ROOM_S0 + 0.9 + 1.0 * float(k)
		_box(Vector3(0.6, 2.2, 0.95), _mats["gris_armoire"], -ROOM_HALF_W + 0.35, ROOM_FLOOR + 1.1, s_k, "Armoire")
		_box(Vector3(0.02, 0.28, 0.2), _mats["sombre"], -ROOM_HALF_W + 0.66, ROOM_FLOOR + 1.6, s_k, "Voyants")


# ---------------------------------------------------------------------------
# Galets porteurs des brins entre les butoirs et dans la fosse (la batterie
# en courbe de la v1.15.26 a disparu avec la roue amont remontée).
# ---------------------------------------------------------------------------

func _build_battery() -> void:
	# Plus de batterie en courbe : le brin de sortie file droit, au niveau
	# de la voie, du sommet de la roue amont à la voie droite. Deux galets
	# porteurs le soutiennent entre les roues, un galet par brin avant la
	# roue aval (plus près, ils toucheraient la jante qui remonte).
	var r_roll: float = 0.16
	var y_roll: float = Y_BRIN - R_CABLE - r_roll
	for s_g in [3.5, 4.6]:
		var f: float = (B_S - s_g) / (B_S - S0)
		var x_g: float = float(B_GROOVES[1]) + f * (LANE_R - float(B_GROOVES[1]))
		var g: MeshInstance3D = _cyl_x(r_roll, 0.10, _mats["acier"])
		add_child(g)
		_place(g, x_g, y_roll, s_g)
		for sx in [-1.0, 1.0]:
			_box(Vector3(0.03, 0.30, 0.36), _mats["sombre"], x_g + sx * 0.08, y_roll - 0.06, s_g, "FlasqueGalet")
	for x_l in [LANE_L, LANE_R]:
		var g2: MeshInstance3D = _cyl_x(r_roll, 0.10, _mats["acier"])
		add_child(g2)
		_place(g2, x_l, y_roll, -0.55)


# ---------------------------------------------------------------------------
# Câble : géométrie (même calcul que salle_machines_cable.sage) puis tubes
# ---------------------------------------------------------------------------

func _pt(c: Vector2, t: float) -> Vector2:
	return c + Vector2(cos(t), sin(t)) * R


static func _vit_cw(t: float) -> Vector2:
	return Vector2(sin(t), -cos(t))


static func _vit_ccw(t: float) -> Vector2:
	return Vector2(-sin(t), cos(t))


## Tangente croisée entre deux cercles égaux, parcourue dans le sens des deux
## roues (première horaire si cw1, sinon anti-horaire).
func _cross_tangent(c1: Vector2, c2: Vector2, cw1: bool) -> Vector2:
	var m: Vector2 = (c1 + c2) * 0.5
	var phi: float = acos(R / (m - c1).length())
	var b1: float = (m - c1).angle()
	var b2: float = (m - c2).angle()
	for sg in [1.0, -1.0]:
		var t1: float = b1 + sg * phi
		var t2: float = b2 + sg * phi
		var u: Vector2 = (_pt(c2, t2) - _pt(c1, t1)).normalized()
		var v1: Vector2 = _vit_cw(t1) if cw1 else _vit_ccw(t1)
		var v2: Vector2 = _vit_ccw(t2) if cw1 else _vit_cw(t2)
		if u.dot(v1) > 0.99 and u.dot(v2) > 0.99:
			return Vector2(t1, t2)
	push_warning("[MachineRoom] tangente croisée introuvable")
	return Vector2.ZERO


func _geometry() -> Dictionary:
	var a: Vector2 = Vector2(A_S, A_Y)
	var b: Vector2 = Vector2(B_S, B_Y)
	var ab: Vector2 = _cross_tangent(a, b, true)      # A horaire → B
	var ba: Vector2 = _cross_tangent(b, a, false)     # B anti-horaire → A
	# sortie : par le SOMMET de B (anti-horaire : son sommet file vers la voie)
	var t_ex: float = PI * 0.5
	return {"tA_out": ab.x, "tB_in": ab.y, "tB_out": ba.x, "tA_in": ba.y,
		"tB_exit": t_ex,
		"P_Bexit": b + Vector2(cos(t_ex), sin(t_ex)) * R,
		"P_Kin": Vector2(S0, Y_BRIN)}


## Arc sur une roue, de t0 à t1 dans le sens donné, à gorge x constante.
func _arc(pts: Array, c: Vector2, rr: float, t0: float, t1: float, cw: bool, x: float) -> void:
	var span: float = fposmod(t0 - t1, TAU) if cw else fposmod(t1 - t0, TAU)
	var n: int = maxi(2, int(ceil(span / deg_to_rad(4.0))))
	for i in range(n + 1):
		var t: float = t0 - span * float(i) / float(n) if cw else t0 + span * float(i) / float(n)
		pts.append(Vector3(x, c.y + sin(t) * rr, c.x + cos(t) * rr))


func _build_cable() -> void:
	var g: Dictionary = _geometry()
	var a: Vector2 = Vector2(A_S, A_Y)
	var b: Vector2 = Vector2(B_S, B_Y)
	var pts: Array = []
	# 1. brin gauche : fin de voie → sommet de la roue aval
	pts.append(Vector3(LANE_L, Y_BRIN, 0.0))
	# 2. roue aval gorge 1 (horaire) jusqu'à la tangente vers B
	_arc(pts, a, R, PI * 0.5, g["tA_out"], true, A_GROOVES[0])
	# 3. roue amont gorge 1 (anti-horaire)
	_arc(pts, b, R, g["tB_in"], g["tB_out"], false, B_GROOVES[0])
	# 4. roue aval gorge 2 : un grand tour par le dessous, la voie et le sommet
	_arc(pts, a, R, g["tA_in"], g["tA_out"], true, A_GROOVES[1])
	# 5. roue amont gorge 2 jusqu'à la sortie
	_arc(pts, b, R, g["tB_in"], g["tB_exit"], false, B_GROOVES[1])
	# 6. du sommet de B, droit vers la voie droite, au niveau de la voie
	var p_kin: Vector2 = g["P_Kin"]
	pts.append(Vector3(LANE_R, p_kin.y, p_kin.x))
	# 7. brin droit jusqu'à la fin de voie
	pts.append(Vector3(LANE_R, Y_BRIN, 0.0))
	_tube(pts, _mats["cable"], "CableMachinerie")


func _tube(pts: Array, mat: StandardMaterial3D, nom: String) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	var segs: int = 8
	for i in range(pts.size() - 1):
		var c0: Vector3 = _to_world(pts[i])
		var c1: Vector3 = _to_world(pts[i + 1])
		if c0.distance_to(c1) < 1e-4:
			continue
		var tg: Vector3 = (c1 - c0).normalized()
		var r_vec: Vector3 = tg.cross(_xf.basis.x).normalized()
		if r_vec.length() < 0.01:
			r_vec = tg.cross(Vector3.UP).normalized()
		var u_vec: Vector3 = r_vec.cross(tg).normalized()
		for kk in range(segs):
			var a0: float = float(kk) / float(segs) * TAU
			var a1: float = float(kk + 1) / float(segs) * TAU
			var p00: Vector3 = c0 + (r_vec * cos(a0) + u_vec * sin(a0)) * R_CABLE
			var p01: Vector3 = c0 + (r_vec * cos(a1) + u_vec * sin(a1)) * R_CABLE
			var p10: Vector3 = c1 + (r_vec * cos(a0) + u_vec * sin(a0)) * R_CABLE
			var p11: Vector3 = c1 + (r_vec * cos(a1) + u_vec * sin(a1)) * R_CABLE
			st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
			st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)
	st.generate_normals()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = nom
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------------------------------------------------------------------------
# Éclairage de la salle
# ---------------------------------------------------------------------------

func _build_lights() -> void:
	var y_l: float = Y_SLAB_BOTTOM - 0.35
	for zz in range(4):
		for xx in [-2.8, 2.8]:
			var s_pos: float = ROOM_S0 + 2.0 + float(zz) * 4.2
			var light: OmniLight3D = OmniLight3D.new()
			light.light_color = Color(0.95, 0.97, 1.0)
			light.light_energy = 3.5
			light.omni_range = 9.0
			light.shadow_enabled = false
			add_child(light)
			_place(light, xx, y_l, s_pos)
			_box(Vector3(0.2, 0.08, 2.4), _mats["neon"], xx, y_l + 0.2, s_pos, "NeonMachines")


# ---------------------------------------------------------------------------
# Animation : roue aval en sens horaire, roue amont en sens inverse (huit)
# ---------------------------------------------------------------------------

func update_rotation(v_cable: float, delta: float) -> void:
	if _spin_a == null:
		return
	# rotation autour de +x : un angle positif amène le sommet vers −s ; la
	# roue aval tourne sommet vers la salle quand le brin gauche y entre.
	_angle -= v_cable / R * delta
	var base_a: Transform3D = _local_xf(_spin_a.get_meta("x", 0.0), A_Y, A_S)
	var base_b: Transform3D = _local_xf(_spin_b.get_meta("x", 0.0), B_Y, B_S)
	_spin_a.transform = base_a * Transform3D(Basis(Vector3.RIGHT, _angle), Vector3.ZERO)
	_spin_b.transform = base_b * Transform3D(Basis(Vector3.RIGHT, -_angle), Vector3.ZERO)


# ---------------------------------------------------------------------------
# Écorché de la vue « salle des machines »
# ---------------------------------------------------------------------------

func _register_cutaway() -> void:
	_cut_nodes.clear()
	for c in get_children():
		if not (c is Node3D) or not c.has_meta("nom"):
			continue
		var rule: String = _CUT_RULES.get(String(c.get_meta("nom")), "")
		if rule != "":
			_cut_nodes.append({"node": c, "rule": rule, "x": float(c.get_meta("x", 0.0))})


## Boîtes englobantes (monde) des machines : la caméra de la salle
## s'arrête devant au lieu de finir dans une armoire ou un moteur.
func obstacle_aabbs() -> Array:
	if not _obstacles.is_empty() or not is_inside_tree():
		return _obstacles
	var stack: Array = get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n is MeshInstance3D):
			continue
		var mi: MeshInstance3D = n
		var nom: String = String(mi.get_meta("nom", mi.name))
		if _CUT_RULES.has(nom) or nom.begins_with("Cable") or nom.begins_with("Neon"):
			continue
		var bb: AABB = mi.global_transform * mi.get_aabb()
		if bb.size.length() > 12.0 or bb.size.length() < 0.05:
			continue
		_obstacles.append(bb.grow(0.12))
	return _obstacles


## Centre de la machinerie (entre les deux roues), en coordonnées monde.
func focus_point() -> Vector3:
	return _to_world(Vector3(-0.2, 0.5 * (A_Y + B_Y) + 0.4, 0.5 * (A_S + B_S)))


## Repère de la fin de ligne (x = travers, y = haut, −z = vers l'amont).
func frame() -> Transform3D:
	return _xf


func set_cutaway(on: bool) -> void:
	cutaway_enabled = on
	if not on:
		for e in _cut_nodes:
			(e.node as Node3D).visible = true


## Masque les parois situées entre la caméra et la machinerie.
func update_cutaway(cam_world: Vector3) -> void:
	if not cutaway_enabled:
		return
	var rel: Vector3 = cam_world - _xf.origin
	var cx: float = rel.dot(_xf.basis.x)
	var cy: float = rel.dot(_xf.basis.y)
	var cs: float = -rel.dot(_xf.basis.z)
	for e in _cut_nodes:
		var hide: bool = false
		match e.rule:
			"side":
				hide = signf(cx) == signf(e.x) and absf(cx) > absf(e.x) - 0.4
			"top":
				hide = cy > Y_SLAB_BOTTOM
			"hall_top":
				hide = cy > Y_HALL_CEIL - 0.4
			"s0":
				hide = cs < ROOM_S0 + 0.2
			"s1":
				hide = cs > ROOM_S1 - 0.2
			"hall_s1":
				hide = cs > HALL_DEPTH - 0.2
			"floor":
				hide = cy < ROOM_FLOOR + 0.1
		(e.node as Node3D).visible = not hide


# ---------------------------------------------------------------------------
# Géométrie élémentaire
# ---------------------------------------------------------------------------

func _local_xf(ox: float, oy: float, os_s: float) -> Transform3D:
	var t: Transform3D = _xf
	t.origin = _to_world(Vector3(ox, oy, os_s))
	return t


func _to_world(p: Vector3) -> Vector3:
	return _xf.origin + _xf.basis.x * p.x + _xf.basis.y * p.y - _xf.basis.z * p.z


func _place(node: Node3D, ox: float, oy: float, os_s: float) -> void:
	# conserve l'orientation propre du nœud (cylindres couchés sur x…)
	var own: Basis = node.transform.basis
	var t: Transform3D = _local_xf(ox, oy, os_s)
	t.basis = t.basis * own
	node.transform = t
	node.set_meta("x", ox)


func _box(size: Vector3, mat: StandardMaterial3D, ox: float, oy: float, os_s: float, nom: String) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.name = nom
	mi.set_meta("nom", nom)   # Godot renomme les homonymes : la règle d'écorché lit ce méta
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_place(mi, ox, oy, os_s)
	return mi


## Cylindre d'axe x (local), centré.
func _cyl_x(radius: float, width: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = width
	cm.radial_segments = 48
	cm.material = mat
	mi.mesh = cm
	mi.rotation = Vector3(0.0, 0.0, PI * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _disc(parent: Node3D, radius: float, width: float, x_off: float, mat: StandardMaterial3D) -> void:
	var d: MeshInstance3D = _cyl_x(radius, width, mat)
	d.position = Vector3(x_off, 0.0, 0.0)
	parent.add_child(d)


## Couronne pleine d'axe x (anneau épais) : r_in..r_out, de x0 à x1.
func _ring(parent: Node3D, r_in: float, r_out: float, x0: float, x1: float, mat: StandardMaterial3D) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	var n: int = 96
	for i in range(n):
		var a0: float = float(i) / float(n) * TAU
		var a1: float = float(i + 1) / float(n) * TAU
		var c0: Vector2 = Vector2(cos(a0), sin(a0))
		var c1: Vector2 = Vector2(cos(a1), sin(a1))
		# faces : extérieure, intérieure, deux flancs
		for q in [[r_out, x0, x1], [r_in, x1, x0]]:
			var rr: float = q[0]
			var p0: Vector3 = Vector3(q[1], c0.y * rr, c0.x * rr)
			var p1: Vector3 = Vector3(q[2], c0.y * rr, c0.x * rr)
			var p2: Vector3 = Vector3(q[2], c1.y * rr, c1.x * rr)
			var p3: Vector3 = Vector3(q[1], c1.y * rr, c1.x * rr)
			st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p2)
			st.add_vertex(p0); st.add_vertex(p2); st.add_vertex(p3)
		for xx in [x0, x1]:
			var q0: Vector3 = Vector3(xx, c0.y * r_in, c0.x * r_in)
			var q1: Vector3 = Vector3(xx, c0.y * r_out, c0.x * r_out)
			var q2: Vector3 = Vector3(xx, c1.y * r_out, c1.x * r_out)
			var q3: Vector3 = Vector3(xx, c1.y * r_in, c1.x * r_in)
			st.add_vertex(q0); st.add_vertex(q1); st.add_vertex(q2)
			st.add_vertex(q0); st.add_vertex(q2); st.add_vertex(q3)
	st.generate_normals()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
