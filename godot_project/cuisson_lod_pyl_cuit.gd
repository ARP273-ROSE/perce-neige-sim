## Pylônes allégés, 3/3 : écrit pylones_lod_<relief>.cuit depuis les JSON de pyl_lod.py.
extends SceneTree
var _web: bool = false
func _initialize() -> void:
	var rel: String = "25"
	var sortie: String = ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rel="):
			rel = a.trim_prefix("--rel=")
		if a.begins_with("--sortie="):
			sortie = a.trim_prefix("--sortie=")
		if a == "--web":
			_web = true
	var U: String = "user://pyl_lod/%s/" % rel
	var lignes: Dictionary = {}
	var nb: int = 0
	for f in DirAccess.get_files_at(U):
		if not f.ends_with(".json"):
			continue
		var D: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(U + f))
		var o: Array = []
		for p in D["pylones"]:
			if _web:
				o.append({"nom": p["nom"], "rang": int(p["rang"]), "L2": _niv(p["L2"])})
			else:
				o.append({"nom": p["nom"], "rang": int(p["rang"]), "L1": _niv(p["L1"]), "L2": _niv(p["L2"])})
			nb += 1
		lignes[D["ligne"]] = o
	var brut: PackedByteArray = var_to_bytes({"version": 2, "relief": rel, "lignes": lignes})
	var z: PackedByteArray = brut.compress(FileAccess.COMPRESSION_ZSTD)
	var g: FileAccess = FileAccess.open(sortie, FileAccess.WRITE)
	g.store_32(brut.size())
	g.store_buffer(z)
	g.close()
	print("CUIT_PYL %s %d lignes %d pylones brut %.2f Mo zstd %.2f Mo" % [rel, lignes.size(), nb, brut.size() / 1048576.0, z.size() / 1048576.0])
	quit(0)
func _niv(L: Dictionary) -> Dictionary:
	var v: PackedVector3Array = PackedVector3Array()
	var c: PackedColorArray = PackedColorArray()
	var fv: Array = L["v"]
	var fc: Array = L["c"]
	for k in range(fv.size()):
		v.append(Vector3(fv[k][0], fv[k][1], fv[k][2]))
		c.append(Color(fc[k][0], fc[k][1], fc[k][2]))
	return {"v": v, "c": c, "i": PackedInt32Array(L["i"])}
