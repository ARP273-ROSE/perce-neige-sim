class_name RollerMesh
extends RefCounted
## Galets de ligne, leurs fourches et le culot d'attache du câble.
##
## Galet (photo du reportage remontees-mecaniques.net « Un galet ainsi
## que le câble », © 2015 Olivier Lakatos, mesurée dans
## audit_physique/galets_ligne.sage) : deux joues évasées en alliage
## léger Ø 640, une bande de roulement en caoutchouc Ø 500 au fond de la
## gorge, un moyeu à bras. Vu de la cabine (vidéo du 26/04) : deux joues
## claires en V et la gorge sombre. Repère local : axe du galet = Y,
## origine au centre (même convention que CylinderMesh).
##
## Culot : cône d'acier coulé sur le bout du câble (« attaches culot »,
## fiche technique du reportage), base ≈ 2,5 d, longueur ≈ 5 d (même photo).

const R_JOUE: float = 0.32          # rayon des joues
const R_BANDE: float = 0.25         # rayon au fond de la gorge (contact du câble)
const LARGEUR: float = 0.20         # de joue à joue
const BANDE: float = 0.10           # largeur de la bande caoutchouc
const EPAULE: float = 0.006         # épaulement de la bande de part et d'autre de la gorge
const T_JOUE: float = 0.008         # épaisseur des joues
const R_JANTE: float = 0.205        # alésage de la jante (ouverture des joues)
const R_MOYEU: float = 0.065
const L_MOYEU: float = 0.17
const N_BRAS: int = 5

# Fourche (flasques + semelle + paliers) : dans le même repère que le galet.
const FLASQUE_T: float = 0.02
const FLASQUE_JEU: float = 0.02     # entre la joue et la flasque
const FLASQUE_Y: float = LARGEUR * 0.5 + FLASQUE_JEU + FLASQUE_T * 0.5
const FOURCHE_BAS: float = R_JOUE + 0.04   # dessous de la semelle, sous l'axe

# Godot : faces avant dans le sens HORAIRE vues de devant (doc ArrayMesh).
const _AVANT_HORAIRE: bool = true


static func materiaux() -> Dictionary:
	var alu: StandardMaterial3D = StandardMaterial3D.new()
	alu.albedo_color = Color(0.80, 0.80, 0.78)
	alu.metallic = 0.55
	alu.roughness = 0.42
	var caoutchouc: StandardMaterial3D = StandardMaterial3D.new()
	caoutchouc.albedo_color = Color(0.075, 0.08, 0.09)
	caoutchouc.roughness = 0.85
	var galva: StandardMaterial3D = StandardMaterial3D.new()
	galva.albedo_color = Color(0.82, 0.83, 0.81)
	galva.metallic = 0.3
	galva.roughness = 0.5
	var acier: StandardMaterial3D = StandardMaterial3D.new()
	acier.albedo_color = Color(0.30, 0.30, 0.32)
	acier.metallic = 0.85
	acier.roughness = 0.35
	var culot: StandardMaterial3D = StandardMaterial3D.new()
	culot.albedo_color = Color(0.72, 0.73, 0.72)
	culot.metallic = 0.7
	culot.roughness = 0.38
	return {"alu": alu, "caoutchouc": caoutchouc, "galva": galva,
		"acier": acier, "culot": culot}


# --- Primitives ------------------------------------------------------------

## Triangle orienté : l'ordre des sommets est choisi pour que la face
## avant soit du côté de `n_ref`.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, n_ref: Vector3) -> void:
	var g: float = (b - a).cross(c - a).dot(n_ref)
	var horaire: bool = g < 0.0
	if horaire != _AVANT_HORAIRE:
		var t: Vector3 = b
		b = c
		c = t
		var tn: Vector3 = nb
		nb = nc
		nc = tn
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)


## Profil (r, y) tourné autour de Y. Chaque segment reçoit la normale
## (dy, −dr)·dehors : +1 pour un profil parcouru vers les y croissants le
## long de sa face extérieure.
static func _lathe(st: SurfaceTool, prof: PackedVector2Array, n_seg: int, dehors: float) -> void:
	for i in range(prof.size() - 1):
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		var d: Vector2 = p1 - p0
		if d.length() < 1e-6:
			continue
		var n2: Vector2 = Vector2(d.y, -d.x).normalized() * dehors
		for j in range(n_seg):
			var t0: float = TAU * float(j) / float(n_seg)
			var t1: float = TAU * float(j + 1) / float(n_seg)
			var c0: float = cos(t0)
			var s0: float = sin(t0)
			var c1: float = cos(t1)
			var s1: float = sin(t1)
			var a: Vector3 = Vector3(p0.x * c0, p0.y, p0.x * s0)
			var b: Vector3 = Vector3(p1.x * c0, p1.y, p1.x * s0)
			var c: Vector3 = Vector3(p1.x * c1, p1.y, p1.x * s1)
			var e: Vector3 = Vector3(p0.x * c1, p0.y, p0.x * s1)
			var n0: Vector3 = Vector3(n2.x * c0, n2.y, n2.x * s0)
			var n1: Vector3 = Vector3(n2.x * c1, n2.y, n2.x * s1)
			var nm: Vector3 = (n0 + n1).normalized()
			_tri(st, a, b, c, n0, n0, n1, nm)
			_tri(st, a, c, e, n0, n1, n1, nm)


## Boîte orientée : centre, demi-tailles le long de ux, uy, uz.
static func _boite(st: SurfaceTool, c: Vector3, h: Vector3, ux: Vector3, uy: Vector3, uz: Vector3) -> void:
	var ax: Array = [ux * h.x, uy * h.y, uz * h.z]
	var nrm: Array = [ux, uy, uz]
	for k in range(3):
		var u: Vector3 = ax[k]
		var v: Vector3 = ax[(k + 1) % 3]
		var w: Vector3 = ax[(k + 2) % 3]
		for sg in [-1.0, 1.0]:
			var f: Vector3 = c + u * sg
			var n: Vector3 = (nrm[k] as Vector3) * sg
			var p0: Vector3 = f - v - w
			var p1: Vector3 = f + v - w
			var p2: Vector3 = f + v + w
			var p3: Vector3 = f - v + w
			_tri(st, p0, p1, p2, n, n, n, n)
			_tri(st, p0, p2, p3, n, n, n, n)


## Cylindre d'axe `u` (fermé), centre c.
static func _cylindre(st: SurfaceTool, c: Vector3, u: Vector3, r: float, l: float, n_seg: int) -> void:
	var a: Vector3 = u.normalized()
	var p: Vector3 = (Vector3.UP if absf(a.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).cross(a).normalized()
	var q: Vector3 = a.cross(p)
	var h: Vector3 = a * l * 0.5
	for j in range(n_seg):
		var t0: float = TAU * float(j) / float(n_seg)
		var t1: float = TAU * float(j + 1) / float(n_seg)
		var d0: Vector3 = p * cos(t0) + q * sin(t0)
		var d1: Vector3 = p * cos(t1) + q * sin(t1)
		var nm: Vector3 = (d0 + d1).normalized()
		_tri(st, c - h + d0 * r, c + h + d0 * r, c + h + d1 * r, d0, d0, d1, nm)
		_tri(st, c - h + d0 * r, c + h + d1 * r, c - h + d1 * r, d0, d1, d1, nm)
		_tri(st, c + h, c + h + d0 * r, c + h + d1 * r, a, a, a, a)
		_tri(st, c - h, c - h + d1 * r, c - h + d0 * r, -a, -a, -a, -a)


# --- Galet -----------------------------------------------------------------

## Profil de la bande de roulement : épaulements à R_BANDE + EPAULE, gorge
## circulaire jusqu'à R_BANDE au milieu (le câble y repose).
static func _profil_bande() -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var hb: float = BANDE * 0.5
	var hg: float = 0.032          # demi-largeur de la gorge
	pts.append(Vector2(R_BANDE + EPAULE, -hb))
	pts.append(Vector2(R_BANDE + EPAULE, -hg))
	for i in range(1, 6):
		var y: float = -hg + 2.0 * hg * float(i) / 6.0
		var f: float = 1.0 - (y / hg) * (y / hg)
		pts.append(Vector2(R_BANDE + EPAULE * (1.0 - f), y))
	pts.append(Vector2(R_BANDE + EPAULE, hg))
	pts.append(Vector2(R_BANDE + EPAULE, hb))
	return pts


## Joue côté σ (±1), profil fermé : flanc de gorge (vers le câble), lèvre,
## dos de la joue jusqu'à l'ouverture, alésage de la jante.
static func _profil_joue(sg: float) -> PackedVector2Array:
	var hb: float = BANDE * 0.5
	var hw: float = LARGEUR * 0.5
	var pied: Vector2 = Vector2(R_BANDE + EPAULE, sg * hb)
	var levre: Vector2 = Vector2(R_JOUE, sg * hw)
	var d: Vector2 = (levre - pied).normalized()
	# normale du flanc côté gorge (vers les |y| décroissants)
	var ng: Vector2 = Vector2(d.y, -d.x) if sg > 0.0 else Vector2(-d.y, d.x)
	var dos_haut: Vector2 = levre - ng * T_JOUE
	var dos_bas: Vector2 = pied - ng * T_JOUE + Vector2(0.0, sg * 0.004)
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(pied)
	pts.append(levre)
	pts.append(Vector2(R_JOUE + 0.004, sg * (hw + 0.002)))
	pts.append(dos_haut)
	pts.append(dos_bas)
	pts.append(Vector2(R_JANTE, sg * (hb + 0.012)))
	pts.append(Vector2(R_JANTE, 0.0))
	return pts


static func build_galet(detail: bool) -> ArrayMesh:
	var mats: Dictionary = materiaux()
	var n_seg: int = 28 if detail else 14
	var mesh: ArrayMesh = ArrayMesh.new()

	# surface 0 : alliage (joues, jante, moyeu, bras)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sg in [-1.0, 1.0]:
		var pj: PackedVector2Array = _profil_joue(sg)
		# le sens de parcours s'inverse avec σ : la normale suit
		_lathe(st, pj, n_seg, sg)
	if detail:
		# moyeu et bras (visibles par l'ouverture des joues)
		var moyeu: PackedVector2Array = PackedVector2Array([
			Vector2(0.03, -L_MOYEU * 0.5), Vector2(R_MOYEU, -L_MOYEU * 0.5),
			Vector2(R_MOYEU, L_MOYEU * 0.5), Vector2(0.03, L_MOYEU * 0.5)])
		_lathe(st, moyeu, 16, 1.0)
		for k in range(N_BRAS):
			var a: float = TAU * float(k) / float(N_BRAS)
			var dirv: Vector3 = Vector3(cos(a), 0.0, sin(a))
			var tang: Vector3 = Vector3(-sin(a), 0.0, cos(a))
			var r0: float = R_MOYEU - 0.01
			var r1: float = R_JANTE + 0.012
			var c: Vector3 = dirv * (r0 + r1) * 0.5
			_boite(st, c, Vector3((r1 - r0) * 0.5, 0.02, 0.022), dirv, Vector3.UP, tang)
	else:
		# loin : l'ouverture des joues est fermée par un disque sombre
		var fond: PackedVector2Array = PackedVector2Array([
			Vector2(0.0, -BANDE * 0.5 - 0.012), Vector2(R_JANTE, -BANDE * 0.5 - 0.012)])
		_lathe(st, fond, n_seg, 1.0)
		var fond2: PackedVector2Array = PackedVector2Array([
			Vector2(R_JANTE, BANDE * 0.5 + 0.012), Vector2(0.0, BANDE * 0.5 + 0.012)])
		_lathe(st, fond2, n_seg, 1.0)
	st.set_material(mats["alu"])
	st.commit(mesh)

	# surface 1 : bande de roulement en caoutchouc
	var st2: SurfaceTool = SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	_lathe(st2, _profil_bande(), n_seg, 1.0)
	st2.set_material(mats["caoutchouc"])
	st2.commit(mesh)
	return mesh


# --- Fourche ---------------------------------------------------------------

## Fourche d'un galet, dans son repère (incliné avec lui, ne tourne pas) :
## deux flasques en tôle galvanisée, une semelle sous le galet, deux
## paliers sur les faces extérieures et l'axe. `sans` = ±1 : pas de palier
## de ce côté (Y local), l'axe s'y arrête à la flasque — côté intérieur
## d'une paire, où l'autre galet est à 4 cm.
static func build_fourche(sans: float = 0.0) -> ArrayMesh:
	var mats: Dictionary = materiaux()
	var mesh: ArrayMesh = ArrayMesh.new()
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Repère du galet (instance = base_voie × rot90) : +X local = haut,
	# +Y = axe, +Z = sens voie.
	var ux: Vector3 = Vector3(1, 0, 0)
	var uy: Vector3 = Vector3(0, 1, 0)
	var uz: Vector3 = Vector3(0, 0, 1)
	for sg in [-1.0, 1.0]:
		var y: float = sg * FLASQUE_Y
		# flasque : trapèze (large en bas) + tête arrondie autour de l'axe
		var bas: float = -FOURCHE_BAS
		var haut: float = 0.0
		var l_bas: float = 0.13       # demi-largeurs le long de la voie
		var l_haut: float = 0.075
		var n_t: int = 6
		for i in range(n_t):
			var x0: float = lerpf(bas, haut, float(i) / float(n_t))
			var x1: float = lerpf(bas, haut, float(i + 1) / float(n_t))
			var w0: float = lerpf(l_bas, l_haut, float(i) / float(n_t))
			var w1: float = lerpf(l_bas, l_haut, float(i + 1) / float(n_t))
			_boite(st, Vector3((x0 + x1) * 0.5, y, 0.0),
				Vector3((x1 - x0) * 0.5, FLASQUE_T * 0.5, (w0 + w1) * 0.5), ux, uy, uz)
		_cylindre(st, Vector3(0.0, y, 0.0), uy, l_haut, FLASQUE_T, 16)
		if sg == sans:
			continue
		# palier : bride + corps + chapeau, côté extérieur
		var yo: float = y + sg * (FLASQUE_T * 0.5)
		_cylindre(st, Vector3(0.0, yo + sg * 0.006, 0.0), uy, 0.068, 0.012, 16)
		_cylindre(st, Vector3(0.0, yo + sg * 0.030, 0.0), uy, 0.050, 0.040, 16)
		_cylindre(st, Vector3(0.0, yo + sg * 0.055, 0.0), uy, 0.030, 0.012, 12)
		# quatre boulons de bride
		for k in range(4):
			var a: float = TAU * (float(k) + 0.5) / 4.0
			_cylindre(st, Vector3(cos(a) * 0.058, yo + sg * 0.015, sin(a) * 0.058), uy, 0.009, 0.010, 6)
	# semelle sous le galet, entre les flasques
	_boite(st, Vector3(-FOURCHE_BAS - 0.01, 0.0, 0.0),
		Vector3(0.01, FLASQUE_Y + FLASQUE_T * 0.5, 0.085), ux, uy, uz)
	st.set_material(mats["galva"])
	st.commit(mesh)
	# axe (acier)
	var st2: SurfaceTool = SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y_neg: float = -(FLASQUE_Y + (0.012 if sans < 0.0 else 0.065))
	var y_pos: float = FLASQUE_Y + (0.012 if sans > 0.0 else 0.065)
	_cylindre(st2, Vector3(0.0, (y_neg + y_pos) * 0.5, 0.0), uy, 0.022, y_pos - y_neg, 12)
	st2.set_material(mats["acier"])
	st2.commit(mesh)
	return mesh


## Traverse en U (repère voie : X travers, Y haut, Z sens voie), longueur w.
static func build_traverse(w: float) -> ArrayMesh:
	var mats: Dictionary = materiaux()
	var mesh: ArrayMesh = ArrayMesh.new()
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ux: Vector3 = Vector3.RIGHT
	var uy: Vector3 = Vector3.UP
	var uz: Vector3 = Vector3.BACK
	_boite(st, Vector3(0, 0, 0.045), Vector3(w * 0.5, 0.05, 0.005), ux, uy, uz)      # âme
	_boite(st, Vector3(0, 0.045, 0), Vector3(w * 0.5, 0.005, 0.05), ux, uy, uz)      # aile haute
	_boite(st, Vector3(0, -0.045, 0), Vector3(w * 0.5, 0.005, 0.05), ux, uy, uz)     # aile basse
	st.set_material(mats["galva"])
	st.commit(mesh)
	return mesh


## Cornière verticale (pied de support), hauteur 1 (mise à l'échelle en Y),
## avec platine au sol.
static func build_pied() -> ArrayMesh:
	var mats: Dictionary = materiaux()
	var mesh: ArrayMesh = ArrayMesh.new()
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ux: Vector3 = Vector3.RIGHT
	var uy: Vector3 = Vector3.UP
	var uz: Vector3 = Vector3.BACK
	_boite(st, Vector3(0, 0, -0.022), Vector3(0.025, 0.5, 0.003), ux, uy, uz)
	_boite(st, Vector3(-0.022, 0, 0), Vector3(0.003, 0.5, 0.025), ux, uy, uz)
	st.set_material(mats["galva"])
	st.commit(mesh)
	return mesh


# --- Culot et tirant ---------------------------------------------------------

## Culot le long de −Z (le câble sort par la pointe vers −Z = vers l'amont
## quand l'instance est orientée sur le brin) : cône coulé, œil de la
## chape à la base, axe de chape. Origine = base du cône.
static func build_culot() -> ArrayMesh:
	var mats: Dictionary = materiaux()
	var mesh: ArrayMesh = ArrayMesh.new()
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var l: float = 0.26
	var rb: float = 0.065
	var rp: float = 0.036
	# profil (r, y) tourné autour de Y puis basculé sur −Z
	var prof: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(rb, 0.0), Vector2(rb, 0.03),
		Vector2(rb * 0.92, 0.08), Vector2(rp, l), Vector2(0.03, l + 0.01)])
	var st_tmp: SurfaceTool = SurfaceTool.new()
	st_tmp.begin(Mesh.PRIMITIVE_TRIANGLES)
	_lathe(st_tmp, prof, 20, 1.0)
	var arr: Array = st_tmp.commit_to_arrays()
	var basc: Basis = Basis(Vector3.RIGHT, -PI * 0.5)   # Y → −Z
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in range(verts.size()):
		st.set_normal(basc * norms[i])
		st.add_vertex(basc * verts[i])
	# chape à la base (deux oreilles) et son axe, vers +Z
	var ux: Vector3 = Vector3.RIGHT
	var uy: Vector3 = Vector3.UP
	var uz: Vector3 = Vector3.BACK
	for sx in [-1.0, 1.0]:
		_boite(st, Vector3(sx * 0.035, 0.0, 0.06), Vector3(0.012, 0.045, 0.06), ux, uy, uz)
	_cylindre(st, Vector3(0.0, 0.0, 0.085), ux, 0.016, 0.11, 10)
	st.set_material(mats["culot"])
	st.commit(mesh)
	return mesh
