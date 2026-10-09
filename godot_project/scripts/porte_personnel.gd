class_name PortePersonnel
extends Node3D
## Porte « réservé au personnel » du garde-corps, en haut des quais de Val
## Claret (retour d'utilisateur, 07/10/2026 : « au moment où on pousse la porte, ça sonne
## avec le son du klaxon puis ça s'arrête »). Le vantail pivote sur sa
## charnière quand quelqu'un (PorteAuto.presences) s'approche à moins de
## RAYON ; la sonnerie — le son du klaxon, une fois — retentit à chaque
## ouverture. Le vantail (nœud enfant, groupe « collision_mobile ») garde
## sa collision en tournant.

const RAYON: float = 0.95
const DUREE: float = 0.9
const ANGLE: float = deg_to_rad(95.0)
const TEMPO: float = 2.5             # s après le passage avant de se refermer

var vantail: Node3D = null
var sens: float = 1.0                # +1 / −1 : sens de rotation (vers l'amont)
var _o: float = 0.0
var _cible: float = 0.0
var _t_libre: float = 0.0
var _son: AudioStreamPlayer3D = null
var sonneries: int = 0               # nombre de sonneries (bancs)


## `n` : le vantail (origine sur la charnière) ; `vers` : direction monde
## dans laquelle il doit s'ouvrir (vers l'amont, loin du quai).
func poser(n: Node3D, vers: Vector3) -> void:
	vantail = n
	if n.get_parent() != self:
		add_child(n)
	n.add_to_group("collision_mobile")
	# quel sens de rotation éloigne le bout du vantail dans `vers` ?
	var bout: Vector3 = Vector3.ZERO
	for c in n.get_children():
		if c is MeshInstance3D:
			var m: MeshInstance3D = c
			bout = n.global_transform.affine_inverse() * (m.global_transform * m.get_aabb().get_center())
			break
	var essai: Vector3 = Basis(Vector3.UP, 0.3) * bout - bout
	sens = 1.0 if essai.dot(n.global_transform.basis.inverse() * vers) >= 0.0 else -1.0
	_son = AudioStreamPlayer3D.new()
	var st: AudioStream = load("res://sounds/klaxon.wav")
	if st is AudioStreamWAV:
		st = (st as AudioStreamWAV).duplicate()
		(st as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	_son.stream = st
	_son.volume_db = -4.0
	_son.max_distance = 30.0
	_son.unit_size = 3.0
	if PNConstants.safari_web():
		_son.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_son)


func _process(delta: float) -> void:
	if vantail == null:
		return
	var proche: bool = false
	for p in PorteAuto.presences:
		if global_position.distance_to(p) < RAYON + 0.5 \
				and vantail.global_position.distance_to(p) < RAYON + 1.0:
			proche = true
			break
	if proche:
		_t_libre = 0.0
		if _cible < 0.5:
			_cible = 1.0
			_sonner()
	else:
		_t_libre += delta
		if _t_libre > TEMPO:
			_cible = 0.0
	var o: float = move_toward(_o, _cible, delta / DUREE)
	if o == _o:
		return
	_o = o
	vantail.rotation = Vector3(0.0, sens * ANGLE * smoothstep(0.0, 1.0, _o), 0.0)


func _sonner() -> void:
	sonneries += 1
	if _son != null and _son.stream != null:
		_son.play()


func ouverture() -> float:
	return _o
