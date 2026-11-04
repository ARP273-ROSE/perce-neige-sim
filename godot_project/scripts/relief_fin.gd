class_name ReliefFin
extends Node3D
## Relief fin : tout le domaine à 5 m (IGN RGE ALTI), PC partis au cran 0 seulement.
## La grille fine subdivise les mailles du relief à 25 m (K mailles par côté) : ses
## triangles sont LE sol des mailles touchées, pour l'affichage, les collisions et
## hauteur_sol. Ajouter un écart sur une grille décalée faisait deux surfaces : les plis
## de la grille à 25 m tombaient dans les mailles fines (0,27 m contre la collision,
## banc du ski, 03/11/2026). Une maille sans écart reste celle du relief à 25 m, et
## son bord, droit sur les deux grilles, se raccorde sans trou.
##
## Donnée : écart à relief_hauteurs.png, préparé hors du jeu depuis les demandes WMS de
## l'IGN calées sur leur grille (360/2^23 degré, soit 3,35 × 4,78 m ici : mesuré sur les
## marches des réponses ; que ce soit la résolution d'origine de la donnée reste une
## hypothèse). Une demande décalée revient au plus proche voisin, en marches et en
## quadrillage, absents de l'orthophoto.
## Décodage : module C++ (noyau_remontee.cpp), sur le fil de préparation du relief. Sans
## module, relief à 25 m : une boucle GDScript sur 14,5 M de nœuds n'est pas envisageable.
## Déblais des gares et aménagements restent ceux du relief à 25 m.
## Affichage : grille suiveuse autour de la caméra, reconstruite à côté du fil principal
## quand elle s'est éloignée de son centre ; au-delà, les tuiles, recalées sur les mêmes
## altitudes aux nœuds à 25 m.

const KF: int = 5                    # grille du dépôt : 5,00 m
const KHD: int = 25                  # pack haute définition : 1,00 m
const NCX: int = ReliefDonnees.NX - 1
const NCZ: int = ReliefDonnees.NZ - 1
const L_X: float = (ReliefDonnees.X_EST - ReliefDonnees.X_OUEST) / float(NCX)
const L_Z: float = (ReliefDonnees.Z_SUD - ReliefDonnees.Z_NORD) / float(NCZ)
static var K: int = KF               # mailles fines par maille à 25 m
static var NJ: int = NCX * KF + 1
static var NI: int = NCZ * KF + 1
static var PX: float = L_X / KF
static var PZ: float = L_Z / KF
const X0: float = ReliefDonnees.X_OUEST
const Z0: float = ReliefDonnees.Z_NORD
const FICHIER: String = "res://data/relief_fin/domaine.bin"
const FONDU: float = 64.0
const R1: float = 256.0              # demi-côté de la grille à 5 m
const R2: float = 640.0              # à 10 m
const R3: float = 1536.0             # à 20 m ; au-delà, les tuiles à 25 m
const SEUIL: float = 48.0            # déplacement qui relance la grille
const JUPE: float = 1.5              # jupe des bords, cache les jointures entre pas

var rel: ReliefBuilder = null
var pret: bool = false
var zone: Rect2 = Rect2(X0, Z0, NCX * L_X, NCZ * L_Z)
var _k_propre: int = KF
var hd: bool = false                                 # sol au mètre du pack, anneaux, normales
var anneaux: ReliefAnneaux = null
var _couches_normales: Array = []
var _couches_ortho: Array = []
var _hn: PackedFloat32Array = PackedFloat32Array()   # altitude des nœuds de la grille fine
var _fine: PackedByteArray = PackedByteArray()       # par maille à 25 m : 1 si la grille fine y est le sol
var _mat: ShaderMaterial = null
var _mi: Array = []
var _centre: Vector2 = Vector2(INF, INF)
var _tache: int = -1
var _resultat: Array = []
var _trou_tuiles: Rect2 = Rect2()
var _demande: Vector2 = Vector2.ZERO


## PC parti au cran 0 : décidé au chargement, le sol ne change plus ensuite (le régulateur
## peut baisser de cran en cours de partie, le skieur reste sur le même sol). Aux autres
## crans et sur le web, rien n'est lu : relief à 25 m, sans surcoût de chargement.
## --relief-fin : force la grille fine (les bancs sans écran ne partent pas forcément au cran 0).
static func voulu(cran: int) -> bool:
	if not (voulu_sans_forcer(cran) or ("--relief-fin" in OS.get_cmdline_user_args() and _permis())):
		return false
	if not ClassDB.class_has_method("NoyauRemontee", "fusion_relief"):
		print("[ReliefFin] module C++ absent : relief à 25 m")
		return false
	return true


static func voulu_sans_forcer(cran: int) -> bool:
	return cran == 0 and _permis()


## Pack haute définition : un fichier optionnel à côté de l'exécutable (dossier pack_hd).
## Absent, le jeu tourne comme avant. --pack-hd=dossier pour les essais.
static func dossier_pack() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pack-hd="):
			return a.trim_prefix("--pack-hd=")
	return OS.get_executable_path().get_base_dir().path_join("pack_hd")


## Sol au mètre : 1,45 Go de grille en mémoire, 16 Go de mémoire vive au moins.
static func hd_voulu() -> bool:
	if "--sans-hd" in OS.get_cmdline_user_args() or not ClassDB.class_exists("ReliefHD"):
		return false
	if not FileAccess.file_exists(dossier_pack().path_join("relief.pnhd")):
		return false
	var ram_go: float = float(OS.get_memory_info().get("physical", 0)) / 1073741824.0
	return ram_go >= 15.0 or "--hd-force" in OS.get_cmdline_user_args()


static func _regler_grille(k: int) -> void:
	K = k
	NJ = NCX * k + 1
	NI = NCZ * k + 1
	PX = L_X / k
	PZ = L_Z / k


static func _permis() -> bool:
	if OS.has_feature("web") or "--sans-relief-fin" in OS.get_cmdline_user_args():
		return false
	return FileAccess.file_exists(FICHIER)


## Lit l'écart et calcule les altitudes des nœuds (fil de préparation du relief). Écart
## annulé là où le relief à 25 m a été retouché (déblais) ou sous un aménagement ; les
## nœuds à 25 m du relief prennent les altitudes de la grille fine, pour les tuiles.
func preparer(r: ReliefBuilder, h0: PackedFloat32Array) -> void:
	rel = r
	var debut: int = Time.get_ticks_usec()
	_regler_grille(KF)
	var f: FileAccess = FileAccess.open(FICHIER, FileAccess.READ)
	if f == null:
		return
	var compresse: PackedByteArray = f.get_buffer(f.get_length())
	var ecart: PackedByteArray = compresse.decompress(NI * NJ * 2, FileAccess.COMPRESSION_DEFLATE)
	var t_lu: int = Time.get_ticks_usec()
	var rects: PackedFloat32Array = PackedFloat32Array()
	var liste: Array = []
	for am in r.amenagements:
		liste.append((am["rect"] as Rect2).grow(FONDU))
	# galerie de la sortie de secours : sa couverture et son portail restent ceux du relief à 25 m
	liste.append(Rect2(100.0, 2010.0, 80.0, 70.0).grow(FONDU))
	for rc in liste:
		var q: Rect2 = rc
		rects.append_array(PackedFloat32Array([q.position.x, q.position.y, q.end.x, q.end.y]))
	var n: RefCounted = ClassDB.instantiate("NoyauRemontee")
	var res: Array = n.call("fusion_relief", r._h, h0, ecart, ReliefDonnees.NX, ReliefDonnees.NZ, K, rects, X0, Z0, K * PX, K * PZ)
	if res.size() != 3:
		print("[ReliefFin] donnée illisible : relief à 25 m")
		return
	_hn = res[0]
	_fine = res[1]
	var h_retouche: PackedFloat32Array = r._h
	r._h = res[2]
	pret = true
	print("[ReliefFin] %.1f M de nœuds : lecture %d ms, fusion %d ms" % [NI * NJ / 1.0e6, (t_lu - debut) / 1000, (Time.get_ticks_usec() - t_lu) / 1000])
	if hd_voulu():
		# (les gares s'annoncent au fil principal, après le départ de ce fil de préparation)
		var attente: int = Time.get_ticks_msec() + 20000
		while not r.amenagements_poses and Time.get_ticks_msec() < attente:
			OS.delay_msec(5)
		for am in r.amenagements:
			var q2: Rect2 = (am["rect"] as Rect2).grow(FONDU + RACCORD_GARE)
			rects.append_array(PackedFloat32Array([q2.position.x, q2.position.y, q2.end.x, q2.end.y]))
		_preparer_hd(r, h0, h_retouche, rects)


## Sol au mètre : le relevé LiDAR du pack, sauf sous les ouvrages, où reste la grille à 5 m sur
## laquelle ils sont réglés. Couloir de chaque ligne (gares, rampes, pylônes, véhicules) et
## aménagements : hauteur_sol ne change pas, ni le profil des lignes qui y est lu.
func _preparer_hd(r: ReliefBuilder, h0: PackedFloat32Array, h_retouche: PackedFloat32Array, rects: PackedFloat32Array) -> void:
	var t0: int = Time.get_ticks_usec()
	var n: RefCounted = ClassDB.instantiate("ReliefHD")
	var nj1: int = NCX * KHD + 1
	var ni1: int = NCZ * KHD + 1
	var chemin: String = ProjectSettings.globalize_path(dossier_pack().path_join("relief.pnhd"))
	var leve: PackedFloat32Array = n.call("decoder", chemin, 0, nj1, ni1)
	if leve.is_empty():
		print("[ReliefHD] pack illisible : grille à 5 m")
		return
	var t1: int = Time.get_ticks_usec()
	var caps: PackedFloat32Array = PackedFloat32Array()
	for D in RemonteesDonnees.LIGNES:
		var a: Vector2 = RemonteesDomaine.monde(float(D["aval"][0]), float(D["aval"][1]))
		var b: Vector2 = RemonteesDomaine.monde(float(D["amont"][0]), float(D["amont"][1]))
		if a.distance_to(b) < 1.0:
			continue
		var u: Vector2 = (b - a).normalized()
		a -= u * RACCORD_BOUT
		b += u * RACCORD_BOUT
		var r0: float = float(D["voie"]) * 0.5 + RACCORD_R0
		caps.append_array(PackedFloat32Array([a.x, a.y, b.x, b.y, r0, r0 + RACCORD_LARGEUR]))
	var reference: PackedFloat32Array = _hn
	var res: Array = n.call("raccorder", leve, _hn, _fine, h_retouche, h0, ReliefDonnees.NX, ReliefDonnees.NZ, KHD, KF,
		caps, rects, RACCORD_LARGEUR, X0, Z0, L_X / KHD, L_Z / KHD)
	if res.size() != 3:
		print("[ReliefHD] raccord impossible : grille à 5 m")
		return
	_hn = res[0]
	_fine = res[1]
	r._h = res[2]
	if "--garder-reference" in OS.get_cmdline_user_args():
		r._h0_ref = h0
		r._hn5_ref = reference
	_regler_grille(KHD)
	_k_propre = KHD
	hd = true
	var t2: int = Time.get_ticks_usec()
	if DisplayServer.get_name() != "headless":
		# (du relevé, partout : le sol réglé des ouvrages, en facettes à 25 m, marquait l'ombrage ;
		# le détail reste lisible le long des lignes)
		_couches_normales = n.call("normales", leve, NJ, NI, ReliefAnneaux.TUILE, ReliefAnneaux.TAILLE, ReliefAnneaux.MARGE, PX, PZ)
	print("[ReliefHD] sol à 1 m, %.0f M de nœuds : pack %d ms, raccord %d ms, normales %d ms" % [NI * NJ / 1.0e6,
		(t1 - t0) / 1000, (t2 - t1) / 1000, (Time.get_ticks_usec() - t2) / 1000])
	var f_ortho: String = dossier_pack().path_join("ortho.pnhd")
	if DisplayServer.get_name() != "headless" and FileAccess.file_exists(f_ortho):
		var t3: int = Time.get_ticks_usec()
		_couches_ortho = n.call("couches", f_ortho)
		print("[ReliefHD] orthophoto : %d couches, %d ms" % [maxi(_couches_ortho.size() - 2, 0), (Time.get_ticks_usec() - t3) / 1000])


const RACCORD_R0: float = 12.0        # couloir d'une ligne, au-delà de sa demi-voie : le sol réglé
const RACCORD_LARGEUR: float = 16.0   # raccord vers le relevé
const RACCORD_GARE: float = 30.0      # abords des gares du funiculaire (rampes, terrasses, au ras du sol)
const RACCORD_BOUT: float = 60.0      # couloir prolongé derrière chaque gare (rampes)


## Tableau de textures des normales (fil principal) : à poser sur les matériaux du relief.
func normales_texture() -> Texture2DArray:
	if _couches_normales.is_empty():
		return null
	var images: Array[Image] = []
	for o in _couches_normales:
		images.append(Image.create_from_data(ReliefAnneaux.TAILLE, ReliefAnneaux.TAILLE, true, Image.FORMAT_RGTC_RG, o))
	_couches_normales = []
	var t: Texture2DArray = Texture2DArray.new()
	t.create_from_images(images)
	return t


## Tableau de textures de l'orthophoto au mètre, ou null sans le fichier.
func ortho_texture() -> Texture2DArray:
	if _couches_ortho.size() < 3:
		return null
	var fmt: Image.Format = _couches_ortho[0] as Image.Format
	var taille: int = _couches_ortho[1]
	var images: Array[Image] = []
	for k in range(2, _couches_ortho.size()):
		images.append(Image.create_from_data(taille, taille, true, fmt, _couches_ortho[k]))
	_couches_ortho = []
	var t: Texture2DArray = Texture2DArray.new()
	t.create_from_images(images)
	return t


func noeuds_grille() -> PackedFloat32Array:
	return _hn


func mailles_fines() -> PackedByteArray:
	return _fine


## Altitude sur les triangles de cette grille, où que soit (x, z) (bancs).
func hauteur_grille(x: float, z: float) -> float:
	var px: float = L_X / _k_propre
	var pz: float = L_Z / _k_propre
	var nj: int = NCX * _k_propre + 1
	var ni: int = NCZ * _k_propre + 1
	var fx: float = clampf((x - X0) / px, 0.0, nj - 1.001)
	var fz: float = clampf((z - Z0) / pz, 0.0, ni - 1.001)
	var j: int = int(fx)
	var i: int = int(fz)
	var u: float = fx - j
	var v: float = fz - i
	var a: int = i * nj + j
	if u + v <= 1.0:
		return _hn[a] + (_hn[a + 1] - _hn[a]) * u + (_hn[a + nj] - _hn[a]) * v
	var d: float = _hn[a + nj + 1]
	return d + (_hn[a + nj] - d) * (1.0 - u) + (_hn[a + 1] - d) * (1.0 - v)


## Banc : la grille à 5 m seule, sur le relief d'origine et les mêmes aménagements.
static func reference_5m(r: ReliefBuilder) -> ReliefFin:
	if r._h0_ref.is_empty():
		return null
	var rf: ReliefFin = ReliefFin.new()
	rf._hn = r._hn5_ref
	rf._k_propre = KF
	return rf


## La grille fine est-elle le sol au point (x, z) ?
func fine_ici(x: float, z: float) -> bool:
	var cj: int = int(floor((x - X0) / L_X))
	var ci: int = int(floor((z - Z0) / L_Z))
	return cj >= 0 and ci >= 0 and cj < NCX and ci < NCZ and _fine[ci * NCX + cj] == 1


## Altitude sur les triangles de la grille fine ; (x, z) dans une maille où fine_ici est vrai.
func hauteur(x: float, z: float) -> float:
	var fx: float = (x - X0) / PX
	var fz: float = (z - Z0) / PZ
	var j: int = mini(int(fx), NJ - 2)
	var i: int = mini(int(fz), NI - 2)
	var u: float = fx - j
	var v: float = fz - i
	var a: int = i * NJ + j
	# même découpe que la grille affichée et les collisions : (a, a+1, a+NJ) puis (a+1, a+NJ+1, a+NJ)
	if u + v <= 1.0:
		return _hn[a] + (_hn[a + 1] - _hn[a]) * u + (_hn[a + NJ] - _hn[a]) * v
	var d: float = _hn[a + NJ + 1]
	return d + (_hn[a + NJ] - d) * (1.0 - u) + (_hn[a + 1] - d) * (1.0 - v)


## Nœud (i, j) de la grille fine, en coordonnées du jeu.
func noeud(i: int, j: int) -> Vector3:
	return Vector3(X0 + j * PX, _hn[i * NJ + j], Z0 + i * PZ)


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return                 # (bancs : le sol suit, sans rien à afficher)
	name = "ReliefFin"
	if hd:
		set_process(false)
		anneaux = ReliefAnneaux.new()
		add_child(anneaux)
		anneaux.demarrer(self, rel)
		return
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
	_relancer(_point_vue())


func _point_vue() -> Vector2:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return Vector2(0.0, 0.0)
	return Vector2(cam.global_position.x, cam.global_position.z)


func _process(_dt: float) -> void:
	if _tache >= 0 and WorkerThreadPool.is_task_completed(_tache):
		WorkerThreadPool.wait_for_task_completion(_tache)
		_tache = -1
		_poser()
	if _tache < 0 and _point_vue().distance_to(_centre) > SEUIL:
		_relancer(_point_vue())


func _relancer(p: Vector2) -> void:
	p.x = clampf(snappedf(p.x, 32.0), zone.position.x, zone.end.x)
	p.y = clampf(snappedf(p.y, 32.0), zone.position.y, zone.end.y)
	_demande = p
	_centre = p
	_tache = WorkerThreadPool.add_task(_calculer, false, "relief fin")


func _calculer() -> void:
	var c: Vector2 = _demande
	var r1: Rect2i = _rect(c, R1, 2)
	var r2: Rect2i = _rect(c, R2, 4)
	# bord extérieur sur des nœuds à 25 m : les tuiles y ont les mêmes altitudes
	var r3: Rect2i = _rect(c, R3, 4 * K)
	_trou_tuiles = Rect2(X0 + r3.position.x * PX, Z0 + r3.position.y * PZ, r3.size.x * PX, r3.size.y * PZ)
	_resultat = [_tableaux(r1, 1, Rect2i()), _tableaux(r2, 2, r1), _tableaux(r3, 4, r2)]


## Carré autour de c, en nœuds de la grille fine, calé sur un multiple de s.
func _rect(c: Vector2, r: float, s: int) -> Rect2i:
	var fin_j: int = (NJ - 1) / s * s
	var fin_i: int = (NI - 1) / s * s
	var ja: int = clampi(int(round((c.x - r - X0) / (PX * s))) * s, 0, fin_j)
	var ia: int = clampi(int(round((c.y - r - Z0) / (PZ * s))) * s, 0, fin_i)
	var jb: int = clampi(int(round((c.x + r - X0) / (PX * s))) * s, 0, fin_j)
	var ib: int = clampi(int(round((c.y + r - Z0) / (PZ * s))) * s, 0, fin_i)
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
			var gx: float = _hn[gi * NJ + mini(gj + s, NJ - 1)] - _hn[gi * NJ + maxi(gj - s, 0)]
			var gz: float = _hn[mini(gi + s, NI - 1) * NJ + gj] - _hn[maxi(gi - s, 0) * NJ + gj]
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
	rel.percer("relief_fin", _trou_tuiles)


func _exit_tree() -> void:
	# (la grille HD reste K = 25 d'une scène à l'autre tant que preparer ne la remet pas)
	if _tache >= 0:
		WorkerThreadPool.wait_for_task_completion(_tache)
		_tache = -1
