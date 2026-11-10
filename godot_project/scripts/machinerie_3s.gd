class_name Machinerie3S
extends RefCounted
## Câble tracteur de l'Olympique dans ses gares (retour d'utilisateur, 25/10/2026,
## d'après sa visite : « la salle des machines est en haut, derrière la salle
## d'embarquement ; en bas, juste le contrepoids, derrière aussi ») — la fiche
## technique confirme : motrice amont (deux moteurs à courant continu, 2 × 785 kW,
## sous la gare, poulie motrice Ø 4,80 m), tension aval par contrepoids.
##
## AVAL : le tracteur file derrière le demi-tour des cabines ; une grande
## poulie bleue verticale, sur chevalet rouge (dans l'axe de la ligne) le renvoie à la verticale
## vers le bas ; deux poulies du chariot de contrepoids, au plan tourné de 90°
## (en travers de la ligne), le font passer à l'horizontale vers l'autre voie
## puis remonter ; une seconde poulie bleue le remet à l'horizontale sur
## l'autre voie. Le bloc de contrepoids pend sous le chariot, dans une fosse.
##
## AMONT : au fond de la salle, deux poulies inclinées font plonger le câble vers une seule poulie motrice
## verticale, sous le plancher, qu'il contourne par le bas après s'être croisé en 8, avec son réducteur et ses freins.

var lg: LigneRemontee

const BLEU: String = "bleu_doppelmayr"
const R_ROUGE: float = 2.0            # poulies de renvoi verticales (aval), sommet sous le plafond (estimé sur photo, ±20 %)
const R_CHARIOT: float = 1.5          # poulies du chariot de contrepoids
const R_INCLINEE: float = 2.0         # poulies de renvoi inclinées (amont, estimé sur photo, ±20 %)
const R_MOTRICE: float = 2.4          # poulie motrice Ø 4,80 m
const RECUL: float = 11.0             # du centre du demi-tour aux renvois
const PROF_FOSSE: float = 7.5         # sous le plancher : fond du chariot de contrepoids
const PROF_MOTRICE: float = 0.6       # du plancher au sommet de la poulie motrice
const H_QUAI: float = 0.25           # quais au niveau du plancher des cabines
const DEMI_TRANCHEE: float = 1.65     # demi-largeur du chemin des cabines
const FOND_GARE: float = 17.0        # du centre du demi-tour au fond du bâtiment
const DZ_CROISEMENT: float = 0.07    # demi-écart des deux brins au croisement en 8 (amont)


func _init(l: LigneRemontee) -> void:
	lg = l


func _zc(aval: bool) -> float:
	return lg.l_gare if aval else -lg.longueur_h() - lg.l_gare


func _sg(aval: bool) -> float:
	return 1.0 if aval else -1.0


## Hauteur du tracteur en gare (repère de la ligne).
func y_tracteur(aval: bool) -> float:
	return lg.terrain(0.0 if aval else lg.longueur_h()) + lg.H_CABLE_GARE + VehiculeRemontee.Y_TRACTEUR_3S


func y_plancher(aval: bool) -> float:
	return lg.terrain(0.0 if aval else lg.longueur_h())


## Centre de la motrice (repère de la ligne).
func y_motrice() -> float:
	return y_plancher(false) - PROF_MOTRICE - R_MOTRICE


## Dessous du toit de la gare (repère de la ligne).
func y_plafond(aval: bool) -> float:
	return y_plancher(aval) + float(lg._emprise_3s(aval)[3]) - 0.2


## Ouverture dans le plancher (repère de la ligne) : [x0, x1, z0, z1].
func fosse(aval: bool) -> Array:
	var zc: float = _zc(aval)
	var sg: float = _sg(aval)
	var rp: float = lg.rayon_poulie()
	if aval:
		var zr: float = zc + sg * RECUL
		return [-(rp + 0.8), rp + 0.8, zr - R_ROUGE - 0.6, zr + 1.0]
	var z0: float = zc + sg * (RECUL - 3.0)
	var z1: float = zc + sg * (RECUL + 3.2)
	return [-(rp + 0.8), rp + 0.8, minf(z0, z1), maxf(z0, z1)]


# --- tracé ----------------------------------------------------------------------------

## Points du tracteur derrière le demi-tour, de la voie `x_de` à la voie
## `x_vers` (dans le sens de la boucle), repère de la ligne. Les poulies
## rencontrées sont ajoutées à `poulies` : [centre, normale, rayon, matière].
func trace(aval: bool, x_de: float, x_vers: float, poulies: Array) -> PackedVector3Array:
	var zc: float = _zc(aval)
	var sg: float = _sg(aval)
	var y: float = y_tracteur(aval)
	var out: PackedVector3Array = PackedVector3Array()
	if aval:
		# le câble remonte du demi-tour au sommet des poulies rouges, juste
		# sous le plafond (retour d'utilisateur, 25/10/2026)
		var zr: float = zc + sg * RECUL
		var yb: float = y_plancher(true) - PROF_FOSSE
		var yh: float = y_plafond(true) - 1.05
		var coins: Array = [
			[Vector3(x_de, y, zc), 0.0, ""],
			[Vector3(x_de, yh, zr), R_ROUGE, BLEU],
			[Vector3(x_de, yb, zr), R_CHARIOT, "peinture_gris"],
			[Vector3(x_vers, yb, zr), R_CHARIOT, "peinture_gris"],
			[Vector3(x_vers, yh, zr), R_ROUGE, BLEU],
			[Vector3(x_vers, y, zc), 0.0, ""],
		]
		return _polyligne(coins, poulies)
	# amont : deux renvois inclinés amènent le câble dans le plan de la motrice verticale. Les brins se croisent
	# en 8 entre les renvois et la motrice, chacun tangent à la motrice du côté opposé à sa voie : l'enroulement
	# passe de 150° à 273° (Olympique), plus de contact pour l'adhérence, et la motrice tourne dans l'autre sens
	# (retour d'utilisateur, 06/11/2026). Les deux brins sont décalés de ±DZ_CROISEMENT de part et d'autre du
	# plan de la motrice pour ne pas se toucher au croisement ; chaque renvoi s'incline dans le plan de son brin
	# (axe à 46° de l'horizontale au lieu de 15°).
	var zs: float = zc + sg * RECUL
	var yw: float = y_motrice()
	var cw: Vector2 = Vector2(0.0, yw)
	var ta: Vector2 = _tangente(Vector2(x_de, y), cw, R_MOTRICE, -signf(x_de))
	var tb: Vector2 = _tangente(Vector2(x_vers, y), cw, R_MOTRICE, -signf(x_vers))
	var za: float = zs - sg * DZ_CROISEMENT
	var zb: float = zs + sg * DZ_CROISEMENT
	var ka: Vector3 = Vector3(x_de, y, za)
	var kb: Vector3 = Vector3(x_vers, y, zb)
	var pa: Vector3 = Vector3(ta.x, ta.y, za)
	var pb: Vector3 = Vector3(tb.x, tb.y, zb)
	out.append(Vector3(x_de, y, zc))
	out.append_array(_conge(ka, Vector3(0, 0, sg), (pa - ka).normalized(), R_INCLINEE, BLEU, poulies))
	# enroulement de ta à tb par le bas
	var a0: float = atan2(ta.y - cw.y, ta.x - cw.x)
	var a1: float = atan2(tb.y - cw.y, tb.x - cw.x)
	var da: float = wrapf(a1 - a0, -PI, PI)
	if absf(wrapf(a0 + da * 0.5 + PI * 0.5, -PI, PI)) > PI * 0.5:
		da = da - signf(da) * TAU
	var n: int = 40
	for k in range(n + 1):
		var a: float = a0 + da * float(k) / n
		out.append(Vector3(cw.x + cos(a) * R_MOTRICE, cw.y + sin(a) * R_MOTRICE, lerpf(za, zb, float(k) / n)))
	poulies.append([Vector3(0, yw, zs), Vector3.BACK * signf(da), R_MOTRICE, BLEU, true])
	out.append_array(_conge(kb, (kb - pb).normalized(), Vector3(0, 0, -sg), R_INCLINEE, BLEU, poulies))
	out.append(Vector3(x_vers, y, zc))
	return out


## Point de tangence (en plan) d'une droite issue de p sur le cercle (c, r),
## du côté x de signe `cote` par rapport au centre.
func _tangente(p: Vector2, c: Vector2, r: float, cote: float) -> Vector2:
	var d: Vector2 = p - c
	var l: float = d.length()
	var a: float = acos(clampf(r / maxf(l, r + 0.01), -1.0, 1.0))
	var b: float = atan2(d.y, d.x)
	var t1: Vector2 = c + Vector2(cos(b + a), sin(b + a)) * r
	var t2: Vector2 = c + Vector2(cos(b - a), sin(b - a)) * r
	return t1 if signf(t1.x - c.x) == cote else t2


## Polyligne à coins arrondis (congés = poulies) : [[coin, rayon, matière], …].
func _polyligne(coins: Array, poulies: Array) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	out.append(coins[0][0])
	for i in range(1, coins.size() - 1):
		var k: Vector3 = coins[i][0]
		var din: Vector3 = (k - (coins[i - 1][0] as Vector3)).normalized()
		var dout: Vector3 = ((coins[i + 1][0] as Vector3) - k).normalized()
		out.append_array(_conge(k, din, dout, float(coins[i][1]), String(coins[i][2]), poulies))
	out.append(coins[coins.size() - 1][0])
	return out


## Arc tangent aux deux droites qui se coupent en k (direction d'arrivée,
## de départ), de rayon r : la poulie de renvoi qui porte le câble.
func _conge(k: Vector3, din: Vector3, dout: Vector3, r: float, m: String, poulies: Array) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var th: float = din.angle_to(dout)
	if th < 0.01:
		out.append(k)
		return out
	var n: Vector3 = din.cross(dout).normalized()
	var t: float = r * tan(th * 0.5)
	var t1: Vector3 = k - din * t
	var c: Vector3 = t1 + n.cross(din) * r
	var v: Vector3 = t1 - c
	var nb: int = maxi(4, int(th / 0.08))
	for j in range(nb + 1):
		out.append(c + v.rotated(n, th * float(j) / nb))
	poulies.append([c, n, r, m, false])
	return out


# --- matériel ---------------------------------------------------------------------------

## Poulies (nœuds tournants, axe local Y = axe de la poulie), chariot et
## bloc de contrepoids, moteurs, fosses et garde-corps. `parent` : repère
## de la ligne. Rend [nœud, vitesse angulaire] des poulies.
## `pause` (facultative) attendue après chaque poulie : 24 ms d'un bloc pour les quatre (relevé du 07/11/2026).
func construire(parent: Node3D, poulies: Array, pause: Callable = Callable()) -> Array:
	var tournantes: Array = []
	for p in poulies:
		if pause.is_valid() and not tournantes.is_empty():
			await pause.call()
		var c: Vector3 = p[0]
		var ax: Vector3 = p[1]
		var r: float = p[2]
		var nd: Node3D = Node3D.new()
		nd.name = "PoulieMotrice" if bool(p[4]) else "PoulieRenvoi"
		var x: Vector3 = ax.cross(Vector3.FORWARD if absf(ax.z) < 0.9 else Vector3.RIGHT).normalized()
		var z: Vector3 = x.cross(ax).normalized()
		nd.transform = Transform3D(Basis(x, ax, z), c)
		parent.add_child(nd)
		if String(p[3]) == BLEU:
			_roue_ajouree(nd, r, BLEU)
		else:
			_roue(nd, r, String(p[3]), bool(p[4]))
		MeshMerge.merge(nd, [], "Roue")
		tournantes.append([nd, lg.vitesse / r])
		# axe et paliers (fixes)
		var pal: Node3D = Node3D.new()
		pal.transform = nd.transform
		parent.add_child(pal)
		RemonteeKit.cylindre(pal, 0.14, 0.14, 0.9, Transform3D.IDENTITY, "acier", 12)
		for s in [-1.0, 1.0]:
			RemonteeKit.boite_en(pal, Vector3(0.5, 0.25, 0.5), Vector3(0, s * 0.42, 0), "peinture_anthracite")
		if String(p[3]) == BLEU and not bool(p[4]):
			var aval: bool = c.z > -lg.longueur_h() * 0.5
			_chevalet(parent, c, ax, r, y_plancher(aval))
		elif bool(p[4]):
			_chevalet(parent, c, ax, r, c.y - r - 0.8)
	return tournantes


## Roue de poulie dans son plan local XZ : jante à gorge, rayons, moyeu.
func _roue(nd: Node3D, r: float, m: String, motrice: bool) -> void:
	RemonteeKit.tube(nd, RemonteeKit.arc(Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, r + 0.03, 0.0, TAU, 56), 0.05, "caoutchouc", 8)
	for dy in [-0.09, 0.09]:
		RemonteeKit.tube(nd, RemonteeKit.arc(Vector3(0, dy, 0), Vector3.RIGHT, Vector3.BACK, r + 0.09, 0.0, TAU, 56), 0.035, m, 6)
	var nr: int = 10 if motrice else 8
	for k in range(nr):
		var a: float = TAU * (k + 0.5) / nr
		var d: Vector3 = Vector3(cos(a), 0, sin(a))
		RemonteeKit.poutre(nd, d * 0.35, d * (r - 0.05), 0.12, 0.10 if not motrice else 0.20, m)
	RemonteeKit.cylindre(nd, 0.38, 0.38, 0.36 if not motrice else 0.6, Transform3D.IDENTITY, m, 20)
	if motrice:
		# couronne dentée du réducteur, sous la jante
		RemonteeKit.tube(nd, RemonteeKit.arc(Vector3(0, -0.35, 0), Vector3.RIGHT, Vector3.BACK, r * 0.7, 0.0, TAU, 48), 0.08, "acier_noir", 8)


## Roue dans son plan local XZ : voile bleu à quatre grands trous ovales, jante et gorge. Les trous font voir sa
## rotation, sens compris, sans objet ni matière de plus.
func _roue_ajouree(nd: Node3D, r: float, m: String) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var e: float = 0.09
	var rc: float = r * 0.60
	var hr: float = r * 0.215
	var alpha: float = PI * 0.25 * 0.70
	var pt := func(rho: float, a: float, y: float) -> Vector3:
		return Vector3(cos(a) * rho, y, sin(a) * rho)
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		for v in [a, b, c, a, c, d, a, c, b, a, d, c]:
			st.add_vertex(v)
	var bornes := func(a: float) -> Vector2:
		var u: float = wrapf(a - PI * 0.25, -PI * 0.25, PI * 0.25) if false else wrapf(a, 0.0, PI * 0.5) - PI * 0.25
		var t: float = absf(u) / alpha
		if t >= 1.0:
			return Vector2(rc, rc)
		var ha: float = hr * sqrt(1.0 - t * t)
		return Vector2(rc - ha, rc + ha)
	var nb: int = 64
	for k in range(nb):
		var a0: float = TAU * k / nb
		var a1: float = TAU * (k + 1) / nb
		var b0: Vector2 = bornes.call(a0)
		var b1: Vector2 = bornes.call(a1)
		for y in [-e, e]:
			quad.call(pt.call(0.0, a0, y), pt.call(b0.x, a0, y), pt.call(b1.x, a1, y), pt.call(0.0, a1, y))
			quad.call(pt.call(b0.y, a0, y), pt.call(r, a0, y), pt.call(r, a1, y), pt.call(b1.y, a1, y))
		if b0.y - b0.x > 0.001 or b1.y - b1.x > 0.001:
			quad.call(pt.call(b0.x, a0, -e), pt.call(b0.x, a0, e), pt.call(b1.x, a1, e), pt.call(b1.x, a1, -e))
			quad.call(pt.call(b0.y, a0, -e), pt.call(b0.y, a0, e), pt.call(b1.y, a1, e), pt.call(b1.y, a1, -e))
		quad.call(pt.call(r, a0, -e), pt.call(r, a0, e), pt.call(r, a1, e), pt.call(r, a1, -e))
	st.generate_normals()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = MeshMerge.valider_indexe_retenu(st)
	mi.material_override = RemonteeKit.mat(m)
	nd.add_child(mi)
	# flasques rouges de la gorge, garniture noire
	RemonteeKit.tube(nd, RemonteeKit.arc(Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, r + 0.02, 0.0, TAU, 48), 0.045, "caoutchouc", 6)
	for dy in [-0.08, 0.08]:
		RemonteeKit.tube(nd, RemonteeKit.arc(Vector3(0, dy, 0), Vector3.RIGHT, Vector3.BACK, r + 0.05, 0.0, TAU, 48), 0.03, "cabine_rouge", 6)
	RemonteeKit.cylindre(nd, r * 0.17, r * 0.17, 0.30, Transform3D.IDENTITY, m, 16)


## Chevalet rouge en A autour du palier, sur sa traverse : `c` centre de la roue, `ax` son axe, le tout dans le
## repère de la ligne. Posé sur deux montants jusqu'au plancher `y_sol`, si la roue est au-dessus.
func _chevalet(parent: Node3D, c: Vector3, ax: Vector3, r: float, y_sol: float) -> void:
	var u: Vector3 = (Vector3.UP - ax * ax.dot(Vector3.UP)).normalized()
	var v: Vector3 = ax.cross(u).normalized()
	var m: String = "cabine_rouge"
	for s in [-1.0, 1.0]:
		var o: Vector3 = ax * (s * 0.32)
		var haut: Vector3 = c + o + u * (r + 0.15)
		RemonteeKit.poutre(parent, c + o + v * (r * 0.62) - u * 0.08, haut, 0.14, 0.12, m, ax)
		RemonteeKit.poutre(parent, c + o - v * (r * 0.62) - u * 0.08, haut, 0.14, 0.12, m, ax)
		RemonteeKit.poutre(parent, c + o - v * (r + 0.55) - u * 0.08, c + o + v * (r + 0.55) - u * 0.08, 0.20, 0.28, m, ax)
		RemonteeKit.boite_en(parent, Vector3(0.42, 0.42, 0.42), c + o, m)
	RemonteeKit.poutre(parent, c - ax * 0.40 + u * (r + 0.15), c + ax * 0.40 + u * (r + 0.15), 0.14, 0.14, m, u)
	if y_sol < c.y - 0.5:
		for sv in [-1.0, 1.0]:
			var p: Vector3 = c + v * (sv * (r + 0.40)) - u * 0.08
			RemonteeKit.barre(parent, p, Vector3(p.x, y_sol, p.z), 0.16, m, 8)


## Chariot et bloc de contrepoids (aval), fosse et garde-corps ; moteurs
## et fosse de la motrice (amont). `g` : nœud de la gare (repère de la gare).
func equipements(g: Node3D, aval: bool) -> void:
	var y0: float = g.position.y
	var f: Array = fosse(aval)
	var x0: float = f[0]
	var x1: float = f[1]
	var z0: float = f[2]
	var z1: float = f[3]
	var prof: float = (PROF_FOSSE + 3.5) if aval else (PROF_MOTRICE + 2.0 * R_MOTRICE + 1.0)
	# parois de béton de la fosse, fond
	var cx: float = (x0 + x1) * 0.5
	var cz: float = (z0 + z1) * 0.5
	var lx: float = x1 - x0
	var lz: float = z1 - z0
	var yp: float = y_plancher(aval) - y0
	for s in [-1.0, 1.0]:
		RemonteeKit.boite_en(g, Vector3(0.3, prof, lz), Vector3(cx + s * lx * 0.5, yp - prof * 0.5, cz), "beton")
		RemonteeKit.boite_en(g, Vector3(lx, prof, 0.3), Vector3(cx, yp - prof * 0.5, cz + s * lz * 0.5), "beton")
	RemonteeKit.boite_en(g, Vector3(lx, 0.3, lz), Vector3(cx, yp - prof, cz), "beton")
	# garde-corps jaune autour de l'ouverture
	var coins: Array = [Vector3(x0, yp, z0), Vector3(x1, yp, z0), Vector3(x1, yp, z1), Vector3(x0, yp, z1)]
	for k in range(4):
		var a: Vector3 = coins[k]
		var b: Vector3 = coins[(k + 1) % 4]
		var nb: int = maxi(1, int(a.distance_to(b) / 1.5))
		for j in range(nb + 1):
			var p: Vector3 = a.lerp(b, float(j) / nb)
			RemonteeKit.barre(g, p, p + Vector3(0, 1.1, 0), 0.03, "jaune_securite", 6)
		RemonteeKit.barre(g, a + Vector3(0, 1.1, 0), b + Vector3(0, 1.1, 0), 0.035, "jaune_securite", 6)
		RemonteeKit.barre(g, a + Vector3(0, 0.55, 0), b + Vector3(0, 0.55, 0), 0.025, "jaune_securite", 6)
	var zc: float = _zc(aval)
	var sg: float = _sg(aval)
	var rp: float = lg.rayon_poulie()
	if aval:
		# chariot : poutre entre les axes des deux poulies, flasques, bloc pendu
		var zr: float = zc + sg * RECUL
		var yb: float = y_plancher(true) - PROF_FOSSE - y0
		var ya: float = yb + R_CHARIOT            # axes des poulies du chariot
		var xa: float = rp - R_CHARIOT
		for s in [-1.0, 1.0]:
			RemonteeKit.boite_en(g, Vector3(2.0 * xa + 0.6, 0.35, 0.18), Vector3(0, ya, zr + s * 0.45), "peinture_anthracite")
			for sx in [-1.0, 1.0]:
				RemonteeKit.poutre(g, Vector3(sx * xa, ya, zr + s * 0.45), Vector3(sx * 0.9, yb - 1.6, zr + s * 0.45), 0.16, 0.12, "peinture_anthracite")
		RemonteeKit.boite_en(g, Vector3(2.6, 2.2, 1.6), Vector3(0, yb - 2.6, zr), "beton")
		var lab: MeshInstance3D = RemonteeKit.texte_fige(g, "CONTREPOIDS", 48, 0.004, Color(0.1, 0.1, 0.1))
		lab.position = Vector3(0, yb - 2.4, zr - sg * 0.81)
		lab.rotation.y = 0.0 if sg < 0.0 else PI
		return
	# amont : à côté de la motrice, palier, poulie de frein jaune à chaîne, disque rouge, réducteur et moteurs
	# bleus ; freins bleus sur bâti rouge de l'autre côté. Simple : c'est la salle des machines.
	var zw: float = zc + sg * RECUL
	var yw: float = y_motrice() - y0
	var tr: Basis = Basis(Vector3.RIGHT, PI * 0.5)
	RemonteeKit.cylindre(g, 0.95, 0.95, 0.42, Transform3D(tr, Vector3(0, yw, zw + sg * 0.75)), "jaune_securite", 24)
	RemonteeKit.cylindre(g, 0.70, 0.40, 0.42, Transform3D(tr, Vector3(0, yw, zw + sg * 1.15)), "cabine_rouge", 20)
	RemonteeKit.boite_en(g, Vector3(2.1, 1.9, 1.3), Vector3(0, yw - 0.3, zw + sg * 2.05), BLEU)
	for sx in [-1.0, 1.0]:
		RemonteeKit.cylindre(g, 0.45, 0.45, 1.3, Transform3D(tr, Vector3(sx * 0.6, yw + 0.1, zw + sg * 2.75)), BLEU, 16)
		# freins sur la jante
		RemonteeKit.boite_en(g, Vector3(0.5, 0.35, 0.45), Vector3(sx * (R_MOTRICE * 0.72), yw - R_MOTRICE * 0.72, zw - sg * 0.40), BLEU)
		RemonteeKit.boite_en(g, Vector3(0.9, 0.2, 0.9), Vector3(sx * (R_MOTRICE * 0.72), yw - R_MOTRICE * 0.72 - 0.25, zw - sg * 0.40), "cabine_rouge")
	var lab2: MeshInstance3D = RemonteeKit.texte_fige(g, "MOTRICE  2 × 785 kW", 48, 0.004, Color(0.95, 0.95, 0.95))
	lab2.position = Vector3(0, yw - 1.4, zw + sg * 1.36)
	lab2.rotation.y = 0.0 if sg < 0.0 else PI


# --- quais ------------------------------------------------------------------------------

## Quais au niveau du plancher des cabines, de part et d'autre de leur
## chemin (tranchée) : îlot à l'intérieur du demi-tour, bande extérieure
## jusqu'aux murs. Triangles dans le repère de la ligne (aussi pour la collision).
func quais(aval: bool) -> PackedVector3Array:
	var tri: PackedVector3Array = PackedVector3Array()
	var y: float = y_plancher(aval) + H_QUAI
	var s0: float = lg.s_gare(aval, 0.0)
	var l: float = lg.longueur_zone(aval)
	var interieur: PackedVector2Array = PackedVector2Array()
	var hx: float = lg._emprise_3s(aval)[0] - 0.4
	var zc: float = _zc(aval)
	var sg: float = _sg(aval)
	var ext_prec: Array = []
	# quai seulement le long de la partie lente, autour du demi-tour (vidéos :
	# il commence après le freinage et s'arrête avant le lanceur ; plancher
	# bas le long des lanceurs, côté ligne)
	var xa: float = LigneRemontee.L_FREIN - 2.0
	var xb: float = l - LigneRemontee.L_FREIN + 2.0
	var x: float = xa
	while x <= xb + 0.01:
		var s: float = s0 + x
		var p: Vector3 = lg._point_cable(s)[0]
		var o: Vector3 = lg._dehors(s)
		var pi: Vector3 = p - o * DEMI_TRANCHEE
		interieur.append(Vector2(pi.x, pi.z))
		var a: Vector3 = p + o * DEMI_TRANCHEE
		# vers le mur sur les côtés droits, 4 m au fond du demi-tour
		var b: Vector3
		if (p.z - zc) * sg < 0.0:
			b = Vector3(signf(p.x) * hx, 0, p.z)
		else:
			b = p + o * (DEMI_TRANCHEE + 4.0)
		var e: Array = [Vector3(a.x, y, a.z), Vector3(b.x, y, b.z)]
		if not ext_prec.is_empty():
			tri.append_array(PackedVector3Array([ext_prec[0], e[0], e[1], ext_prec[0], e[1], ext_prec[1]]))
		ext_prec = e
		x += 0.5
	var idx: PackedInt32Array = Geometry2D.triangulate_polygon(interieur)
	for k in range(0, idx.size(), 3):
		for j in range(3):
			var q: Vector2 = interieur[idx[k + j]]
			tri.append(Vector3(q.x, y, q.y))
	return tri


## Maillage des quais (béton clair, bordure jaune) dans le repère de la gare g.
func maillage_quais(g: Node3D, aval: bool) -> void:
	var tri: PackedVector3Array = quais(aval)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(0, tri.size(), 3):
		var a: Vector3 = tri[k] - Vector3(0, g.position.y, 0)
		var b: Vector3 = tri[k + 1] - Vector3(0, g.position.y, 0)
		var c: Vector3 = tri[k + 2] - Vector3(0, g.position.y, 0)
		var ordre: Array = [a, b, c] if (b - a).cross(c - a).y < 0.0 else [a, c, b]
		for v in ordre:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Quais"
	mi.mesh = MeshMerge.valider(st)
	var m: StandardMaterial3D = (RemonteeKit.mat("beton") as StandardMaterial3D).duplicate()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	g.add_child(mi)
	# nez de quai jaune le long de la tranchée, des deux côtés
	var s0: float = lg.s_gare(aval, 0.0)
	var l: float = lg.longueur_zone(aval)
	var yq: float = y_plancher(aval) + H_QUAI - g.position.y
	for sgn in [-1.0, 1.0]:
		var pts: PackedVector3Array = PackedVector3Array()
		var x: float = 0.0
		while x <= l + 0.01:
			var p: Vector3 = lg._point_cable(s0 + x)[0] + lg._dehors(s0 + x) * (sgn * DEMI_TRANCHEE)
			pts.append(Vector3(p.x, yq - 0.12, p.z))
			x += 0.5
		pts = pts.slice(int((LigneRemontee.L_FREIN - 2.0) / 0.5), int((l - LigneRemontee.L_FREIN + 2.0) / 0.5) + 1)
		RemonteeKit.tube(g, pts, 0.13, "jaune_securite", 4)
