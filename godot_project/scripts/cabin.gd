class_name Cabin
extends Node3D
## Cabine du funiculaire — deux voitures couplées, carrosserie d'après les
## photos du 2026-04-26 (TrainBodyBuilder : tube gris nervuré, hublots,
## portes, calottes jaunes, fond plat au-dessus des rails, bogies).
## Se positionne sur la spline via TunnelBuilder.transform_at(s).

@export var train_length: float = 32.0      # 2 × 16 m
@export var train_radius: float = 1.72      # rayon du tube (TrainBodyBuilder.R_BODY)
@export var car_count: int = 2

var tunnel: TunnelBuilder = null
var physics: TrainPhysics = null

# Noeuds internes
var mesh_root: Node3D = null         # coque extérieure (masquée en FPV)
var interior_root: Node3D = null     # cockpit + sièges + passagers (toujours visibles)
var headlight_front: SpotLight3D = null
var camera_fpv: Camera3D = null
## Loupe sur le pupitre (08/10/2026, Kevin : « on ne peut pas lire les noms
## des boutons ni les chiffres de l'écran du cockpit ») : en 1080p l'écran
## Pro-face ne fait que 230 pixels de large à 78° de champ. Molette ou
## pincement en vue cabine, bouton LOUPE : la caméra pivote vers l'écran et
## le champ se resserre (78° → 32°), en douceur ; 0 = vue normale.
var loupe: float = 0.0
var loupe_cible: float = 0.0
var _cam_fpv_basis_base: Basis = Basis.IDENTITY
var _ecran_loupe: Node3D = null
var camera_ext: Camera3D = null
var interior_light: OmniLight3D = null
# Lumières du poste de conduite : suivent l'éclairage cabine (C). Éteint, il
# ne reste que les écrans et les voyants (retour du 03/10 : « le pupitre est
# éclairé par la cabine sauf si l'éclairage cabine est off »).
var _cockpit_lights: Array[OmniLight3D] = []
# Couche de rendu réservée à la rame : les lumières de la cabine n'éclairent
# qu'elle, jamais le tunnel (« noir, ça veut dire qu'on ne voit rien du
# tout, même à 1 m »).
const LAYER_RAME: int = 1 << 1
# Couche de la voie (rails, longrines, câble) : éclairée, avec les rames,
# par la seule lumière de la vue extérieure.
const LAYER_VOIE: int = 1 << 2
# Intérieur de la cabine, PWA seulement (Compatibility) : les néons des
# gares, renforcés sur le web, ne l'éclairent pas (cf. _couche_interieur)
const LAYER_INTERIEUR: int = 1 << 3
## Masque des lampes de gare renforcées sur le web : tout sauf l'intérieur
## (qui n'a ni la couche 1, ni ne doit être pris par LAYER_RAME).
const MASQUE_GARE_WEB: int = 0xFFFFF & ~(LAYER_INTERIEUR | LAYER_RAME)
var _front_lamps: Array = []         # feux ronds de la calotte avant
var _rear_lamps: Array = []
var _body_mats: Dictionary = {}
# Articulation (2026-09-26) : un nœud par voiture pour la coque
# (_car_roots, sous mesh_root) et pour l'intérieur qui la suit
# (_interior_cars, sous la cabine, visible en FPV). Chacun est replacé
# chaque frame sur la spline à SA propre abscisse (s ∓ 8 m). Le pupitre,
# le siège conducteur, la caméra et les phares restent rigides avec la
# cabine (repère de la vue).
var _car_roots: Array = []
var _interior_cars: Array = []
var _wheels: Array = []              # pivots de roues, tournés à v/R
var _bogies: Array = []              # châssis des bogies (cachés pour le skieur à bord)
var _doors: Array = []               # vantaux coulissants {node, side, base}
var _issues: Array = []              # panneaux d'issue de secours des calottes {node, car, cle}
var issues_retirees: bool = false    # évacuation : les D jaunes sont enlevés
var _door_frac: float = 0.0          # 0 fermé → 1 ouvert (côté le plus ouvert)
var _door_frac_cote: Array[float] = [0.0, 0.0]   # gauche, droite en regardant vers le haut
var _clock_label: Label3D = null     # tablette-horloge du montant gauche
var _pupitre: PupitreConduite = null   # pupitre de conduite (écran, boutons, voyants)
var _clock_next: float = 0.0

# Passagers — références pour animer les têtes selon l'accel/courbure
# Passagers en MultiMesh, une série par voiture : emplacements fixes
# (assis sur les perchoirs, debout en grille), matériel tenu à la main.
# Le nombre affiché suit le remplissage de la physique (pax_car1/2, ou
# ghost_pax pour la rame d'en face) — retour d'essai 2026-09-27.
var _pax_slots: Array = []      # par voiture : Array de {x, z, sit, gear, side}
var _pax_mm: Array = []         # par voiture : {torso, head, ski, pole, board}
var _pax_base: Array = []       # par voiture : {torso: [Transform3D], head: [Transform3D]}
var _pax_gear_prefix: Array = []   # par voiture : {ski: [int], pole: [int], board: [int]}
var _pax_shown: Array = []      # par voiture : nombre affiché
var _pax_noeuds: Array = []     # par voiture : nœud parent des passagers
var _s_pos_roues: float = NAN   # abscisse dessinée à l'image précédente (roues)
var _head_glow: float = 0.0     # phares halogènes : 0 éteint → 1 plein feu
var _head_mat: StandardMaterial3D = null
var head_energy: float = 12.0   # énergie du phare à plein feu (faisceau large depuis le 03/10)
@export var train_number: int = 1
var skieur_a_bord: bool = false        # posé par main : le skieur est dans cette rame
var _prev_v_for_acc: float = 0.0   # vitesse à la frame précédente pour calcul accel

# SKIEUR : le skieur jouable a sa propre caméra (SkieurJoueur), posée par
# main.gd ; la rame s'y voit comme de l'extérieur, passagers compris.
enum ViewMode { FPV, EXTERIOR, MACHINES, SKIEUR }
var view_mode: int = ViewMode.FPV
# Vue « salle des machines » : caméra posée par main.gd dans la gare amont
# (ne suit pas la rame). Null tant qu'elle n'existe pas → cycle à 2 vues.
var camera_machines: MachineRoomCamera = null
var machine_room: MachineRoomBuilder = null

# Secousse d'écran (collision du mode Défi) — décalage aléatoire
# décroissant appliqué à la caméra courante.
var _shake_t: float = 0.0
var _shake_mag: float = 0.0

# Caméra orbitale (vue extérieure) — sphérique autour du centre de la
# rame, dans le repère LOCAL de la cabine (la vue suit l'orientation du
# train comme l'ancienne vue fixe). Défauts = ancienne position (3,10,25).
var orbit_yaw: float = atan2(3.0, 25.0)
var orbit_pitch: float = asin(10.0 / 27.06)
var orbit_dist: float = 27.06


func orbit_rotate(dx: float, dy: float) -> void:
	orbit_yaw -= dx * 0.006
	# jusqu'à −1,2 rad : on passe sous la voie (et sous la montagne, rendue
	# translucide le long du tunnel en vue extérieure)
	orbit_pitch = clampf(orbit_pitch + dy * 0.006, -1.2, 1.35)


## Recul jusqu'à 6 km pour voir le relief 3D du massif (06/10/2026) ; au-delà
## de 150 m, chaque cran de zoom va plus vite.
const ORBIT_DIST_MAX: float = 6000.0

func orbit_zoom(factor: float) -> void:
	if orbit_dist > 150.0:
		factor = pow(factor, 1.8)
	orbit_dist = clampf(orbit_dist * factor, 8.0, ORBIT_DIST_MAX)


func _update_orbit_camera() -> void:
	if camera_ext == null:
		return
	var cp: float = cos(orbit_pitch)
	# plans proche et lointain suivant le recul (précision du tampon de
	# profondeur ; le panorama lointain est à 10 km)
	camera_ext.near = clampf(orbit_dist * 0.01, 0.1, 30.0)
	camera_ext.far = 60000.0   # relief lointain jusqu'à 22 km + recul de 6 km
	camera_ext.position = Vector3(
		orbit_dist * cp * sin(orbit_yaw),
		orbit_dist * sin(orbit_pitch),
		orbit_dist * cp * cos(orbit_yaw))
	if is_inside_tree():
		camera_ext.look_at(
			global_transform.origin + Vector3(0.0, 2.0, 0.0), Vector3.UP)

# Mode ghost : rame 2 (pas de caméra, mesh visible, offset latéral passing loop)
# side = -1 pour rame 1 (voie gauche au passing loop), +1 pour rame 2 ghost
@export var is_ghost: bool = false
@export var passing_side: float = -1.0:
	set(v):
		passing_side = v
		_apply_wheel_types()
var _wheel_dir_applied: int = 0


func _ready() -> void:
	_build_mesh()
	if not is_ghost:
		_build_lights()
		_build_camera()
		# En vue FPV, masquer la cabine elle-même — on est DEDANS.
		# En vue extérieure, on la montre.
		_apply_view_mode()
		_tag_layer_rame(self)
		_tag_layer_rame.call_deferred(self)
		_couche_interieur.call_deferred()
	else:
		# Ghost : mesh toujours visible, pas de caméra. Ses PHARES, oui
		# (retour de Kevin du 06/10/2026 : de la salle des machines on voit
		# le faisceau de la rame qui arrive, quelle qu'elle soit, éclairer
		# peu à peu les parois du tunnel) — même interrupteur que la rame
		# pilotée (physics.lights_head).
		_build_headlight()
		_tag_layer_rame.call_deferred(self)   # éclairée en vue extérieure
		_couche_interieur.call_deferred()
		# (Plus de lumière rouge au centre de la rame — retour du 03/10 :
		# « enlève le feu rouge à l'arrière et le halo rouge qui va avec ».)
		mesh_root.visible = true


func _build_mesh() -> void:
	mesh_root = Node3D.new()
	mesh_root.name = "MeshRoot"
	add_child(mesh_root)

	# Carrosserie réaliste (voir train_body_builder.gd). L'ancien cylindre
	# jaune Ø 3,40 centré 0,15 m sous l'axe descendait à −1,85 : sous la
	# dalle et les rails (retour d'essai 2026-09-26 : « un cylindre qui
	# dépasse même en dessous des rails »).
	# Les deux rames ont le même pare-brise clair et le même intérieur
	# (retour du 06/10/2026, vue salle des machines : « l'autre rame à quai
	# en haut ne contient pas de passagers et la vitre du cockpit est
	# opaque » — la rame d'en face n'avait ni intérieur ni passagers, un
	# disque sombre derrière des vitres teintées).
	var built: Dictionary = TrainBodyBuilder.build_train(mesh_root, train_length, car_count, false)
	_front_lamps = built["front_lamps"]
	_rear_lamps = built["rear_lamps"]
	_body_mats = built["mats"]
	_car_roots = built["car_roots"]
	_wheels = built["wheels"]
	_bogies = built.get("bogies", [])
	_doors = built["doors"]
	_issues = built.get("issues", [])
	for d in _doors:
		d["base"] = (d["node"] as Node3D).position
	# phares de la face AVANT (la cabine est retournée selon le sens de
	# marche : « avant » = tête de train) ; ceux de l'arrière restent des
	# lentilles froides
	_head_mat = (_body_mats["lamp_off"] as StandardMaterial3D).duplicate()
	_head_mat.emission_enabled = true
	for l in _front_lamps:
		(l as MeshInstance3D).set_surface_override_material(0, _head_mat)
	set_train_number(2 if is_ghost else 1)
	_apply_wheel_types()
	# Performance (retour du 30/09 : saccades sur iPad) : roues et pivots
	# de la rame d'en face ne sont dessinés qu'à moins de 150 m — au-delà
	# ils font moins d'un pixel ; la carrosserie, elle, reste visible.
	if is_ghost:
		for w in _wheels:
			var pile: Array = [w]
			while not pile.is_empty():
				var nd: Node = pile.pop_back()
				pile.append_array(nd.get_children())
				if nd is GeometryInstance3D:
					(nd as GeometryInstance3D).visibility_range_end = 150.0
	# Le ghost (rame 2) roule vers nous : ses feux d'extrémité allumés en
	# blanc (elle vient en face). Ses feux arrière restent des lentilles
	# éteintes, comme ceux de la rame pilotée : plus de feux rouges (retour
	# du 03/10 : pas de feu rouge à l'arrière des rames).
	if is_ghost:
		for l in _front_lamps:
			l.set_surface_override_material(0, _body_mats["lamp_on"])

	# --- Intérieur cockpit + sièges + passagers — toujours visible ---------
	_build_interior()
	_merge_static_meshes()
	# Rame d'en face : intérieur et passagers dessinés à moins de 150 m
	# seulement, comme ses roues — au-delà ils font moins d'un pixel
	# derrière les vitres (performance iPad).
	if is_ghost:
		# pas de lampes de poste pour elle : la PWA n'en dessine qu'un
		# nombre limité (cf. v1.15.57) — la gare et le tunnel l'éclairent
		for l in _cockpit_lights:
			(l as Node).queue_free()
		_cockpit_lights.clear()
		var pile: Array = []
		pile.append_array(_interior_cars)
		pile.append_array(_pax_noeuds)
		if interior_root != null:
			pile.append(interior_root)
		while not pile.is_empty():
			var nd: Node = pile.pop_back()
			pile.append_array(nd.get_children())
			if nd is GeometryInstance3D:
				(nd as GeometryInstance3D).visibility_range_end = 150.0


## Performance (retour du 30/09 : le tunnel saccade toujours sur iPad) :
## ~400 MeshInstance3D → une centaine d'appels de dessin en vue cabine. Les
## pièces fixes de chaque voiture (coque, habillage, sièges, pupitre) sont
## fusionnées par matériau ; roues, vantaux et feux restent animables.
func _merge_static_meshes() -> void:
	if "--sans-fusion" in OS.get_cmdline_user_args():   # comparaison visuelle
		return
	var keep: Array = []
	keep.append_array(_wheels)
	keep.append_array(_bogies)
	keep.append_array(_front_lamps)
	keep.append_array(_rear_lamps)
	for d in _doors:
		keep.append(d["node"])
	for e in _issues:
		keep.append(e["node"])       # les issues de secours s'enlèvent : pas fusionnées
	var roots: Array = []
	roots.append_array(_car_roots)
	roots.append_array(_interior_cars)
	if interior_root != null:
		roots.append(interior_root)
	for r in roots:
		MeshMerge.merge(r as Node3D, keep)
	# roues : chaque pivot tourne d'un bloc ; ses deux variantes (boudin
	# guidé / roue plate, cf. _apply_wheel_types) sont fusionnées à part
	for w in _wheels:
		var variantes: Array = []
		for nom in ["Boudin", "Plate"]:
			var v: Node = (w as Node).get_node_or_null(nom)
			if v != null:
				variantes.append(v)
				MeshMerge.merge(v as Node3D)
		MeshMerge.merge(w as Node3D, variantes)
	for b in _bogies:
		MeshMerge.merge(b as Node3D)
	print("[Cabin%s] maillages fixes fusionnés : %d surfaces restantes" % [
		" ghost" if is_ghost else "", _count_surfaces(self)])


## Le skieur à bord ne voit ni roues ni châssis de bogie : le plancher n'est
## qu'à 13 cm du rail, ils dépasseraient dans la voiture (08/10/2026).
func set_bogies_visibles(on: bool) -> void:
	for w in _wheels:
		if is_instance_valid(w):
			(w as Node3D).visible = on
	for b in _bogies:
		if is_instance_valid(b):
			(b as Node3D).visible = on


static func _count_surfaces(n: Node) -> int:
	var k: int = 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		k += (n as MeshInstance3D).mesh.get_surface_count()
	for c in n.get_children():
		k += _count_surfaces(c)
	return k


# ---------------------------------------------------------------------------
# Intérieur cabine — dashboard cockpit, sièges, passagers
# Toujours visible (en FPV on regarde l'intérieur, en EXT la coque cache)
# ---------------------------------------------------------------------------

## Parent intérieur d'un élément d'abscisse z (repère rame) : la voiture
## qui le contient, avec z ramené au repère de la voiture.
func _interior_parent(z: float) -> Dictionary:
	var car_len: float = train_length / float(car_count)
	var idx: int = clampi(int(floor((z + train_length * 0.5) / car_len)), 0, car_count - 1)
	var z_c: float = (float(idx) - (car_count - 1) * 0.5) * car_len
	return {"node": _interior_cars[idx], "z": z - z_c}


## Boîte intérieure allongée selon z, scindée aux limites de voiture.
func _add_interior_box(mat: StandardMaterial3D, sx: float, sy: float, y: float,
		z0: float, z1: float, name: String) -> void:
	var car_len: float = train_length / float(car_count)
	for idx in range(car_count):
		var z_c: float = (float(idx) - (car_count - 1) * 0.5) * car_len
		var za: float = maxf(z0, z_c - car_len * 0.5)
		var zb: float = minf(z1, z_c + car_len * 0.5)
		if zb - za < 0.05:
			continue
		var bm: BoxMesh = BoxMesh.new()
		bm.size = Vector3(sx, sy, zb - za)
		bm.material = mat
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "%s%d" % [name, idx + 1]
		mi.mesh = bm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0.0, y, (za + zb) * 0.5 - z_c)
		_interior_cars[idx].add_child(mi)


func _build_interior() -> void:
	var car_len: float = train_length / float(car_count)
	for idx in range(car_count):
		var n: Node3D = Node3D.new()
		n.name = "InteriorCar%d" % (idx + 1)
		n.position = Vector3(0.0, 0.0, (float(idx) - (car_count - 1) * 0.5) * car_len)
		add_child(n)
		_interior_cars.append(n)
	# Poste de conduite (pupitre, siège, moniteur…) : coordonnées dans le
	# repère de la rame, mais porté par la VOITURE DE TÊTE, comme la caméra
	# et la coque (retour du 01/10) — accroché au centre de la rame, il
	# bougeait par rapport au pare-brise dans les courbes et les changements
	# de pente.
	interior_root = Node3D.new()
	interior_root.name = "Interior"
	interior_root.position = Vector3(0.0, 0.0, -(_interior_cars[0] as Node3D).position.z)
	(_interior_cars[0] as Node3D).add_child(interior_root)
	_build_floor_ceiling()
	_build_console_pupitre()     # pupitre Von Roll fin (tube horizontal blanc)
	_build_cockpit_extras()      # coups-de-poing, étiquettes, horloge, panneau latéral
	_build_cctv_monitor()        # petit moniteur 4 caméras plafond gauche
	_build_driver_seat()
	_build_passenger_seats()
	if not "--sans-pax" in OS.get_cmdline_user_args():     # diagnostic de performance
		_build_passengers()
	_build_handrails()


func _build_floor_ceiling() -> void:
	# Limite AVANT de l'intérieur visible : dans la vraie cabine, le
	# plancher et le plafond s'arrêtent au pare-brise, ~1,6 m devant les
	# yeux du conducteur (caméra FPV à −train_length/2 + 4,0). Les boîtes
	# étaient centrées sur z=0 et couvraient 97 % du train → 3,5 m de
	# plancher/plafond en porte-à-faux DEVANT le poste de pilotage, comme
	# un plongeoir au-dessus de la voie.
	var z_front: float = -train_length * 0.5 + 0.55   # plancher jusqu'à la doublure de la calotte (|x| ≤ 1,0)
	# Plafond + bandeau LED : encore plus courts (retour d'essai : « un
	# plafond qui avance moins vers l'avant au-dessus de nous ») —
	# 0,4 m devant la caméra seulement, simple casquette.
	var z_front_ceil: float = -train_length * 0.5 + 1.0   # la calotte se referme à z_join à |x| = 1,2
	var z_rear: float = train_length * 0.5 * 0.97

	# Sol cabine — plancher caillebotis sombre (matériau acier mat),
	# bien plus contrasté que la dalle béton du tunnel pour qu'on
	# distingue clairement "intérieur" vs "voie" depuis le siège.
	# Paliers couverts d'un tapis de caoutchouc noir alvéolé (photos FUNI-334
	# « l'intérieur », « détail d'un couloir » ; Kevin, 07/10/2026 : « un
	# palier au travers de chaque vitre, recouvert d'un matelas noir en
	# caoutchouc classique ») : trous ronds en quinconce, pas de 4 cm.
	var floor_mat: StandardMaterial3D = _mat_tapis()

	# Plancher EN GRADINS (vidéo cabine f_001/f_002 : une marche par
	# cerceau ; paliers horizontaux à la pente des gares, FLOOR_GRADE),
	# scindé par voiture pour suivre l'articulation.
	_build_stepped_floor(floor_mat, z_front, z_rear)
	# plancher du passage d'intercirculation, entre les deux voitures
	# (09/10/2026 : on passe d'une voiture à l'autre en marchant)
	var car_len_p: float = train_length / float(car_count)
	for idx in range(car_count - 1):
		var pl: BoxMesh = BoxMesh.new()
		pl.size = Vector3(2.0 * TrainBodyBuilder.PASSAGE_DEMI_L + 0.2, 0.06, 0.8)
		pl.material = _mat_tapis()
		var pm: MeshInstance3D = MeshInstance3D.new()
		pm.name = "PlancherPassage%d" % (idx + 1)
		pm.mesh = pl
		pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pm.position = Vector3(0.0, TrainBodyBuilder.Y_FLOOR + STEP_LIFT - 0.03, car_len_p * 0.5)
		_interior_cars[idx].add_child(pm)

	# Plafond cabine — surface plate visible quand on lève les yeux
	var ceil_mat: StandardMaterial3D = StandardMaterial3D.new()
	ceil_mat.albedo_color = Color(0.80, 0.69, 0.53)      # beige des panneaux (photos)
	# éclairé par les spots, il paraît clair sur les photos (il restait brun)
	ceil_mat.emission_enabled = true
	ceil_mat.emission = Color(0.80, 0.69, 0.53)
	ceil_mat.emission_energy_multiplier = 0.25
	ceil_mat.roughness = 0.70
	ceil_mat.metallic = 0.15

	_add_interior_box(ceil_mat, 2.40, 0.04, 1.45, z_front_ceil, z_rear, "InteriorCeiling")

	# Bandeau central du plafond : grille de ventilation gris foncé perforée
	# sur toute la longueur, spots ronds encastrés (photos de l'intérieur,
	# Kevin, 09/10/2026 — avant : un bandeau LED blanc continu)
	var grille: StandardMaterial3D = _mat_grille_plafond()
	var led_z_rear: float = train_length * 0.5 * 0.92
	_add_interior_box(grille, 0.55, 0.04, 1.42, z_front_ceil, led_z_rear, "InteriorLEDStrip")
	var spot_mat: StandardMaterial3D = StandardMaterial3D.new()
	spot_mat.albedo_color = Color(1.0, 1.0, 0.97)
	spot_mat.emission_enabled = true
	spot_mat.emission = Color(1.0, 0.98, 0.92)
	spot_mat.emission_energy_multiplier = 2.2
	spot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var car_len2: float = train_length / float(car_count)
	for idx in range(car_count):
		var z_c2: float = (float(idx) - (car_count - 1) * 0.5) * car_len2
		var z: float = maxf(z_front_ceil, z_c2 - car_len2 * 0.5) + 1.0
		while z < minf(led_z_rear, z_c2 + car_len2 * 0.5) - 0.5:
			var cy: CylinderMesh = CylinderMesh.new()
			cy.top_radius = 0.07
			cy.bottom_radius = 0.07
			cy.height = 0.012
			cy.radial_segments = 16
			cy.material = spot_mat
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.mesh = cy
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(0.0, 1.395, z - z_c2)
			_interior_cars[idx].add_child(mi)
			z += 2.3


## Grille perforée gris foncé du plafond (petits trous en quinconce).
static func _mat_grille_plafond() -> StandardMaterial3D:
	var n: int = 16
	var img: Image = Image.create(n, n, true, Image.FORMAT_RGB8)
	for y in range(n):
		for x in range(n):
			var trou: bool = (Vector2(x % 8, y % 8) - Vector2(4, 4)).length() < 1.6 \
				or (Vector2((x + 4) % 8, (y + 4) % 8) - Vector2(4, 4)).length() < 1.6
			img.set_pixel(x, y, Color(0.10, 0.10, 0.11) if trou else Color(0.33, 0.33, 0.34))
	img.generate_mipmaps()
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_scale = Vector3(14.0, 1.0, 400.0)
	m.roughness = 0.8
	m.metallic = 0.2
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Tapis de caoutchouc alvéolé : fond noir, trous ronds en quinconce où
## l'on devine le plancher brun-orangé.
static var _tapis: StandardMaterial3D = null


static func _mat_tapis() -> StandardMaterial3D:
	if _tapis != null:
		return _tapis
	var n: int = 32
	var img: Image = Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in range(n):
		for x in range(n):
			var c: Color = Color(0.045, 0.045, 0.05)
			# deux trous par motif, en quinconce
			for ctr in [Vector2(8, 8), Vector2(24, 24)]:
				var d: Vector2 = Vector2(x + 0.5, y + 0.5) - ctr
				if d.length() < 5.2:
					c = Color(0.22, 0.10, 0.04).lerp(Color(0.02, 0.02, 0.02), clampf(d.length() / 5.2, 0.0, 1.0) * 0.5)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	_tapis = StandardMaterial3D.new()
	_tapis.albedo_texture = ImageTexture.create_from_image(img)
	_tapis.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_tapis.uv1_triplanar = true
	_tapis.uv1_scale = Vector3(1.0, 1.0, 1.0) / 0.04
	_tapis.roughness = 0.9
	return _tapis


# Pente de construction des paliers (et des bancs, des porte-skis posés
# dessus) : celle des GARES. Fait de Kevin, 07/10/2026 : « les bancs sont
# horizontaux lorsque la pente du wagon est celle des gares » — rame à
# quai, tout est de niveau ; en pleine ligne (30 %), l'avant (amont) est
# 11,8° plus haut. 8,57 % = moyenne des pentes des 4 voitures rame arrêtée
# (audit_physique/pente_paliers.sage ; écart en gare ≤ 0,73°). Avant :
# 26,5 %, la pente moyenne de la ligne, qui penchait les bancs de 10°
# l'arrière en l'air à quai.
const FLOOR_GRADE: float = 0.0857
# Relèvement des paliers : le bord AVANT (bas) de chaque palier affleure le
# plancher plat de la caisse (Y_FLOOR), le bord arrière est 12 cm plus
# haut, et la contremarche est entière. Sans lui, la moitié avant de chaque
# palier passait SOUS le plancher et on ne voyait que des biseaux (retour
# d'essai 2026-09-27 : « un plancher en escalier comme sur les photos »).
const STEP_LIFT: float = (TrainBodyBuilder.PANEL_L + TrainBodyBuilder.RIB_W) * FLOOR_GRADE * 0.5   # (PANEL_L + RIB_W) · pente / 2


## Centre (repère rame) du cerceau k de la voiture idx, et bornes de sa dalle.
func _panel_center(idx: int, k: int) -> float:
	var car_len: float = train_length / float(car_count)
	var z_c: float = (float(idx) - (car_count - 1) * 0.5) * car_len
	var z_a: float = -car_len * 0.5 + (TrainBodyBuilder.CAP_LEN if idx == 0 else TrainBodyBuilder.GAP * 0.5)
	var pitch: float = TrainBodyBuilder.PANEL_L + TrainBodyBuilder.RIB_W
	return z_c + z_a + TrainBodyBuilder.END_BLANK + TrainBodyBuilder.RIB_W + pitch * float(k) \
		+ TrainBodyBuilder.PANEL_L * 0.5


## Hauteur du plancher (repère rame) à l'abscisse z : palier du cerceau
## contenant z, horizontal sur la pente moyenne (monte vers l'arrière +Z
## dans le repère de la voiture, qui a le nez en l'air).
func _floor_y_at(z: float) -> float:
	var car_len: float = train_length / float(car_count)
	var idx: int = clampi(int(floor((z + train_length * 0.5) / car_len)), 0, car_count - 1)
	var pitch: float = TrainBodyBuilder.PANEL_L + TrainBodyBuilder.RIB_W
	var k: int = clampi(int(round((z - _panel_center(idx, 0)) / pitch)), 0, TrainBodyBuilder.N_PANNEAUX - 1)
	return TrainBodyBuilder.Y_FLOOR + STEP_LIFT + (z - _panel_center(idx, k)) * FLOOR_GRADE


func _build_stepped_floor(mat: StandardMaterial3D, z_front: float, z_rear: float) -> void:
	var pitch: float = TrainBodyBuilder.PANEL_L + TrainBodyBuilder.RIB_W
	var tilt: float = -atan(FLOOR_GRADE)
	var riser_mat: StandardMaterial3D = StandardMaterial3D.new()
	riser_mat.albedo_color = Color(0.55, 0.55, 0.57)   # nez de marche alu
	riser_mat.roughness = 0.4
	riser_mat.metallic = 0.5
	for idx in range(car_count):
		var car_len: float = train_length / float(car_count)
		var z_c: float = (float(idx) - (car_count - 1) * 0.5) * car_len
		for k in range(TrainBodyBuilder.N_PANNEAUX):
			var zc: float = _panel_center(idx, k)
			if zc + pitch * 0.5 < z_front or zc - pitch * 0.5 > z_rear:
				continue
			var land: MeshInstance3D = MeshInstance3D.new()
			var lm: BoxMesh = BoxMesh.new()
			lm.size = Vector3(2.40, 0.05, pitch)
			lm.material = mat
			land.mesh = lm
			land.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			land.position = Vector3(0.0, TrainBodyBuilder.Y_FLOOR + STEP_LIFT, zc - z_c)
			land.rotation = Vector3(tilt, 0.0, 0.0)
			land.name = "Palier%d_%d" % [idx + 1, k]
			_interior_cars[idx].add_child(land)
			if k < TrainBodyBuilder.N_PANNEAUX - 1:
				# contremarche au joint (le palier arrière est 12 cm plus bas)
				var rz: float = zc + pitch * 0.5
				var riser: MeshInstance3D = MeshInstance3D.new()
				var rm: BoxMesh = BoxMesh.new()
				rm.size = Vector3(2.40, pitch * FLOOR_GRADE, 0.03)
				rm.material = riser_mat
				riser.mesh = rm
				riser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				riser.position = Vector3(0.0, TrainBodyBuilder.Y_FLOOR + STEP_LIFT, rz - z_c)
				riser.rotation = Vector3(tilt, 0.0, 0.0)
				_interior_cars[idx].add_child(riser)


func _build_handrails() -> void:
	# Barres d'appui ORANGE au-dessus des vitres, sur la paroi, une par
	# panneau vitré, tenues par deux pattes (photos de l'intérieur, Kevin,
	# 09/10/2026). Plus de mains courantes chromées au plafond : les photos
	# n'en montrent pas.
	var orange: StandardMaterial3D = StandardMaterial3D.new()
	orange.albedo_color = Color(0.95, 0.47, 0.10)
	orange.roughness = 0.45
	var th: float = deg_to_rad(TrainBodyBuilder.WIN_T0 - 5.0)
	var r_barre: float = TrainBodyBuilder.R_BODY - 0.17
	var r_patte: float = TrainBodyBuilder.R_BODY - 0.05
	var car_len_r: float = train_length / float(car_count)
	for idx in range(car_count):
		var z_c: float = (float(idx) - (car_count - 1) * 0.5) * car_len_r
		for k in range(TrainBodyBuilder.N_PANNEAUX):
			if TrainBodyBuilder.KINDS[k] != "win":
				continue
			# pas dans le poste ni au fond de la voiture de queue
			if (idx == 0 and k == 0) or (idx == car_count - 1 and k == TrainBodyBuilder.N_PANNEAUX - 1):
				continue
			var zc: float = _panel_center(idx, k) - z_c
			var l: float = TrainBodyBuilder.PANEL_L * 0.72
			for side in [-1.0, 1.0]:
				var p: Vector3 = Vector3(side * r_barre * sin(th), TrainBodyBuilder.Y_CENTER + r_barre * cos(th), zc)
				var barre: CylinderMesh = CylinderMesh.new()
				barre.top_radius = 0.016
				barre.bottom_radius = 0.016
				barre.height = l
				barre.radial_segments = 8
				barre.material = orange
				var mi: MeshInstance3D = MeshInstance3D.new()
				mi.mesh = barre
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.position = p
				mi.rotation = Vector3(PI * 0.5, 0.0, 0.0)
				_interior_cars[idx].add_child(mi)
				for e in [-1.0, 1.0]:
					var q: Vector3 = Vector3(side * r_patte * sin(th), TrainBodyBuilder.Y_CENTER + r_patte * cos(th), zc + e * l * 0.42)
					var a: Vector3 = Vector3(p.x, p.y, q.z)
					var patte: CylinderMesh = CylinderMesh.new()
					patte.top_radius = 0.012
					patte.bottom_radius = 0.012
					patte.height = a.distance_to(q)
					patte.radial_segments = 6
					patte.material = orange
					var pm: MeshInstance3D = MeshInstance3D.new()
					pm.mesh = patte
					pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					var y_ax: Vector3 = (q - a).normalized()
					var x_ax: Vector3 = y_ax.cross(Vector3.BACK).normalized()
					pm.transform = Transform3D(Basis(x_ax, y_ax, x_ax.cross(y_ax)), (a + q) * 0.5)
					_interior_cars[idx].add_child(pm)


# ---------------------------------------------------------------------------
# Pupitre conducteur Von Roll — tube horizontal blanc fin, calé en bas
# de l'écran (y=0.40, bien sous l'horizon du regard à y=0.85). Sur la
# face supérieure : écran tactile vert, 8 voyants LED verts (POSTE/PORTES),
# 4 voyants blancs (FREINS/ÉCLAIRAGE), 2 mushrooms rouges aux extrémités.
# Position et taille calées pour NE JAMAIS masquer la vue tunnel droit
# devant : le pupitre tient dans le bas de l'image, vue centrale dégagée.
# ---------------------------------------------------------------------------

func _build_console_pupitre() -> void:
	# Pupitre reproduit d'après les photos de Kevin et la vidéo de 2013
	# (PupitreConduite : caisson, écran Pro-face vivant, plaque à boutons
	# aux vrais libellés, voyants suivant l'état de la rame) — 06/10/2026.
	var z_console: float = -train_length * 0.5 + 0.45   # tube contre la doublure sous le pare-brise (z_face ≈ −15,9)
	var y_top: float = 0.52                            # face du pupitre
	_pupitre = PupitreConduite.new()
	_pupitre.name = "PupitreConduite"
	interior_root.add_child(_pupitre)
	# face perpendiculaire au regard : œil = caméra cabine (_build_camera)
	_pupitre.construire(z_console, y_top, _cockpit_lights,
		Vector3(0.0, 0.85, -train_length * 0.5 + 1.1))

	# ----- Plafonnier du poste : la lumière de la cabine (celle du milieu
	# de la rame, à 15 m, n'atteint pas le pupitre) ----------------------
	var plafonnier: OmniLight3D = OmniLight3D.new()
	plafonnier.position = Vector3(0.0, y_top + 1.05, z_console + 0.75)
	plafonnier.light_color = Color(1.0, 0.90, 0.72)
	plafonnier.light_energy = 0.9
	plafonnier.omni_range = 2.6
	plafonnier.shadow_enabled = false
	plafonnier.light_cull_mask = LAYER_RAME
	plafonnier.light_volumetric_fog_energy = 0.0   # pas de brouillard dans la cabine
	interior_root.add_child(plafonnier)
	_cockpit_lights.append(plafonnier)


# ---------------------------------------------------------------------------
# Moniteur CCTV plafond — plaque noire avec 4 cellules bleu nuit (réplique
# du moniteur 2×2 visible en haut à gauche du pare-brise sur toutes les
# photos du vrai cockpit Perce-Neige). Cellules émissives.
# ---------------------------------------------------------------------------

## Compléments du poste d'après les photos 095119 / 094402 / 094413 :
## deux coups-de-poing rouges à gauche de l'écran, combiné à l'extrémité
## gauche, étiquettes des groupes, pastille rouge à droite du tube,
## tablette-horloge sur le montant gauche, panneau latéral à boutons avec
## levier et boîtier rouge, grille de ventilation à lamelles.
func _build_cockpit_extras() -> void:
	var z_console: float = -train_length * 0.5 + 0.45   # tube contre la doublure sous le pare-brise (z_face ≈ −15,9)
	# montant gauche : la calotte se referme vite à |x| ≈ 1 m (z_face ≈
	# −15,7) → panneau, levier, grille et tablette restent en arrière
	var z_side: float = -train_length * 0.5 + 1.15
	var y_top: float = 0.52
	var tilt: float = 0.07
	var red: StandardMaterial3D = StandardMaterial3D.new()
	red.albedo_color = Color(0.80, 0.08, 0.06)
	red.roughness = 0.45
	var black: StandardMaterial3D = StandardMaterial3D.new()
	black.albedo_color = Color(0.08, 0.08, 0.09)
	black.roughness = 0.6
	var grey: StandardMaterial3D = StandardMaterial3D.new()
	grey.albedo_color = Color(0.62, 0.62, 0.60)
	grey.roughness = 0.6
	var beige: StandardMaterial3D = StandardMaterial3D.new()
	beige.albedo_color = Color(0.72, 0.70, 0.62)
	beige.roughness = 0.7
	var slat: StandardMaterial3D = StandardMaterial3D.new()
	slat.albedo_color = Color(0.55, 0.56, 0.55)
	slat.roughness = 0.5
	slat.metallic = 0.3
	var screen_dark: StandardMaterial3D = StandardMaterial3D.new()
	screen_dark.albedo_color = Color(0.06, 0.07, 0.10)
	screen_dark.emission_enabled = true
	screen_dark.emission = Color(0.10, 0.12, 0.18)
	screen_dark.emission_energy_multiplier = 0.5
	screen_dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# (coups-de-poing rouges : sur la face du pupitre, PupitreConduite)
	# combiné / boîtier à l'extrémité gauche du tube
	var phone: MeshInstance3D = MeshInstance3D.new()
	var pm: BoxMesh = BoxMesh.new()
	pm.size = Vector3(0.10, 0.05, 0.09)
	pm.material = grey
	phone.mesh = pm
	phone.position = Vector3(-0.66, y_top - 0.02, z_console + 0.06)
	interior_root.add_child(phone)
	# pastille rouge à l'extrémité droite du tube (face avant)
	var dot: MeshInstance3D = _cyl(red, 0.035, 0.006,
		Vector3(0.50, y_top - 0.03 - PupitreConduite.R_TUBE, z_console - PupitreConduite.R_TUBE - 0.004))
	dot.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	interior_root.add_child(dot)
	# tablette-horloge sur le montant gauche, tournée vers le conducteur
	var tab: MeshInstance3D = MeshInstance3D.new()
	var tm: BoxMesh = BoxMesh.new()
	tm.size = Vector3(0.17, 0.11, 0.014)
	tm.material = black
	tab.mesh = tm
	tab.position = Vector3(-0.98, 0.98, z_side - 0.60)
	tab.rotation = Vector3(0.0, 0.55, 0.0)
	interior_root.add_child(tab)
	var scr: MeshInstance3D = MeshInstance3D.new()
	var sm: BoxMesh = BoxMesh.new()
	sm.size = Vector3(0.15, 0.09, 0.004)
	sm.material = screen_dark
	scr.mesh = sm
	scr.position = Vector3(0.0, 0.0, 0.009)
	tab.add_child(scr)
	_clock_label = Label3D.new()
	_clock_label.text = "--:--"
	_clock_label.font_size = 40
	_clock_label.pixel_size = 0.0009
	_clock_label.modulate = Color(0.85, 0.88, 0.95)
	_clock_label.position = Vector3(0.0, 0.0, 0.013)
	tab.add_child(_clock_label)
	# panneau latéral gauche : plaque beige, 4 boutons ronds, levier, boîtier rouge
	var panel: MeshInstance3D = MeshInstance3D.new()
	var pnm: BoxMesh = BoxMesh.new()
	pnm.size = Vector3(0.02, 0.42, 0.30)
	pnm.material = beige
	panel.mesh = pnm
	panel.position = Vector3(-1.06, 0.62, z_side)
	interior_root.add_child(panel)
	for r in range(2):
		for k in range(2):
			var b: MeshInstance3D = _cyl(black, 0.017, 0.014,
				Vector3(-1.04, 0.72 - float(r) * 0.09, z_side - 0.07 + float(k) * 0.10))
			b.rotation = Vector3(0.0, 0.0, PI * 0.5)
			interior_root.add_child(b)
	var lever: MeshInstance3D = MeshInstance3D.new()
	var lvm: BoxMesh = BoxMesh.new()
	lvm.size = Vector3(0.09, 0.025, 0.025)
	lvm.material = black
	lever.mesh = lvm
	lever.position = Vector3(-1.00, 0.52, z_side - 0.05)
	lever.rotation = Vector3(0.0, 0.0, -0.5)
	interior_root.add_child(lever)
	var rbox: MeshInstance3D = MeshInstance3D.new()
	var rbm: BoxMesh = BoxMesh.new()
	rbm.size = Vector3(0.03, 0.05, 0.05)
	rbm.material = red
	rbox.mesh = rbm
	rbox.position = Vector3(-1.04, 0.48, z_side + 0.11)
	interior_root.add_child(rbox)
	# grille de ventilation à lamelles horizontales, plus haut sur le montant
	for k in range(12):
		var sl: MeshInstance3D = MeshInstance3D.new()
		var slm: BoxMesh = BoxMesh.new()
		slm.size = Vector3(0.012, 0.014, 0.34)
		slm.material = slat
		sl.mesh = slm
		sl.position = Vector3(-1.08, 0.70 + float(k) * 0.032, z_side - 0.40)
		sl.rotation = Vector3(0.35, 0.0, 0.0)
		interior_root.add_child(sl)


func _cyl(mat: StandardMaterial3D, r: float, h: float, pos: Vector3) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 16
	cm.material = mat
	mi.mesh = cm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	return mi


func _build_cctv_monitor() -> void:
	# Petit moniteur discret au plafond avant gauche, taille 24×15 cm
	# (vs 32×22 cm précédemment qui prenait trop de place visuelle).
	# Positionné haut (y=1.50) et loin sur le côté gauche (x=-1.0)
	# pour qu'il ne soit visible qu'en levant les yeux à gauche, jamais
	# en regardant droit devant.
	# Accroché juste EN DEDANS du nouveau front du plafond (z_front=−13.6,
	# cf. _build_floor_ceiling) — avant il pendait à −14.6, au-delà du
	# plafond raccourci, donc flottait dans le vide.
	var z_mon: float = -train_length * 0.5 + 1.2
	var bezel_mat: StandardMaterial3D = StandardMaterial3D.new()
	bezel_mat.albedo_color = Color(0.05, 0.05, 0.06)
	bezel_mat.roughness = 0.5
	bezel_mat.metallic = 0.2

	var screen_mat: StandardMaterial3D = StandardMaterial3D.new()
	screen_mat.albedo_color = Color(0.05, 0.08, 0.14)
	screen_mat.emission_enabled = true
	screen_mat.emission = Color(0.20, 0.40, 0.65)
	screen_mat.emission_energy_multiplier = 0.45
	screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "CctvBody"
	var body_mesh: BoxMesh = BoxMesh.new()
	body_mesh.size = Vector3(0.24, 0.15, 0.03)
	body_mesh.material = bezel_mat
	body.mesh = body_mesh
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.position = Vector3(-1.00, 1.50, z_mon)
	body.rotation = Vector3(-0.20, 0.35, 0.0)   # incliné face au conducteur
	interior_root.add_child(body)

	# 4 cellules 2×2 émissives (alignées avec la rotation du body)
	var ang: float = 0.35
	var c_ang: float = cos(ang)
	var s_ang: float = sin(ang)
	for r in range(2):
		for c in range(2):
			var cell: MeshInstance3D = MeshInstance3D.new()
			var cell_mesh: BoxMesh = BoxMesh.new()
			cell_mesh.size = Vector3(0.105, 0.065, 0.004)
			cell_mesh.material = screen_mat
			cell.mesh = cell_mesh
			cell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var dx: float = (-0.058 + float(c) * 0.116)
			var dy: float = (+0.036 - float(r) * 0.072)
			cell.position = Vector3(
				-1.00 + dx * c_ang,
				1.50 + dy,
				z_mon - dx * s_ang + 0.017)
			cell.rotation = Vector3(-0.20, ang, 0.0)
			interior_root.add_child(cell)


func _build_driver_seat() -> void:
	# Siège du conducteur, derrière le dashboard
	var z_seat: float = -train_length * 0.5 + 1.4   # 0,3 m derrière la caméra

	var seat_mat: StandardMaterial3D = StandardMaterial3D.new()
	seat_mat.albedo_color = Color(0.18, 0.18, 0.22)
	seat_mat.roughness = 0.85
	seat_mat.metallic = 0.0

	# Assise
	var base: MeshInstance3D = MeshInstance3D.new()
	base.name = "DriverSeatBase"
	var base_mesh: BoxMesh = BoxMesh.new()
	base_mesh.size = Vector3(0.55, 0.10, 0.55)
	base_mesh.material = seat_mat
	base.mesh = base_mesh
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	base.position = Vector3(0.0, _floor_y_at(z_seat) + 0.50, z_seat)
	interior_root.add_child(base)

	# Dossier
	var back: MeshInstance3D = MeshInstance3D.new()
	back.name = "DriverSeatBack"
	var back_mesh: BoxMesh = BoxMesh.new()
	back_mesh.size = Vector3(0.55, 0.85, 0.10)
	back_mesh.material = seat_mat
	back.mesh = back_mesh
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	back.position = Vector3(0.0, _floor_y_at(z_seat) + 0.95, z_seat + 0.30)
	interior_root.add_child(back)


## Aménagement des paliers (photos FUNI-334 « l'intérieur », « les sièges,
## disposés en escalier à cause de l'inclinaison » ; Kevin, 07/10/2026) :
##  - le long des parois courbes, sous chaque hublot, un banc moulé bleu
##    clair ; pas de banc au droit des portes → deux bancs pour trois
##    cerceaux de chaque côté ;
##  - sur chaque palier, deux porte-skis en tube orange, décalés d'un palier
##    sur deux (en quinconce).
## Chaque palier est horizontal : bancs et porte-skis sont posés dans son
## repère (même inclinaison que la dalle).
const BANC_BLEU: Color = Color(0.56, 0.72, 0.88)
const ORANGE_RACK: Color = Color(1.0, 0.45, 0.05)
const RACK_DZ: float = (TrainBodyBuilder.PANEL_L + TrainBodyBuilder.RIB_W) * 0.5 - 0.17   # porte-skis vers l'arrière du palier
const RACK_L: float = 0.50            # largeur (en travers)
const RACK_P: float = 0.30            # profondeur
const RACK_H: float = 1.00


## Abscisses des deux porte-skis du palier k (quinconce).
static func racks_x(k: int) -> Array:
	return [-0.42, 0.16] if k % 2 == 0 else [-0.16, 0.42]


func _build_passenger_seats() -> void:
	var bleu: StandardMaterial3D = StandardMaterial3D.new()
	bleu.albedo_color = BANC_BLEU
	bleu.roughness = 0.35
	var orange: StandardMaterial3D = StandardMaterial3D.new()
	orange.albedo_color = ORANGE_RACK
	orange.roughness = 0.45
	var gris: StandardMaterial3D = StandardMaterial3D.new()
	gris.albedo_color = Color(0.55, 0.56, 0.58)
	gris.metallic = 0.6
	gris.roughness = 0.4
	var tilt: float = -atan(FLOOR_GRADE)
	var car_len: float = train_length / float(car_count)
	for idx in range(car_count):
		var z_c: float = (float(idx) - (car_count - 1) * 0.5) * car_len
		for k in range(TrainBodyBuilder.N_PANNEAUX):
			if idx == 0 and k == 0:
				continue                 # poste de conduite
			var pal: Node3D = Node3D.new()
			pal.name = "Amenagement%d_%d" % [idx + 1, k]
			pal.position = Vector3(0.0, TrainBodyBuilder.Y_FLOOR + STEP_LIFT + 0.025, _panel_center(idx, k) - z_c)
			pal.rotation = Vector3(tilt, 0.0, 0.0)
			_interior_cars[idx].add_child(pal)
			if TrainBodyBuilder.KINDS[k] == "win":
				for side in [-1.0, 1.0]:
					_banc(pal, side, bleu)
			for xr in racks_x(k):
				_porte_skis(pal, xr, orange, gris)


func _piece(parent: Node3D, mesh: Mesh, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _cube(m: StandardMaterial3D, taille: Vector3) -> BoxMesh:
	var b: BoxMesh = BoxMesh.new()
	b.size = taille
	b.material = m
	return b


func _tube(m: StandardMaterial3D, r: float, h: float) -> CylinderMesh:
	var c: CylinderMesh = CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	c.rings = 1
	c.material = m
	return c


## Banc moulé bleu clair contre la paroi (assise à 0,45 m, lèvre avant
## arrondie, jupe en retrait, dossier jusqu'au bas du hublot).
func _banc(pal: Node3D, side: float, m: StandardMaterial3D) -> void:
	var l: float = TrainBodyBuilder.PANEL_L - 0.12
	_piece(pal, _cube(m, Vector3(0.40, 0.06, l)), Vector3(side * 0.93, 0.42, 0.0))
	_piece(pal, _tube(m, 0.045, l), Vector3(side * 0.74, 0.415, 0.0), Vector3(PI * 0.5, 0.0, 0.0))
	_piece(pal, _cube(m, Vector3(0.04, 0.38, l)), Vector3(side * 0.82, 0.20, 0.0))
	_piece(pal, _cube(m, Vector3(0.05, 0.24, l)), Vector3(side * 1.15, 0.56, 0.0), Vector3(0.0, 0.0, side * 0.28))


## Porte-skis en tube orange cintré (photos FUNI-334 « l'intérieur » de
## face et « détail d'un couloir » de profil ; Kevin, 07/10/2026 : « affine
## la forme des porte-skis ») : deux arceaux en ∩ à coins arrondis (avant
## et arrière), reliés en haut par deux traverses ; chaque pied monte droit,
## fait un décrochement en baïonnette vers mi-hauteur, puis remonte droit ;
## embouts gris au sol.
const RACK_CRAN_Y0: float = 0.42      # début du décrochement
const RACK_CRAN_Y1: float = 0.62      # fin du décrochement
const RACK_CRAN: float = 0.11         # décalage du décrochement (vers l'avant)
const RACK_R_TUBE: float = 0.021
const RACK_R_COIN: float = 0.09


func _porte_skis(pal: Node3D, x: float, orange: StandardMaterial3D, gris: StandardMaterial3D) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0: float = x - RACK_L * 0.5
	var x1: float = x + RACK_L * 0.5
	var zs: Array = [RACK_DZ - RACK_P * 0.5, RACK_DZ + RACK_P * 0.5]
	for zb in zs:
		var zt: float = zb - RACK_CRAN
		# arceau en ∩ : pied gauche, traverse haute, pied droit
		var pts: Array = [Vector3(x0, 0.08, zb), Vector3(x0, RACK_CRAN_Y0, zb),
			Vector3(x0, RACK_CRAN_Y1, zt), Vector3(x0, RACK_H, zt), Vector3(x1, RACK_H, zt),
			Vector3(x1, RACK_CRAN_Y1, zt), Vector3(x1, RACK_CRAN_Y0, zb), Vector3(x1, 0.08, zb)]
		_tube_balaye(st, _arrondir(pts, RACK_R_COIN, 5), RACK_R_TUBE)
		for xx in [x0, x1]:
			_piece(pal, _tube(gris, RACK_R_TUBE * 1.2, 0.08), Vector3(xx, 0.04, zb))
	# traverses reliant les deux arceaux en haut
	for xx in [x0 + RACK_R_COIN, x1 - RACK_R_COIN]:
		_tube_balaye(st, [Vector3(xx, RACK_H, zs[0] - RACK_CRAN), Vector3(xx, RACK_H, zs[1] - RACK_CRAN)],
			RACK_R_TUBE)
	st.generate_normals()
	st.set_material(orange)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pal.add_child(mi)


## Arrondit les coins d'une ligne brisée (rayon `r`, `n` points par arc).
static func _arrondir(pts: Array, r: float, n: int) -> Array:
	var out: Array = [pts[0]]
	for i in range(1, pts.size() - 1):
		var a: Vector3 = pts[i - 1]
		var p: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var da: Vector3 = (a - p).normalized()
		var db: Vector3 = (b - p).normalized()
		var ang: float = acos(clampf(da.dot(db), -1.0, 1.0))
		if ang > PI - 0.01:
			out.append(p)
			continue
		var t: float = minf(r / tan(ang * 0.5), minf(a.distance_to(p), b.distance_to(p)) * 0.45)
		var p0: Vector3 = p + da * t
		var p1: Vector3 = p + db * t
		# Bézier quadratique p0 → p → p1 (assez proche de l'arc)
		for k in range(n + 1):
			var u: float = float(k) / n
			out.append(p0.lerp(p, u).lerp(p.lerp(p1, u), u))
	out.append(pts[pts.size() - 1])
	return out


## Tube de rayon r balayé le long d'une ligne (8 côtés, repère transporté).
static func _tube_balaye(st: SurfaceTool, pts: Array, r: float) -> void:
	var n_c: int = 8
	var prec: Array = []
	var ref: Vector3 = Vector3.RIGHT
	for i in range(pts.size()):
		var t: Vector3
		if i == 0:
			t = (pts[1] - pts[0]).normalized()
		elif i == pts.size() - 1:
			t = (pts[i] - pts[i - 1]).normalized()
		else:
			t = ((pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()).normalized()
		var u: Vector3 = (ref - t * ref.dot(t))
		if u.length() < 1e-3:
			u = Vector3.FORWARD - t * Vector3.FORWARD.dot(t)
		u = u.normalized()
		ref = u
		var v: Vector3 = t.cross(u)
		var anneau: Array = []
		for k in range(n_c):
			var a: float = TAU * k / n_c
			anneau.append(pts[i] + (u * cos(a) + v * sin(a)) * r)
		if not prec.is_empty():
			for k in range(n_c):
				var k2: int = (k + 1) % n_c
				for q in [prec[k], anneau[k], anneau[k2], prec[k], anneau[k2], prec[k2]]:
					st.add_vertex(q)
		prec = anneau


const PAX_PER_LANDING: int = 14      # 2 assis + 12 debout
const PAX_STAND_X: Array = [-0.62, -0.21, 0.21, 0.62]
const PAX_STAND_DZ: Array = [-0.22, 0.22]     # palier de 0,78 m (18 fenêtres par voiture)

# Skieurs réalistes (SkieurMesh, 06/10/2026) : maillages construits une
# seule fois pour les deux rames.
static var _skieurs_cache: Dictionary = {}


static func _skieurs_maillages() -> Dictionary:
	if not _skieurs_cache.is_empty():
		return _skieurs_cache
	var mat: ShaderMaterial = SkieurMesh.materiau()
	var m: Dictionary = {}
	for pose in SkieurMesh.POSES:
		for coiffe in ["casque", "bonnet"]:
			m["p:%s:%s" % [pose, coiffe]] = SkieurMesh.passager(pose, coiffe, mat)
		if pose != "enfant":
			m["s:" + pose] = SkieurMesh.sac(pose, mat)
	m["g:skis"] = SkieurMesh.skis(mat)
	m["g:batons"] = SkieurMesh.batons(mat)
	m["g:surf"] = SkieurMesh.surf(mat)
	_skieurs_cache = m
	return m


## Attitude d'un passager debout : skis 48 %, surf 14 % (même attitude,
## planche à la main), mains libres 18 %, téléphone 11 %, enfant 9 %.
static func _tirer_pose(r: float) -> Array:
	if r < 0.48:
		return ["skis", "skis"]
	if r < 0.62:
		return ["skis", "surf"]
	if r < 0.80:
		return ["libre", ""]
	if r < 0.91:
		return ["telephone", ""]
	return ["enfant", ""]


func _build_passengers() -> void:
	var maillages: Dictionary = _skieurs_maillages()
	var car_len: float = train_length / float(car_count)
	for idx in range(car_count):
		var z_c: float = (float(idx) - (car_count - 1) * 0.5) * car_len
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 1000 * (2 if is_ghost else 1) + idx * 17 + 3
		var slots: Array = []
		for k in range(TrainBodyBuilder.N_PANNEAUX):
			var zc: float = _panel_center(idx, k)
			# zone conducteur : pas de passagers dans le premier cerceau
			if idx == 0 and k == 0:
				continue
			var banc: bool = TrainBodyBuilder.KINDS[k] == "win"
			for sx in [-0.95, 0.95]:
				# assis sur les bancs ; au droit des portes, debout
				slots.append({"x": sx if banc else sx * 0.85, "z": zc, "sit": banc})
			for xs in PAX_STAND_X:
				for dz in PAX_STAND_DZ:
					# pas dans les porte-skis
					var libre: bool = true
					for xr in racks_x(k):
						if absf(xs - xr) < RACK_L * 0.5 + 0.18 and absf(dz - RACK_DZ) < RACK_P * 0.5 + 0.20:
							libre = false
					if libre:
						slots.append({"x": xs, "z": zc + dz, "sit": false})
		# ordre d'apparition mélangé (un remplissage partiel est réparti)
		for i in range(slots.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp: Dictionary = slots[i]
			slots[i] = slots[j]
			slots[j] = tmp
		# par série (clé du maillage) : transformées, graines, préfixes
		var xf: Dictionary = {}
		var cu: Dictionary = {}
		for cle in maillages:
			xf[cle] = []
			cu[cle] = []
		var pre: Dictionary = {}
		for cle2 in maillages:
			pre[cle2] = [0]
		for sl in slots:
			var x: float = sl["x"]
			var z: float = sl["z"]
			var fy: float = _floor_y_at(z)
			var zl: float = z - z_c
			var pose: String
			var materiel: String = ""
			var yaw: float
			if sl["sit"]:
				pose = "assis"
				# sur le perchoir, tourné vers le couloir
				yaw = (PI * 0.5 if x > 0.0 else -PI * 0.5) + rng.randf_range(-0.15, 0.15)
				if rng.randf() < 0.45:
					materiel = "skis_devant"
			else:
				var tir: Array = _tirer_pose(rng.randf())
				pose = tir[0]
				materiel = tir[1]
				yaw = rng.randf_range(-PI, PI)
			var coiffe: String = "casque" if rng.randf() < (0.86 if pose == "enfant" else 0.72) else "bonnet"
			var taille: float = rng.randf_range(0.94, 1.06) if pose != "enfant" else rng.randf_range(0.90, 1.12)
			var base: Transform3D = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * taille),
				Vector3(x, fy, zl))
			var graine: Color = Color(rng.randf(), rng.randf(), rng.randf(), 1.0)
			var cle_p: String = "p:%s:%s" % [pose, coiffe]
			(xf[cle_p] as Array).append(base)
			(cu[cle_p] as Array).append(graine)
			if pose != "enfant" and rng.randf() < 0.28:
				(xf["s:" + pose] as Array).append(base)
				(cu["s:" + pose] as Array).append(graine)
			var g_mat: Color = Color(rng.randf(), rng.randf(), rng.randf(), 1.0)
			match materiel:
				"skis":
					(xf["g:skis"] as Array).append(base * Transform3D(Basis.IDENTITY, SkieurMesh.ANCRE_SKIS))
					(cu["g:skis"] as Array).append(g_mat)
					(xf["g:batons"] as Array).append(base * Transform3D(Basis.IDENTITY, SkieurMesh.ANCRE_BATONS))
					(cu["g:batons"] as Array).append(g_mat)
				"surf":
					(xf["g:surf"] as Array).append(base * Transform3D(Basis.IDENTITY, SkieurMesh.ANCRE_SURF))
					(cu["g:surf"] as Array).append(g_mat)
				"skis_devant":
					(xf["g:skis"] as Array).append(base * Transform3D(Basis(Vector3.UP, PI * 0.5),
						SkieurMesh.ANCRE_SKIS_ASSIS))
					(cu["g:skis"] as Array).append(g_mat)
			for cle3 in maillages:
				(pre[cle3] as Array).append((xf[cle3] as Array).size())
		_pax_slots.append(slots)
		var noeud: Node3D = Node3D.new()
		noeud.name = "Passagers%d" % (idx + 1)
		_interior_cars[idx].add_child(noeud)
		_pax_noeuds.append(noeud)
		var mms: Dictionary = {}
		var bases: Dictionary = {}
		for cle4 in maillages:
			if (xf[cle4] as Array).is_empty():
				continue
			mms[cle4] = _pax_multimesh(idx, maillages[cle4], xf[cle4], cu[cle4], cle4.replace(":", "_"))
			if not cle4.begins_with("g:"):
				bases[cle4] = xf[cle4]
		_pax_mm.append(mms)
		_pax_base.append(bases)
		_pax_gear_prefix.append(pre)
		_pax_shown.append(-1)
	_update_passenger_count()


func _pax_multimesh(idx: int, mesh: Mesh, xforms: Array, customs: Array, nom: String) -> MultiMeshInstance3D:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, customs[i] if i < customs.size() else Color(0.5, 0.5, 0.5))
	mm.visible_instance_count = 0
	var mi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mi.name = "%s%d" % [nom, idx + 1]
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pax_noeuds[idx].add_child(mi)
	return mi


## Passagers par voiture selon le remplissage de la physique.
func _pax_count_for_car(idx: int) -> int:
	if physics == null:
		return 0
	if is_ghost:
		var n: int = physics.ghost_pax
		return (n + 1) / 2 if idx == 0 else n / 2
	return physics.pax_car1 if idx == 0 else physics.pax_car2


func _update_passenger_count() -> void:
	for idx in range(_pax_mm.size()):
		var n: int = clampi(_pax_count_for_car(idx), 0, _pax_slots[idx].size())
		if n == _pax_shown[idx]:
			continue
		_pax_shown[idx] = n
		var mm: Dictionary = _pax_mm[idx]
		var pre: Dictionary = _pax_gear_prefix[idx]
		for kind in mm:
			(mm[kind] as MultiMeshInstance3D).multimesh.visible_instance_count = pre[kind][n]


func _build_lights() -> void:
	_build_headlight()
	_build_cabin_lights()


func _build_headlight() -> void:
	# Phares frontaux (forward = -Z dans Godot) — placés DEVANT la caméra
	# pour que le cône soit visible dans le brouillard volumétrique
	headlight_front = SpotLight3D.new()
	headlight_front.name = "HeadlightFront"
	headlight_front.position = Vector3(0.0, 0.70, -train_length * 0.5 + 0.3)
	# Retour du 01/10 : « le halo central des phares fait un reflet
	# aveuglant » → énergie 14 → 5, cône 32°. Retour du 03/10 : « plus de
	# puissance, mais pas de halo central plus brillant que le reste, comme
	# des pleins phares de voiture ». Le cône de 32° dessinait un ROND
	# lumineux net au fond du tunnel, noir autour. Désormais un faisceau
	# très ouvert (75°, plus large que la vue par le pare-brise : son bord
	# ne se voit plus), homogène (atténuation de cône 2), qui porte loin
	# (atténuation 0,4) et presque à l'horizontale (−2°). Réglé sur
	# captures (shot_noir.gd p=…), en rendu PWA et PC.
	headlight_front.rotation = Vector3(deg_to_rad(-2.0), 0.0, 0.0)
	headlight_front.light_color = Color(1.0, 0.95, 0.80)
	headlight_front.light_energy = head_energy
	headlight_front.spot_range = 280.0
	headlight_front.spot_angle = 75.0
	headlight_front.spot_angle_attenuation = 2.0
	headlight_front.spot_attenuation = 0.4
	# brouillard volumétrique (vue PC) : un faisceau large et puissant y
	# ferait un voile laiteux devant la cabine
	headlight_front.light_volumetric_fog_energy = 0.25
	headlight_front.shadow_enabled = false
	headlight_front.visible = true  # allumés par défaut
	_attach_to_front_car(headlight_front, headlight_front.position)


func _build_cabin_lights() -> void:

	# (Feu arrière rouge supprimé — retour du 03/10 : « enlève le feu rouge à
	# l'arrière des rames et le reflet / halo rouge qui va avec ». Le projecteur
	# rouge de 80 m teintait le tunnel derrière la rame.)

	# Lumière cabine intérieure (ambient jaune chaud)
	interior_light = OmniLight3D.new()
	interior_light.name = "InteriorLight"
	interior_light.position = Vector3(0.0, 0.3, 0.0)
	interior_light.light_color = Color(1.0, 0.88, 0.65)
	interior_light.light_energy = 1.2
	interior_light.omni_range = 15.0
	interior_light.shadow_enabled = false
	interior_light.light_cull_mask = LAYER_RAME
	interior_light.light_volumetric_fog_energy = 0.0   # pas de brouillard dans la cabine
	interior_light.visible = true
	add_child(interior_light)


## Accroche `n` à la voiture `idx` (repère intérieur, qui suit la caisse
## posée sur ses deux bogies), `pos_rame` étant donné dans le repère de la
## rame entière. Sans intérieur (rame d'en face), reste sur la rame.
func _attach_to_car(n: Node3D, idx: int, pos_rame: Vector3) -> void:
	if idx < 0 or idx >= _interior_cars.size():
		n.position = pos_rame
		add_child(n)
		return
	var car_len: float = train_length / float(car_count)
	var z_c: float = (float(idx) - (car_count - 1) * 0.5) * car_len
	n.position = pos_rame - Vector3(0.0, 0.0, z_c)
	(_interior_cars[idx] as Node3D).add_child(n)


## PWA (rendu Compatibility, ni éclairage indirect ni plus de 8 lampes par
## objet) : les néons des gares y sont renforcés pour que les halls ne
## paraissent plus « dans le noir » ; l'intérieur de la cabine passe sur sa
## propre couche (sans la couche 1) pour qu'ils ne le surexposent pas — les
## lumières de la cabine, du tunnel et les phares l'éclairent toujours.
func _couche_interieur() -> void:
	if interior_root == null \
			or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		return
	for n in interior_root.find_children("*", "VisualInstance3D", true, false):
		var vi: VisualInstance3D = n
		vi.layers = (vi.layers & ~1) | LAYER_INTERIEUR | LAYER_RAME


## Vue cabine : commande du pupitre sous le point d'écran `pos` ("" = aucune).
func pupitre_commande_sous(pos: Vector2) -> String:
	if _pupitre == null or camera_fpv == null or view_mode != ViewMode.FPV:
		return ""
	return _pupitre.commande_sous(camera_fpv, pos)


## Commutateur général du pupitre (clé EN MARCHE).
func pupitre_en_marche() -> bool:
	return _pupitre == null or _pupitre.en_marche


func pupitre_appuyer(nom: String, enfonce: bool) -> void:
	if _pupitre != null:
		_pupitre.appuyer(nom, enfonce)


func _attach_to_front_car(n: Node3D, pos_rame: Vector3) -> void:
	_attach_to_car(n, 0, pos_rame)


func _build_camera() -> void:
	# Caméra 1ère personne — position driver dans la zone cockpit
	camera_fpv = Camera3D.new()
	camera_fpv.name = "CameraFPV"
	camera_fpv.fov = 78.0   # « dézoome un peu » (retour du 30/09) : 70 → 78°
	camera_fpv.near = 0.05
	camera_fpv.far = 800.0
	# Avancée de 0,4 m (retour d'essai 2026-07 : « trop loin du panneau
	# de commande ») — le pupitre à 0,7 m devant tombe en bas de l'image.
	# Retours d'essai 2026-09-26/27 : « on est trop loin, il faut zoomer,
	# la vitre doit être plus grande ». Le pare-brise est sur la calotte,
	# à z ≈ −15,9 (presque au nez, −16) : à 2,15 m du nez la caméra était
	# encore à 2,1 m de la vitre. Le vrai conducteur est à ~1 m : caméra à
	# 1,1 m du nez, pupitre 0,65 m devant, champ vertical 70° (la vitre de
	# 1,64 × 1,8 m couvre ±37° en largeur, tout le champ en hauteur).
	# Portée par la VOITURE DE TÊTE (retour du 01/10 : « tremblements de la
	# rame ») : accrochée au centre de la rame, elle suivait la tangente
	# prise 15 m en arrière et se déplaçait par rapport au pupitre (jusqu'à
	# 39 cm en travers dans les courbes, 9 cm en hauteur) ; tout écart
	# d'orientation était multiplié par ce bras de levier.
	_attach_to_front_car(camera_fpv, Vector3(0.0, 0.85, -train_length * 0.5 + 1.1))
	_cam_fpv_basis_base = camera_fpv.transform.basis

	# Caméra extérieure — VRAIE orbitale autour de la rame (retour d'essai
	# 2026-07-24 : « cette vue est fixe ») : yaw/pitch/distance pilotés au
	# doigt (drag 1 doigt = angle, pincement 2 doigts = zoom) ou à la
	# souris (clic gauche maintenu + molette). Position recalculée chaque
	# frame par _update_orbit_camera ; les défauts reproduisent l'ancienne
	# vue fixe (3, 10, 25).
	camera_ext = Camera3D.new()
	camera_ext.name = "CameraExt"
	camera_ext.fov = 60.0
	camera_ext.near = 0.1
	camera_ext.far = 1500.0
	add_child(camera_ext)
	_update_orbit_camera()

	camera_fpv.make_current()


func _apply_view_mode() -> void:
	if view_mode == ViewMode.MACHINES and camera_machines == null:
		view_mode = ViewMode.FPV
	# La coque reste VISIBLE en cabine (2026-09-26) : elle porte les
	# hublots, le pare-brise et sa doublure intérieure — avant, on voyait
	# le tunnel de tous côtés, sans montants ni vitres.
	mesh_root.visible = true
	match view_mode:
		ViewMode.FPV:
			camera_fpv.make_current()
		ViewMode.EXTERIOR:
			camera_ext.make_current()
		ViewMode.MACHINES:
			camera_machines.make_current()
		ViewMode.SKIEUR:
			pass                       # caméra du skieur (main.gd)
	if machine_room != null:
		machine_room.set_cutaway(view_mode == ViewMode.MACHINES)
	# Parois du tunnel translucides en vue extérieure pour voir la rame
	# dans le tube (seule la cabine pilotée bascule la vue). La salle des
	# machines garde ses murs : la caméra y reste à l'intérieur.
	if not is_ghost and tunnel != null:
		tunnel.set_wall_see_through(view_mode == ViewMode.EXTERIOR)


## Cycle des vues 3D : cabine → extérieure → salle des machines → cabine
## (la dernière seulement si la salle est construite).
func toggle_view() -> void:
	var n: int = 3 if camera_machines != null else 2
	set_view(((view_mode + 1) % n))


## Loupe sur le pupitre : marche / arrêt (bouton LOUPE), par crans (molette).
func set_loupe(on: bool) -> void:
	loupe_cible = 1.0 if on else 0.0


func loupe_molette(sens: int) -> void:
	loupe_cible = clampf(loupe_cible + 0.34 * float(sens), 0.0, 1.0)


func _update_loupe(delta: float) -> void:
	if is_ghost or camera_fpv == null:
		return
	if view_mode != ViewMode.FPV:
		loupe_cible = 0.0
	if loupe == 0.0 and loupe_cible == 0.0:
		return
	loupe = move_toward(loupe, loupe_cible, delta * 3.0)
	camera_fpv.fov = lerpf(78.0, 32.0, loupe)
	if _ecran_loupe == null and _pupitre != null:
		_ecran_loupe = _pupitre.find_child("EcranProface", true, false) as Node3D
		if _ecran_loupe == null:
			_ecran_loupe = _pupitre
	var basis: Basis = _cam_fpv_basis_base
	if _ecran_loupe != null and loupe > 0.0:
		var parent: Node3D = camera_fpv.get_parent() as Node3D
		var cible: Vector3 = parent.global_transform.affine_inverse() * _ecran_loupe.global_position
		var dir: Vector3 = cible - camera_fpv.position
		if dir.length() > 0.05:
			basis = _cam_fpv_basis_base.slerp(Basis.looking_at(dir.normalized(), Vector3.UP), loupe)
	camera_fpv.transform.basis = basis


func set_view(mode: int) -> void:
	if is_ghost:
		return
	view_mode = mode
	_apply_view_mode()
	print("[View] %s" % ["FPV cockpit", "EXTERIOR orbital", "salle des machines", "skieur"][view_mode])


func set_tunnel(t: TunnelBuilder) -> void:
	tunnel = t


func set_physics(p: TrainPhysics) -> void:
	physics = p


func _process(_delta: float) -> void:
	if tunnel == null or physics == null:
		return
	_update_shake(_delta)
	_update_loupe(_delta)
	# Caméra orbitale : suit la rame chaque frame en vue extérieure.
	if not is_ghost and view_mode == ViewMode.EXTERIOR:
		_update_orbit_camera()
	# Position le long de la spline : rame 1 à s_render (position physique
	# interpolée pour le rendu), rame 2 (ghost) à MIROIR_S − s_render
	var s_pos: float
	if is_ghost:
		# Le ghost embarque dans SA gare : son propre affaissement de
		# brin s'applique à SA position (visible quand il est en bas).
		# ghost_s_render() vaut MIROIR_S − s en marche normale, et la
		# position FIGÉE de la rame 2 une fois le câble rompu (mode Défi).
		s_pos = physics.ghost_s_render() + physics.ghost_sag_offset()
	else:
		s_pos = physics.s_render

	# IMPORTANT : la cabine doit suivre l'orientation de SA trajectoire, pas celle
	# de l'axe central du tunnel. Dans le passing loop, le déport latéral ajoute
	# une composante tangentielle qui fait tourner la trajectoire. Si on utilisait
	# tunnel.transform_at(s).basis, le nez de la cabine resterait pointé selon la
	# centerline et taperait dans le mur du tube en transition.
	#
	# On échantillonne donc la position MONDE de la cabine à s, s+eps et s-eps
	# (en incluant l'offset latéral à chaque échantillon) pour calculer la
	# tangente réelle de sa trajectoire.
	var eps: float = 1.5
	var s_prev: float = maxf(s_pos - eps, 0.0)
	var s_next: float = minf(s_pos + eps, PNConstants.LENGTH)
	var pos_cur: Vector3 = _cabin_world_pos(s_pos)
	var pos_prev: Vector3 = _cabin_world_pos(s_prev)
	var pos_next: Vector3 = _cabin_world_pos(s_next)
	var trajectory_tangent: Vector3 = (pos_next - pos_prev).normalized()
	if trajectory_tangent.length() < 0.5:
		trajectory_tangent = Vector3.FORWARD

	var xform: Transform3D = _xform_from(pos_cur, trajectory_tangent)
	global_transform = xform

	# Articulation : chaque voiture sur la spline à SA propre abscisse.
	# L'avant de la rame (−Z) pointe vers +s quand la rame 1 monte, vers −s
	# quand le ghost « monte » (il est retourné).
	var travel_sign: float = float(physics.direction) * (-1.0 if is_ghost else 1.0)
	var car_len: float = train_length / float(car_count)
	for idx in range(_car_roots.size()):
		var z_c: float = (float(idx) - (car_count - 1) * 0.5) * car_len
		var s_car: float = clampf(s_pos - travel_sign * z_c, 0.0, PNConstants.LENGTH)
		# Chaque voiture repose sur ses DEUX bogies (à ±6 m de son centre) :
		# la caisse suit la corde entre les deux appuis, pas la tangente en
		# son milieu — sinon, sur un changement de pente convexe, les roues
		# décollaient du rail (retour d'essai 2026-09-27).
		var bh: float = car_len * 0.5 - TrainBodyBuilder.BOGIE_OFFSET
		var p_a: Vector3 = _cabin_world_pos(maxf(s_car - bh, 0.0))
		var p_b: Vector3 = _cabin_world_pos(minf(s_car + bh, PNConstants.LENGTH))
		var p_c: Vector3 = (p_a + p_b) * 0.5
		var tg: Vector3 = (p_b - p_a).normalized()
		if tg.length() < 0.5:
			tg = trajectory_tangent
		var xf_car: Transform3D = _xform_from(p_c, tg)
		(_car_roots[idx] as Node3D).global_transform = xf_car
		if idx < _interior_cars.size():
			(_interior_cars[idx] as Node3D).global_transform = xf_car

	# Roues : roulement sans glissement autour de l'essieu (axe X de la
	# voiture), marche avant = −Z → angle −d/R. d = déplacement RÉEL de la
	# rame dessinée depuis l'image précédente, pas la vitesse de la poulie :
	# la rame du bas qui recule pendant l'embarquement (affaissement du
	# brin), l'oscillation du câble à l'arrêt, la rame qui dévale après une
	# rupture font tourner leurs roues (retour du 06/10/2026 : « quand la
	# rame du bas recule pendant l'embarquement, les roues n'ont pas l'air
	# de tourner »). En marche : identique à v/R. Saut de position
	# (nouveau voyage, scénario) : ignoré.
	if not is_nan(_s_pos_roues) and not _wheels.is_empty():
		var ds: float = s_pos - _s_pos_roues
		if absf(ds) > 1e-5 and absf(ds) < maxf(2.0, 40.0 * _delta):
			var d_ang: float = -ds * travel_sign / TrainBodyBuilder.WHEEL_R
			for w in _wheels:
				(w as Node3D).rotate_x(d_ang)
	_s_pos_roues = s_pos

	# Portes coulissantes (2026-09-26) : déboîtement (premier quart) puis
	# glissement vers l'arrière, des DEUX côtés (retour d'essai : les deux
	# faces s'ouvrent en gare). Course = DOOR_MOTION_S (4,0 s), calée sur
	# le clip sonore ; l'ordre vient de door_leaves_open (physique PWA ou
	# état visuel envoyé par le PC), pas de doors_open (l'interlock).
	# Sens du glissement : TOUJOURS vers le BAS de la pente à l'ouverture,
	# vers le HAUT à la fermeture (retour d'essai 2026-09-27 : « la porte
	# s'ouvre en se déplaçant vers le bas et se ferme vers le haut »). La
	# caisse étant retournée quand elle descend (_xform_from), « vers
	# l'arrière » (+Z local) n'est le bas que dans un sens : on corrige le
	# signe avec la même règle que le retournement.
	# Deux côtés (07/10/2026) : PORTES 1 à 6 à gauche en regardant vers le
	# haut, 7 à 12 à droite ; physics.portes_cotes dit lesquels s'ouvrent.
	# +Z·sgn pointe vers le bas de la pente → la gauche en regardant vers
	# le haut est le côté x = −sgn de la caisse.
	var sgn: float = door_slide_sign(physics.direction, is_ghost)
	for c in range(2):
		var feuilles: bool = physics.ghost_door_leaves_open() if is_ghost else physics.door_leaves_open
		var ouvert: bool = feuilles and (physics.portes_cotes & (1 << c)) != 0
		_door_frac_cote[c] = move_toward(_door_frac_cote[c], 1.0 if ouvert else 0.0,
			_delta / PNConstants.DOOR_MOTION_S)
	_door_frac = maxf(_door_frac_cote[0], _door_frac_cote[1])
	if not _doors.is_empty():
		for d in _doors:
			var f: float = _door_frac_cote[0 if float(d["side"]) * sgn < 0.0 else 1]
			var plug: float = clampf(f / 0.25, 0.0, 1.0)
			var slide: float = clampf((f - 0.25) / 0.75, 0.0, 1.0)
			var node: Node3D = d["node"]
			var base: Vector3 = d["base"]
			node.position = base + Vector3(d["side"] * TrainBodyBuilder.DOOR_PLUG * plug,
				0.0, sgn * TrainBodyBuilder.DOOR_SLIDE * slide)

	# Pupitre : voyants, commandes et écran Pro-face (l'écran seulement en
	# vue cabine — inutile de le redessiner quand on ne le voit pas)
	if _pupitre != null and physics != null:
		# écran vivant aussi pour le skieur à bord de CETTE rame, pilotée ou
		# d'en face (Kevin, 09/10/2026 : « en mode skieur, les données sur les
		# écrans de conduite sont figées »)
		_pupitre.mettre_a_jour(physics, _delta, train_number,
			(not is_ghost and view_mode == ViewMode.FPV) or skieur_a_bord, is_ghost)

	# Tablette-horloge du montant gauche : l'heure réelle, comme en cabine
	if _clock_label != null:
		_clock_next -= _delta
		if _clock_next <= 0.0:
			_clock_next = 1.0
			var hl: Dictionary = PNConstants.heure_locale()
			_clock_label.text = "%02d:%02d" % [hl.hour, hl.minute]

	# Animation des passagers selon dynamique
	_animate_passengers(_delta)
	# Sync des lumières depuis physics (drives by Python sim in client mode)
	_animate_headlights(_delta)
	if physics.direction != _wheel_dir_applied:
		_apply_wheel_types()
	if not is_ghost:
		_apply_cabin_lights(physics.lights_cabin)


var _sway_prec: Vector2 = Vector2(INF, INF)


func _animate_passengers(delta: float) -> void:
	_update_passenger_count()
	# Vue cabine : la caméra regarde vers l'avant, les passagers de la rame
	# sont derrière elle — on ne les dessine pas (économie sur la PWA).
	var montrer: bool = is_ghost or view_mode != ViewMode.FPV
	for noeud in _pax_noeuds:
		if (noeud as Node3D).visible != montrer:
			(noeud as Node3D).visible = montrer
	if is_ghost or _pax_mm.is_empty() or not montrer:
		return
	# Accel longitudinale (m/s²) — freinage = négatif, accel = positif
	var dv: float = physics.v - _prev_v_for_acc
	var acc_long: float = 0.0
	if delta > 0.001:
		acc_long = dv / delta
	_prev_v_for_acc = physics.v
	# Accel latérale dans le passing loop ou virages : approx via courbure horizontale
	var heading_rate_rad_m: float = deg_to_rad(
		SlopeProfile.heading_at(physics.s + 5.0) - SlopeProfile.heading_at(physics.s - 5.0)
	) / 10.0
	var acc_lat: float = physics.v * physics.v * heading_rate_rad_m
	# Inclinaisons (proportionnelles, plafonnées) : accélération → têtes en
	# arrière (+X), virage à droite → têtes vers l'extérieur (−Z)
	var pitch: float = clampf(-acc_long * 0.06, -0.20, 0.20)
	var roll: float = clampf(-acc_lat * 0.05, -0.18, 0.18)
	# rame posée ou en croisière : rien ne bouge, on ne repositionne pas
	if absf(pitch - _sway_prec.x) < 1e-3 and absf(roll - _sway_prec.y) < 1e-3:
		return
	_sway_prec = Vector2(pitch, roll)
	# les silhouettes se balancent autour de leurs pieds (origine du
	# maillage) ; assis, moitié moins
	var sway_s: Basis = Basis.from_euler(Vector3(pitch * 0.6, 0.0, roll * 0.6))
	var sway_a: Basis = Basis.from_euler(Vector3(pitch * 0.3, 0.0, roll * 0.3))
	for idx in range(_pax_mm.size()):
		var pre: Dictionary = _pax_gear_prefix[idx]
		var n: int = _pax_shown[idx]
		if n <= 0:
			continue
		for kind in _pax_base[idx]:
			var mm: MultiMesh = (_pax_mm[idx][kind] as MultiMeshInstance3D).multimesh
			var base: Array = _pax_base[idx][kind]
			var sway: Basis = sway_a if kind.contains("assis") else sway_s
			for i in range(pre[kind][n]):
				var t: Transform3D = base[i]
				mm.set_instance_transform(i, Transform3D(sway * t.basis, t.origin))


## Phares halogènes : le filament chauffe (≈ 0,3 s) et refroidit (≈ 0,6 s),
## la lumière passe par l'orange. La lentille et le projecteur suivent.
func _animate_headlights(delta: float) -> void:
	if _head_mat == null:
		return
	var target: float = 1.0 if physics.lights_head else 0.0
	var tau: float = 0.12 if target > _head_glow else 0.25
	_head_glow += (target - _head_glow) * (1.0 - exp(-delta / tau))
	if absf(target - _head_glow) < 0.002:
		_head_glow = target
	var g: float = _head_glow
	_head_mat.emission = Color(1.0, 0.30 + 0.65 * g, 0.05 + 0.75 * g)
	_head_mat.emission_energy_multiplier = 5.0 * g * g + 0.4 * g
	_head_mat.albedo_color = Color(0.10, 0.10, 0.11).lerp(Color(1.0, 0.96, 0.85), g)
	if headlight_front != null:
		headlight_front.light_energy = head_energy * g * g
		headlight_front.visible = g > 0.01


## Roues Abt : la rame de la voie de GAUCHE dans l'évitement (passing_side
## < 0, rame 1) est guidée par ses roues côté GAUCHE en regardant vers le
## haut (rail extérieur) ; la rame de droite par ses roues de droite. Les
## autres roues sont les cylindres larges. La caisse étant retournée quand
## elle descend (le nez mène toujours), le côté local s'inverse avec le sens.
func _apply_wheel_types() -> void:
	if _wheels.is_empty():
		return
	var flipped: bool = false
	if physics != null:
		flipped = (physics.direction > 0) if is_ghost else (physics.direction < 0)
	_wheel_dir_applied = (physics.direction if physics != null else 0)
	for w in _wheels:
		var pivot: Node3D = w as Node3D
		if pivot == null or not pivot.has_meta("sx"):
			continue
		var sx: float = pivot.get_meta("sx")
		var guided: bool = ((sx < 0.0) == (passing_side < 0.0)) != flipped
		var g: Node3D = pivot.get_node_or_null("Boudin")
		var f: Node3D = pivot.get_node_or_null("Plate")
		if g != null:
			g.visible = guided
		if f != null:
			f.visible = not guided


## Signe du glissement des vantaux en Z LOCAL de la caisse pour que, dans
## le monde, l'ouverture aille vers le bas de la pente. +Z local = arrière
## de la caisse ; la caisse est retournée (PI autour de Y) quand la rame 1
## descend ou quand la rame 2 (ghost) monte — même prédicat que _xform_from.
## Issues de secours de la face (Kevin, 07/10/2026) : les D jaunes de part
## et d'autre du pare-brise s'enlèvent pour évacuer une rame arrêtée en
## tunnel ; remis quand la rame est de nouveau à quai (main.gd).
func retirer_issues(oui: bool) -> void:
	issues_retirees = oui
	for e in _issues:
		(e["node"] as Node3D).visible = not oui
		var caisse: MeshInstance3D = e.get("caisse") as MeshInstance3D
		if caisse == null or not is_instance_valid(caisse):
			continue
		for si in e.get("surfaces", []):
			caisse.set_surface_override_material(int(si), _mat_invisible() if oui else null)


## Matériau qui n'affiche rien : panneau d'issue retiré (surface de la caisse).
static var _invisible: ShaderMaterial = null
static func _mat_invisible() -> ShaderMaterial:
	if _invisible == null:
		var sh: Shader = Shader.new()
		sh.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled, shadows_disabled;\nvoid fragment() { discard; }\n"
		_invisible = ShaderMaterial.new()
		_invisible.shader = sh
	return _invisible


static func door_slide_sign(direction: int, ghost: bool) -> float:
	var flipped: bool = (direction > 0) if ghost else (direction < 0)
	return -1.0 if flipped else 1.0


func set_train_number(n: int) -> void:
	train_number = n
	if mesh_root == null:
		return
	for lbl in mesh_root.find_children("PlaqueTexte", "Label3D", true, false):
		(lbl as Label3D).text = "FUNICULAIRE\nPERCE NEIGE %d" % n



# Position monde de la cabine à la distance s, en tenant compte du déport
# latéral du passing loop (passing_side fixe la voie gauche/droite).
## Transform d'un repère posé en `pos` le long de la tangente `tangent`
## (forward = −Z), décalé de 0,15 m sous l'axe, retourné selon le sens de
## marche (rame 2 va dans le sens −tangent quand la rame 1 monte).
func _xform_from(pos: Vector3, tangent: Vector3) -> Transform3D:
	var world_up: Vector3 = Vector3.UP
	var right: Vector3 = tangent.cross(world_up).normalized()
	if right.length() < 0.01:
		right = Vector3.RIGHT
	var up: Vector3 = right.cross(tangent).normalized()
	var xform: Transform3D = Transform3D()
	xform.basis = Basis(right, up, -tangent)
	xform.origin = pos + up * (-0.15)
	if is_ghost:
		if physics.direction > 0:
			xform.basis = xform.basis.rotated(xform.basis.y, PI)
	else:
		if physics.direction < 0:
			xform.basis = xform.basis.rotated(xform.basis.y, PI)
	return xform


func _cabin_world_pos(s: float) -> Vector3:
	var xf: Transform3D = tunnel.transform_at(s)
	var lat: float = tunnel.passing_loop_offset(s, passing_side)
	return xf.origin + xf.basis.x * lat


## Phares : 0 éteints → 1 plein feu (fondu halogène compris).
func head_glow() -> float:
	return _head_glow


func set_headlights(on: bool) -> void:
	# l'état vient de physics.lights_head ; le fondu halogène est dans
	# _animate_headlights, appelé à chaque tick
	if physics != null:
		physics.lights_head = on


func set_interior_lights(on: bool) -> void:
	_apply_cabin_lights(on)


func _apply_cabin_lights(on: bool) -> void:
	if interior_light != null:
		interior_light.visible = on
	# les fenêtres ne luisent (intérieur éclairé vu du dehors) que si la
	# cabine est allumée
	var vitre = _body_mats.get("glass")
	if vitre is StandardMaterial3D and (vitre as StandardMaterial3D).emission_enabled != on:
		(vitre as StandardMaterial3D).emission_enabled = on
	for l in _cockpit_lights:
		l.visible = on


## Met toute la géométrie de la rame aussi sur LAYER_RAME, seule couche que
## voient les lumières de la cabine.
func _tag_layer_rame(n: Node) -> void:
	tag_layer(n, LAYER_RAME)


## Ajoute la couche `bit` à toute la géométrie sous `n`.
static func tag_layer(n: Node, bit: int) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers |= bit
	for c in n.get_children():
		tag_layer(c, bit)


# --- Secousse d'écran (collision) ----------------------------------------

## Déclenche une secousse : `mag` en unités de décalage caméra (≈ mètres),
## amortie linéairement sur `duration` secondes.
func shake(duration: float, mag: float) -> void:
	_shake_t = maxf(_shake_t, duration)
	_shake_mag = maxf(_shake_mag, mag)


func _update_shake(delta: float) -> void:
	if is_ghost:
		return
	var cam: Camera3D = camera_fpv if view_mode == ViewMode.FPV else camera_ext
	if view_mode == ViewMode.MACHINES:
		cam = camera_fpv    # la salle ne tremble pas ; on remet la cabine à zéro
	if cam == null:
		return
	if _shake_t <= 0.0:
		if cam.h_offset != 0.0 or cam.v_offset != 0.0:
			cam.h_offset = 0.0
			cam.v_offset = 0.0
		return
	_shake_t = maxf(0.0, _shake_t - delta)
	var amp: float = _shake_mag * _shake_t
	cam.h_offset = randf_range(-amp, amp)
	cam.v_offset = randf_range(-amp, amp)
	if _shake_t <= 0.0:
		_shake_mag = 0.0
		cam.h_offset = 0.0
		cam.v_offset = 0.0
