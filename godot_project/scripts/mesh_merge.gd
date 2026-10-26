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


# --- copies côté processeur ------------------------------------------------------
## Relire un maillage déjà envoyé à la carte graphique (surface_get_arrays)
## la fait recopier vers le processeur et synchronise le rendu : sur un vrai
## PC, des à-coups de 100 à 360 ms à chaque construction de remontée (relevés
## du 26/10/2026 ; invisible sur les bancs sans écran). On lit donc :
##  - les primitives (BoxMesh, CylinderMesh…) par get_mesh_arrays(), calculé
##    sur le processeur ;
##  - les maillages faits par `valider` ou par une fusion, dans la copie
##    gardée à leur création (quelques secondes : le temps d'être refusionnés).
static var _cpu: Dictionary = {}          # id du maillage → [WeakRef, [tableaux par surface]]
## Copies gardées tant que le maillage existe (les pièces partagées — galets,
## coussins — servent des milliers de fois : gardées 5 s seulement, elles
## étaient relues sur la carte à chaque pylône, 24 000 fois au banc) ; celles
## des maillages libérés (sources d'une fusion) partent à la purge. Les
## résultats de fusion ne sont pas copiés (mémoire : 5 Go au banc des 66 lignes).
static var _purge: int = 0


static var _formes: Dictionary = {}       # « Box|taille… » → tableaux
## Lectures restées sur la carte graphique (banc de fluidité : à faire tendre vers 0).
static var lectures_carte: int = 0
static var lectures_par_type: Dictionary = {}


static var _ctx: String = ""


static func _compter(mesh: Mesh) -> void:
	lectures_carte += 1
	var c: String = mesh.get_class() + ("@" + _ctx if _ctx != "" else "")
	lectures_par_type[c] = int(lectures_par_type.get(c, 0)) + 1


## Tableaux d'une boîte (sans subdivision) ou d'un cylindre (un anneau)
## calculés ici, mêmes faces que les primitives de Godot (centrées sur
## l'origine, cylindre d'axe Y) ; UV simples par face (matériaux unis). [] si
## la primitive sort de ces cas.
static func _generer(mesh: Mesh) -> Array:
	var v: PackedVector3Array = PackedVector3Array()
	var n: PackedVector3Array = PackedVector3Array()
	var t: PackedFloat32Array = PackedFloat32Array()
	var uv: PackedVector2Array = PackedVector2Array()
	var ix: PackedInt32Array = PackedInt32Array()
	# quad (a, b, c, d) dans le sens horaire vu de dehors (faces avant de Godot)
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3, nn0: Array, tg: Vector3) -> void:
		var k: int = v.size()
		v.append_array(PackedVector3Array([a, b, c, d]))
		for q in range(4):
			n.append(nn0[q])
			t.append_array(PackedFloat32Array([tg.x, tg.y, tg.z, 1.0]))
		uv.append_array(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]))
		ix.append_array(PackedInt32Array([k, k + 1, k + 2, k, k + 2, k + 3]))
	if mesh is BoxMesh:
		var b: BoxMesh = mesh
		if b.subdivide_width + b.subdivide_height + b.subdivide_depth > 0:
			return []
		var h: Vector3 = b.size * 0.5
		for ax in range(3):
			for sg in [1.0, -1.0]:
				var nrm: Vector3 = Vector3.ZERO
				nrm[ax] = sg
				var iu: int = (ax + 1) % 3
				var iw: int = (ax + 2) % 3
				var u: Vector3 = Vector3.ZERO
				u[iu] = 1.0
				var w: Vector3 = Vector3.ZERO
				w[iw] = 1.0
				# (u × w) opposé à la normale : quad (−u−w, +u−w, +u+w, −u+w) dans le
				# sens horaire vu de dehors, la convention des faces avant de Godot
				if u.cross(w).dot(nrm) > 0.0:
					u = -u
				var c: Vector3 = nrm * h[ax]
				var hu: Vector3 = u * h[iu]
				var hw: Vector3 = w * h[iw]
				quad.call(c - hu - hw, c + hu - hw, c + hu + hw, c - hu + hw, [nrm, nrm, nrm, nrm], u)
	elif mesh is CylinderMesh:
		var cy: CylinderMesh = mesh
		if cy.rings != 1 and cy.rings != 0:
			return []
		var seg: int = maxi(cy.radial_segments, 3)
		var y0: float = -cy.height * 0.5
		var y1: float = cy.height * 0.5
		var r0: float = cy.bottom_radius
		var r1: float = cy.top_radius
		var pente: float = (r0 - r1) / maxf(cy.height, 1e-4)
		for k in range(seg):
			var a0: float = TAU * float(k) / seg
			var a1: float = TAU * float(k + 1) / seg
			var d0: Vector3 = Vector3(sin(a0), 0, cos(a0))
			var d1: Vector3 = Vector3(sin(a1), 0, cos(a1))
			var n0: Vector3 = (d0 + Vector3(0, pente, 0)).normalized()
			var n1: Vector3 = (d1 + Vector3(0, pente, 0)).normalized()
			# flanc (bas k+1, bas k, haut k, haut k+1) : sens horaire vu de dehors
			quad.call(d1 * r0 + Vector3(0, y0, 0), d0 * r0 + Vector3(0, y0, 0), d0 * r1 + Vector3(0, y1, 0),
				d1 * r1 + Vector3(0, y1, 0), [n1, n0, n0, n1], Vector3(cos(a0), 0, -sin(a0)))
			if cy.cap_top and r1 > 0.0:
				var kt: int = v.size()
				v.append_array(PackedVector3Array([Vector3(0, y1, 0), d1 * r1 + Vector3(0, y1, 0), d0 * r1 + Vector3(0, y1, 0)]))
				for q in range(3):
					n.append(Vector3.UP)
					t.append_array(PackedFloat32Array([1, 0, 0, 1]))
				uv.append_array(PackedVector2Array([Vector2(0.5, 0.5), Vector2(0.5 + d1.x * 0.5, 0.5 + d1.z * 0.5), Vector2(0.5 + d0.x * 0.5, 0.5 + d0.z * 0.5)]))
				ix.append_array(PackedInt32Array([kt, kt + 1, kt + 2]))
			if cy.cap_bottom and r0 > 0.0:
				var kb: int = v.size()
				v.append_array(PackedVector3Array([Vector3(0, y0, 0), d0 * r0 + Vector3(0, y0, 0), d1 * r0 + Vector3(0, y0, 0)]))
				for q in range(3):
					n.append(Vector3.DOWN)
					t.append_array(PackedFloat32Array([1, 0, 0, 1]))
				uv.append_array(PackedVector2Array([Vector2(0.5, 0.5), Vector2(0.5 + d0.x * 0.5, 0.5 + d0.z * 0.5), Vector2(0.5 + d1.x * 0.5, 0.5 + d1.z * 0.5)]))
				ix.append_array(PackedInt32Array([kb, kb + 1, kb + 2]))
	else:
		return []
	var a: Array = []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_NORMAL] = n
	a[Mesh.ARRAY_TANGENT] = t
	a[Mesh.ARRAY_TEX_UV] = uv
	a[Mesh.ARRAY_INDEX] = ix
	return a


static func _cle_primitive(mesh: Mesh) -> String:
	if mesh is BoxMesh:
		var b: BoxMesh = mesh
		return "B|%s|%d|%d|%d" % [str(b.size), b.subdivide_width, b.subdivide_height, b.subdivide_depth]
	if mesh is CylinderMesh:
		var c: CylinderMesh = mesh
		return "C|%f|%f|%f|%d|%d|%s|%s" % [c.top_radius, c.bottom_radius, c.height, c.radial_segments, c.rings,
			str(c.cap_top), str(c.cap_bottom)]
	if mesh is SphereMesh:
		var sp: SphereMesh = mesh
		return "S|%f|%f|%d|%d|%s" % [sp.radius, sp.height, sp.radial_segments, sp.rings, str(sp.is_hemisphere)]
	return ""


static func retenir(mesh: Mesh, si: int, arrays: Array) -> void:
	var id: int = mesh.get_instance_id()
	var e: Array = _cpu.get(id, [])
	if e.is_empty() or (e[0] as WeakRef).get_ref() != mesh:
		e = [weakref(mesh), []]
	var l: Array = e[1]
	while l.size() <= si:
		l.append(null)
	l[si] = arrays
	_cpu[id] = e
	var f: int = Engine.get_process_frames()
	if f - _purge > 60:
		_purge = f
		for k in _cpu.keys():
			if (_cpu[k][0] as WeakRef).get_ref() == null:
				_cpu.erase(k)


static func tableaux(mesh: Mesh, si: int) -> Array:
	var id: int = mesh.get_instance_id()
	if _cpu.has(id) and (_cpu[id][0] as WeakRef).get_ref() == mesh:
		var l: Array = _cpu[id][1]
		if si < l.size() and l[si] != null:
			return l[si]
	if mesh is PrimitiveMesh:
		# get_mesh_arrays() passe AUSSI par le serveur de rendu (relevés du PC du
		# 26/10/2026) : boîtes et cylindres gardés par DIMENSIONS — une lecture par
		# taille distincte, quel que soit le nombre de boîtes (des milliers) ;
		# les autres primitives, le temps de la fusion (gardées sans fin par
		# objet, elles faisaient 5 Go au banc des 66 lignes)
		var cp: String = _cle_primitive(mesh)
		if cp != "":
			if not _formes.has(cp):
				# boîtes et cylindres simples : construits ici, sans la carte
				var gen: Array = _generer(mesh)
				if gen.is_empty():
					_compter(mesh)
					gen = (mesh as PrimitiveMesh).get_mesh_arrays()
				_formes[cp] = gen
			return _formes[cp]
		_compter(mesh)
		var ap: Array = (mesh as PrimitiveMesh).get_mesh_arrays()
		retenir(mesh, 0, ap)
		return ap
	_compter(mesh)
	return mesh.surface_get_arrays(si)       # (lent : relu sur la carte)


## Triangles d'un maillage (pour une forme de collision) sans relire la
## carte graphique — create_trimesh_shape() la relisait, surface par surface.
static func faces(mesh: Mesh) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for si in range(mesh.get_surface_count()):
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var a: Array = tableaux(mesh, si)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		if a[Mesh.ARRAY_INDEX] != null:
			var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			var k0: int = out.size()
			out.resize(k0 + ix.size())
			for i in range(ix.size()):
				out[k0 + i] = v[ix[i]]
		else:
			out.append_array(v)
	return out


## `st.commit()` qui garde la copie côté processeur (à refusionner sans relire
## la carte graphique).
static func valider(st: SurfaceTool, mesh: ArrayMesh = null) -> ArrayMesh:
	var m: ArrayMesh = mesh if mesh != null else ArrayMesh.new()
	var a: Array = st.commit_to_arrays()
	if a.is_empty() or a[Mesh.ARRAY_VERTEX] == null or (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		return m
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	retenir(m, m.get_surface_count() - 1, a)
	return m


## Fusionne sous `root`. Renvoie le nombre de surfaces retirées.
## `une_instance` : toutes les surfaces (même ombre, même portée) dans UN
## seul MeshInstance3D à plusieurs surfaces — pour les objets qui bougent à
## chaque image (véhicules des remontées : des milliers d'instances).
static func merge(root: Node3D, keep: Array = [], name_prefix: String = "Fusion", une_instance: bool = false) -> int:
	_ctx = name_prefix
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
	var multi: Dictionary = {}      # (ombre, portée) → [ArrayMesh, g]
	for key in groups:
		var g: Dictionary = groups[key]
		var ta: Array = _tableaux_acc(g["acc"])
		if (ta[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		if une_instance:
			var cle: String = "%d|%f" % [g["shadow"], g["range"]]
			if not multi.has(cle):
				multi[cle] = [ArrayMesh.new(), g]
			var am: ArrayMesh = multi[cle][0]
			var n0: int = am.get_surface_count()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ta)
			if am.get_surface_count() > n0:
				am.surface_set_material(n0, g["mat"])
				removed += g["n"] - 1
				for src in g["src"]:
					done[src] = int(done.get(src, 0)) + 1
			continue
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ta)
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
	for cle2 in multi:
		var am2: ArrayMesh = multi[cle2][0]
		if am2.get_surface_count() == 0:
			continue
		var g2: Dictionary = multi[cle2][1]
		var mi2: MeshInstance3D = MeshInstance3D.new()
		mi2.name = "%s%d" % [name_prefix, k]
		mi2.mesh = am2
		mi2.cast_shadow = g2["shadow"]
		mi2.visibility_range_end = g2["range"]
		root.add_child(mi2)
		k += 1
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
			groups[key] = {"mat": mats[si], "acc": {}, "n": 0, "src": [],
				"shadow": mi.cast_shadow, "range": mi.visibility_range_end}
		var g: Dictionary = groups[key]
		_ajouter(g["acc"], tableaux(mesh, si), xf)
		g["n"] = int(g["n"]) + 1
		(g["src"] as Array).append(mi)


static func _triangles(mesh: Mesh, si: int) -> bool:
	if mesh is ArrayMesh:
		return (mesh as ArrayMesh).surface_get_primitive_type(si) == Mesh.PRIMITIVE_TRIANGLES
	return mesh is PrimitiveMesh and not (mesh is PointMesh)


## Concatène une surface (tableaux) transformée par `xf` dans l'accumulateur.
static func _ajouter(acc: Dictionary, a: Array, xf: Transform3D) -> void:
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n0: int = int(acc.get("n", 0))
	if not acc.has("v"):
		acc["v"] = PackedVector3Array()
	var dv: PackedVector3Array = acc["v"]
	var k0: int = dv.size()
	dv.resize(k0 + v.size())
	for i in range(v.size()):
		dv[k0 + i] = xf * v[i]
	acc["v"] = dv
	var nb: Basis = xf.basis.inverse().transposed()
	if a[Mesh.ARRAY_NORMAL] != null:
		var nn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var dn: PackedVector3Array = acc.get("nor", PackedVector3Array())
		var k1: int = dn.size()
		dn.resize(k1 + nn.size())
		for i in range(nn.size()):
			dn[k1 + i] = (nb * nn[i]).normalized()
		acc["nor"] = dn
	if a[Mesh.ARRAY_TANGENT] != null:
		var tt: PackedFloat32Array = a[Mesh.ARRAY_TANGENT]
		var dt: PackedFloat32Array = acc.get("tan", PackedFloat32Array())
		var k2: int = dt.size()
		dt.resize(k2 + tt.size())
		for i in range(0, tt.size(), 4):
			var t3: Vector3 = (xf.basis * Vector3(tt[i], tt[i + 1], tt[i + 2])).normalized()
			dt[k2 + i] = t3.x
			dt[k2 + i + 1] = t3.y
			dt[k2 + i + 2] = t3.z
			dt[k2 + i + 3] = tt[i + 3]
		acc["tan"] = dt
	for e in [[Mesh.ARRAY_COLOR, "col"], [Mesh.ARRAY_TEX_UV, "uv"], [Mesh.ARRAY_TEX_UV2, "uv2"]]:
		if a[e[0]] != null:
			if not acc.has(e[1]):
				acc[e[1]] = a[e[0]].duplicate()
			else:
				acc[e[1]].append_array(a[e[0]])
	if a[Mesh.ARRAY_INDEX] != null:
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var di: PackedInt32Array = acc.get("ix", PackedInt32Array())
		var k3: int = di.size()
		di.resize(k3 + ix.size())
		for i in range(ix.size()):
			di[k3 + i] = ix[i] + n0
		acc["ix"] = di
	acc["n"] = n0 + v.size()


static func _tableaux_acc(acc: Dictionary) -> Array:
	var a: Array = []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = acc.get("v", PackedVector3Array())
	for e in [[Mesh.ARRAY_NORMAL, "nor"], [Mesh.ARRAY_TANGENT, "tan"], [Mesh.ARRAY_COLOR, "col"],
			[Mesh.ARRAY_TEX_UV, "uv"], [Mesh.ARRAY_TEX_UV2, "uv2"], [Mesh.ARRAY_INDEX, "ix"]]:
		if acc.has(e[1]):
			a[e[0]] = acc[e[1]]
	return a


static func _format(mesh: Mesh, si: int) -> int:
	if mesh is ArrayMesh:
		# (le format seul, sans relire les données)
		var fm: int = (mesh as ArrayMesh).surface_get_format(si)
		var f0: int = 0
		var bits: Array = [Mesh.ARRAY_FORMAT_NORMAL, Mesh.ARRAY_FORMAT_TANGENT, Mesh.ARRAY_FORMAT_COLOR,
			Mesh.ARRAY_FORMAT_TEX_UV, Mesh.ARRAY_FORMAT_TEX_UV2, Mesh.ARRAY_FORMAT_INDEX]
		for i in range(bits.size()):
			if fm & int(bits[i]):
				f0 |= 1 << i
		return f0
	var arrays: Array = tableaux(mesh, si)
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
