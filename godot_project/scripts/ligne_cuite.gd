## Remontée vue de loin, sans aucun nœud : le fichier écrit par cuisson_ligne.gd, posé directement sur
## le serveur de rendu. Géométrie fixe, véhicules en instances le long de leur trajet, phase du câble.
## Pas de collisions ni de pièces animées : de près, c'est la ligne construite qui prend le relais.
class_name LigneCuite
extends RefCounted

const VERSION: int = 2
## Sur un fil de travail : au plus ce volume de sommets envoyés au rendu par image (les ordres
## partent tous d'un coup au début de l'image suivante).
const OCTETS_IMAGE: int = 1000000
const FIL_US: int = 4000

## Matériaux partagés entre lignes : recréés à chaque chargement, leurs shaders se recompilaient.
static var _materiaux_communs: Dictionary = {}
static var _shaders: Dictionary = {}
static var _verrou: Mutex = Mutex.new()

var cle: String = ""
var xf: Transform3D = Transform3D.IDENTITY
var _d: Dictionary = {}
var _mats: Array = []
var _meshes: Array = []
var _instances: Array = []
var _multis: Array = []
var _veh: Array = []                # MultiMesh des véhicules, un par surface
var _cable: Array = []              # ShaderMaterial du câble
var _visible: bool = true
var _trajet: PackedFloat32Array = PackedFloat32Array()
var _pas_t: float = 0.5
var _n_points: int = 0
var _periode: float = 0.0
var _phases: PackedFloat32Array = PackedFloat32Array()
var _t: float = 0.0
var _vitesse_cable: float = 0.0
var _pas_cable: float = 1.0
var _phase_cable: float = 0.0
var _octets: int = 0
var _t_fil: int = 0
var _sur_fil: bool = false
var lecture_ms: float = 0.0


static func chemin(dossier: String, nom: String, web: bool) -> String:
	return dossier.path_join(nom + (".web.cuit" if web else ".cuit"))


var _chemin: String = ""


func preparer_chemin(fichier: String) -> void:
	_chemin = fichier


## Lecture puis pose (freinée sur un fil de travail). Sans fichier valable, `cle` reste vide.
func charger(scenario: RID, sur_fil: bool) -> void:
	if lire(_chemin):
		poser(scenario, sur_fil)
	else:
		cle = ""


## Lit et décompresse le fichier (à faire sur un fil de travail). Faux si absent ou d'une autre version.
func lire(fichier: String) -> bool:
	var t0: int = Time.get_ticks_usec()
	var f: FileAccess = FileAccess.open(fichier, FileAccess.READ)
	if f == null:
		return false
	var n: int = f.get_32()
	var z: PackedByteArray = f.get_buffer(f.get_length() - 4)
	f.close()
	_d = bytes_to_var(z.decompress(n, FileAccess.COMPRESSION_ZSTD))
	lecture_ms = (Time.get_ticks_usec() - t0) / 1000.0
	if int(_d.get("version", 0)) != VERSION:
		_d = {}
		return false
	cle = _d["cle"]
	xf = _d["xf_ligne"]
	return true


## Crée d'avance les matériaux de ce fichier : leurs shaders compilés au chargement du jeu,
## plus au premier passage. Sur le fil principal.
func preparer_materiaux() -> void:
	for md in _d["materiaux"]:
		_mats.append(_materiau(md))


## Dépose tout sur le serveur de rendu. `sur_fil` : freiné pour un fil de travail.
func poser(scenario: RID, sur_fil: bool) -> void:
	_sur_fil = sur_fil
	_t_fil = Time.get_ticks_usec()
	if _mats.is_empty():
		preparer_materiaux()
	for s in _d["surfaces"]:
		var me: RID = _maillage(s["surface"], int(s["mat"]))
		var ins: RID = RenderingServer.instance_create2(me, scenario)
		RenderingServer.instance_set_transform(ins, xf)
		_regler(ins, s)
		_instances.append(ins)
		_pause()
	for s in _d["instances"]:
		_multi(s["surface"], int(s["mat"]), s["xfs"], s, scenario)
		_pause()
	for g in _d["mobiles"]:
		for s in g["surfaces"]:
			_multi(s["surface"], int(s["mat"]), _composer(g["xf_racines"], g["xf"]), g, scenario)
			_pause()
	_preparer_vehicules(scenario)
	_vitesse_cable = float(_d.get("vitesse_cable", 0.0))
	_pas_cable = float(_d.get("pas_cable", 1.0))
	for m in _mats:
		if m is ShaderMaterial:
			_cable.append(m)
	_d = {}


func _preparer_vehicules(scenario: RID) -> void:
	_trajet = _d.get("trajet", PackedFloat32Array())
	_pas_t = float(_d.get("pas_t", 0.5))
	_n_points = _trajet.size() / 4
	_periode = _pas_t * _n_points
	_phases = _d.get("phases", PackedFloat32Array())
	if _n_points < 2 or _phases.is_empty():
		return
	var vide: PackedFloat32Array = PackedFloat32Array()
	vide.resize(_phases.size() * 12)
	vide.fill(0.0)
	for s in _d["vehicule_fusion"]:
		var me: RID = _maillage(s["surface"], int(s["mat"]))
		var mm: RID = RenderingServer.multimesh_create()
		RenderingServer.multimesh_set_mesh(mm, me)
		RenderingServer.multimesh_allocate_data(mm, _phases.size(), RenderingServer.MULTIMESH_TRANSFORM_3D)
		RenderingServer.multimesh_set_buffer(mm, vide)
		RenderingServer.multimesh_set_custom_aabb(mm, _d["boite_ligne"])
		var ins: RID = RenderingServer.instance_create2(mm, scenario)
		RenderingServer.instance_set_transform(ins, xf)
		_regler(ins, {"portee": 0.0, "ombre": s["ombre"], "couches": s.get("couches", 5)})
		_instances.append(ins)
		_multis.append(mm)
		_veh.append(mm)
		_pause()


## Avance les véhicules de `dt` et envoie leurs poses (sens : le trajet est déjà dans le repère de la ligne).
func avancer(dt: float) -> void:
	_t += dt
	if not _cable.is_empty() and _vitesse_cable > 0.0:
		_phase_cable = fposmod(_phase_cable + _vitesse_cable * dt, _pas_cable)
		for m in _cable:
			(m as ShaderMaterial).set_shader_parameter("cable_phase", _phase_cable)
	if _veh.is_empty():
		return
	var n: int = _phases.size()
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n * 12)
	for i in range(n):
		var u: float = fposmod(_t + _phases[i], _periode) / _pas_t
		var k: int = int(u)
		var f: float = u - k
		var a: int = k * 4
		var b: int = ((k + 1) % _n_points) * 4
		var x: float = lerpf(_trajet[a], _trajet[b], f)
		var y: float = lerpf(_trajet[a + 1], _trajet[b + 1], f)
		var z: float = lerpf(_trajet[a + 2], _trajet[b + 2], f)
		var c: float = _trajet[a + 3]
		var cs: float = cos(c)
		var sn: float = sin(c)
		var q: int = i * 12
		buf[q] = cs
		buf[q + 1] = 0.0
		buf[q + 2] = sn
		buf[q + 3] = x
		buf[q + 4] = 0.0
		buf[q + 5] = 1.0
		buf[q + 6] = 0.0
		buf[q + 7] = y
		buf[q + 8] = -sn
		buf[q + 9] = 0.0
		buf[q + 10] = cs
		buf[q + 11] = z
	for mm in _veh:
		RenderingServer.multimesh_set_buffer(mm, buf)


func montrer(oui: bool) -> void:
	if oui == _visible:
		return
	_visible = oui
	for ins in _instances:
		RenderingServer.instance_set_visible(ins, oui)


func liberer() -> void:
	for ins in _instances:
		RenderingServer.free_rid(ins)
	for mm in _multis:
		RenderingServer.free_rid(mm)
	for me in _meshes:
		RenderingServer.free_rid(me)
	_instances.clear()
	_multis.clear()
	_meshes.clear()
	_veh.clear()
	_mats.clear()
	_cable.clear()


func _pause() -> void:
	if _sur_fil and Time.get_ticks_usec() - _t_fil >= FIL_US:
		_attendre_image()


func _attendre_image() -> void:
	var f0: int = Engine.get_process_frames()
	while Engine.get_process_frames() == f0:
		OS.delay_msec(1)
	_t_fil = Time.get_ticks_usec()
	_octets = 0


func _maillage(surf: Dictionary, mat: int) -> RID:
	var a: Array = surf["tableaux"]
	if _sur_fil:
		_octets += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() * 40
		if _octets >= OCTETS_IMAGE:
			_attendre_image()
	var me: RID = RenderingServer.mesh_create()
	RenderingServer.mesh_add_surface_from_arrays(me, RenderingServer.PRIMITIVE_TRIANGLES, a, [], surf["lods"])
	if mat >= 0:
		RenderingServer.mesh_surface_set_material(me, 0, (_mats[mat] as Material).get_rid())
	_meshes.append(me)
	return me


func _multi(surf: Dictionary, mat: int, xfs: PackedFloat32Array, s: Dictionary, scenario: RID) -> void:
	var me: RID = _maillage(surf, mat)
	var mm: RID = RenderingServer.multimesh_create()
	RenderingServer.multimesh_set_mesh(mm, me)
	RenderingServer.multimesh_allocate_data(mm, xfs.size() / 12, RenderingServer.MULTIMESH_TRANSFORM_3D)
	RenderingServer.multimesh_set_buffer(mm, xfs)
	var ins: RID = RenderingServer.instance_create2(mm, scenario)
	RenderingServer.instance_set_transform(ins, xf)
	_regler(ins, s)
	_instances.append(ins)
	_multis.append(mm)


func _regler(ins: RID, s: Dictionary) -> void:
	RenderingServer.instance_set_layer_mask(ins, int(s["couches"]))
	RenderingServer.instance_geometry_set_cast_shadows_setting(ins, int(s["ombre"]))
	var p: float = float(s["portee"])
	if p > 0.0:
		RenderingServer.instance_geometry_set_visibility_range(ins, 0.0, p, 0.0, p * 0.05, RenderingServer.VISIBILITY_RANGE_FADE_DISABLED)


static func _composer(racines: PackedFloat32Array, loc: Transform3D) -> PackedFloat32Array:
	var o: PackedFloat32Array = PackedFloat32Array()
	var nb: int = racines.size() / 12
	o.resize(nb * 12)
	for i in range(nb):
		var q: int = i * 12
		var t: Transform3D = Transform3D(
			Basis(Vector3(racines[q], racines[q + 4], racines[q + 8]), Vector3(racines[q + 1], racines[q + 5], racines[q + 9]), Vector3(racines[q + 2], racines[q + 6], racines[q + 10])),
			Vector3(racines[q + 3], racines[q + 7], racines[q + 11])) * loc
		o[q] = t.basis.x.x
		o[q + 1] = t.basis.y.x
		o[q + 2] = t.basis.z.x
		o[q + 3] = t.origin.x
		o[q + 4] = t.basis.x.y
		o[q + 5] = t.basis.y.y
		o[q + 6] = t.basis.z.y
		o[q + 7] = t.origin.y
		o[q + 8] = t.basis.x.z
		o[q + 9] = t.basis.y.z
		o[q + 10] = t.basis.z.z
		o[q + 11] = t.origin.z
	return o


static func _materiau(d: Dictionary) -> Material:
	_verrou.lock()
	var m: Material = _materiau_verrou(d)
	_verrou.unlock()
	return m


static func _materiau_verrou(d: Dictionary) -> Material:
	if d["classe"] == "ShaderMaterial":
		# (matériau propre à la ligne, pour sa phase ; le shader est commun)
		var code: String = d["code"]
		if not _shaders.has(code):
			var sh: Shader = Shader.new()
			sh.code = code
			_shaders[code] = sh
		var sm: ShaderMaterial = ShaderMaterial.new()
		sm.shader = _shaders[code]
		for k in d["params"]:
			sm.set_shader_parameter(k, d["params"][k])
		return sm
	var cle_m: int = hash(d)
	if _materiaux_communs.has(cle_m):
		return _materiaux_communs[cle_m]
	var m: Material = ClassDB.instantiate(d["classe"])
	for k in d:
		if k != "classe":
			m.set(k, d[k])
	_materiaux_communs[cle_m] = m
	return m
