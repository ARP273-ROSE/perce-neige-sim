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
const DEMI_LONG: float = 3.35              # demi-longueur hors tout, lame et fraise comprises
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
## Dameuses lointaines : leurs seuls feux (phares blancs, gyrophare orange), sur tout le domaine.
const N_LOIN: int = 36
const LOIN_MIN: float = 450.0
var _loin: Array = []                       # [piste, abscisse, sens, phase]
var _points_loin: PointsLumineux = null
var _t_loin: float = 0.0
var niveau_feux: float = 1.0                # CycleJour « eclairage » (posé par main)
var _n_forcees: int = 0
## Phares réels sur la plus proche : 0, 1 ou 2 (PerfManager).
var phares_max: int = 2

static var _maillage: ArrayMesh = null
static var _maillage_fleche: ArrayMesh = null
static var _maillage_ancre: ArrayMesh = null
static var _cyl_cable: CylinderMesh = null
static var _mat_cable: StandardMaterial3D = null
static var _son: AudioStreamWAV = null


## Dameuses dessinées en entier autour de la caméra (retour d'essai du 19/11/2026 : « une seule vue sur tout le
## domaine », densité nettement augmentée) ; les autres, sur tout le domaine, ne sont que leurs feux (_lointaines).
static func n_max() -> int:
	if OS.has_feature("web"):
		return 1 if PerfManager.secours_web >= 2 else 2
	return 2 if PerfManager.allege else 4


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
	# dameuses lointaines : les pistes les plus longues, une ou deux chacune, réparties sur tout le domaine
	var longues: Array = []
	for i2 in range(_axes.size()):
		if _long(i2) > 450.0:
			longues.append([_long(i2), i2])
	longues.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var rl := RandomNumberGenerator.new()
	rl.seed = 4242
	for k2 in range(mini(N_LOIN, longues.size() * 2)):
		var ip: int = int(longues[k2 % longues.size()][1])
		_loin.append([ip, rl.randf() * _long(ip), 1.0 if rl.randf() < 0.5 else -1.0, rl.randf()])
	_points_loin = PointsLumineux.new("FeuxDameusesLointaines", 4.5)
	add_child(_points_loin)
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


## Lame : largeur du versoir central, de chaque aile (repliée à 32° vers l'avant), abscisse de son dos.
const LAME_CENTRE: float = 4.0
const LAME_AILE: float = 0.80
const LAME_Z: float = -3.05


## Lattes du versoir : [centre (z, y), longueur, angle autour de X], sur un arc creux vers l'avant (centre à 0,9 m
## devant, du couteau à 0,04 m à la rive à 1,17 m).
static func _versoir() -> Array:
	var c := Vector2(LAME_Z - 0.9, 0.62)
	var l: Array = []
	var n: int = 7
	for k in range(n):
		var f0: float = deg_to_rad(lerpf(-40.0, 38.0, float(k) / n))
		var f1: float = deg_to_rad(lerpf(-40.0, 38.0, float(k + 1) / n))
		var p0: Vector2 = c + 0.9 * Vector2(cos(f0), sin(f0))
		var p1: Vector2 = c + 0.9 * Vector2(cos(f1), sin(f1))
		var d: Vector2 = p1 - p0
		l.append([(p0 + p1) * 0.5, d.length() + 0.02, atan2(d.x, d.y)])
	return l


## Poutre de section carrée de a à b.
static func _poutre(st: SurfaceTool, a: Vector3, b: Vector3, e: float) -> void:
	var d: Vector3 = b - a
	var y: Vector3 = d.normalized()
	var x: Vector3 = (Vector3.UP if absf(y.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).cross(y).normalized()
	var z: Vector3 = x.cross(y)
	var bm := BoxMesh.new()
	bm.size = Vector3(e, d.length(), e)
	st.append_from(bm, 0, Transform3D(Basis(x, y, z), (a + b) * 0.5))


## Train de roulement (retour d'utilisateur du 25/11/2026 : « fais des chenilles qui tournent ») : par côté, une
## bande en boucle autour du barbotin (arrière) et de la poulie (avant), crampons d'acier dessinés par le nuanceur et
## qui défilent à la vitesse d'avance (le brin du bas reste posé sur la neige) ; barbotin, poulie et quatre paires
## de galets tournent dans le nuanceur (centre en UV2, rayon en UV.x). Un maillage pour toutes les dameuses : elles
## roulent toutes à V, en marche avant.
const CH_X: float = 1.78
const CH_LARG: float = 1.30
const CH_R: float = 0.42                   # rayon extérieur de la bande aux extrémités
const CH_Y: float = 0.45
const CH_ZAV: float = -1.95
const CH_ZAR: float = 1.85
const CH_EP: float = 0.08
static var _maillage_train: ArrayMesh = null


static func _boucle_chenille() -> Array:
	# [z, y, nz, ny, u] : brin du bas de l'avant vers l'arrière, barbotin, brin du haut, poulie
	var pts: Array = []
	var u: float = 0.0
	var prev := Vector2.INF
	var seq: Array = []
	seq.append([CH_ZAV, CH_Y - CH_R, 0.0, -1.0])
	seq.append([CH_ZAR, CH_Y - CH_R, 0.0, -1.0])
	for k in range(1, 13):
		var a: float = -PI * 0.5 + PI * k / 12.0
		seq.append([CH_ZAR + CH_R * cos(a), CH_Y + CH_R * sin(a), cos(a), sin(a)])
	seq.append([CH_ZAV, CH_Y + CH_R, 0.0, 1.0])
	for k in range(1, 13):
		var a2: float = PI * 0.5 + PI * k / 12.0
		seq.append([CH_ZAV + CH_R * cos(a2), CH_Y + CH_R * sin(a2), cos(a2), sin(a2)])
	for q in seq:
		var p := Vector2(q[0], q[1])
		if prev != Vector2.INF:
			u += p.distance_to(prev)
		prev = p
		pts.append([q[0], q[1], q[2], q[3], u])
	return pts


static func _mat_train(albedo: Color, chenille: bool) -> ShaderMaterial:
	var sh := Shader.new()
	if chenille:
		sh.code = """shader_type spatial;
render_mode cull_disabled;
uniform float vitesse = 3.6;
void fragment() {
	// crampons : barrettes d'acier tous les 0,30 m sur la bande de caoutchouc, qui défilent (UV.x : m le long de la boucle)
	float k = fract((UV.x - TIME * vitesse) / 0.30);
	float barre = smoothstep(0.0, 0.03, k) * (1.0 - smoothstep(0.42, 0.45, k));
	float bord = step(0.08, UV.y) * step(UV.y, 0.92);
	barre *= bord;
	ALBEDO = mix(vec3(0.035, 0.035, 0.04), vec3(0.42, 0.43, 0.45), barre);
	ROUGHNESS = mix(0.92, 0.45, barre);
	METALLIC = 0.7 * barre;
}
"""
	else:
		sh.code = """shader_type spatial;
uniform float vitesse = 3.6;
uniform vec3 couleur : source_color = vec3(0.1);
uniform float metal = 0.0;
void vertex() {
	// roue de rayon UV.x autour de (z, y) = UV2 : roule vers −Z (marche avant)
	float th = -TIME * vitesse / max(UV.x, 0.05);
	float c = cos(th);
	float s = sin(th);
	vec2 p = vec2(VERTEX.z - UV2.x, VERTEX.y - UV2.y);
	VERTEX.y = UV2.y + p.y * c - p.x * s;
	VERTEX.z = UV2.x + p.y * s + p.x * c;
	vec2 n = vec2(NORMAL.z, NORMAL.y);
	NORMAL.y = n.y * c - n.x * s;
	NORMAL.z = n.y * s + n.x * c;
}
void fragment() {
	ALBEDO = couleur;
	ROUGHNESS = 0.5;
	METALLIC = metal;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("vitesse", V)
	if not chenille:
		m.set_shader_parameter("couleur", albedo)
		m.set_shader_parameter("metal", 0.6 if albedo.r > 0.3 else 0.1)
	return m


## Une roue (dans la surface `acc`) : ses pièces, centre (z, y) et rayon portés par chaque sommet.
static func _roue(acc: Dictionary, st: SurfaceTool, zc: float, yc: float, r: float) -> void:
	st.deindex()
	var a: Array = st.commit_to_arrays()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	# (tableaux compactés : copiés à la lecture, réaffectés après ajout)
	var av: PackedVector3Array = acc["v"]
	var an: PackedVector3Array = acc["n"]
	var au: PackedVector2Array = acc["uv"]
	var au2: PackedVector2Array = acc["uv2"]
	av.append_array(v)
	an.append_array(a[Mesh.ARRAY_NORMAL])
	for i in range(v.size()):
		au.append(Vector2(r, 0.0))
		au2.append(Vector2(zc, yc))
	acc["v"] = av
	acc["n"] = an
	acc["uv"] = au
	acc["uv2"] = au2


static func _train() -> ArrayMesh:
	if _maillage_train != null:
		return _maillage_train
	var am := ArrayMesh.new()
	# bandes : surface extérieure, intérieure et deux flancs, par côté
	var vb := PackedVector3Array()
	var nb := PackedVector3Array()
	var ub := PackedVector2Array()
	var boucle: Array = _boucle_chenille()
	for sd in [-1.0, 1.0]:
		var x0: float = sd * CH_X - CH_LARG * 0.5
		var x1: float = sd * CH_X + CH_LARG * 0.5
		for k in range(boucle.size()):
			var q0: Array = boucle[k]
			var q1: Array = boucle[(k + 1) % boucle.size()]
			var u0: float = q0[4]
			var u1: float = q1[4] if k + 1 < boucle.size() else float(q0[4]) + Vector2(q0[0], q0[1]).distance_to(Vector2(q1[0], q1[1]))
			for face in [0, 1]:
				var ep: float = 0.0 if face == 0 else -CH_EP
				var sg: float = 1.0 if face == 0 else -1.0
				var a0 := Vector3(x0, q0[1] + q0[3] * ep, q0[0] + q0[2] * ep)
				var a1 := Vector3(x1, q0[1] + q0[3] * ep, q0[0] + q0[2] * ep)
				var b0 := Vector3(x0, q1[1] + q1[3] * ep, q1[0] + q1[2] * ep)
				var b1 := Vector3(x1, q1[1] + q1[3] * ep, q1[0] + q1[2] * ep)
				var na := Vector3(0.0, q0[3], q0[2]) * sg
				var nbb := Vector3(0.0, q1[3], q1[2]) * sg
				vb.append_array([a0, b0, a1, a1, b0, b1])
				nb.append_array([na, nbb, na, na, nbb, nbb])
				ub.append_array([Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u0, 1.0), Vector2(u0, 1.0), Vector2(u1, 0.0), Vector2(u1, 1.0)])
			# flancs
			for xs in [x0, x1]:
				var nx := Vector3(signf(xs - sd * CH_X), 0.0, 0.0)
				var o0 := Vector3(xs, q0[1], q0[0])
				var o1 := Vector3(xs, q1[1], q1[0])
				var i0 := Vector3(xs, q0[1] - q0[3] * CH_EP, q0[0] - q0[2] * CH_EP)
				var i1 := Vector3(xs, q1[1] - q1[3] * CH_EP, q1[0] - q1[2] * CH_EP)
				vb.append_array([o0, o1, i0, i0, o1, i1])
				nb.append_array([nx, nx, nx, nx, nx, nx])
				ub.append_array([Vector2(u0, 0.5), Vector2(u1, 0.5), Vector2(u0, 0.5), Vector2(u0, 0.5), Vector2(u1, 0.5), Vector2(u1, 0.5)])
	var ab: Array = []
	ab.resize(Mesh.ARRAY_MAX)
	ab[Mesh.ARRAY_VERTEX] = vb
	ab[Mesh.ARRAY_NORMAL] = nb
	ab[Mesh.ARRAY_TEX_UV] = ub
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ab)
	am.surface_set_material(0, _mat_train(Color.BLACK, true))
	# roues : caoutchouc (gris très sombre) et jantes (acier)
	var accs: Array = []
	for c in range(2):
		accs.append({"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "uv2": PackedVector2Array()})
	var rr: float = CH_R - CH_EP - 0.01
	for sd in [-1.0, 1.0]:
		var xc: float = sd * CH_X
		var roues: Array = [[CH_ZAR, CH_Y, rr, true], [CH_ZAV, CH_Y, rr, false]]
		for zg in [-1.06, -0.35, 0.35, 1.06]:
			roues.append([zg, CH_Y - CH_R + CH_EP + 0.31, 0.30, false])
		for w in roues:
			var zc: float = w[0]
			var yc: float = w[1]
			var r: float = w[2]
			var st_c := SurfaceTool.new()
			st_c.begin(Mesh.PRIMITIVE_TRIANGLES)
			var st_j := SurfaceTool.new()
			st_j.begin(Mesh.PRIMITIVE_TRIANGLES)
			# deux bandages (intérieur, extérieur) sur un moyeu
			for dx in [-0.32, 0.32]:
				_cyl(st_c, r, 0.30, _xf(Vector3(xc + dx, yc, zc), 0.0, 0.0, PI * 0.5), 14)
				_cyl(st_j, r * 0.62, 0.32, _xf(Vector3(xc + dx, yc, zc), 0.0, 0.0, PI * 0.5), 10)
			_cyl(st_j, r * 0.25, CH_LARG + 0.04, _xf(Vector3(xc, yc, zc), 0.0, 0.0, PI * 0.5), 8)
			# rayons sur la face extérieure (on les voit tourner), dents du barbotin
			for kr in range(3):
				var ang: float = TAU * kr / 3.0
				_boite(st_j, Vector3(0.05, r * 1.6, 0.07), Transform3D(Basis(Vector3.RIGHT, ang), Vector3(xc + sd * 0.49, yc, zc)))
			if bool(w[3]):
				for kd in range(12):
					var ad: float = TAU * kd / 12.0
					_boite(st_j, Vector3(0.6, 0.09, 0.07), Transform3D(Basis(Vector3.RIGHT, ad),
						Vector3(xc, yc + cos(ad) * (r + 0.02), zc + sin(ad) * (r + 0.02))))
			_roue(accs[0], st_c, zc, yc, r)
			_roue(accs[1], st_j, zc, yc, r)
	var couleurs: Array = [Color(0.06, 0.06, 0.07), Color(0.45, 0.46, 0.48)]
	for c2 in range(2):
		var ar: Array = []
		ar.resize(Mesh.ARRAY_MAX)
		ar[Mesh.ARRAY_VERTEX] = accs[c2]["v"]
		ar[Mesh.ARRAY_NORMAL] = accs[c2]["n"]
		ar[Mesh.ARRAY_TEX_UV] = accs[c2]["uv"]
		ar[Mesh.ARRAY_TEX_UV2] = accs[c2]["uv2"]
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ar)
		am.surface_set_material(am.get_surface_count() - 1, _mat_train(couleurs[c2], false))
	_maillage_train = am
	return am


static func modele() -> ArrayMesh:
	if _maillage != null:
		return _maillage
	var mats: Dictionary = {
		"caisse": _mat_std(Color(0.86, 0.15, 0.06), 0.32, 0.25),
		"lame": _mat_std(Color(0.06, 0.06, 0.07), 0.85, 0.1),
		"jaune": _mat_std(Color(0.95, 0.72, 0.05), 0.4, 0.15),
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
	mv.emission_energy_multiplier = 0.10
	mv.albedo_color = Color(0.06, 0.08, 0.10)
	mv.roughness = 0.05
	mv.metallic = 0.6
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
	# (chenilles, barbotins, poulies et galets : train de roulement animé, _train())
	# Silhouette d'une dameuse moderne (demande d'utilisateur du 25/11/2026 : « une dameuse moderne rouge, que ce soit
	# joli » ; photos libres de Wikimedia Commons, sans marque ni logo) : châssis noir bas entre les chenilles, nez
	# rouge à calandre noire et phares, poste avancé tout vitré à pare-brise penché vers l'avant, montants noirs, toit
	# rouge débordant à rampe de phares, capot moteur rouge en gradins derrière, ouïes noires, échappement ; lame noire
	# à grille ; fraise et finisseur noirs à l'arrière ; tambour de treuil et bras rouge en arc sur le capot.
	_boite(sts["noir"], Vector3(2.1, 0.55, 4.3), _xf(Vector3(0.0, 0.92, 0.0)))                 # châssis
	_boite(sts["caisse"], Vector3(2.25, 0.62, 0.95), _xf(Vector3(0.0, 1.38, -1.62)))           # nez
	_boite(sts["caisse"], Vector3(2.1, 0.20, 0.30), _xf(Vector3(0.0, 1.62, -2.05), deg_to_rad(-25.0)))
	_boite(sts["noir"], Vector3(1.3, 0.34, 0.04), _xf(Vector3(0.0, 1.30, -2.11)))              # calandre
	for kg in range(6):
		_boite(sts["acier"], Vector3(1.2, 0.02, 0.05), _xf(Vector3(0.0, 1.17 + kg * 0.055, -2.13)))
	_boite(sts["caisse"], Vector3(2.3, 0.55, 3.0), _xf(Vector3(0.0, 1.40, 0.55)))              # caisse basse
	_boite(sts["noir"], Vector3(2.32, 0.10, 4.15), _xf(Vector3(0.0, 1.10, -0.05)))             # liseré bas
	# poste : verrière (côtés et arrière), pare-brise penché, montants, toit
	_boite(sts["vitre"], Vector3(2.0, 1.30, 1.55), _xf(Vector3(0.0, 2.32, -0.55)))
	_boite(sts["vitre"], Vector3(2.0, 1.42, 0.05), _xf(Vector3(0.0, 2.30, -1.38), deg_to_rad(-14.0)))
	for px in [-1.02, 1.02]:
		_boite(sts["noir"], Vector3(0.10, 1.44, 0.10), _xf(Vector3(px, 2.30, -1.38), deg_to_rad(-14.0)))
		_boite(sts["noir"], Vector3(0.10, 1.32, 0.12), _xf(Vector3(px, 2.32, 0.22)))
		_boite(sts["noir"], Vector3(0.06, 1.30, 0.08), _xf(Vector3(px, 2.32, -0.55)))        # montant milieu
		_boite(sts["noir"], Vector3(0.05, 0.36, 0.30), _xf(Vector3(px * 1.12, 2.55, -1.20)))  # rétroviseurs
	_boite(sts["noir"], Vector3(2.06, 0.12, 1.75), _xf(Vector3(0.0, 1.70, -0.58)))             # bas de verrière
	_boite(sts["caisse"], Vector3(2.22, 0.16, 2.0), _xf(Vector3(0.0, 3.03, -0.60)))            # toit
	_boite(sts["caisse"], Vector3(2.10, 0.10, 0.35), _xf(Vector3(0.0, 3.00, -1.70), deg_to_rad(10.0)))  # visière
	_boite(sts["noir"], Vector3(1.7, 0.12, 0.14), _xf(Vector3(0.0, 3.16, -1.45)))              # rampe de phares
	# capot moteur en gradins, ouïes, échappement
	_boite(sts["caisse"], Vector3(2.15, 0.85, 1.75), _xf(Vector3(0.0, 2.08, 1.12)))
	_boite(sts["caisse"], Vector3(1.85, 0.22, 1.45), _xf(Vector3(0.0, 2.58, 1.20)))
	_boite(sts["caisse"], Vector3(2.15, 0.30, 0.30), _xf(Vector3(0.0, 1.78, 2.05), deg_to_rad(30.0)))
	for sdv in [-1.0, 1.0]:
		for kv in range(5):
			_boite(sts["noir"], Vector3(0.03, 0.05, 0.9), _xf(Vector3(sdv * 1.08, 1.90 + kv * 0.09, 1.20)))
	_cyl(sts["noir"], 0.07, 0.75, _xf(Vector3(0.72, 3.0, 0.62)), 8)          # échappement
	# lame à l'avant (retour d'utilisateur du 25/11/2026 : « le râteau devant est pas bien fait ») : versoir bombé (creux
	# vers l'avant) en lattes sur un arc, deux ailes repliées vers l'avant, couteau d'acier en bas, rive rouge en haut,
	# raidisseurs au dos ; cadre de poussée (deux bras) et deux vérins de levage depuis le châssis
	var lattes: Array = _versoir()
	for lt in lattes:
		_boite(sts["lame"], Vector3(LAME_CENTRE, lt[1], 0.06), _xf(Vector3(0.0, lt[0].y, lt[0].x), lt[2]))
	for sd2 in [-1.0, 1.0]:
		var charn := Transform3D(Basis(Vector3.UP, sd2 * deg_to_rad(32.0)), Vector3(sd2 * LAME_CENTRE * 0.5, 0.0, LAME_Z))
		for lt in lattes:
			var loc := _xf(Vector3(sd2 * LAME_AILE * 0.5, lt[0].y, lt[0].x - LAME_Z), lt[2])
			_boite(sts["lame"], Vector3(LAME_AILE, lt[1], 0.06), charn * loc)
		# couteau et rive de l'aile
		_boite(sts["acier"], Vector3(LAME_AILE, 0.07, 0.10), charn * _xf(Vector3(sd2 * LAME_AILE * 0.5, 0.06, -0.20)))
		_boite(sts["noir"], Vector3(LAME_AILE, 0.08, 0.16), charn * _xf(Vector3(sd2 * LAME_AILE * 0.5, 1.17, -0.18)))
		# bras de poussée, du châssis au dos de la lame
		var a0 := Vector3(sd2 * 0.85, 0.78, -1.75)
		var a1 := Vector3(sd2 * 1.05, 0.42, LAME_Z + 0.22)
		_poutre(sts["noir"], a0, a1, 0.16)
		# vérin de levage : corps noir, tige d'acier
		var v0 := Vector3(sd2 * 0.55, 1.45, -1.95)
		var v1 := Vector3(sd2 * 0.70, 0.98, LAME_Z + 0.20)
		_poutre(sts["noir"], v0, v0.lerp(v1, 0.6), 0.11)
		_poutre(sts["acier"], v0.lerp(v1, 0.55), v1, 0.06)
	_boite(sts["acier"], Vector3(LAME_CENTRE, 0.07, 0.10), _xf(Vector3(0.0, 0.06, LAME_Z - 0.20)))
	_boite(sts["noir"], Vector3(LAME_CENTRE, 0.08, 0.16), _xf(Vector3(0.0, 1.17, LAME_Z - 0.18)))
	# grille du haut de la lame (photos : moitié haute ajourée) : barreaux verticaux devant le versoir
	for kb in range(-16, 17):
		_boite(sts["noir"], Vector3(0.035, 0.50, 0.05), _xf(Vector3(kb * 0.12, 0.92, LAME_Z - 0.17)))
	_boite(sts["noir"], Vector3(LAME_CENTRE, 0.04, 0.06), _xf(Vector3(0.0, 0.68, LAME_Z - 0.10)))
	for kx in range(-3, 4):
		_boite(sts["noir"], Vector3(0.07, 0.70, 0.12), _xf(Vector3(kx * 0.62, 0.55, LAME_Z + 0.08)))
	_boite(sts["noir"], Vector3(LAME_CENTRE * 0.8, 0.12, 0.12), _xf(Vector3(0.0, 0.55, LAME_Z + 0.16)))
	# fraise, capot de fraise et peigne (velours côtelé)
	_cyl(sts["noir"], 0.30, 4.2, _xf(Vector3(0.0, 0.34, 2.75), 0.0, 0.0, PI * 0.5), 10)
	# capot de la fraise jaune, joues jaunes (retour d'utilisateur du 25/11/2026 : « la fraise à l'arrière, normalement
	# il y a une partie jaune »)
	_boite(sts["jaune"], Vector3(4.3, 0.10, 1.05), _xf(Vector3(0.0, 0.72, 2.75), deg_to_rad(6.0)))
	_boite(sts["jaune"], Vector3(4.3, 0.32, 0.08), _xf(Vector3(0.0, 0.58, 3.27), deg_to_rad(-20.0)))
	_boite(sts["jaune"], Vector3(0.12, 0.55, 1.0), _xf(Vector3(-2.12, 0.45, 2.75)))
	_boite(sts["jaune"], Vector3(0.12, 0.55, 1.0), _xf(Vector3(2.12, 0.45, 2.75)))
	_boite(sts["lame"], Vector3(4.2, 0.03, 0.85), _xf(Vector3(0.0, 0.10, 3.55), deg_to_rad(10.0)))
	_boite(sts["noir"], Vector3(0.6, 0.18, 0.7), _xf(Vector3(0.0, 0.82, 2.2)))           # attelage
	# phares : rampe sur le toit, feux de châssis, feux arrière
	_boite(sts["phare"], Vector3(1.5, 0.07, 0.05), _xf(Vector3(0.0, 3.16, -1.53)))
	for sd3 in [-0.85, 0.85]:
		_boite(sts["phare"], Vector3(0.36, 0.14, 0.05), _xf(Vector3(sd3, 1.50, -2.12)))
		_boite(sts["phare"], Vector3(0.22, 0.12, 0.05), _xf(Vector3(sd3 * 1.1, 2.85, 0.32)))
	# gyrophares
	for sd4 in [-0.72, 0.72]:
		_cyl(sts["gyro"], 0.085, 0.17, _xf(Vector3(sd4, 3.20, -0.10)), 10)
	# treuil : tambour et sa platine sur le capot
	_boite(sts["noir"], Vector3(1.1, 0.18, 0.62), _xf(Vector3(0.0, 2.75, 1.45)))
	_cyl(sts["noir"], 0.30, 0.95, _xf(Vector3(0.0, 3.0, 1.45), 0.0, 0.0, PI * 0.5), 12)
	var am := ArrayMesh.new()
	for k2 in mats:
		var st2: SurfaceTool = sts[k2]
		st2.generate_normals()
		var n0: int = am.get_surface_count()
		st2.commit(am)
		# (matière sans pièce : pas de surface — sa matière allait sur la précédente, la lame peinte en blanc)
		if am.get_surface_count() > n0:
			am.surface_set_material(am.get_surface_count() - 1, mats[k2])
	_maillage = am
	# flèche du treuil (tourne vers l'ancrage) : bras le long de −Z, extrémité à 1,9 m
	var stf := SurfaceTool.new()
	stf.begin(Mesh.PRIMITIVE_TRIANGLES)
	# bras en arc (photos : col de cygne rouge), bout à 1,9 m vers l'ancrage, poulie au bout
	var arc: Array = [Vector3(0, 0, 0), Vector3(0, 0.65, -0.45), Vector3(0, 0.80, -1.10), Vector3(0, 0.45, -1.70), Vector3(0, 0, -1.9)]
	for ka in range(arc.size() - 1):
		_poutre(stf, arc[ka], arc[ka + 1], 0.20)
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
	var tr := MeshInstance3D.new()
	tr.name = "Train"
	tr.mesh = _train()
	tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	tr.layers = 1 | Cabin.LAYER_VOIE
	racine.add_child(tr)
	var piv := Node3D.new()
	piv.name = "Fleche"
	piv.position = Vector3(0.0, 3.05, 1.45)
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
	_maj_lointaines(delta, pc)


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
				sp.position = Vector3(0.0, 3.12, -1.6)
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


## Feux des dameuses lointaines : elles avancent sur leur piste (demi-tour au bout) ; seuls les feux sont dessinés,
## hors des 450 m autour de la caméra (là, les vraies dameuses).
func _maj_lointaines(dt: float, pc: Vector3) -> void:
	if _points_loin == null:
		return
	var on: bool = actives and niveau_feux > 0.02
	if not on:
		_points_loin.regler_niveau(0.0)
		return
	for e in _loin:
		var i: int = e[0]
		var s: float = float(e[1]) + float(e[2]) * V * dt
		if s <= 2.0 or s >= _long(i) - 2.0:
			e[2] = -float(e[2])
			s = clampf(s, 2.0, _long(i) - 2.0)
		e[1] = s
	_t_loin -= dt
	if _t_loin > 0.0:
		return
	_t_loin = 0.2
	var pts := PackedVector3Array()
	var cs := PackedColorArray()
	for e2 in _loin:
		var i2: int = e2[0]
		var s2: float = e2[1]
		var q: Vector2 = _point(i2, s2)
		if Vector2(pc.x, pc.z).distance_to(q) < LOIN_MIN:
			continue
		var q2: Vector2 = _point(i2, clampf(s2 + float(e2[2]) * 3.0, 0.0, _long(i2)))
		var tg: Vector2 = (q2 - q).normalized() if q2.distance_to(q) > 1e-3 else Vector2(0, -1)
		var h: float = _h(q)
		pts.append(Vector3(q.x + tg.x * 2.0, h + 2.9, q.y + tg.y * 2.0))
		cs.append(Color(1.6, 1.55, 1.4, 0.0))
		pts.append(Vector3(q.x, h + 3.0, q.y))
		cs.append(Color(1.8, 0.75, 0.08, maxf(float(e2[3]), 0.01)))
	_points_loin.poser(pts, cs)
	_points_loin.regler_niveau(niveau_feux)


func n_lointaines_visibles() -> int:
	return _points_loin.multimesh.visible_instance_count / 2 if _points_loin != null and _points_loin.visible else 0
