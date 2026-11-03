## Cuisson hors ligne d'une remontée : fait tourner les constructeurs du jeu puis écrit un fichier
## binaire par ligne : géométrie fixe fusionnée, pièces répétées en instances, niveaux de détail,
## modèle de véhicule, pièces mobiles, formes de collision.
##   godot --headless --fixed-fps 60 --path godot_project -s cuisson_ligne.gd -- --mode=normal --relief-fin --ligne=tcd10_toviere [--sortie=DOSSIER]
## Le relief décide des hauteurs : un fichier par relief. PC : --relief-fin. PWA : --web --sans-relief-fin --indexer --palette
## (fichier .web.cuit : ni tangentes ni UV2).
extends SceneTree

const VERSION: int = 2
## À partir de ce nombre de poses d'un même maillage, des instances plutôt qu'une fusion.
const SEUIL_INSTANCES: int = 4
## Fusion par tronçons le long de la ligne : d'un seul bloc, plus rien n'est éliminé hors du champ
## et le niveau de détail se règle sur toute la ligne.
const TRONCON: float = 250.0

var _main: Node = null
var _f: int = 0
var _cle: String = ""
var _sortie: String = "user://cuites"
var _web: bool = false
var _lg: LigneRemontee = null
var _t0: int = 0
var _fait: bool = false

var _materiaux: Array = []
var _mat_index: Dictionary = {}
var _sans_textures: Dictionary = {}
var _fixes: Dictionary = {}
var _poses: Dictionary = {}
var _mobiles: Array = []
var _textes: Array = []
var _formes: Array = []
var _racines_mobiles: Dictionary = {}
var _avant: Dictionary = {"noeuds": 0, "geometries": 0, "surfaces": 0, "surfaces_vehicule": 0, "triangles": 0}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ligne="):
			_cle = a.trim_prefix("--ligne=")
		elif a.begins_with("--sortie="):
			_sortie = a.trim_prefix("--sortie=")
		elif a == "--web":
			_web = true
	if _cle == "":
		printerr("--ligne=CLE manquant")
		quit(2)
		return
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _tick() -> void:
	_f += 1
	var relief: Variant = _main.get("relief")
	if relief == null or not relief.pret or _f < 30 or _fait:
		return
	if _lg == null:
		_main.basculer_skieur()
		for e in _main.remontees.lignes:
			if String((e[0] as Node).name) == _cle:
				_lg = e[0]
		if _lg == null:
			printerr("ligne inconnue : ", _cle)
			quit(2)
			return
		_main.remontees.set_process(false)
		_t0 = Time.get_ticks_msec()
		_lg.progressif = false
		_lg.construire()
		return
	if _lg.pret:
		_fait = true
		var t_c: int = Time.get_ticks_msec() - _t0
		_main.remontees._portees(_lg)
		var t1: int = Time.get_ticks_msec()
		_cuire()
		print("CUISSON %s : construction %d ms, cuisson %d ms" % [_cle, t_c, Time.get_ticks_msec() - t1])
		quit(0)


func _cuire() -> void:
	for e in _lg._poulies:
		_racines_mobiles[e[0]] = "poulie"
	for e in _lg._pneus:
		_racines_mobiles[e[0]] = "pneu"
	var v0: VehiculeRemontee = _lg._vehicules[0][0] if not _lg._vehicules.is_empty() else null
	var vehicule: Array = []
	if v0 != null:
		_lire_vehicule(v0, v0, Transform3D.IDENTITY, vehicule)
	_parcours(_lg, Transform3D.IDENTITY, "")
	var surfaces: Array = []
	var instances: Array = []
	for cle in _poses:
		var p: Dictionary = _poses[cle]
		if (p["xfs"] as Array).size() >= SEUIL_INSTANCES:
			var xfs: PackedFloat32Array = PackedFloat32Array()
			for x in p["xfs"]:
				_pousser(xfs, x)
			for s in _surfaces_de(p["mesh"]):
				instances.append({"surface": _emballer(s[0]), "mat": _mat(s[1] if p["ov"] == null else p["ov"]),
					"xfs": xfs, "portee": p["portee"], "ombre": p["ombre"], "couches": p["couches"]})
		else:
			for x in p["xfs"]:
				for s in _surfaces_de(p["mesh"]):
					_fusionner_dans(s[1] if p["ov"] == null else p["ov"], p["portee"], p["ombre"], p["couches"], s[0], x, p["troncon"])
	for cle in _fixes:
		var g: Dictionary = _fixes[cle]
		var ta: Array = MeshMerge._tableaux_acc(g["acc"])
		surfaces.append({"surface": _emballer(ta), "mat": _mat(g["m"]), "portee": g["portee"], "ombre": g["ombre"], "couches": g["couches"]})
	var veh_acc: Dictionary = {}
	var miroir_v: Transform3D = Transform3D.IDENTITY if _lg.sens_droite else Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO)
	for e in vehicule:
		if e["detail"]:
			continue               # (pièces de détail : de près, la ligne construite)
		for s in _surfaces_de(e["mesh"]):
			var mt: Material = s[1] if e["ov"] == null else e["ov"]
			var ck2: String = "%d|%d|%s" % [mt.get_instance_id() if mt != null else 0, e["ombre"], _attributs(s[0])]
			if not veh_acc.has(ck2):
				veh_acc[ck2] = {"m": mt, "acc": {}, "ombre": e["ombre"]}
			var ind: Array = s[0]
			if ind[Mesh.ARRAY_INDEX] == null:
				ind = ind.duplicate()
				var nv: int = (ind[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				var ix2: PackedInt32Array = PackedInt32Array()
				ix2.resize(nv)
				for i2 in range(nv):
					ix2[i2] = i2
				ind[Mesh.ARRAY_INDEX] = ix2
			var xv: Transform3D = miroir_v * (e["xf"] as Transform3D)
			MeshMerge._ajouter(veh_acc[ck2]["acc"], _retourne(ind, xv), xv)
	var veh_fusion: Array = []
	for ck2 in veh_acc:
		veh_fusion.append({"surface": _emballer(MeshMerge._tableaux_acc(veh_acc[ck2]["acc"])), "mat": _mat(veh_acc[ck2]["m"]), "ombre": veh_acc[ck2]["ombre"]})
	print("VEHICULE fusionne : %d surfaces" % veh_fusion.size())
	var mob_groupes: Dictionary = {}
	for e in _mobiles:
		var ck: String = "%s|%d|%d|%s|%.0f|%d|%d|%d" % [e["type"], (e["mesh"] as Mesh).get_instance_id(), (e["ov"] as Material).get_instance_id() if e["ov"] != null else 0, str(e["xf"]), e["portee"], e["ombre"], e["couches"], _troncon(AABB((e["xf_racine"] as Transform3D).origin, Vector3.ZERO))]
		if not mob_groupes.has(ck):
			mob_groupes[ck] = {"type": e["type"], "mesh": e["mesh"], "ov": e["ov"], "xf": e["xf"], "xf_racines": PackedFloat32Array(), "portee": e["portee"], "ombre": e["ombre"], "couches": e["couches"]}
		_pousser(mob_groupes[ck]["xf_racines"], e["xf_racine"])
	var mob_sortie: Array = []
	for ck in mob_groupes:
		var e: Dictionary = mob_groupes[ck]
		var s3: Array = []
		for s in _surfaces_de(e["mesh"]):
			s3.append({"surface": _emballer(s[0]), "mat": _mat(s[1] if e["ov"] == null else e["ov"])})
		mob_sortie.append({"type": e["type"], "xf": e["xf"], "xf_racines": e["xf_racines"], "surfaces": s3, "portee": e["portee"], "ombre": e["ombre"], "couches": e["couches"]})
	var d: Dictionary = {
		"version": VERSION, "cle": _cle, "xf_ligne": _lg.global_transform, "cible": "web" if _web else "pc",
		"materiaux": _materiaux, "surfaces": surfaces, "instances": instances,
		"vehicule_fusion": veh_fusion, "mobiles": mob_sortie, "textes": _textes,
		"vitesse_cable": _lg.vitesse, "pas_cable": 0.45 * _lg.diametre_cable / 52.0,
		"boite_ligne": _boite_ligne(),
	}
	_trajet(d)
	var brut: PackedByteArray = var_to_bytes(d)
	var z: PackedByteArray = brut.compress(FileAccess.COMPRESSION_ZSTD)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_sortie))
	var chemin: String = _sortie.path_join(_cle + (".web.cuit" if _web else ".cuit"))
	var f: FileAccess = FileAccess.open(chemin, FileAccess.WRITE)
	f.store_32(brut.size())
	f.store_buffer(z)
	f.close()
	var lods: int = 0
	var sans_lod: int = 0
	for s in surfaces:
		if (s["surface"]["lods"] as Dictionary).is_empty():
			sans_lod += 1
		lods += (s["surface"]["lods"] as Dictionary).size()
	var appels_apres: int = surfaces.size() + instances.size()
	print("AVANT noeuds %d, geometries %d, surfaces fixes %d, surfaces d'un vehicule %d x %d, triangles fixes %d, materiaux %d" % [
		_avant["noeuds"], _avant["geometries"], _avant["surfaces"], _avant["surfaces_vehicule"], _lg._vehicules.size(), _avant["triangles"], _materiaux.size()])
	print("APRES noeuds 0 (serveurs), surfaces fusionnees %d, groupes d'instances %d, groupes de pieces mobiles %d, surfaces d'un vehicule %d, appels fixes %d" % [
		surfaces.size(), instances.size(), mob_sortie.size(), veh_fusion.size(), appels_apres])
	print("LOD %d niveaux en tout, %d surfaces sans LOD" % [lods, sans_lod])
	print("TEXTES %d ; materiaux avec texture non cuite %d ; trajet %d points, %d vehicules" % [_textes.size(), _sans_textures.size(), (d["trajet"] as PackedFloat32Array).size() / 4, (d["phases"] as PackedFloat32Array).size()])
	print("FICHIER %s : brut %.2f Mo, compresse %.2f Mo" % [chemin, brut.size() / 1048576.0, z.size() / 1048576.0])


## Trajet des véhicules : une pose toutes les pas_t secondes sur toute la boucle (vitesse des lanceurs
## comprise) et la phase de chaque véhicule ; la ligne cuite n'a qu'à interpoler.
func _trajet(d: Dictionary) -> void:
	var pas_t: float = 0.5
	var t: PackedFloat32Array = PackedFloat32Array()
	var horaire: PackedFloat32Array = PackedFloat32Array()
	var long: float = _lg.longueur_boucle
	var s: float = 0.0
	var tps: float = 0.0
	var prochain: float = 0.0
	while s < long:
		if tps >= prochain:
			var pc: Array = _lg.point(s)
			var dh: Vector3 = pc[1]
			dh.y = 0.0
			var b: Basis = Basis.looking_at(dh.normalized() if dh.length() > 0.001 else Vector3.FORWARD, Vector3.UP)
			var pos: Vector3 = pc[0]
			t.append_array(PackedFloat32Array([pos.x, pos.y, pos.z, atan2(-b.x.z, b.x.x)]))
			horaire.append(s)
			prochain += pas_t
		s += maxf(_lg.vitesse_en(s), 0.05) * 0.05
		tps += 0.05
	d["trajet"] = t
	d["pas_t"] = pas_t
	var ph: PackedFloat32Array = PackedFloat32Array()
	for e in _lg._vehicules:
		ph.append(horaire.bsearch(float(e[1])) * pas_t)
	d["phases"] = ph


func _boite_ligne() -> AABB:
	var lh: float = _lg.longueur_h()
	var ymin: float = minf(_lg.terrain(0.0), _lg.terrain(lh)) - 60.0
	var ymax: float = maxf(_lg.terrain(0.0), _lg.terrain(lh)) + 120.0
	return AABB(Vector3(-_lg.voie - 10.0, ymin, -lh - _lg.l_gare - 30.0), Vector3(2.0 * _lg.voie + 20.0, ymax - ymin, lh + 2.0 * _lg.l_gare + 60.0))


func _pousser(a: PackedFloat32Array, x: Transform3D) -> void:
	a.append_array(PackedFloat32Array([x.basis.x.x, x.basis.y.x, x.basis.z.x, x.origin.x,
		x.basis.x.y, x.basis.y.y, x.basis.z.y, x.origin.y,
		x.basis.x.z, x.basis.y.z, x.basis.z.z, x.origin.z]))


func _parcours(n: Node, xf: Transform3D, chemin_mobile: String) -> void:
	_avant["noeuds"] += 1
	var x: Transform3D = xf
	if n != _lg and n is Node3D:
		x = xf * (n as Node3D).transform
	if n is VehiculeRemontee:
		_compter_vehicule(n)
		return
	var nom: String = String(n.name)
	if nom.begins_with("VehiculesLoin"):
		return
	if nom.begins_with("Corps_") and n is StaticBody3D:
		return
	if n is Node3D and not (n as Node3D).visible and not n is CollisionObject3D:
		return
	var type_mob: String = _racines_mobiles.get(n, "")
	if type_mob != "":
		_lire_mobile(n, n, Transform3D.IDENTITY, type_mob, x)
		return
	if n is CollisionShape3D:
		_forme(n, x, _formes)
	if n is Label3D:
		var l: Label3D = n
		_textes.append({"texte": l.text, "xf": x, "taille": l.pixel_size, "police": l.font_size})
	elif n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		_geometrie(n, x)
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
		var mmi: MultiMeshInstance3D = n
		var mm: MultiMesh = mmi.multimesh
		for i in range(mm.instance_count):
			_poser(mm.mesh, mmi.material_override, x * mm.get_instance_transform(i), mmi)
	for c in n.get_children():
		_parcours(c, x, chemin_mobile)


func _geometrie(mi: MeshInstance3D, x: Transform3D) -> void:
	_poser(mi.mesh, mi.material_override, x, mi)


func _poser(m: Mesh, ov: Material, x: Transform3D, g: GeometryInstance3D) -> void:
	_avant["geometries"] += 1
	_avant["surfaces"] += m.get_surface_count()
	for sf in _surfaces_de(m):
		var ix: Variant = sf[0][Mesh.ARRAY_INDEX]
		var vv: PackedVector3Array = sf[0][Mesh.ARRAY_VERTEX]
		_avant["triangles"] += (ix as PackedInt32Array).size() / 3 if ix != null else vv.size() / 3
	var mirroir: bool = x.basis.determinant() < 0.0
	var tr: int = _troncon(x * m.get_aabb())
	var cle: String = "%d|%d|%.0f|%d|%d|%s|%d" % [m.get_instance_id(), ov.get_instance_id() if ov != null else 0, g.visibility_range_end, g.cast_shadow, g.layers, str(mirroir), tr]
	if not _poses.has(cle):
		_poses[cle] = {"mesh": m, "ov": ov, "xfs": [], "portee": g.visibility_range_end, "ombre": g.cast_shadow, "couches": g.layers, "troncon": tr}
	(_poses[cle]["xfs"] as Array).append(x)


func _surfaces_de(m: Mesh) -> Array:
	var o: Array = []
	for si in range(m.get_surface_count()):
		var mat: Material = m.surface_get_material(si)
		o.append([MeshMerge.tableaux(m, si), mat])
	return o


## Attributs présents : fusionner une surface sans couleurs avec une surface qui en a donne des
## tableaux de longueurs différentes, rejetés à la pose.
func _attributs(a: Array) -> String:
	var o: String = ""
	for k in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		o += "1" if a[k] != null else "0"
	return o


## Pose en miroir : l'ordre des sommets s'inverse, sinon les faces se retournent.
func _retourne(a: Array, x: Transform3D) -> Array:
	if x.basis.determinant() >= 0.0:
		return a
	var o: Array = a.duplicate()
	var ix: PackedInt32Array = (a[Mesh.ARRAY_INDEX] as PackedInt32Array).duplicate()
	for k in range(0, ix.size() - 2, 3):
		var t: int = ix[k + 1]
		ix[k + 1] = ix[k + 2]
		ix[k + 2] = t
	o[Mesh.ARRAY_INDEX] = ix
	return o


func _troncon(ab: AABB) -> int:
	return int(floor(-ab.get_center().z / TRONCON))


func _fusionner_dans(m: Material, portee: float, ombre: int, couches: int, a: Array, x: Transform3D, tr: int) -> void:
	var cle: String = "%d|%.0f|%d|%d|%d|%s" % [m.get_instance_id() if m != null else 0, portee, ombre, couches, tr, _attributs(a)]
	if not _fixes.has(cle):
		_fixes[cle] = {"m": m, "acc": {}, "portee": portee, "ombre": ombre, "couches": couches}
	var ind: Array = a
	if a[Mesh.ARRAY_INDEX] == null:
		ind = a.duplicate()
		var n: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var ix: PackedInt32Array = PackedInt32Array()
		ix.resize(n)
		for i in range(n):
			ix[i] = i
		ind[Mesh.ARRAY_INDEX] = ix
	MeshMerge._ajouter(_fixes[cle]["acc"], _retourne(ind, x), x)


## Surface prête pour RenderingServer.mesh_add_surface_from_arrays : tableaux et niveaux de détail
## (taille d'arête → indices), lisibles aussi bien par le module C++ que par la PWA.
func _emballer(a: Array) -> Dictionary:
	if _web:
		a = a.duplicate()
		a[Mesh.ARRAY_TANGENT] = null
		a[Mesh.ARRAY_TEX_UV2] = null
	var im: ImporterMesh = ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, a)
	if (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() >= 64:
		im.generate_lods(25.0, 60.0, [])
	var lods: Dictionary = {}
	for i in range(im.get_surface_lod_count(0)):
		lods[im.get_surface_lod_size(0, i)] = im.get_surface_lod_indices(0, i)
	return {"tableaux": im.get_surface_arrays(0), "lods": lods}


func _mat(m: Material) -> int:
	if m == null:
		return -1
	var id: int = m.get_instance_id()
	if _mat_index.has(id):
		return _mat_index[id]
	var d: Dictionary = {"classe": m.get_class()}
	if m is ShaderMaterial:
		var sm: ShaderMaterial = m
		d["code"] = sm.shader.code if sm.shader != null else ""
		var par: Dictionary = {}
		for u in sm.shader.get_shader_uniform_list():
			var v: Variant = sm.get_shader_parameter(u["name"])
			if v is Texture2D:
				_sans_textures[id] = true
			elif v != null:
				par[u["name"]] = v
		d["params"] = par
	else:
		var defauts: Material = ClassDB.instantiate(m.get_class())
		for pr in m.get_property_list():
			if not pr["usage"] & PROPERTY_USAGE_STORAGE:
				continue
			var nom: String = pr["name"]
			if nom.begins_with("resource_") or nom == "script" or nom == "next_pass":
				continue
			var v2: Variant = m.get(nom)
			if v2 is Resource:
				_sans_textures[id] = true
				continue
			if v2 != defauts.get(nom):
				d[nom] = v2
	var i: int = _materiaux.size()
	_materiaux.append(d)
	_mat_index[id] = i
	return i


func _forme(n: CollisionShape3D, x: Transform3D, o: Array) -> void:
	if n.shape == null or n.disabled:
		return
	var d: Dictionary = {"xf": x, "classe": n.shape.get_class()}
	var c: Node = n.get_parent()
	if c is CollisionObject3D:
		d["couche"] = (c as CollisionObject3D).collision_layer
		d["masque"] = (c as CollisionObject3D).collision_mask
		d["corps"] = String(c.name)
	if n.shape is BoxShape3D:
		d["taille"] = (n.shape as BoxShape3D).size
	elif n.shape is CylinderShape3D:
		d["rayon"] = (n.shape as CylinderShape3D).radius
		d["hauteur"] = (n.shape as CylinderShape3D).height
	elif n.shape is ConcavePolygonShape3D:
		d["faces"] = (n.shape as ConcavePolygonShape3D).get_faces()
	elif n.shape is ConvexPolygonShape3D:
		d["points"] = (n.shape as ConvexPolygonShape3D).points
	elif n.shape is SphereShape3D:
		d["rayon"] = (n.shape as SphereShape3D).radius
	elif n.shape is CapsuleShape3D:
		d["rayon"] = (n.shape as CapsuleShape3D).radius
		d["hauteur"] = (n.shape as CapsuleShape3D).height
	o.append(d)


func _lire_formes(n: Node, x: Transform3D, o: Array) -> void:
	var xx: Transform3D = x
	if n is Node3D and x != Transform3D.IDENTITY:
		xx = x * (n as Node3D).transform
	elif n is CollisionShape3D:
		xx = (n as Node3D).transform
	if n is CollisionShape3D:
		_forme(n, xx, o)
	for c in n.get_children():
		_lire_formes(c, xx, o)


func _compter_vehicule(n: Node) -> void:
	_avant["noeuds"] += 1
	for c in n.get_children():
		_compter_vehicule(c)


func _lire_vehicule(n: Node, v0: Node, x: Transform3D, o: Array, chemin: String = "", detail: bool = false) -> void:
	var xx: Transform3D = x if n == v0 else x * (n as Node3D).transform if n is Node3D else x
	var det: bool = detail or n.has_meta("detail")
	var ch: String = chemin if n == v0 else chemin + "/" + String(n.name)
	if n is Node3D and not (n as Node3D).visible:
		det = true
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi: MeshInstance3D = n
		_avant["surfaces_vehicule"] += mi.mesh.get_surface_count()
		o.append({"chemin": ch, "xf": xx, "detail": det, "mesh": mi.mesh, "ov": mi.material_override, "ombre": mi.cast_shadow})
	for c in n.get_children():
		_lire_vehicule(c, v0, xx, o, ch, det)


func _lire_mobile(n: Node, racine: Node, x: Transform3D, type_mob: String, xf_racine: Transform3D) -> void:
	_avant["noeuds"] += 1
	var xx: Transform3D = x if n == racine else x * (n as Node3D).transform if n is Node3D else x
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi: MeshInstance3D = n
		_avant["geometries"] += 1
		_avant["surfaces"] += mi.mesh.get_surface_count()
		_mobiles.append({"type": type_mob, "racine": racine.get_instance_id(), "xf": xx, "xf_racine": xf_racine, "mesh": mi.mesh, "ov": mi.material_override,
			"portee": mi.visibility_range_end, "ombre": mi.cast_shadow, "couches": mi.layers})
	for c in n.get_children():
		_lire_mobile(c, racine, xx, type_mob, xf_racine)
