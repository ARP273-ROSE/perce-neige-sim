class_name MachineRoomCamera
extends Camera3D
## Vue « salle des machines » (demande du 2026-09-30) : caméra fixe par
## rapport à la gare amont — elle n'avance PAS avec le train — qui tourne
## dans tous les sens autour de la machinerie, zoome et se déplace.
##   souris : clic gauche maintenu = tourner, molette = zoom,
##            clic droit (ou milieu) maintenu = déplacer ;
##   tactile : 1 doigt = tourner, 2 doigts = pincer (zoom) et glisser
##            (déplacer).
## Les parois entre la caméra et les roues s'effacent (écorché, cf.
## MachineRoomBuilder.update_cutaway).

var room: MachineRoomBuilder = null
var yaw: float = 0.95          # autour de la verticale, depuis le côté droit en montant
var pitch: float = 0.32        # au-dessus (+) ou au-dessous (−) de l'horizontale
var dist: float = 11.0
var pan: Vector2 = Vector2.ZERO    # décalage du point visé (x travers, s long de la voie)
var pan_y: float = 0.0

const PITCH_MAX: float = 1.50  # ±86° : tout autour, sans basculer au zénith
const DIST_MIN: float = 1.2
const DIST_MAX: float = 25.0


func setup(r: MachineRoomBuilder) -> void:
	room = r
	fov = 66.0
	near = 0.05
	far = 600.0
	_update()


func rotate_by(dx: float, dy: float) -> void:
	yaw -= dx * 0.006
	pitch = clampf(pitch + dy * 0.006, -PITCH_MAX, PITCH_MAX)


func zoom(factor: float) -> void:
	dist = clampf(dist * factor, DIST_MIN, DIST_MAX)


## Déplace le point visé dans le plan de l'écran (pixels → mètres selon
## la distance), pour aller voir un moteur ou l'autre roue de près.
func pan_by(dx: float, dy: float) -> void:
	var k: float = dist * 0.0018
	var right: Vector3 = global_transform.basis.x
	var up: Vector3 = global_transform.basis.y
	var d_world: Vector3 = (-right * dx + up * dy) * k
	if room == null:
		return
	var f: Transform3D = room.frame()
	pan.x = clampf(pan.x + d_world.dot(f.basis.x), -8.0, 8.0)
	pan.y = clampf(pan.y - d_world.dot(f.basis.z), -10.0, 14.0)
	pan_y = clampf(pan_y + d_world.dot(f.basis.y), -4.0, 5.0)


func reset() -> void:
	yaw = 0.95
	pitch = 0.32
	dist = 11.0
	pan = Vector2.ZERO
	pan_y = 0.0


func _process(_delta: float) -> void:
	if current:
		_update()


func _update() -> void:
	if room == null or not is_inside_tree():
		return
	var f: Transform3D = room.frame()
	# repère horizontal de la gare amont : axe de la voie à plat, verticale vraie
	var fwd: Vector3 = -f.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	var target: Vector3 = room.focus_point() + f.basis.x * pan.x - f.basis.z * pan.y \
		+ Vector3.UP * pan_y
	# point visé ramené dans la salle
	if not _inside(target):
		pan = Vector2.ZERO
		pan_y = 0.0
		target = room.focus_point()
	var cp: float = cos(pitch)
	var dir: Vector3 = (right * sin(yaw) - fwd * cos(yaw)) * cp + Vector3.UP * sin(pitch)
	# la caméra reste DANS la salle (et le hall au-dessus de la dalle) :
	# on avance le long du rayon tant qu'on y est — sinon on se retrouvait
	# dans le rocher ou sous les quais de la gare
	var t: float = 0.0
	var step: float = 0.05
	while t + step <= dist and _inside(target + dir * (t + step)):
		t += step
	# … et ne finit jamais DANS une machine (armoire, moteur, réducteur) :
	# on la ramène vers le centre jusqu'à en sortir. On garde la vue
	# par-dessus les machines, contrairement à un arrêt au premier obstacle.
	var obst: Array = room.obstacle_aabbs()
	while t > 0.1 and _in_obstacle(target + dir * t, target, obst):
		t -= 0.1
	var eye: Vector3 = target + dir * maxf(t, 0.05)
	look_at_from_position(eye, target, Vector3.UP)
	room.update_cutaway(eye)


func _in_obstacle(p: Vector3, target: Vector3, obst: Array) -> bool:
	for bb in obst:
		if (bb as AABB).has_point(p) and not (bb as AABB).has_point(target):
			return true
	return false


## Volume où la caméra peut aller : salle des machines sous la dalle,
## hall de la gare au-dessus (repère de fin de ligne x, y, s).
func _inside(p: Vector3) -> bool:
	var f: Transform3D = room.frame()
	var rel: Vector3 = p - f.origin
	var x: float = rel.dot(f.basis.x)
	var y: float = rel.dot(f.basis.y)
	var s: float = -rel.dot(f.basis.z)
	const M: float = 0.3
	if y < MachineRoomBuilder.Y_SLAB_BOTTOM:
		return y > MachineRoomBuilder.ROOM_FLOOR + M \
			and absf(x) < MachineRoomBuilder.ROOM_HALF_W - 0.8 \
			and s > MachineRoomBuilder.ROOM_S0 + M and s < MachineRoomBuilder.ROOM_S1 - M
	return y < MachineRoomBuilder.Y_HALL_CEIL - M \
		and absf(x) < MachineRoomBuilder.HALL_HALF_W - M \
		and s > -6.0 and s < MachineRoomBuilder.HALL_DEPTH - M
