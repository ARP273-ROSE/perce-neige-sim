class_name SkieurJoueur
extends CharacterBody3D
## Le skieur jouable (demande d'un utilisateur du 07/10/2026 : « un skieur capable
## de monter les escaliers des gares et de marcher à l'intérieur sans passer
## au travers du plancher, des murs, des portes ou du wagon, qui peut
## marcher dans le wagon, voyager dans le funiculaire et aller au poste de
## pilotage »).
##
## Vu de dos (caméra au bout d'un bras qui se raccourcit contre les murs),
## ou à la première personne. Joystick à l'écran (CommandesSkieur) ou
## clavier : ZQSD / flèches pour marcher, Maj pour courir, souris (ou
## doigt sur la droite de l'écran) pour tourner la vue, molette pour
## l'éloigner.
##
## Il marche sur les collisions de CollisionsJeu : il monte une marche de
## 40 cm au plus (escaliers, contremarches des paliers, seuil de la rame),
## glisse le long des murs. Debout dans une voiture, il est EMPORTÉ avec
## elle : à chaque image on lui applique le déplacement de la voiture (sa
## position, et son cap), avant de le faire marcher.
## Repère du corps : jamais tourné (le cap ne s'applique qu'à l'apparence).

signal conduite_demandee
signal chute                          # tombé (mur ou roche à vive allure)

const RAYON: float = 0.14              # de profil : il passe entre deux porte-skis
const TAILLE: float = 1.76
const MARCHE_MAX: float = 0.40
const GRIMPE_MAX: float = 1.25          # à pied hors des gares (`grimpe`) : on se
                                        # hisse sur un rebord — fosse entre les
                                        # rails : fond 70 cm sous la dalle, et le
                                        # rail à enjamber est à 1,04 m du fond
                                        # (retour d'utilisateur, 08/10/2026 : « coincé entre les
                                        # deux rails »)
const V_MARCHE: float = 1.45
const V_COURSE: float = 3.3
const ACCEL: float = 7.0
const G: float = 9.81
const Y_YEUX: float = 1.62
const DIST_MIN: float = 1.2
const DIST_MAX: float = 9.0
const N_IMAGES: int = 8

var actif: bool = false
## Commande de marche : x vers la droite, y vers l'avant (−1…1).
var entree: Vector2 = Vector2.ZERO
var course: bool = false
## Course du pilote (mode BOUCLE) en suivant `chemin` : il court quand
## l'embarquement est ouvert (retour d'utilisateur, 11/10/2026 : « il ne court pas s'il
## est en retard »).
var course_auto: bool = false
## Assis sur un banc (mode BOUCLE, en attendant la rame).
var assis: bool = false
## À bord d'une remontée (siège ou cabine) : posé chaque image par
## RemonteesDomaine, il ne marche ni ne glisse (retour d'utilisateur, 22/10/2026)
var embarque: bool = false
const Y_YEUX_ASSIS: float = 1.25          # yeux du passager assis, au-dessus des pieds
const RECUL_ASSIS: float = 0.42          # pieds devant le banc, bassin au-dessus de l'assise
var _image_assise: Mesh = null
## Touches de marche tenues dans le simulateur PC (vue 3D embarquée, le
## clavier reste au PC) : 1 avant, 2 arrière, 4 gauche, 8 droite, 16 courir
var touches_ext: int = 0
var cam_yaw: float = 0.0
var cam_pitch: float = -0.28
var cam_dist: float = 3.2
var premiere_personne: bool = false
## Voiture qui porte le skieur (nœud de la voiture), ou null.
var support: Node3D = null
var _support_xf: Transform3D = Transform3D.IDENTITY
var _cap: float = 0.0
var _phase: float = 0.0
var _chute: float = 0.0
var dernier_sol: Vector3 = Vector3.ZERO
var _depart_chute: Vector3 = Vector3.ZERO   # où la chute a commencé (repli si aucun sol sûr)
var grimpe: bool = false                 # posé par main : à pied hors des gares (tunnel, galerie, dehors)
var _sol_stable: float = 0.0           # temps passé sur un sol fixe
var _chutes: Array = []                # instants des derniers rattrapages
## Où le reposer s'il tombe trois fois de suite (posé par main.gd).
var refuge: Vector3 = Vector3.ZERO
## Points à rejoindre l'un après l'autre (bancs d'essai, mode AUTO).
var chemin: Array = []

var pivot: Node3D = null
var bras: SpringArm3D = null
var camera: Camera3D = null
var _visuel: Node3D = null
var _corps: MultiMeshInstance3D = null
var _skis: MultiMeshInstance3D = null
var _images: Array = []                # maillages de la marche (+ debout en 0)

# --- ski (retour d'utilisateur, 07/10/2026 : « arrivé en haut, il est capable de skier sur
# le décor pour redescendre ») -------------------------------------------------
const MU_NEIGE: float = 0.05            # frottement ski / neige damée
const MU_ARRET: float = 0.12            # immobile, il tient sur une pente douce (≈ 7°)
const K_AIR: float = 0.0032             # traînée ½ρ·Cx·S / m, debout (1/m)
const K_AIR_SCHUSS: float = 0.0018      # recroquevillé (schuss)
const OMEGA_SKI: float = 1.8            # rad/s : pivot des skis à basse vitesse
const A_VIRAGE: float = 6.5             # m/s² : accélération latérale d'un virage coupé
const ADHERENCE: float = 5.0            # 1/s : la carre absorbe la vitesse en travers
const DEC_CHASSE: float = 3.2           # m/s² : chasse-neige à fond
const V_PAS: float = 3.0                # m/s : pas de patineur sur le plat (retour d'utilisateur : 3-4 m/s au départ)
const A_PAS: float = 2.0                # m/s² : poussée des bâtons
const V_MAX_SKI: float = 30.0
## Relief (posé par main.gd) : le sol de la glisse.
var relief: ReliefBuilder = null
var chausse: bool = false
## Vitesse visée par le pilote (bancs, mode AUTO) en suivant `chemin` à ski.
var vitesse_pilote: float = 12.0
var _v_ski: Vector3 = Vector3.ZERO
var _cap_ski: float = 0.0
var _penche: float = 0.0
var _vue_libre: float = 99.0            # s depuis le dernier glissé de la vue
## Pilote EXPERT (BOUCLE) : il carve « comme Odermatt » au lieu du
## chasse-neige à 40 km/h d'une première étoile (retour d'utilisateur, 12/10/2026) —
## virages coupés jusqu'à 1,6 g, carres qui tiennent, vitesse choisie sur
## les courbes à venir jusqu'à ~100 km/h, freinage en dérapage, posture de
## glisse inclinée ou de schuss, jamais le chasse-neige.
var pilote_expert: bool = false
const A_VIRAGE_EXPERT: float = 16.0      # m/s² (1,6 g, virage coupé de géant)
const ADHERENCE_EXPERT: float = 9.0
const DEC_DERAPAGE: float = 4.5          # m/s² : freinage en dérapage contrôlé
const V_EXPERT: float = 27.5             # m/s (≈ 100 km/h)
const A_PLAN: float = 11.0               # m/s² : latérale visée en préparant un virage
var _pilote_schuss: bool = false
var _ski_prog_d: float = INF          # pilote à ski : meilleure distance au point visé
var _ski_prog_t: float = 0.0
var _joy_vise: bool = false             # (conservé pour compatibilité, plus utilisé)
## Repère du pouce (retour d'utilisateur, 12/10/2026 : « c'est infernal de diriger le
## skieur avec une vue qui bouge à chaque mouvement de joystick ou de
## virage ») : la direction du joystick ou des touches se lit dans le repère
## de la vue AU MOMENT où l'on pose le pouce, et ce repère reste FIGÉ tant
## qu'on ne le relâche pas (règle classique des caméras à la troisième
## personne : garder la matrice de la vue précédente tant que l'entrée est
## tenue). Avant, la caméra qui suivait les skis déplaçait la cible du
## pouce : on poursuivait une cible mobile, la vue tournait, le cap aussi.
var _ref_pouce: float = 0.0
var _pouce_tenu: bool = false
var _pouce_lache_t: float = 0.0
## Écran tactile : doigts posés (CommandesSkieur) et dernier contact. Tant
## qu'un doigt touche l'écran (et 0,6 s après), les événements « souris »
## sont ignorés : sur iPad, le glissé du pouce du joystick arrivait AUSSI en
## souris et tournait la vue — pouce vers l'avant = caméra par terre en
## 3e personne, regard au ciel en 1re (retour d'utilisateur, 12/10/2026).
var doigts: int = 0
var tactile_t: float = -10.0
## Caméra de poursuite à ski : ressort critique sur le cap des skis, vitesse
## de rotation bornée (pas de tournis), suspendue quand on tourne la vue à
## la main.
var _cam_v: float = 0.0                 # rad/s
const CAM_OMEGA: float = 1.6            # raideur du ressort (s⁻¹) : ~2 s pour se replacer
const CAM_V_MAX: float = deg_to_rad(50.0)
const VUE_MAIN_PAUSE: float = 2.0       # s sans suivi après une rotation à la main
var _pitch_sol: float = 0.0             # relèvement lissé contre le relief
var _batons: MultiMeshInstance3D = null
var _skis_pieds: Mesh = null
var _skis_main: Mesh = null
var _image_glisse: Mesh = null
var _image_schuss: Mesh = null
var _image_chasse: Mesh = null
var _images_poussee: Array = []          # cycle de poussée sur les bâtons (4 images)
var _poussee_t: float = 0.0
var _pousse: bool = false                # il pousse vraiment (relevé au pas précédent)
var _image_poussee: int = -1
var _skis_pieds_v: Mesh = null           # chasse-neige : skis en V
var _posture: int = 0                    # 0 glisse, 1 schuss, 2 chasse-neige
## Chute (retour d'utilisateur, 07/10/2026 : « si je vais dans les décors trop vite on peut
## déchausser et s'exploser dans la neige, plus qu'à avoir une touche
## rechausser ») : un mur (bâtiment, quai) à plus de V_CHUTE_MUR, la roche
## (pente > 37°, là où la neige ne tient pas) à plus de V_CHUTE_ROCHE → à
## terre CHUTE_S secondes, skis déchaussés ; E (CHAUSSER) pour repartir.
const V_CHUTE_MUR: float = 6.0
const V_CHUTE_ROCHE: float = 8.0
const CHUTE_S: float = 2.5
## Retour d'utilisateur, 08/10/2026 : « je déchausse tout le temps, désactive ce truc » —
## le critère « roche » (pente > 37°) tombait sur toute piste raide. Gardé,
## éteint.
const CHUTES_ACTIVES: bool = false
const Y_SKI: float = 0.10                # skis posés 10 cm au-dessus du sol calculé (sinon
										 # les tuiles du relief, maillées autrement, les cachent)
var _chute_t: float = 0.0
var _capsule: CollisionShape3D = null    # la forme, inclinée avec la voiture qui porte


func _init() -> void:
	collision_layer = CollisionsJeu.COUCHE_SKIEUR
	collision_mask = CollisionsJeu.COUCHE_DECOR | CollisionsJeu.COUCHE_VEHICULE
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = MARCHE_MAX + 0.05
	# on glisse le long d'un mur quel que soit l'angle d'attaque : à moins
	# de 15° de la normale (défaut), le corps s'arrêtait net contre un
	# porte-skis abordé presque de face et n'en sortait plus (07/10/2026)
	wall_min_slide_angle = 0.0
	floor_block_on_wall = false
	floor_stop_on_slope = true
	max_slides = 6
	safe_margin = 0.02
	process_priority = 100                 # après les rames (Cabin._process)


func _ready() -> void:
	var cs: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = RAYON
	cap.height = TAILLE
	cs.shape = cap
	_capsule = cs
	cs.position.y = TAILLE * 0.5
	add_child(cs)
	pivot = Node3D.new()
	pivot.name = "PivotCamera"
	pivot.position.y = Y_YEUX
	add_child(pivot)
	bras = SpringArm3D.new()
	var boule: SphereShape3D = SphereShape3D.new()
	boule.radius = 0.12
	bras.shape = boule
	bras.collision_mask = CollisionsJeu.COUCHE_DECOR | CollisionsJeu.COUCHE_VEHICULE
	bras.margin = 0.05
	bras.add_excluded_object(get_rid())
	pivot.add_child(bras)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 60000.0
	camera.fov = 70.0
	bras.add_child(camera)
	_visuel = Node3D.new()
	_visuel.name = "Apparence"
	add_child(_visuel)
	_construire_apparence()
	visible = false
	set_process(false)


# --- apparence : un skieur de SkieurMesh, skis à la main ---------------------

func _mm(m: Mesh, couleurs: Color) -> MultiMeshInstance3D:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = m
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D.IDENTITY)
	mm.set_instance_custom_data(0, couleurs)
	var mi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 1 | Cabin.LAYER_VOIE       # éclairé par les gares et le jour
	_visuel.add_child(mi)
	return mi


func _construire_apparence() -> void:
	var mat: Material = SkieurMesh.materiau()
	# graines de couleurs : veste rouge, casque blanc… (fixes)
	var graine: Color = Color(0.21, 0.63, 0.37, 1.0)
	_images.append(SkieurMesh.passager("skis", "casque", mat))
	for i in range(N_IMAGES):
		_images.append(SkieurMesh.passager_squelette(_squelette_marche(TAU * i / N_IMAGES),
			"skis", "casque", mat))
	_corps = _mm(_images[0], graine)
	_skis_main = SkieurMesh.skis(mat)
	_skis = _mm(_skis_main, Color(0.55, 0.30, 0.80, 1.0))
	_skis.position = SkieurMesh.ANCRE_SKIS
	# chaussé : posture de glisse, skis aux pieds, deux bâtons
	_image_glisse = SkieurMesh.passager_squelette(SkieurMesh.squelette_glisse(), "libre", "casque", mat)
	_image_schuss = SkieurMesh.passager_squelette(SkieurMesh.squelette_schuss(), "libre", "casque", mat)
	_image_chasse = SkieurMesh.passager_squelette(SkieurMesh.squelette_chasse(), "libre", "casque", mat)
	for k in range(4):
		_images_poussee.append(SkieurMesh.passager_squelette(SkieurMesh.squelette_poussee(k), "libre", "casque", mat))
	_skis_pieds = SkieurMesh.skis_aux_pieds(mat)
	_skis_pieds_v = SkieurMesh.skis_aux_pieds(mat, SkieurMesh.CHASSE_ANGLE)
	_batons = _mm(SkieurMesh.baton(mat), Color(0.55, 0.30, 0.80, 1.0))
	_batons.multimesh.instance_count = 2
	_poser_batons(0)
	for k in range(2):
		_batons.multimesh.set_instance_custom_data(k, Color(0.55, 0.30, 0.80, 1.0))
	_batons.visible = false


## Squelette de la marche à la phase `ph` : jambes en ciseaux, bras gauche
## qui balance à contretemps (le droit tient les skis).
static func _squelette_marche(ph: float) -> Dictionary:
	var s: Dictionary = SkieurMesh.squelette("skis")
	var a: float = sin(ph)
	for c in ["g", "d"]:
		var sg: float = a if c == "g" else -a
		var leve: float = maxf(0.0, (cos(ph) if c == "g" else -cos(ph))) * 0.07
		s["genou_" + c] = (s["genou_" + c] as Vector3) + Vector3(0.0, leve * 0.6, -0.13 * sg - leve * 0.4)
		s["cheville_" + c] = (s["cheville_" + c] as Vector3) + Vector3(0.0, leve, -0.20 * sg)
	for k in ["coude_g", "poignet_g", "main_g"]:
		var f: float = {"coude_g": 0.05, "poignet_g": 0.13, "main_g": 0.16}[k]
		s[k] = (s[k] as Vector3) + Vector3(0.0, 0.0, f * a)
	return s


# --- activation ------------------------------------------------------------------

func activer(position_depart: Vector3, regard: float) -> void:
	global_position = position_depart
	velocity = Vector3.ZERO
	cam_yaw = regard
	_cap = regard
	if dernier_sol == Vector3.ZERO:
		dernier_sol = position_depart
	support = null
	lever()
	actif = true
	visible = true
	set_process(true)
	camera.make_current()


func desactiver(rester_visible: bool = false) -> void:
	actif = false
	# à pied (sur le quai, dans la gare, dehors), il reste où on l'a laissé,
	# visible (retour d'utilisateur, 11/10/2026 : « mon skieur attend la rame au bord
	# du quai ; quand je quitte le mode skieur pour la conduire, il a
	# disparu ») ; à bord, il se fond dans les passagers
	visible = rester_visible and support == null
	set_process(false)
	chemin.clear()


## Chausser ou déchausser (bouton CHAUSSER, touche E) : renvoie la raison
## d'un refus, ou "".
func basculer_ski(forcer: bool = false) -> String:
	# assis en remontée : on ne chausse ni ne déchausse (il se retrouvait
	# debout sur le siège — retour d'utilisateur, 23/10/2026)
	if embarque:
		return "Pas pendant la remontée"
	lever()
	if _chute_t > 0.0:
		_chute_t = 0.0
		_relever()
	if chausse:
		chausse = false
		_v_ski = Vector3.ZERO
		velocity = Vector3.ZERO
		_penche = 0.0
		dernier_sol = global_position
		_apparence_ski()
		return ""
	if relief == null or not relief.pret or support != null:
		return "On chausse dehors, sur la neige"
	if not relief.dans_le_bloc(global_position.x, global_position.z):
		return "Hors du domaine"
	if not forcer and not dehors(relief):
		# dans un bâtiment : non ; SOUS la surface (on a traversé la montagne
		# à pied, là où le relief n'avait pas encore de collision) : on
		# remonte sur la neige (retour d'utilisateur, 08/10/2026 : « il croit que je suis
		# dedans et m'empêche de chausser »)
		var tp: Array = relief.terrain_piece(global_position.x, global_position.z)
		if not is_nan(float(tp[0])) and bool(tp[1]):
			return "On chausse dehors, sur la neige"
		global_position.y = relief.hauteur_sol(global_position.x, global_position.z) + 0.05
		velocity = Vector3.ZERO
	chausse = true
	chemin.clear()
	_cap_ski = _cap
	_v_ski = Vector3.ZERO
	# le sol sous les pieds, quai de gare compris : sur le relief, on passait
	# SOUS un quai surélevé et le siège ne nous prenait plus (Leissières en
	# haut — retour d'utilisateur, 25/10/2026)
	global_position.y = float(_sol_ski(global_position.x, global_position.z, global_position.y)[0])
	_apparence_ski()
	return ""


## S'asseoir sur un banc (mode BOUCLE) : debout devant l'assise, regard
## `cap` ; le corps recule au-dessus du banc, skis posés (cachés).
func asseoir(cap: float, skis_aux_pieds: bool = false) -> void:
	if assis or (chausse and not skis_aux_pieds):
		return
	if _image_assise == null:
		_image_assise = SkieurMesh.passager("assis", "casque", SkieurMesh.materiau())
	assis = true
	_cap = cap
	cam_yaw = cap                  # la vue face à la marche, une fois assis
	cam_pitch = 0.10               # regard vers l'amont (la pente remplissait l'écran)
	velocity = Vector3.ZERO
	_corps.multimesh.mesh = _image_assise
	# au télésiège, chaussé : skis aux pieds, sous les pieds pendants (ils
	# disparaissaient — retour d'utilisateur, 23/10/2026) ; sinon posés
	_skis.visible = chausse
	if chausse:
		_skis.multimesh.mesh = _skis_pieds
		_skis.position = Vector3(0.0, 0.0, -RECUL_ASSIS)
	_visuel.rotation = Vector3(0.0, cap, 0.0)
	_visuel.position = Vector3(sin(cap), 0.0, cos(cap)) * RECUL_ASSIS


func lever() -> void:
	if not assis:
		return
	assis = false
	_skis.visible = true
	_visuel.position = Vector3(0.0, Y_SKI if chausse else 0.0, 0.0)
	_visuel.rotation = Vector3.ZERO
	_corps.multimesh.mesh = _image_glisse if chausse else _images[0]
	if chausse:
		_apparence_ski()


## Vitesse de glisse (m/s), 0 à pied.
func vitesse_ski() -> float:
	return _v_ski.length() if chausse else 0.0


func _apparence_ski() -> void:
	_posture = 0
	_image_poussee = -1
	_corps.multimesh.mesh = _image_glisse if chausse else _images[0]
	_poser_batons(0)
	_corps.position.y = 0.045 if chausse else 0.0
	_skis.multimesh.mesh = _skis_pieds if chausse else _skis_main
	_skis.position = Vector3.ZERO if chausse else SkieurMesh.ANCRE_SKIS
	_batons.visible = chausse
	_visuel.rotation = Vector3(0.0, _cap, 0.0)
	_visuel.position.y = Y_SKI if chausse else 0.0


## Claquement sec d'un pas en chaussures de ski (retour d'utilisateur, 09/10/2026 : « quand
## je marche sur les escaliers le long du quai sans les skis, rajoute un
## claquement sec à chaque pas ») : sons de tools_sons_skieur.py, trois
## variantes au hasard, hauteur légèrement variée, son POSITIONNEL (on
## l'entend aussi en vue extérieure, plus faible au loin).
var _pas: AudioStreamPlayer3D = null
var _sons_pas: Array = []


func _claquer() -> void:
	if _pas == null:
		for k in range(3):
			var st: AudioStream = load("res://sounds/pas_chaussure_%d.wav" % (k + 1))
			if st != null:
				_sons_pas.append(st)
		_pas = AudioStreamPlayer3D.new()
		_pas.volume_db = -4.0
		_pas.unit_size = 4.0
		_pas.max_distance = 40.0
		if PNConstants.safari_web():
			_pas.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		add_child(_pas)
		_pas.position = Vector3(0.0, 0.1, 0.0)
	if _sons_pas.is_empty():
		return
	_pas.stream = _sons_pas[randi() % _sons_pas.size()]
	_pas.pitch_scale = randf_range(0.92, 1.08)
	_pas.play()


## Posture de glisse : 0 glisse, 1 schuss (recroquevillé), 2 chasse-neige
## (skis en V).
func _poser_posture(p: int) -> void:
	if p == _posture:
		return
	_posture = p
	_image_poussee = -1
	_corps.multimesh.mesh = [_image_glisse, _image_schuss, _image_chasse][p]
	_skis.multimesh.mesh = _skis_pieds_v if p == 2 else _skis_pieds
	_poser_batons(p)


## Image k du cycle de poussée : corps et bâtons (posture 3).
func _poser_poussee(k: int) -> void:
	if _posture == 3 and k == _image_poussee:
		return
	_posture = 3
	_image_poussee = k
	_corps.multimesh.mesh = _images_poussee[k]
	_skis.multimesh.mesh = _skis_pieds
	for b in range(2):
		var sx: float = -1.0 if b == 0 else 1.0
		var m: Vector3 = SkieurMesh.POUSSEE_MAINS[k]
		var t: Vector3 = SkieurMesh.POUSSEE_POINTES[k]
		_poser_un_baton(b, Vector3(sx * m.x, m.y, m.z), Vector3(sx * t.x, t.y, t.z))


func _poser_un_baton(k: int, main_p: Vector3, pointe: Vector3) -> void:
	var ax: Vector3 = main_p - pointe
	var y: Vector3 = ax.normalized()
	var x: Vector3 = (Vector3.RIGHT - y * y.x).normalized()
	var z: Vector3 = x.cross(y)
	_batons.multimesh.set_instance_transform(k, Transform3D(
		Basis(x, y * (ax.length() / SkieurMesh.LONG_BATON), z), pointe))


## Bâtons selon la posture : en glisse et en chasse-neige plantés de part et
## d'autre ; en SCHUSS, poignées dans les mains devant le visage, bâtons
## serrés sous les bras, pointes vers l'arrière et un peu en l'air (retour d'utilisateur,
## 09/10/2026 : « en schuss les bâtons, c'est pas ça »).
func _poser_batons(p: int) -> void:
	for k in range(2):
		var sx: float = -1.0 if k == 0 else 1.0
		var main_p: Vector3 = Vector3(sx * 0.27, 0.945, -0.31)
		var pointe: Vector3 = Vector3(sx * 0.36, 0.0, 0.22)
		if p == 1:
			main_p = Vector3(sx * 0.15, 0.70, -0.46)
			pointe = Vector3(sx * 0.24, 0.86, 0.66)
		elif p == 2:
			main_p = Vector3(sx * 0.32, 0.84, -0.15)
			pointe = Vector3(sx * 0.52, 0.0, 0.30)
		var ax: Vector3 = main_p - pointe
		var y: Vector3 = ax.normalized()
		var x: Vector3 = (Vector3.RIGHT - y * y.x).normalized()
		var z: Vector3 = x.cross(y)
		_batons.multimesh.set_instance_transform(k, Transform3D(
			Basis(x, y * (ax.length() / SkieurMesh.LONG_BATON), z), pointe))


## Tombé : skis déchaussés, à terre sur le dos CHUTE_S secondes.
func _chuter() -> void:
	chausse = false
	_v_ski = Vector3.ZERO
	velocity = Vector3.ZERO
	_penche = 0.0
	dernier_sol = global_position
	_chute_t = CHUTE_S
	_apparence_ski()
	_visuel.rotation = Vector3(-1.35, _cap, 0.25)
	_visuel.position.y = 0.30
	chute.emit()


func _relever() -> void:
	_visuel.rotation = Vector3(0.0, _cap, 0.0)
	_visuel.position.y = 0.0


## À terre ?
func a_terre() -> bool:
	return _chute_t > 0.0


# --- entrées -----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not actif:
		return
	# souris émulée à partir du premier doigt (iPad) : la vue se tourne au
	# doigt par CommandesSkieur, sinon le joystick la ferait tourner aussi
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouse and (doigts > 0 or Time.get_ticks_msec() / 1000.0 - tactile_t < 0.6):
		return
	if event is InputEventMouseMotion and (event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)) != 0:
		tourner_vue(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = maxf(DIST_MIN, cam_dist * 0.88)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = minf(DIST_MAX, cam_dist / 0.88)


## Rotation de la vue (glissé de souris ou de doigt, en pixels).
func tourner_vue(d: Vector2) -> void:
	_vue_libre = 0.0
	_cam_v = 0.0
	cam_yaw -= d.x * 0.006
	cam_pitch = clampf(cam_pitch - d.y * 0.005, PITCH_MIN, _pitch_max())


## Regard vers le haut borné : en 3e personne, au-delà de ~14° la caméra
## passe sous les épaules et rase le sol (« la caméra se retrouve par
## terre ») ; en 1re personne, 35° suffisent.
const PITCH_MIN: float = -1.20
func _pitch_max() -> float:
	return 0.60 if premiere_personne else 0.25


func _clavier() -> Vector2:
	var v: Vector2 = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1.0
	v += Vector2(float((touches_ext >> 3) & 1) - float((touches_ext >> 2) & 1),
		float(touches_ext & 1) - float((touches_ext >> 1) & 1))
	return v.limit_length(1.0)


# --- boucle --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not actif:
		return
	delta = minf(delta, 0.05)
	_porter()
	_aligner_capsule()
	if embarque:
		velocity = Vector3.ZERO
		_camera()
		return
	if _chute_t > 0.0:
		_chute_t -= delta
		if _chute_t <= 0.0:
			_relever()
		_camera()
		return
	var cmd: Vector2 = entree
	var k: Vector2 = _clavier()
	if k.length() > 0.0:
		cmd = k
	# repère figé pour le JOYSTICK tactile seulement : au clavier, Z avance
	# là où regarde la vue et la souris dirige, comme dans tous les jeux PC
	# — figé aussi au clavier, le skieur gardait l'ancienne direction quand
	# on tournait la vue à la souris en marchant (retour d'utilisateur, 15/10/2026 :
	# « sur le programme PC, c'est la galère entre les touches, la souris
	# et la vue, le skieur ne va pas où il faut »)
	_maj_pouce(delta, entree if k.length() == 0.0 else Vector2.ZERO)
	var vite: bool = course or Input.is_physical_key_pressed(KEY_SHIFT) \
		or (touches_ext & 16) != 0 or entree.length() > 0.92     # joystick à fond : on court
	if chausse:
		if not chemin.is_empty():
			if pilote_expert:
				cmd = _pilote_expert()
				vite = _pilote_schuss
			else:
				cmd = _pilote_ski()
		elif k.length() == 0.0 and entree.length() > 0.12:
			cmd = _cmd_joystick_ski()
		_glisser(delta, cmd, vite)
		_vue_libre += delta
		_camera_ski(delta)
		_camera()
		return
	if assis:
		if chemin.is_empty() and cmd.length() < 0.08:
			velocity = Vector3.ZERO
			_camera()
			return
		lever()
	var dir: Vector3 = _direction(cmd)
	# horizon : en marchant, la vue revient doucement à l'horizontale 3 s
	# après qu'on l'a tournée à la main
	_vue_libre += delta
	if cmd.length() > 0.08 and _vue_libre > 3.0:
		cam_pitch = move_toward(cam_pitch, -0.10 if premiere_personne else -0.28, delta * 0.35)
	if not chemin.is_empty():
		dir = _suivre_chemin()
		vite = course_auto
	_marcher(delta, dir, vite)
	_trouver_support()
	_animer(delta, dir)
	_camera()


## Repère du pouce : pris sur la vue quand on pose le pouce (ou qu'on
## appuie sur une touche), figé tant qu'on tient, relâché après 0,2 s sans
## entrée.
func _maj_pouce(delta: float, cmd: Vector2) -> void:
	if cmd.length() > 0.08:
		if not _pouce_tenu:
			_ref_pouce = cam_yaw
			_pouce_tenu = true
		_pouce_lache_t = 0.0
	elif _pouce_tenu:
		_pouce_lache_t += delta
		if _pouce_lache_t > 0.2:
			_pouce_tenu = false


## Direction voulue (monde, horizontale) d'après la commande et la vue —
## celle du moment où l'on a posé le pouce (_maj_pouce).
func _direction(cmd: Vector2) -> Vector3:
	if cmd.length() < 0.08:
		return Vector3.ZERO
	var y: float = _ref_pouce if _pouce_tenu else cam_yaw
	var av: Vector3 = Vector3(-sin(y), 0.0, -cos(y))
	var dr: Vector3 = Vector3(cos(y), 0.0, -sin(y))
	return (av * cmd.y + dr * cmd.x).limit_length(1.0)


var _pt_prec: Vector3 = Vector3.ZERO     # dernier point atteint (pour reculer)
## Rayon où un point de `chemin` est atteint (serré pour entrer dans une
## porte de rame : la baie ne laisse que 11 cm de chaque côté)
var tolerance_chemin: float = 0.35
var _prog_d: float = INF                 # meilleure distance au point visé
var _prog_t: float = 0.0                 # temps sans progrès


func _suivre_chemin() -> Vector3:
	var cible: Vector3 = chemin[0]
	var d: Vector3 = cible - global_position
	d.y = 0.0
	var dist: float = d.length()
	if dist < tolerance_chemin:
		_pt_prec = chemin.pop_front()
		_prog_d = INF
		_prog_t = 0.0
		return Vector3.ZERO
	# bloqué (un vantail qui s'ouvre, un coin) : après 2,5 s sans avancer,
	# on recule au point précédent et l'on réessaie
	if dist < _prog_d - 0.15:
		_prog_d = dist
		_prog_t = 0.0
	else:
		_prog_t += get_process_delta_time()
		if _prog_t > 2.5 and _pt_prec != Vector3.ZERO:
			chemin.push_front(_pt_prec)
			_pt_prec = Vector3.ZERO
			_prog_d = INF
			_prog_t = 0.0
			return Vector3.ZERO
	return d.normalized()


## Aide au contournement (retour d'utilisateur, 12/10/2026 : « quand le skieur sur
## le quai marche trop près du funi, il reste coincé contre ») : bloqué de
## face contre un angle (bout d'un pan de caisse au bord d'une baie de
## porte, chambranle, poteau), le glissement le long du mur ne donne rien —
## on essaie la marche voulue tournée de ±30°, ±50°, ±75°, et l'on prend la
## première direction libre, de préférence celle qui s'écarte de l'obstacle.
func _contourner(voulu: Vector3, nm: Vector3) -> void:
	# d'abord ressortir du renfoncement : 2 cm le long des normales de
	# contact (au bord d'une baie de porte ouverte, le bout du pan d'un côté,
	# le fond de la baie de l'autre : leur somme pointe vers le quai)
	var sortie: Vector3 = Vector3.ZERO
	for i in range(get_slide_collision_count()):
		var nk: Vector3 = get_slide_collision(i).get_normal()
		nk.y = 0.0
		sortie += nk
	var vn: Vector3 = Vector3(voulu.x, 0.0, voulu.z).normalized()
	if sortie.length() > 1e-3:
		sortie = sortie.normalized()
		if sortie.dot(vn) < -0.7:
			# obstacle pile en face (bout d'un pan au bord d'une baie) : on
			# s'écarte de 3 cm du côté OPPOSÉ à la poussée latérale — c'est
			# elle qui l'avait fait entrer de 3 cm dans l'embrasure
			var lat: Vector3 = vn - sortie * vn.dot(sortie)
			var cote: Vector3 = Vector3(-vn.z, 0.0, vn.x)
			if lat.length() > 1e-3 and lat.dot(cote) > 0.0:
				cote = -cote
			elif lat.length() <= 1e-3:
				cote = cote if not test_move(global_transform.translated(Vector3.UP * 0.02), cote * 0.05) else -cote
			if not test_move(global_transform.translated(Vector3.UP * 0.02), cote * 0.03):
				global_position += cote * 0.03
				return
		elif not test_move(global_transform.translated(Vector3.UP * 0.02), sortie * 0.02):
			global_position += sortie * 0.02
	var depart: Transform3D = global_transform.translated(Vector3.UP * 0.02)
	for a in [0.52, 0.87, 1.31]:
		var meilleur: Vector3 = Vector3.ZERO
		var score: float = -INF
		for sg in [1.0, -1.0]:
			var c: Vector3 = voulu.rotated(Vector3.UP, a * sg)
			if test_move(depart, c):
				continue
			var sc: float = c.normalized().dot(nm)
			if sc > score:
				score = sc
				meilleur = c
		if meilleur != Vector3.ZERO:
			global_position += meilleur
			return


var _pos_marche_prec: Vector3 = Vector3.ZERO
var _avance_moy: float = 0.0
var _marche_t: float = 0.0


func _marcher(delta: float, dir: Vector3, vite: bool) -> void:
	var v_cible: Vector3 = dir * (V_COURSE if vite else V_MARCHE)
	var vh: Vector3 = Vector3(velocity.x, 0.0, velocity.z).move_toward(v_cible, ACCEL * delta)
	velocity.x = vh.x
	velocity.z = vh.z
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0) - G * delta * 0.1
	else:
		velocity.y -= G * delta
	var avant: Vector3 = global_position
	move_and_slide()
	# contremarche : bloqué par un « mur » alors qu'on avance → monter
	var fait: Vector3 = global_position - avant
	fait.y = 0.0
	var voulu: Vector3 = v_cible * delta
	# progression NETTE dans la direction voulue (moyenne sur ~0,3 s) : contre
	# un angle, il avançait de 2 cm puis était repoussé de 2 cm, image après
	# image — immobile sans jamais paraître bloqué
	if voulu.length() > 1e-4:
		var net: Vector3 = global_position - _pos_marche_prec
		net.y = 0.0
		_avance_moy = lerpf(_avance_moy, net.dot(voulu.normalized()) / maxf(delta, 1e-3), minf(1.0, delta * 4.0))
		if _avance_moy < 0.25 * v_cible.length() and is_on_wall() and _marche_t > 0.4:
			var nw: Vector3 = get_wall_normal()
			nw.y = 0.0
			_contourner(voulu, nw.normalized() if nw.length() > 1e-4 else Vector3.ZERO)
		_marche_t += delta
	else:
		_avance_moy = 0.0
		_marche_t = 0.0
	_pos_marche_prec = global_position
	if voulu.length() > 1e-4 and fait.length() < voulu.length() * 0.5 and is_on_wall():
		# marche montée par le haut (40 cm) ; si la tête cogne, au plus juste
		# (15 cm : les marches du quai font 7 cm) — contre la rame, soulevé de
		# 40 cm, il heurtait le flanc bombé de la caisse au-dessus du quai et
		# restait coincé devant chaque marche (retour d'utilisateur, 12/10/2026)
		if not _monter_marche(voulu) and not _monter_marche(voulu, 0.15) \
				and not (grimpe and support == null and not chausse and _monter_marche(voulu, GRIMPE_MAX, 0.6)):
			# pas une marche : on glisse le long du mur (porte-skis abordé
			# presque de face, contremarche, chambranle) — move_and_slide
			# s'arrêtait net quand le mur était presque perpendiculaire à la
			# marche ; second passage avec la vitesse projetée sur le mur
			var nm: Vector3 = get_wall_normal()
			nm.y = 0.0
			if nm.length() > 1e-4:
				nm = nm.normalized()
				var glisse: Vector3 = voulu - nm * voulu.dot(nm)
				glisse.y = 0.0
				# pas de côté kinématique (un move_and_slide de plus restait
				# collé : déjà en contact, le balayage s'arrête à t = 0) ;
				# l'essai se fait 2 cm au-dessus du sol, sinon le contact au
				# sol compte déjà comme un obstacle
				# glissement qui n'avance presque pas (mur de face : il ne
				# reste que la poussée de côté, qui l'enfonçait dans le
				# renfoncement d'une porte) → contournement
				if glisse.length() >= voulu.length() * 0.5 \
						and not test_move(global_transform.translated(Vector3.UP * 0.02), glisse):
					global_position += glisse
				else:
					_contourner(voulu, nm)
	if is_on_floor():
		_chute = 0.0
		if support == null and get_floor_normal().y > 0.9:
			_sol_stable += delta
			if _sol_stable > 0.6:
				dernier_sol = global_position     # sol fixe depuis un moment
		else:
			_sol_stable = 0.0
	else:
		_sol_stable = 0.0
		if _chute == 0.0:
			_depart_chute = global_position
		_chute += delta
		if _chute > 2.5:
			# tombé dans un trou (fosse, vide) : retour au dernier sol sûr ;
			# au troisième rattrapage en 30 s, au refuge (gare)
			var t: float = Time.get_ticks_msec() / 1000.0
			_chutes = _chutes.filter(func(x): return t - float(x) < 30.0)
			_chutes.append(t)
			var ou: Vector3 = dernier_sol if dernier_sol != Vector3.ZERO else refuge
			if _chutes.size() >= 3 and refuge != Vector3.ZERO:
				ou = refuge
				_chutes.clear()
			if ou == Vector3.ZERO:
				ou = _depart_chute      # ni sol sûr ni refuge : là où la chute a commencé
				                        # (avant : l'origine du monde, la gare basse)
			global_position = ou + Vector3(0.0, 0.3, 0.0)
			velocity = Vector3.ZERO
			support = null
			_chute = 0.0


## Monte une marche (≤ MARCHE_MAX) : soulever, avancer, reposer.
var debug_marche: String = ""


func _monter_marche(pas: Vector3, haut_max: float = MARCHE_MAX, plat_min: float = 0.9) -> bool:
	var xf: Transform3D = global_transform
	var haut: Vector3 = Vector3.UP * haut_max
	var col_p: KinematicCollision3D = KinematicCollision3D.new()
	if test_move(xf, haut, col_p):
		debug_marche = "plafond"
		if OS.is_debug_build() and col_p.get_collider() != null:
			var op: Object = col_p.get_collider()
			var ownp: Object = (op as CollisionObject3D).shape_owner_get_owner(
				(op as CollisionObject3D).shape_find_owner(col_p.get_collider_shape_index()))
			debug_marche += " (%s, y %.2f)" % [(ownp as Node).name if ownp else "?",
				col_p.get_position().y - global_position.y]
		return false
	# assez loin pour que le centre soit au-dessus de la marche
	var av: Vector3 = pas.normalized() * maxf(pas.length(), RAYON + 0.06)
	var xf_h: Transform3D = xf.translated(haut)
	var col_h: KinematicCollision3D = KinematicCollision3D.new()
	if test_move(xf_h, av, col_h):
		debug_marche = "bloqué en haut"
		if OS.is_debug_build() and col_h.get_collider() != null:
			var o: Object = col_h.get_collider()
			var own: Object = (o as CollisionObject3D).shape_owner_get_owner(
				(o as CollisionObject3D).shape_find_owner(col_h.get_collider_shape_index()))
			debug_marche += " (%s, n %.2f, y %.2f)" % [(own as Node).name if own else "?",
				col_h.get_normal().y, col_h.get_position().y - global_position.y]
		return false
	var xf_a: Transform3D = xf_h.translated(av)
	var col: KinematicCollision3D = KinematicCollision3D.new()
	if not test_move(xf_a, Vector3.DOWN * (haut_max + 0.02), col):
		debug_marche = "rien dessous"
		return false
	# sol plat à l'aplomb du centre (pas une paroi de rame en pente, pas
	# le dessus d'une main courante)
	var bas: Vector3 = xf_a.origin + col.get_travel()
	var rq: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		bas + Vector3.UP * 0.30, bas + Vector3.DOWN * 0.15, collision_mask, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(rq)
	if hit.is_empty() or (hit["normal"] as Vector3).y < plat_min:
		debug_marche = "pas de sol plat"
		return false
	debug_marche = "ok"
	global_position = xf_a.origin + col.get_travel()
	return true


## Emporté par la voiture : on lui applique le déplacement de la voiture
## depuis l'image précédente (position et cap). Y compris le RETOURNEMENT
## de la rame au changement de sens en gare (le simulateur la fait pivoter
## de 180° pour mettre la cabine de conduite à l'avant) : il reste à sa
## place dans sa voiture. Un grand saut (rame replacée ailleurs, nouveau
## voyage) ne l'emporte pas.
func _porter() -> void:
	if support == null:
		return
	if not is_instance_valid(support):
		support = null
		return
	var xf: Transform3D = support.global_transform
	var d: Transform3D = xf * _support_xf.affine_inverse()
	var p: Vector3 = d * global_position
	if p.distance_to(global_position) < 60.0:
		global_position = p
		var dl: float = wrapf(atan2(d.basis.z.x, d.basis.z.z), -PI, PI)
		cam_yaw += dl
		_cap += dl
	else:
		support = null
	_support_xf = xf


## Dans une voiture, la capsule prend l'INCLINAISON de la voiture, et le
## « haut » de la marche aussi (08/10/2026) : à mi-tunnel la caisse penche de
## 16,7° (pente 30 %) ; porte-skis et bancs, fixés au plancher, penchent avec
## elle. Une capsule verticale dans le monde avait son haut décalé de 50 cm
## vers le bas de la pente et accrochait le haut des porte-skis — « bloqué
## par les derniers porte-skis, je ne peux pas accéder à l'avant ».
func _aligner_capsule() -> void:
	if _capsule == null:
		return
	var b: Basis = Basis.IDENTITY
	if support != null and is_instance_valid(support):
		b = support.global_transform.basis.orthonormalized()
	_capsule.transform = Transform3D(b, b * Vector3(0.0, TAILLE * 0.5, 0.0))
	up_direction = b.y.normalized()


## Le sol sous ses pieds (rayon vertical : immobile, il n'y a pas de
## contact de glissement) : une voiture, ou le décor.
func _trouver_support() -> void:
	if not is_on_floor():
		return
	var p: Vector3 = global_position
	var rq: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		p + Vector3.UP * 0.30, p + Vector3.DOWN * 0.35, collision_mask, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(rq)
	if hit.is_empty():
		return
	var trouve: Node3D = null
	var o: Object = hit["collider"]
	if o != null and o is Node and (o as Node).has_meta("vehicule"):
		trouve = (o as Node).get_meta("vehicule") as Node3D
	else:
		# le quai est au niveau du plancher de la rame : dans la baie d'une
		# porte, le rayon touchait la rampe du quai un peu au-dessus du
		# seuil → plus de support, la rame repartait sans lui ou le
		# « percutait » (retour d'utilisateur, 13/10/2026 : « passé à travers
		# la cloison, portes fermées, coincé dans le quai »). Une voiture
		# juste sous ses pieds, et lui dans sa caisse, reste son support
		rq.collision_mask = CollisionsJeu.COUCHE_VEHICULE
		var hv: Dictionary = get_world_3d().direct_space_state.intersect_ray(rq)
		if not hv.is_empty() and (hv["position"] as Vector3).y > (hit["position"] as Vector3).y - 0.15:
			var ov: Object = hv["collider"]
			if ov != null and ov is Node and (ov as Node).has_meta("vehicule"):
				var vv: Node3D = (ov as Node).get_meta("vehicule") as Node3D
				if absf((vv.global_transform.affine_inverse() * p).x) < 1.70:
					trouve = vv
	if trouve != support:
		support = trouve
		if support != null:
			_support_xf = support.global_transform


# --- glisse ---------------------------------------------------------------------------

## Un pas de glisse. `cmd` : x virage (droite +), y + pousser / − chasse-neige.
## Le skieur reste posé sur le sol affiché (ReliefBuilder.hauteur_sol) ; sa
## vitesse est dans le plan de la pente : la pesanteur la tire vers le bas,
## les carres absorbent ce qui part en travers des skis, la neige et l'air
## la freinent.
## Chasse-neige automatique (s) : posé à l'arrêt au lâcher d'une perche, il
## tient sur la pente tant que le joueur ne commande rien.
var frein_auto: float = 0.0


func _glisser(delta: float, cmd: Vector2, schuss: bool) -> void:
	if frein_auto > 0.0:
		frein_auto -= delta
		if cmd.length() < 0.1:
			cmd = Vector2(0.0, -1.0)
		else:
			frein_auto = 0.0
	var p: Vector3 = global_position
	var n: Vector3 = _sol_ski(p.x, p.z, p.y)[1]
	var v: Vector3 = _v_ski
	var vit: float = v.length()
	var vit0: float = vit
	# posture : chasse-neige dès qu'on freine, poussée animée quand il pousse
	# sur ses bâtons, schuss quand il file sans pousser
	var expert: bool = pilote_expert and not chemin.is_empty()
	if cmd.y < -0.2 and vit > 0.5 and not expert:
		_poser_posture(2)
	elif _pousse:
		_poussee_t += delta
		_poser_poussee(int(_poussee_t * 4.0 * 1.1) % 4)    # ~1,1 cycle par seconde
	else:
		_poussee_t = 0.0
		_poser_posture(1 if (schuss and vit > 3.0) else 0)
	# virage : les skis pivotent, d'autant moins vite qu'on va vite
	var omega: float = minf(OMEGA_SKI, (A_VIRAGE_EXPERT if expert else A_VIRAGE) / maxf(vit, 0.1))
	_cap_ski -= cmd.x * omega * delta
	var av_h: Vector3 = Vector3(-sin(_cap_ski), 0.0, -cos(_cap_ski))
	var d: Vector3 = (av_h - n * av_h.dot(n)).normalized()
	# pesanteur le long de la pente : g − (g·n) n
	var g_t: Vector3 = Vector3.DOWN * G + n * (G * n.y)
	v += g_t * delta
	# carres : la vitesse en travers des skis est absorbée
	var lat: Vector3 = v - d * v.dot(d)
	v -= lat * minf(1.0, (ADHERENCE_EXPERT if expert else ADHERENCE) * delta)
	# neige et air ; chasse-neige
	vit = v.length()
	var dec: float = MU_NEIGE * G * n.y + (K_AIR_SCHUSS if schuss else K_AIR) * vit * vit
	if cmd.y < -0.2:
		dec += (DEC_DERAPAGE if expert else DEC_CHASSE) * minf(1.0, -cmd.y)
	if vit > 1e-3:
		v *= maxf(0.0, vit - dec * delta) / vit
	# immobile sur une pente douce : il tient
	if v.length() < 0.3 and g_t.length() < MU_ARRET * G and cmd.y <= 0.2:
		v = Vector3.ZERO
	# pas de patineur, poussée des bâtons ; en montée, en canard, plus lent
	var v_av: float = v.dot(d)
	var v_pas: float = V_PAS * cmd.y * clampf(1.0 - 4.0 * d.y, 0.35, 1.0)
	_pousse = cmd.y > 0.2 and v_av < v_pas + 0.3
	if cmd.y > 0.2 and v_av < v_pas:
		v += d * minf(v_pas - v_av, A_PAS * delta)
	v = v.limit_length(V_MAX_SKI)
	# déplacement à l'horizontale, arrêté par les murs, puis posé sur le sol
	var dp: Vector3 = Vector3(v.x, 0.0, v.z) * delta
	var mur: Vector3 = _mur_devant(p, dp)
	# chute : un mur à vive allure, ou la roche (pente > 37°) — éteint
	if CHUTES_ACTIVES and ((mur != Vector3.ZERO and vit0 > V_CHUTE_MUR and dp.dot(mur) < 0.0) \
			or (n.y < 0.80 and vit0 > V_CHUTE_ROCHE)):
		_chuter()
		return
	if mur != Vector3.ZERO:
		if dp.dot(mur) < 0.0:
			dp -= mur * dp.dot(mur)
		if v.dot(mur) < 0.0:
			v -= mur * v.dot(mur)
	var q: Vector3 = p + dp
	if not relief.dans_le_bloc(q.x, q.z):
		q = p
		v = Vector3.ZERO
	var sol: Array = _sol_ski(q.x, q.z, p.y)
	q.y = sol[0]
	global_position = q
	# vitesse remise dans le plan de la pente d'arrivée
	var n2: Vector3 = sol[1]
	var m: float = v.length()
	v -= n2 * v.dot(n2)
	if v.length() > 1e-4:
		v = v.normalized() * m
	# penché dans le virage (accélération latérale v·ω)
	# (expert : angulation jusqu'à ~57°, comme en géant)
	var lim_p: float = 1.0 if expert else 0.6
	var cible: float = clampf(-cmd.x * omega * m / G, -lim_p, lim_p)
	_penche = lerpf(_penche, cible, minf(1.0, delta * 6.0))
	_v_ski = v
	velocity = v
	_cap = _cap_ski
	_visuel.rotation = Vector3(0.0, _cap_ski, _penche)
	_visuel.visible = not premiere_personne


## Sol sous les skis en (x, z) : [hauteur, normale]. Le relief, ou plus
## haut une plate-forme de gare (quai, talus, rampe : collisions du décor)
## sur laquelle on glisse — avant, à ski, seul le relief comptait et le
## skieur qui se levait du télésiège passait sous la gare (retour
## d'utilisateur, 23/10/2026). `y_ref` : hauteur actuelle (on ne monte pas
## sur un toit : la plate-forme doit être à moins de 0,6 m au-dessus).
func _sol_ski(x: float, z: float, y_ref: float) -> Array:
	var h: float = relief.hauteur_sol(x, z)
	var n: Vector3 = relief.normale_sol(x, z)
	# le relief passe au-dessus des skis (tunnel de piste) : s'il y a un sol
	# du décor juste dessous, c'est lui — on ne grimpe pas sur la montagne
	# (le relief monte de quelques dizaines de cm par image à la tête du
	# tunnel : un seuil sur l'écart ne suffisait pas)
	if h > y_ref + 0.05:
		var rq0: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			Vector3(x, y_ref + 0.6, z), Vector3(x, y_ref - 1.5, z), CollisionsJeu.COUCHE_DECOR, [get_rid()])
		var hit0: Dictionary = get_world_3d().direct_space_state.intersect_ray(rq0)
		if not hit0.is_empty() and (hit0["normal"] as Vector3).y > 0.6 and h > (hit0["position"] as Vector3).y + 0.3:
			return [(hit0["position"] as Vector3).y, (hit0["normal"] as Vector3).normalized()]
	var haut: float = maxf(y_ref, h) + 0.6
	if haut > h + 0.05:
		var rq: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			Vector3(x, haut, z), Vector3(x, h, z), CollisionsJeu.COUCHE_DECOR, [get_rid()])
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(rq)
		if not hit.is_empty() and (hit["normal"] as Vector3).y > 0.6:
			return [(hit["position"] as Vector3).y, (hit["normal"] as Vector3).normalized()]
	return [h, n]


## Mur devant (bâtiment, quai, porte : collisions des gares) dans le sens
## du déplacement : sa normale horizontale, ou ZERO.
func _mur_devant(p: Vector3, dp: Vector3) -> Vector3:
	var l: float = dp.length()
	if l < 1e-5:
		return Vector3.ZERO
	var dir: Vector3 = dp / l
	for h in [0.4, 1.2]:
		var a: Vector3 = p + Vector3.UP * h
		var rq: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			a, a + dir * (l + RAYON + 0.15), CollisionsJeu.COUCHE_DECOR | CollisionsJeu.COUCHE_VEHICULE, [get_rid()])
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(rq)
		if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < 0.5:
			var nm: Vector3 = hit["normal"]
			nm.y = 0.0
			return nm.normalized()
	return Vector3.ZERO


## Caméra de poursuite à ski : derrière les SKIS (le cap que l'on commande,
## pas la trajectoire qui dérape), par un ressort critique dont la vitesse
## de rotation est bornée à 50 °/s ; suspendue 2 s après une rotation de la
## vue à la main (« toujours honorer l'intention du joueur »), et sous 1,5 m/s
## (à l'arrêt, la vue ne bouge pas). Le relèvement contre le relief est
## lissé (avant : par à-coups).
func _camera_ski(delta: float) -> void:
	var vh: Vector3 = Vector3(_v_ski.x, 0.0, _v_ski.z)
	if vh.length() > 1.5 and _vue_libre > VUE_MAIN_PAUSE:
		var e: float = wrapf(_cap_ski - cam_yaw, -PI, PI)
		_cam_v += (CAM_OMEGA * CAM_OMEGA * e - 2.0 * CAM_OMEGA * _cam_v) * delta
		_cam_v = clampf(_cam_v, -CAM_V_MAX, CAM_V_MAX)
		cam_yaw += _cam_v * delta
		cam_pitch = lerpf(cam_pitch, -0.30, minf(1.0, delta * 0.8))
	else:
		_cam_v = move_toward(_cam_v, 0.0, CAM_V_MAX * delta * 4.0)
		cam_yaw += _cam_v * delta
	# jamais sous la pente derrière lui (le relief n'a de collisions
	# qu'autour des gares) : on relève doucement, on redescend plus doucement
	# encore, avec une marge (sinon ça pompe)
	var sous_terre: bool = relief.hauteur_sol(global_position.x, global_position.z) > global_position.y + 1.0
	if not premiere_personne and not sous_terre:
		var cp: Vector3 = camera.global_position
		var marge: float = cp.y - (relief.hauteur_sol(cp.x, cp.z) + 0.7)
		if marge < 0.0:
			_pitch_sol = minf(_pitch_sol + delta * 0.9, 0.8)
		elif marge > 0.6:
			_pitch_sol = maxf(_pitch_sol - delta * 0.3, 0.0)


## Joystick à ski, comme dans les jeux (09/10/2026, retour d'utilisateur : « refonds le
## pilotage au joystick, c'est le binz ») : on POINTE le joystick là où l'on
## veut aller, par rapport à l'écran — haut = tout droit dans l'axe de la
## caméra, à droite = vers la droite de l'écran… Les skis tournent vers ce
## cap (virage plus ou moins serré selon l'inclinaison du joystick) et la
## caméra ne bouge pas tant qu'on vise de côté : on traverse la pente au
## lieu de tourner en rond (avant : le joystick était un volant et la
## caméra suivait, tenu à droite on faisait des cercles). Tiré vers soi :
## chasse-neige. Poussé vers le haut à l'arrêt : on pousse sur les bâtons.
func _cmd_joystick_ski() -> Vector2:
	var a: float = atan2(entree.x, entree.y)          # 0 haut, + droite
	var force: float = clampf((entree.length() - 0.12) / 0.88, 0.0, 1.0)
	if absf(a) > 2.3:
		return Vector2(0.0, -force)                   # vers soi : chasse-neige
	var cap_voulu: float = (_ref_pouce if _pouce_tenu else cam_yaw) - a
	var e: float = wrapf(cap_voulu - _cap_ski, -PI, PI)
	var y: float = 0.0
	if _v_ski.length() < 3.0 and absf(a) < 0.8:
		y = force                                     # à l'arrêt : pousser
	return Vector2(clampf(-e * 2.2, -1.0, 1.0) * maxf(force, 0.35), y)


## Pilote à ski (bancs, mode AUTO) : vise le point suivant de `chemin`,
## ralentit avant de tourner.
func _pilote_expert() -> Vector2:
	var p: Vector3 = global_position
	var vit: float = _v_ski.length()
	# points dépassés : à moins de 4 m, ou quand le suivant est plus proche
	while chemin.size() > 1:
		var d0: float = Vector2(chemin[0].x - p.x, chemin[0].z - p.z).length()
		var d1: float = Vector2(chemin[1].x - p.x, chemin[1].z - p.z).length()
		if d0 < 4.0 or d1 < d0:
			chemin.pop_front()
			_ski_prog_d = INF
			_ski_prog_t = 0.0
		else:
			break
	if chemin.size() == 1 and Vector2(chemin[0].x - p.x, chemin[0].z - p.z).length() < 4.0:
		chemin.pop_front()
		_pilote_schuss = false
		return Vector2.ZERO
	# pas de progrès depuis 6 s (creux, contre-pente) : point suivant
	var d_vise: float = Vector2(chemin[0].x - p.x, chemin[0].z - p.z).length()
	if d_vise < _ski_prog_d - 1.0:
		_ski_prog_d = d_vise
		_ski_prog_t = 0.0
	else:
		_ski_prog_t += get_process_delta_time()
		if _ski_prog_t > 6.0 and chemin.size() > 1:
			chemin.pop_front()
			_ski_prog_d = INF
			_ski_prog_t = 0.0
	# point visé à une distance qui croît avec la vitesse (poursuite pure)
	var l_vise: float = clampf(0.7 * vit + 6.0, 7.0, 28.0)
	var cible: Vector2 = Vector2(chemin[0].x, chemin[0].z)
	var acc: float = Vector2(p.x, p.z).distance_to(cible)
	var i: int = 0
	while acc < l_vise and i + 1 < chemin.size():
		var a2: Vector2 = Vector2(chemin[i].x, chemin[i].z)
		var b2: Vector2 = Vector2(chemin[i + 1].x, chemin[i + 1].z)
		var seg: float = a2.distance_to(b2)
		if acc + seg >= l_vise:
			cible = a2.lerp(b2, (l_vise - acc) / maxf(seg, 1e-3))
			acc = l_vise
			break
		acc += seg
		cible = b2
		i += 1
	var vers: Vector2 = cible - Vector2(p.x, p.z)
	var e: float = wrapf(atan2(-vers.x, -vers.y) - _cap_ski, -PI, PI)
	# vitesse permise par les courbes à venir (sur 90 m) : rayon local R,
	# v² ≤ A_PLAN·R, et le freinage possible d'ici là (v² ≤ v_lim² + 2·a·d)
	var v_lim: float = V_EXPERT
	var d_cum: float = 0.0
	var j: int = 0
	while j + 2 < chemin.size() and d_cum < 90.0:
		var q0: Vector2 = Vector2(chemin[j].x, chemin[j].z)
		var q1: Vector2 = Vector2(chemin[j + 1].x, chemin[j + 1].z)
		var q2: Vector2 = Vector2(chemin[j + 2].x, chemin[j + 2].z)
		var l1: float = q0.distance_to(q1)
		var l2: float = q1.distance_to(q2)
		d_cum += l1
		if l1 > 0.5 and l2 > 0.5:
			var dth: float = absf(wrapf((q2 - q1).angle() - (q1 - q0).angle(), -PI, PI))
			if dth > 0.01:
				var r_loc: float = (l1 + l2) * 0.5 / dth
				var v_loc: float = sqrt(A_PLAN * r_loc + 2.0 * DEC_DERAPAGE * 0.6 * d_cum)
				v_lim = minf(v_lim, v_loc)
		j += 1
	# fin du tracé (pied de la gare) : arrêt en douceur, pas à 80 km/h
	var d_reste: float = Vector2(p.x, p.z).distance_to(Vector2(chemin[0].x, chemin[0].z))
	for jj in range(chemin.size() - 1):
		d_reste += Vector2(chemin[jj].x, chemin[jj].z).distance_to(Vector2(chemin[jj + 1].x, chemin[jj + 1].z))
		if d_reste > 200.0:
			break
	if d_reste <= 200.0:
		v_lim = minf(v_lim, sqrt(2.0 * DEC_DERAPAGE * 0.6 * d_reste) + 1.5)
	# en virage serré (on tourne fort maintenant) : on ralentit aussi
	v_lim = minf(v_lim, lerpf(V_EXPERT, 9.0, clampf((absf(e) - 0.25) / 0.9, 0.0, 1.0)))
	var y: float = 0.0
	if vit > v_lim + 0.5:
		y = -clampf((vit - v_lim) / 4.0, 0.3, 1.0)
	elif vit < 3.0:
		y = 1.0
	_pilote_schuss = vit < v_lim - 2.0 and absf(e) < 0.12 and vit > 6.0
	return Vector2(clampf(-e * 2.6, -1.0, 1.0), y)


func _pilote_ski() -> Vector2:
	var cible: Vector3 = chemin[0]
	var vers: Vector3 = cible - global_position
	vers.y = 0.0
	if vers.length() < 14.0:
		chemin.pop_front()
		_ski_prog_d = INF
		_ski_prog_t = 0.0
		return Vector2.ZERO
	# pas de progrès vers ce point depuis 6 s (creux, point en contre-haut
	# qu'on n'atteint pas en poussant) : on vise le suivant — sinon il
	# oscillait sur place jusqu'à la fin du délai (09/10/2026, relief élargi)
	if vers.length() < _ski_prog_d - 1.0:
		_ski_prog_d = vers.length()
		_ski_prog_t = 0.0
	else:
		_ski_prog_t += get_process_delta_time()
		if _ski_prog_t > 6.0 and chemin.size() > 1:
			chemin.pop_front()
			_ski_prog_d = INF
			_ski_prog_t = 0.0
			return Vector2.ZERO
	var e: float = wrapf(atan2(-vers.x, -vers.z) - _cap_ski, -PI, PI)
	var vit: float = _v_ski.length()
	var v_but: float = lerpf(vitesse_pilote, 4.0, clampf(absf(e) / 1.2, 0.0, 1.0))
	var y: float = 0.0
	if vit > v_but:
		y = -clampf((vit - v_but) / 3.0, 0.3, 1.0)
	elif vit < 2.5:
		y = 1.0
	return Vector2(clampf(-e * 2.0, -1.0, 1.0), y)


# --- apparence et caméra -----------------------------------------------------------

func _animer(delta: float, dir: Vector3) -> void:
	var vh: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var vitesse: float = vh.length()
	if dir.length() > 0.05:
		var cap_voulu: float = atan2(-dir.x, -dir.z)
		_cap = lerp_angle(_cap, cap_voulu, minf(1.0, delta * 10.0))
	_visuel.rotation = Vector3(0.0, _cap, 0.0)
	var image: int = 0
	if vitesse > 0.15 and is_on_floor():
		var demi_avant: int = int(_phase / PI)
		_phase = fmod(_phase + delta * vitesse / 0.62 * PI, TAU)
		# un pas à chaque demi-cycle : claquement des chaussures de ski sur
		# un sol dur (quais, escaliers, rames, terrasse) — pas dans la neige
		if int(_phase / PI) != demi_avant and not dehors(relief):
			_claquer()
		image = 1 + int(_phase / TAU * N_IMAGES) % N_IMAGES
	else:
		_phase = 0.0
	if _corps.multimesh.mesh != _images[image]:
		_corps.multimesh.mesh = _images[image]
	# skis portés à la main : soulevés en marchant
	_skis.position = SkieurMesh.ANCRE_SKIS + Vector3(0.0, 0.14 if image > 0 else 0.0, 0.0)
	_visuel.visible = not premiere_personne


func _camera() -> void:
	cam_pitch = clampf(cam_pitch, PITCH_MIN, _pitch_max())
	pivot.rotation = Vector3(clampf(cam_pitch - _pitch_sol, PITCH_MIN, _pitch_max()), cam_yaw, 0.0)
	bras.spring_length = 0.0 if premiere_personne else cam_dist
	# en remontée, la caméra de dos passe à travers le véhicule (vitré) :
	# arrêtée par ses parois, elle restait enfermée dans la cabine portes
	# fermées (retour d'utilisateur, 23/10/2026) ; dans le funiculaire, elle reste
	# dans la rame
	bras.collision_mask = CollisionsJeu.COUCHE_DECOR if embarque else (CollisionsJeu.COUCHE_DECOR | CollisionsJeu.COUCHE_VEHICULE)
	pivot.position.y = Y_YEUX if premiere_personne else Y_YEUX - 0.05
	pivot.position.x = 0.0
	pivot.position.z = 0.0
	if premiere_personne:
		# on ne se voit pas soi-même, à pied, à ski ou en remontée (retour
		# d'utilisateur, 23/10/2026 : « à la première personne sur le TS je me vois »)
		_visuel.visible = false
		if assis:
			# yeux du passager assis : au-dessus du bassin (en arrière des
			# pieds), à 1,25 m au-dessus des pieds
			pivot.position = Vector3(_visuel.position.x * 0.9, Y_YEUX_ASSIS, _visuel.position.z * 0.9)
	elif not _visuel.visible and _chute_t <= 0.0:
		_visuel.visible = true


## Le skieur est-il à l'air libre (ni dans une gare, ni dans le tunnel) ?
func dehors(relief: ReliefBuilder) -> bool:
	if relief == null or support != null:
		return false
	var h: float = relief.hauteur(global_position.x, global_position.z)
	var tp: Array = relief.terrain_piece(global_position.x, global_position.z)
	if not is_nan(float(tp[0])):
		if bool(tp[1]):
			return false          # dans un bâtiment
		h = float(tp[0])
	return global_position.y > h - 3.0
