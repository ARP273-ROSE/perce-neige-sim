class_name ExtrusionVoie
## Bandes rectangulaires (patin, âme, champignon des rails) extrudées le long de la voie : sommets et UV d'un tronçon
## en un appel. Classe OutilsVoie du module C++ quand il est chargé ; sinon (PWA sans module), la même chose en
## GDScript (`bandes_gd`), mêmes calculs dans le même ordre : les deux donnent les mêmes tableaux, et la suite
## (normales, indexation du SurfaceTool) est celle du moteur. Preuve : bench_empreinte_pn.gd avec et sans le module.
## (L'émission sommet par sommet faisait l'essentiel des 120 ms d'un bloc des rails du Funival, PC, 08/11/2026.)

static var cpp_desactive: bool = false        # bancs : comparer les deux chemins
static var _cpp: RefCounted = null
static var _cpp_cherche: bool = false


static func _outils_cpp() -> RefCounted:
	if cpp_desactive:
		return null
	if not _cpp_cherche:
		_cpp_cherche = true
		if ClassDB.class_exists("OutilsVoie"):
			_cpp = ClassDB.instantiate("OutilsVoie")
	return _cpp


## Pour chaque pas entre deux sections (origine, droite, haut, centre latéral cx, abscisse s), pour chaque bande
## [y_bas, y_haut, demi-largeur basse, demi-largeur haute] : faces gauche, droite et dessus (deux triangles chacune).
## Rend [sommets, UV], dans l'ordre d'émission de TrackBuilder._emit_rail_step_xv.
static func bandes(origines: PackedVector3Array, droites: PackedVector3Array, hauts: PackedVector3Array,
		cx: PackedFloat64Array, s: PackedFloat64Array, bnd: PackedFloat64Array) -> Array:
	var o: RefCounted = _outils_cpp()
	if o != null:
		return o.call("extruder_bandes", origines, droites, hauts, cx, s, bnd)
	return bandes_gd(origines, droites, hauts, cx, s, bnd)


static func bandes_gd(origines: PackedVector3Array, droites: PackedVector3Array, hauts: PackedVector3Array,
		cx: PackedFloat64Array, s: PackedFloat64Array, bnd: PackedFloat64Array) -> Array:
	var n: int = origines.size()
	var nb: int = bnd.size() / 4
	var nv: int = maxi(n - 1, 0) * nb * 18
	var dv: PackedVector3Array = PackedVector3Array()
	var du: PackedVector2Array = PackedVector2Array()
	dv.resize(nv)
	du.resize(nv)
	var k: int = 0
	for i in range(1, n):
		var p0: Vector3 = origines[i - 1]
		var r0: Vector3 = droites[i - 1]
		var u0: Vector3 = hauts[i - 1]
		var p1: Vector3 = origines[i]
		var r1: Vector3 = droites[i]
		var u1: Vector3 = hauts[i]
		var c0: float = cx[i - 1]
		var c1: float = cx[i]
		var v0: float = s[i - 1]
		var v1: float = s[i]
		for b in range(nb):
			var y_lo: float = bnd[b * 4]
			var y_hi: float = bnd[b * 4 + 1]
			var w_lo: float = bnd[b * 4 + 2]
			var w_hi: float = bnd[b * 4 + 3]
			var a00: Vector3 = p0 + r0 * (c0 - w_lo) + u0 * y_lo
			var a01: Vector3 = p0 + r0 * (c0 + w_lo) + u0 * y_lo
			var a10: Vector3 = p0 + r0 * (c0 + w_hi) + u0 * y_hi
			var a11: Vector3 = p0 + r0 * (c0 - w_hi) + u0 * y_hi
			var b00: Vector3 = p1 + r1 * (c1 - w_lo) + u1 * y_lo
			var b01: Vector3 = p1 + r1 * (c1 + w_lo) + u1 * y_lo
			var b10: Vector3 = p1 + r1 * (c1 + w_hi) + u1 * y_hi
			var b11: Vector3 = p1 + r1 * (c1 - w_hi) + u1 * y_hi
			# face gauche, face droite, dessus : (00, 10, 11) et (00, 11, 01) de chaque quad, comme _emit_quad_strip
			for q in [[a00, a11, b00, b11, Vector2(0.0, v0), Vector2(0.1, v0), Vector2(0.0, v1), Vector2(0.1, v1)],
					[a01, b01, a10, b10, Vector2(0.0, v0), Vector2(0.0, v1), Vector2(0.1, v0), Vector2(0.1, v1)],
					[a11, a10, b11, b10, Vector2(0.0, v0), Vector2(1.0, v0), Vector2(0.0, v1), Vector2(1.0, v1)]]:
				dv[k] = q[0]; du[k] = q[4]
				dv[k + 1] = q[2]; du[k + 1] = q[6]
				dv[k + 2] = q[3]; du[k + 2] = q[7]
				dv[k + 3] = q[0]; du[k + 3] = q[4]
				dv[k + 4] = q[3]; du[k + 4] = q[7]
				dv[k + 5] = q[1]; du[k + 5] = q[5]
				k += 6
	return [dv, du]


## SurfaceTool prêt pour generate_normals et l'indexation, à partir des tableaux de `bandes`.
static func surface(sommets_uv: Array, mat: Material) -> SurfaceTool:
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = sommets_uv[0]
	arr[Mesh.ARRAY_TEX_UV] = sommets_uv[1]
	var st: SurfaceTool = SurfaceTool.new()
	st.create_from_arrays(arr, Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	return st
