class_name ReliefFin
extends Node3D
## Essai du relief fin : une zone de 2 km à 4 m (IGN RGE ALTI), PC seulement.
## La grille fine subdivise les mailles du relief à 25 m (K mailles par côté) : ses
## triangles sont LE sol des mailles touchées, pour l'affichage, les collisions et
## hauteur_sol. Ajouter un écart sur une grille décalée faisait deux surfaces : les plis
## de la grille à 25 m tombaient dans les mailles fines (0,27 m contre la collision,
## banc du ski, 03/11/2026). Une maille sans écart reste celle du relief à 25 m, et
## son bord, droit sur les deux grilles, se raccorde sans trou.
## Les déblais des gares et les aménagements restent ceux du relief à 25 m.
## Affichage : grille suiveuse à 4 / 8 / 16 m autour de la caméra, reconstruite à
## côté du fil principal quand elle s'est éloignée de son centre.

const CX: float = -140.0
const CZ: float = 1280.0
const COTE: float = 2048.0
const K: int = 6                     # mailles fines par maille à 25 m : 4,17 m
const NC: int = 82                   # mailles à 25 m par côté de la zone
const N: int = NC * K + 1
const PX: float = (ReliefDonnees.X_EST - ReliefDonnees.X_OUEST) / float(ReliefDonnees.NX - 1) / K
const PZ: float = (ReliefDonnees.Z_SUD - ReliefDonnees.Z_NORD) / float(ReliefDonnees.NZ - 1) / K
const N_BRUT: int = 513              # fichier de l'essai : 4 m, calé sur CX, CZ
const PAS_BRUT: float = 4.0
const FONDU: float = 64.0
const R1: float = 192.0              # demi-côté de la grille à 4 m
const R2: float = 448.0              # demi-côté de la grille à 8 m
const SEUIL: float = 48.0            # déplacement qui relance la grille
const JUPE: float = 1.5              # jupe des bords, cache les jointures entre pas

var rel: ReliefBuilder = null
var pret: bool = false
var x0: float = ReliefDonnees.X_OUEST + round((CX - COTE * 0.5 - ReliefDonnees.X_OUEST) / (K * PX)) * K * PX
var z0: float = ReliefDonnees.Z_NORD + round((CZ - COTE * 0.5 - ReliefDonnees.Z_NORD) / (K * PZ)) * K * PZ
var zone: Rect2 = Rect2(x0, z0, (N - 1) * PX, (N - 1) * PZ)
var _hn: PackedFloat32Array = PackedFloat32Array()   # altitude des nœuds de la grille fine
var _fine: PackedByteArray = PackedByteArray()       # par maille à 25 m : 1 si la grille fine y est le sol
var _mat: ShaderMaterial = null
var _mi: Array = []
var _centre: Vector2 = Vector2(INF, INF)
var _tache: int = -1
var _resultat: Array = []
var _demande: Vector2 = Vector2.ZERO
static var voulu_banc: bool = false


## PC à rendu complet, et pas sur demande contraire.
static func voulu() -> bool:
	if OS.has_feature("web") or "--sans-relief-fin" in OS.get_cmdline_user_args():
		return false
	return FileAccess.file_exists("res://data/relief_fin/zone_essai.bin")


## Écart fin − 25 m sur la grille fine : nul au bord de la zone et là où le relief
## à 25 m a été retouché (déblais), ou sous un aménagement.
func preparer(r: ReliefBuilder, h0: PackedFloat32Array) -> void:
	rel = r
	var f: FileAccess = FileAccess.open("res://data/relief_fin/zone_essai.bin", FileAccess.READ)
	if f == null:
		return
	var brut: PackedFloat32Array = f.get_buffer(N_BRUT * N_BRUT * 4).to_float32_array()
	# une passe de lissage : la donnée à 1 m rééchantillonnée à 4 m a un bruit de 1 à 2 m
	# d'un point au suivant, qui secoue le skieur (banc du ski, 03/11/2026)
	var fin: PackedFloat32Array = brut.duplicate()
	var nb: int = N_BRUT
	for i in range(1, nb - 1):
		for j in range(1, nb - 1):
			var a: int = i * nb + j
			if brut[a] > 500.0:
				fin[a] = (4.0 * brut[a] + 2.0 * (brut[a - 1] + brut[a + 1] + brut[a - nb] + brut[a + nb]) \
					+ brut[a - nb - 1] + brut[a - nb + 1] + brut[a + nb - 1] + brut[a + nb + 1]) / 16.0
	# mailles à 25 m retouchées, élargies d'une maille
	var nx: int = ReliefDonnees.NX
	var nz: int = ReliefDonnees.NZ
	var tenu: PackedByteArray = PackedByteArray()
	tenu.resize(nx * nz)
	for k in range(nx * nz):
		if absf(r._h[k] - h0[k]) > 0.02:
			for di in [-1, 0, 1]:
				for dj in [-1, 0, 1]:
					var q: int = k + di * nx + dj
					if q >= 0 and q < nx * nz:
						tenu[q] = 1
	_hn.resize(N * N)
	_fine.resize(NC * NC)
	var ecart: PackedByteArray = PackedByteArray()
	ecart.resize(N * N)
	var rects: Array = []
	for am in r.amenagements:
		rects.append((am["rect"] as Rect2).grow(FONDU))
	# galerie de la sortie de secours : sa couverture et son portail restent ceux du relief à 25 m
	rects.append(Rect2(100.0, 2010.0, 80.0, 70.0).grow(FONDU))
	for i in range(N):
		var z: float = z0 + i * PZ
		for j in range(N):
			var x: float = x0 + j * PX
			var bord: float = minf(minf(x - zone.position.x, zone.end.x - x), minf(z - zone.position.y, zone.end.y - z))
			var w: float = smoothstep(0.0, FONDU, bord)
			var fx: float = clampf((x - ReliefDonnees.X_OUEST) / r._dx, 0.0, nx - 1.001)
			var fz: float = clampf((z - ReliefDonnees.Z_NORD) / r._dz, 0.0, nz - 1.001)
			var ci: int = int(fz)
			var cj: int = int(fx)
			var u: float = fx - cj
			var v: float = fz - ci
			var libre: float = lerpf(lerpf(1.0 - tenu[ci * nx + cj], 1.0 - tenu[ci * nx + cj + 1], u),
				lerpf(1.0 - tenu[(ci + 1) * nx + cj], 1.0 - tenu[(ci + 1) * nx + cj + 1], u), v)
			w *= libre * libre
			for rc in rects:
				if (rc as Rect2).has_point(Vector2(x, z)):
					w = 0.0
					break
			var val: float = _brut_en(fin, x, z)
			var d: float = (val - r._tri_sur(h0, x, z)) * w if val > 500.0 else 0.0
			_hn[i * N + j] = r._tri_sur(r._h, x, z) + d
			ecart[i * N + j] = 1 if d != 0.0 else 0
	for ci in range(NC):
		for cj in range(NC):
			var touche: int = 0
			for i in range(ci * K, (ci + 1) * K + 1):
				for j in range(cj * K, (cj + 1) * K + 1):
					touche |= ecart[i * N + j]
			_fine[ci * NC + cj] = touche
	pret = true


## Fichier de l'essai au point (x, z), bilinéaire ; 0 sans donnée.
func _brut_en(fin: PackedFloat32Array, x: float, z: float) -> float:
	var fx: float = (x - (CX - COTE * 0.5)) / PAS_BRUT
	var fz: float = (z - (CZ - COTE * 0.5)) / PAS_BRUT
	if fx < 0.0 or fz < 0.0 or fx >= N_BRUT - 1.001 or fz >= N_BRUT - 1.001:
		return 0.0
	var j: int = int(fx)
	var i: int = int(fz)
	var a: int = i * N_BRUT + j
	if fin[a] <= 500.0 or fin[a + 1] <= 500.0 or fin[a + N_BRUT] <= 500.0 or fin[a + N_BRUT + 1] <= 500.0:
		return 0.0
	var u: float = fx - j
	return lerpf(lerpf(fin[a], fin[a + 1], u), lerpf(fin[a + N_BRUT], fin[a + N_BRUT + 1], u), fz - i)


## La grille fine est-elle le sol au point (x, z) ?
func fine_ici(x: float, z: float) -> bool:
	var cj: int = int(floor((x - x0) / (K * PX)))
	var ci: int = int(floor((z - z0) / (K * PZ)))
	return cj >= 0 and ci >= 0 and cj < NC and ci < NC and _fine[ci * NC + cj] == 1


## Altitude sur les triangles de la grille fine ; (x, z) dans une maille où fine_ici est vrai.
func hauteur(x: float, z: float) -> float:
	var fx: float = (x - x0) / PX
	var fz: float = (z - z0) / PZ
	var j: int = mini(int(fx), N - 2)
	var i: int = mini(int(fz), N - 2)
	var u: float = fx - j
	var v: float = fz - i
	var a: int = i * N + j
	# même découpe que la grille affichée et les collisions : (a, a+1, a+N) puis (a+1, a+N+1, a+N)
	if u + v <= 1.0:
		return _hn[a] + (_hn[a + 1] - _hn[a]) * u + (_hn[a + N] - _hn[a]) * v
	var d: float = _hn[a + N + 1]
	return d + (_hn[a + N] - d) * (1.0 - u) + (_hn[a + 1] - d) * (1.0 - v)


## Nœud (i, j) de la grille fine, en coordonnées du jeu.
func noeud(i: int, j: int) -> Vector3:
	return Vector3(x0 + j * PX, _hn[i * N + j], z0 + i * PZ)


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return                 # (bancs : le sol suit, sans rien à afficher)
	name = "ReliefFin"
	_mat = (rel._mat_terrain as ShaderMaterial).duplicate()
	var noir: Image = Image.create(2, 2, false, Image.FORMAT_RF)
	noir.fill(Color(0, 0, 0))
	_mat.set_shader_parameter("trous", ImageTexture.create_from_image(noir))
	_mat.set_shader_parameter("piece", 1.0)
	_mat.set_shader_parameter("emprise", Vector4(zone.position.x, zone.position.y, zone.end.x, zone.end.y))
	rel._mats_hiver.append(_mat)
	_mat.set_shader_parameter("hiver", rel._hiver)
	for k in range(3):
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Grille%d" % k
		mi.layers = 1 | Cabin.LAYER_RELIEF
		mi.set_meta("sans_collision", true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_mi.append(mi)
	rel.percer("relief_fin", zone)
	_relancer(_point_vue(), true)


func _point_vue() -> Vector2:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return Vector2(CX, CZ)
	return Vector2(cam.global_position.x, cam.global_position.z)


func _process(_dt: float) -> void:
	if _tache >= 0 and WorkerThreadPool.is_task_completed(_tache):
		WorkerThreadPool.wait_for_task_completion(_tache)
		_tache = -1
		_poser()
	if _tache < 0 and _point_vue().distance_to(_centre) > SEUIL:
		_relancer(_point_vue(), false)


func _relancer(p: Vector2, tout_de_suite: bool) -> void:
	p.x = clampf(snappedf(p.x, 32.0), zone.position.x, zone.end.x)
	p.y = clampf(snappedf(p.y, 32.0), zone.position.y, zone.end.y)
	_demande = p
	_centre = p
	if tout_de_suite:
		_calculer()
		_poser()
	else:
		_tache = WorkerThreadPool.add_task(_calculer, false, "relief fin")


func _calculer() -> void:
	var c: Vector2 = _demande
	var r1: Rect2i = _rect(c, R1, 2)
	var r2: Rect2i = _rect(c, R2, 4)
	_resultat = [_tableaux(r1, 1, Rect2i()), _tableaux(r2, 2, r1), _tableaux(Rect2i(0, 0, N - 1, N - 1), 4, r2)]


## Carré autour de c, en nœuds de la grille fine, calé sur un multiple de s.
func _rect(c: Vector2, r: float, s: int) -> Rect2i:
	var ja: int = clampi(int(round((c.x - r - x0) / (PX * s))) * s, 0, N - 1)
	var ia: int = clampi(int(round((c.y - r - z0) / (PZ * s))) * s, 0, N - 1)
	var jb: int = clampi(int(round((c.x + r - x0) / (PX * s))) * s, 0, N - 1)
	var ib: int = clampi(int(round((c.y + r - z0) / (PZ * s))) * s, 0, N - 1)
	return Rect2i(ja, ia, jb - ja, ib - ia)


## Maillage d'un carré de nœuds, un nœud sur s, moins le carré `trou`.
func _tableaux(r: Rect2i, s: int, trou: Rect2i) -> Array:
	var nj: int = r.size.x / s + 1
	var ni: int = r.size.y / s + 1
	var nb: int = ni * nj
	var v: PackedVector3Array = PackedVector3Array()
	var n: PackedVector3Array = PackedVector3Array()
	var uv: PackedVector2Array = PackedVector2Array()
	v.resize(nb)
	n.resize(nb)
	uv.resize(nb)
	var lx: float = (ReliefDonnees.NX - 1) * rel._dx
	var lz: float = (ReliefDonnees.NZ - 1) * rel._dz
	for i in range(ni):
		var gi: int = r.position.y + i * s
		for j in range(nj):
			var gj: int = r.position.x + j * s
			var k: int = i * nj + j
			var p: Vector3 = noeud(gi, gj)
			var gx: float = _hn[gi * N + mini(gj + s, N - 1)] - _hn[gi * N + maxi(gj - s, 0)]
			var gz: float = _hn[mini(gi + s, N - 1) * N + gj] - _hn[maxi(gi - s, 0) * N + gj]
			v[k] = p
			n[k] = Vector3(-gx / (2.0 * s * PX), 1.0, -gz / (2.0 * s * PZ)).normalized()
			uv[k] = Vector2((p.x - ReliefDonnees.X_OUEST) / lx, (p.z - ReliefDonnees.Z_NORD) / lz)
	var idx: PackedInt32Array = PackedInt32Array()
	var av_trou: bool = trou.has_area()
	for i in range(ni - 1):
		for j in range(nj - 1):
			if av_trou and trou.has_point(Vector2i(r.position.x + j * s, r.position.y + i * s)):
				continue
			var a: int = i * nj + j
			idx.append_array(PackedInt32Array([a, a + 1, a + nj, a + 1, a + nj + 1, a + nj]))
	# jupe du bord : descend sous la grille voisine, plus grossière, et cache la jointure
	if not av_trou or s < 4:
		var bords: Array = []
		for j in range(nj - 1):
			bords.append([j, j + 1])
			bords.append([(ni - 1) * nj + j + 1, (ni - 1) * nj + j])
		for i in range(ni - 1):
			bords.append([(i + 1) * nj, i * nj])
			bords.append([i * nj + nj - 1, (i + 1) * nj + nj - 1])
		for b in bords:
			var ka: int = v.size()
			v.append(v[b[0]] + Vector3.DOWN * JUPE)
			v.append(v[b[1]] + Vector3.DOWN * JUPE)
			n.append(n[b[0]])
			n.append(n[b[1]])
			uv.append(uv[b[0]])
			uv.append(uv[b[1]])
			idx.append_array(PackedInt32Array([b[0], b[1], ka, b[1], ka + 1, ka]))
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


func _poser() -> void:
	for k in range(_resultat.size()):
		var m: ArrayMesh = ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _resultat[k])
		m.surface_set_material(0, _mat)
		(_mi[k] as MeshInstance3D).mesh = m
	_resultat = []


func _exit_tree() -> void:
	if _tache >= 0:
		WorkerThreadPool.wait_for_task_completion(_tache)
		_tache = -1
