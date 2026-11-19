## Éclairages de nuit du domaine (19/11/2026) : candélabres aux gares des remontées (deux par gare, côté accès),
## vitres des cabines et des gares éclairées de l'intérieur, plafonnier de la cabine où l'on est assis.
## Peu de vraies lumières : les têtes des candélabres et les vitres sont émissives (aucun coût d'éclairage) ; seules
## quelques OmniLight3D, posées sur les candélabres les plus proches de la caméra, éclairent la neige — leur nombre
## suit la machine (PerfManager : carte dédiée 8, cran ≥ 3 4, puce intégrée 2, PWA 2, PWA de secours 0). De jour,
## tout est éteint et caché : rien ne coûte.
class_name EclairagesNuit
extends Node3D

const H_MAT: float = 6.5
const COULEUR: Color = Color(1.0, 0.80, 0.52)        # sodium-LED chaude ≈ 3 000 K
const PORTEE_LUMIERE: float = 24.0
const RAYON_CHOIX: float = 320.0
## Matériaux partagés des vitres (RemonteeKit) éclairés de l'intérieur la nuit, et la force de leur lueur.
const VITRES: Dictionary = {"vitre": 0.20, "vitre_bleue": 0.16, "vitre_bleu_clair": 0.18, "vitre_teintee": 0.12,
	"vitrage_sombre": 0.30}

var relief: ReliefBuilder = null
var remontees: RemonteesDomaine = null
var tetes: PackedVector3Array = PackedVector3Array()    # têtes des candélabres (monde)
var _mm_mats: MultiMeshInstance3D = null
var _mm_tetes: MultiMeshInstance3D = null
var _mat_tete: StandardMaterial3D = null
var _lumieres: Array = []
var _t_choix: float = 0.0
var niveau: float = 0.0                  # 0 éteint, 1 allumé (CycleJour « eclairage »)
var _vitres_pretes: bool = false
var _plafonnier: OmniLight3D = null
var n_lumieres_max: int = 8
var _construit: bool = false
var _n_applique: float = -1.0             # niveau déjà appliqué aux matériaux (vitres, têtes)
var _t_vitres: float = 0.0                # repris toutes les 5 s (lignes cuites chargées entre-temps)


static func lumieres_max() -> int:
	if OS.has_feature("web"):
		return 0 if PerfManager.secours_web >= 1 else 2
	if PerfManager.allege or PerfManager.type_gpu == "integre":
		return 2 if PerfManager.cran_courant >= 3 else 3
	return 8 if PerfManager.cran_courant <= 2 else 4


func _init() -> void:
	name = "EclairagesNuit"


## Candélabres des gares (une fois les remontées posées).
func construire(r: ReliefBuilder, rm: RemonteesDomaine) -> void:
	if _construit:
		return
	_construit = true
	relief = r
	remontees = rm
	var pieds: PackedVector3Array = PackedVector3Array()
	for e in rm.lignes:
		var lg: LigneRemontee = e[0]
		if lg is Funival:
			continue
		var xf: Transform3D = lg.global_transform if lg.is_inside_tree() else lg.xf_monde
		var L: float = lg.longueur_h()
		var lat: float = lg.voie * 0.5 + 3.2
		for aval in [true, false]:
			var z: float = (lg.l_gare + 2.5) if aval else (-L - lg.l_gare - 2.5)
			for sd in [-1.0, 1.0]:
				var p: Vector3 = xf * Vector3(sd * lat, 0.0, z)
				var h: float = relief.hauteur_sol(p.x, p.z) if relief != null else p.y
				if is_inf(h) or is_nan(h):
					continue
				pieds.append(Vector3(p.x, h, p.z))
	var mat_mat := StandardMaterial3D.new()
	mat_mat.albedo_color = Color(0.25, 0.26, 0.28)
	mat_mat.metallic = 0.6
	mat_mat.roughness = 0.5
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.09
	cyl.height = H_MAT
	cyl.radial_segments = 6
	cyl.rings = 1
	cyl.material = mat_mat
	_mat_tete = StandardMaterial3D.new()
	_mat_tete.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_tete.albedo_color = Color(0.12, 0.12, 0.12)
	var tete := BoxMesh.new()
	tete.size = Vector3(0.55, 0.14, 0.30)
	tete.material = _mat_tete
	var mm1 := MultiMesh.new()
	mm1.transform_format = MultiMesh.TRANSFORM_3D
	mm1.mesh = cyl
	mm1.instance_count = pieds.size()
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.mesh = tete
	mm2.instance_count = pieds.size()
	tetes.resize(pieds.size())
	for k in range(pieds.size()):
		var p2: Vector3 = pieds[k]
		mm1.set_instance_transform(k, Transform3D(Basis.IDENTITY, p2 + Vector3(0.0, H_MAT * 0.5, 0.0)))
		var t: Vector3 = p2 + Vector3(0.0, H_MAT + 0.05, 0.0)
		mm2.set_instance_transform(k, Transform3D(Basis.IDENTITY, t))
		tetes[k] = t
	_mm_mats = MultiMeshInstance3D.new()
	_mm_mats.name = "Candelabres"
	_mm_mats.multimesh = mm1
	_mm_mats.layers = 1 | Cabin.LAYER_VOIE
	_mm_mats.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm_mats)
	_mm_tetes = MultiMeshInstance3D.new()
	_mm_tetes.name = "TetesCandelabres"
	_mm_tetes.multimesh = mm2
	_mm_tetes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm_tetes)
	print("[Nuit] %d candélabres aux gares" % pieds.size())


## Niveau d'éclairage (0..1, CycleJour « eclairage ») et caméra : allume, éteint, place les vraies lumières.
func regler(n: float, cam_pos: Vector3, dt: float, support: Node3D = null, tete: Vector3 = Vector3.ZERO) -> void:
	niveau = n
	var allume: bool = n > 0.02
	visible = allume
	_t_vitres -= dt
	if absf(n - _n_applique) > 0.004 or (n == 0.0 and _n_applique != 0.0) or (n > 0.0 and _t_vitres <= 0.0):
		_t_vitres = 5.0
		_n_applique = n
		if _mat_tete != null:
			_mat_tete.albedo_color = Color(0.12, 0.12, 0.12).lerp(Color(1.6, 1.3, 0.9), n)
		_regler_vitres(n)
	n_lumieres_max = lumieres_max()
	if not allume:
		for l in _lumieres:
			(l as Node).queue_free()
		_lumieres.clear()
		_regler_plafonnier(null, 0.0, tete)
		return
	_t_choix -= dt
	if _t_choix <= 0.0:
		_t_choix = 0.75
		_choisir(cam_pos)
	for l in _lumieres:
		(l as OmniLight3D).light_energy = 2.2 * n
	_regler_plafonnier(support, n, tete)


func _choisir(cam_pos: Vector3) -> void:
	# les têtes les plus proches de la caméra (à moins de RAYON_CHOIX)
	var proches: Array = []
	for k in range(tetes.size()):
		var d: float = tetes[k].distance_squared_to(cam_pos)
		if d < RAYON_CHOIX * RAYON_CHOIX:
			proches.append([d, k])
	proches.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var n: int = mini(proches.size(), n_lumieres_max)
	while _lumieres.size() < n:
		var o := OmniLight3D.new()
		o.light_color = COULEUR
		o.omni_range = PORTEE_LUMIERE
		o.omni_attenuation = 1.2
		o.shadow_enabled = false
		o.light_specular = 0.3
		add_child(o)
		_lumieres.append(o)
	while _lumieres.size() > n:
		(_lumieres.pop_back() as Node).queue_free()
	for j in range(n):
		(_lumieres[j] as OmniLight3D).global_position = tetes[int(proches[j][1])] - Vector3(0.0, 0.35, 0.0)


## Vitres des cabines, des téléphériques et des gares : lueur chaude de l'intérieur. L'émission n'est activée
## qu'à la première tombée de la nuit (une variante de nuanceur de plus) et reste ensuite à 0 de jour.
func _regler_vitres(n: float) -> void:
	if n <= 0.0 and not _vitres_pretes:
		return
	var mats: Array = []
	for nom in VITRES:
		mats.append([RemonteeKit.mat(nom), float(VITRES[nom])])
	# copies des lignes cuites (vues de loin) : mêmes couleurs que celles du kit
	LigneCuite._verrou.lock()
	for m in LigneCuite._materiaux_communs.values():
		if m is StandardMaterial3D:
			var sm: StandardMaterial3D = m
			if sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				continue
			for nom2 in VITRES:
				if sm.albedo_color.is_equal_approx(RemonteeKit.mat(nom2).albedo_color):
					mats.append([sm, float(VITRES[nom2])])
	LigneCuite._verrou.unlock()
	for e in mats:
		var m2: StandardMaterial3D = e[0]
		if not m2.emission_enabled:
			if n <= 0.0:
				continue
			m2.emission_enabled = true
			m2.emission = COULEUR
		m2.emission_energy_multiplier = float(e[1]) * n
	if n > 0.0:
		_vitres_pretes = true


## Plafonnier dans la cabine où le skieur est assis (une seule petite lumière).
func _regler_plafonnier(support: Node3D, n: float, tete: Vector3) -> void:
	if support == null or n <= 0.02:
		if _plafonnier != null:
			_plafonnier.queue_free()
			_plafonnier = null
		return
	if _plafonnier != null and _plafonnier.get_parent() != support:
		_plafonnier.queue_free()
		_plafonnier = null
	if _plafonnier == null:
		_plafonnier = OmniLight3D.new()
		_plafonnier.name = "PlafonnierNuit"
		_plafonnier.light_color = Color(1.0, 0.88, 0.70)
		_plafonnier.omni_range = 3.2
		_plafonnier.shadow_enabled = false
		support.add_child(_plafonnier)
		# au plafond, au-dessus de la tête du skieur assis
		_plafonnier.position = support.to_local(tete + Vector3(0.0, 0.55, 0.0))
	_plafonnier.light_energy = 0.9 * n


## Têtes de candélabres les plus proches (lampes du décor : la neige éclairée autour des gares).
func lampes_decor(cam_pos: Vector3) -> Array:
	var out: Array = []
	if niveau <= 0.02:
		return out
	var proches: Array = []
	for k in range(tetes.size()):
		var d: float = tetes[k].distance_squared_to(cam_pos)
		if d < 250000.0:
			proches.append([d, k])
	proches.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for j in range(mini(proches.size(), LampesDecor.N)):
		out.append({"p": tetes[int(proches[j][1])] - Vector3(0.0, 0.3, 0.0), "r": PORTEE_LUMIERE, "c": COULEUR * 1.1 * niveau})
	return out
