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
	if mesh is BoxMesh:
		var b: BoxMesh = mesh
		if b.subdivide_width + b.subdivide_height + b.subdivide_depth > 0:
			return []
		return _generer_formes(true, b.size, 0.0, 0.0, 0.0, 0, false, false)
	if mesh is CylinderMesh:
		var cy: CylinderMesh = mesh
		if cy.rings != 1 and cy.rings != 0:
			return []
		return _generer_formes(false, Vector3.ZERO, cy.bottom_radius, cy.top_radius, cy.height, cy.radial_segments,
			cy.cap_top, cy.cap_bottom)
	if mesh is QuadMesh:
		return _generer_quad(mesh as QuadMesh)
	return []


## QuadMesh (face Z, sans subdivision) comme PlaneMesh._create_mesh_array du moteur 4.6, normale et tangente passées
## par la compression du serveur de rendu (octaèdre 2 × 16 bits) : les tableaux qu'en rendait la relecture sur la
## carte, octet pour octet (logos des cabines : une relecture, 32 ms de blocage, par taille ; relevé du 10/11/2026).
## [] dans les autres cas (relu sur la carte, une fois par dimensions).
static func _generer_quad(q: QuadMesh) -> Array:
	if q.orientation != PlaneMesh.FACE_Z or q.subdivide_width != 0 or q.subdivide_depth != 0 or q.flip_faces or q.add_uv2:
		return []
	var start: Vector2 = q.size * -0.5
	var pts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var z: float = start.y
	for j in range(2):
		var x: float = start.x
		for i in range(2):
			pts.append(Vector3(-x, z, 0.0) + q.center_offset)
			uvs.append(Vector2(1.0 - float(i), 1.0 - float(j)))
			x = _f32(x + q.size.x / 1.0)
		z = _f32(z + q.size.y / 1.0)
	var nq: Vector3 = _normale_serveur(Vector3(0.0, 0.0, 1.0))
	var tq: Array = _tangente_serveur(Vector3(1.0, 0.0, 0.0), 1.0)
	var ns: PackedVector3Array = PackedVector3Array([nq, nq, nq, nq])
	var ts: PackedFloat32Array = PackedFloat32Array()
	for _k in range(4):
		ts.append_array(PackedFloat32Array([tq[0].x, tq[0].y, tq[0].z, tq[1]]))
	var a: Array = []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = pts
	a[Mesh.ARRAY_NORMAL] = ns
	a[Mesh.ARRAY_TANGENT] = ts
	a[Mesh.ARRAY_TEX_UV] = uvs
	a[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 1, 3, 2])
	return a


## Arrondi en réel simple (calcul du moteur en float).
static func _f32(v: float) -> float:
	return PackedFloat32Array([v])[0]


static func _normale_serveur(n: Vector3) -> Vector3:
	var o: Vector2 = n.octahedron_encode()
	var v0: int = int(clampf(_f32(o.x * 65535.0), 0.0, 65535.0))
	var v1: int = int(clampf(_f32(o.y * 65535.0), 0.0, 65535.0))
	return Vector3.octahedron_decode(Vector2(v0 / 65535.0, v1 / 65535.0))


## [tangente, signe] après l'aller-retour du serveur de rendu (Vector3.octahedron_tangent_encode / _decode).
static func _tangente_serveur(t: Vector3, signe: float) -> Array:
	var o: Vector2 = t.octahedron_encode()
	var y: float = maxf(o.y, _f32(1.0 / 32767.0))
	y = _f32(_f32(y * 0.5) + 0.5)
	y = y if signe >= 0.0 else _f32(1.0 - y)
	var v0: int = int(clampf(_f32(o.x * 65535.0), 0.0, 65535.0))
	var v1: int = int(clampf(_f32(y * 65535.0), 0.0, 65535.0))
	if v0 == 0 and v1 == 65535:
		v0 = 65535
	var oy: float = _f32(_f32(float(v1) / 65535.0) * 2.0 - 1.0)
	var s: float = 1.0 if oy >= 0.0 else -1.0
	return [Vector3.octahedron_decode(Vector2(v0 / 65535.0, absf(oy))), s]


static func _generer_formes(boite: bool, taille: Vector3, r_bas: float, r_haut: float, hauteur: float, segments: int,
		cap_top: bool, cap_bottom: bool) -> Array:
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
	if boite:
		var h: Vector3 = taille * 0.5
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
	else:
		var seg: int = maxi(segments, 3)
		var y0: float = -hauteur * 0.5
		var y1: float = hauteur * 0.5
		var r0: float = r_bas
		var r1: float = r_haut
		var pente: float = (r0 - r1) / maxf(hauteur, 1e-4)
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
			if cap_top and r1 > 0.0:
				var kt: int = v.size()
				v.append_array(PackedVector3Array([Vector3(0, y1, 0), d1 * r1 + Vector3(0, y1, 0), d0 * r1 + Vector3(0, y1, 0)]))
				for q in range(3):
					n.append(Vector3.UP)
					t.append_array(PackedFloat32Array([1, 0, 0, 1]))
				uv.append_array(PackedVector2Array([Vector2(0.5, 0.5), Vector2(0.5 + d1.x * 0.5, 0.5 + d1.z * 0.5), Vector2(0.5 + d0.x * 0.5, 0.5 + d0.z * 0.5)]))
				ix.append_array(PackedInt32Array([kt, kt + 1, kt + 2]))
			if cap_bottom and r0 > 0.0:
				var kb: int = v.size()
				v.append_array(PackedVector3Array([Vector3(0, y0, 0), d0 * r0 + Vector3(0, y0, 0), d1 * r0 + Vector3(0, y0, 0)]))
				for q in range(3):
					n.append(Vector3.DOWN)
					t.append_array(PackedFloat32Array([1, 0, 0, 1]))
				uv.append_array(PackedVector2Array([Vector2(0.5, 0.5), Vector2(0.5 + d0.x * 0.5, 0.5 + d0.z * 0.5), Vector2(0.5 + d1.x * 0.5, 0.5 + d1.z * 0.5)]))
				ix.append_array(PackedInt32Array([kb, kb + 1, kb + 2]))
	var a: Array = []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_NORMAL] = n
	a[Mesh.ARRAY_TANGENT] = t
	a[Mesh.ARRAY_TEX_UV] = uv
	a[Mesh.ARRAY_INDEX] = ix
	return a


## Boîte et cylindre de RemonteeKit en ArrayMesh, tableaux calculés ici (sur le fil de construction) et partagés
## par dimensions avec _formes : une BoxMesh ou une CylinderMesh créée sur le fil renvoyait sa mise à jour
## (PrimitiveMesh._update, appel différé) au fil principal, 4 à 15 ms par image vers la salle (relevé du NAS,
## 07/11/2026). Dimensions en meta (PRIM_BOITE : taille de la boîte), pour collisions_jeu.
const PRIM_BOITE: StringName = &"prim_boite"


static func arrays_boite(taille: Vector3) -> Array:
	var cle: String = "B|%s|0|0|0" % str(taille)
	verrou.lock()
	var a: Variant = _formes.get(cle)
	verrou.unlock()
	if a == null:
		a = _generer_formes(true, taille, 0.0, 0.0, 0.0, 0, false, false)
		verrou.lock()
		_formes[cle] = a
		verrou.unlock()
	return a


static func arrays_cylindre(r_bas: float, r_haut: float, h: float, seg: int) -> Array:
	var cle: String = "C|%f|%f|%f|%d|%d|%s|%s" % [r_haut, r_bas, h, seg, 1, "true", "true"]
	verrou.lock()
	var a: Variant = _formes.get(cle)
	verrou.unlock()
	if a == null:
		a = _generer_formes(false, Vector3.ZERO, r_bas, r_haut, h, seg, true, true)
		verrou.lock()
		_formes[cle] = a
		verrou.unlock()
	return a


## ArrayMesh d'une surface, ses tableaux retenus (fusion et collisions sans relire la carte).
static func maillage_retenu(a: Array, m: Material) -> ArrayMesh:
	var am: ArrayMesh = ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	am.surface_set_material(0, m)
	retenir(am, 0, a)
	return am


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
	if mesh is QuadMesh:
		# (skis rangés des véhicules : relus sur la carte à chaque modèle, 32 ms de blocage, relevé du 10/11/2026)
		var qm: QuadMesh = mesh
		return "Q|%s|%s|%d|%d|%d" % [str(qm.size), str(qm.center_offset), qm.subdivide_width, qm.subdivide_depth, qm.orientation]
	return ""


## Les remontées se construisent sur un autre fil pendant que le fil principal
## lit aussi ces copies (collisions à la demande) : caches sous verrou.
static var verrou: Mutex = Mutex.new()


static func retenir(mesh: Mesh, si: int, arrays: Array) -> void:
	verrou.lock()
	_retenir(mesh, si, arrays)
	verrou.unlock()


static func _retenir(mesh: Mesh, si: int, arrays: Array) -> void:
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


## Copie processeur gardée pour ce maillage (toutes ses surfaces) ?
static func a_copie(mesh: Mesh) -> bool:
	verrou.lock()
	var id: int = mesh.get_instance_id()
	var ok: bool = _cpu.has(id) and (_cpu[id][0] as WeakRef).get_ref() == mesh
	if ok:
		var l: Array = _cpu[id][1]
		for si in range(mesh.get_surface_count()):
			ok = ok and si < l.size() and l[si] != null
	verrou.unlock()
	return ok


## Oublie la copie processeur d'un maillage (mémoire).
static func oublier(mesh: Mesh) -> void:
	verrou.lock()
	_cpu.erase(mesh.get_instance_id())
	verrou.unlock()


static func tableaux(mesh: Mesh, si: int) -> Array:
	verrou.lock()
	var a: Array = _tableaux(mesh, si)
	verrou.unlock()
	return a


static func _tableaux(mesh: Mesh, si: int) -> Array:
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
	if indexer:
		st.index()
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
## Maillages partagés entre pièces identiques (paires de galets, pneus des lanceurs) :
## sans cela, chaque ligne en refaisait des centaines, soit la moitié de ses sommets
## (Lanches : 680 000 sur 1,6 million) et 800 de ses 1 300 maillages (mesure PWA, 02/11/2026).
static var _partages: Dictionary = {}          # clé → [[mesh, ombre, portée, nom], …]
static var _verrou_partages: Mutex = Mutex.new()


## Pose sous `root` les maillages déjà faits pour `cle` ; faux s'il faut les
## construire : fabriquer alors les pièces sous `root`, puis fusion_partagee.
static func poser_partage(root: Node3D, cle: String) -> bool:
	root.set_meta("modele", cle)
	_verrou_partages.lock()
	var l: Variant = _partages.get(cle)
	_verrou_partages.unlock()
	if l == null:
		return false
	for e in l:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = e[3]
		mi.mesh = e[0]
		mi.cast_shadow = e[1]
		mi.visibility_range_end = e[2]
		root.add_child(mi)
	root.set_meta("modele_pose", true)
	return true


## Fusionne `root` et retient le résultat pour les suivants de même clé.
static func fusion_partagee(root: Node3D, name_prefix: String) -> void:
	if root.has_meta("modele_pose"):
		return
	merge(root, [], name_prefix)
	if not root.has_meta("modele"):
		return
	var l: Array = []
	for c in root.get_children():
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			l.append([mi.mesh, mi.cast_shadow, mi.visibility_range_end, String(mi.name)])
	_verrou_partages.lock()
	_partages[String(root.get_meta("modele"))] = l
	_verrou_partages.unlock()


static func vider_partages() -> void:
	_verrou_partages.lock()
	_partages.clear()
	_verrou_partages.unlock()


## PWA : sommets soudés (les maillages sans index répètent chaque sommet à chaque
## triangle : la mémoire des tampons est le plafond de l'iPad, 03/11/2026). Les sommets
## ne sont soudés que si position, normale, UV… concordent : le rendu ne change pas.
static var indexer: bool = OS.has_feature("web") or not ("--sans-indexer" in OS.get_cmdline_user_args())
static var index_us: int = 0


static func _indexes(ta: Array) -> Array:
	# (petits maillages : un tampon de plus pour presque rien)
	if not indexer or ta[Mesh.ARRAY_INDEX] != null or (ta[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() < 128:
		return ta
	var t0: int = Time.get_ticks_usec()
	var st: SurfaceTool = SurfaceTool.new()
	st.create_from_arrays(ta)
	st.index()
	var r: Array = st.commit_to_arrays()
	index_us += Time.get_ticks_usec() - t0
	return r


## `st.commit()`, sommets soudés sur la PWA.
## commit() d'un SurfaceTool sans matériau, copie processeur gardée (mêmes tableaux ; voir valider_indexe_retenu).
static func commit_retenu(st: SurfaceTool) -> ArrayMesh:
	var a: Array = st.commit_to_arrays()
	var m: ArrayMesh = ArrayMesh.new()
	if a.is_empty() or a[Mesh.ARRAY_VERTEX] == null or (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		return m
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	retenir(m, 0, a)
	return m


## valider_indexe, copie processeur gardée (maillage refusionné ensuite : sans elle, la fusion le relisait sur la
## carte et bloquait le fil principal ~32 ms ; relevé du 10/11/2026). Pour un SurfaceTool sans matériau : mêmes
## tableaux que commit().
static func valider_indexe_retenu(st: SurfaceTool) -> ArrayMesh:
	if indexer:
		var t0: int = Time.get_ticks_usec()
		st.index()
		index_us += Time.get_ticks_usec() - t0
	var a: Array = st.commit_to_arrays()
	var m: ArrayMesh = ArrayMesh.new()
	if a.is_empty() or a[Mesh.ARRAY_VERTEX] == null or (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		return m
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	retenir(m, 0, a)
	return m


static func valider_indexe(st: SurfaceTool, mesh: ArrayMesh = null) -> ArrayMesh:
	if indexer:
		var t0: int = Time.get_ticks_usec()
		st.index()
		index_us += Time.get_ticks_usec() - t0
	if not garder_chargement:
		return st.commit(mesh)
	# chargement (PC) : copie gardée jusqu'aux collisions du skieur (voir garder_chargement) — sans elle, l'entrée en
	# skieur relisait sur la carte la voie, le tunnel et les gares (165 relectures au banc de fluidité, 14/11/2026).
	# commit() pose les tableaux de commit_to_arrays() : même maillage.
	var a: Array = st.commit_to_arrays()
	var m: ArrayMesh = st.commit(mesh)
	if not a.is_empty() and a[Mesh.ARRAY_VERTEX] != null and not (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		retenir(m, m.get_surface_count() - 1, a)
		verrou.lock()
		_gardes_chargement.append(weakref(m))
		verrou.unlock()
	return m


## Partage des fusions à géométrie identique (PWA : les deux rames et leurs voitures
## envoyaient chacune la leur à la carte, ~66 Mo de tampons au menu, 03/11/2026).
## Seule une empreinte est gardée, pas les sommets. Actif le temps de fusionner une rame.
static var partager_identiques: bool = false
static var _identiques: Dictionary = {}    # empreinte → ArrayMesh
static var sommets_partages: int = 0


static func _empreinte(ta: Array) -> String:
	var h: HashingContext = HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	for i in range(ta.size()):
		h.update(("|%d:" % i).to_ascii_buffer())
		if ta[i] != null:
			h.update(ta[i].to_byte_array())
	return h.finish().hex_encode()


static func _maillage_identique(ta: Array) -> ArrayMesh:
	if not partager_identiques:
		return null
	var m: ArrayMesh = _identiques.get(_empreinte(ta), null)
	if m != null:
		sommets_partages += (ta[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return m


static func _retenir_identique(ta: Array, m: ArrayMesh) -> void:
	if partager_identiques:
		_identiques[_empreinte(ta)] = m


## `garder` : la copie processeur du résultat est gardée (tant que le maillage existe, ou jusqu'à oublier()),
## pour une seconde fusion sans relire la carte graphique (pylônes : LigneRemontee.fusionner_pylones_loin).
static func merge(root: Node3D, keep: Array = [], name_prefix: String = "Fusion", une_instance: bool = false, garder: bool = false) -> int:
	_ctx = name_prefix
	var groups: Dictionary = {}     # clé → {mat, st, n, shadow}
	var done: Dictionary = {}       # MeshInstance3D → nb de surfaces fusionnées
	var t_us: int = Time.get_ticks_usec()
	_collecter(_a_fusionner(root, keep), 0, 0, groups, done)
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
			var ti: Array = _indexes(ta)
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ti)
			if am.get_surface_count() > n0:
				am.surface_set_material(n0, g["mat"])
				# copie gardée (PC) : les véhicules lointains (_maillage_miroir) relisaient sinon ces fusions sur
				# la carte, et chaque relecture bloquait le fil principal ~32 ms (relevé du 10/11/2026) ; la PWA garde
				# sa mémoire
				if not OS.has_feature("web"):
					retenir(am, n0, ti)
				removed += g["n"] - 1
				for src in g["src"]:
					done[src] = int(done.get(src, 0)) + 1
			continue
		_poser_groupe(root, g, ta, "%s%d" % [name_prefix, k], garder, done)
		k += 1
		removed += g["n"] - 1
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
	_retirer_sources(done)
	fusion_us += Time.get_ticks_usec() - t_us
	return removed


## merge() en plusieurs tranches (construction sur le fil principal, PWA) : `pause` est attendue chaque fois
## qu'environ `budget_ms` se sont écoulées. Les sources ne partent qu'à la fin : entre deux tranches, le
## résultat partiel double des pièces encore là (même géométrie, sans effet à l'écran). Pas de une_instance.
static func merge_par_tranches(root: Node3D, keep: Array, name_prefix: String, garder: bool, pause: Callable,
		budget_ms: float = 2.5) -> int:
	var groups: Dictionary = {}
	var done: Dictionary = {}
	var t: int = Time.get_ticks_usec()
	var budget: int = int(budget_ms * 1000.0)
	var t_us: int = t
	var l: Array = _a_fusionner(root, keep)
	var i: int = 0
	while i < l.size():
		_ctx = name_prefix
		i = _collecter(l, i, maxi(budget - (Time.get_ticks_usec() - t), 1), groups, done)
		if Time.get_ticks_usec() - t > budget:
			fusion_us += Time.get_ticks_usec() - t_us
			await pause.call()
			t = Time.get_ticks_usec()
			t_us = t
	var removed: int = 0
	var k: int = 0
	for key in groups:
		var g: Dictionary = groups[key]
		_ctx = name_prefix
		var ta: Array = _tableaux_acc(g["acc"])
		if (ta[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		_poser_groupe(root, g, ta, "%s%d" % [name_prefix, k], garder, done)
		k += 1
		removed += g["n"] - 1
		if Time.get_ticks_usec() - t > budget:
			fusion_us += Time.get_ticks_usec() - t_us
			await pause.call()
			t = Time.get_ticks_usec()
			t_us = t
	_retirer_sources(done)
	fusion_us += Time.get_ticks_usec() - t_us
	return removed


## Les MeshInstance3D visibles sous `root` (hors `keep`, sans descendre dans un nœud à script) et leur
## transformation dans le repère de `root`.
## Meta : pièce jamais fusionnée (textes figés : un maillage partagé par texte, au lieu d'une copie dans chaque
## gare ou pylône fusionné — +4 à 6 Mo de tampons sur la PWA, relevé du NAS du 07/11/2026).
const SANS_FUSION: StringName = &"sans_fusion"


static func _a_fusionner(root: Node3D, keep: Array) -> Array:
	if _outils_cpp() != null and collecte_cpp:
		var l: Array = _outils.parcourir(root, keep)
		if verifier_cpp:
			_verifier_parcours(l, _a_fusionner_gd(root, keep))
		return l
	return _a_fusionner_gd(root, keep)


static func _a_fusionner_gd(root: Node3D, keep: Array) -> Array:
	var r: Array = []
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
			if c is MeshInstance3D and not c.has_meta(SANS_FUSION):
				r.append([c, cxf])
			# un nœud à script peut s'animer lui-même : on ne descend pas
			if c.get_script() == null:
				stack.append([c, cxf])
	return r


## Chargement (PC) : copies processeur des fusions gardées jusqu'à ce que les collisions du skieur les aient lues
## (CollisionsJeu), puis oubliées d'un coup. Sans elles, l'entrée en skieur relisait ces maillages sur la carte : trois
## images de 130 à 160 ms (relevé du 10/11/2026).
static var garder_chargement: bool = false
static var _gardes_chargement: Array = []


static func oublier_chargement() -> void:
	verrou.lock()
	for w in _gardes_chargement:
		var m: Object = (w as WeakRef).get_ref()
		if m != null:
			_cpu.erase(m.get_instance_id())
	_gardes_chargement.clear()
	verrou.unlock()


static func _poser_groupe(root: Node3D, g: Dictionary, ta: Array, nom: String, garder: bool, done: Dictionary) -> void:
	var mesh: ArrayMesh = _maillage_identique(ta)
	var nouveau: bool = mesh == null
	if nouveau:
		mesh = ArrayMesh.new()
		var tai: Array = _indexes(ta)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tai)
		mesh.surface_set_material(0, g["mat"])
		if garder or garder_chargement:
			retenir(mesh, 0, tai)
			if not garder:
				verrou.lock()
				_gardes_chargement.append(weakref(mesh))
				verrou.unlock()
		_retenir_identique(ta, mesh)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = nom
	mi.mesh = mesh
	if not nouveau and mesh.surface_get_material(0) != g["mat"]:
		mi.set_surface_override_material(0, g["mat"])
	mi.cast_shadow = g["shadow"]
	mi.visibility_range_end = g["range"]
	root.add_child(mi)
	for src in g["src"]:
		done[src] = int(done.get(src, 0)) + 1


## _collect sur l[i0..] ; avec `budget_us` > 0, s'arrête dès qu'il est dépassé (au moins une pièce). Rend
## l'indice suivant. Module chargé (hors palette) : en C++ (OutilsMaillage.collecter, mêmes groupes).
static func _collecter(l: Array, i0: int, budget_us: int, groups: Dictionary, done: Dictionary) -> int:
	if _outils_cpp() != null and collecte_cpp and not palette:
		if verifier_cpp:
			return _collecter_verifie(l, i0, groups, done)
		return _outils.collecter(l, i0, budget_us, groups, _cpu, verrou, _repli_tableaux)
	return _collecter_gd(l, i0, budget_us, groups, done)


static func _collecter_gd(l: Array, i0: int, budget_us: int, groups: Dictionary, done: Dictionary) -> int:
	var t0: int = Time.get_ticks_usec()
	var i: int = i0
	while i < l.size():
		var e: Array = l[i]
		i += 1
		if is_instance_valid(e[0]):
			_collect(e[0], e[1], groups, done)
		if budget_us > 0 and Time.get_ticks_usec() - t0 > budget_us:
			break
	return i


## Bancs : temps passé dans merge / merge_par_tranches (hors attentes), en µs. --collecte-gd : parcours,
## regroupement et retrait en GDScript (assemblage toujours en C++), pour comparer.
static var fusion_us: int = 0
static var collecte_cpp: bool = not ("--collecte-gd" in OS.get_cmdline_user_args())
## Bancs (--verifier-fusion) : chaque parcours et chaque regroupement faits en C++ ET en GDScript sur les mêmes
## pièces, comparés (pièces, transformations, groupes, ordre des clés, tableaux) ; écarts comptés.
static var verifier_cpp: bool = "--verifier-fusion" in OS.get_cmdline_user_args()
static var verif_appels: int = 0
static var verif_ecarts: int = 0


static func _verifier_parcours(l_cpp: Array, l_gd: Array) -> void:
	var ok: bool = l_cpp.size() == l_gd.size()
	var i: int = 0
	while ok and i < l_gd.size():
		ok = l_cpp[i][0] == l_gd[i][0] and l_cpp[i][1] == l_gd[i][1]
		i += 1
	verif_appels += 1
	if not ok:
		verif_ecarts += 1
		push_warning("MeshMerge : parcours C++ ≠ GDScript (%s, %d / %d pièces, écart à %d)" % [_ctx, l_cpp.size(), l_gd.size(), i - 1])


static func _collecter_verifie(l: Array, i0: int, groups: Dictionary, done: Dictionary) -> int:
	var g_gd: Dictionary = {}
	var g_cpp: Dictionary = {}
	_collecter_gd(l, i0, 0, g_gd, done)
	_outils.collecter(l, i0, 0, g_cpp, _cpu, verrou, _repli_tableaux)
	verif_appels += 1
	if g_gd.keys() != g_cpp.keys() or g_gd != g_cpp:
		verif_ecarts += 1
		push_warning("MeshMerge : groupes C++ ≠ GDScript (%s) : %s / %s" % [_ctx, str(g_cpp.keys()), str(g_gd.keys())])
	for k in g_cpp:
		groups[k] = g_cpp[k]
	return l.size()
static var _repli_tableaux: Callable = func(mesh: Mesh, si: int) -> Array: return tableaux(mesh, si)


## Retire les sources : un objet n'est collecté que si TOUTES ses surfaces sont fusionnables (cf. _collect),
## il est donc entièrement repris.
static func _retirer_sources(done: Dictionary) -> void:
	if _outils_cpp() != null and collecte_cpp:
		_outils.retirer(done)
		return
	for mi_any in done.keys():
		var mi: MeshInstance3D = mi_any
		if int(done[mi]) == mi.mesh.get_surface_count():
			var dans_scene: bool = mi.is_inside_tree()
			mi.get_parent().remove_child(mi)
			# hors de la scène (construction sur un autre fil) : libérée tout de suite, ici. En file de suppression,
			# des milliers de pièces fusionnées étaient détruites d'un coup par le fil principal (34 à 72 ms d'une
			# image vers la salle, relevé du PC du 07/11/2026)
			if dans_scene:
				mi.queue_free()
			else:
				mi.free()


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
		var cp: String = _classe_palette(mats[si])
		var ta0: Array = []
		var mat_g: Material = mats[si]
		var fmt: int = _format(mesh, si)
		if cp != "":
			ta0 = tableaux(mesh, si)
			if ta0[Mesh.ARRAY_NORMAL] == null or ta0[Mesh.ARRAY_COLOR] != null:
				cp = ""
		var key: String
		if cp != "":
			mat_g = _materiau_palette(cp, mats[si])
			key = "P%s_%d_%d_%.1f" % [cp, 1 if ta0[Mesh.ARRAY_INDEX] != null else 0, mi.cast_shadow, mi.visibility_range_end]
		else:
			key = "%d_%d_%d_%.1f" % [mats[si].get_instance_id(), fmt, mi.cast_shadow, mi.visibility_range_end]
		if not groups.has(key):
			groups[key] = {"mat": mat_g, "acc": {}, "n": 0, "src": [],
				"shadow": mi.cast_shadow, "range": mi.visibility_range_end}
		var g: Dictionary = groups[key]
		if cp != "":
			_ajouter(g["acc"], _en_palette(ta0, (mats[si] as BaseMaterial3D).albedo_color), xf)
		else:
			_ajouter(g["acc"], tableaux(mesh, si), xf)
		g["n"] = int(g["n"]) + 1
		(g["src"] as Array).append(mi)


## PWA : matériau « palette ». Les matériaux unis ne diffèrent le plus souvent que par leur
## couleur (717 uniques, un UBO et souvent un programme chacun ; 2 000 à 2 700 appels de dessin
## à chaque plantage iPad, 03/11/2026) : la couleur passe dans les sommets, et un seul matériau
## par classe (rugosité et métal arrondis, faces, ombrage). Les matériaux à texture, à émission
## ou aux effets particuliers gardent leur chemin.
static var palette: bool = OS.has_feature("web") or "--palette" in OS.get_cmdline_user_args()
static var _palette: Dictionary = {}    # classe → StandardMaterial3D
const SANS_PALETTE: StringName = &"sans_palette"   # méta : matériau dont la couleur change en jeu


static func _classe_palette(m: Material) -> String:
	if not palette or not (m is BaseMaterial3D) or m.has_meta(SANS_PALETTE):
		return ""
	var b: BaseMaterial3D = m
	if b.albedo_texture != null or b.normal_enabled or b.emission_enabled or b.vertex_color_use_as_albedo \
			or b.rim_enabled or b.clearcoat_enabled or b.anisotropy_enabled or b.ao_enabled \
			or b.heightmap_enabled or b.refraction_enabled or b.backlight_enabled or b.subsurf_scatter_enabled \
			or b.detail_enabled or b.metallic_texture != null or b.roughness_texture != null \
			or b.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED or b.grow or b.no_depth_test \
			or b.uv1_triplanar or b.fixed_size or b.use_point_size or b.proximity_fade_enabled \
			or b.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED:
		return ""
	return "%d_%d_%d_%d" % [roundi(b.roughness * 4.0), 1 if b.metallic >= 0.5 else 0, b.cull_mode, b.shading_mode]


static func _materiau_palette(cle: String, m: Material) -> StandardMaterial3D:
	var r: StandardMaterial3D = _palette.get(cle, null)
	if r == null:
		var b: BaseMaterial3D = m
		r = StandardMaterial3D.new()
		r.resource_name = "palette_" + cle
		r.vertex_color_use_as_albedo = true
		r.vertex_color_is_srgb = true
		r.roughness = roundf(b.roughness * 4.0) / 4.0
		r.metallic = 1.0 if b.metallic >= 0.5 else 0.0
		r.metallic_specular = b.metallic_specular
		r.cull_mode = b.cull_mode
		r.shading_mode = b.shading_mode
		_palette[cle] = r
	return r


## Sans UV ni tangentes (inutiles sans texture : autant de tampon en moins), couleur en sommets.
static func _en_palette(a: Array, couleur: Color) -> Array:
	var r: Array = a.duplicate()
	r[Mesh.ARRAY_TEX_UV] = null
	r[Mesh.ARRAY_TEX_UV2] = null
	r[Mesh.ARRAY_TANGENT] = null
	var c: PackedColorArray = PackedColorArray()
	c.resize((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	c.fill(Color(couleur.r, couleur.g, couleur.b, 1.0))
	r[Mesh.ARRAY_COLOR] = c
	return r


static func _triangles(mesh: Mesh, si: int) -> bool:
	if mesh is ArrayMesh:
		return (mesh as ArrayMesh).surface_get_primitive_type(si) == Mesh.PRIMITIVE_TRIANGLES
	return mesh is PrimitiveMesh and not (mesh is PointMesh)


## Assemblage en C++ (classe OutilsMaillage du module), un appel par groupe,
## quand il est chargé ; sinon (PWA sans module) les boucles GDScript
## ci-dessous, mêmes calculs (banc du 27/10/2026 : la fusion faisait l'essentiel
## des 10 à 40 ms de chaque pylône construit).
static var cpp_desactive: bool = false           # bancs : comparer les deux chemins
static var _outils: RefCounted = null
static var _outils_cherche: bool = false


static func _outils_cpp() -> RefCounted:
	if cpp_desactive:
		return null
	if not _outils_cherche:
		_outils_cherche = true
		if ClassDB.class_exists("OutilsMaillage"):
			_outils = ClassDB.instantiate("OutilsMaillage")
	return _outils


## Concatène une surface (tableaux) transformée par `xf` dans l'accumulateur.
static func _ajouter(acc: Dictionary, a: Array, xf: Transform3D) -> void:
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n0: int = int(acc.get("n", 0))
	if _outils_cpp() != null:
		# (module : les surfaces sont assemblées d'un coup, dans _tableaux_acc)
		if not acc.has("surfaces"):
			acc["surfaces"] = []
			acc["xfs"] = []
		(acc["surfaces"] as Array).append(a)
		(acc["xfs"] as Array).append(xf)
		return
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
	_ajouter_attributs(acc, a)
	if a[Mesh.ARRAY_INDEX] != null:
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var di: PackedInt32Array = acc.get("ix", PackedInt32Array())
		var k3: int = di.size()
		di.resize(k3 + ix.size())
		for i in range(ix.size()):
			di[k3 + i] = ix[i] + n0
		acc["ix"] = di
	acc["n"] = n0 + v.size()


## Couleurs et UV : recopiés tels quels.
static func _ajouter_attributs(acc: Dictionary, a: Array) -> void:
	for e in [[Mesh.ARRAY_COLOR, "col"], [Mesh.ARRAY_TEX_UV, "uv"], [Mesh.ARRAY_TEX_UV2, "uv2"]]:
		if a[e[0]] != null:
			if not acc.has(e[1]):
				acc[e[1]] = a[e[0]].duplicate()
			else:
				acc[e[1]].append_array(a[e[0]])


static func _tableaux_acc(acc: Dictionary) -> Array:
	if acc.has("surfaces"):
		return _outils_cpp().fusionner(acc["surfaces"], acc["xfs"])
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
