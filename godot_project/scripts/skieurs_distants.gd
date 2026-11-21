## Mode réseau : les autres joueurs du salon (ReseauClient), dessinés avec le skieur commun (SkieurMesh) dans la
## posture qu'ils envoient (à ski, à pied, assis, debout à bord), habillés selon leur couleur (graine du nuanceur),
## leur nom au-dessus de la tête.
class_name SkieursDistants
extends Node3D

const MAX: int = 8
const HAUTEUR_NOM: float = 2.15

var _mm: Array = []           # [ski corps, skis aux pieds, à pied, assis, debout]
var _noms: Array = []         # Label3D par place
var positions: Array = []     # pieds dessinés (bancs)


func _ready() -> void:
	name = "SkieursDistants"
	var mat: ShaderMaterial = SkieurMesh.materiau()
	var maill: Array = [
		SkieurMesh.passager_squelette(SkieurMesh.squelette_glisse(), "skis", "casque", mat),
		SkieurMesh.skis_aux_pieds(mat),
		SkieurMesh.passager("skis", "casque", mat),
		SkieurMesh.passager("assis", "casque", mat),
		SkieurMesh.passager("debout", "casque", mat)]
	for m in maill:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = m
		mm.instance_count = MAX
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 2000.0
		mi.top_level = true
		add_child(mi)
		_mm.append(mm)
	for k in range(MAX):
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0016
		l.font_size = 28
		l.outline_size = 8
		l.modulate = Color(1, 1, 1)
		l.outline_modulate = Color(0, 0, 0, 0.85)
		l.visible = false
		l.top_level = true
		add_child(l)
		_noms.append(l)


## liste : [[pieds (Vector3), cap, posture, couleur, nom], …]
func poser(liste: Array) -> void:
	if _mm.is_empty():
		return
	var n: Array = [0, 0, 0, 0, 0]
	positions.clear()
	for k in range(mini(liste.size(), MAX)):
		var e: Array = liste[k]
		var p: Vector3 = e[0]
		var b: Basis = Basis(Vector3.UP, float(e[1]))
		var po: int = int(e[2])
		var c: Color = e[3]
		var graine: Color = Color(c.r, c.g, c.b, 1.0)
		var quoi: Array = [0, 1] if po == 0 or po == 4 else ([2] if po == 1 or po == 5 else ([3] if po == 2 else [4]))
		for q in quoi:
			var mm: MultiMesh = _mm[q]
			var j: int = n[q]
			mm.set_instance_transform(j, Transform3D(b, p))
			mm.set_instance_custom_data(j, graine)
			n[q] = j + 1
		var l: Label3D = _noms[k]
		l.text = String(e[4])
		l.global_position = p + Vector3(0.0, HAUTEUR_NOM, 0.0)
		l.visible = true
		positions.append(p)
	for q2 in range(_mm.size()):
		(_mm[q2] as MultiMesh).visible_instance_count = n[q2]
	for k2 in range(liste.size(), MAX):
		(_noms[k2] as Label3D).visible = false


func vider() -> void:
	poser([])
