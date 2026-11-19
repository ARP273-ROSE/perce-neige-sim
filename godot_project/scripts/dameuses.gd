## Dameuses de nuit (19/11/2026) : le soir et la nuit, de la fermeture des pistes (17 h 30) au matin, une ou deux
## dameuses travaillent sur les pistes balisées autour de la caméra (PistesDonnees, comme les skieurs IA). Engin
## dessiné ici (pas la copie d'un modèle de marque) : chenilles, lame à l'avant, fraise et peigne à l'arrière,
## cabine éclairée, gyrophares orange, phares, treuil sur le capot.
## Sur une pente raide (> 38 %), la dameuse est treuillée : un câble d'acier tendu court de la flèche du treuil à
## un ancrage en amont, posé sur la neige là où le relief le soulève. Câble DANGEREUX : le skieur qui le touche
## tombe (main._maj_nuit). Bruit de moteur diesel de synthèse (aucun son sous droits).
## Coût : un maillage par dameuse (une surface par matériau), un MultiMesh pour le câble, des phares (SpotLight3D)
## sur la plus proche seulement, selon la machine (PerfManager).
class_name Dameuses
extends Node3D

const V: float = 3.6                       # m/s (13 km/h)
const PENTE_TREUIL: float = 0.38           # au-delà, treuillée (≈ 21°)
const PENTE_LACHE: float = 0.26
const APPARITION_MIN: float = 140.0
const APPARITION_MAX: float = 650.0
const RETRAIT: float = 1500.0
const CABLE_MAX: float = 420.0
const N_SEG: int = 30
const RAYON_CABLE: float = 0.022           # câble de 11 mm, épaissi pour qu'on le devine
const PAS_ECH: float = 40.0
const CASE_ECH: float = 250.0
const DEMI_LONG: float = 3.2               # demi-longueur hors tout, lame et fraise comprises
const DEMI_LARG: float = 2.4

var relief: ReliefBuilder = null
## Heure de damage (posé par main) ; faux : plus aucune dameuse.
var actives: bool = false
var n_voulu: int = 0
var engins: Array = []                    # Dictionary par dameuse
var _axes: Array = []
var _longs: Array = []
var _ech_cases: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _t_maj: float = 0.0
var _prete: bool = false
var _n_forcees: int = 0
## Phares réels sur la plus proche : 0, 1 ou 2 (PerfManager).
var phares_max: int = 2

static var _maillage: ArrayMesh = null
static var _maillage_fleche: ArrayMesh = null
static var _maillage_ancre: ArrayMesh = null
static var _cyl_cable: CylinderMesh = null
static var _mat_cable: StandardMaterial3D = null
static var _son: AudioStreamWAV = null


static func n_max() -> int:
	if OS.has_feature("web"):
		return 0 if PerfManager.secours_web >= 2 else 1
	return 1 if PerfManager.allege else 2


func preparer(r: ReliefBuilder) -> void:
	relief = r
	name = "Dameuses"
	_rng.seed = 1730
	for i in range(PistesDonnees.PISTES.size()):
		var a: PackedVector2Array = PistesDonnees.axe(i)
		var l: PackedFloat32Array = PackedFloat32Array([0.0])
		for k in range(1, a.size()):
			l.append(l[k - 1] + a[k - 1].distance_to(a[k]))
		_axes.append(a)
		_longs.append(l)
		if a.size() < 2 or l[l.size() - 1] < 250.0:
			continue
		var s: float = 60.0
		while s < l[l.size() - 1] - 60.0:
			var q: Vector2 = _point(i, s)
			var c: Vector2i = Vector2i(floori(q.x / CASE_ECH), floori(q.y / CASE_ECH))
			if not _ech_cases.has(c):
				_ech_cases[c] = []
			(_ech_cases[c] as Array).append([i, s, q])
			s += PAS_ECH
	_prete = true


func _point(i: int, s: float) -> Vector2:
	var a: PackedVector2Array = _axes[i]
	var l: PackedFloat32Array = _longs[i]
	s = clampf(s, 0.0, l[l.size() - 1])
	var k: int = clampi(l.bsearch(s, true) - 1, 0, a.size() - 2)
	var t: float = (s - l[k]) / maxf(l[k + 1] - l[k], 1e-3)
	return a[k].lerp(a[k + 1], t)


func _long(i: int) -> float:
	var l: PackedFloat32Array = _longs[i]
	return l[l.size() - 1]


func _h(q: Vector2) -> float:
	return relief.hauteur_sol(q.x, q.y) if relief != null else 0.0


## Pente (dénivelé / distance) le long de l'axe de la piste i en s (positive si l'abscisse croissante monte).
func pente(i: int, s: float) -> float:
	var a: float = clampf(s - 10.0, 0.0, _long(i))
	var b: float = clampf(s + 10.0, 0.0, _long(i))
	if b - a < 1.0:
		return 0.0
	return (_h(_point(i, b)) - _h(_point(i, a))) / (b - a)


# --- modèle -----------------------------------------------------------------------------------------------------

static func _mat_std(c: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _boite(st: SurfaceTool, taille: Vector3, xf: Transform3D) -> void:
	var b := BoxMesh.new()
	b.size = taille
	st.append_from(b, 0, xf)


static func _cyl(st: SurfaceTool, r: float, h: float, xf: Transform3D, seg: int = 12) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	st.append_from(c, 0, xf)


static func _xf(p: Vector3, rx: float = 0.0, ry: float = 0.0, rz: float = 0.0) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(rx, ry, rz)), p)


static func modele() -> ArrayMesh:
	if _maillage != null:
		return _maillage
	var mats: Dictionary = {
		"caisse": _mat_std(Color(0.78, 0.11, 0.07), 0.45, 0.2),
		"bande": _mat_std(Color(0.92, 0.92, 0.90), 0.6),
		"noir": _mat_std(Color(0.05, 0.05, 0.06), 0.9),
		"acier": _mat_std(Color(0.42, 0.44, 0.47), 0.4, 0.7),
		"vitre": _mat_std(Color(0.10, 0.12, 0.15), 0.1, 0.3),
		"phare": StandardMaterial3D.new(),
		"gyro": ShaderMaterial.new(),
	}
	# cabine éclairée de l'intérieur
	var mv: StandardMaterial3D = mats["vitre"]
	mv.emission_enabled = true
	mv.emission = Color(1.0, 0.80, 0.52)
	mv.emission_energy_multiplier = 0.18
	var mp: StandardMaterial3D = mats["phare"]
	mp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mp.albedo_color = Color(1.0, 0.98, 0.92)
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
varying float cote;
void vertex() {
	cote = step(0.0, VERTEX.x);
}
void fragment() {
	// deux feux qui tournent en alternance (la phase suit le côté)
	float a = pow(max(sin(TIME * 6.5 + cote * 3.1416), 0.0), 3.0);
	ALBEDO = vec3(1.0, 0.45, 0.04) * (0.25 + 2.2 * a);
}
"""
	(mats["gyro"] as ShaderMaterial).shader = sh
	var sts: Dictionary = {}
	for k in mats:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts[k] = st
	# chenilles et leurs galets d'extrémité
	for sd in [-1.0, 1.0]:
		_boite(sts["noir"], Vector3(1.15, 0.78, 3.9), _xf(Vector3(sd * 1.72, 0.52, 0.0)))
		for zz in [-1.95, 1.95]:
			_cyl(sts["noir"], 0.40, 1.15, _xf(Vector3(sd * 1.72, 0.50, zz), 0.0, 0.0, PI * 0.5))
			_cyl(sts["acier"], 0.22, 1.18, _xf(Vector3(sd * 1.72, 0.50, zz), 0.0, 0.0, PI * 0.5), 8)
		# crampons : barrettes sur le dessus de la chenille
		for kk in range(9):
			_boite(sts["acier"], Vector3(1.17, 0.05, 0.08), _xf(Vector3(sd * 1.72, 0.93, -1.8 + kk * 0.45)))
	# châssis, bande, cabine, capot
	_boite(sts["caisse"], Vector3(2.4, 0.85, 4.1), _xf(Vector3(0.0, 1.18, 0.0)))
	_boite(sts["bande"], Vector3(2.42, 0.12, 4.12), _xf(Vector3(0.0, 1.30, 0.0)))
	_boite(sts["vitre"], Vector3(1.86, 1.10, 1.76), _xf(Vector3(0.0, 2.16, -0.70)))
	_boite(sts["caisse"], Vector3(2.02, 0.14, 1.94), _xf(Vector3(0.0, 2.78, -0.70)))
	for px in [-0.95, 0.95]:
		for pz in [-1.6, 0.2]:
			_boite(sts["caisse"], Vector3(0.09, 1.12, 0.09), _xf(Vector3(px, 2.16, pz)))
	_boite(sts["caisse"], Vector3(2.15, 0.78, 1.85), _xf(Vector3(0.0, 1.98, 1.12)))
	_boite(sts["noir"], Vector3(1.9, 0.42, 0.03), _xf(Vector3(0.0, 1.98, 2.06)))
	_cyl(sts["noir"], 0.07, 0.9, _xf(Vector3(0.75, 2.75, 0.75)), 8)          # échappement
	# lame à l'avant (orientable, en trois pans), ses bras
	_boite(sts["acier"], Vector3(3.4, 1.05, 0.16), _xf(Vector3(0.0, 0.72, -3.0), deg_to_rad(-10.0)))
	for sd2 in [-1.0, 1.0]:
		_boite(sts["acier"], Vector3(0.95, 1.0, 0.15), _xf(Vector3(sd2 * 2.05, 0.72, -2.82), deg_to_rad(-10.0), sd2 * deg_to_rad(-28.0)))
		_boite(sts["noir"], Vector3(0.16, 0.16, 1.3), _xf(Vector3(sd2 * 0.75, 0.80, -2.3), deg_to_rad(8.0)))
	_boite(sts["caisse"], Vector3(3.42, 0.10, 0.18), _xf(Vector3(0.0, 1.25, -3.08), deg_to_rad(-10.0)))
	# fraise, capot de fraise et peigne (velours côtelé)
	_cyl(sts["acier"], 0.30, 4.2, _xf(Vector3(0.0, 0.34, 2.75), 0.0, 0.0, PI * 0.5), 10)
	_boite(sts["caisse"], Vector3(4.3, 0.10, 1.05), _xf(Vector3(0.0, 0.72, 2.75), deg_to_rad(6.0)))
	_boite(sts["noir"], Vector3(0.12, 0.55, 1.0), _xf(Vector3(-2.12, 0.45, 2.75)))
	_boite(sts["noir"], Vector3(0.12, 0.55, 1.0), _xf(Vector3(2.12, 0.45, 2.75)))
	_boite(sts["bande"], Vector3(4.2, 0.03, 0.85), _xf(Vector3(0.0, 0.10, 3.55), deg_to_rad(10.0)))
	_boite(sts["noir"], Vector3(0.6, 0.18, 0.7), _xf(Vector3(0.0, 0.82, 2.2)))           # attelage
	# phares : rampe sur le toit, feux de châssis, feux arrière
	_boite(sts["phare"], Vector3(1.6, 0.09, 0.09), _xf(Vector3(0.0, 2.90, -1.55)))
	for sd3 in [-0.85, 0.85]:
		_boite(sts["phare"], Vector3(0.32, 0.16, 0.05), _xf(Vector3(sd3, 1.42, -2.06)))
		_boite(sts["phare"], Vector3(0.22, 0.12, 0.05), _xf(Vector3(sd3 * 1.1, 2.70, 0.22)))
	# gyrophares
	for sd4 in [-0.72, 0.72]:
		_cyl(sts["gyro"], 0.085, 0.17, _xf(Vector3(sd4, 2.94, -0.15)), 10)
	# treuil : tambour et sa platine sur le capot
	_boite(sts["acier"], Vector3(1.1, 0.18, 0.62), _xf(Vector3(0.0, 2.45, 1.45)))
	_cyl(sts["acier"], 0.30, 0.95, _xf(Vector3(0.0, 2.72, 1.45), 0.0, 0.0, PI * 0.5), 12)
	var am := ArrayMesh.new()
	for k2 in mats:
		var st2: SurfaceTool = sts[k2]
		st2.generate_normals()
		st2.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mats[k2])
	_maillage = am
	# flèche du treuil (tourne vers l'ancrage) : bras le long de −Z, extrémité à 1,9 m
	var stf := SurfaceTool.new()
	stf.begin(Mesh.PRIMITIVE_TRIANGLES)
	_boite(stf, Vector3(0.20, 0.20, 1.9), _xf(Vector3(0.0, 0.0, -0.95)))
	_cyl(stf, 0.12, 0.26, _xf(Vector3(0.0, 0.0, -1.9), 0.0, 0.0, PI * 0.5), 8)
	stf.generate_normals()
	_maillage_fleche = stf.commit()
	_maillage_fleche.surface_set_material(0, mats["caisse"])
	# ancrage : piquet balisé orange et blanc
	var sta := SurfaceTool.new()
	sta.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cyl(sta, 0.10, 1.4, _xf(Vector3(0.0, 0.7, 0.0)), 8)
	_boite(sta, Vector3(0.7, 0.12, 0.7), _xf(Vector3(0.0, 0.06, 0.0)))
	sta.generate_normals()
	_maillage_ancre = sta.commit()
	var ma: StandardMaterial3D = _mat_std(Color(0.95, 0.42, 0.06), 0.6)
	ma.emission_enabled = true
	ma.emission = Color(0.95, 0.42, 0.06)
	ma.emission_energy_multiplier = 0.25
	_maillage_ancre.surface_set_material(0, ma)
	_cyl_cable = CylinderMesh.new()
	_cyl_cable.top_radius = 1.0
	_cyl_cable.bottom_radius = 1.0
	_cyl_cable.height = 1.0
	_cyl_cable.radial_segments = 5
	_cyl_cable.rings = 1
	# acier gras : presque invisible la nuit, il ne luit que dans les phares (un rien d'émission pour qu'on le devine)
	_mat_cable = _mat_std(Color(0.30, 0.31, 0.33), 0.30, 0.85)
	_mat_cable.emission_enabled = true
	_mat_cable.emission = Color(0.55, 0.58, 0.62)
	_mat_cable.emission_energy_multiplier = 0.25
	_cyl_cable.material = _mat_cable
	return _maillage


## Bruit de diesel de synthèse : 1 s en boucle (36 cycles d'allumage, harmoniques, bouffées filtrées, cliquetis
## des chenilles à 12 Hz), calculé une fois.
static func son_moteur() -> AudioStreamWAV:
	if _son != null:
		return _son
	var sr: int = 22050
	var n: int = sr
	var f0: float = 36.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 36
	var data := PackedByteArray()
	data.resize(n * 2)
	var bruit_f: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(sr)
		var ph: float = fposmod(t * f0, 1.0)
		var s: float = 0.0
		s += sin(TAU * f0 * t) * 0.55 + sin(TAU * 2.0 * f0 * t + 0.7) * 0.38 + sin(TAU * 3.0 * f0 * t + 1.9) * 0.22
		s += sin(TAU * 4.0 * f0 * t + 0.3) * 0.14 + sin(TAU * 6.0 * f0 * t + 2.4) * 0.08
		bruit_f += (rng.randf_range(-1.0, 1.0) - bruit_f) * 0.18
		s += bruit_f * exp(-ph * 7.0) * 1.6
		var pc: float = fposmod(t * 12.0, 1.0)
		if pc < 0.035:
			s += rng.randf_range(-1.0, 1.0) * 0.30 * (1.0 - pc / 0.035)
		var v: int = int(clampf(tanh(s * 0.9) * 0.62, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	_son = AudioStreamWAV.new()
	_son.format = AudioStreamWAV.FORMAT_16_BITS
	_son.mix_rate = sr
	_son.stereo = false
	_son.data = data
	_son.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_son.loop_begin = 0
	_son.loop_end = n
	return _son


# --- engins -----------------------------------------------------------------------------------------------------

func _creer(i: int, s: float, sens: float) -> Dictionary:
	var racine := Node3D.new()
	racine.name = "Dameuse%d" % engins.size()
	add_child(racine)
	var mi := MeshInstance3D.new()
	mi.name = "Corps"
	mi.mesh = modele()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.layers = 1 | Cabin.LAYER_VOIE           # éclairée par le Soleil ou la Lune du skieur dehors
	racine.add_child(mi)
	var piv := Node3D.new()
	piv.name = "Fleche"
	piv.position = Vector3(0.0, 2.80, 1.45)
	racine.add_child(piv)
	var mf := MeshInstance3D.new()
	mf.mesh = _maillage_fleche
	mf.layers = 1 | Cabin.LAYER_VOIE
	piv.add_child(mf)
	var son := AudioStreamPlayer3D.new()
	son.name = "Moteur"
	son.stream = son_moteur()
	son.unit_size = 9.0
	son.max_distance = 380.0
	son.volume_db = -2.0
	son.pitch_scale = 0.95 + 0.1 * _rng.randf()
	son.position = Vector3(0.0, 1.8, 1.0)
	racine.add_child(son)
	son.play(_rng.randf())
	# câble et ancrage (cachés hors treuil)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _cyl_cable
	mm.instance_count = N_SEG
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "CableTreuil"
	mmi.multimesh = mm
	mmi.top_level = true
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = CABLE_MAX
	mmi.layers = 1 | Cabin.LAYER_VOIE
	racine.add_child(mmi)
	var anc := MeshInstance3D.new()
	anc.name = "Ancrage"
	anc.mesh = _maillage_ancre
	anc.top_level = true
	anc.visible = false
	anc.layers = 1 | Cabin.LAYER_VOIE
	racine.add_child(anc)
	var e: Dictionary = {"noeud": racine, "corps": mi, "fleche": piv, "son": son, "cable": mmi, "ancre_mi": anc,
		"i": i, "s": s, "sens": sens, "dec": _rng.randf_range(-0.30, 0.30) * PistesDonnees.LARGEUR,
		"treuil": false, "ancre": Vector3.ZERO, "pts": PackedVector3Array(), "t_cable": 0.0, "lache": 0.0,
		"pose": false, "phares": []}
	engins.append(e)
	_poser(e, 0.0)
	return e


func _retirer(k: int) -> void:
	(engins[k]["noeud"] as Node3D).queue_free()
	engins.remove_at(k)


## Pose une dameuse sur une piste donnée (bancs, captures) ; treuil selon la pente.
func forcer(i: int, s: float, sens: float) -> Dictionary:
	if not _prete:
		return {}
	actives = true
	_n_forcees = engins.size() + 1
	n_voulu = maxi(n_voulu, _n_forcees)
	return _creer(i, clampf(s, 5.0, _long(i) - 5.0), sens)


## Point de piste le plus raide à moins de r de p (bancs, captures) : [piste, abscisse] ou [].
func piste_raide_pres(p: Vector3, r: float = 900.0) -> Array:
	var best: Array = []
	var pmax: float = PENTE_TREUIL
	var c: Vector2 = Vector2(p.x, p.z)
	for e in _echantillons(c, 0.0, r):
		var pe: float = absf(pente(int(e[0]), float(e[1])))
		if pe > pmax and pe < 0.85:
			pmax = pe
			best = [int(e[0]), float(e[1])]
	return best


func _echantillons(c: Vector2, r0: float, r1: float) -> Array:
	var out: Array = []
	var c0: Vector2i = Vector2i(floori((c.x - r1) / CASE_ECH), floori((c.y - r1) / CASE_ECH))
	var c1: Vector2i = Vector2i(floori((c.x + r1) / CASE_ECH), floori((c.y + r1) / CASE_ECH))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for e in _ech_cases.get(Vector2i(cx, cz), []):
				var d: float = (e[2] as Vector2).distance_to(c)
				if d >= r0 and d <= r1:
					out.append(e)
	return out


func _process(delta: float) -> void:
	if not _prete or relief == null or not is_inside_tree():
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var pc: Vector3 = cam.global_position
	_t_maj -= delta
	if _t_maj <= 0.0:
		_t_maj = 3.0
		n_voulu = maxi(n_max(), _n_forcees) if actives else 0
		for k in range(engins.size() - 1, -1, -1):
			var pk: Vector3 = engins[k]["noeud"].global_position
			if k >= n_voulu or Vector2(pk.x, pk.z).distance_to(Vector2(pc.x, pc.z)) > RETRAIT:
				_retirer(k)
		if actives and engins.size() < n_voulu:
			var ech: Array = _echantillons(Vector2(pc.x, pc.z), APPARITION_MIN, APPARITION_MAX)
			if not ech.is_empty():
				var e0: Array = ech[_rng.randi_range(0, ech.size() - 1)]
				_creer(int(e0[0]), float(e0[1]), 1.0 if _rng.randf() < 0.5 else -1.0)
	for e in engins:
		_poser(e, delta)
	_phares(pc)


func _poser(e: Dictionary, dt: float) -> void:
	var i: int = e["i"]
	var lmax: float = _long(i)
	var s: float = float(e["s"]) + float(e["sens"]) * V * dt
	if s <= 2.0 or s >= lmax - 2.0:
		# au bout : demi-tour, passe suivante décalée (on dame la piste en bandes)
		e["sens"] = -float(e["sens"])
		var dec: float = float(e["dec"]) + 4.2
		if dec > PistesDonnees.LARGEUR * 0.32:
			dec = -PistesDonnees.LARGEUR * 0.32
		e["dec"] = dec
		s = clampf(s, 2.0, lmax - 2.0)
		_lacher(e)
	e["s"] = s
	var sg: float = float(e["sens"])
	var q: Vector2 = _point(i, s)
	var q2: Vector2 = _point(i, clampf(s + sg * 3.0, 0.0, lmax))
	var tg: Vector2 = (q2 - q).normalized() if q2.distance_to(q) > 1e-3 else Vector2(0, -1)
	var nrm: Vector2 = Vector2(-tg.y, tg.x)
	var c2: Vector2 = q + nrm * float(e["dec"])
	var f2: Vector2 = tg
	var hf: float = _h(c2 + f2 * 2.2)
	var hb: float = _h(c2 - f2 * 2.2)
	var hr: float = _h(c2 + nrm * 1.6)
	var hl: float = _h(c2 - nrm * 1.6)
	var fwd: Vector3 = Vector3(f2.x * 4.4, hf - hb, f2.y * 4.4).normalized()
	var droite: Vector3 = Vector3(nrm.x * 3.2, hr - hl, nrm.y * 3.2).normalized()
	var haut: Vector3 = droite.cross(fwd).normalized()
	droite = fwd.cross(haut).normalized()
	var cible := Transform3D(Basis(droite, haut, -fwd), Vector3(c2.x, (hf + hb + hr + hl) * 0.25 + 0.02, c2.y))
	var racine: Node3D = e["noeud"]
	if not bool(e["pose"]):
		racine.global_transform = cible
		e["pose"] = true
	else:
		racine.global_transform = racine.global_transform.interpolate_with(cible, clampf(dt * 5.0, 0.0, 1.0))
	# treuil
	var p_ax: float = pente(i, s)
	var raide: bool = absf(p_ax) > PENTE_TREUIL
	if raide and not bool(e["treuil"]):
		_accrocher(e, p_ax)
	elif bool(e["treuil"]):
		if absf(p_ax) < PENTE_LACHE:
			e["lache"] = float(e["lache"]) + V * dt
			if float(e["lache"]) > 25.0:
				_lacher(e)
		else:
			e["lache"] = 0.0
	if bool(e["treuil"]):
		var anc: Vector3 = e["ancre"]
		if Vector2(anc.x, anc.z).distance_to(c2) < 12.0:
			_lacher(e)
	if bool(e["treuil"]):
		e["t_cable"] = float(e["t_cable"]) - dt
		var piv: Node3D = e["fleche"]
		var cible_f: Vector3 = e["ancre"]
		if piv.global_position.distance_to(cible_f) > 0.5:
			piv.look_at(cible_f, Vector3.UP)
		if float(e["t_cable"]) <= 0.0:
			e["t_cable"] = 0.08
			_tendre(e)
	# moteur : plus aigu en montée
	var monte: float = p_ax * sg
	(e["son"] as AudioStreamPlayer3D).pitch_scale = clampf(1.0 + monte * 0.35, 0.85, 1.25)


func _accrocher(e: Dictionary, p_ax: float) -> void:
	var i: int = e["i"]
	var s: float = e["s"]
	# ancrage en amont : on remonte l'axe tant que ça monte, au plus CABLE_MAX
	var sgn: float = 1.0 if p_ax > 0.0 else -1.0
	var sa: float = s
	var h_prec: float = _h(_point(i, s))
	var d: float = 0.0
	while d < CABLE_MAX:
		var s2: float = clampf(sa + sgn * 20.0, 0.0, _long(i))
		if is_equal_approx(s2, sa):
			break
		var h2: float = _h(_point(i, s2))
		if h2 < h_prec - 0.5:
			break
		sa = s2
		h_prec = h2
		d += 20.0
	if d < 40.0:
		return
	var qa: Vector2 = _point(i, sa)
	e["ancre"] = Vector3(qa.x, _h(qa) + 1.25, qa.y)
	e["treuil"] = true
	e["lache"] = 0.0
	e["t_cable"] = 0.0
	var am: MeshInstance3D = e["ancre_mi"]
	am.global_transform = Transform3D(Basis.IDENTITY, Vector3(qa.x, _h(qa), qa.y))
	am.visible = true


func _lacher(e: Dictionary) -> void:
	e["treuil"] = false
	e["pts"] = PackedVector3Array()
	((e["cable"] as MultiMeshInstance3D).multimesh).visible_instance_count = 0
	(e["ancre_mi"] as MeshInstance3D).visible = false
	(e["fleche"] as Node3D).rotation = Vector3.ZERO


## Câble tendu de la flèche à l'ancrage, droit, posé sur la neige là où le relief dépasse la ligne droite.
func _tendre(e: Dictionary) -> void:
	var piv: Node3D = e["fleche"]
	var a: Vector3 = piv.global_transform * Vector3(0.0, 0.0, -1.9)
	var b: Vector3 = e["ancre"]
	var pts := PackedVector3Array()
	pts.resize(N_SEG + 1)
	for k in range(N_SEG + 1):
		var p: Vector3 = a.lerp(b, float(k) / float(N_SEG))
		var g: float = _h(Vector2(p.x, p.z)) + 0.06
		p.y = maxf(p.y, g)
		pts[k] = p
	e["pts"] = pts
	var mm: MultiMesh = (e["cable"] as MultiMeshInstance3D).multimesh
	for k in range(N_SEG):
		var p0: Vector3 = pts[k]
		var p1: Vector3 = pts[k + 1]
		var axe: Vector3 = p1 - p0
		var lg: float = axe.length()
		if lg < 1e-4:
			mm.set_instance_transform(k, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), p0))
			continue
		var y: Vector3 = axe / lg
		var x: Vector3 = y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
		var z: Vector3 = x.cross(y).normalized()
		mm.set_instance_transform(k, Transform3D(Basis(x * RAYON_CABLE, y * lg, z * RAYON_CABLE), (p0 + p1) * 0.5))
	mm.visible_instance_count = N_SEG


## Distance (m) du point p au câble de treuil le plus proche ; INF sans câble.
func distance_cable(p: Vector3) -> float:
	var best: float = INF
	for e in engins:
		if not bool(e["treuil"]):
			continue
		var pts: PackedVector3Array = e["pts"]
		for k in range(pts.size() - 1):
			var a: Vector3 = pts[k]
			var b: Vector3 = pts[k + 1]
			var ab: Vector3 = b - a
			var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			best = minf(best, p.distance_to(a + ab * t))
	return best


## Distance (m) du point p à la caisse de la dameuse la plus proche (boîte hors tout) ; INF sans dameuse.
func distance_dameuse(p: Vector3) -> float:
	var best: float = INF
	for e in engins:
		var racine: Node3D = e["noeud"]
		var l: Vector3 = racine.global_transform.affine_inverse() * p
		var dx: float = maxf(absf(l.x) - DEMI_LARG, 0.0)
		var dz: float = maxf(absf(l.z) - DEMI_LONG, 0.0)
		var dy: float = maxf(absf(l.y - 1.4) - 1.6, 0.0)
		best = minf(best, Vector3(dx, dy, dz).length())
	return best


func treuil_actif() -> bool:
	for e in engins:
		if bool(e["treuil"]):
			return true
	return false


## Phares réels (SpotLight3D) sur la dameuse la plus proche de la caméra, à moins de 250 m ; les autres n'ont que
## leurs feux émissifs.
func _phares(pc: Vector3) -> void:
	var proche: Dictionary = {}
	var dmin: float = 250.0
	for e in engins:
		var d: float = (e["noeud"] as Node3D).global_position.distance_to(pc)
		if d < dmin:
			dmin = d
			proche = e
	for e in engins:
		var ph: Array = e["phares"]
		var voulu: int = phares_max if e == proche else 0
		while ph.size() < voulu:
			var sp := SpotLight3D.new()
			sp.light_color = Color(1.0, 0.97, 0.90)
			sp.light_energy = 5.0
			sp.spot_range = 70.0
			sp.spot_angle = 34.0
			sp.spot_attenuation = 0.8
			sp.shadow_enabled = false
			sp.light_specular = 0.2
			if ph.is_empty():
				sp.position = Vector3(0.0, 2.95, -1.6)
				sp.rotation = Vector3(deg_to_rad(-14.0), 0.0, 0.0)
			else:
				# feu de travail arrière, sur la fraise
				sp.position = Vector3(0.0, 2.7, 0.3)
				sp.rotation = Vector3(deg_to_rad(-38.0), PI, 0.0)
				sp.spot_range = 22.0
				sp.light_energy = 2.5
			(e["noeud"] as Node3D).add_child(sp)
			ph.append(sp)
		while ph.size() > voulu:
			(ph.pop_back() as Node).queue_free()
