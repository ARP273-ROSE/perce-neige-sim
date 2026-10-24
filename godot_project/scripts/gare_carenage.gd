class_name GareCarenage
extends RefCounted
## Carénages des gares de télésiège et de télécabine, par constructeur et
## par époque, d'après les photos des gares du domaine (reportages
## remontees-mecaniques.net, consultés comme référence) :
##   doppelmayr_unig : UNI-G (Palafour, Tufs, Solaise…) — caisse blanche
##     au dessous plat, voûte sombre nervurée, front en arc bordé de bleu,
##     petits ailerons au nez, une seule grosse colonne grise ;
##   doppelmayr_dline : D-Line (Datcha, Solaise) — dôme vitré sombre sur un
##     bandeau noir renflé, liseré rouge, « Val d'Isère » en blanc ;
##   doppelmayr_uni : gares des années 1990 (Paquis, Chaudannes, Vanoise…) —
##     capot blanc à pans coupés, jupe grise, bout arrondi vitré ;
##   poma_classique : Madeleine, Bellevarde, Pyramides — caisse blanche à
##     bandeau de vitres, lanterne vitrée en berceau au-dessus de la poulie,
##     entonnoir sous la poulie, poteaux carrés anthracite ;
##   poma_moderne : Marais, Aiguille Rouge, Daille, Vallon (Poma / Ingélo) —
##     voûte noire en berceau sur un bandeau (blanc à Tignes, noir à
##     Val d'Isère, liseré rouge) ;
##   garaventa : Glacier, Laisinant, Leissières — fût arrondi à bandeau de
##     vitres, grand dôme à facettes au-dessus de la poulie, liseré rouge ;
##   leitner : Leitner récent (Aiguille Percée) — caisse blanche en
##     baignoire, flancs évasés vers le haut, couverture noire bombée à
##     nervures, grand nom bleu sur le flanc ;
##   teleski : poulie horizontale sur un portique galvanisé, motoréducteur
##     sous capot gris à la gare motrice ;
##   fixe : télésièges à pinces fixes (Montaval, Skirail, GMM…) — poulie à
##     l'air sur un bâti d'acier noir, petit local blanc de la motrice.
## La gare BMF (Marmottes, Fontaine Froide) reste celle de LigneRemontee._capot.
## Repère : celui de la gare (X en travers, Y vers le haut, −Z vers l'amont).

var lg: LigneRemontee
var _st: Dictionary = {}          # [matériau, plat] → SurfaceTool
## Élargissement du carénage (double embarquement de Bollin) : les sièges du
## contour extérieur passent jusqu'à elarg m plus loin de l'axe.
var elarg: float = 0.0


func _init(ligne: LigneRemontee) -> void:
	lg = ligne


static func style_pour(constructeur: String, annee: int, famille: String) -> String:
	if famille.begins_with("perche"):
		return "teleski"
	if famille.begins_with("siege_fixe"):
		return "fixe"
	var c: String = constructeur.to_lower()
	if c.find("bmf") >= 0 or c.find("bartholet") >= 0:
		return "bmf"
	if c.find("garaventa") >= 0:
		return "garaventa"
	if c.find("doppelmayr") >= 0:
		if annee >= 2015 and not famille.begins_with("cabine"):
			return "doppelmayr_dline"      # (la télécabine de Solaise garde l'UNI-G)
		return "doppelmayr_unig" if annee >= 2000 else "doppelmayr_uni"
	if c.find("poma") >= 0 or c.find("ingelo") >= 0 or c.find("ingélo") >= 0 or c.find("fatzer") >= 0:
		return "poma_moderne" if annee >= 2010 else "poma_classique"
	if c.find("leitner") >= 0:
		return "leitner" if annee >= 2010 else "doppelmayr_uni"
	return "bmf"


## Abscisse de la colonne du milieu du quai (collisions comprises).
static func z_colonne(znez: float, zc: float) -> float:
	return (znez + zc) * 0.5 - signf(zc - znez) * 1.0


# --- maillage --------------------------------------------------------------------

func _s(mat: String, plat: bool) -> SurfaceTool:
	var k: String = mat + ("|p" if plat else "|l")
	if not _st.has(k):
		var s: SurfaceTool = SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[k] = s
	return _st[k]


func _quad(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, plat: bool = false) -> void:
	var s: SurfaceTool = _s(mat, plat)
	for v in [a, b, c, a, c, d]:
		s.add_vertex(v)


## Section (demi-profil [r, h], du bas extérieur au faîte) balayée de z0 à
## z1, des deux côtés ; mat(h) donne le matériau de chaque bande.
func _balayer(prof: Array, y0: float, z0: float, z1: float, mat: Callable) -> void:
	for sx in [-1.0, 1.0]:
		for i in range(prof.size() - 1):
			var a: Array = prof[i]
			var b: Array = prof[i + 1]
			var m: String = mat.call((float(a[1]) + float(b[1])) * 0.5)
			_quad(m, Vector3(sx * a[0], y0 + a[1], z0), Vector3(sx * b[0], y0 + b[1], z0),
				Vector3(sx * b[0], y0 + b[1], z1), Vector3(sx * a[0], y0 + a[1], z1))


## Bout arrondi en plan : la section tourne autour de l'axe vertical en
## (0, zc), de phi0 à phi1 (0 = côté +X, PI/2 = vers l'arrière de la gare).
func _tourner(prof: Array, y0: float, zc: float, sg: float, phi0: float, phi1: float, n: int,
		mat: Callable, plat: bool = false) -> void:
	for k in range(n):
		var p0: float = lerpf(phi0, phi1, float(k) / n)
		var p1: float = lerpf(phi0, phi1, float(k + 1) / n)
		for i in range(prof.size() - 1):
			var a: Array = prof[i]
			var b: Array = prof[i + 1]
			var m: String = mat.call((float(a[1]) + float(b[1])) * 0.5, (p0 + p1) * 0.5)
			var pt := func(r: float, h: float, phi: float) -> Vector3:
				return Vector3(r * cos(phi), y0 + h, zc + sg * r * sin(phi))
			_quad(m, pt.call(a[0], a[1], p0), pt.call(b[0], b[1], p0), pt.call(b[0], b[1], p1), pt.call(a[0], a[1], p1), plat)


## Face plane d'extrémité fermant la section en z.
func _face(prof: Array, y0: float, z: float, mat: Callable) -> void:
	for i in range(prof.size() - 1):
		var a: Array = prof[i]
		var b: Array = prof[i + 1]
		var m: String = mat.call((float(a[1]) + float(b[1])) * 0.5)
		_quad(m, Vector3(-float(a[0]), y0 + a[1], z), Vector3(float(a[0]), y0 + a[1], z),
			Vector3(float(b[0]), y0 + b[1], z), Vector3(-float(b[0]), y0 + b[1], z), true)


## Dessous plat, avec la fente des suspentes qui suit la boucle des
## véhicules (droite le long du quai, demi-cercle autour de la poulie).
func _dessous(y0: float, z0: float, zc: float, sg: float, R: float, Ro: float, z_ar: float, mat: String) -> void:
	var r_in: float = R - 0.55
	var r_out: float = R + 0.60 + elarg          # fente : les deux contours
	for sx in [-1.0, 1.0]:
		_quad(mat, Vector3(sx * r_out, y0, z0), Vector3(sx * Ro, y0, z0), Vector3(sx * Ro, y0, zc), Vector3(sx * r_out, y0, zc), true)
	_quad(mat, Vector3(-r_in, y0, z0), Vector3(r_in, y0, z0), Vector3(r_in, y0, zc), Vector3(-r_in, y0, zc), true)
	var n: int = 24
	var o: Vector3 = Vector3(0, y0, zc)
	for k in range(n):
		var p0: float = PI * float(k) / n
		var p1: float = PI * float(k + 1) / n
		var c0: Vector3 = Vector3(cos(p0), 0, sg * sin(p0))
		var c1: Vector3 = Vector3(cos(p1), 0, sg * sin(p1))
		_quad(mat, o + c0 * r_in, o + c1 * r_in, o, o, true)
		# au-delà de la fente : jusqu'au bord (cercle, ou rectangle si la caisse est carrée)
		var e0: Vector3 = o + c0 * Ro
		var e1: Vector3 = o + c1 * Ro
		if z_ar != zc:
			e0 = _au_bord(o, c0, Ro, z_ar)
			e1 = _au_bord(o, c1, Ro, z_ar)
		_quad(mat, o + c0 * r_out, e0, e1, o + c1 * r_out, true)


func _au_bord(o: Vector3, c: Vector3, Ro: float, z_ar: float) -> Vector3:
	# rayon issu de la poulie jusqu'au bord d'une caisse rectangulaire
	var tx: float = Ro / maxf(absf(c.x), 0.001)
	var tz: float = absf(z_ar - o.z) / maxf(absf(c.z), 0.001)
	return o + c * minf(tx, tz)


func _valider(g: Node3D, nom: String) -> void:
	var mesh: ArrayMesh = ArrayMesh.new()
	for k in _st.keys():
		var s: SurfaceTool = _st[k]
		var parts: PackedStringArray = String(k).split("|")
		if parts[1] == "p":
			s.set_smooth_group(0xFFFFFFFF)
		s.index()
		s.generate_normals()
		s.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, lg._mat_capot(parts[0]))
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = nom
	mi.mesh = mesh
	g.add_child(mi)
	_st.clear()


## Superellipse : quart de profil de (r0, h0) au faîte (0, h1).
static func _voute(r0: float, h0: float, h1: float, e: float, n: int = 12) -> Array:
	var out: Array = []
	for i in range(1, n + 1):
		var a: float = PI * 0.5 * float(i) / n
		out.append([r0 * pow(cos(a), 2.0 / e), h0 + (h1 - h0) * pow(sin(a), 2.0 / e)])
	return out


static func _r_a(prof: Array, h: float) -> float:
	for i in range(prof.size() - 1):
		if h <= float(prof[i + 1][1]):
			var t: float = (h - float(prof[i][1])) / maxf(float(prof[i + 1][1]) - float(prof[i][1]), 0.001)
			return lerpf(float(prof[i][0]), float(prof[i + 1][0]), t)
	return 0.0


## Cadre (tube) qui suit le profil d'une face, d'un bord à l'autre.
func _cadre(g: Node3D, prof: Array, y0: float, z: float, r: float, m: String, dr: float = 0.0) -> void:
	var pts: PackedVector3Array = PackedVector3Array()
	for i in range(prof.size()):
		pts.append(Vector3(float(prof[i][0]) + dr, y0 + float(prof[i][1]), z))
	for i in range(prof.size() - 2, -1, -1):
		pts.append(Vector3(-float(prof[i][0]) - dr, y0 + float(prof[i][1]), z))
	RemonteeKit.tube(g, pts, r, m, 6)


func _nom(g: Node3D, texte: String, pos: Vector3, rot_y: float, couleur: Color, px: float = 0.0028) -> void:
	if texte == "":
		return
	var lab: Label3D = Label3D.new()
	lab.text = texte
	lab.font_size = 96
	lab.pixel_size = px
	lab.modulate = couleur
	lab.outline_size = 0
	lab.position = pos
	lab.rotation.y = rot_y
	g.add_child(lab)


## Noms sur les deux flancs (lisibles de l'extérieur) à la hauteur h.
func _noms_flancs(g: Node3D, r: float, y: float, zm: float, couleur: Color, majuscules: bool = true) -> void:
	var t: String = lg.nom_court().to_upper() if majuscules else lg.nom_court()
	for sx in [-1.0, 1.0]:
		_nom(g, t, Vector3(sx * (r + 0.03), y, zm), sx * PI * 0.5, couleur)


## Poteau : rond ou carré, protection en mousse rouge au pied.
func _poteau(g: Node3D, z: float, h: float, m: String, rond: bool, r: float = 0.5) -> void:
	if rond:
		RemonteeKit.cylindre(g, r, r, h, Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, z)), m, 20)
	else:
		RemonteeKit.boite_en(g, Vector3(r * 2.0, h, r * 2.0), Vector3(0, h * 0.5, z), m)
	RemonteeKit.cylindre(g, r + 0.12, r + 0.12, 1.9, Transform3D(Basis.IDENTITY, Vector3(0, 0.95, z)), "mousse_rouge", 16)


func _val() -> bool:
	return lg.station.find("Val") >= 0


## Panneaux clairs du carénage : bardage de mélèze aux télécabines de
## Tignes (Tovière, Brévières), plaques blanches ailleurs.
func _coque() -> String:
	return "bois_meleze" if lg.famille.begins_with("cabine") and not _val() else "blanc_plaque"


# --- construction ------------------------------------------------------------------

func construire(g: Node3D, znez: float, zc: float, style: String) -> void:
	match style:
		"doppelmayr_unig":
			_unig(g, znez, zc)
		"doppelmayr_dline":
			_dline(g, znez, zc)
		"doppelmayr_uni":
			_uni(g, znez, zc)
		"poma_classique":
			_poma_classique(g, znez, zc)
		"poma_moderne":
			_poma_moderne(g, znez, zc)
		"garaventa":
			_garaventa(g, znez, zc)
		"leitner":
			_leitner(g, znez, zc)
		"fixe":
			_fixe(g, znez, zc)
		"teleski":
			_teleski(g, znez, zc)


## Doppelmayr UNI-G (photos de Palafour) : caisse rectangulaire aux bouts
## plats, flancs droits blancs, voûte sombre ; arc du front bordé d'un
## jonc bleu (rouge à Val d'Isère), vitres sombres et échelle au nez.
func _unig(g: Node3D, znez: float, zc: float) -> void:
	var sg: float = signf(zc - znez)
	var R: float = lg.voie * 0.5
	var Ro: float = R + LigneRemontee.D_CAPOT + elarg
	var y0: float = lg.H_CABLE_GARE + LigneRemontee.Y_CAPOT
	var z0: float = znez - sg * 1.2
	var z_ar: float = zc + sg * (Ro + 0.2)
	var h1: float = 1.30
	var ht: float = 3.0
	var prof: Array = [[Ro, 0.0], [Ro, h1]]
	prof.append_array(_voute(Ro, h1, ht, 2.6))
	var jonc: String = "rouge_val" if _val() else "bleu_doppelmayr"
	var toit: String = "toit_noir" if _val() else "toit_bleu_nuit"
	var coque: String = _coque()
	var mat := func(h: float) -> String:
		return coque if h < h1 else toit
	_balayer(prof, y0, z0, z_ar, mat)
	_face(prof, y0, z0, func(_h: float) -> String: return coque)
	_face(prof, y0, z_ar, func(_h: float) -> String: return coque)
	_dessous(y0, z0, zc, sg, R, Ro, z_ar, coque)
	_valider(g, "Capot")
	# joncs de l'arc aux deux bouts, filet le long des flancs
	for z in [z0, z_ar]:
		_cadre(g, prof.slice(1), y0, z - sg * 0.02 * (1.0 if z == z0 else -1.0), 0.10, jonc, 0.04)
	for sx in [-1.0, 1.0]:
		RemonteeKit.barre(g, Vector3(sx * (Ro + 0.03), y0 + h1, z0), Vector3(sx * (Ro + 0.03), y0 + h1, z_ar), 0.05, jonc, 6)
		# ailerons au bas du nez
		var ail: Transform3D = Transform3D(Basis(Vector3.BACK, sx * 0.35), Vector3(sx * (Ro + 0.55), y0 + 0.15, z0 + sg * 0.6))
		RemonteeKit.boite(g, Vector3(1.2, 0.10, 1.2), ail, jonc)
	# vitres sombres du front (poste de vigie) et échelle au milieu
	var zf: float = z0 - sg * 0.03
	for sx in [-1.0, 1.0]:
		RemonteeKit.boite_en(g, Vector3(Ro * 0.62, 1.15, 0.05), Vector3(sx * Ro * 0.40, y0 + 1.95, zf), "vitrage_sombre")
	for sx in [-0.25, 0.25]:
		RemonteeKit.barre(g, Vector3(sx, y0 + 0.4, zf - sg * 0.12), Vector3(sx, y0 + ht + 1.1, zf - sg * 0.12), 0.025, "galva", 6)
	for k in range(int((ht + 0.7) / 0.35)):
		var y: float = y0 + 0.5 + k * 0.35
		RemonteeKit.barre(g, Vector3(-0.25, y, zf - sg * 0.12), Vector3(0.25, y, zf - sg * 0.12), 0.015, "galva", 4)
	# garde-corps du toit, au-dessus de l'échelle
	RemonteeKit.barre(g, Vector3(-0.8, y0 + ht + 1.0, zf + sg * 0.3), Vector3(0.8, y0 + ht + 1.0, zf + sg * 0.3), 0.025, "galva", 6)
	# vitres latérales du poste (hublots) vers le nez
	for sx in [-1.0, 1.0]:
		for k in range(3):
			RemonteeKit.boite_en(g, Vector3(0.04, 0.55, 0.9), Vector3(sx * (Ro + 0.01), y0 + 0.7, z0 + sg * (1.4 + 1.2 * k)), "vitrage_sombre")
	_noms_flancs(g, Ro, y0 + 0.40, (z0 + z_ar) * 0.5 + sg * 2.0, Color(0.72, 0.08, 0.10) if not _val() else Color(0.08, 0.08, 0.10))
	# une grosse colonne grise sous la poulie, une autre au quai
	_poteau(g, zc, lg.H_CABLE_GARE - 0.35, "peinture_gris", true, 0.55)
	_poteau(g, z_colonne(znez, zc), y0, "peinture_gris", true, 0.45)


## Doppelmayr D-Line (photo de la Datcha) : bandeau noir renflé au bas,
## liseré rouge, puis un dôme de verre sombre jusqu'au faîte ; bout
## arrondi autour de la poulie ; « Val d'Isère » en blanc sur le bandeau ;
## poteaux ronds gris.
func _dline(g: Node3D, znez: float, zc: float) -> void:
	var sg: float = signf(zc - znez)
	var R: float = lg.voie * 0.5
	var Ro: float = R + LigneRemontee.D_CAPOT + elarg
	var y0: float = lg.H_CABLE_GARE + LigneRemontee.Y_CAPOT
	var z0: float = znez - sg * 0.6
	var hb: float = 1.0
	var prof: Array = [[Ro - 0.1, 0.0], [Ro + 0.25, 0.35], [Ro + 0.25, hb]]
	prof.append_array(_voute(Ro + 0.25, hb, 3.0, 1.9))
	var mat := func(h: float) -> String:
		return "toit_noir" if h < hb or h > 2.75 else "vitrage_sombre"
	var mat_flanc := func(h: float) -> String:
		return "toit_noir" if h < hb or h > 2.3 else "vitrage_sombre"
	_balayer(prof, y0, z0, zc, mat_flanc)
	var mat2 := func(h: float, _phi: float) -> String: return mat.call(h)
	_tourner(prof, y0, zc, sg, 0.0, PI, 32, mat2)
	_face(prof, y0, z0, func(_h: float) -> String: return "toit_noir")
	_dessous(y0, z0, zc, sg, R, Ro - 0.1, zc, "toit_noir")
	_valider(g, "Capot")
	# liseré rouge au haut du bandeau, tout autour
	var pts: PackedVector3Array = PackedVector3Array()
	var rl: float = Ro + 0.28
	pts.append(Vector3(rl, y0 + hb, z0))
	pts.append_array(RemonteeKit.arc(Vector3(0, y0 + hb, zc), Vector3.RIGHT, Vector3(0, 0, sg), rl, 0.0, PI, 32))
	pts.append(Vector3(-rl, y0 + hb, z0))
	RemonteeKit.tube(g, pts, 0.07, "rouge_val", 6)
	# montants clairs de la verrière du dôme
	for k in range(9):
		var phi: float = PI * (0.06 + 0.88 * float(k) / 8.0)
		var pm: PackedVector3Array = PackedVector3Array()
		for j in range(8):
			var h: float = lerpf(hb + 0.05, 2.75, float(j) / 7.0)
			var r: float = _r_a(prof, h) + 0.02
			pm.append(Vector3(r * cos(phi), y0 + h, zc + sg * r * sin(phi)))
		RemonteeKit.tube(g, pm, 0.03, "alu_pince", 5)
	var texte: String = "Val d'Isère" if _val() else lg.station
	_nom(g, texte, Vector3(0, y0 + 0.62, zc + sg * (Ro + 0.28)), 0.0 if sg > 0.0 else PI, Color(0.97, 0.97, 0.97), 0.0045)
	_noms_flancs(g, Ro + 0.25, y0 + 0.62, (z0 + zc) * 0.5, Color(0.97, 0.97, 0.97))
	_poteau(g, zc, lg.H_CABLE_GARE - 0.35, "peinture_gris", true, 0.50)
	_poteau(g, z_colonne(znez, zc), y0, "peinture_gris", true, 0.42)


## Doppelmayr années 1990 (Paquis, Chaudannes) : capot blanc à pans coupés
## sur une jupe grise, bout arrondi autour de la poulie avec un bandeau
## de vitres, colonnes blanches.
func _uni(g: Node3D, znez: float, zc: float) -> void:
	var sg: float = signf(zc - znez)
	var R: float = lg.voie * 0.5
	var Ro: float = R + LigneRemontee.D_CAPOT + elarg
	var y0: float = lg.H_CABLE_GARE + LigneRemontee.Y_CAPOT
	var z0: float = znez - sg * 0.6
	var prof: Array = [[Ro, 0.0], [Ro, 0.55], [Ro - 0.20, 0.75], [Ro * 0.80, 2.05]]
	prof.append_array(_voute(Ro * 0.80, 2.05, 2.55, 2.2, 6))
	var mat := func(h: float) -> String:
		return "peinture_gris" if h < 0.55 else "blanc_plaque"
	_balayer(prof, y0, z0, zc, mat)
	var mat_bout := func(h: float, phi: float) -> String:
		if h > 0.85 and h < 1.75 and phi > 0.35 and phi < PI - 0.35:
			return "vitrage_sombre"
		return mat.call(h)
	_tourner(prof, y0, zc, sg, 0.0, PI, 28, mat_bout)
	_face(prof, y0, z0, mat)
	_dessous(y0, z0, zc, sg, R, Ro, zc, "blanc_plaque")
	_valider(g, "Capot")
	# hublots rectangulaires le long des flancs
	var rh: float = _r_a(prof, 1.3)
	var n_h: int = int(absf(zc - z0) / 2.6)
	for sx in [-1.0, 1.0]:
		for k in range(1, n_h):
			var zh: float = z0 + sg * (2.6 * k)
			var b: Basis = Basis(Vector3.BACK, sx * atan2(Ro * 0.2 - 0.2, 1.3))
			RemonteeKit.boite(g, Vector3(0.05, 0.75, 1.6), Transform3D(b, Vector3(sx * (rh + 0.02), y0 + 1.3, zh)), "vitrage_sombre")
	_noms_flancs(g, Ro, y0 + 0.28, (z0 + zc) * 0.5, Color(0.92, 0.92, 0.94))
	_poteau(g, zc, lg.H_CABLE_GARE - 0.35, "blanc_plaque", true, 0.50)
	_poteau(g, z_colonne(znez, zc), y0, "blanc_plaque", true, 0.45)


## Poma des années 1990-2000 (photos de la Madeleine) : caisse blanche au
## toit presque plat, bandeau de vitres sur les flancs ; au-dessus de la
## poulie, une lanterne en berceau entièrement vitrée qui dépasse le
## toit ; entonnoir blanc sous la poulie ; poteaux carrés anthracite.
func _poma_classique(g: Node3D, znez: float, zc: float) -> void:
	var sg: float = signf(zc - znez)
	var R: float = lg.voie * 0.5
	var Ro: float = R + LigneRemontee.D_CAPOT + elarg
	var y0: float = lg.H_CABLE_GARE + LigneRemontee.Y_CAPOT
	var z0: float = znez - sg * 0.6
	var z_ar: float = zc + sg * (Ro + 0.2)
	var zl: float = z_ar - sg * 3.6         # début de la lanterne
	var prof: Array = [[Ro, 0.0], [Ro, 2.25], [Ro * 0.55, 2.50], [0.0, 2.58]]
	var blanc := func(_h: float) -> String: return "blanc_plaque"
	_balayer(prof, y0, z0, zl, blanc)
	_face(prof, y0, z0, blanc)
	# lanterne : flancs droits jusqu'à 1,5 m puis berceau elliptique
	var lan: Array = [[Ro, 0.0], [Ro, 1.5]]
	for i in range(1, 13):
		var a: float = PI * 0.5 * float(i) / 12
		lan.append([Ro * cos(a), 1.5 + 1.75 * sin(a)])
	var vitre := func(h: float) -> String: return "vitrage_sombre" if h > 0.95 else "blanc_plaque"
	_balayer(lan, y0, zl, z_ar, vitre)
	_face(lan, y0, z_ar, vitre)
	_face(lan, y0, zl, blanc)
	_dessous(y0, z0, zc, sg, R, Ro, z_ar, "blanc_plaque")
	_valider(g, "Capot")
	# meneaux blancs de la lanterne : arcs en travers et lisses en long
	var nz: int = 4
	for k in range(nz + 1):
		var z: float = lerpf(zl, z_ar, float(k) / nz) + (sg * 0.03 if k == nz else 0.0)
		var pts: PackedVector3Array = PackedVector3Array()
		for i in range(lan.size()):
			if float(lan[i][1]) >= 0.95:
				pts.append(Vector3(float(lan[i][0]) + 0.03, y0 + float(lan[i][1]), z))
		for i in range(lan.size() - 2, -1, -1):
			if float(lan[i][1]) >= 0.95:
				pts.append(Vector3(-float(lan[i][0]) - 0.03, y0 + float(lan[i][1]), z))
		RemonteeKit.tube(g, pts, 0.05, "blanc_plaque", 5)
	for i in [1, 4, 7, 10]:
		for sx in [-1.0, 1.0]:
			var p: Array = lan[mini(i + 1, lan.size() - 1)]
			RemonteeKit.barre(g, Vector3(sx * (float(p[0]) + 0.03), y0 + float(p[1]), zl), Vector3(sx * (float(p[0]) + 0.03), y0 + float(p[1]), z_ar), 0.04, "blanc_plaque", 5)
	# meneaux du fond vitré
	for k in range(-3, 4):
		var x: float = Ro * k / 3.5
		var hx: float = 1.5 + 1.75 * sqrt(maxf(1.0 - pow(x / Ro, 2.0), 0.0))
		RemonteeKit.barre(g, Vector3(x, y0 + 0.95, z_ar + sg * 0.03), Vector3(x, y0 + hx, z_ar + sg * 0.03), 0.04, "blanc_plaque", 5)
	# bandeau de vitres des flancs
	var n_v: int = int(absf(zl - z0) / 1.65) - 1
	for sx in [-1.0, 1.0]:
		for k in range(n_v):
			RemonteeKit.boite_en(g, Vector3(0.05, 0.80, 1.40), Vector3(sx * (Ro + 0.01), y0 + 1.70, z0 + sg * (1.4 + 1.65 * k)), "vitrage_sombre")
	_noms_flancs(g, Ro, y0 + 0.75, (z0 + zl) * 0.5, Color(0.20, 0.21, 0.24), false)
	# entonnoir sous la poulie (carter de l'arbre)
	RemonteeKit.cylindre(g, R * 0.30, R * 0.62, 0.75, Transform3D(Basis.IDENTITY, Vector3(0, y0 - 0.375, zc)), "blanc_plaque", 20)
	_poteau(g, zc, lg.H_CABLE_GARE - 0.35, "peinture_anthracite", false, 0.50)
	_poteau(g, z_colonne(znez, zc), y0, "peinture_anthracite", false, 0.45)


## Poma / Ingélo récents (photos du Marais et de la Daille) : bandeau droit
## (blanc à Tignes, noir à Val d'Isère avec un liseré rouge) sous une voûte
## noire en berceau, bout arrondi autour de la poulie, lanterneaux sur la
## voûte ; poteaux carrés gris.
func _poma_moderne(g: Node3D, znez: float, zc: float) -> void:
	var sg: float = signf(zc - znez)
	var R: float = lg.voie * 0.5
	var Ro: float = R + LigneRemontee.D_CAPOT + elarg
	var y0: float = lg.H_CABLE_GARE + LigneRemontee.Y_CAPOT
	var z0: float = znez - sg * 0.6
	var hb: float = 1.40
	var ht: float = 2.75
	var prof: Array = [[Ro, 0.0], [Ro, hb]]
	prof.append_array(_voute(Ro, hb, ht, 2.1))
	var bandeau: String = "toit_noir" if _val() else _coque()
	var mat := func(h: float) -> String:
		return bandeau if h < hb else "toit_noir"
	_balayer(prof, y0, z0, zc, mat)
	# le bout autour de la poulie est une grande verrière sombre (photo du Marais)
	var mat2 := func(h: float, phi: float) -> String:
		if h > hb + 0.08 and h < ht - 0.25 and phi > 0.22 and phi < PI - 0.22:
			return "vitrage_sombre"
		return mat.call(h)
	_tourner(prof, y0, zc, sg, 0.0, PI, 28, mat2)
	_face(prof, y0, z0, mat)
	_dessous(y0, z0, zc, sg, R, Ro, zc, bandeau)
	_valider(g, "Capot")
	# liseré au haut du bandeau (rouge à Val d'Isère, gris clair à Tignes)
	var lis: String = "rouge_val" if _val() else "alu_pince"
	var pts: PackedVector3Array = PackedVector3Array()
	pts.append(Vector3(Ro + 0.03, y0 + hb, z0))
	pts.append_array(RemonteeKit.arc(Vector3(0, y0 + hb, zc), Vector3.RIGHT, Vector3(0, 0, sg), Ro + 0.03, 0.0, PI, 24))
	pts.append(Vector3(-Ro - 0.03, y0 + hb, z0))
	RemonteeKit.tube(g, pts, 0.06, lis, 6)
	# lanterneaux : panneaux vitrés couchés sur la voûte
	var n_l: int = int(absf(zc - z0) / 4.5)
	for sx in [-1.0, 1.0]:
		var a: float = 0.95
		var r: float = Ro * pow(cos(a), 2.0 / 2.1) + 0.03
		var h: float = hb + (ht - hb) * pow(sin(a), 2.0 / 2.1)
		var b: Basis = Basis(Vector3.BACK, sx * 0.62)
		for k in range(n_l):
			RemonteeKit.boite(g, Vector3(1.2, 0.04, 2.2), Transform3D(b, Vector3(sx * r, y0 + h, z0 + sg * (2.5 + 4.5 * k))), "vitrage_sombre")
	var coul: Color = Color(0.96, 0.96, 0.96) if _val() else Color(0.12, 0.18, 0.55)
	_noms_flancs(g, Ro, y0 + 0.70, (z0 + zc) * 0.5 - sg * 3.0, coul)
	for sx in [-1.0, 1.0]:
		_nom(g, "VAL D'ISÈRE" if _val() else "TIGNES", Vector3(sx * (Ro + 0.03), y0 + 0.70, (z0 + zc) * 0.5 + sg * 6.0), sx * PI * 0.5, Color(0.80, 0.10, 0.12))
	_poteau(g, zc, lg.H_CABLE_GARE - 0.35, "peinture_gris", false, 0.45)
	_poteau(g, z_colonne(znez, zc), y0, "peinture_gris", false, 0.40)


## Garaventa (photos du Glacier) : fût arrondi à bandeau de vitres et
## liseré rouge, terminé au-dessus de la poulie par un grand dôme blanc à
## facettes, plus large et plus haut que le fût ; colonnes rondes blanches.
func _garaventa(g: Node3D, znez: float, zc: float) -> void:
	var sg: float = signf(zc - znez)
	var R: float = lg.voie * 0.5
	var Ro: float = R + LigneRemontee.D_CAPOT + elarg
	var y0: float = lg.H_CABLE_GARE + LigneRemontee.Y_CAPOT
	var z0: float = znez - sg * 0.6
	var prof: Array = [[Ro, 0.0], [Ro, 0.5]]
	prof.append_array(_voute(Ro, 0.5, 2.35, 2.3))
	var blanc := func(_h: float) -> String: return "blanc_plaque"
	var blanc2 := func(_h: float, _p: float) -> String: return "blanc_plaque"
	_balayer(prof, y0, z0, zc, blanc)
	_face(prof, y0, z0, blanc)
	_dessous(y0, z0, zc, sg, R, Ro, zc, "blanc_plaque")
	# dôme : jupe droite puis calotte, tour complet, à facettes
	var Rd: float = Ro + 0.45
	var dome: Array = [[Rd, -0.25], [Rd, 0.95]]
	for i in range(1, 9):
		var a: float = PI * 0.5 * float(i) / 8
		dome.append([Rd * cos(a), 0.95 + 2.45 * sin(a)])
	_tourner(dome, y0, zc, sg, 0.0, TAU, 18, blanc2, true)
	# dessous du dôme (anneau au-delà de la fente) ; le fût s'y arrête
	var n: int = 36
	for k in range(n):
		var p0: float = TAU * float(k) / n
		var p1: float = TAU * float(k + 1) / n
		var c0: Vector3 = Vector3(cos(p0), 0, sin(p0))
		var c1: Vector3 = Vector3(cos(p1), 0, sin(p1))
		var o: Vector3 = Vector3(0, y0 - 0.25, zc)
		_quad("blanc_plaque", o + c0 * (R + 0.6), o + c0 * Rd, o + c1 * Rd, o + c1 * (R + 0.6), true)
		_quad("blanc_plaque", o + c0 * (R - 0.55), o + c1 * (R - 0.55), o, o, true)
	_valider(g, "Capot")
	# liserés rouges : autour du dôme et le long du fût
	RemonteeKit.tube(g, RemonteeKit.arc(Vector3(0, y0 + 0.75, zc), Vector3.RIGHT, Vector3.BACK, Rd + 0.02, 0.0, TAU, 36), 0.05, "rouge_val", 5)
	for sx in [-1.0, 1.0]:
		var ze: float = zc - sg * Rd * 0.85
		RemonteeKit.barre(g, Vector3(sx * (Ro + 0.02), y0 + 0.35, z0), Vector3(sx * (Ro + 0.02), y0 + 0.35, ze), 0.04, "rouge_val", 5)
		# bandeau de vitres haut sur le fût
		var rv: float = _r_a(prof, 1.55)
		var n_v: int = int(absf(ze - z0) / 1.7)
		for k in range(n_v):
			var b: Basis = Basis(Vector3.BACK, sx * 0.35)
			RemonteeKit.boite(g, Vector3(0.05, 0.55, 1.45), Transform3D(b, Vector3(sx * (rv + 0.02), y0 + 1.55, z0 + sg * (1.0 + 1.7 * k))), "vitrage_sombre")
	_noms_flancs(g, Ro, y0 + 0.80, (z0 + zc) * 0.5 - sg * 2.0, Color(0.62, 0.08, 0.10), false)
	for sx in [-1.0, 1.0]:
		_nom(g, "Val d'Isère" if _val() else lg.station, Vector3(sx * (Rd + 0.04), y0 + 0.40, zc), sx * PI * 0.5, Color(0.70, 0.08, 0.10))
	_poteau(g, zc, lg.H_CABLE_GARE - 0.35, "blanc_plaque", true, 0.60)
	_poteau(g, z_colonne(znez, zc), y0, "blanc_plaque", true, 0.45)


## Leitner récent (photos de l'Aiguille Percée) : caisse blanche « en
## baignoire » aux flancs évasés vers le haut et aux bouts arrondis,
## couverture noire bombée à nervures qui déborde à peine, joints
## verticaux des panneaux, grand nom bleu sur le flanc ; poteau gris.
func _leitner(g: Node3D, znez: float, zc: float) -> void:
	var sg: float = signf(zc - znez)
	var R: float = lg.voie * 0.5
	var Ro: float = R + LigneRemontee.D_CAPOT + elarg
	var y0: float = lg.H_CABLE_GARE + LigneRemontee.Y_CAPOT
	var z0: float = znez - sg * 0.6
	var hb: float = 1.45
	var prof: Array = [[Ro - 0.35, 0.0], [Ro - 0.05, 0.25], [Ro + 0.30, hb], [Ro + 0.18, hb + 0.08]]
	prof.append_array(_voute(Ro + 0.18, hb + 0.08, 2.85, 2.4, 10))
	var mat := func(h: float) -> String:
		return "blanc_plaque" if h < hb + 0.04 else "toit_noir"
	var mat2 := func(h: float, _phi: float) -> String: return mat.call(h)
	# nez arrondi aussi : un quart de tour à chaque coin, face plane entre les deux
	var rc: float = 1.6
	var zf: float = z0 + sg * rc
	var prof_c: Array = []
	for p in prof:
		prof_c.append([maxf(float(p[0]) - (Ro - rc), 0.0), p[1]])
	_balayer(prof, y0, zf, zc, mat)
	_tourner(prof, y0, zc, sg, 0.0, PI, 30, mat2)
	for sx in [-1.0, 1.0]:
		var ox2: float = sx * (Ro - rc)
		for k in range(8):
			var q0: float = PI * 0.5 * float(k) / 8
			var q1: float = PI * 0.5 * float(k + 1) / 8
			for i in range(prof_c.size() - 1):
				var a3: Array = prof_c[i]
				var b3: Array = prof_c[i + 1]
				var m3: String = mat.call((float(a3[1]) + float(b3[1])) * 0.5)
				var pt3 := func(r: float, h: float, phi: float) -> Vector3:
					return Vector3(ox2 + sx * r * cos(phi), y0 + h, zf - sg * r * sin(phi))
				_quad(m3, pt3.call(a3[0], a3[1], q0), pt3.call(b3[0], b3[1], q0), pt3.call(b3[0], b3[1], q1), pt3.call(a3[0], a3[1], q1))
	for i in range(prof_c.size() - 1):
		var a4: Array = prof_c[i]
		var b4: Array = prof_c[i + 1]
		var x4: float = Ro - rc
		_quad(mat.call((float(a4[1]) + float(b4[1])) * 0.5), Vector3(-x4, y0 + a4[1], zf - sg * float(a4[0])), Vector3(x4, y0 + a4[1], zf - sg * float(a4[0])),
			Vector3(x4, y0 + b4[1], zf - sg * float(b4[0])), Vector3(-x4, y0 + b4[1], zf - sg * float(b4[0])))
	_dessous(y0, zf - sg * (rc - 0.35), zc, sg, R, Ro - 0.35, zc, "blanc_plaque")
	_valider(g, "Capot")
	# nervures de la couverture : arcs en travers, tous les 1,6 m
	var n_n: int = int(absf(zc - zf) / 1.6)
	var voute: Array = prof.slice(3)
	for k in range(n_n + 1):
		var z: float = zf + sg * 1.6 * k
		var pts: PackedVector3Array = PackedVector3Array()
		for p in voute:
			pts.append(Vector3(float(p[0]) + 0.03, y0 + float(p[1]) + 0.03, z))
		for i in range(voute.size() - 2, -1, -1):
			pts.append(Vector3(-float(voute[i][0]) - 0.03, y0 + float(voute[i][1]) + 0.03, z))
		RemonteeKit.tube(g, pts, 0.035, "acier_noir", 5)
	# joints verticaux des panneaux blancs
	for sx in [-1.0, 1.0]:
		for k in range(1, int(absf(zc - zf) / 2.4) + 1):
			var zj: float = zf + sg * 2.4 * k
			RemonteeKit.barre(g, Vector3(sx * (Ro - 0.33), y0 + 0.02, zj), Vector3(sx * (Ro + 0.31), y0 + hb - 0.02, zj), 0.012, "peinture_gris", 4)
	_noms_flancs(g, Ro + 0.12, y0 + 0.75, (zf + zc) * 0.5, Color(0.16, 0.24, 0.62))
	_poteau(g, zc, lg.H_CABLE_GARE - 0.35, "galva", true, 0.50)
	_poteau(g, z_colonne(znez, zc), y0, "galva", true, 0.42)


## Bâtiment d'une gare de télécabine (photos de la Daille, de Tovière, de
## Solaise, des Brévières) : à côté du quai, côté embarquement, un chalet
## à soubassement de pierre et étage bardé de mélèze, grandes baies sur le
## quai, toit à deux pans couvert de lauzes sombres ; les fondations
## descendent dans le talus.
static func emprise_batiment(lg: LigneRemontee, aval: bool) -> Array:
	var L: float = lg.longueur_h()
	var znez: float = 0.0 if aval else -L
	var sg: float = 1.0 if aval else -1.0
	var xb: float = signf(lg._x_brin(aval))
	var w: float = 7.5
	var x: float = xb * (lg.voie * 0.5 + LigneRemontee.D_CAPOT + 1.2 + w * 0.5)
	var z0: float = znez + sg * 3.0
	var z1: float = znez + sg * (lg.l_gare - 1.0)
	# [centre au sol, taille (x, y, z), côté du quai]
	return [Vector3(x, 0.0, (z0 + z1) * 0.5), Vector3(w, 6.2, absf(z1 - z0)), xb]


func batiment(g: Node3D, aval: bool) -> void:
	var e: Array = emprise_batiment(lg, aval)
	var c: Vector3 = e[0]
	var t: Vector3 = e[1]
	var xb: float = e[2]
	var h0: float = 3.4                     # soubassement de pierre
	RemonteeKit.boite_en(g, Vector3(t.x, h0 + 4.0, t.z), c + Vector3(0, (h0 - 4.0) * 0.5, 0), "pierre")
	RemonteeKit.boite_en(g, Vector3(t.x - 0.2, t.y - h0, t.z - 0.2), c + Vector3(0, h0 + (t.y - h0) * 0.5, 0), "bois_meleze")
	# toit à deux pans (faîtage dans la longueur), débord de 0,8 m
	var pente: float = 0.45
	var demi: float = t.x * 0.5 + 0.8
	var lp: float = demi / cos(pente)
	for sx in [-1.0, 1.0]:
		var b: Basis = Basis(Vector3.BACK, -sx * pente)
		RemonteeKit.boite(g, Vector3(lp, 0.22, t.z + 1.6), Transform3D(b, c + Vector3(sx * demi * 0.5, t.y + demi * tan(pente) * 0.5, 0)), "toit_bardeaux")
	# pignons en bois
	for sz in [-1.0, 1.0]:
		var zp: float = c.z + sz * t.z * 0.5
		var pts: PackedVector3Array = PackedVector3Array()
		var hp: float = demi * tan(pente)
		for k in range(7):
			var u: float = float(k) / 6.0
			var x: float = lerpf(-t.x * 0.5, t.x * 0.5, u)
			var y: float = t.y + hp * (1.0 - absf(x) / demi) - 0.1
			RemonteeKit.boite_en(g, Vector3(t.x / 6.0, maxf(y - t.y, 0.05), 0.12), Vector3(c.x + x, t.y + maxf(y - t.y, 0.05) * 0.5, zp), "bois_meleze")
	# baies vitrées côté quai (rez-de-chaussée) et fenêtres de l'étage
	var xf: float = c.x - xb * (t.x * 0.5 + 0.02)
	var n: int = int(t.z / 3.0)
	for k in range(n):
		var z: float = c.z - t.z * 0.5 + 1.5 + 3.0 * k
		RemonteeKit.boite_en(g, Vector3(0.05, 2.3, 2.3), Vector3(xf, 1.35, z), "vitrage_sombre")
		RemonteeKit.boite_en(g, Vector3(0.05, 1.1, 1.3), Vector3(xf + xb * 0.1, h0 + 1.3, z), "vitrage_sombre")
	# porte vers les portillons et nom de la ligne au-dessus
	var zr: float = c.z + signf(c.z - (0.0 if aval else -lg.longueur_h())) * (t.z * 0.5 + 0.02)
	RemonteeKit.boite_en(g, Vector3(2.2, 2.5, 0.05), Vector3(c.x, 1.25, zr), "vitrage_sombre")
	_nom(g, lg.nom_court(), Vector3(c.x, h0 + 0.6, zr + signf(zr - c.z) * 0.03), 0.0 if zr > c.z else PI, Color(0.95, 0.95, 0.95), 0.0035)


## Téléski : la poulie à l'air, portée par un portique galvanisé (deux
## jambes en A et une traverse), le motoréducteur sous un capot gris au-dessus
## de la poulie ; protections en mousse au pied des jambes.
func _teleski(g: Node3D, znez: float, zc: float) -> void:
	var sg: float = signf(zc - znez)
	var R: float = lg.voie * 0.5
	var yb: float = lg.H_CABLE_GARE + 0.55
	# traverse en caisson au-dessus de la poulie, en long
	RemonteeKit.boite_en(g, Vector3(0.40, 0.45, R * 2.0 + 1.6), Vector3(0, yb, zc), "galva")
	# jambes en A, en dehors de la boucle des perches
	for sz in [-1.0, 1.0]:
		var top: Vector3 = Vector3(0, yb, zc + sz * (R + 0.6))
		for sx in [-1.0, 1.0]:
			var pied: Vector3 = Vector3(sx * 1.6, 0.0, zc + sz * (R + 1.4))
			RemonteeKit.poutre(g, pied, top, 0.18, 0.18, "galva")
			RemonteeKit.cylindre(g, 0.22, 0.22, 1.6, Transform3D(Basis.IDENTITY, pied + Vector3(0, 0.8, 0)), "mousse_rouge", 12)
	# axe de la poulie et capot du motoréducteur
	RemonteeKit.cylindre(g, 0.12, 0.12, 0.6, Transform3D(Basis.IDENTITY, Vector3(0, lg.H_CABLE_GARE + 0.2, zc)), "acier", 12)
	RemonteeKit.boite_en(g, Vector3(1.2, 0.9, 1.5), Vector3(0, yb + 0.68, zc), "peinture_gris")
	RemonteeKit.boite_en(g, Vector3(1.3, 0.06, 1.6), Vector3(0, yb + 1.15, zc), "acier_noir")
	if lg.nom_court() != "":
		_nom(g, lg.nom_court(), Vector3(0, yb + 0.70, zc - sg * 0.77), 0.0 if sg < 0.0 else PI, Color(0.15, 0.15, 0.17), 0.0018)


## Télésiège à pinces fixes (photos du Grand Pré) : pas de carénage sur la
## boucle ; poulie à l'air sous un bâti d'acier noir porté par un poteau,
## local blanc vitré de la motrice au-dessus de la poulie.
func _fixe(g: Node3D, znez: float, zc: float) -> void:
	var sg: float = signf(zc - znez)
	var R: float = lg.voie * 0.5
	var yb: float = lg.H_CABLE_GARE + 0.75           # dessus de la poutre maîtresse
	var zp: float = z_colonne(znez, zc)
	# poutre maîtresse en caisson, du poteau du quai jusqu'au-delà de la poulie
	RemonteeKit.boite_en(g, Vector3(0.55, 0.70, absf(zc - zp) + 2.0), Vector3(0, yb - 0.35, (zc + zp) * 0.5 + sg * 0.5), "acier_noir")
	# traverse au-dessus de la poulie
	RemonteeKit.boite_en(g, Vector3(R * 1.3, 0.45, 0.45), Vector3(0, yb - 0.22, zc), "acier_noir")
	# local de la motrice : caisse blanche vitrée, toit débordant noir
	var c: Vector3 = Vector3(0, yb, zc + sg * 0.6)
	var t: Vector3 = Vector3(3.4, 2.3, 4.6)
	RemonteeKit.boite_en(g, t, c + Vector3(0, t.y * 0.5, 0), "blanc_plaque")
	RemonteeKit.boite_en(g, Vector3(t.x + 0.5, 0.18, t.z + 0.5), c + Vector3(0, t.y + 0.09, 0), "acier_noir")
	for sx in [-1.0, 1.0]:
		RemonteeKit.boite_en(g, Vector3(0.05, 0.9, t.z * 0.75), c + Vector3(sx * (t.x * 0.5 + 0.01), 1.45, 0), "vitrage_sombre")
	RemonteeKit.boite_en(g, Vector3(t.x * 0.7, 0.9, 0.05), c + Vector3(0, 1.45, -sg * (t.z * 0.5 + 0.01)), "vitrage_sombre")
	_nom(g, lg.nom_court(), c + Vector3(0, 0.45, -sg * (t.z * 0.5 + 0.03)), 0.0 if sg < 0.0 else PI, Color(0.12, 0.12, 0.14), 0.0022)
	# poteaux noirs : sous la poulie, au quai
	_poteau(g, zc, lg.H_CABLE_GARE - 0.35, "acier_noir", false, 0.38)
	_poteau(g, zp, yb - 0.7, "acier_noir", false, 0.32)
	# jambe de force inclinée vers la poulie
	RemonteeKit.poutre(g, Vector3(0, 0.0, zp + sg * 2.5), Vector3(0, yb - 0.7, zp + sg * 6.0), 0.30, 0.30, "acier_noir")
