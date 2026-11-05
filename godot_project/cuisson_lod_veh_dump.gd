## Véhicules allégés, 1/3 : géométrie réelle de chaque type (user://veh_dump/<i>.json). Voir outils_lod/recuire_lod.py.
extends SceneTree
var _main: Node
var _f: int = 0
var _fait: bool = false

func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)

func _tick() -> void:
	_f += 1
	if _fait or _f < 60:
		return
	if _main.get("remontees") == null:
		if _f == 60 or _f % 200 == 0:
			_main.basculer_skieur()
		return
	if _main.remontees.lignes.is_empty():
		return
	_fait = true
	var types: Dictionary = {}
	for e in _main.remontees.lignes:
		var lg: LigneRemontee = e[0]
		var st: String = ""
		if String(lg.famille) == "cabine_tph":
			st = "fornet" if String(lg.name) == "tph_fornet" else ""
		var liv: String = "" if String(lg.famille) == "cabine_tph" else String(lg.station)   # (téléphériques : pas de livrée posée)
		var cle: String = "%s|%s|%s|%s|%s" % [lg.famille, liv, LigneRemontee.TEINTES_CABINES.get(String(lg.name), ""), str(String(lg.name) in LigneRemontee.LIGNES_A108), st]
		if not types.has(cle):
			types[cle] = {"famille": lg.famille, "livree": liv, "teinte": LigneRemontee.TEINTES_CABINES.get(String(lg.name), ""), "a108": String(lg.name) in LigneRemontee.LIGNES_A108, "style": st, "lignes": []}
		(types[cle]["lignes"] as Array).append(String(lg.name))
	DirAccess.make_dir_recursive_absolute("user://veh_dump")
	var i: int = 0
	var bilan: Array = []
	for cle in types:
		var T: Dictionary = types[cle]
		var v: VehiculeRemontee = VehiculeRemontee.new()
		v.famille = T["famille"]
		v.livree = T["livree"]
		v.teinte = T["teinte"]
		v.pince_a108 = T["a108"]
		if T["style"] != "":
			v.style_tph = T["style"]
		v.numero = 1
		get_root().add_child(v)
		v.construire()
		var P: Array = []
		_lire(v, v, Transform3D.IDENTITY, P, "", false)
		var tot: int = 0
		for p in P:
			tot += (p["i"] as Array).size() / 3
		T["cle"] = cle
		T["pieces"] = P
		T["pivot"] = [v.pivot.x, v.pivot.y, v.pivot.z]
		var f: FileAccess = FileAccess.open("user://veh_dump/%d.json" % i, FileAccess.WRITE)
		f.store_string(JSON.stringify(T))
		f.close()
		bilan.append("%d %s : %d lignes, %d pieces, %d triangles" % [i, cle, (T["lignes"] as Array).size(), P.size(), tot])
		print("TYPE ", bilan[-1])
		v.free()
		i += 1
	print("DUMP_OK ", i)
	quit(0)

func _coul(mat: Material) -> Dictionary:
	var o: Dictionary = {"classe": mat.get_class() if mat != null else "", "nom": mat.resource_name if mat != null else ""}
	if mat is BaseMaterial3D:
		var b: BaseMaterial3D = mat
		o["c"] = [b.albedo_color.r, b.albedo_color.g, b.albedo_color.b, b.albedo_color.a]
		o["transp"] = b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		o["rough"] = b.roughness
		o["metal"] = b.metallic
		o["vc"] = b.vertex_color_use_as_albedo
		o["unshaded"] = b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
		o["cull"] = b.cull_mode
		if b.albedo_texture != null:
			o["tex"] = true
			var im: Image = b.albedo_texture.get_image()
			if im != null:
				im = im.duplicate()
				if im.is_compressed():
					im.decompress()
				im.resize(1, 1, Image.INTERPOLATE_BILINEAR)
				var c: Color = im.get_pixel(0, 0)
				o["tex_c"] = [c.r, c.g, c.b, c.a]
	return o

func _lire(n: Node, v0: Node, x: Transform3D, o: Array, ch0: String, det0: bool) -> void:
	var xx: Transform3D = x if n == v0 else (x * (n as Node3D).transform if n is Node3D else x)
	var det: bool = det0 or n.has_meta("detail")
	var ch: String = ch0 if n == v0 else ch0 + "/" + String(n.name)
	var cache: bool = false
	if n is Node3D and not (n as Node3D).visible:
		return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and not cache:
		var mi: MeshInstance3D = n
		for si in range(mi.mesh.get_surface_count()):
			var a: Array = MeshMerge.tableaux(mi.mesh, si)
			var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var nn: Variant = a[Mesh.ARRAY_NORMAL]
			var ix: Variant = a[Mesh.ARRAY_INDEX]
			var cc: Variant = a[Mesh.ARRAY_COLOR]
			var mat: Material = mi.material_override if mi.material_override != null else mi.mesh.surface_get_material(si)
			var fv: Array = []
			var fn: Array = []
			var fc: Array = []
			for k in range(vv.size()):
				var q: Vector3 = xx * vv[k]
				fv.append_array([snappedf(q.x, 0.0001), snappedf(q.y, 0.0001), snappedf(q.z, 0.0001)])
				if nn != null:
					var m: Vector3 = (xx.basis.inverse().transposed() * (nn as PackedVector3Array)[k]).normalized()
					fn.append_array([snappedf(m.x, 0.001), snappedf(m.y, 0.001), snappedf(m.z, 0.001)])
				if cc != null:
					var c: Color = (cc as PackedColorArray)[k]
					fc.append_array([snappedf(c.r, 0.001), snappedf(c.g, 0.001), snappedf(c.b, 0.001)])
			var fi: Array = []
			if ix != null:
				fi = Array(ix as PackedInt32Array)
			else:
				for k in range(vv.size()):
					fi.append(k)
			o.append({"chemin": ch, "detail": det, "ombre": mi.cast_shadow, "mat": _coul(mat), "v": fv, "n": fn, "col": fc, "i": fi})
	for c2 in n.get_children():
		_lire(c2, v0, xx, o, ch, det)
