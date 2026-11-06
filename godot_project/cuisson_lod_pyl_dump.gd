## Pylônes allégés, 1/3 : géométrie réelle des pylônes d'une ligne (user://pyl_dump/<relief>/<ligne>.json). --liste : noms des lignes.
extends SceneTree
var _main: Node
var _f: int = 0
var _fait: bool = false
var _cle: String = ""


func _initialize() -> void:
	LigneRemontee.fusion_pylones = false      # (la cuisson lit les pièces sur chaque pylône)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ligne="):
			_cle = a.trim_prefix("--ligne=")
		elif a == "--liste":
			var f0: FileAccess = FileAccess.open(RemonteesDonnees.FICHIER, FileAccess.READ)
			var n0: int = f0.get_32()
			var noms: PackedStringArray = PackedStringArray()
			for l in bytes_to_var(f0.get_buffer(f0.get_length() - 4).decompress(n0, FileAccess.COMPRESSION_ZSTD)):
				noms.append(String(l["cle"]))
			print("LIGNES ", ",".join(noms))
			quit(0)
			return
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
	_suite()


func _chercher(n: Node, o: Array) -> void:
	for c in n.get_children():
		if c is PyloneRemontee or c is PyloneTreillis:
			o.append(c)
		else:
			_chercher(c, o)


func _suite() -> void:
	var lg: LigneRemontee = null
	for e in _main.remontees.lignes:
		if String((e[0] as Node).name) == _cle:
			lg = e[0]
	lg.progressif = false
	lg.construire()
	var t0: int = Time.get_ticks_msec()
	while not lg.pret and Time.get_ticks_msec() - t0 < 400000:
		await process_frame
	_main.remontees.set_process(false)
	var rel: String = "fin" if _main.relief.fin != null else "25"
	var L: Array = []
	_chercher(lg, L)
	var P: Array = []
	var tot: int = 0
	for i in range(L.size()):
		var p: Node3D = L[i]
		var o: Array = []
		_lire(p, p, Transform3D.IDENTITY, o, "", false)
		var nt: int = 0
		for q in o:
			nt += (q["i"] as Array).size() / 3
		tot += nt
		P.append({"rang": i, "nom": String(p.name), "classe": p.get_class(), "tri": nt, "pieces": o, "xf_o": [p.position.x, p.position.y, p.position.z], "basis": [[p.global_transform.basis.x.x, p.global_transform.basis.x.y, p.global_transform.basis.x.z], [p.global_transform.basis.y.x, p.global_transform.basis.y.y, p.global_transform.basis.y.z], [p.global_transform.basis.z.x, p.global_transform.basis.z.y, p.global_transform.basis.z.z]]})
	DirAccess.make_dir_recursive_absolute("user://pyl_dump/" + rel)
	var f: FileAccess = FileAccess.open("user://pyl_dump/%s/%s.json" % [rel, _cle], FileAccess.WRITE)
	f.store_string(JSON.stringify({"ligne": _cle, "rel": rel, "famille": lg.famille, "pylones": P}))
	f.close()
	print("PYL_OK %s %s %d pylones %d triangles" % [rel, _cle, L.size(), tot])
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
