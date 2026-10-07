class_name SkieurJoueur
extends CharacterBody3D
## Le skieur jouable (demande de Kevin du 07/10/2026 : « un skieur capable
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

const RAYON: float = 0.14              # de profil : il passe entre deux porte-skis
const TAILLE: float = 1.76
const MARCHE_MAX: float = 0.40
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


func _init() -> void:
	collision_layer = CollisionsJeu.COUCHE_SKIEUR
	collision_mask = CollisionsJeu.COUCHE_DECOR | CollisionsJeu.COUCHE_VEHICULE
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = MARCHE_MAX + 0.05
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
	_skis = _mm(SkieurMesh.skis(mat), Color(0.55, 0.30, 0.80, 1.0))
	_skis.position = SkieurMesh.ANCRE_SKIS


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
	dernier_sol = position_depart
	support = null
	actif = true
	visible = true
	set_process(true)
	camera.make_current()


func desactiver() -> void:
	actif = false
	visible = false
	set_process(false)
	chemin.clear()


# --- entrées -----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not actif:
		return
	# souris émulée à partir du premier doigt (iPad) : la vue se tourne au
	# doigt par CommandesSkieur, sinon le joystick la ferait tourner aussi
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
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
	cam_yaw -= d.x * 0.006
	cam_pitch = clampf(cam_pitch - d.y * 0.005, -1.30, 0.75)


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
	return v.limit_length(1.0)


# --- boucle --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not actif:
		return
	delta = minf(delta, 0.05)
	_porter()
	var cmd: Vector2 = entree
	var k: Vector2 = _clavier()
	if k.length() > 0.0:
		cmd = k
	var vite: bool = course or Input.is_physical_key_pressed(KEY_SHIFT)
	var dir: Vector3 = _direction(cmd)
	if not chemin.is_empty():
		dir = _suivre_chemin()
		vite = false
	_marcher(delta, dir, vite)
	_trouver_support()
	_animer(delta, dir)
	_camera()


## Direction voulue (monde, horizontale) d'après la commande et la vue.
func _direction(cmd: Vector2) -> Vector3:
	if cmd.length() < 0.08:
		return Vector3.ZERO
	var av: Vector3 = Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var dr: Vector3 = Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	return (av * cmd.y + dr * cmd.x).limit_length(1.0)


func _suivre_chemin() -> Vector3:
	var cible: Vector3 = chemin[0]
	var d: Vector3 = cible - global_position
	d.y = 0.0
	if d.length() < 0.35:
		chemin.pop_front()
		return Vector3.ZERO
	return d.normalized()


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
	if voulu.length() > 1e-4 and fait.length() < voulu.length() * 0.5 and is_on_wall():
		_monter_marche(voulu)
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
		_chute += delta
		if _chute > 2.5:
			# tombé dans un trou (fosse, vide) : retour au dernier sol sûr ;
			# au troisième rattrapage en 30 s, au refuge (gare)
			var t: float = Time.get_ticks_msec() / 1000.0
			_chutes = _chutes.filter(func(x): return t - float(x) < 30.0)
			_chutes.append(t)
			var ou: Vector3 = dernier_sol
			if _chutes.size() >= 3 and refuge != Vector3.ZERO:
				ou = refuge
				_chutes.clear()
			global_position = ou + Vector3(0.0, 0.3, 0.0)
			velocity = Vector3.ZERO
			support = null
			_chute = 0.0


## Monte une marche (≤ MARCHE_MAX) : soulever, avancer, reposer.
var debug_marche: String = ""


func _monter_marche(pas: Vector3) -> bool:
	var xf: Transform3D = global_transform
	var haut: Vector3 = Vector3.UP * MARCHE_MAX
	if test_move(xf, haut):
		debug_marche = "plafond"
		return false
	# assez loin pour que le centre soit au-dessus de la marche
	var av: Vector3 = pas.normalized() * maxf(pas.length(), RAYON + 0.06)
	var xf_h: Transform3D = xf.translated(haut)
	if test_move(xf_h, av):
		debug_marche = "bloqué en haut"
		return false
	var xf_a: Transform3D = xf_h.translated(av)
	var col: KinematicCollision3D = KinematicCollision3D.new()
	if not test_move(xf_a, Vector3.DOWN * (MARCHE_MAX + 0.02), col):
		debug_marche = "rien dessous"
		return false
	# sol plat à l'aplomb du centre (pas une paroi de rame en pente, pas
	# le dessus d'une main courante)
	var bas: Vector3 = xf_a.origin + col.get_travel()
	var rq: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		bas + Vector3.UP * 0.30, bas + Vector3.DOWN * 0.15, collision_mask, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(rq)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.9:
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
	if trouve != support:
		support = trouve
		if support != null:
			_support_xf = support.global_transform


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
		_phase = fmod(_phase + delta * vitesse / 0.62 * PI, TAU)
		image = 1 + int(_phase / TAU * N_IMAGES) % N_IMAGES
	else:
		_phase = 0.0
	if _corps.multimesh.mesh != _images[image]:
		_corps.multimesh.mesh = _images[image]
	# skis portés à la main : soulevés en marchant
	_skis.position = SkieurMesh.ANCRE_SKIS + Vector3(0.0, 0.14 if image > 0 else 0.0, 0.0)
	_visuel.visible = not premiere_personne


func _camera() -> void:
	pivot.rotation = Vector3(cam_pitch, cam_yaw, 0.0)
	bras.spring_length = 0.0 if premiere_personne else cam_dist
	pivot.position.y = Y_YEUX if premiere_personne else Y_YEUX - 0.05


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
