class_name ReliefFin
extends Node3D
## Essai du relief fin : une zone de 2 km à 4 m (IGN RGE ALTI), PC seulement.
## L'écart au relief à 25 m est appliqué là où le sol du jeu est lu (hauteur_sol,
## _hauteur_tri) : affichage, collisions, ski et objets posés suivent le même sol.
## Les déblais des gares et les aménagements restent ceux du relief à 25 m.
## Affichage : grille suiveuse à 4 / 8 / 16 m autour de la caméra, reconstruite à
## côté du fil principal quand elle s'est éloignée de son centre.

const CX: float = -140.0
const CZ: float = 1280.0
const COTE: float = 2048.0
const N: int = 513
const PAS: float = 4.0
const FONDU: float = 64.0
const R1: float = 192.0              # demi-côté de la grille à 4 m
const R2: float = 448.0              # demi-côté de la grille à 8 m
const SEUIL: float = 48.0            # déplacement qui relance la grille
const JUPE: float = 1.5              # jupe des bords, cache les jointures entre pas

var rel: ReliefBuilder = null
var pret: bool = false
var x0: float = CX - COTE * 0.5
var z0: float = CZ - COTE * 0.5
var zone: Rect2 = Rect2(CX - COTE * 0.5, CZ - COTE * 0.5, COTE, COTE)
var _d: PackedFloat32Array = PackedFloat32Array()
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


## Écart fin − 25 m sur la grille à 4 m : nul au bord de la zone et là où le relief
## à 25 m a été retouché (déblais), ou sous un aménagement.
func preparer(r: ReliefBuilder, h0: PackedFloat32Array) -> void:
	rel = r
	var f: FileAccess = FileAccess.open("res://data/relief_fin/zone_essai.bin", FileAccess.READ)
	if f == null:
		return
	var brut: PackedFloat32Array = f.get_buffer(N * N * 4).to_float32_array()
	# une passe de lissage : la donnée à 1 m rééchantillonnée à 4 m a un bruit de 1 à 2 m
	# d'un point au suivant, qui secoue le skieur (banc du ski, 03/11/2026)
	var fin: PackedFloat32Array = brut.duplicate()
	for i in range(1, N - 1):
		for j in range(1, N - 1):
			var a: int = i * N + j
			if brut[a] > 500.0:
				fin[a] = (4.0 * brut[a] + 2.0 * (brut[a - 1] + brut[a + 1] + brut[a - N] + brut[a + N]) \
					+ brut[a - N - 1] + brut[a - N + 1] + brut[a + N - 1] + brut[a + N + 1]) / 16.0
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
	_d.resize(N * N)
	var rects: Array = []
	for am in r.amenagements:
		rects.append((am["rect"] as Rect2).grow(FONDU))
	# galerie de la sortie de secours : sa couverture et son portail restent ceux du relief à 25 m
	rects.append(Rect2(100.0, 2010.0, 80.0, 70.0).grow(FONDU))
	for i in range(N):
		var z: float = z0 + i * PAS
		for j in range(N):
			var x: float = x0 + j * PAS
			var bord: float = minf(minf(x - x0, x0 + COTE - x), minf(z - z0, z0 + COTE - z))
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
			var val: float = fin[i * N + j]
			_d[i * N + j] = (val - r._tri_sur(h0, x, z)) * w if val > 500.0 else 0.0
	pret = true


## Écart au point (x, z) ; nul hors de la zone.
func delta(x: float, z: float) -> float:
	var fx: float = (x - x0) / PAS
	var fz: float = (z - z0) / PAS
	if fx < 0.0 or fz < 0.0 or fx >= N - 1.001 or fz >= N - 1.001:
		return 0.0
	var j: int = int(fx)
	var i: int = int(fz)
	var u: float = fx - j
	var v: float = fz - i
	var a: int = i * N + j
	# même découpe que la grille affichée et les collisions : (a, a+1, a+N) puis (a+1, a+N+1, a+N)
	if u + v <= 1.0:
		return _d[a] + (_d[a + 1] - _d[a]) * u + (_d[a + N] - _d[a]) * v
	var d: float = _d[a + N + 1]
	return d + (_d[a + N] - d) * (1.0 - u) + (_d[a + 1] - d) * (1.0 - v)


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
	var r1: Rect2 = _rect(c, R1, 8.0)
	var r2: Rect2 = _rect(c, R2, 16.0)
	_resultat = [_tableaux(r1, 4.0, Rect2()), _tableaux(r2, 8.0, r1), _tableaux(zone, 16.0, r2)]


## Carré autour de c, calé sur la grille de pas `p`, dans la zone.
func _rect(c: Vector2, r: float, p: float) -> Rect2:
	var a: Vector2 = Vector2(maxf(snappedf(c.x - r - x0, p) + x0, zone.position.x), maxf(snappedf(c.y - r - z0, p) + z0, zone.position.y))
	var b: Vector2 = Vector2(minf(snappedf(c.x + r - x0, p) + x0, zone.end.x), minf(snappedf(c.y + r - z0, p) + z0, zone.end.y))
	return Rect2(a, b - a)


func _tableaux(r: Rect2, p: float, trou: Rect2) -> Array:
	var nj: int = int(round(r.size.x / p)) + 1
	var ni: int = int(round(r.size.y / p)) + 1
	var h: PackedFloat32Array = PackedFloat32Array()
	h.resize(ni * nj)
	for i in range(ni):
		var z: float = r.position.y + i * p
		for j in range(nj):
			h[i * nj + j] = rel._hauteur_tri(r.position.x + j * p, z)
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
		var z: float = r.position.y + i * p
		for j in range(nj):
			var x: float = r.position.x + j * p
			var k: int = i * nj + j
			var gx: float = h[i * nj + mini(j + 1, nj - 1)] - h[i * nj + maxi(j - 1, 0)]
			var gz: float = h[mini(i + 1, ni - 1) * nj + j] - h[maxi(i - 1, 0) * nj + j]
			v[k] = Vector3(x, h[k], z)
			n[k] = Vector3(-gx, 2.0 * p, -gz).normalized()
			uv[k] = Vector2((x - ReliefDonnees.X_OUEST) / lx, (z - ReliefDonnees.Z_NORD) / lz)
	var idx: PackedInt32Array = PackedInt32Array()
	var av_trou: bool = trou.has_area()
	for i in range(ni - 1):
		var zc: float = r.position.y + (i + 0.5) * p
		for j in range(nj - 1):
			if av_trou and trou.has_point(Vector2(r.position.x + (j + 0.5) * p, zc)):
				continue
			var a: int = i * nj + j
			idx.append_array(PackedInt32Array([a, a + 1, a + nj, a + 1, a + nj + 1, a + nj]))
	# jupe du bord : descend sous la grille voisine, plus grossière, et cache la jointure
	if not av_trou or p < 16.0:
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
