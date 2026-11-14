class_name VuesRemontee
extends Node3D
## Vues de spectateur sur la remontée où l'on est assis : comme les vues du
## funiculaire (poste, extérieur orbital, salle des machines), mais pour
## n'importe quelle ligne (retour d'utilisateur, 14/11/2026 : « sur le funi
## j'ai plein d'options de vue, est-ce possible de transférer ça à n'importe
## quelle remontée ? »).
##
## Vues, dans l'ordre du bouton VUE LIGNE (touche T) :
##   0 skieur      : la vue habituelle (1re / 3e personne, touche V) ;
##   1 orbite      : autour du véhicule ; glisser pour tourner, molette ou
##                   pincement pour la distance (mêmes gestes que le skieur) ;
##   2 pylône      : depuis la tête du prochain pylône, téléobjectif ;
##   3 gare        : depuis la gare d'arrivée, regard vers la ligne ;
##   4 travelling  : de côté, à hauteur du câble, la portée et sa flèche ;
##   5 drone       : au-dessus et en arrière, la ligne devant soi.
## Funival (souterrain) : skieur et orbite rapprochée seulement.
##
## Tout est calculé par différences à partir des positions monde (pas de
## composition de Transform3D en float32 loin de l'origine, cf. PLAN_COEUR
## 09/11). La caméra skieur reprend la main dès qu'on quitte la remontée.

const NOMS: Array = ["SKIEUR", "ORBITE", "PYLÔNE", "GARE", "TRAVELLING", "DRONE"]
const SKIEUR: int = 0
const ORBITE: int = 1
const PYLONE: int = 2
const GARE: int = 3
const TRAVELLING: int = 4
const DRONE: int = 5

var main: Node = null
var skieur: SkieurJoueur = null
var mode: int = SKIEUR
var camera: Camera3D = null

var _ligne: LigneRemontee = null
var _i_veh: int = -1
var _pos_prec: Vector3 = Vector3.ZERO
var _sens: Vector3 = Vector3.ZERO        # direction de marche du véhicule (monde, horizontale)
var _pyl_vise: int = -1                  # indice du pylône de la vue PYLÔNE
var _lisse: bool = false                 # position de caméra déjà amorcée (lissage)


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "CameraLigne"
	camera.near = 0.1
	camera.far = 20000.0
	add_child(camera)
	set_process(true)


## La ligne et le véhicule qui portent le skieur, ou [null, -1].
func _porteur() -> Array:
	if main == null:
		return [null, -1]
	var rm: Node = main.get("remontees")
	if rm == null:
		return [null, -1]
	var ab: Array = rm.get("a_bord")
	if ab.is_empty() or not (ab[0] is LigneRemontee) or not is_instance_valid(ab[0]):
		return [null, -1]
	return [ab[0], int(ab[1])]


## Vues proposées pour la ligne : le Funival, sous terre, n'a que l'orbite rapprochée.
func _vues_possibles(lg: LigneRemontee) -> Array:
	if lg is Funival:
		return [SKIEUR, ORBITE]
	var v: Array = [SKIEUR, ORBITE]
	if not lg.pylones.is_empty():
		v.append(PYLONE)
	v.append_array([GARE, TRAVELLING, DRONE])
	return v


## Disponible seulement à bord d'une remontée.
func possible() -> bool:
	return _porteur()[0] != null


## Nom de la vue en cours, pour le bouton.
func nom() -> String:
	return NOMS[mode]


## Vue suivante (bouton VUE LIGNE, touche T). Renvoie le nom de la vue, "" hors remontée.
func suivante() -> String:
	var p: Array = _porteur()
	if p[0] == null:
		_rendre()
		return ""
	var vues: Array = _vues_possibles(p[0])
	var k: int = vues.find(mode)
	mode = vues[(k + 1) % vues.size()]
	_pyl_vise = -1
	_lisse = false
	if mode == SKIEUR:
		_rendre()
	return NOMS[mode]


## Retour à la caméra du skieur.
func _rendre() -> void:
	mode = SKIEUR
	_ligne = null
	_i_veh = -1
	_lisse = false
	if camera != null and camera.current and skieur != null and skieur.camera != null:
		skieur.camera.make_current()


func reinitialiser() -> void:
	_rendre()


func _process(delta: float) -> void:
	if mode == SKIEUR:
		return
	if skieur == null or not skieur.actif or main == null or not bool(main.get("mode_skieur")):
		_rendre()
		return
	var p: Array = _porteur()
	var lg: LigneRemontee = p[0]
	if lg == null or not lg.pret:
		_rendre()           # descendu de la remontée : la vue du skieur revient
		return
	if lg != _ligne or int(p[1]) != _i_veh:
		_ligne = lg
		_i_veh = int(p[1])
		_lisse = false
		_pyl_vise = -1
		if not _vues_possibles(lg).has(mode):
			mode = ORBITE
	# on vise le skieur, assis ou accroché : le nœud du véhicule peut être
	# figé par le niveau de détail (MultiMesh) alors que le skieur, lui, suit
	var cible: Vector3 = skieur.global_position + Vector3(0, 0.6, 0)
	# sens de marche : par différence de positions (le véhicule peut être sur
	# le brin montant ou descendant), repli sur l'axe de la ligne
	var axe: Vector3 = -lg.global_basis.z
	axe.y = 0.0
	axe = axe.normalized()
	var dp: Vector3 = cible - _pos_prec
	dp.y = 0.0
	if _lisse and dp.length() > 0.02 and dp.length() < 30.0:
		_sens = _sens.lerp(dp.normalized(), clampf(delta * 3.0, 0.0, 1.0)).normalized()
	elif _sens == Vector3.ZERO or not _lisse:
		var d_loc: float = -lg.to_local(cible).z
		_sens = axe if d_loc < lg.longueur_h() * 0.5 else -axe
	_pos_prec = cible
	var pos: Vector3
	var regard: Vector3 = cible
	var fov: float = 70.0
	var lisser: bool = true
	match mode:
		ORBITE:
			var dist: float = 4.0 + skieur.cam_dist * 2.4
			if lg is Funival:
				dist = minf(dist, 7.0)
			var elev: float = clampf(-skieur.cam_pitch, -0.15, 1.35)
			var yaw: float = skieur.cam_yaw
			pos = cible + Vector3(sin(yaw) * cos(elev), sin(elev), cos(yaw) * cos(elev)) * dist
			regard = cible + Vector3(0, 0.5, 0)
			lisser = false
		PYLONE:
			pos = _vue_pylone(lg, cible)
			if pos == Vector3.INF:
				pos = _vue_gare(lg, cible)
			lisser = false
			fov = _teleobjectif(pos.distance_to(cible), 10.0)
		GARE:
			pos = _vue_gare(lg, cible)
			lisser = false
			fov = _teleobjectif(pos.distance_to(cible), 12.0)
		TRAVELLING:
			var cote: Vector3 = Vector3(-_sens.z, 0.0, _sens.x)
			# du côté extérieur du brin où l'on est (on voit le véhicule, pas l'autre brin)
			var x_loc: float = lg.to_local(cible).x
			var s: float = signf(x_loc) if absf(x_loc) > 0.3 else 1.0
			if cote.dot(lg.global_basis.x) * s < 0.0:
				cote = -cote
			pos = cible + cote * 26.0 + Vector3(0, 3.0, 0) - _sens * 4.0
			regard = cible + _sens * 4.0
			fov = 55.0
		DRONE:
			pos = cible - _sens * 40.0 + Vector3(0, 28.0, 0)
			regard = cible + _sens * 25.0
			fov = 65.0
	pos = _au_dessus_du_sol(pos, 2.5)
	if lisser and _lisse:
		pos = camera.global_position.lerp(pos, clampf(delta * 5.0, 0.0, 1.0))
	_lisse = true
	camera.global_position = pos
	if pos.distance_to(regard) > 0.05:
		var haut: Vector3 = Vector3.UP
		if absf((regard - pos).normalized().dot(Vector3.UP)) > 0.98:
			haut = _sens
		camera.look_at(regard, haut)
	camera.fov = fov
	if skieur.camera != null:
		camera.far = skieur.camera.far
		camera.cull_mask = skieur.camera.cull_mask
		camera.environment = skieur.camera.environment
		camera.attributes = skieur.camera.attributes
	if not camera.current:
		camera.make_current()


## Champ resserré pour garder le véhicule à une taille lisible à l'écran.
func _teleobjectif(dist: float, cadre: float) -> float:
	return clampf(rad_to_deg(2.0 * atan(cadre * 0.5 / maxf(dist, 1.0))) * 2.2, 6.0, 70.0)


## Tête du prochain pylône devant le véhicule (dans son sens de marche), ou INF.
func _vue_pylone(lg: LigneRemontee, cible: Vector3) -> Vector3:
	var loc: Vector3 = lg.to_local(cible)
	var d_veh: float = -loc.z
	var monte: bool = _sens.dot(-lg.global_basis.z) > 0.0
	# garde le pylône visé jusqu'à ce que le véhicule l'ait dépassé de 15 m (plan de coupe net)
	if _pyl_vise >= 0 and _pyl_vise < lg.pylones.size():
		var dv: float = float(lg.pylones[_pyl_vise]["d"])
		if (monte and d_veh < dv + 15.0) or (not monte and d_veh > dv - 15.0):
			return _tete(lg, dv, loc.x)
	var best: int = -1
	var dmin: float = INF
	for k in range(lg.pylones.size()):
		var dk: float = float(lg.pylones[k]["d"])
		var ecart: float = (dk - d_veh) if monte else (d_veh - dk)
		if ecart > 5.0 and ecart < dmin:
			dmin = ecart
			best = k
	_pyl_vise = best
	if best < 0:
		return Vector3.INF
	return _tete(lg, float(lg.pylones[best]["d"]), loc.x)


## Point de vue à la tête d'un pylône, un peu à l'extérieur du brin du véhicule.
func _tete(lg: LigneRemontee, d: float, x_veh: float) -> Vector3:
	var s: float = signf(x_veh) if absf(x_veh) > 0.3 else 1.0
	var monte: bool = x_veh * (1.0 if lg.sens_droite else -1.0) >= 0.0
	var y: float = lg.y_cable(d, monte) + 2.5
	return lg.to_global(Vector3(s * (absf(x_veh) + 4.0), y, -d))


## Au nez de la gare d'arrivée, à côté de la ligne, au-dessus du câble.
func _vue_gare(lg: LigneRemontee, cible: Vector3) -> Vector3:
	var loc: Vector3 = lg.to_local(cible)
	var monte: bool = _sens.dot(-lg.global_basis.z) > 0.0
	var L: float = lg.longueur_h()
	var d: float = L - 6.0 if monte else 6.0
	var s: float = signf(loc.x) if absf(loc.x) > 0.3 else 1.0
	var y: float = maxf(lg.y_cable(d, true), lg.terrain(d)) + 7.0
	return lg.to_global(Vector3(s * (lg.voie * 0.5 + 7.0), y, -d))


## La caméra ne passe jamais sous le relief (vue de côté sur un versant, drone en contre-pente).
func _au_dessus_du_sol(p: Vector3, marge: float) -> Vector3:
	var relief: Node = main.get("relief") if main != null else null
	if relief == null or not relief.has_method("hauteur"):
		return p
	var h: float = float(relief.hauteur(p.x, p.z))
	if is_nan(h):
		return p
	if p.y < h + marge:
		p.y = h + marge
	return p
