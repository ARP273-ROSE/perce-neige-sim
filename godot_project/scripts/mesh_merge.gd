class_name MeshMerge
extends RefCounted
## Fusion des maillages statiques d'un sous-arbre (2026-09-30, saccades de
## la PWA) : la cabine comptait ~400 MeshInstance3D, soit une centaine
## d'appels de dessin par image en vue cabine — en WebGL chaque appel coûte
## cher sur le fil principal. Les surfaces opaques qui ne bougent pas par
## rapport à `root` sont regroupées par matériau en un seul ArrayMesh, posé
## sous `root` (elles suivent donc ses déplacements).
##
## Restent séparés : les nœuds de `keep` et tout leur sous-arbre (roues,
## vantaux, feux dont le matériau change…), les matériaux transparents (tri
## par profondeur), les repères en miroir (déterminant < 0 : l'ordre des
## sommets s'inverserait), les primitives non triangulaires. Une distance
## de visibilité (visibility_range_end) est conservée, groupe par groupe.

# attributs qui doivent concorder dans un même groupe (SurfaceTool
# complète les absents par des zéros : une couleur de sommet noire, etc.)
const _ATTRS: Array = [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR,
	Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_INDEX]


## Fusionne sous `root`. Renvoie le nombre de surfaces retirées.
static func merge(root: Node3D, keep: Array = [], name_prefix: String = "Fusion") -> int:
	var groups: Dictionary = {}     # clé → {mat, st, n, shadow}
	var done: Dictionary = {}       # MeshInstance3D → nb de surfaces fusionnées
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var node: Node = e[0]
		var xf: Transform3D = e[1]
		for c in node.get_children():
			if c in keep or not (c is Node3D):
				continue
			var cxf: Transform3D = xf * (c as Node3D).transform
			if not (c as Node3D).visible:
				continue
			if c is MeshInstance3D:
				_collect(c as MeshInstance3D, cxf, groups, done)
			# un nœud à script peut s'animer lui-même : on ne descend pas
			if c.get_script() == null:
				stack.append([c, cxf])
	var removed: int = 0
	var k: int = 0
	for key in groups:
		var g: Dictionary = groups[key]
		var st: SurfaceTool = g["st"]
		var mesh: ArrayMesh = st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		mesh.surface_set_material(0, g["mat"])
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "%s%d" % [name_prefix, k]
		mi.mesh = mesh
		mi.cast_shadow = g["shadow"]
		mi.visibility_range_end = g["range"]
		root.add_child(mi)
		k += 1
		removed += g["n"] - 1
		for src in g["src"]:
			done[src] = int(done.get(src, 0)) + 1
	# retire les sources : un objet n'est collecté que si TOUTES ses
	# surfaces sont fusionnables (cf. _collect), il est donc entièrement repris
	for mi_any in done.keys():
		var mi: MeshInstance3D = mi_any
		if int(done[mi]) == mi.mesh.get_surface_count():
			mi.get_parent().remove_child(mi)
			mi.queue_free()
	return removed


static func _material_of(mi: MeshInstance3D, si: int) -> Material:
	if mi.material_override != null:
		return mi.material_override
	var m: Material = mi.get_surface_override_material(si)
	if m == null:
		m = mi.mesh.surface_get_material(si)
	return m


static func _collect(mi: MeshInstance3D, xf: Transform3D, groups: Dictionary, done: Dictionary) -> void:
	var mesh: Mesh = mi.mesh
	if mesh == null or mi.material_overlay != null \
			or mi.visibility_range_begin > 0.0 or mi.get_script() != null \
			or xf.basis.determinant() <= 0.0 or mi.skin != null:
		return
	if mesh is ArrayMesh and (mesh as ArrayMesh).get_blend_shape_count() > 0:
		return
	var ns: int = mesh.get_surface_count()
	var mats: Array = []
	for si in range(ns):
		var m: Material = _material_of(mi, si)
		if m == null or not _opaque(m) or not _triangles(mesh, si):
			return   # une surface non fusionnable → l'objet reste entier
		mats.append(m)
	for si in range(ns):
		var key: String = "%d_%d_%d_%.1f" % [mats[si].get_instance_id(), _format(mesh, si),
			mi.cast_shadow, mi.visibility_range_end]
		if not groups.has(key):
			var st: SurfaceTool = SurfaceTool.new()
			groups[key] = {"mat": mats[si], "st": st, "n": 0, "src": [],
				"shadow": mi.cast_shadow, "range": mi.visibility_range_end}
		var g: Dictionary = groups[key]
		(g["st"] as SurfaceTool).append_from(mesh, si, xf)
		g["n"] = int(g["n"]) + 1
		(g["src"] as Array).append(mi)


static func _triangles(mesh: Mesh, si: int) -> bool:
	if mesh is ArrayMesh:
		return (mesh as ArrayMesh).surface_get_primitive_type(si) == Mesh.PRIMITIVE_TRIANGLES
	return mesh is PrimitiveMesh and not (mesh is PointMesh)


static func _format(mesh: Mesh, si: int) -> int:
	var arrays: Array = mesh.surface_get_arrays(si)
	var f: int = 0
	for i in range(_ATTRS.size()):
		if arrays[_ATTRS[i]] != null:
			f |= 1 << i
	return f


static func _opaque(m: Material) -> bool:
	if m is BaseMaterial3D:
		var b: BaseMaterial3D = m
		return b.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
			and b.albedo_color.a >= 0.999 and b.next_pass == null
	return false
