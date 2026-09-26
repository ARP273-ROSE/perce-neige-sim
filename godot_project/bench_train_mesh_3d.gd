# Exporte la carrosserie construite par TrainBodyBuilder (triangles + couleur
# par surface) pour un rendu orthographique hors Godot (tests/rendu_rame.py),
# et vérifie les cotes : rien sous la table de roulement, tube dans l'alésage.
# Exécution : godot --headless --path godot_project -s bench_train_mesh_3d.gd [sortie.txt]
extends SceneTree


func _initialize() -> void:
	var out_path: String = "/tmp/rame_mesh.txt"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		out_path = args[0]
	var root: Node3D = Node3D.new()
	get_root().add_child(root)
	var built: Dictionary = TrainBodyBuilder.build_train(root, 32.0, 2)
	var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	var n_tri: int = 0
	var y_min: float = 99.0
	var y_max: float = -99.0
	var x_max: float = 0.0
	var z_min: float = 99.0
	var z_max: float = -99.0
	for child in root.get_children():
		if not (child is MeshInstance3D):
			continue
		var mi: MeshInstance3D = child
		var xf: Transform3D = mi.transform
		var mesh: Mesh = mi.mesh
		for si in range(mesh.get_surface_count()):
			var mat: Material = mi.get_surface_override_material(si)
			if mat == null:
				mat = mesh.surface_get_material(si)
			var col: Color = Color(1, 0, 1)
			var alpha: float = 1.0
			if mat is StandardMaterial3D:
				col = (mat as StandardMaterial3D).albedo_color
				alpha = col.a
			var arrays: Array = mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				idx = arrays[Mesh.ARRAY_INDEX]
			var tri_list: Array = []
			if idx.size() > 0:
				for k in range(0, idx.size(), 3):
					tri_list.append([idx[k], idx[k + 1], idx[k + 2]])
			else:
				for k in range(0, verts.size(), 3):
					tri_list.append([k, k + 1, k + 2])
			for t in tri_list:
				var line: String = "%s %.3f %.3f %.3f %.2f" % [mi.name, col.r, col.g, col.b, alpha]
				for vi in t:
					var p: Vector3 = xf * verts[vi]
					line += " %.4f %.4f %.4f" % [p.x, p.y, p.z]
					y_min = minf(y_min, p.y)
					y_max = maxf(y_max, p.y)
					x_max = maxf(x_max, absf(p.x))
					z_min = minf(z_min, p.z)
					z_max = maxf(z_max, p.z)
				f.store_line(line)
				n_tri += 1
	f.close()
	var ok: bool = true
	print("triangles : %d ; y ∈ [%.2f, %.2f] ; |x| ≤ %.2f ; z ∈ [%.1f, %.1f]" % [n_tri, y_min, y_max, x_max, z_min, z_max])
	# Cotes (repère cabine = centre tunnel − 0,15) : rails à −0,58, alésage 1,95
	if y_min < TrainBodyBuilder.Y_RAIL_HEAD - 0.001:
		print("  ECHEC : un élément descend sous la table de roulement (%.2f < %.2f)" % [y_min, TrainBodyBuilder.Y_RAIL_HEAD]); ok = false
	# repère cabine = monde + 0,15 (le nœud Cabin est posé 0,15 m sous l'axe)
	if y_max - 0.15 > 1.95 - 0.10:
		print("  ECHEC : la rame touche la voûte (sommet monde %.2f)" % (y_max - 0.15)); ok = false
	if x_max > 1.95 - 0.10:
		print("  ECHEC : la rame touche les parois (|x| %.2f)" % x_max); ok = false
	if absf(z_min + 16.0) > 0.05 or absf(z_max - 16.0) > 0.05:
		print("  ECHEC : longueur visuelle ≠ 32 m (%.2f → %.2f)" % [z_min, z_max]); ok = false
	print("BENCH_RAME " + ("OK" if ok else "ECHEC") + " → " + out_path)
	quit(0 if ok else 1)
