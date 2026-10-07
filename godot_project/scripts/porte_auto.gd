class_name PorteAuto
extends Node3D
## Porte coulissante automatique (entrée de la gare du bas, baies du mur de
## tête en haut) : elle s'ouvre quand quelqu'un s'approche — le skieur
## jouable (07/10/2026), dont main.gd pose la position dans `presences`.
## Ses vantaux sont des nœuds à part (groupe « collision_mobile ») : ils
## gardent leur collision en glissant.

## Positions monde des personnes qui déclenchent les portes.
static var presences: Array = []

const RAYON: float = 2.6
const DUREE: float = 1.1

var vantaux: Array = []                # [nœud, position fermée, course]
var _o: float = 0.0


## Un vantail : `course` = déplacement (repère de la porte) à l'ouverture.
func ajouter_vantail(n: Node3D, course: Vector3) -> void:
	if n.get_parent() != self:
		add_child(n)
	n.add_to_group("collision_mobile")
	vantaux.append([n, n.position, course])


func _process(delta: float) -> void:
	var proche: bool = false
	for p in presences:
		if global_position.distance_to(p) < RAYON:
			proche = true
			break
	var o: float = move_toward(_o, 1.0 if proche else 0.0, delta / DUREE)
	if o == _o:
		return
	_o = o
	var k: float = smoothstep(0.0, 1.0, _o)
	for v in vantaux:
		(v[0] as Node3D).position = (v[1] as Vector3) + (v[2] as Vector3) * k


## Ouverture actuelle (0 fermée, 1 ouverte).
func ouverture() -> float:
	return _o
