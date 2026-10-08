class_name SkieurMesh
extends RefCounted
## Skieurs réalistes (demande de Kevin du 06/10/2026 : « redesign
## complètement les passagers pour qu'ils soient bien réalistes, mes
## skieurs »). Maillages procéduraux : formes organiques (tubes à section
## elliptique, ellipsoïdes), proportions d'un adulte de 1,75 m, tenue de
## ski complète. Repère : origine aux pieds (ou au sol sous l'assise),
## regard vers −Z, X à droite, Y en haut.
##
## Chaque sommet porte en UV2.x le numéro de sa PIÈCE (peau, veste,
## pantalon, chaussure…) : skieur.gdshader choisit les couleurs par
## passager (INSTANCE_CUSTOM = graines aléatoires), de sorte que tous les
## passagers d'un même maillage sont habillés différemment.
##
## Deux niveaux de détail dans le même maillage (LOD Godot, mêmes
## sommets) : complet de près, allégé au loin.

# --- Pièces (UV2.x) ---------------------------------------------------------
const P_PEAU: int = 0
const P_VESTE: int = 1
const P_VESTE2: int = 2        # empiècement (épaules), poignets, col
const P_PANTALON: int = 3
const P_CHAUSSURE: int = 4
const P_BOUCLE: int = 5        # boucles, carres (métal)
const P_SEMELLE: int = 6       # semelles, strap, fermeture éclair (noir)
const P_GANT: int = 7
const P_CASQUE: int = 8
const P_ECRAN: int = 9         # écran du masque / verres (miroir)
const P_MASQUE: int = 10       # monture et sangle
const P_SAC: int = 11
const P_BONNET: int = 12
const P_CHEVEUX: int = 13
const P_TOUR_COU: int = 14     # tour de cou (ou peau, selon le passager)
const P_SKI: int = 15          # dessus des skis
const P_SKI_MOTIF: int = 16
const P_SKI_SEMELLE: int = 17
const P_FIXATION: int = 18
const P_BATON: int = 19
const P_POIGNEE: int = 20
const P_SURF: int = 21
const P_TELEPHONE: int = 22
const P_POMPON: int = 23

const POSES: Array[String] = ["skis", "libre", "telephone", "enfant", "assis"]
# torse de la veste : [t de l'ourlet (0) au haut (1), demi-largeur, demi-
# épaisseur, décalage avant/arrière]
const PROFIL_TORSE: Array = [[0.0, 0.196, 0.142, -0.002], [0.12, 0.188, 0.136, 0.0], [0.30, 0.180, 0.130, 0.0],
	[0.50, 0.188, 0.134, -0.008], [0.68, 0.198, 0.140, -0.016], [0.80, 0.198, 0.130, -0.010],
	[0.88, 0.186, 0.118, -0.002], [0.94, 0.156, 0.106, 0.004], [1.0, 0.090, 0.084, 0.010]]


## Surface du torse (veste) à la hauteur relative t et au décalage latéral
## x : profondeur z de la face avant (sg = −1) ou arrière (sg = +1).
static func _z_torse(t: float, x: float, sg: float, k: float) -> float:
	var a: Array = PROFIL_TORSE[0]
	var b: Array = PROFIL_TORSE[PROFIL_TORSE.size() - 1]
	for i in range(PROFIL_TORSE.size() - 1):
		if t >= float(PROFIL_TORSE[i][0]) and t <= float(PROFIL_TORSE[i + 1][0]):
			a = PROFIL_TORSE[i]
			b = PROFIL_TORSE[i + 1]
			break
	var u: float = clampf((t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-6), 0.0, 1.0)
	var rx: float = lerpf(float(a[1]), float(b[1]), u) * k
	var rz: float = lerpf(float(a[2]), float(b[2]), u) * k
	var dz: float = lerpf(float(a[3]), float(b[3]), u) * k
	var q: float = clampf(x / rx, -0.98, 0.98)
	return dz + sg * rz * sqrt(1.0 - q * q)
# matériel tenu à droite (repère du passager) : main droite sur les skis
const ANCRE_SKIS: Vector3 = Vector3(0.34, 0.0, -0.03)
const ANCRE_BATONS: Vector3 = Vector3(0.44, 0.0, 0.06)
const ANCRE_SURF: Vector3 = Vector3(0.37, 0.0, -0.02)
const ANCRE_SKIS_ASSIS: Vector3 = Vector3(0.0, 0.0, -0.62)

const _AVANT_HORAIRE: bool = true   # convention Godot (cf. RollerMesh)


# --- Constructeur de maillage --------------------------------------------------

class Bati extends RefCounted:
	var v: PackedVector3Array = PackedVector3Array()
	var n: PackedVector3Array = PackedVector3Array()
	var u2: PackedVector2Array = PackedVector2Array()
	var i_haut: PackedInt32Array = PackedInt32Array()
	var i_bas: PackedInt32Array = PackedInt32Array()
	var lod: int = 0          # 0 : détail (i_haut), 1 : allégé (i_bas), 2 : les deux

	func pt(p: Vector3, nn: Vector3, part: int) -> int:
		v.append(p)
		n.append(nn.normalized() if nn.length() > 1e-9 else Vector3.UP)
		u2.append(Vector2(float(part), 0.0))
		return v.size() - 1

	func tri(a: int, b: int, c: int) -> void:
		var nr: Vector3 = n[a] + n[b] + n[c]
		var g: float = (v[b] - v[a]).cross(v[c] - v[a]).dot(nr)
		var horaire: bool = g < 0.0
		if horaire != SkieurMesh._AVANT_HORAIRE:
			var t: int = b
			b = c
			c = t
		if lod == 0 or lod == 2:
			i_haut.append_array([a, b, c])
		if lod == 1 or lod == 2:
			i_bas.append_array([a, b, c])

	func quad(a: int, b: int, c: int, d: int) -> void:
		tri(a, b, c)
		tri(a, c, d)

	## Grille (lignes × colonnes fermées en anneau si `anneau`).
	func grille(g: Array, anneau: bool) -> void:
		for r in range(g.size() - 1):
			var l0: Array = g[r]
			var l1: Array = g[r + 1]
			var nc: int = l0.size()
			var lim: int = nc if anneau else nc - 1
			for c in range(lim):
				var c1: int = (c + 1) % nc
				quad(l0[c], l1[c], l1[c1], l0[c1])

	func commit(mat: Material) -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TEX_UV2] = u2
		arrays[Mesh.ARRAY_INDEX] = i_haut
		var lods: Dictionary = {}
		if i_bas.size() > 0:
			lods[0.012] = i_bas      # ~1 cm d'écart : au-delà de quelques mètres
		var m: ArrayMesh = ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
		m.surface_set_material(0, mat)
		return m


# --- Primitives (émises deux fois : détail, puis allégé) ------------------------

static func _ellipsoide(b: Bati, c: Vector3, r: Vector3, rot: Basis, part: int,
		th0: float = 0.0, th1: float = PI) -> void:
	for niveau in [0, 1]:
		b.lod = niveau
		var nu: int = 14 if niveau == 0 else 7
		var nv: int = 9 if niveau == 0 else 4
		var g: Array = []
		for j in range(nv + 1):
			var th: float = lerpf(th0, th1, float(j) / float(nv))
			var ligne: Array = []
			for i in range(nu):
				var ph: float = TAU * float(i) / float(nu)
				var d: Vector3 = Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
				var p: Vector3 = c + rot * Vector3(d.x * r.x, d.y * r.y, d.z * r.z)
				var nn: Vector3 = rot * Vector3(d.x / r.x, d.y / r.y, d.z / r.z)
				ligne.append(b.pt(p, nn, part))
			g.append(ligne)
		b.grille(g, true)


## Tube à section elliptique le long d'une polyligne (membres, torse) :
## rx le long de `lat` (latéral), rz perpendiculaire. Bouts fermés au besoin.
static func _tube(b: Bati, pts: Array, rx: Array, rz: Array, part: int, lat: Vector3 = Vector3.RIGHT,
		bout0: bool = false, bout1: bool = false, parts: Array = []) -> void:
	for niveau in [0, 1]:
		b.lod = niveau
		var ns: int = 14 if niveau == 0 else 6
		var g: Array = []
		var axes: Array = []
		for k in range(pts.size()):
			var p0: Vector3 = pts[maxi(k - 1, 0)]
			var p1: Vector3 = pts[mini(k + 1, pts.size() - 1)]
			var t: Vector3 = (p1 - p0).normalized()
			var x: Vector3 = (lat - t * lat.dot(t)).normalized()
			if x.length() < 0.5:
				x = Vector3.FORWARD.cross(t).normalized()
			var z: Vector3 = t.cross(x).normalized()
			axes.append([x, z, t])
			var pk: int = parts[k] if k < parts.size() else part
			var pk_av: int = parts[k - 1] if (k > 0 and k - 1 < parts.size()) else pk
			# changement de pièce : l'anneau est dédoublé (couture nette)
			var passes: Array = [pk_av, pk] if pk_av != pk else [pk]
			for pp in passes:
				var ligne: Array = []
				for i in range(ns):
					var ph: float = TAU * float(i) / float(ns)
					var e: Vector3 = x * (cos(ph) * float(rx[k])) + z * (sin(ph) * float(rz[k]))
					var nn: Vector3 = x * (cos(ph) / float(rx[k])) + z * (sin(ph) / float(rz[k]))
					ligne.append(b.pt((pts[k] as Vector3) + e, nn, pp))
				g.append(ligne)
		# lignes d'un même anneau dédoublé : pas de facette entre elles
		for r in range(g.size() - 1):
			var l0: Array = g[r]
			var l1: Array = g[r + 1]
			if b.v[l0[0]].distance_to(b.v[l1[0]]) < 1e-7 and b.v[l0[1]].distance_to(b.v[l1[1]]) < 1e-7:
				continue
			var nc: int = l0.size()
			for c in range(nc):
				b.quad(l0[c], l1[c], l1[(c + 1) % nc], l0[(c + 1) % nc])
		for fin in [0, 1]:
			if (fin == 0 and not bout0) or (fin == 1 and not bout1):
				continue
			var k2: int = 0 if fin == 0 else pts.size() - 1
			var t2: Vector3 = (axes[k2] as Array)[2]
			var nn2: Vector3 = -t2 if fin == 0 else t2
			var pk2: int = parts[k2] if k2 < parts.size() else part
			var centre: int = b.pt(pts[k2], nn2, pk2)
			var bord: Array = []
			for idx in (g[0 if fin == 0 else g.size() - 1] as Array):
				bord.append(b.pt(b.v[idx], nn2, pk2))
			for i in range(bord.size()):
				b.tri(centre, bord[i], bord[(i + 1) % bord.size()])
	b.lod = 0


static func _boite(b: Bati, c: Vector3, h: Vector3, rot: Basis, part: int, deux_niveaux: bool = true) -> void:
	b.lod = 2 if deux_niveaux else 0
	var ax: Array = [rot.x * h.x, rot.y * h.y, rot.z * h.z]
	var nrm: Array = [rot.x, rot.y, rot.z]
	for k in range(3):
		var u: Vector3 = ax[k]
		var vv: Vector3 = ax[(k + 1) % 3]
		var w: Vector3 = ax[(k + 2) % 3]
		for sg in [-1.0, 1.0]:
			var f: Vector3 = c + u * sg
			var nn: Vector3 = (nrm[k] as Vector3) * sg
			b.quad(b.pt(f - vv - w, nn, part), b.pt(f + vv - w, nn, part),
				b.pt(f + vv + w, nn, part), b.pt(f - vv + w, nn, part))
	b.lod = 0


## Bande cylindrique d'axe vertical (masque, sangle, lunettes) : rayon R
## autour de `c`, angles [a0, a1] comptés depuis l'avant (−Z), hauteur h.
static func _bande(b: Bati, c: Vector3, rx: float, rz: float, a0: float, a1: float, h: float,
		part: int, rot: Basis = Basis.IDENTITY, bombe: float = 0.0) -> void:
	for niveau in [0, 1]:
		b.lod = niveau
		var na: int = 16 if niveau == 0 else 6
		var g: Array = []
		for j in range(3):
			var y: float = lerpf(-h * 0.5, h * 0.5, float(j) / 2.0)
			var ligne: Array = []
			for i in range(na + 1):
				var a: float = lerpf(a0, a1, float(i) / float(na))
				var gonfle: float = 1.0 + bombe * (1.0 - absf(y) / (h * 0.5))
				var d: Vector3 = Vector3(sin(a), 0.0, -cos(a))
				var p: Vector3 = c + rot * Vector3(d.x * rx * gonfle, y, d.z * rz * gonfle)
				var nn: Vector3 = rot * Vector3(d.x / rx, 0.0, d.z / rz)
				ligne.append(b.pt(p, nn, part))
			g.append(ligne)
		b.grille(g, false)
	b.lod = 0


# --- Squelette par pose -----------------------------------------------------

## Points clés d'une pose (repère du passager). `k` : échelle du corps,
## `kt` : échelle de la tête (un enfant a la tête proportionnellement grosse).
static func _squelette(pose: String) -> Dictionary:
	var s: Dictionary = {}
	var k: float = 0.70 if pose == "enfant" else 1.0
	s.k = k
	s.kt = 0.86 if pose == "enfant" else 1.0
	if pose == "assis":
		for sx in [-1.0, 1.0]:
			var c: String = "d" if sx > 0.0 else "g"
			s["hanche_" + c] = Vector3(sx * 0.095, 0.55, 0.02)
			s["genou_" + c] = Vector3(sx * 0.105, 0.54, -0.40)
			s["cheville_" + c] = Vector3(sx * 0.11, 0.11, -0.43)
			s["epaule_" + c] = Vector3(sx * 0.190, 1.035, 0.03)
			s["coude_" + c] = Vector3(sx * 0.245, 0.80, -0.05)
			s["poignet_" + c] = Vector3(sx * 0.20, 0.63, -0.27)
			s["main_" + c] = Vector3(sx * 0.17, 0.61, -0.36)
		s.bassin = Vector3(0.0, 0.56, 0.03)
		s.ourlet = 0.52
		s.haut_torse = 1.11
		s.tete = Vector3(0.0, 1.265, 0.0)
		s.tangage = 0.0
		return s
	for sx in [-1.0, 1.0]:
		var c2: String = "d" if sx > 0.0 else "g"
		s["hanche_" + c2] = Vector3(sx * 0.09, 0.90, 0.0) * k
		s["genou_" + c2] = Vector3(sx * 0.10, 0.50, -0.025) * k
		s["cheville_" + c2] = Vector3(sx * 0.10, 0.11, 0.03) * k
		s["epaule_" + c2] = Vector3(sx * 0.190, 1.405, 0.01) * k
		s["coude_" + c2] = Vector3(sx * 0.228, 1.14, 0.045) * k
		s["poignet_" + c2] = Vector3(sx * 0.238, 0.905, 0.0) * k
		s["main_" + c2] = Vector3(sx * 0.236, 0.81, -0.02) * k
	s.bassin = Vector3(0.0, 0.93, 0.01) * k
	s.ourlet = 0.84 * k
	s.haut_torse = 1.49 * k
	s.tete = Vector3(0.0, 1.640, 0.0) * k
	s.tangage = 0.0
	match pose:
		"skis":
			# main droite sur les skis tenus debout à sa droite
			s.coude_d = Vector3(0.285, 1.17, 0.03)
			s.poignet_d = Vector3(0.305, 1.05, -0.03)
			s.main_d = Vector3(0.325, 1.02, -0.06)
		"telephone":
			s.coude_d = Vector3(0.21, 1.13, -0.04)
			s.poignet_d = Vector3(0.08, 1.16, -0.21)
			s.main_d = Vector3(0.035, 1.185, -0.26)
			s.coude_g = Vector3(-0.21, 1.12, -0.03)
			s.poignet_g = Vector3(-0.075, 1.15, -0.20)
			s.main_g = Vector3(-0.03, 1.175, -0.255)
			s.tangage = 0.42
	return s


# --- Le skieur ----------------------------------------------------------------

static func materiau() -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://scripts/skieur.gdshader")
	return mat


## Passager complet, sans son sac ni son matériel (MultiMesh séparés).
## `coiffe` : "casque" (masque de ski) ou "bonnet" (lunettes, cheveux).
static func passager(pose: String, coiffe: String, mat: Material) -> ArrayMesh:
	return passager_squelette(_squelette(pose), pose, coiffe, mat)


## Squelette d'une pose, à modifier avant passager_squelette() (le skieur
## jouable : images de la marche, postures de ski).
static func squelette(pose: String) -> Dictionary:
	return _squelette(pose)


## Posture de glisse (skieur jouable chaussé, fantôme) : genoux fléchis,
## buste plus bas, bras en avant, mains à hauteur des hanches pour tenir les
## bâtons. Repère : avant = −z ; le dessous des chaussures à y = 0.
static func squelette_glisse() -> Dictionary:
	var s: Dictionary = _squelette("libre")
	var bas: float = 0.10
	for k in ["bassin", "tete", "epaule_g", "epaule_d"]:
		s[k] = (s[k] as Vector3) + Vector3(0.0, -bas, 0.04)
	s.ourlet = float(s.ourlet) - bas
	s.haut_torse = float(s.haut_torse) - bas
	for c in ["g", "d"]:
		var sx: float = -1.0 if c == "g" else 1.0
		s["hanche_" + c] = Vector3(sx * 0.09, 0.80, 0.06)
		s["genou_" + c] = Vector3(sx * 0.10, 0.47, -0.13)
		s["coude_" + c] = Vector3(sx * 0.25, 1.06, -0.10)
		s["poignet_" + c] = Vector3(sx * 0.27, 0.93, -0.25)
		s["main_" + c] = Vector3(sx * 0.27, 0.90, -0.31)
	return s


## Schuss (Kevin, 07/10/2026 : « ça serait bien que le skieur se mette
## effectivement en mode schuss ou chasse-neige ») : recroquevillé, bassin
## 30 cm plus bas, genoux pliés en avant, buste penché, mains devant.
static func squelette_schuss() -> Dictionary:
	var s: Dictionary = _squelette("libre")
	var bas: float = 0.32
	for k in ["bassin", "epaule_g", "epaule_d"]:
		s[k] = (s[k] as Vector3) + Vector3(0.0, -bas, -0.12)
	# (l'avant est en −z : Kevin, 08/10/2026, « la tête va en arrière au lieu
	# d'en avant »)
	s.tete = Vector3(0.0, 1.64 - bas - 0.10, -0.30)
	s.ourlet = float(s.ourlet) - bas
	s.haut_torse = float(s.haut_torse) - bas
	s.tangage = 0.75
	for c in ["g", "d"]:
		var sx: float = -1.0 if c == "g" else 1.0
		s["hanche_" + c] = Vector3(sx * 0.09, 0.60, 0.10)
		s["genou_" + c] = Vector3(sx * 0.10, 0.40, -0.26)
		s["coude_" + c] = Vector3(sx * 0.20, 0.82, -0.18)
		s["poignet_" + c] = Vector3(sx * 0.16, 0.72, -0.40)
		s["main_" + c] = Vector3(sx * 0.15, 0.70, -0.46)
	return s


## Chasse-neige : jambes écartées, genoux rentrés, buste droit, bâtons
## derrière.
static func squelette_chasse() -> Dictionary:
	var s: Dictionary = squelette_glisse()
	for c in ["g", "d"]:
		var sx: float = -1.0 if c == "g" else 1.0
		s["hanche_" + c] = Vector3(sx * 0.11, 0.80, 0.04)
		s["genou_" + c] = Vector3(sx * 0.14, 0.48, -0.08)
		s["cheville_" + c] = Vector3(sx * 0.17, 0.11, 0.03)
		s["coude_" + c] = Vector3(sx * 0.27, 1.02, 0.02)
		s["poignet_" + c] = Vector3(sx * 0.31, 0.88, -0.10)
		s["main_" + c] = Vector3(sx * 0.32, 0.84, -0.15)
	return s


## Passager sur un squelette donné (cf. squelette()).
static func passager_squelette(s: Dictionary, pose: String, coiffe: String, mat: Material) -> ArrayMesh:
	var b: Bati = Bati.new()
	var k: float = s.k
	var assis: bool = pose == "assis"
	# -- jambes : chaussures de ski, pantalon bouffant par-dessus
	for c in ["g", "d"]:
		var sx: float = -1.0 if c == "g" else 1.0
		var ch: Vector3 = s["cheville_" + c]
		var ge: Vector3 = s["genou_" + c]
		var ha: Vector3 = s["hanche_" + c]
		_chaussure(b, ch, sx, k)
		var bas: Vector3 = ch + Vector3(0.0, 0.13 * k, -0.01 * k)
		var mi_tibia: Vector3 = bas.lerp(ge, 0.5)
		var mi_cuisse: Vector3 = ge.lerp(ha, 0.5) + Vector3(0.0, 0.0, -0.01 * k)
		_tube(b, [bas, bas + (ge - bas).normalized() * 0.06 * k, mi_tibia, ge, mi_cuisse, ha],
			[0.090 * k, 0.084 * k, 0.074 * k, 0.073 * k, 0.086 * k, 0.082 * k],
			[0.094 * k, 0.086 * k, 0.078 * k, 0.078 * k, 0.088 * k, 0.084 * k],
			P_PANTALON, Vector3.RIGHT, true, false)
	_ellipsoide(b, s.bassin + Vector3(0.0, 0.0, -0.008) * k, Vector3(0.165, 0.11, 0.112) * k,
		Basis.IDENTITY, P_PANTALON)
	# -- torse : veste (bas) et empiècement (haut), col montant
	var y0: float = s.ourlet
	var y1: float = s.haut_torse
	var z_dos: float = 0.02 * k if assis else 0.0
	var prof: Array = PROFIL_TORSE
	var pts: Array = []
	var rxs: Array = []
	var rzs: Array = []
	var parts: Array = []
	for e in prof:
		var y: float = lerpf(y0, y1, float(e[0]))
		pts.append(Vector3(0.0, y, float(e[3]) * k + z_dos))
		rxs.append(float(e[1]) * k)
		rzs.append(float(e[2]) * k)
		parts.append(P_VESTE if float(e[0]) < 0.66 else P_VESTE2)
	_tube(b, pts, rxs, rzs, P_VESTE, Vector3.RIGHT, true, false, parts)
	# fermeture éclair et poches (fines bandes sombres sur le devant)
	var zip_z: float = -0.142 * k + z_dos
	_boite(b, Vector3(0.0, lerpf(y0, y1, 0.48), zip_z), Vector3(0.006 * k, (y1 - y0) * 0.46, 0.004),
		Basis.IDENTITY, P_SEMELLE, false)
	for sx2 in [-1.0, 1.0]:
		_boite(b, Vector3(sx2 * 0.11 * k, lerpf(y0, y1, 0.22), zip_z + 0.012 * k),
			Vector3(0.05 * k, 0.004, 0.004), Basis(Vector3.FORWARD, sx2 * 0.5), P_SEMELLE, false)
	var tete: Vector3 = s.tete
	var col_bas: Vector3 = Vector3(0.0, y1 - 0.03 * k, 0.008 * k + z_dos)
	var col_haut: Vector3 = Vector3(0.0, tete.y - 0.085 * s.kt, 0.004 * k + z_dos)
	_tube(b, [col_bas, col_haut], [0.078 * k, 0.074 * k], [0.075 * k, 0.072 * k], P_VESTE2,
		Vector3.RIGHT, false, false)
	# -- bras : manches bouffantes, poignets, gants à manchette
	for c3 in ["g", "d"]:
		var sxa: float = -1.0 if c3 == "g" else 1.0
		var ep: Vector3 = s["epaule_" + c3]
		var co: Vector3 = s["coude_" + c3]
		var po: Vector3 = s["poignet_" + c3]
		var ma: Vector3 = s["main_" + c3]
		_ellipsoide(b, ep + Vector3(-sxa * 0.014, -0.016, 0.0) * k, Vector3(0.066, 0.060, 0.072) * k,
			Basis.IDENTITY, P_VESTE)
		var lat_bras: Vector3 = Vector3(0.0, 0.0, 1.0).cross(co - ep).normalized()
		if lat_bras.length() < 0.5:
			lat_bras = Vector3.RIGHT
		var dir_av: Vector3 = (po - co).normalized()
		var manchette: Vector3 = po - dir_av * 0.03 * k
		_tube(b, [ep, ep.lerp(co, 0.5), co, co.lerp(manchette, 0.55), manchette, po],
			[0.068 * k, 0.064 * k, 0.059 * k, 0.056 * k, 0.054 * k, 0.050 * k],
			[0.068 * k, 0.064 * k, 0.060 * k, 0.056 * k, 0.054 * k, 0.050 * k],
			P_VESTE, lat_bras, false, false,
			[P_VESTE, P_VESTE, P_VESTE, P_VESTE, P_VESTE2, P_VESTE2])
		_gant(b, po, ma, sxa, k)
	# -- tête
	var tang: Basis = Basis(Vector3.RIGHT, -float(s.tangage))
	var kt: float = s.kt
	var pivot: Vector3 = Vector3(0.0, tete.y - 0.10 * kt, tete.z)
	var cou_bas: Vector3 = Vector3(0.0, y1 - 0.02 * k, 0.006 * k + z_dos)
	_tube(b, [cou_bas, pivot + tang * Vector3(0.0, 0.05 * kt, 0.0)], [0.050 * kt, 0.048 * kt],
		[0.052 * kt, 0.050 * kt], P_TOUR_COU)
	var T: Callable = func(p: Vector3) -> Vector3: return pivot + tang * ((p - pivot))
	_ellipsoide(b, T.call(tete + Vector3(0.0, 0.0, 0.005) * kt), Vector3(0.080, 0.103, 0.098) * kt, tang, P_PEAU)
	_ellipsoide(b, T.call(tete + Vector3(0.0, -0.045, -0.030) * kt), Vector3(0.066, 0.066, 0.066) * kt, tang, P_PEAU)
	_ellipsoide(b, T.call(tete + Vector3(0.0, -0.006, -0.097) * kt), Vector3(0.013, 0.021, 0.017) * kt, tang, P_PEAU)
	# tour de cou porté sur le menton : couleur peau chez ceux qui n'en
	# ont pas (cou et menton), sinon tissu
	_tube(b, [T.call(tete + Vector3(0.0, -0.118, -0.004) * kt), T.call(tete + Vector3(0.0, -0.085, -0.010) * kt),
		T.call(tete + Vector3(0.0, -0.052, -0.018) * kt)],
		[0.068 * kt, 0.070 * kt, 0.068 * kt], [0.074 * kt, 0.082 * kt, 0.080 * kt], P_TOUR_COU,
		tang * Vector3.RIGHT, false, false)
	if coiffe == "casque":
		var rc: Basis = tang * Basis(Vector3.RIGHT, 0.22)
		_ellipsoide(b, T.call(tete + Vector3(0.0, 0.028, 0.012) * kt), Vector3(0.106, 0.102, 0.126) * kt,
			rc, P_CASQUE, 0.0, deg_to_rad(104.0))
		for sxh in [-1.0, 1.0]:
			_ellipsoide(b, T.call(tete + Vector3(sxh * 0.096, -0.022, 0.014) * kt),
				Vector3(0.026, 0.046, 0.044) * kt, tang, P_CASQUE)
		# masque : monture, écran bombé, sangle
		var cm: Vector3 = T.call(tete + Vector3(0.0, -0.006, 0.018) * kt)
		_bande(b, cm, 0.111 * kt, 0.124 * kt, deg_to_rad(-80.0), deg_to_rad(80.0), 0.090 * kt, P_MASQUE, tang)
		_bande(b, cm, 0.116 * kt, 0.130 * kt, deg_to_rad(-72.0), deg_to_rad(72.0), 0.078 * kt, P_ECRAN, tang, 0.05)
		_bande(b, cm + tang * Vector3(0.0, 0.006, 0.0), 0.109 * kt, 0.124 * kt, deg_to_rad(76.0),
			deg_to_rad(284.0), 0.034 * kt, P_MASQUE, tang)
	else:
		# bonnet à revers et pompon, cheveux, lunettes de soleil
		_ellipsoide(b, T.call(tete + Vector3(0.0, 0.020, 0.006) * kt), Vector3(0.091, 0.098, 0.106) * kt,
			tang, P_BONNET, 0.0, deg_to_rad(96.0))
		var cr: Vector3 = T.call(tete + Vector3(0.0, 0.004, 0.006) * kt)
		_bande(b, cr, 0.094 * kt, 0.108 * kt, 0.0, TAU, 0.040 * kt, P_BONNET, tang, 0.05)
		_ellipsoide(b, T.call(tete + Vector3(0.0, 0.122, 0.012) * kt), Vector3(0.036, 0.034, 0.036) * kt, tang, P_POMPON)
		_ellipsoide(b, T.call(tete + Vector3(0.0, -0.035, 0.052) * kt), Vector3(0.086, 0.074, 0.066) * kt, tang, P_CHEVEUX)
		var cl: Vector3 = T.call(tete + Vector3(0.0, -0.012, 0.010) * kt)
		_bande(b, cl, 0.098 * kt, 0.112 * kt, deg_to_rad(-60.0), deg_to_rad(60.0), 0.036 * kt, P_ECRAN, tang, 0.03)
		_bande(b, cl + tang * Vector3(0.0, 0.022 * kt, 0.0), 0.097 * kt, 0.111 * kt, deg_to_rad(-62.0),
			deg_to_rad(62.0), 0.007 * kt, P_MASQUE, tang)
	if pose == "telephone":
		var ph: Vector3 = (s.main_d + s.main_g) * 0.5 + Vector3(0.0, 0.012, 0.0)
		var rot_ph: Basis = Basis(Vector3.RIGHT, deg_to_rad(-52.0))
		_boite(b, ph, Vector3(0.037, 0.075, 0.0045), rot_ph, P_SEMELLE)
		_boite(b, ph + rot_ph * Vector3(0.0, 0.0, -0.0047), Vector3(0.033, 0.069, 0.0005), rot_ph, P_TELEPHONE)
	return b.commit(mat)


static func _chaussure(b: Bati, ch: Vector3, sx: float, k: float) -> void:
	var kk: float = maxf(k, 0.80)    # pointure : les chaussures d'enfant restent grosses
	var z_pied: float = ch.z - 0.075 * kk
	# semelle, coque du pied, tige avec inclinaison vers l'avant
	_boite(b, Vector3(ch.x, 0.016 * kk, z_pied), Vector3(0.056, 0.016, 0.158) * kk, Basis.IDENTITY, P_SEMELLE)
	_ellipsoide(b, Vector3(ch.x, 0.066 * kk, z_pied - 0.01 * kk), Vector3(0.060, 0.052, 0.150) * kk,
		Basis.IDENTITY, P_CHAUSSURE)
	var bas: Vector3 = Vector3(ch.x, 0.05 * kk, ch.z + 0.012 * kk)
	var haut: Vector3 = Vector3(ch.x, 0.335 * kk, ch.z - 0.035 * kk)
	_tube(b, [bas, bas.lerp(haut, 0.5), haut], [0.064 * kk, 0.065 * kk, 0.068 * kk],
		[0.080 * kk, 0.077 * kk, 0.078 * kk], P_CHAUSSURE, Vector3.RIGHT, true, true)
	# strap en haut, boucles côté extérieur
	_tube(b, [haut - Vector3(0.0, 0.035, -0.006) * kk, haut + Vector3(0.0, 0.002, 0.0)],
		[0.070 * kk, 0.071 * kk], [0.081 * kk, 0.082 * kk], P_SEMELLE)
	for j in range(3):
		var y: float = [0.10, 0.19, 0.27][j] * kk
		var t: float = clampf((y - bas.y) / (haut.y - bas.y), 0.0, 1.0)
		var p: Vector3 = bas.lerp(haut, t)
		var zf: float = p.z - (0.083 if j > 0 else 0.07) * kk
		_boite(b, Vector3(p.x + sx * 0.035 * kk, y, zf), Vector3(0.018, 0.007, 0.012) * kk,
			Basis(Vector3.UP, sx * 0.6), P_BOUCLE, false)


static func _gant(b: Bati, po: Vector3, ma: Vector3, sx: float, k: float) -> void:
	var d: Vector3 = (ma - po).normalized()
	var lat: Vector3 = Vector3.RIGHT if absf(d.dot(Vector3.RIGHT)) < 0.8 else Vector3.FORWARD
	_tube(b, [po - d * 0.03 * k, po + d * 0.035 * k], [0.054 * k, 0.050 * k], [0.054 * k, 0.050 * k],
		P_GANT, lat, false, true)
	var x: Vector3 = (lat - d * lat.dot(d)).normalized()
	var z: Vector3 = d.cross(x).normalized()
	var rot: Basis = Basis(x, d, z)
	_ellipsoide(b, po + d * 0.085 * k, Vector3(0.046, 0.075, 0.030) * k, rot, P_GANT)
	_ellipsoide(b, po + d * 0.06 * k + x * (-sx) * 0.035 * k - z * 0.01 * k,
		Vector3(0.017, 0.040, 0.017) * k, rot * Basis(Vector3.FORWARD, sx * 0.5), P_GANT)


## Sac à dos (même transformée que le passager).
static func sac(pose: String, mat: Material) -> ArrayMesh:
	var b: Bati = Bati.new()
	var s: Dictionary = _squelette(pose)
	var k: float = s.k
	var z_dos: float = 0.02 * k if pose == "assis" else 0.0
	var y0: float = s.ourlet
	var y1: float = s.haut_torse
	var yc: float = lerpf(y0, y1, 0.55)
	var hc: float = (y1 - y0) * 0.33
	_ellipsoide(b, Vector3(0.0, yc, 0.205 * k + z_dos), Vector3(0.150 * k, hc, 0.085 * k),
		Basis.IDENTITY, P_SAC)
	_boite(b, Vector3(0.0, yc + hc * 0.15, 0.27 * k + z_dos), Vector3(0.10 * k, hc * 0.55, 0.02 * k),
		Basis.IDENTITY, P_SEMELLE)
	for sx in [-1.0, 1.0]:
		# du haut du sac, par-dessus l'épaule, puis le long de la poitrine,
		# à 7 mm de la veste
		var pts_b: Array = []
		var x_b: float = sx * 0.095 * k
		for tv in [0.82, 0.90, 0.95]:
			pts_b.append(Vector3(x_b, lerpf(y0, y1, tv), _z_torse(tv, x_b, 1.0, k) + 0.007 + z_dos))
		pts_b.append(Vector3(x_b, y1 + 0.004 * k, 0.012 * k + z_dos))
		for tv2 in [0.95, 0.88, 0.76, 0.62, 0.50]:
			var xx: float = sx * lerpf(0.095, 0.115, (0.95 - tv2) / 0.45) * k
			pts_b.append(Vector3(xx, lerpf(y0, y1, tv2), _z_torse(tv2, xx, -1.0, k) - 0.007 + z_dos))
		var rxb: Array = []
		var rzb: Array = []
		for q in pts_b:
			rxb.append(0.021 * k)
			rzb.append(0.005)
		_tube(b, pts_b, rxb, rzb, P_SAC, Vector3.RIGHT, true, true)
	return b.commit(mat)


# --- Matériel -------------------------------------------------------------------

## Paire de skis tenue debout, spatules en haut, semelle contre semelle
## (freins emboîtés) : cintrés, spatules relevées, fixations, carres.
static func skis(mat: Material) -> ArrayMesh:
	var b: Bati = Bati.new()
	var L: float = 1.70
	# (hauteur depuis le talon, demi-largeur)
	var prof: Array = [[0.0, 0.030], [0.025, 0.050], [0.08, 0.056], [0.30, 0.053], [0.60, 0.046],
		[0.85, 0.0425], [1.10, 0.047], [1.35, 0.057], [1.48, 0.062], [1.57, 0.058], [1.64, 0.047],
		[1.68, 0.030], [1.70, 0.012]]
	var ep: float = 0.016
	for sg in [-1.0, 1.0]:
		for niveau in [0, 1]:
			b.lod = niveau
			var g: Array = []
			var pas: int = 1 if niveau == 0 else 3
			var ks: Array = []
			var q: int = 0
			while q < prof.size():
				ks.append(q)
				q += pas
			if ks[ks.size() - 1] != prof.size() - 1:
				ks.append(prof.size() - 1)
			for kk in ks:
				var y: float = float(prof[kk][0]) * L / 1.70
				var w: float = prof[kk][1]
				# spatule et talon relevés vers le dessus (extérieur)
				var lev: float = 0.0
				if y > 1.42:
					lev = 0.075 * pow((y - 1.42) / 0.28, 2.0)
				elif y < 0.12:
					lev = 0.012 * pow((0.12 - y) / 0.12, 2.0)
				var x_semelle: float = sg * (0.006 + lev)
				var x_dessus: float = x_semelle + sg * ep
				var part_dessus: int = P_SKI_MOTIF if (y > 1.10 and y < 1.36) or y < 0.10 else P_SKI
				var ligne: Array = []
				# 4 coins : semelle avant, dessus avant, dessus arrière, semelle arrière
				ligne.append(b.pt(Vector3(x_semelle, y, -w), Vector3(-sg, 0.0, 0.0), P_SKI_SEMELLE))
				ligne.append(b.pt(Vector3(x_semelle, y, -w), Vector3(0.0, 0.0, -1.0), P_BOUCLE))
				ligne.append(b.pt(Vector3(x_dessus, y, -w), Vector3(0.0, 0.0, -1.0), P_BOUCLE))
				ligne.append(b.pt(Vector3(x_dessus, y, -w), Vector3(sg, 0.0, 0.0), part_dessus))
				ligne.append(b.pt(Vector3(x_dessus, y, w), Vector3(sg, 0.0, 0.0), part_dessus))
				ligne.append(b.pt(Vector3(x_dessus, y, w), Vector3(0.0, 0.0, 1.0), P_BOUCLE))
				ligne.append(b.pt(Vector3(x_semelle, y, w), Vector3(0.0, 0.0, 1.0), P_BOUCLE))
				ligne.append(b.pt(Vector3(x_semelle, y, w), Vector3(-sg, 0.0, 0.0), P_SKI_SEMELLE))
				g.append(ligne)
			# faces : semelle (0-7), carre (1-2), dessus (3-4), carre (5-6)
			for r in range(g.size() - 1):
				var l0: Array = g[r]
				var l1: Array = g[r + 1]
				for paire in [[0, 7], [1, 2], [3, 4], [5, 6]]:
					b.quad(l0[paire[0]], l1[paire[0]], l1[paire[1]], l0[paire[1]])
		b.lod = 0
		# fixations : butée (avant) et talonnière, freins
		var xo: float = sg * (0.006 + ep)
		_boite(b, Vector3(xo + sg * 0.024, 0.965, 0.0), Vector3(0.024, 0.050, 0.036), Basis.IDENTITY, P_FIXATION)
		_boite(b, Vector3(xo + sg * 0.030, 0.640, 0.0), Vector3(0.030, 0.065, 0.034), Basis.IDENTITY, P_FIXATION)
		_boite(b, Vector3(xo + sg * 0.010, 0.80, 0.0), Vector3(0.010, 0.11, 0.030), Basis.IDENTITY, P_SEMELLE, false)
		for sz in [-1.0, 1.0]:
			_boite(b, Vector3(xo + sg * 0.012, 0.70, sz * 0.050), Vector3(0.006, 0.050, 0.008),
				Basis(Vector3.RIGHT, sz * 0.25), P_SEMELLE, false)
	return b.commit(mat)


## Skis chaussés (le skieur jouable sur la neige) : deux skis à plat sous
## les chaussures, spatule vers l'avant (−z), semelle à y = 0. Même profil
## que skis() ; chaussure centrée à 0,80 m de la queue, entre la talonnière
## (0,64 m) et la butée (0,965 m).
const CENTRE_CHAUSSURE: float = 0.80
## `chasse` : angle (rad) du chasse-neige — chaque ski pivote autour de sa
## spatule, les talons s'écartent, les pieds sont plus larges.
static func skis_aux_pieds(mat: Material, chasse: float = 0.0) -> ArrayMesh:
	var b: Bati = Bati.new()
	var prof: Array = [[0.0, 0.030], [0.025, 0.050], [0.08, 0.056], [0.30, 0.053], [0.60, 0.046],
		[0.85, 0.0425], [1.10, 0.047], [1.35, 0.057], [1.48, 0.062], [1.57, 0.058], [1.64, 0.047],
		[1.68, 0.030], [1.70, 0.012]]
	var ep: float = 0.016
	var zc: float = -0.05                 # milieu de la chaussure (repère du skieur)
	b.lod = 2
	for sx in [-1.0, 1.0]:
		var xc: float = sx * (0.10 if chasse == 0.0 else 0.17)
		var piv: Vector3 = Vector3(xc, 0.0, zc - (1.70 - CENTRE_CHAUSSURE))   # la spatule
		var rot: Basis = Basis(Vector3.UP, sx * chasse)
		var tourne: Callable = func(p: Vector3) -> Vector3:
			return piv + rot * (p - piv)
		var nrot: Callable = func(nv: Vector3) -> Vector3:
			return rot * nv
		var g: Array = []
		for e in prof:
			var y: float = e[0]
			var w: float = e[1]
			var lev: float = 0.0
			if y > 1.42:
				lev = 0.075 * pow((y - 1.42) / 0.28, 2.0)
			elif y < 0.12:
				lev = 0.012 * pow((0.12 - y) / 0.12, 2.0)
			var z: float = zc - (y - CENTRE_CHAUSSURE)
			var dessus: int = P_SKI_MOTIF if (y > 1.10 and y < 1.36) or y < 0.10 else P_SKI
			g.append([
				b.pt(tourne.call(Vector3(xc - w, lev, z)), Vector3.DOWN, P_SKI_SEMELLE),
				b.pt(tourne.call(Vector3(xc + w, lev, z)), Vector3.DOWN, P_SKI_SEMELLE),
				b.pt(tourne.call(Vector3(xc - w, lev, z)), nrot.call(Vector3.LEFT), P_BOUCLE),
				b.pt(tourne.call(Vector3(xc - w, lev + ep, z)), nrot.call(Vector3.LEFT), P_BOUCLE),
				b.pt(tourne.call(Vector3(xc - w, lev + ep, z)), Vector3.UP, dessus),
				b.pt(tourne.call(Vector3(xc + w, lev + ep, z)), Vector3.UP, dessus),
				b.pt(tourne.call(Vector3(xc + w, lev + ep, z)), nrot.call(Vector3.RIGHT), P_BOUCLE),
				b.pt(tourne.call(Vector3(xc + w, lev, z)), nrot.call(Vector3.RIGHT), P_BOUCLE)])
		for r in range(g.size() - 1):
			var l0: Array = g[r]
			var l1: Array = g[r + 1]
			for paire in [[0, 1], [2, 3], [4, 5], [6, 7]]:
				b.quad(l0[paire[0]], l1[paire[0]], l1[paire[1]], l0[paire[1]])
		# fixations : butée et talonnière
		_boite(b, tourne.call(Vector3(xc, ep + 0.022, zc - (0.965 - CENTRE_CHAUSSURE))), Vector3(0.036, 0.022, 0.026),
			rot, P_FIXATION)
		_boite(b, tourne.call(Vector3(xc, ep + 0.028, zc - (0.64 - CENTRE_CHAUSSURE))), Vector3(0.034, 0.028, 0.032),
			rot, P_FIXATION)
	b.lod = 0
	return b.commit(mat)


## Un bâton seul, debout du pied (0, 0, 0) à la poignée (0, 1,15, 0) :
## posé par le skieur jouable entre sa main et la neige.
const LONG_BATON: float = 1.15
static func baton(mat: Material) -> ArrayMesh:
	var b: Bati = Bati.new()
	var pied: Vector3 = Vector3.ZERO
	var tete: Vector3 = Vector3(0.0, LONG_BATON, 0.0)
	var d: Vector3 = Vector3.UP
	_tube(b, [pied + d * 0.02, pied.lerp(tete, 0.5), tete - d * 0.12], [0.0055, 0.0085, 0.0095],
		[0.0055, 0.0085, 0.0095], P_BATON, Vector3.RIGHT, true, false)
	_tube(b, [tete - d * 0.14, tete - d * 0.06, tete], [0.015, 0.017, 0.016], [0.015, 0.017, 0.016],
		P_POIGNEE, Vector3.RIGHT, false, true)
	_bande(b, pied + d * 0.09, 0.042, 0.042, 0.0, TAU, 0.006, P_POIGNEE, Basis.IDENTITY)
	return b.commit(mat)


## Deux bâtons appuyés : tube effilé, poignée, dragonne, rondelle.
static func batons(mat: Material) -> ArrayMesh:
	var b: Bati = Bati.new()
	for sz in [-0.018, 0.018]:
		var pied: Vector3 = Vector3(0.0, 0.0, sz)
		var tete: Vector3 = Vector3(-0.07, 1.20, sz - 0.04)
		var d: Vector3 = (tete - pied).normalized()
		_tube(b, [pied + d * 0.02, pied.lerp(tete, 0.5), tete - d * 0.12], [0.0055, 0.0085, 0.0095],
			[0.0055, 0.0085, 0.0095], P_BATON, Vector3.RIGHT, true, false)
		_tube(b, [tete - d * 0.14, tete - d * 0.06, tete], [0.015, 0.017, 0.016], [0.015, 0.017, 0.016],
			P_POIGNEE, Vector3.RIGHT, false, true)
		var rot: Basis = Basis(Vector3.FORWARD, -atan2(d.x, d.y))
		_bande(b, pied + d * 0.09, 0.042, 0.042, 0.0, TAU, 0.006, P_POIGNEE, rot)
		_tube(b, [tete - d * 0.04, tete - d * 0.04 + Vector3(0.03, -0.09, 0.0), tete - d * 0.10 + Vector3(0.015, -0.13, 0.0)],
			[0.004, 0.004, 0.004], [0.010, 0.010, 0.010], P_SEMELLE)
	return b.commit(mat)


## Snowboard tenu debout : planche aux bouts arrondis, deux fixations à
## spoiler et sangles.
static func surf(mat: Material) -> ArrayMesh:
	var b: Bati = Bati.new()
	var L: float = 1.55
	var ep: float = 0.013
	for niveau in [0, 1]:
		b.lod = niveau
		var n_ys: int = 22 if niveau == 0 else 8
		var g: Array = []
		for j in range(n_ys + 1):
			var t: float = float(j) / float(n_ys)
			var y: float = t * L
			var w: float = 0.125 + 0.020 * pow(2.0 * t - 1.0, 2.0)
			var bout: float = 0.11
			if y < bout:
				w *= sqrt(maxf(1.0 - pow((bout - y) / bout, 2.0), 0.0))
			elif y > L - bout:
				w *= sqrt(maxf(1.0 - pow((y - (L - bout)) / bout, 2.0), 0.0))
			w = maxf(w, 0.004)
			var lev: float = 0.03 * (pow(maxf(0.0, (y - (L - 0.16)) / 0.16), 2.0) + pow(maxf(0.0, (0.16 - y) / 0.16), 2.0))
			var x0: float = lev
			var x1: float = lev + ep
			g.append([
				b.pt(Vector3(x0, y, -w), Vector3(-1, 0, 0), P_SKI_SEMELLE),
				b.pt(Vector3(x0, y, -w), Vector3(0, 0, -1), P_BOUCLE),
				b.pt(Vector3(x1, y, -w), Vector3(0, 0, -1), P_BOUCLE),
				b.pt(Vector3(x1, y, -w), Vector3(1, 0, 0), P_SURF),
				b.pt(Vector3(x1, y, w), Vector3(1, 0, 0), P_SURF),
				b.pt(Vector3(x1, y, w), Vector3(0, 0, 1), P_BOUCLE),
				b.pt(Vector3(x0, y, w), Vector3(0, 0, 1), P_BOUCLE),
				b.pt(Vector3(x0, y, w), Vector3(-1, 0, 0), P_SKI_SEMELLE)])
		for r in range(g.size() - 1):
			var l0: Array = g[r]
			var l1: Array = g[r + 1]
			for paire in [[0, 7], [1, 2], [3, 4], [5, 6]]:
				b.quad(l0[paire[0]], l1[paire[0]], l1[paire[1]], l0[paire[1]])
	b.lod = 0
	for y in [0.55, 1.00]:
		var x: float = 0.013
		_boite(b, Vector3(x + 0.012, y, 0.0), Vector3(0.012, 0.075, 0.115), Basis.IDENTITY, P_FIXATION)
		_boite(b, Vector3(x + 0.095, y + 0.06, 0.10), Vector3(0.085, 0.012, 0.07),
			Basis(Vector3.FORWARD, 0.15), P_FIXATION)
		for dy in [-0.035, 0.035]:
			_boite(b, Vector3(x + 0.060, y + dy, 0.0), Vector3(0.008, 0.016, 0.105), Basis.IDENTITY, P_SEMELLE)
	return b.commit(mat)
