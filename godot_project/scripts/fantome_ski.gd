class_name FantomeSki
extends Node3D
## Fantôme d'une descente réelle d'un utilisateur (FantomesDonnees) : un skieur
## translucide qui refait la trace, seconde par seconde, posé sur le
## relief. Il part quand le skieur chaussé passe à son départ
## (DomaineSkiable.suivre).

var relief: ReliefBuilder = null
var actif: bool = false
var numero: int = -1
var duree: float = 0.0
var t: float = 0.0
var _pts: PackedVector2Array = PackedVector2Array()
var _corps: Node3D = null
var _nom: Label3D = null


## Ses deux maillages précalculés sur un fil de travail dès le chargement (PC) : 42 ms d'un bloc sur le fil
## principal à l'entrée en skieur sinon (relevé du 10/11/2026). Mêmes appels, mêmes maillages.
static var _pre: Array = []
static var _pre_tache: int = -1


static func precalculer() -> void:
	if _pre_tache >= 0 or not _pre.is_empty():
		return
	_pre_tache = WorkerThreadPool.add_task(_calculer.bind(_pre), true, "fantôme")


static func _calculer(d: Array) -> void:
	var mat: Material = SkieurMesh.materiau()
	d.append_array([SkieurMesh.passager_squelette(SkieurMesh.squelette_glisse(), "libre", "casque", mat),
			SkieurMesh.skis_aux_pieds(mat)])


func _ready() -> void:
	var verre: StandardMaterial3D = StandardMaterial3D.new()
	verre.albedo_color = Color(0.15, 0.45, 1.0, 0.55)   # bleu vif : se voit sur la neige
	verre.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	verre.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	verre.no_depth_test = false
	_corps = Node3D.new()
	add_child(_corps)
	if _pre_tache >= 0:
		WorkerThreadPool.wait_for_task_completion(_pre_tache)
		_pre_tache = -1
	var maillages: Array = []
	if not _pre.is_empty():
		maillages = _pre.duplicate()
		_pre.clear()
	else:
		_calculer(maillages)
	for m in maillages:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = verre
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 1 | Cabin.LAYER_VOIE
		_corps.add_child(mi)
	_corps.get_child(0).position.y = 0.045
	_nom = Label3D.new()
	_nom.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nom.font_size = 40
	_nom.pixel_size = 0.006
	_nom.modulate = Color(0.30, 0.60, 1.0, 1.0)
	_nom.outline_size = 8
	_nom.position.y = 2.4
	_nom.no_depth_test = true
	add_child(_nom)
	visible = false
	set_process(false)


func demarrer(k: int) -> void:
	numero = k
	duree = float(FantomesDonnees.DESCENTES[k][0])
	_pts = FantomesDonnees.points(k)
	t = 0.0
	actif = true
	visible = true
	_nom.text = "Fantôme — descente %d" % (k + 1)
	set_process(true)
	_placer()


func arreter() -> void:
	actif = false
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if Prof.actif:
		var t0_prof: int = Time.get_ticks_usec()
		_process_corps(delta)
		Prof.ajouter("fantome_ski", t0_prof)
	else:
		_process_corps(delta)


func _process_corps(delta: float) -> void:
	t += delta
	if t >= duree + 5.0:
		arreter()
		return
	_placer()


func _placer() -> void:
	var u: float = clampf(t, 0.0, duree)
	var i: int = mini(int(u), _pts.size() - 2)
	var a: Vector2 = _pts[i].lerp(_pts[i + 1], u - i)
	var j: int = mini(i + 2, _pts.size() - 1)
	var d: Vector2 = _pts[j] - _pts[maxi(i - 1, 0)]
	position = Vector3(a.x, relief.hauteur_sol(a.x, a.y), a.y)
	if d.length() > 0.5:
		_corps.rotation.y = lerp_angle(_corps.rotation.y, atan2(-d.x, -d.y), 0.2)
