## Véhicules allégés, 3/3 : écrit vehicules_lod.cuit depuis les JSON de veh_lod.py, puis rend les planches L0 / L1 / L2.
extends SceneTree

var _racine: Node3D
var _cam: Camera3D
var _sortie: String = ""
var _seul: bool = false
const U: String = "user://veh_lod/"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sortie="):
			_sortie = a.trim_prefix("--sortie=")
		if a == "--cuit-seul":
			_seul = true
	_suite()


func _lire_json() -> Array:
	var o: Array = []
	for f in DirAccess.get_files_at(U):
		if f.ends_with(".json"):
			o.append(JSON.parse_string(FileAccess.get_file_as_string(U + f)))
	return o


func _niveau(L: Dictionary) -> Dictionary:
	var v: PackedVector3Array = PackedVector3Array()
	var c: PackedColorArray = PackedColorArray()
	var fv: Array = L["v"]
	var fc: Array = L["c"]
	for k in range(fv.size()):
		v.append(Vector3(fv[k][0], fv[k][1], fv[k][2]))
		c.append(Color(fc[k][0], fc[k][1], fc[k][2]))
	return {"v": v, "c": c, "i": PackedInt32Array(L["i"])}


func _maillage(N: Dictionary, mat: Material) -> ArrayMesh:
	var a: Array = []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = N["v"]
	a[Mesh.ARRAY_COLOR] = N["c"]
	a[Mesh.ARRAY_INDEX] = N["i"]
	var m: ArrayMesh = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	m.surface_set_material(0, mat)
	return m


func _att(n: int = 4) -> void:
	for i in range(n):
		await process_frame


func _suite() -> void:
	await process_frame
	var J: Array = _lire_json()
	var types: Dictionary = {}
	for R in J:
		types[R["cle"]] = {"pivot": Vector3(R["pivot"][0], R["pivot"][1], R["pivot"][2]), "L1": _niveau(R["L1"]), "L2": _niveau(R["L2"])}
	var d: Dictionary = {"version": 2, "types": types}
	var brut: PackedByteArray = var_to_bytes(d)
	var z: PackedByteArray = brut.compress(FileAccess.COMPRESSION_ZSTD)
	var f: FileAccess = FileAccess.open(U + "vehicules_lod.cuit", FileAccess.WRITE)
	f.store_32(brut.size())
	f.store_buffer(z)
	f.close()
	print("CUIT types %d brut %.2f Mo zstd %.2f Mo" % [types.size(), brut.size() / 1048576.0, z.size() / 1048576.0])
	if _seul:
		quit(0)
		return
	_racine = Node3D.new()
	get_root().add_child(_racine)
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.74, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.9, 1.0)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	_racine.add_child(we)
	var sol: DirectionalLight3D = DirectionalLight3D.new()
	sol.look_at_from_position(GareAmont.SOLEIL.normalized() * 100.0, Vector3.ZERO, Vector3.UP)
	sol.light_energy = 1.1
	_racine.add_child(sol)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 2000.0
	_racine.add_child(_cam)
	_cam.make_current()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for R in J:
		var cle: String = R["cle"]
		var p: Array = cle.split("|")
		var v: VehiculeRemontee = VehiculeRemontee.new()
		v.famille = p[0]
		v.livree = p[1]
		v.teinte = p[2]
		v.pince_a108 = p[3] == "true"
		v.style_tph = p[4]
		v.numero = 1
		_racine.add_child(v)
		v.construire()
		var o1: MeshInstance3D = MeshInstance3D.new()
		o1.mesh = _maillage(types[cle]["L1"], mat)
		_racine.add_child(o1)
		var o2: MeshInstance3D = MeshInstance3D.new()
		o2.mesh = _maillage(types[cle]["L2"], mat)
		_racine.add_child(o2)
		var cible: Vector3 = (o1.mesh as ArrayMesh).get_aabb().get_center()
		var taille: float = (o1.mesh as ArrayMesh).get_aabb().size.length()
		var nom: String = cle.replace("|", "_").replace(" ", "").replace("'", "").validate_filename()
		var objs: Array = [v, o1, o2]
		for k in range(3):
			for m in range(3):
				(objs[m] as Node3D).visible = m == k
			# 2 vues rapprochées, puis tailles réelles sur une tablette
			var ang: Array = [Vector3(1, 0.25, 0.8), Vector3(-0.9, 0.35, -0.5)]
			for a in range(2):
				_cam.fov = 40.0
				_cam.look_at_from_position(cible + (ang[a] as Vector3).normalized() * taille * 1.25, cible, Vector3.UP)
				await _att()
				get_root().get_texture().get_image().save_jpg("%s/%s_L%d_v%d.jpg" % [_sortie, nom, k, a], 0.9)
			_cam.fov = 70.0
			var di: Array = [60.0, 150.0, 300.0]
			for a2 in range(3):
				_cam.look_at_from_position(cible + (ang[0] as Vector3).normalized() * float(di[a2]), cible, Vector3.UP)
				await _att()
				var im: Image = get_root().get_texture().get_image()
				var w: int = im.get_width()
				var h: int = im.get_height()
				im.get_region(Rect2i(w / 2 - 80, h / 2 - 80, 160, 160)).save_png("%s/%s_L%d_d%d.png" % [_sortie, nom, k, int(di[a2])])
		v.queue_free()
		o1.queue_free()
		o2.queue_free()
		print("PLANCHE ", cle)
	print("PLANCHES_OK")
	quit(0)
